--  DER (ASN.1 distinguished encoding) TLV reader.  One call parses one element;
--  the caller walks structures by entering an element's content range and reading
--  the children.  Strictly bounds-checked.
package X509.DER with SPARK_Mode => On is

   type TLV is record
      Tag       : U8 := 0;
      Content   : Slice;          --  the value's index range (empty if no content)
      Elem_Last : Natural := 0;   --  last index of the whole element (tag+len+value)
      Valid     : Boolean := False;
   end record;

   --  Read the element starting at Pos, which must lie within Buf and whose whole
   --  encoding must end at or before Limit (an inclusive last index, <= Buf'Last).
   --  Valid = False on any overrun, indefinite length, reserved/long-form tag, or
   --  length that does not fit.  (Long-form tags and indefinite lengths never occur
   --  in a valid DER certificate, so they are rejected.)
   --
   --  Workhorse lemma (Tier A): a valid element stays inside [Pos .. Limit] subset
   --  Buf, and its (non-empty) content range lies within Buf.  Callers walk a
   --  structure by re-reading at Elem_Last + 1, and index Buf over the content
   --  range; this postcondition is what makes that indexing provably in-bounds.
   procedure Read (Buf : Byte_Array; Pos, Limit : Natural; E : out TLV)
     with Pre  => Buf'Last < Natural'Last,   --  a real cert buffer, not the whole heap
          Post =>
       (if E.Valid then
          E.Elem_Last <= Limit
          and then E.Elem_Last <= Buf'Last
          and then E.Content.Last <= E.Elem_Last
          and then (if Length (E.Content) > 0 then
                      E.Content.First >= Buf'First
                      and then E.Content.Last <= Buf'Last));

end X509.DER;
