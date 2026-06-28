--  Native host test for Modbus.Master: drives the SAME master source (against the
--  real GNAT.Sockets) at the stdlib Python slave in modbus_slave.py, exercising
--  every function code plus the exception path.  Port is argv(1).  See run.sh.
with Ada.Command_Line; use Ada.Command_Line;
with Ada.Text_IO;      use Ada.Text_IO;
with Interfaces;
with GNAT.Sockets;
with Modbus;           use Modbus;
with Modbus.Master;

procedure Modbus_Master_Host is
   use type Interfaces.Unsigned_16;
   package M renames Modbus.Master;
   use type M.Status;

   S : M.Session;
   P : constant GNAT.Sockets.Port_Type :=
         GNAT.Sockets.Port_Type'Value (Argument (1));

   Passed, Failed : Natural := 0;

   procedure Check (Label : String; Cond : Boolean) is
   begin
      if Cond then
         Passed := Passed + 1;  Put_Line ("  ok   " & Label);
      else
         Failed := Failed + 1;  Put_Line ("  FAIL " & Label);
      end if;
   end Check;

   R   : M.Status;
   Exc : Exception_Code;
begin
   M.Connect (S, "127.0.0.1", Port => P, Result => R);
   Check ("connect", R = M.OK);
   if R /= M.OK then
      Put_Line ("cannot reach slave -- abort");
      Set_Exit_Status (1);
      return;
   end if;

   --  FC03 read holding: holding[r] = 1000 + r
   declare
      W : Word_Array (0 .. 9);
   begin
      M.Read_Holding_Registers (S, 1, 0, 10, W, R, Exc);
      Check ("read holding 0..9 OK", R = M.OK);
      Check ("holding[0]=1000", W (0) = 1000);
      Check ("holding[9]=1009", W (9) = 1009);
   end;

   --  FC04 read input: input[r] = 2000 + r
   declare
      W : Word_Array (0 .. 4);
   begin
      M.Read_Input_Registers (S, 1, 0, 5, W, R, Exc);
      Check ("read input 0..4 OK", R = M.OK);
      Check ("input[0]=2000", W (0) = 2000);
      Check ("input[4]=2004", W (4) = 2004);
   end;

   --  FC01 read coils: even addresses are set
   declare
      B : Bit_Array (0 .. 15);
   begin
      M.Read_Coils (S, 1, 0, 16, B, R, Exc);
      Check ("read coils OK", R = M.OK);
      Check ("coil[0]=T", B (0));
      Check ("coil[1]=F", not B (1));
      Check ("coil[2]=T", B (2));
   end;

   --  FC02 read discrete inputs: r mod 3 = 0 set
   declare
      B : Bit_Array (0 .. 15);
   begin
      M.Read_Discrete_Inputs (S, 1, 0, 16, B, R, Exc);
      Check ("read discrete OK", R = M.OK);
      Check ("di[0]=T", B (0));
      Check ("di[3]=T", B (3));
      Check ("di[1]=F", not B (1));
   end;

   --  FC06 write single register, read back
   declare
      W : Word_Array (0 .. 0);
   begin
      M.Write_Single_Register (S, 1, 20, 16#BEEF#, R, Exc);
      Check ("write single reg OK", R = M.OK);
      M.Read_Holding_Registers (S, 1, 20, 1, W, R, Exc);
      Check ("read back 0xBEEF", R = M.OK and then W (0) = 16#BEEF#);
   end;

   --  FC05 write single coil, read back (addr 7 defaults False)
   declare
      B : Bit_Array (0 .. 0);
   begin
      M.Write_Single_Coil (S, 1, 7, True, R, Exc);
      Check ("write single coil OK", R = M.OK);
      M.Read_Coils (S, 1, 7, 1, B, R, Exc);
      Check ("read back coil[7]=T", R = M.OK and then B (0));
   end;

   --  FC16 write multiple registers, read back
   declare
      Out_W : constant Word_Array := (10, 20, 30);
      W     : Word_Array (0 .. 2);
   begin
      M.Write_Multiple_Registers (S, 1, 30, Out_W, R, Exc);
      Check ("write multi reg OK", R = M.OK);
      M.Read_Holding_Registers (S, 1, 30, 3, W, R, Exc);
      Check ("read back [10,20,30]",
             R = M.OK and then W (0) = 10 and then W (1) = 20 and then W (2) = 30);
   end;

   --  FC15 write multiple coils, read back
   declare
      Out_B : constant Bit_Array := (True, False, True, True);
      B     : Bit_Array (0 .. 3);
   begin
      M.Write_Multiple_Coils (S, 1, 40, Out_B, R, Exc);
      Check ("write multi coil OK", R = M.OK);
      M.Read_Coils (S, 1, 40, 4, B, R, Exc);
      Check ("read back T F T T",
             R = M.OK and then B (0) and then not B (1)
             and then B (2) and then B (3));
   end;

   --  Exception path: address >= 0x9000 -> Illegal Data Address
   declare
      W : Word_Array (0 .. 0);
   begin
      M.Read_Holding_Registers (S, 1, 16#9000#, 1, W, R, Exc);
      Check ("bad addr -> Exception_Response", R = M.Exception_Response);
      Check ("exc = Illegal_Data_Address", Exc = Illegal_Data_Address);
   end;

   M.Close (S);

   New_Line;
   Put_Line ("Modbus master:" & Natural'Image (Passed) & " passed,"
             & Natural'Image (Failed) & " failed");
   if Failed > 0 then
      Set_Exit_Status (1);
   end if;
end Modbus_Master_Host;
