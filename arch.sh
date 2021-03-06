#!/usr/bin/env bash

set -e

user=$(logname)

deps_exist=("dialog" "fdisk")
deps_latest=("archlinux-keyring")

function err() {
   local red=$(tput setaf 1)
   local reset=$(tput sgr0)
   echo -e "${red}[Error]${reset} $1" >&2
}

function dialog_cmd() {
   dialog \
   --stdout \
   --backtitle "Arch Linux Setup" \
   "$@"
}

function main_menu() {
   local selected_entry=$(dialog_cmd \
      --title "Main Menu" \
      --no-items \
      --menu "" 0 0 0 \
      "1. Format disk" \
      "2. Install base system" \
      "3. Reboot" \
      "4. Setup dotfiles" \
      "5. Install Vim" \
      "6. Install desktop environment"
   )

   if [ $? -eq 0 ]; then
      case $selected_entry in
         "1. Format disk")
            format_disk
            main_menu
            ;;
         "2. Install base system")
            install_base_system
            ;;
         "3. Reboot")
            reboot
            ;;
         "4. Setup dotfiles")
            setup_dotfiles
            main_menu
            ;;
         "5. Install Vim")
            install_vim
            main_menu
            ;;
         "6. Install desktop environment")
            install_desktop_environment
            main_menu
            ;;
         *)
            exit
      esac
   fi
}

function ensure_deps() {
	if ! test -e "/sys/firmware/efi/efivars"; then
      err "/sys/firmware/efi/efivars not found."
		err "This script only works on EFI systems."
		exit 1
	fi

	timedatectl set-ntp true

   sed -i -e "s/#ParallelDownloads/ParallelDownloads/" /etc/pacman.conf
   pacman -Sy
	for pkg in ${deps_exist}
	do
		if ! pacman -Qe ${pkg} >/dev/null
		then
			pacman -S --noconfirm --needed ${deps_exist}
			break
		fi
	done

   for pkg in ${deps_latest}
   do
      if ! diff \
         <(pacman -Qi ${pkg} | grep "^Version") \
         <(pacman -Si ${pkg} | grep "^Version")
      then
         pacman -S --noconfirm --needed ${pkg}
      fi
   done
}

function format_disk() {
   read -r -a devices <<< \
      $(lsblk -Sdnpo NAME,SIZE,TYPE \
      | grep 'disk$' \
      | awk '{print $1,$2}' \
      | tr '\n' '\t')
   local disk=$(dialog_cmd \
      --title "Format Disk" \
      --menu "Target disk will be partitioned into a 512MB EFI partition, and a main partition taking up the remaining disk space." 15 60 0 \
      ${devices[@]} \
   )
   unset devices

	if lsblk -np -o MOUNTPOINTS "$disk" | grep -q .; then
		err "Mounted volumes detected for device $disk. Please unmount and try again."
		lsblk -p -o NAME,MOUNTPOINTS "$disk" >&2
		exit 1
	fi

	fdisk -W always -w always "$disk" << EOF
g
n


+512M
t
1
n



w
EOF

	yes | mkfs.fat -F32 ${disk}1
	yes | mkfs.ext4 ${disk}2

	mount ${disk}2 /mnt
	mkdir -p /mnt/efi
	mount ${disk}1 /mnt/efi
}

function install_base_system() {
   local hostname=$(dialog_cmd --inputbox "Hostname" 0 0)

   pacstrap /mnt base base-devel linux linux-firmware

   genfstab -U /mnt >> /mnt/etc/fstab
   echo ${hostname} >> /mnt/etc/hostname

   # TODO Download chroot.sh
   local script_dir="/root/tmp"
   mkdir -p /mnt/${script_dir}
   cp $(cd $(dirname $0) && pwd)/*.sh /mnt/${script_dir}/
   chmod +x /mnt/${script_dir}/*.sh

   arch-chroot /mnt bash ${script_dir}/chroot.sh

   echo "Base system installation comlete."
   echo "Please reboot into your new system and rerun this script to continue:"
   echo "   $ sudo ~/arch.sh"
}

function setup_dotfiles() {
   pacman -S --noconfirm git tk
   runuser -l $user -c "git clone --bare https://github.com/ginogravanis/dotfiles.git ~/.dotfiles.git"
   dot="git --git-dir=\$HOME/.dotfiles.git/ --work-tree=\$HOME"
   runuser -l $user -c "$dot checkout -f main"
   runuser -l $user -c "$dot config --local status.showUntrackedFiles no"
}

function install_vim() {
   pacman -S --noconfirm --needed tmux vim
   runuser -l $user -c "git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim"
   runuser -l $user -c "vim +PluginInstall +qa"
}

function install_desktop_environment() {
   install_xorg
   install_github_pkg dmenu
   install_github_pkg st
   install_github_pkg dwm
   install_github_pkg pacman-contrib-gino
   install_bluetooth
   install_extras
}

function install_xorg() {
   pacman -S --noconfirm --needed \
      xorg-server \
      xorg-drivers \
      xorg-xinit \
      xorg-xrandr \
      xorg-xsetroot \
      libxkbcommon \
      gnu-free-fonts \
      openssh

   localectl set-x11-keymap de
}

function install_github_pkg() {
   local pkg="$1"
   runuser -l $user -c "git clone https://github.com/ginogravanis/$pkg.git dev/$pkg"
   grep 'depends.*=' "/home/$user/dev/$pkg/PKGBUILD" | sed -E 's/.*depends.*\(([^()]*)\).*/\1/p' | sed "s/'//g" | xargs pacman -S --asdeps --noconfirm --needed
   runuser -l $user -c "cd dev/$pkg && makepkg"
   pacman -U --noconfirm /home/$user/dev/$pkg/$pkg*.zst
}

function install_bluetooth() {
   pacman -S --noconfirm --needed bluez bluez-utils
   sed -i -e "s/#AutoEnable=.*/AutoEnable=true/" /etc/bluetooth/main.conf
   systemctl enable bluetooth
}

function install_extras() {
   pacman -S --noconfirm --needed \
      pipewire \
      pipewire-alsa \
      pipewire-pulse \
      pipewire-jack \
      alsa-utils
   pacman -S --noconfirm --needed acpi feh redshift xclip
   pacman -S --noconfirm --needed firefox
}

if [[ ${BASH_SOURCE[0]} == ${0} ]]; then
   ensure_deps
   main_menu
fi
