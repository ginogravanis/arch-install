#!/usr/bin/env bash

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

pacman -Sy
if ! command -v git
then
   if ! pacman -S --noconfirm git
   then
      pacman-keys --init
      pacman -Syy
      if ! pacman -S --noconfirm git
      then
         >&2 echo "Failed to install git. Please install git and retry."
         exit 1
      fi
   fi
fi

git clone --depth 1 https://github.com/ginogravanis/arch-install.git "$tmpdir"

sudo "$tmpdir/arch.sh"
