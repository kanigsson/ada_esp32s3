/* esp32s3_sd_spi console helpers.  Shared bare-boot in ../../common/bare. */
extern int esp_rom_printf(const char *fmt, ...);

static const char *kind_name(int k)
{
    switch (k) {        /* matches ESP32S3.SD_SPI.Card_Kind'Pos */
    case 0: return "Unknown";
    case 1: return "SD v1.x (SDSC)";
    case 2: return "SD v2 SDSC";
    case 3: return "SDHC/SDXC";
    default: return "?";
    }
}
static const char *status_name(int s)
{
    switch (s) {        /* matches ESP32S3.SD_SPI.Status'Pos */
    case 0: return "OK";
    case 1: return "No_Card";
    case 2: return "Unusable";
    case 3: return "Init_Timeout";
    case 4: return "Read_Error";
    case 5: return "Write_Error";
    default: return "?";
    }
}

void native_sd_banner(void)
{
    esp_rom_printf("[sd-spi] bare-metal SD-over-SPI self-test (needs a wired card)\n");
}
void native_sd_init(int status, int kind)
{
    esp_rom_printf("[sd-spi] init: %s   card: %s\n",
                   status_name(status), kind_name(kind));
}
void native_sd_read(int which, int status, int b0, int b1, int b2, int b3)
{
    esp_rom_printf("[sd-spi] read#%d: %s   first bytes = %02x %02x %02x %02x\n",
                   which, status_name(status), b0, b1, b2, b3);
}
void native_sd_write(int status)
{
    esp_rom_printf("[sd-spi] write-back: %s\n", status_name(status));
}
void native_sd_verify(int ok)
{
    esp_rom_printf("[sd-spi] round-trip (re-read == original): %s\n",
                   ok ? "PASS" : "FAIL");
}
void native_sd_done(void) { esp_rom_printf("[sd-spi] done.\n"); }
