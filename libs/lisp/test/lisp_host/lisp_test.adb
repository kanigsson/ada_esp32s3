--  Native host test for the LISP core: read S-expression text and print it back,
--  checking the round-trip, plus symbol interning identity.  No hardware.
with Ada.Text_IO; use Ada.Text_IO;
with Lisp;        use Lisp;
with Lisp.Reader;

procedure Lisp_Test is
   Passed, Failed : Natural := 0;

   procedure RT (Input, Want : String) is
      Got : constant String := Print (Lisp.Reader.Read (Input));
   begin
      if Got = Want then
         Passed := Passed + 1;  Put_Line ("  ok   " & Input & "  ->  " & Got);
      else
         Failed := Failed + 1;
         Put_Line ("  FAIL " & Input & "  ->  " & Got & "  (want " & Want & ")");
      end if;
   end RT;

   procedure Check (Label : String; Cond : Boolean) is
   begin
      if Cond then Passed := Passed + 1; Put_Line ("  ok   " & Label);
      else Failed := Failed + 1; Put_Line ("  FAIL " & Label); end if;
   end Check;
begin
   Put_Line ("reader / printer round-trips:");
   RT ("42", "42");
   RT ("-5", "-5");
   RT ("+7", "7");
   RT ("#t", "#t");
   RT ("#f", "#f");
   RT ("foo", "foo");
   RT ("()", "()");
   RT ("(+ 1 2)", "(+ 1 2)");
   RT ("(a (b c) d)", "(a (b c) d)");
   RT ("(1 . 2)", "(1 . 2)");
   RT ("(1 2 . 3)", "(1 2 . 3)");
   RT ("'x", "(quote x)");
   RT ("'(1 2)", "(quote (1 2))");
   RT ("  ( a   b ) ; trailing comment", "(a b)");
   RT ("(- 4)", "(- 4)");          --  '-' alone is the symbol, not a number
   RT ("(define x 10)", "(define x 10)");

   New_Line;
   Put_Line ("symbol interning:");
   Check ("(intern x) = (intern x)", Intern ("x") = Intern ("x"));
   Check ("(intern x) /= (intern y)", Intern ("x") /= Intern ("y"));
   Check ("nil is the empty list", Is_Nil (Lisp.Reader.Read ("()")));

   New_Line;
   Put_Line ("Lisp core:" & Natural'Image (Passed) & " passed,"
             & Natural'Image (Failed) & " failed  (cells used:"
             & Natural'Image (Cells_Used) & ")");
   if Failed > 0 then
      raise Program_Error with "lisp core test failed";
   end if;
end Lisp_Test;
