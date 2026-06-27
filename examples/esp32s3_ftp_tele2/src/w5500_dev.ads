with ESP32S3.W5500;
with ESP32S3.W5500.DHCP;

--  The W5500 as a library-level, aliased board resource, plus a one-call bring-up
--  that uses DHCP: SPI + reset + wait for link + acquire a lease (which programs
--  the IP / subnet / GATEWAY into the chip) + hand the chip to the GNAT.Sockets
--  facade.  No address is hand-configured -- the router assigns it, and the
--  returned lease also carries the DNS server to use.
package W5500_Dev is
   Dev : aliased ESP32S3.W5500.Device;

   --  Bring the link up and acquire a DHCP lease.  False if the chip is absent,
   --  the link never comes up, or no DHCP server answers.  On True the chip is
   --  configured and registered with GNAT.Sockets, and Lease holds the assigned
   --  IP / subnet / gateway / DNS.
   function Bring_Up
     (Lease : out ESP32S3.W5500.DHCP.Lease_Info) return Boolean;

   --  Dotted-decimal text of an IPv4 address, e.g. "192.168.1.50".
   function Image (A : ESP32S3.W5500.IPv4_Address) return String;
end W5500_Dev;
