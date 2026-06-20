#!/bin/bash
# IDF-free build of esp32s3_intr_levels via the shared bare-boot.  Embedded
# profile (pragma Attach_Handler -- the Ada.Interrupts layer -- needs the Jorvik
# interrupt machinery, which the configurable full runtime omits).
export ESP32S3_RTS_PROFILE=embedded
HERE="$(cd "$(dirname "$0")" && pwd)"
exec bash "$HERE/../common/bare/bare_build.sh" "$HERE" "_ada_example"
