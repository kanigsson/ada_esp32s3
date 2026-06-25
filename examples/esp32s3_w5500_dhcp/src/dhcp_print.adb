with ESP32S3.W5500;
with ESP32S3.Log; use ESP32S3.Log;

package body DHCP_Print is
   procedure Put_IP (A : ESP32S3.W5500.IPv4_Address) is
   begin
      for I in A'Range loop
         Put (Integer (A (I)));
         if I < A'Last then Put ("."); end if;
      end loop;
   end Put_IP;

   procedure On_Bound (Lease : ESP32S3.W5500.DHCP.Lease_Info) is
   begin
      Put ("[dhcp] bound: IP ");  Put_IP (Lease.IP);
      Put (" mask ");             Put_IP (Lease.Subnet);
      Put (" gw ");               Put_IP (Lease.Gateway);
      Put (" dns ");              Put_IP (Lease.DNS);
      Put (" lease ");            Put (Integer (Lease.Lease_Seconds));
      Put_Line (" s");
   end On_Bound;
end DHCP_Print;
