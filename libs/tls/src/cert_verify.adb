with ESP32S3.RSA;
with SPARKNaCl;
with SPARKNaCl.Hashing.SHA256;
with SPARKNaCl.Hashing.SHA384;
with SPARKNaCl.Hashing.SHA512;
with SPARKNaCl.Sign;
with P256;

package body Cert_Verify with SPARK_Mode => On is

   use type X509.U8;
   subtype U8 is X509.U8;
   subtype Byte_Array is X509.Byte_Array;

   --  DigestInfo prefixes (DER of the digest algorithm + the OCTET STRING header)
   --  that precede the hash in a PKCS#1 v1.5 block -- one per SHA variant.
   DI_SHA256 : constant Byte_Array :=
     (16#30#, 16#31#, 16#30#, 16#0D#, 16#06#, 16#09#, 16#60#, 16#86#, 16#48#,
      16#01#, 16#65#, 16#03#, 16#04#, 16#02#, 16#01#, 16#05#, 16#00#, 16#04#, 16#20#);
   DI_SHA384 : constant Byte_Array :=
     (16#30#, 16#41#, 16#30#, 16#0D#, 16#06#, 16#09#, 16#60#, 16#86#, 16#48#,
      16#01#, 16#65#, 16#03#, 16#04#, 16#02#, 16#02#, 16#05#, 16#00#, 16#04#, 16#30#);
   DI_SHA512 : constant Byte_Array :=
     (16#30#, 16#51#, 16#30#, 16#0D#, 16#06#, 16#09#, 16#60#, 16#86#, 16#48#,
      16#01#, 16#65#, 16#03#, 16#04#, 16#02#, 16#03#, 16#05#, 16#00#, 16#04#, 16#40#);

   --  Big-endian bytes -> little-endian 32-bit words (word 0 least significant).
   --  W may hold more words than B fills; the high words are zeroed.  At most
   --  128 words (the RSA accelerator's ceiling) keeps the index arithmetic in
   --  range.  Iterating over W'Range makes the full initialization of W obvious.
   procedure BE_To_Words (B : Byte_Array; W : out ESP32S3.RSA.Word_Array)
     with Pre => W'Length <= 128 and then B'Last < Natural'Last - 1
   is
      use ESP32S3.RSA;
      Len : constant Natural := B'Length;
   begin
      for J in W'Range loop
         --  W'Length <= 128, so the 0-based word index stays <= 127; this lets
         --  the prover bound Base = 4 * Idx and the Base + k byte offsets below.
         pragma Loop_Invariant (J - W'First <= 127);
         declare
            Idx  : constant Natural := J - W'First;       --  0-based word #, <= 127
            Base : constant Natural := 4 * Idx;           --  LSB byte offset, <= 508
            Acc  : Word := 0;
         begin
            --  Word Idx covers the bytes Base .. Base + 3 counted back from the
            --  LSB end of B (which is B'Last).  All arithmetic stays in Natural:
            --  Base + k < Len guarantees B'Last - Base - k >= B'First.
            if Base     < Len then Acc := Acc + Word (B (B'Last - Base)); end if;
            if Base + 1 < Len then Acc := Acc + Word (B (B'Last - Base - 1)) * 16#100#; end if;
            if Base + 2 < Len then Acc := Acc + Word (B (B'Last - Base - 2)) * 16#1_0000#; end if;
            if Base + 3 < Len then Acc := Acc + Word (B (B'Last - Base - 3)) * 16#100_0000#; end if;
            W (J) := Acc;
         end;
      end loop;
   end BE_To_Words;

   --  Little-endian words -> big-endian bytes.  EM must be exactly 4 * W'Length
   --  bytes; the (others => 0) prefill discharges full initialization despite the
   --  strided writes (the loop overwrites every byte anyway).
   procedure Words_To_BE (W : ESP32S3.RSA.Word_Array; EM : out Byte_Array)
     with Pre => W'Length <= 128 and then EM'Length = 4 * W'Length
   is
      use ESP32S3.RSA;
   begin
      EM := (others => 0);
      for J in W'Range loop
         declare
            Idx : constant Natural := J - W'First;
            Wd  : constant Word    := W (J);
            P   : constant Natural := EM'Last - 4 * Idx;       --  LSB of word J
         begin
            EM (P)     := U8 (Wd mod 16#100#);
            EM (P - 1) := U8 ((Wd / 16#100#)     mod 16#100#);
            EM (P - 2) := U8 ((Wd / 16#1_0000#)  mod 16#100#);
            EM (P - 3) := U8 ((Wd / 16#100_0000#) mod 16#100#);
         end;
      end loop;
   end Words_To_BE;

   --  Big-endian SHA digests of Data, as a fixed-length Byte_Array (index 0 ..).
   function SHA256_BA (Data : Byte_Array) return Byte_Array
     with Pre  => Data'Length >= 1 and then Data'Last < Natural'Last - 1,
          Post => SHA256_BA'Result'First = 0
                  and then SHA256_BA'Result'Last = 31
   is
      Msg : SPARKNaCl.Byte_Seq (0 .. SPARKNaCl.N32 (Data'Length - 1));
      Dg  : SPARKNaCl.Hashing.SHA256.Digest;
      R   : Byte_Array (0 .. 31);
   begin
      for I in Msg'Range loop
         Msg (I) := SPARKNaCl.Byte (Data (Data'First + Natural (I)));
      end loop;
      Dg := SPARKNaCl.Hashing.SHA256.Hash (Msg);
      for I in R'Range loop
         R (I) := U8 (Dg (SPARKNaCl.Index_32 (I)));
      end loop;
      return R;
   end SHA256_BA;

   function SHA384_BA (Data : Byte_Array) return Byte_Array
     with Pre  => Data'Length >= 1 and then Data'Last < Natural'Last - 1,
          Post => SHA384_BA'Result'First = 0
                  and then SHA384_BA'Result'Last = 47
   is
      Msg : SPARKNaCl.Byte_Seq (0 .. SPARKNaCl.N32 (Data'Length - 1));
      Dg  : SPARKNaCl.Hashing.SHA384.Digest;
      R   : Byte_Array (0 .. 47);
   begin
      for I in Msg'Range loop
         Msg (I) := SPARKNaCl.Byte (Data (Data'First + Natural (I)));
      end loop;
      Dg := SPARKNaCl.Hashing.SHA384.Hash (Msg);
      for I in R'Range loop
         R (I) := U8 (Dg (SPARKNaCl.Index_48 (I)));
      end loop;
      return R;
   end SHA384_BA;

   function SHA512_BA (Data : Byte_Array) return Byte_Array
     with Pre  => Data'Length >= 1 and then Data'Last < Natural'Last - 1,
          Post => SHA512_BA'Result'First = 0
                  and then SHA512_BA'Result'Last = 63
   is
      Msg : SPARKNaCl.Byte_Seq (0 .. SPARKNaCl.N32 (Data'Length - 1));
      Dg  : SPARKNaCl.Hashing.SHA512.Digest;
      R   : Byte_Array (0 .. 63);
   begin
      for I in Msg'Range loop
         Msg (I) := SPARKNaCl.Byte (Data (Data'First + Natural (I)));
      end loop;
      Dg := SPARKNaCl.Hashing.SHA512.Hash (Msg);
      for I in R'Range loop
         R (I) := U8 (Dg (SPARKNaCl.Index_64 (I)));
      end loop;
      return R;
   end SHA512_BA;

   --  RSASSA-PKCS1-v1.5 verify with a precomputed digest Hash and its matching
   --  DigestInfo prefix DI: recover EM = Signature^Exponent mod Modulus and
   --  constant-time compare it to 00 01 FF..FF 00 || DI || Hash.  The block is
   --  built at fixed offsets (the 0x00 separator after the FF padding is left by
   --  the prefill), so every Want write is provably in [0 .. K - 1].
   function RSA_PKCS1_Core
     (Hash, DI, Signature, Modulus, Exponent : Byte_Array) return Boolean
     with Pre => Hash'Length <= 64 and then DI'Length <= 32
                 and then Hash'Last      < Natural'Last - 1
                 and then DI'Last        < Natural'Last - 1
                 and then Signature'Last < Natural'Last - 1
                 and then Modulus'Last   < Natural'Last - 1
                 and then Exponent'Last  < Natural'Last - 1
   is
      M_First : Natural;
   begin
      --  A zero-length modulus can never carry a signature; reject it up front so
      --  that Modulus'First below is a valid (non-negative) index -- for an empty
      --  array the prover only knows the bounds in the index base type.
      if Modulus'Length = 0 then
         return False;
      end if;
      --  Drop a single leading 0x00 (DER positive-sign byte) from the modulus.
      M_First := Modulus'First;
      if Modulus (Modulus'First) = 0 then
         M_First := Modulus'First + 1;
      end if;
      declare
         K : constant Natural :=
           (if Modulus'Last >= M_First then Modulus'Last - M_First + 1 else 0);
      begin
         --  k a whole number of words, RSA-sized, and big enough for the block
         --  (00 01 || >=8 FF || 00 || DigestInfo || hash).
         if K = 0 or else K mod 4 /= 0 or else K > 512
           or else Signature'Length /= K
           or else K < 11 + DI'Length + Hash'Length
         then
            return False;
         end if;
         declare
            use ESP32S3.RSA;
            N             : constant Natural := K / 4;
            Nm, Sg, Ex, Z : Word_Array (0 .. N - 1);
            Ok            : Boolean;
            EM            : Byte_Array (0 .. K - 1);
            Want          : Byte_Array (0 .. K - 1) := (others => 0);
            PS_Len        : constant Natural := K - 3 - (DI'Length + Hash'Length);
            Diff          : U8 := 0;
         begin
            BE_To_Words (Modulus (M_First .. Modulus'Last), Nm);
            BE_To_Words (Signature, Sg);
            BE_To_Words (Exponent, Ex);
            Mod_Exp (Sg, Ex, Nm, Z, Ok);          --  EM = sig^e mod n
            if not Ok then
               return False;
            end if;
            Words_To_BE (Z, EM);

            --  Build the expected block: 00 01 FF..FF 00 || DigestInfo || hash.
            --  The 0x00 separator at index 2 + PS_Len is left by the prefill.
            Want (0) := 16#00#;
            Want (1) := 16#01#;
            for I in 0 .. PS_Len - 1 loop
               Want (2 + I) := 16#FF#;
            end loop;
            for I in 0 .. DI'Length - 1 loop
               Want (3 + PS_Len + I) := DI (DI'First + I);
            end loop;
            for I in 0 .. Hash'Length - 1 loop
               Want (3 + PS_Len + DI'Length + I) := Hash (Hash'First + I);
            end loop;

            for I in EM'Range loop                --  constant-time compare
               Diff := Diff or (EM (I) xor Want (I));
            end loop;
            return Diff = 0;
         end;
      end;
   end RSA_PKCS1_Core;

   function RSA_PKCS1_SHA256 (TBS, Signature, Modulus, Exponent : Byte_Array)
      return Boolean is
     (RSA_PKCS1_Core (SHA256_BA (TBS), DI_SHA256, Signature, Modulus, Exponent));

   function RSA_PKCS1_SHA384 (TBS, Signature, Modulus, Exponent : Byte_Array)
      return Boolean is
     (RSA_PKCS1_Core (SHA384_BA (TBS), DI_SHA384, Signature, Modulus, Exponent));

   function RSA_PKCS1_SHA512 (TBS, Signature, Modulus, Exponent : Byte_Array)
      return Boolean is
     (RSA_PKCS1_Core (SHA512_BA (TBS), DI_SHA512, Signature, Modulus, Exponent));

   ---------------------------------------------------------------------------
   --  RSASSA-PSS (MGF1-SHA-256, salt length 32).  SHA256_BA is defined above.
   ---------------------------------------------------------------------------

   --  MGF1 with SHA-256.  Mask_Len is small in practice (<= the modulus size),
   --  bounded here so the Pos arithmetic cannot overflow; Seed is a hash (32
   --  bytes), comfortably within the headroom bound.
   function MGF1 (Seed : Byte_Array; Mask_Len : Natural) return Byte_Array
     with Pre  => Mask_Len <= 4096 and then Seed'Last < Natural'Last - 6,
          Post => MGF1'Result'First = 0
                  and then MGF1'Result'Length = Mask_Len
   is
      R   : Byte_Array (0 .. Mask_Len - 1) := (others => 0);
      Pos : Natural := 0;
      Cnt : Natural := 0;
   begin
      while Pos < Mask_Len loop
         pragma Loop_Invariant (Pos <= Mask_Len + 31);
         --  Pos and Cnt advance in lock-step (Pos += 32, Cnt += 1 each block),
         --  so Cnt = Pos / 32 stays small (<= 128) -- Cnt + 1 cannot overflow.
         pragma Loop_Invariant (Pos = 32 * Cnt);
         pragma Loop_Variant (Increases => Pos);
         declare
            In_Buf : Byte_Array (0 .. Seed'Length + 3) := (others => 0);
            H      : Byte_Array (0 .. 31);
         begin
            for I in 0 .. Seed'Length - 1 loop
               In_Buf (I) := Seed (Seed'First + I);
            end loop;
            In_Buf (Seed'Length)     := U8 ((Cnt / 16#100_0000#) mod 256);
            In_Buf (Seed'Length + 1) := U8 ((Cnt / 16#1_0000#) mod 256);
            In_Buf (Seed'Length + 2) := U8 ((Cnt / 16#100#) mod 256);
            In_Buf (Seed'Length + 3) := U8 (Cnt mod 256);
            H := SHA256_BA (In_Buf);
            for I in 0 .. 31 loop
               if Pos + I < Mask_Len then R (Pos + I) := H (I); end if;
            end loop;
            Pos := Pos + 32;
            Cnt := Cnt + 1;
         end;
      end loop;
      return R;
   end MGF1;

   function RSA_PSS_SHA256 (Message, Signature, Modulus, Exponent : Byte_Array)
      return Boolean
   is
      M_First : Natural;
   begin
      --  Reject a zero-length modulus up front: it makes Modulus'First below a
      --  valid non-negative index.
      if Modulus'Length = 0 then
         return False;
      end if;
      M_First := Modulus'First;
      if Modulus (Modulus'First) = 0 then
         M_First := Modulus'First + 1;
      end if;
      declare
         K : constant Natural :=
           (if Modulus'Last >= M_First then Modulus'Last - M_First + 1 else 0);
      begin
         if K = 0 or else K mod 4 /= 0 or else K > 512
           or else Signature'Length /= K
         then
            return False;
         end if;
         declare
            use ESP32S3.RSA;
            N             : constant Natural := K / 4;
            Nm, Sg, Ex, Z : Word_Array (0 .. N - 1);
            Ok            : Boolean;
            EMb           : Byte_Array (0 .. K - 1);
            hLen          : constant := 32;
            sLen          : constant := 32;
            Topb          : Natural := 0;
            Top           : constant U8 := Modulus (M_First);
         begin
            BE_To_Words (Modulus (M_First .. Modulus'Last), Nm);
            BE_To_Words (Signature, Sg);
            BE_To_Words (Exponent, Ex);
            Mod_Exp (Sg, Ex, Nm, Z, Ok);          --  EM = sig^e mod n  (k bytes BE)
            if not Ok then
               return False;
            end if;
            Words_To_BE (Z, EMb);

            --  Bit length of the modulus' top byte (0 .. 8), highest set bit + 1.
            for Bit in reverse 0 .. 7 loop
               if (Top and U8 (2 ** Bit)) /= 0 then
                  Topb := Bit + 1;
                  exit;
               end if;
            end loop;
            pragma Assert (Topb <= 8);

            declare
               ModBits  : constant Natural := (K - 1) * 8 + Topb;
               EmBits   : constant Natural := ModBits - 1;
               EmLen    : constant Natural := (EmBits + 7) / 8;
               LeadBits : constant Natural := 8 * EmLen - EmBits;
               EM_Off   : constant Natural := K - EmLen;
            begin
               pragma Assert (EmLen <= K);
               pragma Assert (LeadBits <= 7);
               if EmLen < hLen + sLen + 2 or else EM_Off + EmLen /= K then
                  return False;
               end if;
               if EMb (EM_Off + EmLen - 1) /= 16#BC# then         --  trailer
                  return False;
               end if;
               if LeadBits > 0
                 and then (EMb (EM_Off) and U8 (16#100# - 2 ** (8 - LeadBits))) /= 0
               then
                  return False;
               end if;

               declare
                  DBLen : constant Natural := EmLen - hLen - 1;
                  ZeroN : constant Natural := EmLen - hLen - sLen - 2;
                  mHash : constant Byte_Array := SHA256_BA (Message);
                  H     : Byte_Array (0 .. hLen - 1);
               begin
                  for I in 0 .. hLen - 1 loop
                     H (I) := EMb (EM_Off + DBLen + I);
                  end loop;
                  declare
                     DBMask : constant Byte_Array := MGF1 (H, DBLen);
                     DB     : Byte_Array (0 .. DBLen - 1);
                     Salt   : Byte_Array (0 .. sLen - 1);
                     Mp     : Byte_Array (0 .. 8 + hLen + sLen - 1) := (others => 0);
                     Hp     : Byte_Array (0 .. hLen - 1);
                     Good   : Boolean := True;
                  begin
                     for I in DB'Range loop
                        DB (I) := EMb (EM_Off + I) xor DBMask (I);
                     end loop;
                     if LeadBits > 0 then
                        DB (0) := DB (0) and U8 (2 ** (8 - LeadBits) - 1);
                     end if;
                     for I in 0 .. ZeroN - 1 loop
                        if DB (I) /= 0 then Good := False; end if;
                     end loop;
                     if DB (ZeroN) /= 16#01# then            --  PS || 0x01 || salt
                        Good := False;
                     end if;
                     if not Good then
                        return False;
                     end if;
                     for I in 0 .. sLen - 1 loop
                        Salt (I) := DB (DBLen - sLen + I);
                     end loop;
                     --  M' = (0x00)*8 || mHash || salt ; H' = SHA-256(M')
                     for I in 0 .. hLen - 1 loop Mp (8 + I) := mHash (I); end loop;
                     for I in 0 .. sLen - 1 loop Mp (8 + hLen + I) := Salt (I); end loop;
                     Hp := SHA256_BA (Mp);
                     for I in 0 .. hLen - 1 loop
                        if Hp (I) /= H (I) then
                           return False;
                        end if;
                     end loop;
                     return True;
                  end;
               end;
            end;
         end;
      end;
   end RSA_PSS_SHA256;

   ---------------------------------------------------------------------------
   --  ECDSA / P-256 and Ed25519.  These bottom out in the pure-Ada P256 and
   --  SPARKNaCl.Sign primitives; their bodies are SPARK_Mode (Off) -- the same
   --  out-of-scope boundary as the silicon RSA accelerator (proving the elliptic
   --  curve / EdDSA group laws is not in Tier A's functional scope).
   ---------------------------------------------------------------------------

   --  SHA-384 of Data, left-truncated to 32 bytes (ECDSA uses the leftmost
   --  256 bits of the digest with a 256-bit group order).
   function SHA384_BA_32 (Data : Byte_Array) return Byte_Array
     with SPARK_Mode => Off
   is
      Msg : SPARKNaCl.Byte_Seq (0 .. SPARKNaCl.N32 (Data'Length - 1));
      Dg  : SPARKNaCl.Hashing.SHA384.Digest;
      R   : Byte_Array (0 .. 31);
   begin
      for I in 0 .. Data'Length - 1 loop
         Msg (SPARKNaCl.N32 (I)) := SPARKNaCl.Byte (Data (Data'First + I));
      end loop;
      Dg := SPARKNaCl.Hashing.SHA384.Hash (Msg);
      for I in 0 .. 31 loop
         R (I) := U8 (Dg (SPARKNaCl.Index_32 (I)));
      end loop;
      return R;
   end SHA384_BA_32;

   function To_P256 (B : Byte_Array) return P256.Bytes_32
     with SPARK_Mode => Off
   is
      R : P256.Bytes_32;
   begin
      for I in 0 .. 31 loop
         R (I) := P256.Byte (B (B'First + I));
      end loop;
      return R;
   end To_P256;

   --  Read a DER INTEGER at Pos (tag 0x02), big-endian, into a 32-byte right-aligned
   --  value (leading zero sign byte dropped, short values left-padded).  Advances Pos.
   procedure DER_Int (Buf : Byte_Array; Pos : in out Natural; Last : Natural;
                      Out32 : out P256.Bytes_32; Ok : in out Boolean)
     with SPARK_Mode => Off
   is
      Len, First, Vlen : Natural;
   begin
      Out32 := (others => 0);
      if not Ok or else Pos + 1 > Last or else Buf (Pos) /= 16#02# then
         Ok := False;  return;
      end if;
      Len := Natural (Buf (Pos + 1));               --  r, s < 128 bytes => short form
      Pos := Pos + 2;
      if Len = 0 or else Pos + Len - 1 > Last then
         Ok := False;  return;
      end if;
      First := Pos;  Vlen := Len;
      while Vlen > 0 and then Buf (First) = 0 loop   --  drop leading zero bytes
         First := First + 1;  Vlen := Vlen - 1;
      end loop;
      if Vlen > 32 then
         Ok := False;  return;
      end if;
      for I in 0 .. Vlen - 1 loop
         Out32 (32 - Vlen + I) := P256.Byte (Buf (First + I));
      end loop;
      Pos := Pos + Len;
   end DER_Int;

   --  Verify ECDSA(SHA-256/384)/P-256 of Hash32 with signature Sig_DER under
   --  (Pub_X, Pub_Y).  Sig_DER = SEQUENCE { r INTEGER, s INTEGER }.
   function ECDSA_Core (Hash32 : Byte_Array; Sig_DER, Pub_X, Pub_Y : Byte_Array)
                        return Boolean
     with SPARK_Mode => Off
   is
      Pos    : Natural;
      Ok     : Boolean := True;
      R32, S32 : P256.Bytes_32;
   begin
      if Sig_DER'Length < 8 or else Pub_X'Length /= 32 or else Pub_Y'Length /= 32
        or else Sig_DER (Sig_DER'First) /= 16#30#
      then
         return False;
      end if;
      Pos := Sig_DER'First + 2;                      --  past SEQUENCE tag + length
      DER_Int (Sig_DER, Pos, Sig_DER'Last, R32, Ok);
      DER_Int (Sig_DER, Pos, Sig_DER'Last, S32, Ok);
      if not Ok then
         return False;
      end if;
      return P256.Verify (To_P256 (Pub_X), To_P256 (Pub_Y), To_P256 (Hash32), R32, S32);
   end ECDSA_Core;

   function ECDSA_P256_SHA256
     (Message, Sig_DER, Pub_X, Pub_Y : X509.Byte_Array) return Boolean
     with SPARK_Mode => Off
   is
   begin
      return ECDSA_Core (SHA256_BA (Message), Sig_DER, Pub_X, Pub_Y);
   end ECDSA_P256_SHA256;

   function ECDSA_P256_SHA384
     (Message, Sig_DER, Pub_X, Pub_Y : X509.Byte_Array) return Boolean
     with SPARK_Mode => Off
   is
   begin
      return ECDSA_Core (SHA384_BA_32 (Message), Sig_DER, Pub_X, Pub_Y);
   end ECDSA_P256_SHA384;

   --  Detached verify: NaCl exposes the combined form (signature || message), so
   --  reconstruct SM = Signature || Message, run Open (which cryptographically
   --  verifies), and confirm it recovered exactly Message.
   function Ed25519_Verify (Message, Signature, Pub_Key : X509.Byte_Array)
                            return Boolean
     with SPARK_Mode => Off
   is
      use type SPARKNaCl.I32;
      use type SPARKNaCl.Byte;
      PKB : SPARKNaCl.Bytes_32;
      PK  : SPARKNaCl.Sign.Signing_PK;
   begin
      if Signature'Length /= 64 or else Pub_Key'Length /= 32
        or else Message'Length = 0
      then
         return False;
      end if;
      for I in 0 .. 31 loop
         PKB (SPARKNaCl.Index_32 (I)) := SPARKNaCl.Byte (Pub_Key (Pub_Key'First + I));
      end loop;
      SPARKNaCl.Sign.PK_From_Bytes (PKB, PK);

      declare
         Total  : constant Natural := 64 + Message'Length;
         SM     : SPARKNaCl.Byte_Seq (0 .. SPARKNaCl.N32 (Total - 1));
         M      : SPARKNaCl.Byte_Seq (0 .. SPARKNaCl.N32 (Total - 1));
         Status : Boolean;
         MLen   : SPARKNaCl.I32;
      begin
         for I in 0 .. 63 loop
            SM (SPARKNaCl.N32 (I)) := SPARKNaCl.Byte (Signature (Signature'First + I));
         end loop;
         for I in 0 .. Message'Length - 1 loop
            SM (SPARKNaCl.N32 (64 + I)) :=
              SPARKNaCl.Byte (Message (Message'First + I));
         end loop;
         SPARKNaCl.Sign.Open (M, Status, MLen, SM, PK);
         if not Status or else MLen /= SPARKNaCl.I32 (Message'Length) then
            return False;
         end if;
         for I in 0 .. Message'Length - 1 loop
            if M (SPARKNaCl.N32 (I)) /= SPARKNaCl.Byte (Message (Message'First + I))
            then
               return False;
            end if;
         end loop;
         return True;
      end;
   end Ed25519_Verify;

end Cert_Verify;
