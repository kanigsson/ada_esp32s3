with Net_Routes;

--  Library-level mock liveness for the route-table test: a per-interface up/down
--  flag plus a closure-free query to inject via Net_Routes.Configure (an access to
--  a nested function would break the accessibility rule, so it lives here).
package Net_Routes_Mock is

   Up : array (Net_Routes.Interface_Id) of Boolean := (others => True);

   function Is_Up (Id : Net_Routes.Interface_Id) return Boolean;

end Net_Routes_Mock;
