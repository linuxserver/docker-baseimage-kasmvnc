#!/usr/bin/env bash

# Enable Nvidia GPU support if detected
if vulkaninfo >/dev/null 2>&1 && which nvidia-smi; then
  printf "1" > /run/s6/container_environment/LIBGL_KOPPER_DRI2
  printf "zink" > /run/s6/container_environment/MESA_LOADER_DRIVER_OVERRIDE
  printf "zink" > /run/s6/container_environment/GALLIUM_DRIVER
fi

/usr/bin/openbox-session
