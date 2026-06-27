with Interfaces; use Interfaces;

package body Net_Routes with SPARK_Mode => On is

   use type Net_Devices.Interface_Id;   --  "=" on Iface in Resolve's contract

   --  Pack a dotted address into a 32-bit value for masking/compare.
   function U32 (A : Net_Devices.IPv4_Address) return Unsigned_32 is
     (Shift_Left (Unsigned_32 (A (0)), 24) or Shift_Left (Unsigned_32 (A (1)), 16)
      or Shift_Left (Unsigned_32 (A (2)), 8) or Unsigned_32 (A (3)));

   --  Prefix length = number of set bits in the mask (works for any mask, /0..32).
   function Prefix_Len (Mask : Unsigned_32) return Natural
     with Post => Prefix_Len'Result <= 32;
   function Prefix_Len (Mask : Unsigned_32) return Natural is
      N : Natural := 0;
   begin
      for I in 0 .. 31 loop
         if (Shift_Right (Mask, I) and 1) = 1 then
            N := N + 1;
         end if;
         pragma Loop_Invariant (N <= I + 1);   --  at most one bit counted per pass
      end loop;
      return N;
   end Prefix_Len;

   type Route is record
      Dest, Mask : Unsigned_32  := 0;
      Iface      : Interface_Id := 0;
      Metric     : Natural      := 0;
      Valid      : Boolean      := False;
   end record;

   Max_Routes : constant := 16;
   subtype Route_Count is Natural range 0 .. Max_Routes;
   Table      : array (1 .. Max_Routes) of Route;
   N_Routes   : Route_Count := 0;
   Up         : Up_Query := null;

   procedure Configure (Is_Up : Up_Query) is
   begin
      Up := Is_Up;
   end Configure;

   procedure Clear is
   begin
      N_Routes := 0;
   end Clear;

   function Has_Routes return Boolean is (N_Routes > 0);

   procedure Add_Route (Dest, Mask : Net_Devices.IPv4_Address;
                        Iface : Interface_Id; Metric : Natural := 100) is
   begin
      if N_Routes < Max_Routes then
         N_Routes := N_Routes + 1;
         Table (N_Routes) :=
           (Dest => U32 (Dest), Mask => U32 (Mask),
            Iface => Iface, Metric => Metric, Valid => True);
      end if;
   end Add_Route;

   procedure Set_Default (Iface : Interface_Id; Metric : Natural := 100) is
   begin
      Add_Route ((0, 0, 0, 0), (0, 0, 0, 0), Iface, Metric);
   end Set_Default;

   --  Ghost: is route R a candidate for destination D, given its interface is Live?
   --  Valid, its network covers D, and Live.  This is exactly the guard the Resolve
   --  loop screens each route with.  Liveness is passed in (not read from Up here)
   --  so the predicate is self-evidently terminating: the indirect call Up (Iface)
   --  -- whose body the prover can't see -- stays in Resolve's assertions, which
   --  carry no termination obligation, rather than in this expression function.
   function Qualifies (R : Route; D : Unsigned_32; Live : Boolean) return Boolean is
     (R.Valid
      and then (D and R.Mask) = (R.Dest and R.Mask)
      and then Live)
   with Ghost;

   --  Functional spec of the selection (longest-prefix, then lowest-metric):
   --    * Found iff some route qualifies for Dest; and
   --    * when Found, the chosen Iface is that of a qualifying route W which is
   --      best -- no qualifying route has a longer prefix, and none with an equal
   --      prefix has a strictly lower metric.  (Full prefix+metric ties keep the
   --      earliest such route, whose metric this still bounds.)
   procedure Resolve (Dest  : Net_Devices.IPv4_Address;
                     Iface : out Interface_Id;
                     Found : out Boolean)
     with Refined_Post =>
       (Found =
          (for some K in 1 .. N_Routes =>
             Qualifies (Table (K), U32 (Dest),
                        Up = null or else Up (Table (K).Iface)))
        and then
          (if Found then
             (for some W in 1 .. N_Routes =>
                Qualifies (Table (W), U32 (Dest),
                           Up = null or else Up (Table (W).Iface))
                and then Table (W).Iface = Iface
                and then
                  (for all K in 1 .. N_Routes =>
                     (if Qualifies (Table (K), U32 (Dest),
                                    Up = null or else Up (Table (K).Iface))
                      then
                        Prefix_Len (Table (K).Mask) < Prefix_Len (Table (W).Mask)
                        or else
                          (Prefix_Len (Table (K).Mask) = Prefix_Len (Table (W).Mask)
                           and then Table (W).Metric <= Table (K).Metric))))))
   is
      D           : constant Unsigned_32 := U32 (Dest);
      Best_Len    : Integer := -1;          --  so the first match always wins
      Best_Metric : Natural := 0;
      Witness     : Route_Count := 0 with Ghost;  --  route backing (Iface,Best_*)
   begin
      Found := False;
      Iface := 0;
      for I in 1 .. N_Routes loop
         declare
            R : Route renames Table (I);
         begin
            if R.Valid
              and then (D and R.Mask) = (R.Dest and R.Mask)        --  matches
              and then (Up = null or else Up (R.Iface))            --  interface up
            then
               declare
                  Len : constant Natural := Prefix_Len (R.Mask);
               begin
                  if Len > Best_Len
                    or else (Len = Best_Len and then R.Metric < Best_Metric)
                  then
                     Best_Len    := Len;
                     Best_Metric := R.Metric;
                     Iface       := R.Iface;
                     Found       := True;
                     Witness     := I;
                  end if;
               end;
            end if;
         end;

         --  Best-so-far over Table (1 .. I): Found tracks "some route qualified",
         --  Witness backs the current pick, and (Best_Len, Best_Metric) dominate
         --  every qualifier seen so far.
         pragma Loop_Invariant
           (Found = (for some K in 1 .. I =>
                       Qualifies (Table (K), D,
                                  Up = null or else Up (Table (K).Iface))));
         pragma Loop_Invariant (Found = (Best_Len >= 0));
         pragma Loop_Invariant
           (if Found then
              Witness in 1 .. I
              and then Qualifies (Table (Witness), D,
                                  Up = null or else Up (Table (Witness).Iface))
              and then Prefix_Len (Table (Witness).Mask) = Best_Len
              and then Table (Witness).Metric = Best_Metric
              and then Table (Witness).Iface = Iface);
         pragma Loop_Invariant
           (for all K in 1 .. I =>
              (if Qualifies (Table (K), D,
                             Up = null or else Up (Table (K).Iface))
               then
                 Prefix_Len (Table (K).Mask) < Best_Len
                 or else (Prefix_Len (Table (K).Mask) = Best_Len
                          and then Best_Metric <= Table (K).Metric)));
      end loop;
   end Resolve;

end Net_Routes;
