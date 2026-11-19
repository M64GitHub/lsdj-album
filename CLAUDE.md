# lsdj-album — notes for Claude

LSDj save → Game Boy album ROM (DMG, MBC5) with logo, song names and a visualizer.
Assembly for RGBDS 1.0, helper scripts in Python 3 (stdlib only), lsdpack as a submodule.
User-facing docs: README.md. License GPL-2.0-or-later (player.s derives from lsdpack).

## Build and test

    make                      # needs SAVE (config.mk has the owner's settings)
    make clean && make        # after changing SKIP / ONLY / LENGTH
    make gbshot && make demo  # headless: docs/screenshot.png + docs/demo.gif

Always look at a change before reporting it: run the ROM headless with gbshot and read
the PNGs (or a contact sheet), and check that the audio level is non-zero:

    tools/gbshot/gbshot X.gb OUT 1300 120,600,1260 A:300 B:600
    python3 -I tools/gbshot/montage.py OUT/sheet.png 3 OUT/f00120.png ...

`rgbasm -Wall` must stay warning-free. Never commit LSDj ROMs, saves, built ROMs or
`docs/` pictures made from someone's work-in-progress songs.

## Architecture

- `lsdpack -d -t` (Makefile) records on an emulated DMG with one tick per timer interrupt;
  LSDj 9.x ticks at 360.2 Hz there. Without `-t` recordings have zero ticks.
- `player.s`: lsdpack's player + `VizOnWrite` hooks + auto-advance (`.handle_song_stop`).
  `LsdjTick` runs in the timer ISR (`main.s`, TMA 256-182 = 360.1 Hz) and switches ROM
  banks, so ALL code and data the UI touches must be in ROM0.
- `main.s`: init (LCD off) → main loop on VBlank flag: `VBlankCopy` (one buffer per frame:
  name > wave > meters, under `di`, only if LY is 144..148), input, song change, levels,
  then render wave (even frames) or meters (odd frames) into WRAM buffers.
- Generated: `gen/gfx_*.inc` (tools/mkgfx.py: logo + font + 50 wave tiles + 3 meter
  tiles, ≤ 256 tiles), `work/NAME/names.asm` (tools/mknames.py, needs the charmap in
  gfx_const.inc), `work/NAME/songs.s` (lsdpack).

## Invariants (break these and things fail silently)

- `VizRegs` is 256-byte aligned and indexed by register low byte ($10-$3F); `VizNewNote`
  must directly follow `VizVol` (VizOnWrite adds 4).
- `VizOnWrite` preserves bc, de, hl: sample_start/next keep NR25 in e, LsdjTick keeps the
  last command byte in b and the stream pointer in hl.
- UI reads/writes of `VizVol`/`VizNewNote` happen under `di` (shared with the ISR).
- Song count is link-time: `NUM_SONGS` = (SongLocationsEnd − SongLocations) / 4, and an
  ASSERT checks it equals the number of names (8 bytes each).
- VRAM copies use `inc e` within a row: rows must not cross a 256-byte page (true for the
  current layout; re-check if rows/columns move).
- RGBDS names: avoid `L`, `R`, `Dec`… (register/instruction clashes); character literals
  are `'x'`, strings in numeric context are deprecated.

## LSDj facts learned the hard way

- LSDj 9.3.9 soft envelopes are raw NRx2 writes using DMG zombie mode: `09,11,18` = −1,
  `08` = +1 (lsdpack's AMP_DEC rule does not catch them with `-d`). VizOnWrite applies the
  zombie rules: old pace 0 → +1, else old dir down → +2; dir flip → 16−v; & 15.
- lsdpack's emulator writes the .sav back on exit → the Makefile always works on copies.
- Bumping the lsdpack submodule rebuilds lsdpack and re-records the songs (songs.s depends on
  the binary, the binary on lsdpack's sources). Verify recordings per song, not just song 1:
  lsdpack once dropped song 2's first NR10 write (register state carried across songs).
- LSDj 9.x command ids are alphabetical incl. B: H = 8 (not 7 as in older docs/libs).
  `tools/lsdj_song_info.py` finds HFF in phrases and tables with that.
- LSDj file names can contain `x` (lowercase) — the font has it.
