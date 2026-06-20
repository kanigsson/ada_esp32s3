with System;
with ESP32S3.GPIO;
with ESP32S3.GDMA;

--  RAW LCD_CAM (i80 parallel) register driver -- the ZFP-safe *mechanism* with
--  NO mutual exclusion.  PRIVATE child: only the ESP32S3.LCD subtree may use it;
--  the application reaches LCD only through the task-safe parent, which hides the
--  Bus handle and hands it out solely through its ownership-checked gateway.
--  This is the only unit that names the LCD_CAM registers and owns the GDMA
--  channel.
--
--  (Data_Pins is declared in the parent and used here by child visibility.)
private package ESP32S3.LCD.Engine is

   --  A configured controller: its claimed GDMA channel + a validity bit.
   --  Limited because it holds a limited-controlled GDMA Channel.
   type Bus is limited private;

   --  Bring the LCD up in 8-bit mode at (about) Pclk_Hz and Claim its GDMA
   --  channel.  Is_Valid is False if the channel could not be claimed.
   procedure Open (B : in out Bus; Pclk_Hz : Positive);
   function  Is_Valid (B : Bus) return Boolean;

   --  Route the data bus and pixel clock to physical pads.
   procedure Configure_Pins (B    : Bus;
                             Data : Data_Pins;
                             Pclk : ESP32S3.GPIO.Optional_Pin);

   --  Free-run the pixel clock continuously on Pclk_Pad (no data transaction).
   procedure Enable_Clock_Out (B : Bus; Pclk_Pad : ESP32S3.GPIO.Pin_Id);

   --  Stream Length bytes (1 .. 4095) from Tx out the data bus, one per PCLK.
   --  Ok is True once the transfer completes.
   procedure Transmit (B : Bus; Tx : System.Address; Length : Natural;
                       Ok : out Boolean);

private
   type Bus is limited record
      Chan  : ESP32S3.GDMA.Channel;    --  claimed by Open
      Valid : Boolean := False;
   end record;
end ESP32S3.LCD.Engine;
