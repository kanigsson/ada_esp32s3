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

end X509;
