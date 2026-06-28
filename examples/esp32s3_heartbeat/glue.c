/* esp32s3_heartbeat example-specific native.  All bare-boot (core bring-up, env
   entry, the L5 tick, clock, etc.) is shared in ../../common/bare/bare_glue.c. */
extern int esp_rom_printf(const char *fmt, ...);

/* The env task logs a 1 Hz heartbeat count (Ada import "ada_log" in
   src/example.adb). */
void ada_log(int n)
{
    esp_rom_printf("[example] heartbeat %d\n", n);
}
