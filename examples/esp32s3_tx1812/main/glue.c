/* esp32s3_tx1812 console helpers.  Shared bare-boot in ../../common/bare. */
extern int esp_rom_printf(const char *fmt, ...);

void native_led_banner(void)
{
    esp_rom_printf("[led] TX1812 string of 64 LEDs on IO48 via RMT "
                   "(wrap-streamed; on-board LED = pixel 1)\n");
}

void native_led_acquired(int ok)
{
    esp_rom_printf("[led] acquire RMT TX channel: %s\n",
                   ok ? "OK" : "FAILED (channel busy?)");
}

void native_led_color(int idx)
{
    static const char *names[] = {"red", "green", "blue", "white", "off"};
    esp_rom_printf("[led] %s\n",
                   (idx >= 0 && idx < 5) ? names[idx] : "?");
}
