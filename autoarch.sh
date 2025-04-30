#!/bin/bash
# hell yeah
export NEWT_COLORS='
window=white,gray
border=lightgray,gray
shadow=white,black
button=black,cyan
actbutton=black,cyan
compactbutton=lightgray,black
title=cyan,gray
roottext=cyan,black
textbox=lightgray,gray
acttextbox=gray,white
entry=black,lightgray
disentry=gray,black
checkbox=black,lightgray
actcheckbox=black,green
emptyscale=,lightgray
fullscale=,grey
listbox=black,lightgray
actlistbox=lightgray,black
actsellistbox=black,cyan
'

[[ $(cat /sys/firmware/efi/fw_platform_size) -ne 64 ]] && \
  whiptail --title "Error" --msgbox "System is not in UEFI mode. Exiting." 8 40 && exit 1

whiptail --title "Arch Linux Automated Install Script" --msgbox "
 █████╗ ██╗   ██╗████████╗ ██████╗  █████╗ ██████╗  ██████╗██╗  ██╗
██╔══██╗██║   ██║╚══██╔══╝██╔═══██╗██╔══██╗██╔══██╗██╔════╝██║  ██║
███████║██║   ██║   ██║   ██║   ██║███████║██████╔╝██║     ███████║
██╔══██║██║   ██║   ██║   ██║   ██║██╔══██║██╔══██╗██║     ██╔══██║
██║  ██║╚██████╔╝   ██║   ╚██████╔╝██║  ██║██║  ██║╚██████╗██║  ██║
╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝
            === Arch Linux Automated Install Script ===
                 Press ENTER to start..." 20 72

prompt_input() { whiptail --title "$1" --inputbox "$2" 0 0 "$3" 3>&1 1>&2 2>&3; }

user=$(prompt_input "Username" "Enter your username:" "user")
hostname=$(prompt_input "Hostname" "Enter your hostname:" "autoarch")
userpass=$(prompt_input "User Password" "Enter user's password:" "root")
rootpass=$(prompt_input "Root Password" "Enter root password:" "root")
locale=$(prompt_input "Locale" "Enter your locale (e.g., en_US.UTF-8 UTF-8):" "en_US.UTF-8 UTF-8")
timezone=$(prompt_input "Timezone" "Enter your timezone (e.g., Australia/Tasmania):" "UTC")
swapfilesize=$(prompt_input "Swapfile Size" "Enter swapfile size in GB:" "0")

mapfile -t entries < <(lsblk -o NAME,SIZE,TYPE -n | awk '$3=="disk" {gsub(/[[:graph:]]*─/, "", $1); print $1 " (" $2 ")"}')
disk=$(whiptail --title "Select Disk" --menu "Choose a disk:" 20 60 10 $(for e in "${entries[@]}"; do echo "$e"; done) 3>&1 1>&2 2>&3) && echo "Selected: $disk"

if ! whiptail --title "Partitioning" --yesno "No = Auto Partition /dev/$disk | Yes = Manual Partition" 8 60; then
  parted "/dev/$disk" --script mklabel gpt
  parted "/dev/$disk" --script mkpart ESP fat32 1MiB 257MiB
  parted "/dev/$disk" --script set 1 boot on
  parted "/dev/$disk" --script mkpart primary ext4 257MiB 100%
  efipart="/dev/${disk}${SUFFIX}1"
  rootpart="/dev/${disk}${SUFFIX}2"
  mkfs.fat -F32 "$efipart"
else
  whiptail --title "Manual Partitioning" --msgbox "You'll now partition using cfdisk. Press ENTER to continue." 8 50
  cfdisk "/dev/$disk"
  mapfile -t entries < <(lsblk -o NAME,SIZE,TYPE -n | awk '$3=="part" {gsub(/[[:graph:]]*─/, "", $1); print $1 " (" $2 ")"}')
  rootpart=$(whiptail --title "Select Root Partition" --menu "Choose root partition:" 20 60 10 $(for p in "${parts[@]}"; do echo "$p"; done) 3>&1 1>&2 2>&3)
  efipart=$(whiptail --title "Select EFI Partition" --menu "Choose EFI partition:" 20 60 10 $(for p in "${parts[@]}"; do echo "$p"; done) 3>&1 1>&2 2>&3)
  rootpart="/dev/$rootpart"
  efipart="/dev/$efipart"
  if whiptail --title "Wipe EFI Partition" --yesno "Do you want to wipe the EFI partition ($efipart)?" 8 60; then
    mkfs.fat -F32 "$efipart"
  fi
fi

mkfs.ext4 "$rootpart"
mount "$rootpart" /mnt
mount --mkdir "$efipart" /mnt/boot/efi

PACMANCONF="/etc/pacman.conf"
sed -i '/^SigLevel/c\SigLevel = Never' "$PACMANCONF"

reflector --country "${timezone%%/*}" --latest 5 --protocol http --protocol https --sort rate --save /etc/pacman.d/mirrorlist
additional=$(prompt_input "Additional Packages" "Any additional packages? Type them correctly as there is no check if the packages exist. Space separated:" "")

pacstrap -K /mnt base grub efibootmgr linux linux-firmware sudo nano networkmanager $additional

if [[ "$swapfilesize" -ne 0 ]]; then
    SWAP_FILE="/mnt/swapfile"
    dd if=/dev/zero of="$SWAP_FILE" bs=1M count=$((swapfilesize * 1024)) status=progress
    chmod 600 "$SWAP_FILE"
    mkswap "$SWAP_FILE"
    swapon "$SWAP_FILE"
fi

genfstab -U /mnt >> /mnt/etc/fstab
cp /etc/pacman.conf /mnt/etc/pacman.conf

arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc
sed -i 's/#$locale/$locale/' /etc/locale.gen
locale-gen
echo "LANG=${locale%% *}" > /etc/locale.conf
echo "$hostname" > /etc/hostname
echo "root:$rootpass" | chpasswd
useradd -m -G wheel $user
echo "$user:$userpass" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
mkinitcpio -P
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --modules="tpm" --disable-shim-lock
grub-mkconfig -o /boot/grub/grub.cfg
EOF

curl -fsSL https://github.com/Typhoonz0/lutil/raw/refs/heads/main/lutil.sh -o /mnt/home/$user/lutil.sh && chmod +x /mnt/home/$user/lutil.sh
curl -fsSL https://github.com/Typhoonz0/dots/raw/refs/heads/main/download-dots.sh -o /mnt/home/$user/get-my-dots.sh && chmod +x /mnt/home/$user/get-my-dots.sh
curl -fsSL https://github.com/Typhoonz0/autoarch/raw/refs/heads/main/steamscript.sh -o /mnt/home/$user/autosteam.sh && chmod +x /mnt/home/$user/autosteam.sh
systemctl --root=/mnt enable NetworkManager >/dev/null 2>&1
if [ $additional ?? "gnome" ]; then
    systemctl --root=/mnt enable gdm >/dev/null 2>&1 
fi 
if [ $additional ?? "plasma" ]; then
    systemctl --root=/mnt enable sddm >/dev/null 2>&1 
fi 

whiptail --title "Arch Linux Automated Install Script" --msgbox "
 █████╗ ██╗   ██╗████████╗ ██████╗  █████╗ ██████╗  ██████╗██╗  ██╗
██╔══██╗██║   ██║╚══██╔══╝██╔═══██╗██╔══██╗██╔══██╗██╔════╝██║  ██║
███████║██║   ██║   ██║   ██║   ██║███████║██████╔╝██║     ███████║
██╔══██║██║   ██║   ██║   ██║   ██║██╔══██║██╔══██╗██║     ██╔══██║
██║  ██║╚██████╔╝   ██║   ╚██████╔╝██║  ██║██║  ██║╚██████╗██║  ██║
╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝
Installation finished! Click OK, remove installation media and type 'reboot'." 20 72
