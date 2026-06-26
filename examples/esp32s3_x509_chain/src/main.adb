--  X.509 certificate-chain validation on the bare-metal ESP32-S3 (no FreeRTOS,
--  no IDF)
--  =====================================================================
--  What it demonstrates:
--    The trust *policy* layered on top of the crypto we already have -- a leaf
--    certificate signed by a CA, anchored to a pinned CA root.  Each case feeds
--    Chain_Verify.Validate an ordered chain (leaf first), a set of pinned trust
--    anchors, a host name and a wall-clock time, and asserts the verdict.
--    Between them the six cases exercise every distinct Result the validator can
--    return: a good chain (Valid), the leaf alone re-anchored to its issuer
--    (Valid), a host-name miss (Name_Mismatch), evaluation past the validity
--    window (Expired), a forged link (Bad_Signature) and an unpinned root
--    (Untrusted_Root).
--
--  Build & run:  ./x run esp32s3_x509_chain
--    Runs under the embedded profile (build.sh sets ESP32S3_RTS_PROFILE=embedded).
--
--  Output:
--    A banner, then one "[chain] <name> : PASS" line per case (the verdict
--    matched what was expected), then "[chain] done".  A mismatch prints
--    "FAIL (<actual Result>)" instead.  The board then idles forever.
--
--  Hardware:  none (self-contained; the test certificates are embedded).
with Ada.Real_Time; use Ada.Real_Time;
with X509;
with Chain_Verify;  use Chain_Verify;
with Chain_Certs;    use Chain_Certs;
with ESP32S3.RNG;
with ESP32S3.Log;    use ESP32S3.Log;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   --  The three embedded test certificates, referenced by their library-level DER
   --  bytes (see Chain_Certs for the legend and provenance).
   Leaf  : constant Cert_Ref := (Data => Leaf_DER'Access);   --  CN=test.example.com
   CA    : constant Cert_Ref := (Data => CA_DER'Access);     --  CN=Test Root CA (issues Leaf)
   Other : constant Cert_Ref := (Data => Other_DER'Access);  --  CN=Unrelated CA (a different, unpinned root)

   --  Evaluation times (UTC, packed as YYYYMMDDhhmmss).  All three certificates
   --  are valid 2020..2049, so Within_Window evaluates inside the window, while
   --  Past_Window is deliberately past notAfter to force the Expired verdict.
   Within_Window : constant X509.Time_64 := X509.Pack_Time (2025, 6, 1, 12, 0, 0);
   Past_Window   : constant X509.Time_64 := X509.Pack_Time (2050, 1, 1, 0, 0, 0);

   --  The host the leaf is expected to cover (its CN and its only SAN).
   Host : constant String := "test.example.com";

   --  Let the runtime and console settle before the first line of output.
   Console_Settle : constant Time_Span := Milliseconds (200);

   --  After the self-test the example has nothing left to do; park the core in a
   --  long idle delay rather than busy-looping.
   Idle_Period : constant Time_Span := Seconds (3600);

   procedure Check (Name : String; Got, Want : Result) is
   begin
      Put_Line ("[chain] " & Name & " : "
                & (if Got = Want then "PASS" else "FAIL (" & Result'Image (Got) & ")"));
   end Check;
begin
   delay until Clock + Console_Settle;

   --  Chain_Verify's RSA signature checks draw from the hardware RNG (blinding);
   --  arm the entropy source before the first Validate call.
   ESP32S3.RNG.Enable_Entropy_Source;
   Put_Line ("[chain] certificate-chain validation (leaf <- CA, pinned root)");

   --  Positive: full leaf<-CA chain, CA pinned as the trust anchor.
   Check ("leaf+CA, pinned CA",   Validate ((Leaf, CA),   (1 => CA),    Host, Within_Window), Valid);
   --  Positive: leaf alone is enough when its issuer is itself the pinned anchor.
   Check ("leaf only, anchor CA", Validate ((1 => Leaf),  (1 => CA),    Host, Within_Window), Valid);
   --  Negative: leaf does not cover this host name.
   Check ("wrong hostname",       Validate ((Leaf, CA),   (1 => CA),    "evil.example.com", Within_Window), Name_Mismatch);
   --  Negative: evaluated past the certificates' validity window.
   Check ("expired (2050)",       Validate ((Leaf, CA),   (1 => CA),    Host, Past_Window), Expired);
   --  Negative: leaf<-leaf is a forged link; the second cert did not sign the first.
   Check ("broken link",          Validate ((Leaf, Leaf), (1 => CA),    Host, Within_Window), Bad_Signature);
   --  Negative: the chain's root is not among the pinned anchors.
   Check ("untrusted root",       Validate ((Leaf, CA),   (1 => Other), Host, Within_Window), Untrusted_Root);
   Put_Line ("[chain] done");

   loop
      delay until Clock + Idle_Period;
   end loop;
end Main;
