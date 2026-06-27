package body Net_Routes_Mock is

   function Is_Up (Id : Net_Routes.Interface_Id) return Boolean is
   begin
      return Up (Id);
   end Is_Up;

end Net_Routes_Mock;
