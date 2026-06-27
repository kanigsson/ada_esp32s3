with X509;

--  Certificate-chain validation: put the pieces together -- per-link signature
--  verification (Cert_Verify), validity dates and hostname matching (X509) -- and
--  anchor the chain to a pinned set of root certificates.  RSA/SHA-256 signatures
--  only for now (the algorithm Cert_Verify implements).
package Chain_Verify with SPARK_Mode => On is

   type Result is
     (Valid,
      Malformed,        --  a certificate did not parse (or is not RSA)
      Name_Mismatch,    --  the leaf does not cover the host name
      Expired,          --  a certificate is outside its validity window at Now
      Bad_Signature,    --  a link's signature does not verify under its issuer
      Untrusted_Root);  --  the top of the chain is not signed by a pinned root

   --  A certificate is referenced by its (library-level, aliased) DER bytes, so no
   --  copying and no heap.  The reference is a *named* access-to-constant type
   --  (SPARK forbids an anonymous access type as a record component).
   type Cert_Data is access constant X509.Byte_Array;
   type Cert_Ref  is record
      Data : Cert_Data;
   end record;
   type Cert_List is array (Positive range <>) of Cert_Ref;

   --  Every certificate buffer in a list is present and small enough to parse:
   --  non-null, and Indexable (one-past-end headroom, X509.Parse's precondition).
   --  Real DER buffers are a few KiB, so this always holds; it lets the validator
   --  dereference and Parse each reference without a run-time error.
   function All_Parsable (L : Cert_List) return Boolean is
     (for all I in L'Range =>
        L (I).Data /= null and then X509.Indexable (L (I).Data.all))
   with Ghost;

   --  Validate an ordered Chain (leaf first, then issuers) for Host at time Now,
   --  requiring the top certificate to be signed by one of the pinned Anchors
   --  (root certificates the device trusts).  Each certificate must be valid at
   --  Now, each link's signature must verify under the next certificate's key, the
   --  leaf must match Host, and the top must be anchored.
   function Validate
     (Chain, Anchors : Cert_List;
      Host           : String;
      Now            : X509.Time_64) return Result
   with Pre => All_Parsable (Chain) and then All_Parsable (Anchors);

end Chain_Verify;
