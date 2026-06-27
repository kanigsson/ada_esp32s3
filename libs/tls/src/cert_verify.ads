with X509;

--  Certificate signature verification: ties the X.509 parser to the hardware RSA
--  accelerator and SPARKNaCl's SHA-256.  Currently RSASSA-PKCS1-v1.5 with SHA-256
--  (the most common certificate signature); more algorithms can be added alongside.
package Cert_Verify with SPARK_Mode => On is

   --  True iff Signature is a valid RSASSA-PKCS1-v1.5 (SHA-256) signature over TBS
   --  under the RSA public key (Modulus, Exponent) -- each a big-endian byte string
   --  as it appears in a certificate (the modulus may carry a leading 0x00 sign
   --  byte).  Uses the "encode and compare" check (RFC 8017): hash TBS, RSA-recover
   --  the padded block with the public exponent, and compare it byte-for-byte to a
   --  freshly built PKCS#1 block -- so there is no padding to mis-parse.
   --  The byte strings are slices of a (finite) certificate buffer.  Capping
   --  every 'Last just below Natural'Last lets the parser's index arithmetic
   --  (length computation, +1 past-end, the BE<->word conversions) be carried
   --  out without overflow -- exactly the X509.Indexable headroom convention.
   --  TBS must be non-empty (a certificate's signed region always is).
   function RSA_PKCS1_SHA256
     (TBS, Signature, Modulus, Exponent : X509.Byte_Array) return Boolean
   with Pre => TBS'Length >= 1
               and then TBS'Last       < Natural'Last - 1
               and then Signature'Last < Natural'Last - 1
               and then Modulus'Last   < Natural'Last - 1
               and then Exponent'Last  < Natural'Last - 1;

   --  Verify an RSASSA-PSS signature (MGF1 with SHA-256, salt length 32) over
   --  Message under the RSA public key (Modulus, Exponent).  This is the scheme
   --  TLS 1.3 uses for a CertificateVerify made with an RSA key (rsa_pss_rsae_*);
   --  PKCS#1 v1.5 is not allowed there.  True iff the signature verifies.
   function RSA_PSS_SHA256
     (Message, Signature, Modulus, Exponent : X509.Byte_Array) return Boolean
   with Pre => Message'Length >= 1
               and then Message'Last   < Natural'Last - 1
               and then Signature'Last < Natural'Last - 1
               and then Modulus'Last   < Natural'Last - 1
               and then Exponent'Last  < Natural'Last - 1;

end Cert_Verify;
