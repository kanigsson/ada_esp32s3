/* esp32s3_gps_display example data glue.  Bare-boot is shared in
   ../../common/bare/bare_glue.c.  Console output now goes through ESP32S3.Log
   (the panel is the real output; the console mirrors each row over serial). */

/* 240x240 RGB565 Ada-mascot splash; the symbol ada_logo_rgb565 is imported by
   Ada (src/ada_logo.ads) and blitted at startup via ESP32S3.ST7789.Draw_Bitmap. */
#include "ada_logo.h"
