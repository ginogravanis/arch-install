#!/usr/bin/env bash

install_root="/var/www/install.godmode.sh"
ssh godmode rm -rf "$install_root"/'*'
scp "$(dirname "$0")/download.sh" godmode:"$install_root/arch"
