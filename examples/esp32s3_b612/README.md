# B612 font on an ST7789 display — bare-metal Ada (ESP32-S3)

Renders the **B612** typeface (Airbus's cockpit font, SIL OFL 1.1) on a 240×240
ST7789 panel, anti-aliased, at three sizes, with a reusable proportional-font
renderer.

```
[b612] anti-aliased B612 font: 12/16/24 px -> ST7789 240x240
[b612]   12px      5498 bytes
[b612]   16px      9093 bytes
[b612]   24px     19486 bytes
```

## Anti-aliasing on a write-only panel

Coverage is **4-bit (16-level)**, 2 px/byte. Each glyph pixel's coverage indexes
a 16-entry **bg→fg colour ramp** built once per string, so anti-aliasing is done
by blending against the *known* background — no framebuffer read-back, which the
panel doesn't support. Spacing is proportional (per-glyph advance).

## Pay only for the sizes you use

Each size is fully independent:

- its glyph data is a separate C header (`main/b612_<sz>.h`) compiled into its
  own `.rodata.b612_<sz>_*` linker section (`-fdata-sections`);
- it has its own one-line Ada package (`src/b612_<sz>.ads`) exposing a
  `Glyph_Fonts.Font` constant.

So a program links a size's bytes **only if** it both `#include`s that header in
`glue.c` *and* `with`s that package. Need only 16 px? `#include "b612_16.h"` and
`with B612_16;` — 12/24 px are never compiled in (0 bytes). **This demo includes
all three** to show them together; trim the `#include`s in `glue.c` and the
`with`s in `main.adb` for a real build.

## The renderer — `Glyph_Fonts`

One font-agnostic renderer serves every size. A `Font` is a light descriptor
that points (by address) at the atlas arrays plus `First / Count / Height /
Ascent`. `Draw_Text (S, Font, X, Baseline, Str, FG, BG)` blits each glyph with
`ESP32S3.ST7789.Draw_Bitmap`, advancing the pen by each glyph's metric;
`Text_Width` measures a string. (Productising this would move `Glyph_Fonts` into
the HAL alongside the existing 5×7 `ESP32S3.ST7789.Text`.)

## Glyphs

Printable **Latin-1** (`0x20..0xFF`, 191 glyphs) — the full set addressable from
an Ada `String`. The font also has ~400 codepoints above `0xFF` (Latin
Extended, etc.); reaching those would need UTF-8 input + a cmap lookup (future).

## Regenerating the atlases

```sh
./main/gen_b612.py        # B612-Regular.ttf -> b612_<sz>.h + src/b612_<sz>.ads
```

Re-run only when the sizes/range/font change; the committed headers and Ada
packages are the build inputs. Needs Pillow (with FreeType). `B612-Regular.ttf`
and `OFL.txt` are vendored under `main/`. (To add a size, append it to `SIZES`.)

## Licensing

B612 is **SIL Open Font License 1.1** (`main/OFL.txt`) — free to embed and
redistribute; the derived bitmap atlas is a permitted use.

## Build / flash / run

```sh
./x build b612            # -> app.bin (embedded profile)
./x flash b612 -p /dev/ttyACM0
./x run   b612 -p /dev/ttyACM0
```
