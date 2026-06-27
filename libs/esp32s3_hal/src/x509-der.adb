package body X509.DER is

   use type Interfaces.Unsigned_8;

   procedure Read (Buf : Byte_Array; Pos, Limit : Natural; E : out TLV) is
      P      : Natural := Pos;
      LB     : U8;
      NBytes : Natural;
      Len    : Natural := 0;
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
         for K in 1 .. NBytes loop
            Len := Len * 256 + Natural (Buf (P + K));
         end loop;
         P := P + NBytes;
      end if;

      --  Content range: starts just after the length field.
      if Len = 0 then
         E.Content   := (First => P + 1, Last => P);   --  empty
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
