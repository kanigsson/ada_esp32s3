package body FTP_Replies with SPARK_Mode => On is

   use type Interfaces.Unsigned_16;

   function Code_Of (Line : String; Last : Natural) return Integer is
      --  Integer (the index base type), not Natural: a null String's 'First is
      --  only known to gnatprove to lie in the base type, so storing it in a
      --  Natural draws a spurious lower-bound check.  Indexing stays safe via
      --  Line'Range.  (proof-patterns.md: "empty-array 'First can be negative".)
      F : constant Integer := Line'First;
   begin
      if Last >= 3
        and then (for all I in F .. F + 2 => Line (I) in '0' .. '9')
      then
         return (Character'Pos (Line (F))     - Character'Pos ('0')) * 100
              + (Character'Pos (Line (F + 1)) - Character'Pos ('0')) * 10
              + (Character'Pos (Line (F + 2)) - Character'Pos ('0'));
      else
         return -1;
      end if;
   end Code_Of;

   function Is_Mid_Multiline (Line : String; Last : Natural) return Boolean is
     (Last >= 4 and then Line (Line'First + 3) = '-');

   function Is_Final_Line (Line : String; Last, Code : Natural) return Boolean is
     (Code_Of (Line, Last) = Code
      and then (Last < 4 or else Line (Line'First + 3) = ' '));

   procedure Parse_Pasv (Line : String;
                         Last : Natural;
                         Host : out Host_Octets;
                         Port : out Port_16;
                         Ok   : out Boolean)
   is
      Nums : array (1 .. 6) of Natural := (others => 0);
      Slot : Natural := 1;
      --  I and Hi are Integer (the index base type), not Natural, so a null
      --  String's 'First doesn't draw a spurious lower-bound check; indexing is
      --  guarded by the loop invariants below.  (See Code_Of.)
      I    : Integer;
      --  Last valid index of the reply text (Line'First - 1 when the line is
      --  empty, so the scan loops simply never run).
      Hi   : constant Integer := Line'First + Last - 1;
   begin
      Host := (others => 0);
      Port := 0;
      Ok   := False;

      --  Skip to the opening parenthesis of the (h1,h2,h3,h4,p1,p2) group.
      I := Line'First;
      while I <= Hi and then Line (I) /= '(' loop
         pragma Loop_Invariant (I in Line'First .. Hi);
         I := I + 1;
      end loop;
      if I > Hi then return; end if;          --  no '(' -> not a PASV reply
      I := I + 1;

      --  Accumulate up to six comma-separated decimal fields until ')'.  The
      --  "<= 255" guard caps each field at 2559, so neither the running *10 + digit
      --  nor a later octet conversion can overflow on a hostile, over-long number.
      while I <= Hi and then Slot <= 6 loop
         pragma Loop_Invariant (I in Line'First .. Hi);
         pragma Loop_Invariant (Slot in 1 .. 6);
         pragma Loop_Invariant (for all K in Nums'Range => Nums (K) <= 2559);
         exit when Line (I) = ')';
         if Line (I) in '0' .. '9' then
            if Nums (Slot) <= 255 then
               Nums (Slot) := Nums (Slot) * 10
                              + (Character'Pos (Line (I)) - Character'Pos ('0'));
            end if;
         elsif Line (I) = ',' then
            Slot := Slot + 1;
         end if;
         I := I + 1;
      end loop;

      if Slot < 6 then return; end if;         --  fewer than six fields parsed
      if Nums (1) > 255 or else Nums (2) > 255 or else Nums (3) > 255
        or else Nums (4) > 255 or else Nums (5) > 255 or else Nums (6) > 255
      then
         return;                               --  a field is not a valid octet
      end if;

      Host := (Octet (Nums (1)), Octet (Nums (2)),
               Octet (Nums (3)), Octet (Nums (4)));
      Port := Port_16 (Nums (5)) * 256 + Port_16 (Nums (6));
      Ok   := True;
   end Parse_Pasv;

end FTP_Replies;
