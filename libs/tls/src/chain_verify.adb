with Cert_Verify;

package body Chain_Verify is

   --  Does Child's signature verify under Issuer's RSA public key?
   function Sig_OK (Child_Buf : X509.Byte_Array; Child : X509.Certificate;
                    Iss_Buf : X509.Byte_Array; Iss : X509.Certificate)
                    return Boolean is
     (Cert_Verify.RSA_PKCS1_SHA256
        (TBS       => Child_Buf (Child.TBS.First .. Child.TBS.Last),
         Signature => Child_Buf (Child.Signature.First .. Child.Signature.Last),
         Modulus   => Iss_Buf (Iss.RSA_Modulus.First .. Iss.RSA_Modulus.Last),
         Exponent  => Iss_Buf (Iss.RSA_Exponent.First .. Iss.RSA_Exponent.Last)));

   function Validate
     (Chain, Anchors : Cert_List;
      Host           : String;
      Now            : X509.Time_64) return Result
   is
   begin
      if Chain'Length = 0 then
         return Malformed;
      end if;

      --  Leaf: parse and check the host name.
      declare
         LB   : X509.Byte_Array renames Chain (Chain'First).Data.all;
         Leaf : X509.Certificate;
      begin
         X509.Parse (LB, Leaf);
         if not Leaf.Valid then
            return Malformed;
         end if;
         if not X509.Host_Matches (LB, Leaf, Host) then
            return Name_Mismatch;
         end if;
      end;

      --  Each certificate must be in date, and each link must be signed by the
      --  next certificate in the chain.
      for I in Chain'Range loop
         declare
            CB : X509.Byte_Array renames Chain (I).Data.all;
            C  : X509.Certificate;
         begin
            X509.Parse (CB, C);
            if not C.Valid then
               return Malformed;
            end if;
            if not X509.Valid_At (CB, C, Now) then
               return Expired;
            end if;
            if I < Chain'Last then
               declare
                  IB  : X509.Byte_Array renames Chain (I + 1).Data.all;
                  Iss : X509.Certificate;
               begin
                  X509.Parse (IB, Iss);
                  if not Iss.Valid then
                     return Malformed;
                  end if;
                  if not Sig_OK (CB, C, IB, Iss) then
                     return Bad_Signature;
                  end if;
               end;
            end if;
         end;
      end loop;

      --  Anchor the top: its signature must verify under a pinned root key.
      declare
         TB  : X509.Byte_Array renames Chain (Chain'Last).Data.all;
         Top : X509.Certificate;
      begin
         X509.Parse (TB, Top);                  --  re-parse (already known valid)
         for A in Anchors'Range loop
            declare
               AB : X509.Byte_Array renames Anchors (A).Data.all;
               Ac : X509.Certificate;
            begin
               X509.Parse (AB, Ac);
               if Ac.Valid and then Sig_OK (TB, Top, AB, Ac) then
                  return Valid;
               end if;
            end;
         end loop;
      end;
      return Untrusted_Root;
   end Validate;

end Chain_Verify;
