--  Native host test for the Modbus framing layer (Modbus): big-endian helpers,
--  exception-code mapping, MBAP, and a known Read-Holding-Registers request frame
--  checked byte-for-byte against the canonical Modbus TCP example.  Pure logic.
with Ada.Text_IO; use Ada.Text_IO;
with Interfaces;
with Modbus;      use Modbus;

procedure Modbus_Test is

   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_16;

   Passed, Failed : Natural := 0;

   procedure Check (Label : String; Cond : Boolean) is
   begin
      if Cond then
         Passed := Passed + 1;
         Put_Line ("  ok   " & Label);
      else
         Failed := Failed + 1;
         Put_Line ("  FAIL " & Label);
      end if;
   end Check;

   --  Compare Buf (B'First .. ) against the given byte values.
   procedure Expect (Label : String; B : Byte_Array; Want : Byte_Array) is
      OK : Boolean := B'Length = Want'Length;
   begin
      if OK then
         for I in 0 .. Want'Length - 1 loop
            if B (B'First + I) /= Want (Want'First + I) then OK := False; end if;
         end loop;
      end if;
      Check (Label, OK);
   end Expect;

begin
   ----------------------------------------------------------------------------
   Put_Line ("1. big-endian U16");
   declare
      B : Byte_Array (0 .. 1) := (others => 0);
   begin
      Put_U16 (B, 0, 16#1234#);
      Expect ("put 0x1234 -> 12 34", B, (16#12#, 16#34#));
      Check ("get back 0x1234", Get_U16 (B, 0) = 16#1234#);
   end;

   ----------------------------------------------------------------------------
   Put_Line ("2. exception-code mapping");
   Check ("Illegal_Data_Address -> 2", To_Byte (Illegal_Data_Address) = 2);
   Check ("Gateway_Target -> 11", To_Byte (Gateway_Target_Failed_To_Respond) = 11);
   Check ("2 -> Illegal_Data_Address", To_Exception (2) = Illegal_Data_Address);
   Check ("11 -> Gateway_Target", To_Exception (11) = Gateway_Target_Failed_To_Respond);
   Check ("reserved 99 -> Slave_Device_Failure",
          To_Exception (99) = Slave_Device_Failure);
   Check ("0 -> None", To_Exception (0) = None);

   ----------------------------------------------------------------------------
   Put_Line ("3. MBAP header (TID=1, Unit=1, PDU=5 bytes)");
   declare
      B    : Byte_Array (0 .. MBAP_Size - 1) := (others => 16#EE#);
      TID  : Word;
      Unit : Unit_Id;
      Len  : Natural;
   begin
      Put_MBAP (B, TID => 1, Unit => 1, PDU_Len => 5);
      --  TID=0001, proto=0000, length=0006 (unit+5 PDU), unit=01
      Expect ("bytes", B, (16#00#, 16#01#, 16#00#, 16#00#, 16#00#, 16#06#, 16#01#));
      Get_MBAP (B, TID, Unit, Len);
      Check ("parse TID=1",   TID = 1);
      Check ("parse Unit=1",  Unit = 1);
      Check ("parse Length=6", Len = 6);
   end;

   ----------------------------------------------------------------------------
   Put_Line ("4. full Read-Holding-Registers request (addr 0, qty 10)");
   declare
      --  ADU = MBAP(7) + PDU(FC + addr + qty = 5).
      B : Byte_Array (0 .. MBAP_Size + 5 - 1) := (others => 0);
   begin
      Put_MBAP (B, TID => 1, Unit => 1, PDU_Len => 5);
      B (7) := Byte (FC_Read_Holding_Registers);
      Put_U16 (B, 8, 0);    --  starting address
      Put_U16 (B, 10, 10);  --  quantity
      --  Canonical frame: 00 01 00 00 00 06 01 03 00 00 00 0A
      Expect ("canonical frame", B,
              (16#00#, 16#01#, 16#00#, 16#00#, 16#00#, 16#06#,
               16#01#, 16#03#, 16#00#, 16#00#, 16#00#, 16#0A#));
   end;

   ----------------------------------------------------------------------------
   New_Line;
   Put_Line ("Modbus framing:" & Natural'Image (Passed) & " passed,"
             & Natural'Image (Failed) & " failed");
   if Failed > 0 then
      raise Program_Error with "modbus framing test failed";
   end if;
end Modbus_Test;
