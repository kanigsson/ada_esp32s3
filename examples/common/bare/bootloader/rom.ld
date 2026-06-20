/* ESP32-S3 mask-ROM symbols the minimal bootloader calls (no ESP-IDF needed).
 * Addresses from ESP-IDF v5.4.4 components/esp_rom/esp32s3/ld/esp32s3.rom*.ld. */
PROVIDE ( esp_rom_printf              = 0x400005d0 );   /* = ets_printf            */
PROVIDE ( esp_rom_spiflash_read       = 0x40000a20 );   /* direct SPI flash read   */
PROVIDE ( Cache_Disable_ICache        = 0x4000186c );
PROVIDE ( Cache_Enable_ICache         = 0x40001878 );
PROVIDE ( Cache_Disable_DCache        = 0x40001884 );
PROVIDE ( Cache_Enable_DCache         = 0x40001890 );
PROVIDE ( Cache_Ibus_MMU_Set          = 0x400019a4 );   /* map flash IROM (i-bus)  */
PROVIDE ( Cache_Dbus_MMU_Set          = 0x400019b0 );   /* map flash DROM (d-bus)  */
PROVIDE ( Cache_Invalidate_ICache_All = 0x400016d4 );
PROVIDE ( rom_config_data_cache_mode  = 0x40001a28 );   /* (held in reserve)       */
/* Octal-PSRAM bring-up (Stage 1.2): the ROM helpers the vendored esp_psram_impl_octal
 * / mspi_timing objects call, + the cache d-bus MMU mapper for the PSRAM region. */
PROVIDE ( Cache_Resume_DCache         = 0x400018c0 );
PROVIDE ( esp_rom_opiflash_exec_cmd   = 0x400008b8 );
PROVIDE ( esp_rom_opiflash_pin_config = 0x40000894 );   /* octal MSPI pin config (D4-7/DQS) */
PROVIDE ( esp_rom_opiflash_read_raw   = 0x4004d9d4 );
PROVIDE ( esp_rom_spi_set_dtr_swap_mode = 0x4000093c );
PROVIDE ( rom_spiflash_legacy_data    = 0x3fceffe4 );

