--  Ada TWAI (CAN) self-test on the bare-metal ESP32-S3 (no FreeRTOS, no IDF)
--  ========================================================================
--  Exercises the reusable HAL TWAI driver (ESP32S3.TWAI): the controller is put
--  in self-test mode, where it can transmit a CAN frame and receive its own copy
--  with no second node to acknowledge it.  TX is looped back to RX through one
--  GPIO pad (the matrix loops out->in -- no wiring), so the whole send/receive
--  path runs on silicon.  We round-trip BOTH a standard (11-bit id) and an
--  extended (29-bit id) frame, using the overloaded Send/Receive and the
--  Available/Is_Extended peek to pick the right Receive each time.
with Interfaces;   use Interfaces;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.TWAI; use ESP32S3.TWAI;
with ESP32S3.GPIO;
with ESP32S3.Log;  use ESP32S3.Log;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   --  One self-rx result line.
   procedure Result (Extended, Remote, Got, Data_Ok, Ok : Boolean;
                     Id, Len : Unsigned_32) is
   begin
      Put ("[twai] ");
      Put (if Extended then "extended(29-bit)" else "standard(11-bit)");
      Put (" ");
      Put (if Remote then "remote(RTR)" else "data      ");
      Put (" self-rx: got=");
      Put (Boolean'Pos (Got));
      Put (" id=0x");
      Put_Hex (Id);
      Put (" len=");
      Put (Integer (Len));
      Put (" match=");
      Put (if Data_Ok then "y" else "n");
      Put ("  ");
      Put_Line (if Ok then "PASS" else "FAIL");
   end Result;

   Pad : constant ESP32S3.GPIO.Pin_Id := 4;     --  TX driven, RX read back

   Std : constant Standard_Frame :=
     (Id     => 16#123#,                         --  11-bit data frame
      Length => 5,
      Data   => (16#DE#, 16#AD#, 16#BE#, 16#EF#, 16#42#, 0, 0, 0),
      others => <>);
   Ext : constant Extended_Frame :=
     (Id     => 16#14AB_CDE#,                    --  29-bit data frame
      Length => 3,
      Data   => (16#01#, 16#02#, 16#03#, others => 0),
      others => <>);
   Rtr : constant Standard_Frame :=
     (Id     => 16#7A5#,                         --  11-bit remote request (RTR)
      Remote => True,                            --  requests 8 bytes, sends none
      Length => 8,
      others => <>);
   Ert : constant Extended_Frame :=
     (Id     => 16#1F1_2345#,                    --  29-bit remote request (RTR)
      Remote => True,
      Length => 6,
      others => <>);
begin
   delay until Clock + Milliseconds (200);
   Put_Line ("[twai] bare-metal TWAI (CAN) self-test loopback (no wiring)");

   Setup (Mode => Self_Test, Bit_Rate => 125_000);

   declare
      S    : Session;
      RS   : Standard_Frame;
      RE   : Extended_Frame;
      Got  : Boolean;
      D_Ok : Boolean;
   begin
      Acquire (S);
      Enable_Loopback (S, Pad);    --  loopback on the held controller

      --  Standard (11-bit) round-trip: Send picks the overload from Std's type.
      Send (S, Std);
      Got := Available (S) and then not Is_Extended (S);
      if Got then
         Receive (S, RS, Got);
      end if;
      D_Ok := Got and then not RS.Remote and then RS.Id = Std.Id
                and then RS.Length = Std.Length;
      if D_Ok then
         for I in 0 .. Std.Length - 1 loop
            D_Ok := D_Ok and then RS.Data (I) = Std.Data (I);
         end loop;
      end if;
      Result (Extended => False, Remote => False, Got => Got, Data_Ok => D_Ok,
              Ok => Got and then D_Ok,
              Id => Unsigned_32 (RS.Id), Len => Unsigned_32 (RS.Length));

      --  Extended (29-bit) data round-trip.
      Send (S, Ext);
      Got := Available (S) and then Is_Extended (S);
      if Got then
         Receive (S, RE, Got);
      end if;
      D_Ok := Got and then not RE.Remote and then RE.Id = Ext.Id
                and then RE.Length = Ext.Length;
      if D_Ok then
         for I in 0 .. Ext.Length - 1 loop
            D_Ok := D_Ok and then RE.Data (I) = Ext.Data (I);
         end loop;
      end if;
      Result (Extended => True, Remote => False, Got => Got, Data_Ok => D_Ok,
              Ok => Got and then D_Ok,
              Id => Unsigned_32 (RE.Id), Len => Unsigned_32 (RE.Length));

      --  Standard remote-request (RTR) round-trip: carries Id + DLC, no data.
      Send (S, Rtr);
      Got := Available (S) and then not Is_Extended (S);
      if Got then
         Receive (S, RS, Got);
      end if;
      --  A correct RTR echo: Remote set, matching Id and requested length.
      D_Ok := Got and then RS.Remote and then RS.Id = Rtr.Id
                and then RS.Length = Rtr.Length;
      Result (Extended => False, Remote => True, Got => Got, Data_Ok => D_Ok,
              Ok => Got and then D_Ok,
              Id => Unsigned_32 (RS.Id), Len => Unsigned_32 (RS.Length));

      --  Extended (29-bit) remote-request (RTR) round-trip -- RTR works on either
      --  width, the Remote flag is orthogonal to the addressing standard.
      Send (S, Ert);
      Got := Available (S) and then Is_Extended (S);
      if Got then
         Receive (S, RE, Got);
      end if;
      D_Ok := Got and then RE.Remote and then RE.Id = Ert.Id
                and then RE.Length = Ert.Length;
      Result (Extended => True, Remote => True, Got => Got, Data_Ok => D_Ok,
              Ok => Got and then D_Ok,
              Id => Unsigned_32 (RE.Id), Len => Unsigned_32 (RE.Length));
   end;                                  --  S finalizes -> controller released

   Put_Line ("[twai] done.");

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
