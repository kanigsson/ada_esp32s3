/* esp32s3_sdmmc console helpers.  Shared bare-boot in ../../common/bare. */
extern int esp_rom_printf(const char *fmt, ...);

static const char *kind_name(int k)
{
    switch (k) {        /* ESP32S3.SDMMC.Card_Kind'Pos */
    case 0: return "Unknown";
    case 1: return "SDSC";
    case 2: return "SDHC/SDXC";
    default: return "?";
    }
}
static const char *status_name(int s)
{
    switch (s) {        /* ESP32S3.SDMMC.Status'Pos */
    case 0: return "OK";
    case 1: return "No_Card";
    case 2: return "Unusable";
    case 3: return "Init_Timeout";
    case 4: return "Cmd_Timeout";
    case 5: return "Cmd_CRC";
    case 6: return "Read_Error";
    case 7: return "Write_Error";
    default: return "?";
    }
}

void native_sdmmc_banner(void)
{
    esp_rom_printf("[sdmmc] bare-metal native SD/MMC-host self-test (needs a wired card)\n");
}
void native_sdmmc_init(int status, int kind, int width)
{
    esp_rom_printf("[sdmmc] init: %s   card: %s   bus: %d-bit\n",
                   status_name(status), kind_name(kind), width);
}
void native_sdmmc_read(int which, int status, int b0, int b1, int b2, int b3)
{
    esp_rom_printf("[sdmmc] read#%d: %s   first bytes = %02x %02x %02x %02x\n",
                   which, status_name(status), b0, b1, b2, b3);
}
void native_sdmmc_write(int status)
{
    esp_rom_printf("[sdmmc] write-back: %s\n", status_name(status));
}
void native_sdmmc_verify(int ok)
{
    esp_rom_printf("[sdmmc] round-trip (re-read == original): %s\n",
                   ok ? "PASS" : "FAIL");
}
void native_sdmmc_done(void) { esp_rom_printf("[sdmmc] done.\n"); }
