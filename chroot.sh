#!/usr/bin/env bash

set -e

source "$(dirname $0)/arch.sh"

function setup_clock() {
   # TODO Let user specify timezone
   ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
   timedatectl set-ntp true

   hwclock --systohc
}

function setup_locale() {
   echo "LANG=en_US.UTF-8" >> /etc/locale.conf
   echo "LC_TIME=en_GB.UTF-8" >> /etc/locale.conf
   echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
   echo "en_GB.UTF-8 UTF-8" >> /etc/locale.gen
   locale-gen

   # Duplicate de-latin1 keyboard layout, but remap Caps lock to Ctrl
   local keymapsdir=/usr/share/kbd/keymaps/i386/qwertz/
   gzip -cd "$keymapsdir/de-latin1.map.gz"            \
      | sed -e "s/\(keycode\s*58 =\).*/\1 Control/"   \
      | gzip > "$keymapsdir/de-latin1-nocapslock.map.gz"
   echo "KEYMAP=de-latin1-nocapslock" > /etc/vconsole.conf
}

function setup_network() {
   hostname=$(cat /etc/hostname)
   echo "127.0.0.1   localhost" >> /etc/hosts
   echo "::1         localhost" >> /etc/hosts
   echo "127.0.1.1   $hostname" >> /etc/hosts

   # TODO Alternatives? systemd-networkd?
   pacman -S --noconfirm --needed networkmanager # dhcpcd
   systemctl enable NetworkManager
}

function update_cpu_microcode() {
   if cat /proc/cpuinfo | grep "^vendor_id" | grep -q "Intel" && \
      cat /proc/cpuinfo | grep "^model name" | grep -q "Intel(R)"; then
      microcode_pkg="intel-ucode"
   elif cat /proc/cpuinfo | grep "^vendor_id" | grep -q "AMD" && \
      cat /proc/cpuinfo | grep "^model name" | grep -q "AMD"; then
      microcode_pkg="amd-ucode"
   else
      cpu_vendor=$(dialog_cmd \
         --no-items \
         --title "Select CPU vendor" \
         --menu "Can't detect CPU vendor. Please select:" 0 0 0 \
         "AMD" "Intel"
      )
      case $cpu_vendor in
         "AMD")
            microcode_pkg="amd-ucode"
            ;;
         "Intel")
            microcode_pkg="intel-ucode"
            ;;
         *)
            exit
      esac
   fi
   pacman -S --noconfirm ${microcode_pkg}
}

function make_inital_ramdisk() {
   mkinitcpio -P
}

function install_bootloader() {
   pacman -S --noconfirm grub efibootmgr
   grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
   grub-mkconfig -o /boot/grub/grub.cfg
}

function setup_user() {
   local username=$(dialog_cmd --inputbox "User name" 0 0)
   dialog_cmd --msgbox "Your initial password is the same as your username. You will be asked to change it on your first login." 0 0

   echo -e "%wheel   ALL=(ALL)   ALL" > /etc/sudoers.d/wheel

   useradd -m -G sys,wheel,power "${username}"
   echo "${username}:${username}" | chpasswd
   passwd -e "${username}"
   mv /root/tmp/arch.sh "/home/${username}/"
   rm -r /root/tmp
   chown "${username}:${username}" "/home/${username}/arch.sh"

   passwd -d root
   sed -ie "s|/root:.*|/root:/sbin/nologin|" /etc/passwd

   pacman -S --noconfirm --needed polkit

   # Allow all users to run dmesg
   echo kernel.dmesg_restrict=0 | sudo tee -a /etc/sysctl.d/99-dmesg.conf
}

function install_manpages() {
   pacman -S --noconfirm --needed man-db
}


if [[ ${BASH_SOURCE[0]} == ${0} ]]; then
   setup_clock
   setup_locale
   setup_network
   update_cpu_microcode
   make_inital_ramdisk
   install_bootloader
   setup_user
   install_manpages
fi
