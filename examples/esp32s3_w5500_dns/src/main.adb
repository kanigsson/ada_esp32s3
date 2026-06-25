--  DNS lookup over the W5500, using GNAT.Sockets (UDP).
--
--  Builds a standard DNS A-record query for a hostname, sends it to a resolver,
--  and parses the first A record out of the response (handling DNS name
--  compression).  Demonstrates building and parsing a binary protocol over UDP.
with Ada.Real_Time; use Ada.Real_Time;
with Ada.Streams;   use Ada.Streams;
with GNAT.Sockets;  use GNAT.Sockets;
with ESP32S3.Log;   use ESP32S3.Log;
with W5500_Dev;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   DNS_Server : constant String := "8.8.8.8";       --  the resolver
   Hostname   : constant String := "example.com";   --  what to resolve

   Sock  : Socket_Type;
   Query : Stream_Element_Array (0 .. 511);
   QLen  : Stream_Element_Offset := 0;
   Resp  : Stream_Element_Array (0 .. 511);
   RLast : Stream_Element_Offset;
   SLast : Stream_Element_Offset;
   To    : aliased Sock_Addr_Type := (Family_Inet, Inet_Addr (DNS_Server), 53);
   From  : aliased Sock_Addr_Type;

   --  Build a standard recursive A-record query for Name into Query.
   procedure Build_Query (Name : String) is
      P     : Stream_Element_Offset := Query'First;
      Start : Natural;
      procedure B (V : Integer) is
      begin
         Query (P) := Stream_Element (V);  P := P + 1;
      end B;
   begin
      B (16#12#); B (16#34#);          --  ID
      B (16#01#); B (16#00#);          --  flags: standard query, recursion desired
      B (0); B (1);                    --  QDCOUNT = 1
      B (0); B (0);  B (0); B (0);  B (0); B (0);   --  AN/NS/AR = 0
      Start := Name'First;             --  QNAME as length-prefixed labels
      for I in Name'First .. Name'Last + 1 loop
         if I > Name'Last or else Name (I) = '.' then
            B (I - Start);
            for J in Start .. I - 1 loop
               B (Character'Pos (Name (J)));
            end loop;
            Start := I + 1;
         end if;
      end loop;
      B (0);                           --  end of name
      B (0); B (1);                    --  QTYPE  = A
      B (0); B (1);                    --  QCLASS = IN
      QLen := P - Query'First;
   end Build_Query;

   --  Advance Pos past a DNS name (labels, or a 0xC0 compression pointer).
   procedure Skip_Name (Pos : in out Stream_Element_Offset) is
      Len : Integer;
   begin
      loop
         Len := Integer (Resp (Pos));
         if Len = 0 then
            Pos := Pos + 1;  exit;
         elsif Len >= 16#C0# then            --  pointer: 2 bytes, name ends here
            Pos := Pos + 2;  exit;
         else
            Pos := Pos + 1 + Stream_Element_Offset (Len);
         end if;
      end loop;
   end Skip_Name;

   function U16 (Pos : Stream_Element_Offset) return Integer is
     (Integer (Resp (Pos)) * 256 + Integer (Resp (Pos + 1)));
begin
   delay until Clock + Milliseconds (200);
   Put_Line ("[dns] W5500 DNS lookup (GNAT.Sockets, UDP)");
   if not W5500_Dev.Bring_Up then
      loop delay until Clock + Seconds (3600); end loop;
   end if;

   Build_Query (Hostname);
   Create_Socket (Sock, Family_Inet, Socket_Datagram);
   Bind_Socket   (Sock, (Family_Inet, Any_Inet_Addr, 13_001));
   Put_Line ("[dns] resolving " & Hostname & " via " & DNS_Server & " ...");
   Send_Socket    (Sock, Query (Query'First .. QLen - 1), SLast, To => To'Access);
   Receive_Socket (Sock, Resp, RLast, From => From'Access);

   declare
      AnCount : constant Integer := U16 (Resp'First + 6);   --  answer count
      Pos     : Stream_Element_Offset := Resp'First + 12;   --  past the header
      Found   : Boolean := False;
   begin
      Skip_Name (Pos);                 --  skip the question's QNAME
      Pos := Pos + 4;                  --   + QTYPE + QCLASS
      for A in 1 .. AnCount loop
         Skip_Name (Pos);              --  answer NAME (usually a pointer)
         declare
            RRType : constant Integer := U16 (Pos);
            RDLen  : constant Integer := U16 (Pos + 8);
            RData  : constant Stream_Element_Offset := Pos + 10;
         begin
            if RRType = 1 and then RDLen = 4 then      --  an A record
               Put ("[dns] " & Hostname & " = ");
               Put (Integer (Resp (RData)));     Put (".");
               Put (Integer (Resp (RData + 1))); Put (".");
               Put (Integer (Resp (RData + 2))); Put (".");
               Put (Integer (Resp (RData + 3))); New_Line;
               Found := True;  exit;
            end if;
            Pos := RData + Stream_Element_Offset (RDLen);
         end;
      end loop;
      if not Found then
         Put_Line ("[dns] no A record in the response");
      end if;
   end;

   Close_Socket (Sock);
   loop delay until Clock + Seconds (3600); end loop;
end Main;
