/* esp32s3_mcpwm_pwm example-specific console helpers.  All bare-boot is shared in
   ../../common/bare/bare_glue.c.  The self-test report uses the ROM
   USB-Serial-JTAG printf; the Ada driver does the register work and imports
   these as "native_mcpwm_*". */
extern int esp_rom_printf(const char *fmt, ...);

void native_mcpwm_banner(void)
{
    esp_rom_printf("[mcpwm] bare-metal MCPWM PWM-output self-test "
                   "(GPIO-sampled, no wiring)\n");
}

/* One measured channel: configured duty %, GPIO-measured duty (x10, so 253 =
   25.3%), measured frequency in Hz, and the pass/fail verdict. */
void native_mcpwm_result(int set_pct, int meas_pct_x10, int meas_hz, int ok)
{
    esp_rom_printf("[mcpwm] duty set=%d%%  measured=%d.%d%%  freq=%d Hz  %s\n",
                   set_pct, meas_pct_x10 / 10, meas_pct_x10 % 10, meas_hz,
                   ok ? "PASS" : "FAIL");
}

/* Complementary pair + dead-time: A and B duty (x10), and the fraction of time
   BOTH were high (x10) -- which must be ~0 because the dead-time keeps them from
   ever overlapping. */
void native_mcpwm_pair(int duty_a_x10, int duty_b_x10, int overlap_x10, int ok)
{
    esp_rom_printf("[mcpwm] pair: A=%d.%d%%  B=%d.%d%%  overlap=%d.%d%%  %s\n",
                   duty_a_x10 / 10, duty_a_x10 % 10, duty_b_x10 / 10, duty_b_x10 % 10,
                   overlap_x10 / 10, overlap_x10 % 10, ok ? "PASS" : "FAIL");
}

/* Capture submodule: the channel-0 output, fed back into a capture input,
   measured precisely (period/high in 80 MHz ticks -> freq + duty). */
void native_mcpwm_capture(int freq_hz, int duty_x10, int ok)
{
    esp_rom_printf("[mcpwm] capture: freq=%d Hz  duty=%d.%d%%  %s\n",
                   freq_hz, duty_x10 / 10, duty_x10 % 10, ok ? "PASS" : "FAIL");
}

/* Fault / trip-zone: output duty while running, while the fault is asserted
   (forced low -> ~0), and after clearing it (resumed). */
void native_mcpwm_fault(int run_pct, int fault_pct, int resume_pct, int ok)
{
    esp_rom_printf("[mcpwm] fault: run=%d%%  tripped=%d%%  resumed=%d%%  %s\n",
                   run_pct, fault_pct, resume_pct, ok ? "PASS" : "FAIL");
}

/* Carrier (chopper): output duty at 100%% PWM with the carrier off (constant
   high) vs on (chopped to the carrier's own duty). */
void native_mcpwm_carrier(int off_pct, int on_pct, int ok)
{
    esp_rom_printf("[mcpwm] carrier: off=%d%%  on=%d%%  %s\n",
                   off_pct, on_pct, ok ? "PASS" : "FAIL");
}

void native_mcpwm_done(void) { esp_rom_printf("[mcpwm] done.\n"); }
