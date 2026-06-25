with Interfaces;

--  Minimal, portable X.509 certificate parsing for the bare-metal TLS work.  Pure
--  byte handling (no chip dependency, no heap), so it builds under every profile.
--  The parser is strictly bounds-checked: it parses attacker-controlled data, so
--  every read is validated and any malformation yields Valid = False rather than an
--  out-of-range access.
package X509 is

   subtype U8 is Interfaces.Unsigned_8;
   type Byte_Array is array (Natural range <>) of U8;

   --  An index range into the certificate buffer (empty when First > Last).
   type Slice is record
      First : Natural := 1;
      Last  : Natural := 0;
   end record;
   function Length (S : Slice) return Natural is
     (if S.Last >= S.First then S.Last - S.First + 1 else 0);

   --  The fields we extract from a certificate.  All are index ranges into the
   --  original buffer (no copying); TBS is the exact signed region (the full DER of
   --  tbsCertificate), to be hashed when verifying the signature.
   type Certificate is record
      Valid        : Boolean := False;
      TBS          : Slice;            --  signed bytes (tag..end of tbsCertificate)
      Serial       : Slice;            --  serialNumber INTEGER content
      Not_Before   : Slice;            --  validity times (ASCII, see *_Tag)
      Not_After    : Slice;
      NB_Tag       : U8 := 0;          --  0x17 UTCTime or 0x18 GeneralizedTime
      NA_Tag       : U8 := 0;
      Sig_Alg_OID  : Slice;            --  signatureAlgorithm OID content
      Signature    : Slice;            --  signatureValue (BIT STRING, unused-bits byte dropped)
      RSA_Modulus  : Slice;            --  SubjectPublicKeyInfo RSA modulus  (big-endian INTEGER)
      RSA_Exponent : Slice;            --  RSA public exponent
   end record;

   --  Parse a DER-encoded certificate.  On success Result.Valid is True and the
   --  slices are filled; on any structural problem Result.Valid is False.
   procedure Parse (Cert : Byte_Array; Result : out Certificate);

end X509;
