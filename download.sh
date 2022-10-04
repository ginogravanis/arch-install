#!/usr/bin/env bash

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

if timedatectl status | grep 'NTP service: inactive'
then
   timedatectl set-ntp true
   sleep 1
fi

if timedatectl status | grep 'synchronized: no'
then
   systemctl restart systemd-timesyncd
   sleep 1
fi

sudo pacman -Sy
sudo pacman -S --noconfirm --needed git
git clone --depth 1 https://github.com/ginogravanis/arch-install.git "$tmpdir"

sudo "$tmpdir/arch.sh"
