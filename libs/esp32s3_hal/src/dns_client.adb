with Ada.Streams;  use Ada.Streams;
with GNAT.Sockets; use GNAT.Sockets;
with DNS_Parse;

package body DNS_Client is

   function Resolve
     (Server     : Inet_Addr_Type;
      Name       : String;
      Addr       : out Inet_Addr_Type;
      Timeout    : Duration  := 0.0;
      Local_Port : Port_Type := 13_001) return Boolean
   is
      Sock  : Socket_Type;
      Query : Stream_Element_Array (0 .. 511);
      QLen  : Stream_Element_Offset := 0;
      Resp  : Stream_Element_Array (0 .. 511);
      RLast : Stream_Element_Offset;
      SLast : Stream_Element_Offset;
      To    : aliased Sock_Addr_Type := (Family_Inet, Server, 53);
      From  : aliased Sock_Addr_Type;

      --  Decimal image of E with no leading blank ("84", not " 84").
      function Img (E : Stream_Element) return String is
         S : constant String := Integer'Image (Integer (E));
      begin
         return S (S'First + 1 .. S'Last);
      end Img;

      --  Build a standard recursive A-record query for Name into Query.
      procedure Build_Query is
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

   begin
      Addr := Any_Inet_Addr;
      Build_Query;
      Create_Socket (Sock, Family_Inet, Socket_Datagram);
      Bind_Socket   (Sock, (Family_Inet, Any_Inet_Addr, Local_Port));
      if Timeout > 0.0 then
         Set_Socket_Option (Sock, Socket_Level, (Receive_Timeout, Timeout => Timeout));
      end if;
      Send_Socket (Sock, Query (Query'First .. QLen - 1), SLast, To => To'Access);
      begin
         Receive_Socket (Sock, Resp, RLast, From => From'Access);
      exception
         when Socket_Error =>                --  no reply within Timeout
            Close_Socket (Sock);
            return False;
      end;

      --  Hand the raw reply to the proved, socket-free parser (DNS_Parse): it walks
      --  the attacker-controlled datagram with every index bounded by RLast and
      --  recovers the first A-record address, fail-closed on anything malformed.
      declare
         Host  : DNS_Parse.Host_Octets;
         Found : Boolean;
      begin
         DNS_Parse.Parse_Reply (Resp, RLast, Host, Found);
         if Found then
            Addr := Inet_Addr
              (Img (Host (1)) & "." & Img (Host (2)) & "." &
               Img (Host (3)) & "." & Img (Host (4)));
         end if;
         Close_Socket (Sock);
         return Found;
      end;
   end Resolve;

end DNS_Client;
