; main.s - lsdj-album front end (DMG): screen, visualizer, controls
; Copyright (C) 2026  Mario 64 (github.com/M64GitHub)
; SPDX-License-Identifier: GPL-2.0-or-later
; Part of lsdj-album: https://github.com/M64GitHub/lsdj-album
;
; Screen: logo, current song name + number, a scrolling waveform and four
; LED meters (PU1 PU2 WAV NOI). The meters follow what the player really
; writes to the sound chip (VizOnWrite in player.s): note triggers set the
; volume, LSDj's soft-envelope writes are modelled like the DMG does ("zombie
; mode"), and hardware envelopes are stepped here. WAV shows NR32's level.
; The waveform shows the combined level (square-root scaled), with a little
; randomness so it looks like audio.
;
; Controls: A = next song, B = previous song. Songs advance by themselves.
;
; Timing: the music runs from the timer interrupt (360 Hz). The UI renders
; into WRAM buffers and copies one buffer per VBlank (waveform and meters
; alternate, so each updates at 30 Hz).

INCLUDE "gfx_const.inc"

; --- hardware registers ---
DEF rP1   EQU $FF00
DEF rTIMA EQU $FF05
DEF rTMA  EQU $FF06
DEF rTAC  EQU $FF07
DEF rIF   EQU $FF0F
DEF rLCDC EQU $FF40
DEF rLY   EQU $FF44
DEF rBGP  EQU $FF47
DEF rIE   EQU $FFFF
DEF SCRN  EQU $9800

; --- screen layout (tiles) ---
DEF LOGO_ROW  EQU 0
DEF LOGO_COL  EQU (20 - LOGO_W) / 2
DEF NAME_ROW  EQU 8
DEF NAME_COL  EQU 1
DEF NAME_LEN  EQU 18            ; 8 name + 5 blank + "NN/MM"
DEF WAVE_ROW  EQU 9             ; 4 rows: outer-up, inner-up, inner-down, outer-down
DEF WAVE_COL  EQU 1
DEF WAVE_W    EQU 18            ; tiles, 2 samples each
DEF WAVE_N    EQU WAVE_W * 2    ; samples of history
DEF METER_ROW EQU 14            ; 4 rows: PU1 PU2 WAV NOI
DEF LABEL_COL EQU 1
DEF METER_COL EQU 4
DEF SEGS      EQU 15            ; one segment per volume step

DEF NUM_SONGS EQUS "((SongLocationsEnd - SongLocations) / 4)"

    ASSERT (SongNamesEnd - SongNames) / 8 == NUM_SONGS, \
        "song name count differs from recorded song count"

SECTION "vblank_vector", ROM0[$40]
    jp  VBlankISR

SECTION "timer_vector", ROM0[$50]
    jp  TimerISR

SECTION "header", ROM0[$100]
    nop
    jp  Start
    ds  $150 - @, 0             ; filled by rgbfix

SECTION "main", ROM0

Start:
    di
    ld  sp,$E000

    ; LCD may only be switched off during VBlank
.wait_vblank
    ldh a,[rLY]
    cp  144
    jr  c,.wait_vblank
    xor a
    ldh [rLCDC],a

    ; zero UI state and the player's viz shadow
    ld  hl,VarsStart
    ld  bc,VarsEnd - VarsStart
    xor a
    call MemFill
    ld  hl,VizRegs
    ld  bc,VizNewNote + 4 - VizRegs
    xor a
    call MemFill

    ; tiles, empty map, logo, meter labels
    ld  hl,$8000
    ld  de,GfxTiles
    ld  bc,GfxTilesEnd - GfxTiles
    call MemCopy
    ld  hl,SCRN
    ld  bc,32 * 32
    ld  a,TILE_BLACK
    call MemFill

    ld  de,LogoMap
    ld  hl,SCRN + LOGO_ROW * 32 + LOGO_COL
    ld  b,LOGO_H
.logo_row
    ld  c,LOGO_W
.logo_col
    ld  a,[de]
    inc de
    ld  [hl+],a
    dec c
    jr  nz,.logo_col
    push de
    ld  de,32 - LOGO_W
    add hl,de
    pop de
    dec b
    jr  nz,.logo_row

    ld  de,Labels
    ld  hl,SCRN + METER_ROW * 32 + LABEL_COL
    ld  b,4
.label_row
    REPT 3
        ld  a,[de]
        inc de
        ld  [hl+],a
    ENDR
    push de
    ld  de,32 - 3
    add hl,de
    pop de
    dec b
    jr  nz,.label_row

    ; flat waveform, dark meters
    ld  hl,WaveHist
    ld  bc,WAVE_N
    ld  a,1
    call MemFill
    call RenderWave
    call RenderMeters
    call CopyWave
    call CopyMeters

    ; first song
    ld  a,$FF
    ld  [ShownSong],a
    xor a
    call LsdjPlaySong
    call CheckSongChange
    call CopyName
    xor a
    ld  [NameDirty],a

    ld  a,$5A
    ld  [Seed],a
    ld  a,%11100100             ; 3 = black ... 0 = white
    ldh [rBGP],a

    ; music timer: 65536 Hz / 182 = 360.1 Hz (LSDj 9.x on DMG ticks at 360.2 Hz)
    ld  a,256 - 182
    ldh [rTMA],a
    ldh [rTIMA],a
    ld  a,%110                  ; timer on, 65536 Hz
    ldh [rTAC],a

    ld  a,%10010001             ; LCD on, BG tiles at $8000, BG on
    ldh [rLCDC],a
    xor a
    ldh [rIF],a
    ld  a,%101                  ; VBlank + timer interrupts
    ldh [rIE],a
    ei

MainLoop:
    halt
    ldh a,[hVBlank]
    and a
    jr  z,MainLoop
    xor a
    ldh [hVBlank],a

    call VBlankCopy             ; first: we are at the start of VBlank
    call ReadInput
    call CheckSongChange
    call UpdateLevels

    ld  a,[Frame]
    inc a
    ld  [Frame],a
    and 1
    jr  nz,.meters
    call PushWave
    call RenderWave
    ld  a,1
    ld  [WaveDirty],a
    jr  MainLoop
.meters
    call RenderMeters
    ld  a,1
    ld  [MetersDirty],a
    jr  MainLoop

; ---------------------------------------------------------------------------
; Interrupts

VBlankISR:
    push af
    ld  a,1
    ldh [hVBlank],a
    pop af
    reti

TimerISR:
    push af
    call LsdjTick
    pop af
    reti

; ---------------------------------------------------------------------------
; VRAM updates (one buffer per VBlank)

VBlankCopy:
    ldh a,[rLY]
    cp  144
    ret c                       ; VBlank already over: skip this frame
    cp  149
    ret nc                      ; too little VBlank left for a full copy
    ld  a,[NameDirty]
    and a
    jr  z,.not_name
    xor a
    ld  [NameDirty],a
    di
    call CopyName
    ei
    ret
.not_name
    ld  a,[WaveDirty]
    and a
    jr  z,.not_wave
    xor a
    ld  [WaveDirty],a
    di
    call CopyWave
    ei
    ret
.not_wave
    ld  a,[MetersDirty]
    and a
    ret z
    xor a
    ld  [MetersDirty],a
    di
    call CopyMeters
    ei
    ret

CopyWave:
    ld  hl,WaveBuf
    FOR ROW, 4
        ld  de,SCRN + (WAVE_ROW + ROW) * 32 + WAVE_COL
        REPT WAVE_W
            ld  a,[hl+]
            ld  [de],a
            inc e
        ENDR
    ENDR
    ret

CopyMeters:
    ld  hl,MeterBuf
    FOR ROW, 4
        ld  de,SCRN + (METER_ROW + ROW) * 32 + METER_COL
        REPT SEGS
            ld  a,[hl+]
            ld  [de],a
            inc e
        ENDR
    ENDR
    ret

CopyName:
    ld  hl,NameBuf
    ld  de,SCRN + NAME_ROW * 32 + NAME_COL
    REPT NAME_LEN
        ld  a,[hl+]
        ld  [de],a
        inc e
    ENDR
    ret

; ---------------------------------------------------------------------------
; Input: A = next song, B = previous song

ReadInput:
    ld  a,$10                   ; select the action buttons
    ldh [rP1],a
    REPT 4
        ldh a,[rP1]             ; read a few times to let the lines settle
    ENDR
    cpl
    and $0F
    ld  b,a                     ; b = buttons held
    ld  a,$30
    ldh [rP1],a
    ld  a,[PrevKeys]
    cpl
    and b
    ld  c,a                     ; c = newly pressed
    ld  a,b
    ld  [PrevKeys],a

    bit 0,c
    jr  nz,.next
    bit 1,c
    ret z
    di
    ld  a,[Song]
    and a
    jr  nz,.prev
    ld  a,NUM_SONGS
.prev
    dec a
    jr  .play
.next
    di
    ld  a,[Song]
    inc a
    cp  NUM_SONGS
    jr  c,.play
    xor a
.play
    call LsdjPlaySong
    ei
    ret

; ---------------------------------------------------------------------------
; Song name line: "NAME8CHR     NN/MM", rebuilt when the song changes

CheckSongChange:
    ld  a,[Song]
    ld  b,a
    ld  a,[ShownSong]
    cp  b
    ret z
    ld  a,b
    ld  [ShownSong],a

    ld  l,b                     ; hl = SongNames + song * 8
    ld  h,0
    add hl,hl
    add hl,hl
    add hl,hl
    ld  de,SongNames
    add hl,de
    ld  de,NameBuf
    ld  c,8
.name
    ld  a,[hl+]
    ld  [de],a
    inc de
    dec c
    jr  nz,.name
    xor a
    REPT 5
        ld  [de],a
        inc de
    ENDR
    ld  a,b
    inc a
    call PutDec2
    ld  a,'/'
    ld  [de],a
    inc de
    ld  a,NUM_SONGS
    call PutDec2

    ld  a,1
    ld  [NameDirty],a
    ; new song: meters start from silence
    di
    xor a
    ld  hl,VizVol
    REPT 8                      ; VizVol + VizNewNote
        ld  [hl+],a
    ENDR
    ei
    ld  hl,ChanState
    ld  bc,ChanStateEnd - ChanState
    jp  MemFill

; a = 0..99 -> two digit tiles at [de], de += 2
PutDec2:
    ld  c,0
.tens
    cp  10
    jr  c,.ones
    sub 10
    inc c
    jr  .tens
.ones
    push af
    ld  a,c
    add FONT_0
    ld  [de],a
    inc de
    pop af
    add FONT_0
    ld  [de],a
    inc de
    ret

; ---------------------------------------------------------------------------
; Channel levels from the player's register shadow

; Hardware envelope of PU1/PU2/NOI: the player hook (VizOnWrite) sets the
; volume on note triggers and envelope writes; here we add the automatic
; steps, one every <pace> frames (hardware: every pace/64 s).
; \1 = channel slot, \2 = NRx2 register
MACRO ENV_STEP
    ld  a,[VizNewNote + \1]     ; new note: restart the envelope timer
    and a
    jr  z,.running\@
    xor a
    ld  [VizNewNote + \1],a
    ld  [EnvCnt + \1],a
.running\@:
    ld  a,[VizRegs + \2]
    and $07                     ; pace 0 = no automatic envelope
    jr  z,.done\@
    ld  b,a
    ld  a,[EnvCnt + \1]
    inc a
    cp  b
    jr  c,.store\@
    ld  a,[VizRegs + \2]
    bit 3,a                     ; direction: 1 = up
    ld  a,[VizVol + \1]
    jr  z,.down\@
    cp  15
    jr  z,.reset\@
    inc a
    jr  .set\@
.down\@:
    and a
    jr  z,.reset\@
    dec a
.set\@:
    ld  [VizVol + \1],a
.reset\@:
    xor a
.store\@:
    ld  [EnvCnt + \1],a
.done\@:
ENDM

; a = sample: b = min(b, a), c = max(c, a)
MACRO MINMAX
    cp  b
    jr  nc,.not_min\@
    ld  b,a
.not_min\@:
    cp  c
    jr  c,.not_max\@
    ld  c,a
.not_max\@:
ENDM

UpdateLevels:
    di                          ; VizVol/VizNewNote are shared with the player
    ENV_STEP 0, $12             ; PU1
    ENV_STEP 1, $17             ; PU2
    ENV_STEP 3, $21             ; NOI
    xor a
    ld  [VizNewNote + 2],a
    ld  a,[VizVol + 0]
    ld  [Vol + 0],a
    ld  a,[VizVol + 1]
    ld  [Vol + 1],a
    ld  a,[VizVol + 3]
    ld  [Vol + 3],a
    ei

    ; WAV: loudness = peak-to-peak of the 32 samples in wave RAM (synth
    ; waveform or the current drum-kit chunk), scaled by NR32's output level,
    ; while the DAC (NR30 bit 7) is on
    ld  a,[VizRegs + $1A]
    bit 7,a
    ld  a,0
    jr  z,.wav_set
    ld  a,[VizRegs + $1C]
    swap a
    rra
    and 3                       ; NR32 bits 6-5: 0 = mute, 1 = 100%, 2 = 50%, 3 = 25%
    jr  z,.wav_set
    push af
    ld  hl,VizRegs + $30
    ld  bc,$0F00                ; b = min, c = max
    ld  e,16
.wav_byte
    ld  a,[hl+]
    ld  d,a
    swap a
    and $0F
    MINMAX
    ld  a,d
    and $0F
    MINMAX
    dec e
    jr  nz,.wav_byte
    ld  a,c
    sub b                       ; 0..15
    jr  nc,.wav_amp
    xor a
.wav_amp
    ld  b,a
    pop af
    dec a                       ; shift right 0, 1 or 2 times
    ld  c,a
    ld  a,b
    jr  z,.wav_set
.wav_shift
    srl a
    dec c
    jr  nz,.wav_shift
.wav_set
    ld  [Vol + 2],a

    ; shown level: muted if sound is off (NR52) or the channel is panned nowhere (NR51)
    ld  a,[VizRegs + $26]
    bit 7,a
    ld  c,0
    jr  z,.pan
    ld  a,[VizRegs + $25]
    ld  c,a
.pan
    FOR CH, 4
        ld  a,c
        and $11 << CH
        jr  z,.mute\@           ; a = 0
        ld  a,[Vol + CH]
.mute\@:
        ld  [Disp + CH],a
    ENDR

    ; peak hold: jump up at once, hold ~2/3 s, then fall one step per 4 frames
    FOR CH, 4
        ld  a,[Disp + CH]
        ld  b,a
        ld  a,[Peak + CH]
        cp  b
        jr  z,.raise\@
        jr  nc,.fall\@
.raise\@:
        ld  a,b
        ld  [Peak + CH],a
        ld  a,40
        ld  [PeakHold + CH],a
        jr  .peak_done\@
.fall\@:
        ld  a,[PeakHold + CH]
        and a
        jr  z,.drop\@
        dec a
        ld  [PeakHold + CH],a
        jr  .peak_done\@
.drop\@:
        ld  a,[Peak + CH]
        dec a
        ld  [Peak + CH],a
        ld  a,3
        ld  [PeakHold + CH],a
.peak_done\@:
    ENDR
    ret

; ---------------------------------------------------------------------------
; Waveform: history of the combined level, newest on the right

PushWave:
    ld  a,[Disp + 0]
    ld  b,a
    ld  a,[Disp + 1]
    add b
    ld  b,a
    ld  a,[Disp + 2]
    add b
    ld  b,a
    ld  a,[Disp + 3]
    add b                       ; 0..60
    ld  hl,AmpTab               ; -> amplitude 0..8 in 2-pixel steps
    add l
    ld  l,a
    adc h
    sub l
    ld  h,a
    ld  a,[hl]
    ld  c,a                     ; texture: take off 0..amp/2 at random
    srl a
    ld  b,a
    call Random
    and 3
    cp  b
    jr  c,.tex_ok
    ld  a,b
.tex_ok
    ld  b,a
    ld  a,c
    sub b
    jr  nz,.nonzero
    inc a                       ; keep a thin line in silence
.nonzero
    ld  b,a

    ld  hl,WaveHist             ; scroll left by one sample
    ld  c,WAVE_N - 1
.shift
    inc hl
    ld  a,[hl-]
    ld  [hl+],a
    dec c
    jr  nz,.shift
    ld  [hl],b
    ret

; returns a pseudo-random a; preserves bc, de, hl
Random:
    push bc
    ld  a,[Seed]
    ld  b,a
    add a
    add a
    add b
    inc a                       ; seed * 5 + 1
    ld  [Seed],a
    swap a                      ; use the better high bits
    pop bc
    ret

; \1 = index table, \2 = up row, \3 = mirrored down row
MACRO WAVE_PASS
    ld  hl,WaveHist
    ld  de,WaveBuf + \2 * WAVE_W
    ld  c,WAVE_W
.col\@:
    ld  a,[hl+]                 ; left sample
    swap a
    ld  b,a
    ld  a,[hl+]                 ; right sample
    or  b
    push hl
    ld  l,a
    ld  h,HIGH(\1)
    ld  a,[hl]                  ; tile offset for this pair
    pop hl
    ld  b,a
    add WAVE_UP
    ld  [de],a
    push de
    ld  a,e
    add (\3 - \2) * WAVE_W
    ld  e,a
    jr  nc,.no_carry\@
    inc d
.no_carry\@:
    ld  a,b
    add WAVE_DN
    ld  [de],a
    pop de
    inc de
    dec c
    jr  nz,.col\@
ENDM

RenderWave:
    WAVE_PASS WaveOuterTab, 0, 3
    WAVE_PASS WaveInnerTab, 1, 2
    ret

; ---------------------------------------------------------------------------
; LED meters: lit up to the level, peak segment lighter

RenderMeters:
    ld  hl,MeterBuf
    FOR CH, 4
        ld  a,[Disp + CH]
        ld  b,a
        ld  a,[Peak + CH]
        ld  c,a
        ld  e,1
.seg\@:
        ld  a,b
        cp  e
        ld  a,SEG_ON
        jr  nc,.put\@           ; level >= segment
        ld  a,c
        cp  e
        ld  a,SEG_PEAK
        jr  z,.put\@
        ld  a,SEG_OFF
.put\@:
        ld  [hl+],a
        inc e
        ld  a,e
        cp  SEGS + 1
        jr  c,.seg\@
    ENDR
    ret

; ---------------------------------------------------------------------------
; Helpers

; copy bc bytes from de to hl
MemCopy:
    ld  a,[de]
    ld  [hl+],a
    inc de
    dec bc
    ld  a,b
    or  c
    jr  nz,MemCopy
    ret

; fill bc bytes at hl with a
MemFill:
    ld  d,a
.loop
    ld  a,d
    ld  [hl+],a
    dec bc
    ld  a,b
    or  c
    jr  nz,.loop
    ret

Labels:
    db  "PU1", "PU2", "WAV", "NOI"

AmpTab:                         ; combined level 0..60 -> round(sqrt(1.2 * level)), max 8
    db  0, 1, 2, 2, 2, 2, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 6, 6, 6, 6, 6
    db  6, 6, 6, 6, 6, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8

; Waveform tile offsets, indexed by (left << 4) | right with amplitudes 0..8
; (2-pixel steps, 16 pixels per half). Each tile pair holds 0..4 steps per
; 4-pixel column: "inner" rows touch the centre line, "outer" rows extend it.
SECTION "wave_tables", ROM0, ALIGN[8]
WaveInnerTab:
    FOR I, 256
        DEF TL = I >> 4
        DEF TR = I & 15
        IF TL > 4
            REDEF TL = 4
        ENDC
        IF TR > 4
            REDEF TR = 4
        ENDC
        db  TL * 5 + TR
    ENDR
WaveOuterTab:
    FOR I, 256
        DEF TL = (I >> 4) - 4
        DEF TR = (I & 15) - 4
        IF TL < 0
            REDEF TL = 0
        ENDC
        IF TR < 0
            REDEF TR = 0
        ENDC
        IF TL > 4
            REDEF TL = 4
        ENDC
        IF TR > 4
            REDEF TR = 4
        ENDC
        db  TL * 5 + TR
    ENDR

INCLUDE "gfx_data.inc"

; ---------------------------------------------------------------------------
; RAM

SECTION "ui_vars", WRAM0
VarsStart:
Frame:       ds 1
Seed:        ds 1
PrevKeys:    ds 1
ShownSong:   ds 1
NameDirty:   ds 1
WaveDirty:   ds 1
MetersDirty: ds 1
ChanState:                      ; per channel: PU1 PU2 WAV NOI
Vol:         ds 4
EnvCnt:      ds 4
Disp:        ds 4
Peak:        ds 4
PeakHold:    ds 4
ChanStateEnd:
NameBuf:     ds NAME_LEN
WaveHist:    ds WAVE_N
WaveBuf:     ds WAVE_W * 4
MeterBuf:    ds SEGS * 4
VarsEnd:

SECTION "hram", HRAM
hVBlank:     ds 1
