with Interfaces;
with ESP32S3.W5500.Sockets;

--  A minimal DHCP client for the W5500.  DHCP is a software protocol over UDP
--  (the chip has no hardware DHCP), so this rides on the socket engine: it runs
--  the DORA exchange (Discover / Offer / Request / Ack) and, on success, programs
--  the leased IP / subnet / gateway into the chip (Net.Configure).  Use it instead
--  of a static address.
--
--  Acquire_Lease is one-shot (no automatic renewal yet); call it again before the
--  lease expires to renew.  Requires the embedded or full profile.
package ESP32S3.W5500.DHCP is

   type Lease_Info is record
      IP, Subnet, Gateway, DNS : IPv4_Address := (0, 0, 0, 0);
      Lease_Seconds            : Interfaces.Unsigned_32 := 0;
   end record;

   --  Run DORA on the given hardware Socket using MAC as the client identity.
   --  On success: Lease is filled, the chip is configured with it, and the result
   --  is True.  On failure (no server answered within Tries attempts): False, and
   --  the chip is left with a 0.0.0.0 address.
   function Acquire_Lease
     (Dev    : ESP32S3.W5500.Sockets.Device_Access;
      MAC    : MAC_Address;
      Lease  : out Lease_Info;
      Socket : Socket_Id := 0;
      Tries  : Positive  := 4) return Boolean;

end ESP32S3.W5500.DHCP;
