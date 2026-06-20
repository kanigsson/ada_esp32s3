#!/bin/bash
# IDF-free build of esp32s3_full_intr via the shared bare-boot.  FULL profile:
# this is the test that pragma Attach_Handler / Ada.Interrupts protected handlers
# now build and run under ESP32S3_RTS_PROFILE=full (the bareboard full
# System.Interrupts in full_overlay/gnarl/s-interr.{ads,adb}).  The full RTS uses
# exceptions + finalization + a heap, so request a heap + a large env stack like
# the other full-profile examples.
export ESP32S3_RTS_PROFILE=full
export HEAP_SIZE=196608 ENV_STACK_SIZE=65536
HERE="$(cd "$(dirname "$0")" && pwd)"
exec bash "$HERE/../common/bare/bare_build.sh" "$HERE" "_ada_example"
