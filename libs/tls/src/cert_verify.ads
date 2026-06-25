with X509;

--  Certificate signature verification: ties the X.509 parser to the hardware RSA
--  accelerator and SPARKNaCl's SHA-256.  Currently RSASSA-PKCS1-v1.5 with SHA-256
--  (the most common certificate signature); more algorithms can be added alongside.
package Cert_Verify is

   --  True iff Signature is a valid RSASSA-PKCS1-v1.5 (SHA-256) signature over TBS
   --  under the RSA public key (Modulus, Exponent) -- each a big-endian byte string
   --  as it appears in a certificate (the modulus may carry a leading 0x00 sign
   --  byte).  Uses the "encode and compare" check (RFC 8017): hash TBS, RSA-recover
   --  the padded block with the public exponent, and compare it byte-for-byte to a
   --  freshly built PKCS#1 block -- so there is no padding to mis-parse.
   function RSA_PKCS1_SHA256
     (TBS, Signature, Modulus, Exponent : X509.Byte_Array) return Boolean;

end Cert_Verify;
