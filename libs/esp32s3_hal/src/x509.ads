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

   --  Public-key algorithm of the certificate's subject key, and the algorithm the
   --  certificate's issuer used to sign it -- the parser classifies both so the
   --  verifier can dispatch RSA vs ECDSA without re-walking the DER.
   type Key_Algorithm is (Key_RSA, Key_EC_P256, Key_Ed25519, Key_Other);
   type Sig_Algorithm is
     (Sig_RSA_SHA256, Sig_RSA_SHA384, Sig_RSA_SHA512,
      Sig_ECDSA_SHA256, Sig_ECDSA_SHA384, Sig_Ed25519, Sig_Other);

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
      Sig_Kind     : Sig_Algorithm := Sig_Other;  --  classified signatureAlgorithm
      Signature    : Slice;            --  signatureValue (BIT STRING, unused-bits byte dropped)
      Key_Kind     : Key_Algorithm := Key_Other;  --  subject public-key algorithm
      RSA_Modulus  : Slice;            --  SubjectPublicKeyInfo RSA modulus  (big-endian INTEGER)
      RSA_Exponent : Slice;            --  RSA public exponent
      EC_X         : Slice;            --  P-256 public-key affine X (32 bytes) when Key_EC_P256
      EC_Y         : Slice;            --  P-256 public-key affine Y (32 bytes)
      Ed_Pub       : Slice;            --  Ed25519 public key (32 bytes) when Key_Ed25519
      SAN          : Slice_Array;      --  subjectAltName dNSName entries
      SAN_Count    : Natural := 0;

      --  X.509 v3 extension flags the chain validator enforces (RFC 5280
      --  4.2.1.9 basicConstraints, 4.2.1.3 keyUsage, 4.2.1.12 extKeyUsage).
      BC_Present     : Boolean := False;  --  basicConstraints extension present
      Is_CA          : Boolean := False;  --  basicConstraints cA = TRUE
      Path_Len       : Integer := -1;     --  pathLenConstraint (-1 = absent)
      KU_Present     : Boolean := False;  --  keyUsage extension present
      KU_Cert_Sign   : Boolean := False;  --  keyUsage keyCertSign bit (5)
      KU_Digital_Sig : Boolean := False;  --  keyUsage digitalSignature bit (0)
      EKU_Present    : Boolean := False;  --  extendedKeyUsage present
      EKU_Server     : Boolean := False;  --  id-kp-serverAuth (or anyExtendedKeyUsage)
      EKU_Client     : Boolean := False;  --  id-kp-clientAuth (or anyExtendedKeyUsage)
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
   --  the consumers (Valid_At, Host_Matches, Cert_Verify via Chain_Verify) require
   --  it so that indexing Cert over those slices is provably in-bounds.  It covers
   --  every public-key slice the chain validator may dispatch to (RSA, P-256, Ed).
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
      and then Slice_In (Cert, C.EC_X)
      and then Slice_In (Cert, C.EC_Y)
      and then Slice_In (Cert, C.Ed_Pub)
      and then (for all I in 1 .. C.SAN_Count => Slice_In (Cert, C.SAN (I))))
   with Ghost;

   --  Parse a DER-encoded certificate.  On success Result.Valid is True and the
   --  slices are filled; on any structural problem Result.Valid is False.
   --
   --  The Well_Formed postcondition is the contract Chain_Verify / Cert_Verify
   --  build on: every slice a valid certificate carries lies within Cert.  The
   --  parser body proves it (SPARK_Mode On), so the consumers' indexing is in
   --  bounds without any assumption.
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
