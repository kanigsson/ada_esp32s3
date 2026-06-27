--  Native host test for Net_Routes -- the multi-interface routing table.  Pure
--  logic: routes + an injected mock up-state (Net_Routes_Mock), no hardware.
--  Exercises longest-prefix match, metric tie-break, and up/down failover.
with Ada.Text_IO;  use Ada.Text_IO;
with Net_Devices;
with Net_Routes;
with Net_Routes_Mock;

procedure Net_Routes_Test is

   use type Net_Routes.Interface_Id;

   Eth  : constant Net_Routes.Interface_Id := 0;   --  wired W5500
   Cell : constant Net_Routes.Interface_Id := 1;   --  cellular

   Passed, Failed : Natural := 0;

   --  Resolve Dest and assert the chosen interface (or that none was found).
   procedure Expect (Label : String; Dest : Net_Devices.IPv4_Address;
                     Want : Net_Routes.Interface_Id; Want_Found : Boolean := True)
   is
      Got   : Net_Routes.Interface_Id;
      Found : Boolean;
      OK    : Boolean;
   begin
      Net_Routes.Resolve (Dest, Got, Found);
      if Want_Found then
         OK := Found and then Got = Want;
      else
         OK := not Found;
      end if;
      if OK then
         Passed := Passed + 1;
         Put_Line ("  ok   " & Label);
      else
         Failed := Failed + 1;
         Put_Line ("  FAIL " & Label
                   & "  (found=" & Boolean'Image (Found)
                   & " iface=" & Net_Routes.Interface_Id'Image (Got) & ")");
      end if;
   end Expect;

   procedure All_Up is
   begin
      Net_Routes_Mock.Up := (others => True);
   end All_Up;

begin
   Net_Routes.Configure (Net_Routes_Mock.Is_Up'Access);

   ----------------------------------------------------------------------------
   Put_Line ("1. single default route");
   Net_Routes.Clear; All_Up;
   Net_Routes.Set_Default (Eth, Metric => 10);
   Expect ("any dest -> eth", (8, 8, 8, 8), Eth);

   ----------------------------------------------------------------------------
   Put_Line ("2. two default routes -> lower metric (eth) wins");
   Net_Routes.Clear; All_Up;
   Net_Routes.Set_Default (Eth,  Metric => 10);
   Net_Routes.Set_Default (Cell, Metric => 100);
   Expect ("prefer eth", (1, 1, 1, 1), Eth);

   ----------------------------------------------------------------------------
   Put_Line ("3. eth down -> fail over to cell");
   Net_Routes_Mock.Up (Eth) := False;
   Expect ("failover to cell", (1, 1, 1, 1), Cell);

   ----------------------------------------------------------------------------
   Put_Line ("4. eth back up -> preempt back to eth");
   Net_Routes_Mock.Up (Eth) := True;
   Expect ("preempt to eth", (1, 1, 1, 1), Eth);

   ----------------------------------------------------------------------------
   Put_Line ("5. longest-prefix beats metric");
   Net_Routes.Clear; All_Up;
   Net_Routes.Set_Default (Eth, Metric => 1);                       --  /0, low metric
   Net_Routes.Add_Route ((10, 0, 0, 0), (255, 0, 0, 0), Cell, 100); --  10/8, high metric
   Expect ("10.1.2.3 -> cell (more specific)", (10, 1, 2, 3), Cell);
   Expect ("9.9.9.9   -> eth (default)",       (9, 9, 9, 9),  Eth);

   ----------------------------------------------------------------------------
   Put_Line ("6. specific route's interface down -> fall to default");
   Net_Routes_Mock.Up (Cell) := False;
   Expect ("10.1.2.3 -> eth (cell down)", (10, 1, 2, 3), Eth);

   ----------------------------------------------------------------------------
   Put_Line ("7. all matching interfaces down -> no route");
   Net_Routes.Clear; All_Up;
   Net_Routes.Set_Default (Eth, Metric => 10);
   Net_Routes_Mock.Up (Eth) := False;
   Expect ("nothing up -> not found", (1, 2, 3, 4), Eth, Want_Found => False);

   ----------------------------------------------------------------------------
   Put_Line ("8. empty table -> no route");
   Net_Routes.Clear; All_Up;
   Expect ("empty -> not found", (1, 2, 3, 4), Eth, Want_Found => False);

   ----------------------------------------------------------------------------
   New_Line;
   Put_Line ("Net_Routes:" & Natural'Image (Passed) & " passed,"
             & Natural'Image (Failed) & " failed");
   if Failed > 0 then
      raise Program_Error with "route-table test failed";
   end if;
end Net_Routes_Test;
