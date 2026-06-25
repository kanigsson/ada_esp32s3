with Interfaces;    use Interfaces;
with Ada.Real_Time; use Ada.Real_Time;

package body ESP32S3.W5500.DHCP is

   package WS renames ESP32S3.W5500.Sockets;
   use type WS.Status;

   Server_Port : constant WS.Port_Number := 67;
   Client_Port : constant WS.Port_Number := 68;

   --  DHCP message types (option 53).
   Discover : constant Byte := 1;
   Offer    : constant Byte := 2;
   Request  : constant Byte := 3;
   Ack      : constant Byte := 5;

   function Acquire_Lease
     (Dev    : ESP32S3.W5500.Sockets.Device_Access;
      MAC    : MAC_Address;
      Lease  : out Lease_Info;
      Socket : Socket_Id := 0;
      Tries  : Positive  := 4) return Boolean
   is
      Bcast : constant IPv4_Address := (255, 255, 255, 255);

      S     : WS.Socket;
      St    : WS.Status;
      TX    : Byte_Array (0 .. 299) := (others => 0);
      RX    : Byte_Array (0 .. 299);
      TX_Len : Natural;

      Offered   : IPv4_Address := (0, 0, 0, 0);   --  yiaddr from the OFFER
      Server_Id : IPv4_Address := (0, 0, 0, 0);   --  option 54

      --  Build a BOOTP/DHCP frame of message type Msg into TX; With_Req adds the
      --  requested-IP (50) and server-id (54) options (for REQUEST).
      procedure Build (Msg : Byte; With_Req : Boolean) is
         P : Natural;
      begin
         TX := (others => 0);
         TX (0) := 1;  TX (1) := 1;  TX (2) := 6;  TX (3) := 0;   --  op/htype/hlen/hops
         TX (4) := 16#39#; TX (5) := 16#03#;                      --  xid (fixed)
         TX (6) := 16#F3#; TX (7) := 16#26#;
         TX (10) := 16#80#;                                       --  flags: broadcast
         for I in 0 .. 5 loop TX (28 + I) := MAC (I); end loop;   --  chaddr = MAC
         TX (236) := 16#63#; TX (237) := 16#82#;                  --  magic cookie
         TX (238) := 16#53#; TX (239) := 16#63#;
         P := 240;
         TX (P) := 53; TX (P + 1) := 1; TX (P + 2) := Msg;        --  message type
         P := P + 3;
         if With_Req then
            TX (P) := 50; TX (P + 1) := 4;                        --  requested IP
            for I in 0 .. 3 loop TX (P + 2 + I) := Offered (I); end loop;
            P := P + 6;
            TX (P) := 54; TX (P + 1) := 4;                        --  server id
            for I in 0 .. 3 loop TX (P + 2 + I) := Server_Id (I); end loop;
            P := P + 6;
         end if;
         TX (P) := 55; TX (P + 1) := 4;                           --  param request list
         TX (P + 2) := 1; TX (P + 3) := 3; TX (P + 4) := 6; TX (P + 5) := 51;
         P := P + 6;
         TX (P) := 255;                                           --  end
         TX_Len := P + 1;
      end Build;

      --  Poll for a reply of the wanted message type until Deadline; parse its
      --  options (filling Lease + Server_Id + Offered).  Returns True on a match.
      function Wait_Reply (Want : Byte; Deadline : Time) return Boolean is
         FA      : IPv4_Address;
         FP      : WS.Port_Number;
         Count   : Natural;
         Rst     : WS.Status;
         P, Code, Len : Natural;
         Msg     : Byte;
      begin
         loop
            WS.Receive_From (S, FA, FP, RX, Count, Rst);
            if Count >= 240 then
               Msg := 0;
               P   := 240;
               while P <= Count - 1 loop
                  Code := Natural (RX (P));
                  exit when Code = 255;                           --  end option
                  if Code = 0 then
                     P := P + 1;                                  --  pad
                  else
                     Len := Natural (RX (P + 1));
                     case Code is
                        when 53 => Msg := RX (P + 2);
                        when 54 => for I in 0 .. 3 loop Server_Id (I) := RX (P + 2 + I); end loop;
                        when 1  => for I in 0 .. 3 loop Lease.Subnet  (I) := RX (P + 2 + I); end loop;
                        when 3  => for I in 0 .. 3 loop Lease.Gateway (I) := RX (P + 2 + I); end loop;
                        when 6  => for I in 0 .. 3 loop Lease.DNS     (I) := RX (P + 2 + I); end loop;
                        when 51 =>
                           Lease.Lease_Seconds :=
                             Shift_Left (Unsigned_32 (RX (P + 2)), 24) or
                             Shift_Left (Unsigned_32 (RX (P + 3)), 16) or
                             Shift_Left (Unsigned_32 (RX (P + 4)), 8)  or
                                         Unsigned_32 (RX (P + 5));
                        when others => null;
                     end case;
                     P := P + 2 + Len;
                  end if;
               end loop;
               if Msg = Want then
                  for I in 0 .. 3 loop Offered (I) := RX (16 + I); end loop;  --  yiaddr
                  Lease.IP := Offered;
                  return True;
               end if;
            end if;
            exit when Clock >= Deadline;
            delay until Clock + Milliseconds (10);
         end loop;
         return False;
      end Wait_Reply;

   begin
      --  Identity for DORA: our MAC, and a 0.0.0.0 address (as DHCP requires).
      Configure (Dev.all, MAC, IPv4 (0, 0, 0, 0), IPv4 (0, 0, 0, 0), IPv4 (0, 0, 0, 0));
      WS.Open_UDP (Dev, S, Socket, Client_Port, St);
      if St /= WS.OK then
         return False;
      end if;

      for Attempt in 1 .. Tries loop
         Build (Discover, With_Req => False);
         WS.Send_To (S, Bcast, Server_Port, TX (0 .. TX_Len - 1), St);
         if St = WS.OK and then Wait_Reply (Offer, Clock + Seconds (2)) then
            Build (Request, With_Req => True);
            WS.Send_To (S, Bcast, Server_Port, TX (0 .. TX_Len - 1), St);
            if St = WS.OK and then Wait_Reply (Ack, Clock + Seconds (2)) then
               WS.Close (S);
               Configure (Dev.all, MAC, Lease.IP, Lease.Subnet, Lease.Gateway);
               return True;
            end if;
         end if;
      end loop;

      WS.Close (S);
      return False;
   end Acquire_Lease;

end ESP32S3.W5500.DHCP;
