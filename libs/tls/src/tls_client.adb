with Ada.Streams;            use Ada.Streams;
with ESP32S3.RNG;
with SPARKNaCl;
with SPARKNaCl.Scalar;

package body TLS_Client is

   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_16;
   use GNAT.Sockets;

   --  Record content types and handshake message types.
   CT_Change_Cipher_Spec : constant U8 := 20;
   CT_Alert              : constant U8 := 21;
   CT_Handshake          : constant U8 := 22;
   HS_Client_Hello       : constant U8 := 1;
   HS_Server_Hello       : constant U8 := 2;

   ---------------------------------------------------------------------------
   --  X25519 key pair (SPARKNaCl, seeded from the hardware RNG).
   ---------------------------------------------------------------------------

   function To_B32 (B : Key32) return SPARKNaCl.Bytes_32 is
      R : SPARKNaCl.Bytes_32;
   begin
      for I in 0 .. 31 loop
         R (SPARKNaCl.Index_32 (I)) := SPARKNaCl.Byte (B (I));
      end loop;
      return R;
   end To_B32;

   function From_B32 (B : SPARKNaCl.Bytes_32) return Key32 is
      R : Key32;
   begin
      for I in 0 .. 31 loop
         R (I) := U8 (B (SPARKNaCl.Index_32 (I)));
      end loop;
      return R;
   end From_B32;

   procedure Make_Key_Pair (S : in out Session) is
      Rnd : ESP32S3.RNG.Byte_Array (0 .. 31);
   begin
      ESP32S3.RNG.Fill (Rnd);
      for I in 0 .. 31 loop
         S.Priv (I) := U8 (Rnd (I));
      end loop;
      S.Pub := From_B32 (SPARKNaCl.Scalar.Mult_Base (To_B32 (S.Priv)));
   end Make_Key_Pair;

   ---------------------------------------------------------------------------
   --  Byte buffer builder (for the outgoing ClientHello).
   ---------------------------------------------------------------------------

   type Builder is record
      Data : Byte_Array (0 .. 2047);
      Len  : Natural := 0;
   end record;

   --  One handshake at a time, so keep the big buffers in static scratch rather
   --  than on the (limited) task stack -- alongside SPARKNaCl's X25519 they would
   --  otherwise overflow it.
   CH : Builder;                       --  ClientHello build buffer
   RB : Byte_Array (0 .. 4095);        --  inbound record fragment

   procedure P8  (B : in out Builder; V : U8) is
   begin
      B.Data (B.Len) := V;  B.Len := B.Len + 1;
   end P8;

   procedure P16 (B : in out Builder; V : U16) is
   begin
      P8 (B, U8 (V / 256));  P8 (B, U8 (V mod 256));
   end P16;

   procedure PBytes (B : in out Builder; X : Byte_Array) is
   begin
      for E of X loop
         P8 (B, E);
      end loop;
   end PBytes;

   procedure PString (B : in out Builder; S : String) is
   begin
      for C of S loop
         P8 (B, U8 (Character'Pos (C)));
      end loop;
   end PString;

   --  Back-patch a 2-byte length at Mark to (current end - Mark - 2).
   procedure Patch16 (B : in out Builder; Mark : Natural) is
      L : constant Natural := B.Len - Mark - 2;
   begin
      B.Data (Mark)     := U8 (L / 256);
      B.Data (Mark + 1) := U8 (L mod 256);
   end Patch16;

   ---------------------------------------------------------------------------
   --  Record I/O over the socket.
   ---------------------------------------------------------------------------

   procedure Send_Bytes (Sock : Socket_Type; Data : Byte_Array) is
      SEA  : Stream_Element_Array (1 .. Stream_Element_Offset (Data'Length));
      Last : Stream_Element_Offset;
   begin
      for I in Data'Range loop
         SEA (Stream_Element_Offset (I - Data'First) + 1) := Stream_Element (Data (I));
      end loop;
      Send_Socket (Sock, SEA, Last);
   end Send_Bytes;

   --  Read exactly Buf'Length bytes (TLS records may straddle TCP segments).
   procedure Recv_Exact (Sock : Socket_Type; Buf : out Byte_Array; Ok : out Boolean) is
      SEA  : Stream_Element_Array (1 .. Stream_Element_Offset (Buf'Length));
      Pos  : Stream_Element_Offset := 1;
      Last : Stream_Element_Offset;
   begin
      Ok := False;
      if Buf'Length = 0 then
         Ok := True;
         return;
      end if;
      while Pos <= SEA'Last loop
         Receive_Socket (Sock, SEA (Pos .. SEA'Last), Last);
         exit when Last < Pos;                 --  peer closed
         Pos := Last + 1;
      end loop;
      if Pos > SEA'Last then
         for I in Buf'Range loop
            Buf (I) := U8 (SEA (Stream_Element_Offset (I - Buf'First) + 1));
         end loop;
         Ok := True;
      end if;
   end Recv_Exact;

   --  Read one TLS record: its content type and fragment.
   procedure Recv_Record (Sock : Socket_Type; CType : out U8;
                          Frag : out Byte_Array; Len : out Natural; Ok : out Boolean) is
      Hdr : Byte_Array (0 .. 4);
   begin
      CType := 0;  Len := 0;
      Recv_Exact (Sock, Hdr, Ok);
      if not Ok then
         return;
      end if;
      CType := Hdr (0);
      Len   := Natural (Hdr (3)) * 256 + Natural (Hdr (4));
      if Len > Frag'Length then
         Ok := False;
         return;
      end if;
      if Len > 0 then
         Recv_Exact (Sock, Frag (Frag'First .. Frag'First + Len - 1), Ok);
      end if;
   end Recv_Record;

   ---------------------------------------------------------------------------
   --  ClientHello
   ---------------------------------------------------------------------------

   procedure Send_Client_Hello (S : Session; Sock : Socket_Type; Host : String) is
      B    : Builder renames CH;
      Rnd  : ESP32S3.RNG.Byte_Array (0 .. 31);
      Rec, HS, Body_Mark, Ext_Mark, M : Natural;
   begin
      B.Len := 0;
      --  Record header: handshake, legacy version 0x0303, length (patched last).
      P8 (B, CT_Handshake);  P16 (B, 16#0303#);  Rec := B.Len;  P16 (B, 0);

      --  Handshake header: client_hello, 3-byte length (patched last).
      P8 (B, HS_Client_Hello);  HS := B.Len;  P8 (B, 0); P16 (B, 0);
      Body_Mark := B.Len;

      P16 (B, 16#0303#);                                   --  legacy_version
      ESP32S3.RNG.Fill (Rnd);                              --  random (32)
      for I in 0 .. 31 loop P8 (B, U8 (Rnd (I))); end loop;
      ESP32S3.RNG.Fill (Rnd);                              --  legacy_session_id (32)
      P8 (B, 32);
      for I in 0 .. 31 loop P8 (B, U8 (Rnd (I))); end loop;

      P16 (B, 4);                                          --  cipher_suites
      P16 (B, TLS_AES_128_GCM_SHA256);
      P16 (B, TLS_AES_256_GCM_SHA384);

      P8 (B, 1);  P8 (B, 0);                               --  compression: null

      Ext_Mark := B.Len;  P16 (B, 0);                      --  extensions length

      --  server_name (SNI)
      P16 (B, 0);  M := B.Len;  P16 (B, 0);
      P16 (B, Host'Length + 3);                            --  ServerNameList
      P8  (B, 0);                                          --  host_name
      P16 (B, Host'Length);  PString (B, Host);
      Patch16 (B, M);

      --  supported_groups: x25519
      P16 (B, 10);  P16 (B, 4);  P16 (B, 2);  P16 (B, 16#001D#);

      --  signature_algorithms
      P16 (B, 13);  P16 (B, 8);  P16 (B, 6);
      P16 (B, 16#0401#);  P16 (B, 16#0804#);  P16 (B, 16#0403#);

      --  supported_versions: TLS 1.3
      P16 (B, 43);  P16 (B, 3);  P8 (B, 2);  P16 (B, 16#0304#);

      --  key_share: one x25519 entry
      P16 (B, 51);  P16 (B, 38);  P16 (B, 36);             --  ext, ext len, list len
      P16 (B, 16#001D#);  P16 (B, 32);                     --  group, key length
      PBytes (B, S.Pub);

      Patch16 (B, Ext_Mark);                               --  extensions length

      --  back-patch the handshake (3-byte) and record (2-byte) lengths
      declare
         HL : constant Natural := B.Len - Body_Mark;
      begin
         B.Data (HS)     := U8 (HL / 65536);
         B.Data (HS + 1) := U8 ((HL / 256) mod 256);
         B.Data (HS + 2) := U8 (HL mod 256);
      end;
      Patch16 (B, Rec);

      Send_Bytes (Sock, B.Data (0 .. B.Len - 1));
   end Send_Client_Hello;

   ---------------------------------------------------------------------------
   --  ServerHello parse: cipher suite + key_share
   ---------------------------------------------------------------------------

   procedure Parse_Server_Hello (S : in out Session; Frag : Byte_Array; Len : Natural;
                                 Ok : out Boolean) is
      P    : Natural := Frag'First;
      Last : constant Natural := Frag'First + Len - 1;

      function U16_At (I : Natural) return U16 is
        (U16 (Frag (I)) * 256 + U16 (Frag (I + 1)));
   begin
      Ok := False;
      if Len < 40 or else Frag (P) /= HS_Server_Hello then
         return;
      end if;
      P := P + 4;                                  --  hs type + 3-byte length
      P := P + 2;                                  --  legacy_version
      P := P + 32;                                 --  random
      if P > Last then return; end if;
      P := P + 1 + Natural (Frag (P));             --  legacy_session_id_echo
      if P + 2 > Last then return; end if;
      S.Suite := U16_At (P);  P := P + 2;          --  cipher_suite
      P := P + 1;                                  --  legacy_compression_method
      if P + 1 > Last then return; end if;
      P := P + 2;                                  --  extensions length

      --  Walk extensions for key_share (51).
      while P + 4 <= Last + 1 loop
         declare
            Ext_Type : constant U16     := U16_At (P);
            Ext_Len  : constant Natural := Natural (U16_At (P + 2));
            EBody    : constant Natural := P + 4;
         begin
            if Ext_Type = 51 and then Ext_Len >= 36 then
               --  KeyShareEntry: group (2) + length (2) + key_exchange
               if U16_At (EBody) = 16#001D# and then Natural (U16_At (EBody + 2)) = 32 then
                  for I in 0 .. 31 loop
                     S.Server_Pub (I) := Frag (EBody + 4 + I);
                  end loop;
                  S.Have_Share := True;
               end if;
            end if;
            P := EBody + Ext_Len;
         end;
      end loop;
      Ok := S.Suite /= 0;
   end Parse_Server_Hello;

   ---------------------------------------------------------------------------
   --  Drive the opening exchange.
   ---------------------------------------------------------------------------

   procedure Hello (S : in out Session; Sock : Socket_Type; Host : String;
                    Ok : out Boolean) is
      Frag  : Byte_Array renames RB;
      CType : U8;
      Len   : Natural;
      RK    : Boolean;
   begin
      Ok := False;
      Make_Key_Pair (S);
      Send_Client_Hello (S, Sock, Host);

      --  Read records until a handshake record arrives (skip ChangeCipherSpec).
      for Attempt in 1 .. 4 loop
         Recv_Record (Sock, CType, Frag, Len, RK);
         if not RK then
            return;
         end if;
         if CType = CT_Alert then
            return;                               --  server rejected us
         elsif CType = CT_Change_Cipher_Spec then
            null;                                 --  middlebox-compat, ignore
         elsif CType = CT_Handshake then
            Parse_Server_Hello (S, Frag, Len, Ok);
            return;
         end if;
      end loop;
   end Hello;

   function Cipher_Suite (S : Session) return U16 is (S.Suite);

   function Server_Key_Share (S : Session) return Byte_Array is (S.Server_Pub);

end TLS_Client;
