/* esp32s3_uart_loopback example-specific console helpers.  All bare-boot is
   shared in ../../common/bare/bare_glue.c.  The self-test report uses the ROM
   USB-Serial-JTAG printf (the reliable console path for these bare examples);
   the Ada driver does the register work and imports these as "native_uart_*". */
extern int esp_rom_printf(const char *fmt, ...);

void native_uart_banner(void)
{
    esp_rom_printf("[uart] bare-metal UART self-test "
                   "(internal TX->RX loopback, no wiring)\n");
}

/* Start a labelled byte line.  kind: 0 = sent, 1 = recv. */
void native_uart_line(int kind)
{
    esp_rom_printf("[uart] %s:", kind ? "recv" : "sent");
}

void native_uart_hex(int v) { esp_rom_printf(" %02x", v & 0xff); }
void native_uart_eol(void)  { esp_rom_printf("\n"); }

void native_uart_verdict(int ok)
{
    esp_rom_printf("[uart] loopback: %s\n", ok ? "PASS" : "FAIL");
}

/* RTS/CTS hardware-flow-control result: how much the RX FIFO was throttled to
   (capped, well below total = flow control engaged) and whether all bytes then
   drained back intact. */
void native_uart_flow(int capped, int total, int ok)
{
    esp_rom_printf("[uart] flow: RX throttled to %d of %d bytes, all drained: %s\n",
                   capped, total, ok ? "PASS" : "FAIL");
}

/* Line-inversion result (Set_Inversion called AFTER Configure_Pins): inverting
   only TX flips the line polarity the non-inverted RX expects, so the link
   breaks; inverting TX+RX makes both ends agree and the bytes match again. */
void native_uart_invert(int tx_only_broke, int tx_rx_matched, int ok)
{
    esp_rom_printf("[uart] invert: TX-only->link-breaks:%s  TX+RX->match:%s  %s\n",
                   tx_only_broke ? "y" : "n", tx_rx_matched ? "y" : "n",
                   ok ? "PASS" : "FAIL");
}

void native_uart_done(void) { esp_rom_printf("[uart] done.\n"); }
