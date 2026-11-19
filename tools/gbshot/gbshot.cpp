// gbshot: run a Game Boy ROM headless (Gambatte, DMG mode), save screenshots, print audio level.
// Part of lsdj-album. Links the Gambatte core from the lsdpack submodule (GPL-2.0).
// SPDX-License-Identifier: GPL-2.0-or-later
// usage: gbshot rom.gb outdir total_frames shot1,shot2,... [BUTTON:frame ...]
//   e.g. gbshot x.gb out 1200 60,600 A:300 B:900   (button held for 6 frames)
#include "gambatte.h"
#include <zlib.h>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <sys/stat.h>
#include <string>
#include <vector>

unsigned g_tick_irq_address = 0;  // lsdpack hook: never matches an IRQ vector here
static void noop_write(char, char, unsigned long) {}
static void noop_lcd() {}

struct Pad : gambatte::InputGetter {
    unsigned state = 0;
    unsigned operator()() override { return state; }
};

static void put32(std::vector<unsigned char>& v, unsigned x) {
    for (int i = 3; i >= 0; --i) v.push_back((x >> (8 * i)) & 255);
}
static void chunk(FILE* f, const char* type, const std::vector<unsigned char>& data) {
    std::vector<unsigned char> c; put32(c, data.size());
    c.insert(c.end(), type, type + 4); c.insert(c.end(), data.begin(), data.end());
    unsigned crc = crc32(0, c.data() + 4, c.size() - 4); put32(c, crc);
    fwrite(c.data(), 1, c.size(), f);
}
static void write_png(const std::string& path, const gambatte::uint_least32_t* px, int scale) {
    int w = 160 * scale, h = 144 * scale;
    std::vector<unsigned char> raw;
    for (int y = 0; y < h; ++y) {
        raw.push_back(0);
        for (int x = 0; x < w; ++x) {
            unsigned p = px[(y / scale) * 160 + (x / scale)];
            raw.push_back((p >> 16) & 255); raw.push_back((p >> 8) & 255); raw.push_back(p & 255);
        }
    }
    uLongf n = compressBound(raw.size()); std::vector<unsigned char> z(n);
    compress(z.data(), &n, raw.data(), raw.size()); z.resize(n);
    FILE* f = fopen(path.c_str(), "wb");
    fwrite("\x89PNG\r\n\x1a\n", 1, 8, f);
    std::vector<unsigned char> ihdr; put32(ihdr, w); put32(ihdr, h);
    ihdr.insert(ihdr.end(), {8, 2, 0, 0, 0});
    chunk(f, "IHDR", ihdr); chunk(f, "IDAT", z); chunk(f, "IEND", {});
    fclose(f);
}

int main(int argc, char** argv) {
    if (argc < 5) { fputs("usage: gbshot rom.gb outdir total_frames shots [BTN:frame...]\n", stderr); return 1; }
    std::string outdir = argv[2];
    mkdir(outdir.c_str(), 0755);  // ok if it exists
    long total = atol(argv[3]);
    std::vector<long> shots;
    for (char* s = strtok(argv[4], ","); s; s = strtok(nullptr, ",")) shots.push_back(atol(s));
    struct Ev { unsigned btn; long frame; }; std::vector<Ev> evs;
    for (int i = 5; i < argc; ++i) {
        std::string a = argv[i]; size_t c = a.find(':');
        std::string b = a.substr(0, c); long fr = atol(a.c_str() + c + 1);
        unsigned m = b == "A" ? 1 : b == "B" ? 2 : b == "SELECT" ? 4 : b == "START" ? 8 :
                     b == "RIGHT" ? 16 : b == "LEFT" ? 32 : b == "UP" ? 64 : b == "DOWN" ? 128 : 0;
        evs.push_back({m, fr});
    }

    gambatte::GB gb; Pad pad;
    gb.setInputGetter(&pad); gb.setWriteHandler(noop_write); gb.setLcdHandler(noop_lcd);
    if (gb.load(argv[1], gambatte::GB::FORCE_DMG)) { fprintf(stderr, "load failed\n"); return 1; }
    const unsigned long pal[4] = {0xE0F8D0, 0x88C070, 0x346856, 0x081820};  // DMG-ish greens
    for (int i = 0; i < 4; ++i) gb.setDmgPaletteColor(0, i, pal[i]);

    std::vector<gambatte::uint_least32_t> video(160 * 144, 0), audio(35112 + 2064);
    long frame = 0; unsigned long long sampleClock = 0; size_t shotIdx = 0;
    double sum2 = 0; long cnt = 0; int second = 0; long lcdFrames = 0;
    while (frame < total) {
        pad.state = 0;
        for (auto& e : evs) if (frame >= e.frame && frame < e.frame + 6) pad.state |= e.btn;
        std::size_t samples = 35112;
        std::ptrdiff_t r = gb.runFor(video.data(), 160, audio.data(), samples);
        if (r >= 0) ++lcdFrames;
        const short* pcm = reinterpret_cast<const short*>(audio.data());
        for (size_t i = 0; i < samples; ++i) {
            double l = pcm[2 * i], rr = pcm[2 * i + 1];
            sum2 += (l * l + rr * rr) / 2; ++cnt;
        }
        sampleClock += samples;
        long newFrame = sampleClock / 35112;
        while (frame < newFrame) {
            ++frame;
            if (shotIdx < shots.size() && frame == shots[shotIdx]) {
                char name[64]; snprintf(name, sizeof name, "/f%05ld.png", frame);
                write_png(outdir + name, video.data(), 3); ++shotIdx;
            }
            if (frame % 60 == 0) {
                printf("t=%3ds  audio rms=%6.0f\n", ++second, std::sqrt(sum2 / (cnt ? cnt : 1)));
                sum2 = 0; cnt = 0;
            }
        }
    }
    printf("frames=%ld lcd_frames=%ld\n", frame, lcdFrames);
    return 0;
}
