package body X509.DER with SPARK_Mode => On is

   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_32;

   procedure Read (Buf : Byte_Array; Pos, Limit : Natural; E : out TLV) is
      P      : Natural := Pos;
      LB     : U8;
      NBytes : Natural;
      Len    : Natural;          --  set on every reachable path before use
   begin
      E := (Tag => 0, Content => (1, 0), Elem_Last => 0, Valid => False);

      --  The window [Pos .. Limit] must be inside the buffer and non-empty.
      if Limit > Buf'Last or else Pos < Buf'First or else Pos > Limit then
         return;
      end if;

      --  Tag (single-byte only; high-tag-number form is rejected).
      E.Tag := Buf (P);
      if (E.Tag and 16#1F#) = 16#1F# then
         return;
      end if;
      if P >= Limit then                    --  no room for a length byte
         return;
      end if;
      P := P + 1;

      --  Length.
      LB := Buf (P);
      if LB < 16#80# then                    --  short form
         Len := Natural (LB);
      elsif LB = 16#80# then                 --  indefinite: not allowed in DER
         return;
      else                                   --  long form: LB-0x80 length octets
         NBytes := Natural (LB and 16#7F#);
         if NBytes > 4 or else NBytes > Limit - P then
            return;
         end if;
         --  Accumulate the length in a modular 32-bit type.  For NBytes <= 4 the
         --  value fits exactly, so this cannot overflow the way `Len * 256` on a
         --  fixed-range Integer would for a crafted 4-byte length (e.g.
         --  84 FF FF FF FF -> 2**32-1, past Natural'Last -> Constraint_Error).
         declare
            Acc    : Interfaces.Unsigned_32 := 0;
            Window : constant Natural := Limit - P - NBytes;   --  bytes after len
         begin
            for K in 1 .. NBytes loop
               Acc := Acc * 256 + Interfaces.Unsigned_32 (Buf (P + K));
            end loop;
            --  Reject a length the remaining window cannot hold; this also bounds
            --  Acc <= Natural'Last so the narrowing to Len is safe.
            if Acc > Interfaces.Unsigned_32 (Window) then
               return;
            end if;
            Len := Natural (Acc);
         end;
         P := P + NBytes;
      end if;

      --  Content range: starts just after the length field.
      if Len = 0 then
         E.Content   := (First => 1, Last => 0);   --  canonical empty slice
         E.Elem_Last := P;
      else
         --  Need P + Len <= Limit (overflow-safe form).
         if Len > Limit - P then
            return;
         end if;
         E.Content   := (First => P + 1, Last => P + Len);
         E.Elem_Last := P + Len;
      end if;
      E.Valid := True;
   end Read;

end X509.DER;
