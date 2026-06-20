package Comm is
   pragma Elaborate_Body;
   --  Cross-core demo: a Producer task pinned to core 1 writes a mailbox and
   --  opens a protected-object entry barrier; a Consumer task pinned to core 0
   --  blocks in that entry until served.  Serving the entry on core 1 makes the
   --  consumer ready on the *other* core, which the GNARL kernel delivers via
   --  the served-entry list and an inter-core poke.  See the body.
end Comm;
