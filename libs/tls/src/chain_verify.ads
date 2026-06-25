with X509;

--  Certificate-chain validation: put the pieces together -- per-link signature
--  verification (Cert_Verify), validity dates and hostname matching (X509) -- and
--  anchor the chain to a pinned set of root certificates.  RSA/SHA-256 signatures
--  only for now (the algorithm Cert_Verify implements).
package Chain_Verify is

   type Result is
     (Valid,
      Malformed,        --  a certificate did not parse (or is not RSA)
      Name_Mismatch,    --  the leaf does not cover the host name
      Expired,          --  a certificate is outside its validity window at Now
      Bad_Signature,    --  a link's signature does not verify under its issuer
      Untrusted_Root);  --  the top of the chain is not signed by a pinned root

   --  A certificate is referenced by its (library-level, aliased) DER bytes, so no
   --  copying and no heap.
   type Cert_Ref  is record
      Data : access constant X509.Byte_Array;
   end record;
   type Cert_List is array (Positive range <>) of Cert_Ref;

   --  Validate an ordered Chain (leaf first, then issuers) for Host at time Now,
   --  requiring the top certificate to be signed by one of the pinned Anchors
   --  (root certificates the device trusts).  Each certificate must be valid at
   --  Now, each link's signature must verify under the next certificate's key, the
   --  leaf must match Host, and the top must be anchored.
   function Validate
     (Chain, Anchors : Cert_List;
      Host           : String;
      Now            : X509.Time_64) return Result;

end Chain_Verify;
