with Interfaces;

--  ECDSA signature verification on the NIST P-256 curve (secp256r1 /
--  prime256v1), in pure Ada -- no chip dependency.  Verification only: it
--  operates entirely on public values (public key, signature, message hash), so
--  there are no secret-dependent branches and ordinary variable-time code is fine.
--
--  256-bit integers are held as eight little-endian 32-bit limbs; the field and
--  order arithmetic is Montgomery (CIOS), with all Montgomery constants derived on
--  the fly from the hard-coded curve parameters.  Point arithmetic is Jacobian.
package P256 is

   subtype Byte is Interfaces.Unsigned_8;
   type Bytes is array (Natural range <>) of Byte;
   subtype Bytes_32 is Bytes (0 .. 31);

   --  Verify an ECDSA signature (r, s) of the message digest Hash under the public
   --  key (Pub_X, Pub_Y).  All five inputs are 32-byte big-endian integers.  Hash
   --  is the message digest reduced to 256 bits: for ECDSA-with-SHA-256 it is the
   --  32-byte digest; for SHA-384/512 the caller passes the leftmost 32 bytes.
   --  Returns True iff the signature verifies.
   function Verify (Pub_X, Pub_Y : Bytes_32;
                    Hash         : Bytes_32;
                    R, S         : Bytes_32) return Boolean;

end P256;
