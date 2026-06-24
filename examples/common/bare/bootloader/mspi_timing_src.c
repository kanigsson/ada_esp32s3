/* From-source replacements for the vendored mspi_timing_*.c.obj + gpio_periph.c.obj
 * blobs.  These are the only symbols the kept esp_psram_impl_octal.c.obj imports
 * from those four objects:
 *   GPIO_PIN_MUX_REG, mspi_timing_set_pin_drive_strength,
 *   mspi_timing_enter_low_speed_mode, mspi_timing_enter_high_speed_mode,
 *   mspi_timing_psram_tuning.
 *
 * Everything here is a fixed register sequence reproducing the exact state the
 * blobs left on a working board (captured live over JTAG -- see
 * PSRAM_BRINGUP_RESEARCH.md).  The MSPI din "tuning" is a proven no-op (it never
 * varies the cache din), so it is dropped: the correct cache din (mode 1) is
 * applied directly.
 *
 * MMIO map (ESP32-S3): SPI0/cache base 0x60003000, SPI1 base 0x60002000.
 */
#include <stdint.h>

#define REG(a) (*(volatile uint32_t *)(uintptr_t)(a))

/* --- SPI0 (cache controller) registers used by the MSPI clock/din config --- */
#define SPI0_FLASH_CLK   0x60003014u   /* SPI_MEM_CLOCK_REG(0)        : core/flash divider */
#define SPI1_FLASH_CLK   0x60002014u   /* SPI_MEM_CLOCK_REG(1)                              */
#define SPI0_SRAM_CLK    0x60003050u   /* SPI_MEM_SRAM_CLK_REG(0)     : PSRAM divider       */
/* Single MSPI core-clock select (both set_flash_clock and set_psram_clock write
 * the same 0x600030EC); 0=80 MHz, 2=160 MHz core. */
#define SPI0_CORE_CLK    0x600030ECu   /* SPI_MEM_CORE_CLK_SEL_REG(0) */
#define SPI0_SMEM_DIN_MODE  0x600030C0u
#define SPI0_SMEM_DIN_NUM   0x600030C4u
#define SPI0_SMEM_TIMING_CALI 0x600030BCu  /* TIMING_CALI + EXTRA_DUMMY_CYCLELEN */
#define SPI0_MEM_DATE    0x600033FCu   /* SPI_MEM_DATE_REG(0) : SMEM SPICLK drive */

/* Clock divider words = (N<<16)|(H<<8)|L with N=L=freqdiv-1, H=freqdiv/2-1
 * (exactly as the blob's set_flash/psram_clock computes):
 *   div 4 (core 80 / 20 MHz, low speed)  -> (3<<16)|(1<<8)|3 = 0x00030103
 *   div 2 (core 160 / 80 MHz, high speed)-> (1<<16)|(0<<8)|1 = 0x00010001  */
#define CLK_DIV4  0x00030103u
#define CLK_DIV2  0x00010001u

/* Working cache din state, measured: din_mode=1, din_num=0, extra_dummy=2. */
#define DIN_MODE_1   0x01249249u
#define TIMING_CALI_2 0x0000000Bu   /* TIMING_CLK_ENA|TIMING_CALI|EXTRA_DUMMY=2 */

/* GPIO -> IO_MUX register table (linear on the S3: IO_MUX_GPIOn = 0x60009004 + 4n).
 * esp_psram_impl_octal indexes this with the PSRAM CS pin (GPIO26 -> 0x6000906c). */
const uint32_t GPIO_PIN_MUX_REG[49] = {
#define M(n) (0x60009004u + 4u * (n))
    M(0),  M(1),  M(2),  M(3),  M(4),  M(5),  M(6),  M(7),  M(8),  M(9),
    M(10), M(11), M(12), M(13), M(14), M(15), M(16), M(17), M(18), M(19),
    M(20), M(21), M(22), M(23), M(24), M(25), M(26), M(27), M(28), M(29),
    M(30), M(31), M(32), M(33), M(34), M(35), M(36), M(37), M(38), M(39),
    M(40), M(41), M(42), M(43), M(44), M(45), M(46), M(47), M(48)
#undef M
};

/* The octal MSPI data/DQS pins whose pad drive strength the blob bumps to 3
 * (FUN_DRV = bits[11:10]); from the blob's pin table. */
static const uint32_t k_mspi_drive_pins[9] = {
    0x60009070u, 0x60009074u,               /* GPIO27, GPIO28 */
    0x60009080u, 0x60009084u, 0x60009088u,  /* GPIO31, GPIO32, GPIO33 */
    0x6000908Cu, 0x60009090u, 0x60009094u, 0x60009098u  /* GPIO34..37 */
};

void mspi_timing_set_pin_drive_strength(void)
{
    unsigned i;
    /* SMEM SPICLK pad drive (matches the working state). */
    REG(SPI0_MEM_DATE) = 0x0210105Fu;
    /* FUN_DRV = 3 on the octal data/DQS pads. */
    for (i = 0; i < 9; i++)
        REG(k_mspi_drive_pins[i]) =
            (REG(k_mspi_drive_pins[i]) & ~(3u << 10)) | (3u << 10);
}

/* Low speed: 80 MHz core, flash+PSRAM at /4 (20 MHz) for the MR transactions;
 * clear the din tuning regs.  (control_both arg ignored -- we always set both.) */
void mspi_timing_enter_low_speed_mode(int control_both)
{
    (void) control_both;
    REG(SPI0_CORE_CLK)  = (REG(SPI0_CORE_CLK) & ~3u) | 0u;   /* core 80 MHz */
    REG(SPI0_FLASH_CLK) = CLK_DIV4;
    REG(SPI1_FLASH_CLK) = CLK_DIV4;
    REG(SPI0_SRAM_CLK)  = CLK_DIV4;
    REG(SPI0_SMEM_DIN_MODE)   = 0;
    REG(SPI0_SMEM_DIN_NUM)    = 0;
    REG(SPI0_SMEM_TIMING_CALI) = 0;
}

/* High speed: 160 MHz core, flash+PSRAM at /2 (80 MHz); apply the measured din. */
void mspi_timing_enter_high_speed_mode(int control_both)
{
    (void) control_both;
    REG(SPI0_CORE_CLK)  = (REG(SPI0_CORE_CLK) & ~3u) | 2u;   /* core 160 MHz */
    REG(SPI0_FLASH_CLK) = CLK_DIV2;
    REG(SPI1_FLASH_CLK) = CLK_DIV2;
    REG(SPI0_SRAM_CLK)  = CLK_DIV2;
    REG(SPI0_SMEM_TIMING_CALI) = TIMING_CALI_2;
    REG(SPI0_SMEM_DIN_MODE)    = DIN_MODE_1;
    REG(SPI0_SMEM_DIN_NUM)     = 0;
}

/* The blob's din sweep is a proven no-op on the S3 cache path (it never varies
 * the din it claims to test); the correct din is applied above.  So: nothing. */
void mspi_timing_psram_tuning(void) { }
