with Interfaces;

--  Minimal, portable X.509 certificate parsing for the bare-metal TLS work.  Pure
--  byte handling (no chip dependency, no heap), so it builds under every profile.
--  The parser is strictly bounds-checked: it parses attacker-controlled data, so
--  every read is validated and any malformation yields Valid = False rather than an
--  out-of-range access.
package X509 with SPARK_Mode => On is

   subtype U8 is Interfaces.Unsigned_8;
   type Byte_Array is array (Natural range <>) of U8;

   --  Indices into a (finite) certificate buffer.  Capping just below Natural'Last
   --  lets a slice length (Last - First + 1) be computed without overflow; real DER
   --  buffers are a few KiB, nowhere near this bound.
   subtype Buffer_Index is Natural range 0 .. Natural'Last - 1;

   --  An index range into the certificate buffer (empty when First > Last).
   type Slice is record
      First : Buffer_Index := 1;
      Last  : Buffer_Index := 0;
   end record;
   function Length (S : Slice) return Natural is
     (if S.Last >= S.First then S.Last - S.First + 1 else 0);

   Max_SAN : constant := 8;                       --  dNSNames captured per cert
   type Slice_Array is array (1 .. Max_SAN) of Slice;

   --  Civil time packed as YYYYMMDDHHMMSS in one comparable integer (lexicographic
   --  on the fixed-width fields), the form Valid_At compares against.
   subtype Time_64 is Interfaces.Integer_64;
   use type Interfaces.Integer_64;
   function Pack_Time (Year, Month, Day, Hour, Minute, Second : Natural)
                       return Time_64 is
     (((((Time_64 (Year) * 100 + Time_64 (Month)) * 100 + Time_64 (Day)) * 100
        + Time_64 (Hour)) * 100 + Time_64 (Minute)) * 100 + Time_64 (Second))
   with Pre => Year <= 9999 and then Month <= 99 and then Day <= 99
               and then Hour <= 99 and then Minute <= 99 and then Second <= 99;

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
      SAN          : Slice_Array;      --  subjectAltName dNSName entries
      SAN_Count    : Natural := 0;
   end record;

   --  A certificate buffer that leaves headroom for the one-past-the-end indices
   --  the parser forms (dropping a BIT STRING's unused-bits byte, the wildcard
   --  "*." skip, ...).  Real DER certs are a few KiB, nowhere near this bound.
   function Indexable (Cert : Byte_Array) return Boolean is
     (Cert'Last < Natural'Last - 1)
   with Ghost;

   --  A slice is "in" Cert if it is empty or its index range lies within Cert.
   --  (Empty slices carry no position, so they are always in-buffer.)
   function Slice_In (Cert : Byte_Array; S : Slice) return Boolean is
     (Length (S) = 0
      or else (S.First >= Cert'First and then S.Last <= Cert'Last))
   with Ghost;

   --  Every slice a valid Certificate carries lies within Cert, and SAN_Count is
   --  in range.  This is the contract glue of Tier A: Parse establishes it, and
   --  the consumers (Valid_At, Host_Matches, and later Cert_Verify) require it so
   --  that indexing Cert over those slices is provably in-bounds.
   function Well_Formed (Cert : Byte_Array; C : Certificate) return Boolean is
     (C.SAN_Count <= Max_SAN
      and then Slice_In (Cert, C.TBS)
      and then Slice_In (Cert, C.Serial)
      and then Slice_In (Cert, C.Not_Before)
      and then Slice_In (Cert, C.Not_After)
      and then Slice_In (Cert, C.Sig_Alg_OID)
      and then Slice_In (Cert, C.Signature)
      and then Slice_In (Cert, C.RSA_Modulus)
      and then Slice_In (Cert, C.RSA_Exponent)
      and then (for all I in 1 .. C.SAN_Count => Slice_In (Cert, C.SAN (I))))
   with Ghost;

   --  Parse a DER-encoded certificate.  On success Result.Valid is True and the
   --  slices are filled; on any structural problem Result.Valid is False.
   procedure Parse (Cert : Byte_Array; Result : out Certificate)
     with Pre  => Indexable (Cert),
          Post => (if Result.Valid then Well_Formed (Cert, Result));

   --  notBefore <= Now <= notAfter, with Now a Pack_Time value (e.g. derived from
   --  the NTP clock).  False if either validity time fails to parse.
   function Valid_At (Cert : Byte_Array; C : Certificate; Now : Time_64)
                      return Boolean
     with Pre => Well_Formed (Cert, C);

   --  Does any subjectAltName dNSName match Host?  Case-insensitive (ASCII), with a
   --  single leftmost "*" wildcard label (RFC 6125: "*.a.b" matches one label and
   --  only where the remainder has at least two labels).  Host carries no trailing
   --  dot.  (The deprecated subject-CN fallback is intentionally not used.)
   function Host_Matches (Cert : Byte_Array; C : Certificate; Host : String)
                          return Boolean
     with Pre => Indexable (Cert) and then Well_Formed (Cert, C);

end X509;
