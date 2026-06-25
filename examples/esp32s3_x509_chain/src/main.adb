--  X.509 certificate-chain validation: a leaf signed by a CA, anchored to the
--  pinned CA root.  Exercises per-link signature verification, validity, hostname
--  matching and the trust anchor -- the policy around the crypto we already have.
with Ada.Real_Time; use Ada.Real_Time;
with X509;
with Chain_Verify;  use Chain_Verify;
with Chain_Certs;    use Chain_Certs;
with ESP32S3.RNG;
with ESP32S3.Log;    use ESP32S3.Log;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   Leaf  : constant Cert_Ref := (Data => Leaf_DER'Access);
   CA    : constant Cert_Ref := (Data => CA_DER'Access);
   Other : constant Cert_Ref := (Data => Other_DER'Access);

   T2025 : constant X509.Time_64 := X509.Pack_Time (2025, 6, 1, 12, 0, 0);
   T2050 : constant X509.Time_64 := X509.Pack_Time (2050, 1, 1, 0, 0, 0);
   Host  : constant String := "test.example.com";

   procedure Check (Name : String; Got, Want : Result) is
   begin
      Put_Line ("[chain] " & Name & " : "
                & (if Got = Want then "PASS" else "FAIL (" & Result'Image (Got) & ")"));
   end Check;
begin
   delay until Clock + Milliseconds (200);
   ESP32S3.RNG.Enable_Entropy_Source;
   Put_Line ("[chain] certificate-chain validation (leaf <- CA, pinned root)");

   Check ("leaf+CA, pinned CA",   Validate ((Leaf, CA),   (1 => CA),    Host, T2025), Valid);
   Check ("leaf only, anchor CA", Validate ((1 => Leaf),  (1 => CA),    Host, T2025), Valid);
   Check ("wrong hostname",       Validate ((Leaf, CA),   (1 => CA),    "evil.example.com", T2025), Name_Mismatch);
   Check ("expired (2050)",       Validate ((Leaf, CA),   (1 => CA),    Host, T2050), Expired);
   Check ("broken link",          Validate ((Leaf, Leaf), (1 => CA),    Host, T2025), Bad_Signature);
   Check ("untrusted root",       Validate ((Leaf, CA),   (1 => Other), Host, T2025), Untrusted_Root);
   Put_Line ("[chain] done");

   loop delay until Clock + Seconds (3600); end loop;
end Main;
