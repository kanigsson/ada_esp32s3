--  Pure FTP-server path handling, factored out of the FTP_Server body so it can
--  be proved in SPARK: it touches only String / Natural / Integer, never the VFS
--  or GNAT.Sockets (whose controlled handles are out of the subset).
--
--  Abs_Path is the path-traversal guard.  It normalises a client-supplied path
--  against the current directory -- collapsing ".", "..", "//" and trailing "/"
--  -- so the result is always a clean absolute path rooted at "/".  Because every
--  ".." is applied during the walk (and can never back up past the leading "/"),
--  a hostile argument such as "../../../etc" resolves back to "/" and can never
--  escape above the root.  Split breaks an absolute path into (parent, last name).
--
--  Both write into caller-supplied buffers (no secondary-stack "return String"),
--  the same bounded-buffer shape that brought Parse_Time into the subset in Tier A.
package FTP_Paths with SPARK_Mode => On is

   --  Ghost: a complete ".." path component starts at S (K) -- two dots bounded
   --  on each side by a '/' or by the end of the string.  This is the only
   --  construct that climbs a directory level, so a rooted path that contains
   --  none of them (No_Parent_Ref below) can never refer above its own root.
   --  "a..b", "x..", "...": the dots are not a *complete* component, so they are
   --  ordinary file names and do not count.
   function Dot_Dot_At (S : String; K : Integer) return Boolean is
     (K >= S'First and then K < S'Last
        and then S (K) = '.' and then S (K + 1) = '.'
        and then (K = S'First or else S (K - 1) = '/')
        and then (K + 1 = S'Last or else S (K + 2) = '/'))
   with Ghost;

   --  Ghost: S has no ".." path component -- the no-escape property.
   function No_Parent_Ref (S : String) return Boolean is
     (for all K in S'Range => not Dot_Dot_At (S, K))
   with Ghost;

   --  Normalised absolute form of Arg resolved against Cwd, written into
   --  Result (Result'First .. Result'First + Len - 1).
   --
   --  Cwd must be a non-empty absolute path (it starts with '/').  Result must
   --  hold the worst case -- normalisation never lengthens a path, but the raw
   --  join of Cwd, a separator and Arg, plus one slot of normalisation slack,
   --  bounds it at Cwd'Length + Arg'Length + 3 characters.
   --
   --  The result is itself absolute (Len >= 1 and Result (Result'First) = '/'),
   --  so it is always anchored at the root: this is the first half of the
   --  no-escape guarantee (a path that is always rooted can never be a relative
   --  reference, and the walk that builds it discards every ".." that would
   --  climb above "/").
   procedure Abs_Path
     (Cwd    : String;
      Arg    : String;
      Result : out String;
      Len    : out Natural)
   with
     Pre  => Cwd'Length >= 1
             and then Cwd (Cwd'First) = '/'
             and then Cwd'Last < Integer'Last
             and then Arg'Last < Integer'Last
             and then Result'Last < Integer'Last
             and then Result'Length >= Cwd'Length + Arg'Length + 3,
     Post => Len in 1 .. Result'Length
             and then Result (Result'First) = '/'
             and then No_Parent_Ref (Result (Result'First .. Result'First + Len - 1));

   --  Split an absolute Path into its parent directory and last name component.
   --  Path must be absolute (starts with '/').  Dir and Name must each be able to
   --  hold Path (the parent is shorter than Path, the last name shorter still).
   procedure Split
     (Path     : String;
      Dir      : out String;
      Dir_Len  : out Natural;
      Name     : out String;
      Name_Len : out Natural)
   with
     Pre  => Path'Length >= 1
             and then Path (Path'First) = '/'
             and then Path'Last < Integer'Last
             and then Dir'Last  < Integer'Last
             and then Name'Last < Integer'Last
             and then Dir'Length  >= Path'Length
             and then Name'Length >= Path'Length,
     Post => Dir_Len in 1 .. Dir'Length
             and then Name_Len <= Name'Length;

end FTP_Paths;
