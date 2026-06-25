with X509.DER;

package body X509 is

   use type Interfaces.Unsigned_8;

   --  Read the element at P within [.. Limit]; require Valid and (if Want /= 0) a
   --  matching tag.  Clears Ok on failure and short-circuits once Ok is False.
   procedure Expect (Buf : Byte_Array; P, Limit : Natural; Want : U8;
                     E : out DER.TLV; Ok : in out Boolean) is
   begin
      E := (Valid => False, others => <>);
      if not Ok then
         return;
      end if;
      DER.Read (Buf, P, Limit, E);
      if not E.Valid or else (Want /= 0 and then E.Tag /= Want) then
         Ok := False;
      end if;
   end Expect;

   --  subjectAltName extension OID is 2.5.29.17  (DER content 55 1D 11).
   function Is_SAN_OID (Cert : Byte_Array; S : Slice) return Boolean is
     (Length (S) = 3
      and then Cert (S.First) = 16#55#
      and then Cert (S.First + 1) = 16#1D#
      and then Cert (S.First + 2) = 16#11#);

   --  GeneralNames ::= SEQUENCE OF GeneralName; collect dNSName ([2], tag 0x82).
   procedure Parse_SAN (Cert : Byte_Array; First, Last : Natural;
                        Result : in out Certificate) is
      Seq, Name : DER.TLV;
      P : Natural;
   begin
      DER.Read (Cert, First, Last, Seq);
      if not Seq.Valid or else Seq.Tag /= 16#30# then
         return;
      end if;
      P := Seq.Content.First;
      while P <= Seq.Content.Last loop
         DER.Read (Cert, P, Seq.Content.Last, Name);
         exit when not Name.Valid;
         if Name.Tag = 16#82# and then Result.SAN_Count < Max_SAN then
            Result.SAN_Count := Result.SAN_Count + 1;
            Result.SAN (Result.SAN_Count) := Name.Content;
         end if;
         P := Name.Elem_Last + 1;
      end loop;
   end Parse_SAN;

   --  Extensions ::= SEQUENCE OF Extension { extnID OID, [critical], extnValue }.
   procedure Parse_Extensions (Cert : Byte_Array; First, Last : Natural;
                               Result : in out Certificate) is
      Seq, Ext, OID, Val : DER.TLV;
      P, EP : Natural;
   begin
      DER.Read (Cert, First, Last, Seq);
      if not Seq.Valid or else Seq.Tag /= 16#30# then
         return;
      end if;
      P := Seq.Content.First;
      while P <= Seq.Content.Last loop
         DER.Read (Cert, P, Seq.Content.Last, Ext);
         exit when not Ext.Valid or else Ext.Tag /= 16#30#;
         EP := Ext.Content.First;
         DER.Read (Cert, EP, Ext.Content.Last, OID);
         if OID.Valid and then OID.Tag = 16#06#
           and then Is_SAN_OID (Cert, OID.Content)
         then
            EP := OID.Elem_Last + 1;
            DER.Read (Cert, EP, Ext.Content.Last, Val);
            if Val.Valid and then Val.Tag = 16#01# then    --  optional critical BOOLEAN
               EP := Val.Elem_Last + 1;
               DER.Read (Cert, EP, Ext.Content.Last, Val);
            end if;
            if Val.Valid and then Val.Tag = 16#04# then    --  extnValue OCTET STRING
               Parse_SAN (Cert, Val.Content.First, Val.Content.Last, Result);
            end if;
         end if;
         P := Ext.Elem_Last + 1;
      end loop;
   end Parse_Extensions;

   procedure Parse (Cert : Byte_Array; Result : out Certificate) is
      Ok : Boolean := True;
      Outer, Tbs, E, Validity, SPKI, Bits, RSASeq, SigAlg, OID, SigVal : DER.TLV;
      P, L : Natural;
   begin
      Result := (Valid => False, others => <>);
      if Cert'Length < 2 then
         return;
      end if;

      --  Certificate ::= SEQUENCE { tbsCertificate, signatureAlgorithm, signature }
      Expect (Cert, Cert'First, Cert'Last, 16#30#, Outer, Ok);
      if not Ok then
         return;
      end if;

      --  tbsCertificate (the whole element is the signed region).
      Expect (Cert, Outer.Content.First, Outer.Content.Last, 16#30#, Tbs, Ok);
      if not Ok then
         return;
      end if;
      Result.TBS := (First => Outer.Content.First, Last => Tbs.Elem_Last);

      P := Tbs.Content.First;
      L := Tbs.Content.Last;

      --  version [0] EXPLICIT -- optional.
      DER.Read (Cert, P, L, E);
      if E.Valid and then E.Tag = 16#A0# then
         P := E.Elem_Last + 1;
      end if;

      --  serialNumber INTEGER
      Expect (Cert, P, L, 16#02#, E, Ok);
      Result.Serial := E.Content;
      P := E.Elem_Last + 1;

      --  signature AlgorithmIdentifier  (skip)
      Expect (Cert, P, L, 16#30#, E, Ok);
      P := E.Elem_Last + 1;

      --  issuer Name  (skip)
      Expect (Cert, P, L, 16#30#, E, Ok);
      P := E.Elem_Last + 1;

      --  validity SEQUENCE { notBefore Time, notAfter Time }
      Expect (Cert, P, L, 16#30#, Validity, Ok);
      if Ok then
         declare
            VP : Natural := Validity.Content.First;
            VL : constant Natural := Validity.Content.Last;
            NB, NA : DER.TLV;
         begin
            Expect (Cert, VP, VL, 0, NB, Ok);
            Result.Not_Before := NB.Content;  Result.NB_Tag := NB.Tag;
            VP := NB.Elem_Last + 1;
            Expect (Cert, VP, VL, 0, NA, Ok);
            Result.Not_After := NA.Content;   Result.NA_Tag := NA.Tag;
         end;
      end if;
      P := Validity.Elem_Last + 1;

      --  subject Name  (skip)
      Expect (Cert, P, L, 16#30#, E, Ok);
      P := E.Elem_Last + 1;

      --  subjectPublicKeyInfo SEQUENCE { algorithm, subjectPublicKey BIT STRING }
      Expect (Cert, P, L, 16#30#, SPKI, Ok);
      if Ok then
         declare
            SP    : Natural := SPKI.Content.First;
            SL    : constant Natural := SPKI.Content.Last;
            AlgId : DER.TLV;
         begin
            Expect (Cert, SP, SL, 16#30#, AlgId, Ok);     --  algorithm (skip)
            SP := AlgId.Elem_Last + 1;
            Expect (Cert, SP, SL, 16#03#, Bits, Ok);      --  subjectPublicKey BIT STRING
            if Ok and then Length (Bits.Content) >= 2 then
               --  Skip the BIT STRING's unused-bits byte; parse RSAPublicKey.
               Expect (Cert, Bits.Content.First + 1, Bits.Content.Last, 16#30#, RSASeq, Ok);
               if Ok then
                  declare
                     RP : Natural := RSASeq.Content.First;
                     RL : constant Natural := RSASeq.Content.Last;
                     M, Ex : DER.TLV;
                  begin
                     Expect (Cert, RP, RL, 16#02#, M, Ok);   --  modulus INTEGER
                     Result.RSA_Modulus := M.Content;
                     RP := M.Elem_Last + 1;
                     Expect (Cert, RP, RL, 16#02#, Ex, Ok);  --  publicExponent INTEGER
                     Result.RSA_Exponent := Ex.Content;
                  end;
               end if;
            else
               Ok := False;
            end if;
         end;
      end if;

      --  extensions [3] EXPLICIT -- optional; we pull subjectAltName dNSNames.
      if Ok then
         P := SPKI.Elem_Last + 1;
         DER.Read (Cert, P, L, E);
         if E.Valid and then E.Tag = 16#A3# then
            Parse_Extensions (Cert, E.Content.First, E.Content.Last, Result);
         end if;
      end if;

      --  signatureAlgorithm SEQUENCE { OID ... }
      P := Tbs.Elem_Last + 1;
      Expect (Cert, P, Outer.Content.Last, 16#30#, SigAlg, Ok);
      Expect (Cert, SigAlg.Content.First, SigAlg.Content.Last, 16#06#, OID, Ok);
      Result.Sig_Alg_OID := OID.Content;
      P := SigAlg.Elem_Last + 1;

      --  signatureValue BIT STRING (drop the leading unused-bits byte).
      Expect (Cert, P, Outer.Content.Last, 16#03#, SigVal, Ok);
      if Ok and then Length (SigVal.Content) >= 1 then
         Result.Signature := (First => SigVal.Content.First + 1, Last => SigVal.Content.Last);
      else
         Ok := False;
      end if;

      Result.Valid := Ok;
   end Parse;

   ---------------------------------------------------------------------------
   --  Validity dates
   ---------------------------------------------------------------------------

   --  Parse an ASN.1 Time (UTCTime YYMMDDHHMMSSZ or GeneralizedTime
   --  YYYYMMDDHHMMSSZ) at slice S into a packed Time_64.  False if malformed.
   function Parse_Time (Cert : Byte_Array; S : Slice; Tag : U8; T : out Time_64)
                        return Boolean
   is
      F    : constant Natural := S.First;
      L    : constant Natural := Length (S);
      Base : Natural;
      Year, Mon, Day, Hr, Mi, Sc : Natural;

      function Is_Digit (Off : Natural) return Boolean is
        (Cert (F + Off) in 16#30# .. 16#39#);
      function D (Off : Natural) return Natural is
        (Natural (Cert (F + Off)) - 16#30#);
      function Two (Off : Natural) return Natural is (D (Off) * 10 + D (Off + 1));
   begin
      T := 0;
      if Tag = 16#17# then                        --  UTCTime (13: YYMMDDHHMMSSZ)
         if L /= 13 or else Cert (F + 12) /= 16#5A# then
            return False;
         end if;
         for K in 0 .. 11 loop
            if not Is_Digit (K) then return False; end if;
         end loop;
         Year := (if Two (0) < 50 then 2000 + Two (0) else 1900 + Two (0));
         Base := 2;
      elsif Tag = 16#18# then                      --  GeneralizedTime (15)
         if L /= 15 or else Cert (F + 14) /= 16#5A# then
            return False;
         end if;
         for K in 0 .. 13 loop
            if not Is_Digit (K) then return False; end if;
         end loop;
         Year := D (0) * 1000 + D (1) * 100 + D (2) * 10 + D (3);
         Base := 4;
      else
         return False;
      end if;
      Mon := Two (Base);      Day := Two (Base + 2);
      Hr  := Two (Base + 4);  Mi  := Two (Base + 6);  Sc := Two (Base + 8);
      if Mon not in 1 .. 12 or else Day not in 1 .. 31
        or else Hr > 23 or else Mi > 59 or else Sc > 60
      then
         return False;
      end if;
      T := Pack_Time (Year, Mon, Day, Hr, Mi, Sc);
      return True;
   end Parse_Time;

   function Valid_At (Cert : Byte_Array; C : Certificate; Now : Time_64)
                      return Boolean
   is
      NB, NA : Time_64;
   begin
      if not Parse_Time (Cert, C.Not_Before, C.NB_Tag, NB)
        or else not Parse_Time (Cert, C.Not_After, C.NA_Tag, NA)
      then
         return False;
      end if;
      return Now >= NB and then Now <= NA;
   end Valid_At;

   ---------------------------------------------------------------------------
   --  Hostname matching (subjectAltName dNSName)
   ---------------------------------------------------------------------------

   function Lower (B : U8) return U8 is
     (if B in 16#41# .. 16#5A# then B + 16#20# else B);

   --  Case-insensitive equality of Cert[BF..BL] (ASCII bytes) and Host[HF..HL].
   function Eq_CI (Cert : Byte_Array; BF, BL : Natural;
                   Host : String; HF, HL : Natural) return Boolean is
   begin
      if BL < BF or else HL < HF or else BL - BF /= HL - HF then
         return False;
      end if;
      for K in 0 .. BL - BF loop
         if Lower (Cert (BF + K)) /= Lower (U8 (Character'Pos (Host (HF + K)))) then
            return False;
         end if;
      end loop;
      return True;
   end Eq_CI;

   function Name_Matches (Cert : Byte_Array; S : Slice; Host : String)
                          return Boolean
   is
      function Has_Dot (From, To : Natural) return Boolean is
      begin
         for I in From .. To loop
            if Cert (I) = 16#2E# then return True; end if;
         end loop;
         return False;
      end Has_Dot;
   begin
      if Length (S) = 0 or else Host'Length = 0 then
         return False;
      end if;

      --  Wildcard "*." : match exactly one leftmost label of Host, and only where
      --  the remainder still has two labels (a dot).
      if Length (S) >= 2
        and then Cert (S.First) = 16#2A# and then Cert (S.First + 1) = 16#2E#
      then
         declare
            Dot : Natural := 0;
         begin
            for I in Host'Range loop
               if Host (I) = '.' then Dot := I; exit; end if;
            end loop;
            if Dot = 0 or else Dot = Host'First then        --  no / empty leftmost label
               return False;
            end if;
            return Eq_CI (Cert, S.First + 1, S.Last, Host, Dot, Host'Last)
                   and then Has_Dot (S.First + 2, S.Last);
         end;
      else
         return Eq_CI (Cert, S.First, S.Last, Host, Host'First, Host'Last);
      end if;
   end Name_Matches;

   function Host_Matches (Cert : Byte_Array; C : Certificate; Host : String)
                          return Boolean is
   begin
      for I in 1 .. C.SAN_Count loop
         if Name_Matches (Cert, C.SAN (I), Host) then
            return True;
         end if;
      end loop;
      return False;
   end Host_Matches;

end X509;
