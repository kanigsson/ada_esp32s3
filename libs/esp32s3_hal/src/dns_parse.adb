with Ada.Streams; use Ada.Streams;

package body DNS_Parse with SPARK_Mode => On is

   --  Big-endian 16-bit field at Resp (Pos .. Pos + 1).  Total over its domain;
   --  the result is in 0 .. 65_535 (used to bound the RDLENGTH-driven advance).
   function U16
     (Resp : Stream_Element_Array; Pos : Stream_Element_Offset) return Natural
   is (Natural (Resp (Pos)) * 256 + Natural (Resp (Pos + 1)))
     with Pre => Resp'Last <= 16#FFFF#
                 and then Pos >= Resp'First
                 and then Pos < Resp'Last;

   --  Advance Pos past one DNS name in Resp (Resp'First .. RLast): a run of
   --  length-prefixed labels ending at a 0 byte, or a 0xC0 compression pointer
   --  (2 bytes, which ends the name -- we never *follow* the pointer, so there is
   --  no resolver pointer-loop to chase).  Ok is False, fail-closed, if the name
   --  runs past RLast.  The for-loop's fixed trip count (each non-terminal label
   --  advances Pos by >= 2) makes the walk provably bounded -- no unbounded
   --  Skip_Name overrun, the live bug the inline parse carried.
   procedure Skip_Name
     (Resp  : Stream_Element_Array;
      RLast : Stream_Element_Offset;
      Pos   : in out Stream_Element_Offset;
      Ok    : out Boolean)
     with Pre  => Resp'First >= 0
                  and then Resp'Last <= 16#FFFF#
                  and then RLast <= Resp'Last
                  and then Pos >= Resp'First
                  and then Pos <= RLast + 1,
          Post => (if Ok then Pos >= Resp'First and then Pos <= RLast + 1)
   is
      Len : Natural;
   begin
      Ok := False;
      for Step in 0 .. Resp'Length loop
         pragma Loop_Invariant (Pos >= Resp'First);
         if Pos > RLast then          --  ran off the end of the datagram
            return;
         end if;
         Len := Natural (Resp (Pos));
         if Len = 0 then              --  root label: name ends here
            Pos := Pos + 1;
            Ok  := True;
            return;
         elsif Len >= 16#C0# then     --  compression pointer: 2 bytes, name ends
            if Pos + 1 > RLast then
               return;                --  truncated pointer
            end if;
            Pos := Pos + 2;
            Ok  := True;
            return;
         else                         --  ordinary label of Len bytes
            if Pos + Stream_Element_Offset (Len) > RLast then
               return;                --  label overshoots the datagram
            end if;
            Pos := Pos + 1 + Stream_Element_Offset (Len);
         end if;
      end loop;
   end Skip_Name;

   procedure Parse_Reply
     (Resp  : Stream_Element_Array;
      RLast : Stream_Element_Offset;
      Host  : out Host_Octets;
      Found : out Boolean)
   is
      AnCount : Natural;
      Pos     : Stream_Element_Offset;
      Ok      : Boolean;
   begin
      Host  := (others => 0);
      Found := False;

      --  A reply must carry at least the 12-byte fixed header.
      if RLast < Resp'First + 11 then
         return;
      end if;

      AnCount := U16 (Resp, Resp'First + 6);       --  ANCOUNT
      Pos     := Resp'First + 12;                  --  first byte past the header

      Skip_Name (Resp, RLast, Pos, Ok);            --  the question's QNAME
      if not Ok then
         return;
      end if;
      Pos := Pos + 4;                              --   + QTYPE + QCLASS

      for A in 1 .. AnCount loop
         pragma Loop_Invariant (Pos >= Resp'First);
         exit when Pos > RLast;
         Skip_Name (Resp, RLast, Pos, Ok);         --  the answer's NAME
         exit when not Ok;
         --  Need the fixed 10-byte RR header (TYPE/CLASS/TTL/RDLENGTH) at Pos.
         exit when Pos + 9 > RLast;
         declare
            RRType : constant Natural := U16 (Resp, Pos);
            RDLen  : constant Natural := U16 (Resp, Pos + 8);
            RData  : constant Stream_Element_Offset := Pos + 10;
         begin
            if RRType = 1 and then RDLen = 4 then  --  an A record (4-byte RDATA)
               exit when RData + 3 > RLast;        --  RDATA must be in the datagram
               Host  := (Resp (RData), Resp (RData + 1),
                         Resp (RData + 2), Resp (RData + 3));
               Found := True;
               exit;
            end if;
            Pos := RData + Stream_Element_Offset (RDLen);
         end;
      end loop;
   end Parse_Reply;

end DNS_Parse;
