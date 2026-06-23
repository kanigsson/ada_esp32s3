/* esp32s3_tx1812 console helpers.  Shared bare-boot in ../../common/bare. */
extern int esp_rom_printf(const char *fmt, ...);

void native_led_banner(void)
{
    esp_rom_printf("[led] TX1812 addressable RGB LED on IO48, driven by RMT\n");
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
