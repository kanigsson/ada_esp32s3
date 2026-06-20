/* esp32s3_i2s_pdm example-specific console helpers.  All bare-boot is shared in
   ../../common/bare/bare_glue.c.  The Ada driver does the I2S/PDM register work
   and imports these as "native_pdm_*". */
extern int esp_rom_printf(const char *fmt, ...);

void native_pdm_banner(void)
{
    esp_rom_printf("[i2s-pdm] bare-metal I2S PDM microphone capture demo (needs an external PDM mic)\n");
}

void native_pdm_hint(int clk, int dat)
{
    esp_rom_printf("[i2s-pdm] wire a PDM mic: CLK <- GPIO%d   DATA -> GPIO%d   (plus VDD/GND)\n", clk, dat);
    esp_rom_printf("[i2s-pdm] with no mic the data line floats -- expect railed/quiet; speak/tap to see the level rise\n");
}

void native_pdm_block(int idx, int mn, int mx, int pp, int signal)
{
    const char *tag = signal ? "<-- signal present"
                    : (mn <= -32000 || mx >= 32000) ? "(railed -- no mic?)"
                    : "(quiet)";
    esp_rom_printf("[i2s-pdm] block %d: min=%d max=%d peak-to-peak=%d %s\n",
                   idx, mn, mx, pp, tag);
}

void native_pdm_done(void) { esp_rom_printf("[i2s-pdm] capture done.\n"); }
