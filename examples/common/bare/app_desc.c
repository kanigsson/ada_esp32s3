/* Minimal esp_app_desc_t.  The vendored bootloader asserts that image segment #0
 * (the DROM segment) begins with this structure's magic word (0xABCD5432).
 * sections.ld KEEPs *(.rodata_desc) first in .flash.appdesc, at the start of the
 * DROM segment, so this lands exactly where the bootloader looks. */
#include <stdint.h>

typedef struct {
    uint32_t magic_word;
    uint32_t secure_version;
    uint32_t reserv1[2];
    char     version[32];
    char     project_name[32];
    char     time[16];
    char     date[16];
    char     idf_ver[32];
    uint8_t  app_elf_sha256[32];
    uint16_t min_efuse_blk_rev_full;
    uint16_t max_efuse_blk_rev_full;
    uint8_t  mmu_page_size;     /* 0 = chip default (64 KB) */
    uint8_t  reserv3[3];
    uint32_t reserv2[18];
} esp_app_desc_t;

__attribute__((section(".rodata_desc"), used))
const esp_app_desc_t esp_app_desc = {
    .magic_word   = 0xABCD5432,
    .version      = "noidf-spike",
    .project_name = "gpio0_blink",
    .idf_ver      = "v5.4.4",
};
