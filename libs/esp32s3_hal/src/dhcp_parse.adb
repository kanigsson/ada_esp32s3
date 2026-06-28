with Interfaces; use Interfaces;

package body DHCP_Parse with SPARK_Mode => On is

   procedure Parse_Reply
     (RX     : Byte_Array;
      Count  : Natural;
      Result : out Parsed_Reply)
   is
      P    : Natural;
      Code : Natural;
      Len  : Natural;
   begin
      Result := (Msg_Type      => 0,
                 Yiaddr        => (others => 0),
                 Server_Id     => (others => 0),
                 Subnet        => (others => 0),
                 Gateway       => (others => 0),
                 DNS           => (others => 0),
                 Lease_Seconds => 0,
                 Have_Server   => False,
                 Have_Subnet   => False,
                 Have_Gateway  => False,
                 Have_DNS      => False,
                 Have_Lease    => False);

      --  A BOOTP/DHCP reply must carry the fixed header + magic cookie before the
      --  option area: yiaddr sits at offset 16 and the options start at offset 240,
      --  so the first option byte RX (RX'First + 240) must be a received byte.
      if Count < 241 then
         return;
      end if;

      declare
         --  Last received byte index.  From Count <= RX'Length and RX'Last <=
         --  16#FFFF#, Hi <= RX'Last <= 16#FFFF#, which bounds every offset add.
         Hi : constant Natural := RX'First + Count - 1;
      begin
         --  yiaddr (the assigned address) is at the fixed offset 16; Count >= 241
         --  guarantees RX'First + 19 <= Hi.
         Result.Yiaddr := (RX (RX'First + 16), RX (RX'First + 17),
                           RX (RX'First + 18), RX (RX'First + 19));

         P := RX'First + 240;
         --  Fixed trip count: each iteration either exits or advances P by >= 1,
         --  and the walk exits once P passes Hi, so Count + 1 steps is an upper
         --  bound -- this discharges termination without a loop variant.
         for Step in 0 .. Count loop
            pragma Loop_Invariant (P >= RX'First + 240);
            exit when P > Hi;                  --  no option byte left
            Code := Natural (RX (P));
            exit when Code = 255;              --  the End option terminates the area
            if Code = 0 then                   --  Pad option: a single byte
               P := P + 1;
            else
               exit when P + 1 > Hi;           --  the length byte must be present
               Len := Natural (RX (P + 1));
               case Code is
                  when 53 =>                   --  DHCP message type (1 byte)
                     if P + 2 <= Hi then
                        Result.Msg_Type := RX (P + 2);
                     end if;
                  when 54 =>                   --  server identifier (4 bytes)
                     if P + 5 <= Hi then
                        Result.Server_Id :=
                          (RX (P + 2), RX (P + 3), RX (P + 4), RX (P + 5));
                        Result.Have_Server := True;
                     end if;
                  when 1 =>                    --  subnet mask (4 bytes)
                     if P + 5 <= Hi then
                        Result.Subnet :=
                          (RX (P + 2), RX (P + 3), RX (P + 4), RX (P + 5));
                        Result.Have_Subnet := True;
                     end if;
                  when 3 =>                    --  router / gateway (4 bytes)
                     if P + 5 <= Hi then
                        Result.Gateway :=
                          (RX (P + 2), RX (P + 3), RX (P + 4), RX (P + 5));
                        Result.Have_Gateway := True;
                     end if;
                  when 6 =>                    --  DNS server (first 4 bytes)
                     if P + 5 <= Hi then
                        Result.DNS :=
                          (RX (P + 2), RX (P + 3), RX (P + 4), RX (P + 5));
                        Result.Have_DNS := True;
                     end if;
                  when 51 =>                   --  IP-address lease time (4 bytes)
                     if P + 5 <= Hi then
                        Result.Lease_Seconds :=
                          Shift_Left (Unsigned_32 (RX (P + 2)), 24) or
                          Shift_Left (Unsigned_32 (RX (P + 3)), 16) or
                          Shift_Left (Unsigned_32 (RX (P + 4)), 8)  or
                                      Unsigned_32 (RX (P + 5));
                        Result.Have_Lease := True;
                     end if;
                  when others =>
                     null;
               end case;
               P := P + 2 + Len;               --  past the option's value
            end if;
         end loop;
      end;
   end Parse_Reply;

end DHCP_Parse;
