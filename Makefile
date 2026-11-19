# lsdj-album: LSDj songs -> stand-alone Game Boy ROM with logo and visualizer
# SPDX-License-Identifier: GPL-2.0-or-later
#
#   make SAVE=path/to/lsdj         record all songs, build $(NAME).gb
#   make SAVE=... run              ...and open it (macOS: SameBoy)
#   make SAVE=... songs            list the songs in the save
#   make SAVE=... info SLOT=3      song structure + where its HFF commands are
#   make SAVE=... ONLY=3 LENGTH=240 NAME=song3   one song, cut after 240 s
#   make SAVE=... demo             docs/screenshot.png + docs/demo.gif (headless)
#   make clean
#
# SAVE is your LSDj ROM + save without extension: path/to/lsdj means
# path/to/lsdj.gb and path/to/lsdj.sav. Put your settings in config.mk
# (see config.mk.example) instead of typing them every time.
#
# Songs must end with an HFF command, or set LENGTH. Changing SKIP, ONLY or
# LENGTH needs `make clean` (or a different NAME).

-include config.mk

SAVE    ?=
SKIP    ?=
ONLY    ?=
LENGTH  ?=
NAME    ?= album
TITLE   ?= LSDJ ALBUM
LOGO    ?= assets/logo.png
LSDPACK ?= lsdpack

ifeq ($(strip $(SAVE)),)
  ifneq ($(filter-out clean lsdpack gbshot,$(or $(MAKECMDGOALS),all)),)
    $(error Set SAVE=path/to/lsdj (your LSDj ROM and save, without .gb/.sav), on the command line or in config.mk)
  endif
endif

ALL_SLOTS := $(shell seq 1 32)
ifneq ($(ONLY),)
  SKIP := $(filter-out $(ONLY),$(ALL_SLOTS))
endif
FLAGS   := -d -t $(if $(LENGTH),-l $(LENGTH))
W       := work/$(NAME)
GEN     := gen/gfx_const.inc gen/gfx_data.inc
LSDPACK_BIN := $(LSDPACK)/build/lsdpack
GBSHOT  := tools/gbshot/gbshot
GAMBATTE := $(LSDPACK)/libgambatte

all: $(NAME).gb

$(NAME).gb: $(W)/main.o $(W)/player.o $(W)/songs.o $(W)/names.o
	rgblink -o $@ -m $(NAME).map -n $(NAME).sym $^
	rgbfix -v -m 0x19 -p 0xFF -t "$(TITLE)" $@

# --- lsdpack (git submodule) ---
lsdpack: $(LSDPACK_BIN)
$(LSDPACK_BIN):
	@test -f $(LSDPACK)/CMakeLists.txt || { echo "lsdpack missing: run git submodule update --init"; exit 1; }
	cmake -S $(LSDPACK) -B $(LSDPACK)/build -DCMAKE_BUILD_TYPE=Release
	cmake --build $(LSDPACK)/build --target lsdpack

# --- graphics from the logo ---
$(GEN): $(LOGO) tools/mkgfx.py
	mkdir -p gen
	python3 -I tools/mkgfx.py "$(LOGO)" gen

# --- record the songs (on copies: lsdpack's emulator writes the .sav back) ---
$(W)/songs.s: $(SAVE).gb $(SAVE).sav tools/mknames.py tools/lsdj_drop.py | $(LSDPACK_BIN)
	rm -rf $(W) && mkdir -p $(W)
	cp "$(SAVE).gb" $(W)/songs.gb
	python3 -I tools/lsdj_drop.py "$(SAVE).sav" $(W)/songs.sav $(SKIP)
	python3 -I tools/mknames.py $(W)/songs.sav $(W)/names.asm
	cd $(W) && "$(abspath $(LSDPACK_BIN))" $(FLAGS) songs.gb

$(W)/songs.o: $(W)/songs.s
	rgbasm -o $@ $<
$(W)/names.o: $(W)/songs.s $(GEN)
	rgbasm -I gen -o $@ $(W)/names.asm
$(W)/player.o: player.s | $(W)/songs.s
	rgbasm -Wall -o $@ $<
$(W)/main.o: main.s $(GEN) | $(W)/songs.s
	rgbasm -Wall -I gen -o $@ $<

run: $(NAME).gb
	open -a SameBoy $(NAME).gb

songs:
	@python3 -I tools/lsdj_songs.py "$(SAVE).sav"

info:
	@python3 -I tools/lsdj_song_info.py "$(SAVE).sav" $(SLOT)

# --- headless test runner (Gambatte from the lsdpack submodule) ---
gbshot: $(GBSHOT)
$(GBSHOT): tools/gbshot/gbshot.cpp | $(LSDPACK_BIN)
	c++ -std=c++14 -O2 -w -DHAVE_STDINT_H -I$(GAMBATTE)/common -I$(GAMBATTE)/include \
	    -I$(GAMBATTE)/src -I$(GAMBATTE)/src/mem -o $@ $< $(wildcard $(GAMBATTE)/src/*.cpp) \
	    $(GAMBATTE)/src/file/file.cpp $(wildcard $(GAMBATTE)/src/mem/*.cpp) \
	    $(wildcard $(GAMBATTE)/src/sound/*.cpp) $(wildcard $(GAMBATTE)/src/video/*.cpp) -lz

# README pictures: one screenshot, and 4 s of animation (every 2nd frame, 30 fps)
DEMO_START := 600
DEMO_FRAMES := $(shell seq $(DEMO_START) 2 $$(($(DEMO_START) + 238)) | paste -sd, -)
demo: $(NAME).gb $(GBSHOT)
	rm -rf $(W)/shots && mkdir -p $(W)/shots docs
	$(GBSHOT) $(NAME).gb $(W)/shots $$(($(DEMO_START) + 240)) $(DEMO_FRAMES) > /dev/null
	cp $(W)/shots/f$$(printf %05d $(DEMO_START)).png docs/screenshot.png
	python3 -I tools/gbshot/gif.py docs/demo.gif 2 $(W)/shots/f*.png

clean:
	rm -rf work gen *.gb *.map *.sym

.PHONY: all lsdpack run songs info gbshot demo clean
