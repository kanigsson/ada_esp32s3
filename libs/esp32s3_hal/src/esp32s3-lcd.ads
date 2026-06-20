with System;
with Ada.Finalization;
with ESP32S3.GPIO;

--  ESP32-S3 LCD (the LCD half of the LCD_CAM controller) -- 8-bit Intel-8080
--  parallel master, DMA-driven.
--
--  Drives an 8-bit "i80"/MCU parallel display (or any 8-bit parallel sink): a
--  byte buffer is streamed out the data bus, one byte per pixel clock (PCLK),
--  over the GDMA crossbar.  (The camera-receive half and the RGB/16-bit modes
--  are not covered here.)
--
--  The single controller is guarded by a protected object; Acquire hands out a
--  limited, controlled Session that owns it exclusively and releases on scope
--  exit.  Uses finalization, so it targets the embedded/full profile.
package ESP32S3.LCD is

   No_Pin : constant ESP32S3.GPIO.Pad_Number := ESP32S3.GPIO.No_Pin;

   --  The eight parallel data lines (D0 .. D7); any may be left unrouted.
   type Data_Pins is array (0 .. 7) of ESP32S3.GPIO.Optional_Pin;

   type Session is limited private;

   ----------------------------------------------------------------------------
   --  One-time configuration (single-threaded at startup).  This is the only
   --  port-based call; pin routing and clock-out are post-Setup and require the
   --  held controller (see below).
   ----------------------------------------------------------------------------

   --  Bring the LCD up in 8-bit mode at (about) Pclk_Hz pixel clock and Claim its
   --  GDMA channel.  Pixel clock = 20 MHz / round(20 MHz / Pclk_Hz).
   procedure Setup (Pclk_Hz : Positive := 1_000_000);

   ----------------------------------------------------------------------------
   --  Concurrent, mutually-exclusive use.  Acquire the controller, then run
   --  every transfer AND every post-Setup reconfiguration through it -- so
   --  changing a setting requires ownership and can never race another task.
   --  All register access lives in the private Engine child; the handle is
   --  hidden in the body and reached only through one ownership-checked gateway.
   ----------------------------------------------------------------------------

   --  Raised by Acquire if the controller was never Setup (or its GDMA channel
   --  could not be claimed) -- configuration must precede ownership.
   Not_Initialized : exception;

   --  Raised by any operation below if S does not hold the controller.  Each
   --  reaches the hardware only through the gateway, so "use it without holding
   --  it" fails loudly.
   Not_Owned : exception;

   --  Take exclusive ownership of the Setup controller (suspends until free).
   --  Raises Not_Initialized if Setup did not succeed.
   procedure Acquire (S : in out Session);

   --  Route the data bus and pixel clock to physical pads (for a real display),
   --  on the held controller.  Raises Not_Owned unless S holds it.
   procedure Configure_Pins (S : Session; Data : Data_Pins;
                             Pclk : ESP32S3.GPIO.Optional_Pin);

   --  Free-run the pixel clock continuously on Pclk_Pad (no data transaction) --
   --  useful as a bus clock and for verifying the clock on its own.  On the held
   --  controller; raises Not_Owned unless S holds it.
   procedure Enable_Clock_Out (S : Session; Pclk_Pad : ESP32S3.GPIO.Pin_Id);

   --  Stream Length bytes (1 .. 4095) from Tx out the data bus, one per PCLK.
   --  Blocking; Ok is True once the transfer completes.  Buffer in internal SRAM.
   --  Raises Not_Owned unless S holds the controller.
   procedure Transmit (S : Session; Tx : System.Address; Length : Natural;
                       Ok : out Boolean);

   procedure Release (S : in out Session);

private
   type Session is new Ada.Finalization.Limited_Controlled with record
      Active : Boolean := False;
   end record;
   overriding procedure Finalize (S : in out Session);
end ESP32S3.LCD;
