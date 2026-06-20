------------------------------------------------------------------------------
--  GNAT RUN-TIME COMPONENTS (ESP32-S3 full)
--  S Y S T E M . B I N D G E N _ G L O B A L S
--  S p e c
------------------------------------------------------------------------------
--  Binder/runtime C-interface globals for the full-tasking bareboard runtime.
--
--  On a hosted target gnatbind defines __gl_main_priority etc. and init.c
--  provides __gnat_install_SEH_handler / __gnat_get_interrupt_state; the
--  Ravenscar bareboard runtime instead put __gl_main_priority / __gl_main_cpu /
--  __gnat_get_secondary_stack in System.Tasking (s-taskin).  The donor full
--  s-taskin imports rather than defines them, so this unit supplies the
--  definitions, keeping the full runtime self-contained (an app needs no extra
--  C glue to link against it).
------------------------------------------------------------------------------

package System.Bindgen_Globals is
   pragma Elaborate_Body;
end System.Bindgen_Globals;
