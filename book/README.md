# The book — *Bare-Metal Ada on the ESP32-S3*

A LaTeX book documenting this project: why Ada suits microcontrollers, how it
makes register and bit-field programming safe, the anatomy of an Ada application
from `Main` down to the boot ROM, the three runtime profiles, how to build and
run on the ESP32-S3, a guide to every peripheral driver (with worked examples),
and how to use the pure-Ada ext4 filesystem.

## Build

```sh
make            # -> main.pdf  (needs pdflatex; runs it twice for the ToC)
make clean
```

## Layout

| File | Chapters |
|------|----------|
| `main.tex` | preamble, title page, table of contents |
| `ch_foundations.tex` | Why Ada for microcontrollers; register addressing; bit fields |
| `ch_anatomy.tex` | Anatomy of an Ada application; the runtime profiles; building & running |
| `ch_hal.tex` | HAL conventions; GPIO, RNG, Temperature, SPI, I2C, UART |
| `ch_hal2.tex` | GDMA, MCPWM, I2S, LEDC, RMT, PCNT, SDM, TWAI, Timer, LCD, ADC |
| `ch_hal3.tex` | RTC, RTC-IO, Touch, SHA, AES |
| `ch_driver_design.tex` | How to write a task-safe driver (Engine / ownership gateway); why and benefits |
| `ch_storage.tex` | SD\_SPI, SDMMC, and the ext4 filesystem |
