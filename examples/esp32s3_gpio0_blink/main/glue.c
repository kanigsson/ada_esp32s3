/* gpio0_blink example-specific native.  All bare-boot (core bring-up, env entry,
   the L5 tick, clock, etc.) is shared in ../../common/bare/bare_glue.c. */
extern int esp_rom_printf(const char *fmt, ...);

/* Console echo of the GPIO0 level (the Ada driver in src/gpio.adb does the
   register work and imports this as "native_gpio_log"). */
void native_gpio_log(int level)
{
    esp_rom_printf("[gpio0] %s\n", level ? "HIGH" : "low ");
}
