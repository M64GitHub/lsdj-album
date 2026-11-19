; lsdpack - standalone LSDj (Little Sound Dj) recorder + player {{{
; Copyright (C) 2018  Johan Kotlinski
; https://www.littlesounddj.com
;
; This program is free software; you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation; either version 2 of the License, or
; (at your option) any later version.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License along
; with this program; if not, write to the Free Software Foundation, Inc.,
; 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA. }}}

if __RGBDS_MAJOR__ != 1
    warn "Unknown RGBDS version {__RGBDS_VERSION__}! this lsdpack copy was ported to RGBDS 1.0"
endc

; ---------------------------------------------------------------------------
; Modified 2026 for lsdj-album (github.com/M64GitHub/lsdj-album) by Mario 64:
; visualizer hooks (marked "viz") and auto-advance to the next song when a
; song ends. Hooks only record what the
; player writes (VizOnWrite, end of file); they never change the sound.
; ---------------------------------------------------------------------------

; viz: report the value in a, just written to sound register \1
MACRO VIZ
    ld  c,\1
    call VizOnWrite
ENDM

; viz: LSDj soft-envelope step "volume - 1" (writes 9, $11, $18 to NRx2 \1)
MACRO VIZ_AMP_DEC
    ld  c,\1
    ld  a,9
    call VizOnWrite
    ld  a,$11
    call VizOnWrite
    ld  a,$18
    call VizOnWrite
ENDM

SECTION "player",ROM0     ; lsdpack: ROM0[$3d00] for .gbs; not needed for a ROM
    ; .gbs player entry points
    ret
    jp LsdjPlaySong
    jp LsdjTick


; Starts playing a song. If a song is already playing,
; make sure interrupts are disabled when calling this.
;
; IN: a = song number
; OUT: -
; SIDE EFFECTS: trashes af
;
LsdjPlaySong::
    push    de
    push    hl

    ld  [Song],a

    ld  hl,SongLocations
    add a,a
    add a,a
    add a,l
    ld  l,a

    ld  de,CurrentBank
    ld  a,[hl+]
    ld  [de],a  ; CurrentBank
    inc de
    ld  a,[hl+]
    ld  [de],a  ; CurrentBank + 1
    inc de
    ld  a,[hl+]
    ld  [de],a  ; CurrentPtr
    inc de
    ld  a,[hl+]
    ld  [de],a  ; CurrentPtr + 1

    xor a
    ldh [$FF26],a ; stop sound
    ld  [RepeatCmdCounter],a

    pop hl
    pop de
    ret

DEF CMD_END_TICK        = 0
DEF CMD_SAMPLE_START    = 1
DEF CMD_SONG_STOP       = 2
DEF CMD_NEXT_BANK       = 3
DEF CMD_AMP_DEC_PU0     = 4
DEF CMD_AMP_DEC_PU1     = 5
DEF CMD_AMP_DEC_NOI     = 6
DEF CMD_PITCH_PU0       = 7
DEF CMD_PITCH_PU1       = 8
DEF CMD_PITCH_WAV       = 9
DEF CMD_SAMPLE_NEXT     = 10

; Call this six times per screen update,
; evenly spread out over the screen.
;
; IN: -
; OUT: -
; SIDE EFFECTS: changes ROM bank, trashes af
;
LsdjTick::
    push    hl
    push    bc

.tick
    ld  a,[CurrentBank+1]
    ld  [$3000],a
    ld  a,[CurrentBank]
    ld  [$2000],a
    ld  a,[CurrentPtr+1] ; hl = ptr
    ld  h,a
    ld  a,[CurrentPtr]
    ld  l,a

    xor a
    ld  b,a ; b = last read command byte

.loop
    bit 7,b
    jr  nz,.lyc_done

    ; load repeated cmd
    ld  a,[RepeatCmdCounter]
    or  a
    jr  z,.load_new_cmd_from_stream
    dec a
    ld  [RepeatCmdCounter],a
    ld  a,[RepeatCmd]
    jr  .apply_cmd

.load_new_cmd_from_stream
    ld  a,[hl+]
    bit 6,a
    jr  z,.apply_cmd

    ; save repeated cmd
    and ~$40
    ld  [RepeatCmd],a
    ld  b,a
    ld  a,[hl+]
    ld  [RepeatCmdCounter],a
    ld  a,b

.apply_cmd
    ld  b,a
    and $3f
    jr  z,.lyc_done
    cp  10
    jp  z,.sample_next
    jr  c,.is_command

    ; write sound register
    ld  c,a
    ld  a,[hl+]
    ldh [c],a
    call VizOnWrite     ; viz
    jr  .loop

.is_command
    cp  CMD_SAMPLE_START
    jp  z,.sample_start
    cp  CMD_AMP_DEC_PU0
    jp  z,.amp_dec_pu0
    cp  CMD_AMP_DEC_PU1
    jp  z,.amp_dec_pu1
    cp  CMD_AMP_DEC_NOI
    jp  z,.amp_dec_noi
    cp  CMD_PITCH_PU0
    jp  z,.pitch_pu0
    cp  CMD_PITCH_PU1
    jp  z,.pitch_pu1
    cp  CMD_PITCH_WAV
    jp  z,.pitch_wav
    cp  CMD_NEXT_BANK
    jp  z,.next_bank
    cp  CMD_SONG_STOP
    jp  z,.handle_song_stop

.lyc_done
    ld  a,l
    ld  [CurrentPtr],a
    ld  a,h
    ld  [CurrentPtr+1],a
    pop bc
    pop hl
    ret

.handle_song_stop:
    ; lsdj-album: go on to the next song (wrapping) instead of repeating
    ld  a,[Song]
    inc a
    cp  (SongLocationsEnd - SongLocations) / 4
    jr  c,.next_song_ok
    xor a
.next_song_ok:
    call    LsdjPlaySong
    jp  .tick

.amp_dec_pu0:
    ld  a,9
    ldh [$FF12],a
    ld  a,$11
    ldh [$FF12],a
    ld  a,$18
    ldh [$FF12],a
    VIZ_AMP_DEC $12
    jp  .loop

.amp_dec_pu1:
    ld  a,9
    ldh [$FF17],a
    ld  a,$11
    ldh [$FF17],a
    ld  a,$18
    ldh [$FF17],a
    VIZ_AMP_DEC $17
    jp  .loop

.amp_dec_noi:
    ld  a,9
    ldh [$FF21],a
    ld  a,$11
    ldh [$FF21],a
    ld  a,$18
    ldh [$FF21],a
    VIZ_AMP_DEC $21
    jp  .loop

.pitch_pu0:
    ld  a,[hl+]
    ldh [$FF13],a
    VIZ $13
    ld  a,[hl+]
    ldh [$FF14],a
    VIZ $14
    jp  .loop

.pitch_pu1:
    ld  a,[hl+]
    ldh [$FF18],a
    VIZ $18
    ld  a,[hl+]
    ldh [$FF19],a
    VIZ $19
    jp  .loop

.pitch_wav:
    ld  a,[hl+]
    ldh [$FF1D],a
    VIZ $1D
    ld  a,[hl+]
    ldh [$FF1E],a
    VIZ $1E
    jp  .loop

.next_bank:
    ld  a,$40
    ld  h,a
    xor a
    ld  l,a

    ld  a,[CurrentBank]
    inc a
    ld  [CurrentBank],a
    ld  [$2000],a
    jp  nz,.loop
    ld  a,[CurrentBank+1]
    inc a
    ld  [CurrentBank+1],a
    ld  [$3000],a
    ; Reapply LSB in case of non-MBC5 cartridge.
    ld  [CurrentBank],a
    ld  [$2000],a
    jp  .loop

.sample_start:
    push    de
    ld  a,[hl+]
    ld  c,a     ; c = sample bank
    ld  [SampleBank],a
    ld  a,[hl+]
    ld  e,a
    ld  a,[hl+]
    ld  d,a     ; de = sample ptr

    push    hl
    ; switch bank
    xor a
    ld  [$3000],a
    ld  a,c
    ld  [$2000],a

    ld  h,d
    ld  l,e

    ; disable wave channel output
    ldh a,[$FF25]
    ld  e,a
    and a,~$44
    ldh [$FF25],a

    xor a
    ldh [$FF1A],a ; mute channel

    FOR N, 16           ; copy the wave chunk; viz: keep a copy for the UI
        ld  a,[hl+]
        ldh [$FF30 + N],a
        ld  [VizRegs + $30 + N],a
    ENDR

    ld  a,l
    ld  [SampleAddress],a
    ld  a,h
    ld  [SampleAddress+1],a

    ld  a,$80 ; unmute
    ldh [$FF1A],a
    VIZ $1A

    pop     hl

    ld  a,[CurrentBank+1]
    ld  [$3000],a
    ld  a,[CurrentBank]
    ld  [$2000],a

    ld  a,[hl+]
    ldh [$FF1E],a
    ld  [SamplePitchMsb],a
    VIZ $1E
    ld  a,[hl+]
    ldh [$FF1D],a

    ld  a,e
    ldh [$FF25],a

    pop de
    jp  .loop

.sample_next:
    push    de
    ld  a,[SampleBank]
    ld  c,a     ; c = sample bank
    ld  a,[SampleAddress]
    ld  e,a
    ld  a,[SampleAddress+1]
    ld  d,a     ; de = sample ptr

    push    hl
    ; switch bank
    xor a
    ld  [$3000],a
    ld  a,c
    ld  [$2000],a

    ld  h,d
    ld  l,e

    ; disable wave channel output
    ldh a,[$FF25]
    ld  e,a
    and a,~$44
    ldh [$FF25],a

    xor a
    ldh [$FF1A],a ; mute channel

    FOR N, 16           ; copy the wave chunk; viz: keep a copy for the UI
        ld  a,[hl+]
        ldh [$FF30 + N],a
        ld  [VizRegs + $30 + N],a
    ENDR

    ld  a,$80 ; unmute
    ldh [$FF1A],a
    VIZ $1A

    ld  a,[SamplePitchMsb]
    ldh [$FF1E],a
    VIZ $1E

    ld  a,e
    ldh [$FF25],a

    ld  a,[CurrentBank+1]
    ld  [$3000],a
    ld  a,[CurrentBank]
    ld  [$2000],a

    ld  a,l
    ld  [SampleAddress],a
    ld  a,h
    ld  [SampleAddress+1],a

    pop hl
    pop de
    jp  .loop


SECTION "viz_hooks",ROM0

; viz: record one sound register write. Runs inside LsdjTick (interrupts off).
;   VizRegs[reg]   last value written (indexed by register low byte)
;   VizVol[ch]     current volume 0-15 of PU1, PU2, WAV(unused), NOI:
;                  note trigger -> initial volume from NRx2; NRx2 writes while
;                  playing -> DMG "zombie mode" (how LSDj does soft envelopes)
;   VizNewNote[ch] set on note trigger; the UI clears it
; IN: c = register ($10-$3F), a = value. Preserves bc, de, hl.
VizOnWrite::
    push hl
    push de
    ld  h,HIGH(VizRegs)
    ld  l,c
    ld  e,[hl]          ; e = old value
    ld  [hl],a
    ld  d,a             ; d = new value
    ld  a,c
    ld  hl,VizVol
    cp  $12
    jr  z,.env
    cp  $14
    jr  z,.trig
    inc hl
    cp  $17
    jr  z,.env
    cp  $19
    jr  z,.trig
    inc hl
    cp  $1E
    jr  z,.trig_wav
    inc hl
    cp  $21
    jr  z,.env
    cp  $23
    jr  z,.trig
.done
    pop de
    pop hl
    ret

.trig_wav
    bit 7,d
    jr  z,.done
    jr  .new_note
.trig                   ; NRx4 with bit 7: note starts at NRx2's volume
    bit 7,d
    jr  z,.done
    push hl
    ld  h,HIGH(VizRegs)
    ld  a,c
    sub 2               ; NRx2 = NRx4 - 2
    ld  l,a
    ld  a,[hl]
    pop hl
    ld  e,a
    and $F8
    jr  z,.trig_vol     ; DAC off: silent (a = 0)
    ld  a,e
    swap a
    and $0F
.trig_vol
    ld  [hl],a
.new_note
    ld  de,VizNewNote - VizVol
    add hl,de
    ld  [hl],1
    jr  .done

.env                    ; NRx2 write while playing (DMG zombie mode)
    ld  a,d
    and $F8
    jr  nz,.dac_on
    ld  [hl],a          ; DAC off: silent
    jr  .done
.dac_on
    ld  a,e
    and $07
    ld  a,[hl]
    jr  nz,.old_pace
    inc a               ; old pace 0: volume + 1
    jr  .dir
.old_pace
    bit 3,e
    jr  nz,.dir
    add 2               ; old direction down: volume + 2
.dir
    push af
    ld  a,e
    xor d
    bit 3,a
    jr  z,.same_dir
    pop af              ; direction flipped: volume = 16 - volume
    cpl
    inc a
    jr  .set_vol
.same_dir
    pop af
.set_vol
    and $0F
    ld  [hl],a
    jr  .done

SECTION "viz_regs",WRAM0,ALIGN[8]

VizRegs::           ; [$00-$3F], indexed by register low byte (must be 256-aligned)
    ds  $40
VizVol::            ; PU1 PU2 WAV NOI
    ds  4
VizNewNote::        ; must follow VizVol
    ds  4

SECTION "player_ram",WRAM0

Song::              ; exported: the UI shows the current song
    ds  1
CurrentBank:
    ds  2
CurrentPtr:
    ds  2
SampleBank:
    ds  1
SampleAddress:
    ds  2
SamplePitchMsb:
    ds  1
RepeatCmd:
    ds  1
RepeatCmdCounter:
    ds  1
