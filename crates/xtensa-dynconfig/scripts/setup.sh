#!/bin/bash

if [ ! -d xtensa-dynconfig ]; then
  git clone https://github.com/espressif/xtensa-dynconfig.git
fi

if [ ! -d xtensa-overlays ]; then
  git clone https://github.com/espressif/xtensa-overlays.git
fi

if [ ! -e xtensa-dynconfig/config ]; then
  ln -s ../xtensa-overlays xtensa-dynconfig/config
fi
