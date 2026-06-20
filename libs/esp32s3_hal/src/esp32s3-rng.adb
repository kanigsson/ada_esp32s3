with ESP32S3_Registers.RNG;

package body ESP32S3.RNG is

   function Read return Word is
   begin
      return ESP32S3_Registers.RNG.RNG_Periph.DATA;
   end Read;

   procedure Fill (Buffer : out Byte_Array) is
      use ESP32S3_Registers;                         --  brings UInt32 + its ops
      I : Natural := Buffer'First;
   begin
      while I <= Buffer'Last loop
         declare
            W : constant Word    := Read;            --  one fresh random word
            N : constant Natural := Natural'Min (4, Buffer'Last - I + 1);
         begin
            for J in 0 .. N - 1 loop                 --  little-endian byte slice
               Buffer (I + J) := Byte ((W / (UInt32'(2) ** (8 * J))) mod 256);
            end loop;
            I := I + N;
         end;
      end loop;
   end Fill;

end ESP32S3.RNG;
