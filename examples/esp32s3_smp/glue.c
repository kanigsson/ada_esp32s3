/* esp32s3_smp example-specific natives.  All bare-boot (core bring-up,
   env entry, the L5 tick, clock, etc.) is shared in ../../common/bare/bare_glue.c. */
extern int esp_rom_printf(const char *fmt, ...);

/* One line per cross-core transfer (printed only by the consumer, so the two
   cores' output never interleaves). */
void native_log_xfer(int value, int from_core, int to_core)
{
    esp_rom_printf("value %2d:  producer core %d  -->  consumer core %d\n",
                   value, from_core, to_core);
}

/* Per-period count of completed consumer entry calls (~1 == the entry blocks
   correctly; a flood would mean it busy-returns). */
void native_log_rate(int gets, int posted)
{
    esp_rom_printf("[rate] posted %d:  consumer entry Get completed %d time(s)"
                   " this period\n", posted, gets);
}
