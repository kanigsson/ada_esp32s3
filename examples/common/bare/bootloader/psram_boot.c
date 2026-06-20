/* Octal-PSRAM bring-up, kept in C because it drives the vendored IDF blobs
 * (esp_psram_impl_octal / mspi_timing).  Called once from the Ada loader
 * (boot_main.adb) as psram_bringup(), after the flash cache is up. */
#include <stdint.h>
#include "board_config.h"   /* generated from config/board.ads: BOARD_PSRAM_PAGES */

extern int  esp_rom_printf(const char *fmt, ...);
extern void esp_rom_opiflash_pin_config(void);
extern void mspi_timing_set_pin_drive_strength(void);
extern int  esp_psram_impl_enable(void);
extern int  esp_psram_impl_get_physical_size(uint32_t *out);
extern void Cache_Disable_DCache(void);
extern void Cache_Enable_DCache(uint32_t autoload);
extern int  Cache_Dbus_MMU_Set(uint32_t ext_ram, uint32_t vaddr, uint32_t paddr,
                               uint32_t psize, uint32_t num, uint32_t fixed);

#define REG(a) (*(volatile uint32_t *)(uintptr_t)(a))

void psram_bringup(void);
void psram_bringup(void)
{
    /* FIX 1 (= the IDF's esp_mspi_pin_init): configure the OCTAL MSPI pins
       SPID4-7 + DQS the ROM flash setup leaves unwired, + the pin drive.  Without
       them the OPI mode-register read has only 4 of 8 data lines -> a corrupted
       read (density 0x5/16MB vs the real 0x3/8MB) -> a mis-configured chip. */
    esp_rom_opiflash_pin_config();
    mspi_timing_set_pin_drive_strength();

    int prc = esp_psram_impl_enable();
    uint32_t psz = 0;
    esp_psram_impl_get_physical_size(&psz);
    esp_rom_printf("[ada-free-boot] octal PSRAM up: rc=%d  %u MB\n", prc, psz >> 20);

    Cache_Disable_DCache();
    /* FIX 2: our psram-tuning leaves din SMEM_MODE=0x04924924 (mode 4) but the SPI0
       cache OPI-DDR read only completes with the IDF's mode 1; force it. */
    REG(0x600030C0u) = 0x01249249u;
    /* map BOARD_PSRAM_PAGES x 64 KB of PSRAM @0x3D000000 (size from board.ads) */
    int mrc = Cache_Dbus_MMU_Set(0x8000u, 0x3D000000u, 0, 64, BOARD_PSRAM_PAGES, 0);
    Cache_Enable_DCache(0);
    esp_rom_printf("[ada-free-boot] PSRAM mapped @0x3D000000 rc=%d\n", mrc);
}
