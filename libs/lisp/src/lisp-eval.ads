--  The evaluator: eval/apply, lexical environments, the special forms, and the
--  built-in primitives.  An environment is a chain of frames, each an association
--  list of (symbol . value); Global_Env is the outermost, pre-loaded with the
--  primitives.
package Lisp.Eval is

   --  The global environment (built once, holds the primitives).
   function Global_Env return Ref;

   --  Evaluate Expr in Env.
   function Eval (Expr : Ref; Env : Ref) return Ref;

   --  Evaluate in the global environment (a REPL top level).
   function Eval_Top (Expr : Ref) return Ref;

end Lisp.Eval;
