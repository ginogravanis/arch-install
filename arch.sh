#!/usr/bin/env bash

set -e

user=$(logname)

deps_exist=(
   "dialog"
   "util-linux" # fdisk
)
deps_latest=("archlinux-keyring")

err() {
   local red reset
   red="$(tput setaf 1)"
   reset="$(tput sgr0)"
   echo -e "${red}[Error]${reset} $1" >&2
}

dialog_cmd() {
   dialog \
   --stdout \
   --backtitle "Arch Linux Setup" \
   "$@"
}

main_menu() {
   local selected_entry
   selected_entry=$(dialog_cmd \
      --title "Main Menu" \
      --no-items \
      --menu "" 0 0 0 \
      "1. Format disk" \
      "2. Install base system" \
      "3. Post-installation setup" \
      "4. Setup dotfiles" \
      "5. Install Neovim" \
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
         "3. Post-installation setup")
            post_install_setup
            main_menu
            ;;
         "4. Setup dotfiles")
            setup_dotfiles
            main_menu
            ;;
         "5. Install Neovim")
            install_neovim
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

ensure_deps() {
   if [ "$(whoami)" != "root" ]
   then
      err "Script must be run as root. Try: sudo $(basename "$0")"
      exit 1
   fi

	if ! test -e "/sys/firmware/efi/efivars"; then
      err "/sys/firmware/efi/efivars not found."
		err "This script only works on EFI systems."
		exit 1
	fi

   set -x

   local uncomment="s/^#//"
   sed -ie "/ParallelDownloads/{$uncomment};s/5/10/" /etc/pacman.conf
   sed -ie "/\[community\]/{$uncomment;n;$uncomment}" /etc/pacman.conf
   pacman -Sy
   pacman -S --noconfirm --needed "${deps_latest[@]}"
   pacman -S --noconfirm --needed "${deps_exist[@]}"
}

format_disk() {
   local devices disk
   read -r -a devices <<< \
      "$(lsblk -dnpo NAME,SIZE,TYPE \
      | grep 'disk$' \
      | awk '{print $1,$2}' \
      | tr '\n' '\t')"
   disk=$(dialog_cmd \
      --title "Format Disk" \
      --menu "Target disk will be partitioned into a 512MB EFI partition, and a main partition taking up the remaining disk space." 15 60 0 \
      "${devices[@]}" \
   )

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

   boot_partition=$(lsblk -nlp -o NAME | grep "$disk" | grep '1$')
   root_partition=$(lsblk -nlp -o NAME | grep "$disk" | grep '2$')

   yes | mkfs.fat -F32 "${boot_partition}"
   yes | mkfs.ext4 "${root_partition}"

   mount "${root_partition}" /mnt
   mkdir -p /mnt/boot
   mount "${boot_partition}" /mnt/boot
}

install_base_system() {
   local hostname
   hostname=$(dialog_cmd --inputbox "Hostname" 0 0)

   pacstrap /mnt base base-devel linux linux-firmware

   genfstab -U /mnt >> /mnt/etc/fstab
   echo "${hostname}" >> /mnt/etc/hostname

   local script_dir="/root/tmp"
   mkdir -p /mnt/${script_dir}
   cp "$(realpath "$0")" /mnt/${script_dir}/
   chmod +x "/mnt/${script_dir}/$(basename "$0")"

   arch-chroot /mnt bash "${script_dir}/arch.sh" chroot

   reboot
}

post_install_setup() {
   timedatectl set-ntp true
   hwclock --systohc
}

setup_dotfiles() {
   pacman -S --noconfirm git
   pacman -S --noconfirm --asdeps tk
   runuser -l "$user" -c "git clone --bare https://github.com/ginogravanis/dotfiles.git ~/.dotfiles.git"
   dot="git --git-dir=\$HOME/.dotfiles.git/ --work-tree=\$HOME"
   rm /home/"$user"/.bash_*
   runuser -l "$user" -c "$dot checkout -f main"
   runuser -l "$user" -c "$dot config --local status.showUntrackedFiles no"
}

install_neovim() {
   pacman -S --noconfirm --needed \
      ttf-nerd-fonts-symbols-common \
      ttf-joypixels \
      ttf-font-awesome \
      tmux \
      ripgrep \
      fd \
      neovim \
      jq
}

install_desktop_environment() {
   install_xorg
   install_github_pkg dmenu-pkg
   install_github_pkg st-pkg
   install_github_pkg dwm-pkg
   install_github_pkg pacman-contrib-gino
   install_bluetooth
   install_extras
   install_dev_suite
}

install_xorg() {
   pacman -S --noconfirm --needed \
      xorg-server \
      xorg-drivers \
      xorg-xinit \
      xorg-xrandr \
      xorg-xsetroot \
      libxkbcommon \
      gnu-free-fonts \
      noto-fonts \
      noto-fonts-emoji \
      noto-fonts-extra \
      libxkbcommon \

   localectl set-x11-keymap de "" "" caps:ctrl_modifier
}

install_github_pkg() {
   local pkg="$1"
   local dir="/home/$user/dev/$pkg"
   runuser -l "$user" -c "git clone https://github.com/ginogravanis/$pkg.git $dir"
   grep 'depends.*=' "$dir/PKGBUILD" \
      | sed -E 's/.*depends.*\(([^()]*)\).*/\1/p' \
      | sed "s/'//g" \
      | xargs pacman -S --asdeps --noconfirm --needed
   runuser -l "$user" -c "cd $dir && makepkg"
   pacman -U --noconfirm "$dir"/*.zst
}

install_bluetooth() {
   pacman -S --noconfirm --needed bluez bluez-utils
   sed -ie "s/#AutoEnable=.*/AutoEnable=true/" /etc/bluetooth/main.conf
   systemctl enable bluetooth
}

install_extras() {
   pacman -S --noconfirm --needed \
      bash-completion \
      pipewire \
      pipewire-alsa \
      pipewire-pulse \
      pipewire-jack \
      alsa-utils \
      acpi \
      xclip \
      unclutter \
      xwallpaper \
      sxiv \
      redshift \
      xorg-xbacklight \
      firefox \
      slock \
      rclone\
      zathura-pdf-mupdf \
      mpv \
      youtube-dl \
      mpd \
      mpc \
      ncmpcpp
}

install_dev_suite() {
   pacman -S --noconfirm --needed \
      openssh \
      docker \
      docker-compose \
      qemu-desktop \
      virt-manager

   usermod -aG docker,libvirt "$(logname)"
}

setup_locale() {
   ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
   echo "LANG=en_US.UTF-8" >> /etc/locale.conf
   echo "LC_TIME=en_GB.UTF-8" >> /etc/locale.conf
   echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
   echo "en_GB.UTF-8 UTF-8" >> /etc/locale.gen
   locale-gen
}

setup_tty() {
   # Duplicate de-latin1 keyboard layout, but remap Caps lock to Ctrl
   local keymapsdir="/usr/share/kbd/keymaps/i386/qwertz/"
   gzip -cd "$keymapsdir/de-latin1.map.gz"            \
      | sed -e "s/\(keycode\s*58 =\).*/\1 Control/"   \
      | gzip > "$keymapsdir/de-latin1-nocapslock.map.gz"
   echo "KEYMAP=de-latin1-nocapslock" > /etc/vconsole.conf

   # tty font
   pacman -S --noconfirm --needed terminus-font
   echo "FONT=ter-118b" >> /etc/vconsole.conf
   echo "FONT_MAP=8859-1" >> /etc/vconsole.conf
}

setup_network() {
   hostname=$(cat /etc/hostname)
   {
      echo "127.0.0.1   localhost"
      echo "::1         localhost"
      echo "127.0.1.1   $hostname"
   } >> /etc/hosts

   # TODO Alternatives? systemd-networkd?
   pacman -S --noconfirm --needed networkmanager # dhcpcd
   systemctl enable NetworkManager
}

update_cpu_microcode() {
   if grep "^vendor_id" /proc/cpuinfo | grep -q "Intel" && \
      grep "^model name" /proc/cpuinfo | grep -q "Intel(R)"; then
      microcode_pkg="intel-ucode"
   elif grep "^vendor_id" /proc/cpuinfo | grep -q "AMD" && \
       grep "^model name" /proc/cpuinfo | grep -q "AMD"; then
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

make_inital_ramdisk() {
   mkinitcpio -P
}

install_bootloader() {
   pacman -S --noconfirm grub efibootmgr
   grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
   grub-mkconfig -o /boot/grub/grub.cfg
}

setup_user() {
   local username
   username=$(dialog_cmd --inputbox "User name" 0 0)
   dialog_cmd --msgbox "Your initial password is the same as your username. You will be asked to change it on your first login." 0 0

   echo -e "%wheel   ALL=(ALL)   ALL" > /etc/sudoers.d/wheel

   useradd -m -G sys,wheel,power "${username}"
   echo "${username}:${username}" | chpasswd
   passwd -e "${username}"
   mv /root/tmp/arch.sh "/home/${username}/"
   rm -r /root/tmp
   chown "${username}:${username}" "/home/${username}/arch.sh"

   passwd -d root
   sed -ie "s|/root:.*|/root:/usr/bin/nologin|" /etc/passwd

   pacman -S --noconfirm --needed polkit

   echo kernel.dmesg_restrict=0 | tee -a /etc/sysctl.d/99-dmesg.conf

   echo -e "\nsudo ~/arch.sh" >> "/home/${username}/.bashrc"
}

install_manpages() {
   pacman -S --noconfirm --needed man-db
}

chroot() {
   setup_locale
   setup_tty
   setup_network
   update_cpu_microcode
   make_inital_ramdisk
   install_bootloader
   setup_user
   install_manpages
}

usage="Usage: $(basename "$0") [chroot]"

main() {
   case "$1" in
      "chroot")
         local entrypoint=chroot
         ;;
      "")
         local entrypoint=main_menu
         ;;
      *)
         err "Invalid arguments: $*"
         echo "$usage"
         exit 1
         ;;
   esac

   ensure_deps
   $entrypoint
}

main "$@"
