package body FTP_Paths with SPARK_Mode => On is

   procedure Abs_Path
     (Cwd    : String;
      Arg    : String;
      Result : out String;
      Len    : out Natural)
   is
      --  Worst-case scratch: Cwd, a separator and Arg.  Raw'Length is at least 3
      --  (Cwd is non-empty), and the built path uses at most Raw'Length - 1 of it.
      Raw  : String (1 .. Cwd'Length + Arg'Length + 2) := (others => ' ');
      RLen : Natural;

      --  Normalised output (1-based); one slot of slack over Raw so the
      --  separator a component may prepend always fits (see the OLen <= I
      --  invariant: in the tightest case a write reaches index I + 1).
      O    : String (1 .. Raw'Length + 1) := (others => '/');
      OLen : Natural;

      --  Index into Raw.  Integer (the index base type), not Natural, so the
      --  empty-String 'First never draws a spurious lower-bound check; every read
      --  is bounded by the loop invariants below.
      I    : Integer;
   begin
      Result := (others => ' ');

      ----------------------------------------------------------------------
      --  1. Build the raw absolute path (Cwd-relative unless Arg is absolute).
      ----------------------------------------------------------------------
      if Arg'Length > 0 and then Arg (Arg'First) = '/' then
         Raw (1 .. Arg'Length) := Arg;
         RLen := Arg'Length;
      else
         Raw (1 .. Cwd'Length) := Cwd;
         RLen := Cwd'Length;
         if Raw (RLen) /= '/' then
            RLen := RLen + 1;
            Raw (RLen) := '/';
         end if;
         Raw (RLen + 1 .. RLen + Arg'Length) := Arg;
         RLen := RLen + Arg'Length;
      end if;

      --  Raw is now a non-empty path beginning with '/', occupying 1 .. RLen.
      pragma Assert (RLen in 1 .. Raw'Length);
      pragma Assert (Raw (1) = '/');

      ----------------------------------------------------------------------
      --  2. Walk components, collapsing "." / ".." / "//".
      --
      --  Slashes are consumed at the end of each iteration (and once before the
      --  loop), so at the top of the loop Raw (I) is always a component char and
      --  every component is non-empty.
      --
      --  The key invariant relates the output cursor OLen to the input cursor I:
      --  the output never overtakes the input, with one extra unit of headroom
      --  when the output does not already end in a '/' (because the next
      --  component must then prepend a separator).  The leading '/' is what funds
      --  that headroom -- it is copied but never re-counted -- and it is what
      --  guarantees ".." can never climb above the root.  Written as a single
      --  bound:  OLen <= I - 1 - (1 if O (OLen) /= '/').
      ----------------------------------------------------------------------
      OLen := 1;
      O (1) := '/';

      I := 1;
      while I <= RLen and then Raw (I) = '/' loop
         pragma Loop_Invariant (I in 1 .. RLen);
         I := I + 1;
      end loop;

      while I <= RLen loop
         pragma Loop_Invariant (I in 2 .. RLen);
         pragma Loop_Invariant (OLen in 1 .. RLen);
         pragma Loop_Invariant (O (1) = '/');
         pragma Loop_Invariant
           (if O (OLen) = '/' then OLen <= I - 1 else OLen <= I - 2);
         declare
            Start : constant Integer := I;
         begin
            while I <= RLen and then Raw (I) /= '/' loop
               pragma Loop_Invariant (I in Start .. RLen);
               I := I + 1;
            end loop;

            declare
               Comp : constant String := Raw (Start .. I - 1);
            begin
               if Comp = "." then
                  null;

               elsif Comp = ".." then
                  --  Pop the last component (back to its leading '/'), then drop
                  --  that slash; "/.." stays "/" (cannot climb above the root).
                  while OLen > 1 and then O (OLen) /= '/' loop
                     pragma Loop_Invariant (OLen in 1 .. RLen);
                     pragma Loop_Invariant (O (1) = '/');
                     --  Pop only shrinks OLen, so the output-vs-input bound from
                     --  the outer invariant survives the pop (I is fixed here).
                     pragma Loop_Invariant (OLen <= I - 1);
                     OLen := OLen - 1;
                  end loop;
                  if OLen > 1 then
                     OLen := OLen - 1;
                  end if;

               else
                  --  Append "/" (unless the output already ends in one) + Comp.
                  if O (OLen) /= '/' then
                     OLen := OLen + 1;
                     O (OLen) := '/';
                  end if;
                  O (OLen + 1 .. OLen + Comp'Length) := Comp;
                  OLen := OLen + Comp'Length;
               end if;
            end;
         end;

         --  After handling a component OLen <= I - 1.  The separator skip below
         --  re-establishes the keyed outer invariant: stated as an implication
         --  conditioned on the exit test, it hands the prover the keyed bound
         --  exactly when the loop is about to leave (one skipped slash supplies
         --  the extra "ends in non-slash" unit of headroom).
         while I <= RLen and then Raw (I) = '/' loop
            pragma Loop_Invariant (I in 2 .. RLen + 1);
            --  Carry the post-handling bound so it survives the havoc of I; the
            --  keyed refinement then adds the extra unit of headroom for a
            --  non-slash output, but only once the skip is about to finish.
            pragma Loop_Invariant (OLen <= I - 1);
            pragma Loop_Invariant
              (if I > RLen or else Raw (I) /= '/' then
                 (if O (OLen) /= '/' then OLen <= I - 2));
            I := I + 1;
         end loop;
      end loop;

      ----------------------------------------------------------------------
      --  3. Copy the normalised path into the caller's buffer.
      ----------------------------------------------------------------------
      Len := OLen;
      Result (Result'First .. Result'First + Len - 1) := O (1 .. Len);
   end Abs_Path;

   procedure Split
     (Path     : String;
      Dir      : out String;
      Dir_Len  : out Natural;
      Name     : out String;
      Name_Len : out Natural)
   is
      --  Integer (base type) so an empty-String 'First needs no lower-bound
      --  check; Path is non-empty here, but keep the pattern uniform.
      Slash : Integer := Path'First;
   begin
      Dir  := (others => ' ');
      Name := (others => ' ');

      --  Last '/' in Path (Path (Path'First) = '/' seeds it at the front).
      for K in Path'Range loop
         if Path (K) = '/' then
            Slash := K;
         end if;
         pragma Loop_Invariant (Slash in Path'First .. K);
      end loop;

      Name_Len := Path'Last - Slash;
      Name (Name'First .. Name'First + Name_Len - 1) := Path (Slash + 1 .. Path'Last);

      if Slash = Path'First then
         Dir_Len := 1;
         Dir (Dir'First) := '/';
      else
         Dir_Len := Slash - Path'First;
         Dir (Dir'First .. Dir'First + Dir_Len - 1) := Path (Path'First .. Slash - 1);
      end if;
   end Split;

end FTP_Paths;
