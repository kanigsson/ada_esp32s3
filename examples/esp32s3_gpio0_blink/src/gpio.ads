package GPIO is
   pragma Elaborate_Body;
   --  GPIO0 blink demo.  A library-level task configures GPIO0 as a push-pull
   --  output and toggles it at ~2 Hz (a 250 ms half-period square wave on the
   --  pad), printing each transition over the USB-Serial-JTAG console.  It drives
   --  the pin through the shared, reusable HAL (ESP32S3.GPIO, in
   --  libs/esp32s3_hal) rather than poking registers directly -- the
   --  template for using the driver library on top of the Ada runtime.
end GPIO;
