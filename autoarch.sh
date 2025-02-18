#!/bin/bash
banner() {
cat <<EOF

 █████╗ ██╗   ██╗████████╗ ██████╗  █████╗ ██████╗  ██████╗██╗  ██╗
██╔══██╗██║   ██║╚══██╔══╝██╔═══██╗██╔══██╗██╔══██╗██╔════╝██║  ██║
███████║██║   ██║   ██║   ██║   ██║███████║██████╔╝██║     ███████║
██╔══██║██║   ██║   ██║   ██║   ██║██╔══██║██╔══██╗██║     ██╔══██║
██║  ██║╚██████╔╝   ██║   ╚██████╔╝██║  ██║██║  ██║╚██████╗██║  ██║
╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝
        === Arch Linux Automated Install Script ===

EOF
}
clear
# Ensure UEFI mode
if [[ $(cat /sys/firmware/efi/fw_platform_size) -ne 64 ]]; then
    echo "Error: System is not in UEFI mode. Exiting."
    exit 1
fi

# Prompt function
prompt() {
    echo -ne "[\e[31m$usr\e[0m@\e[32mautoarch\e[0m] \e[36m$\e[0m "
}
banner
usr="autoarch"
# User inputs
echo "Your username?" && prompt && read usr
echo "Your computer's hostname?" && prompt && read hostnm
echo "Your user's password (sudo)?" && prompt && read userps
echo "Your root password (su)?" && prompt && read rootps
echo "Your locale (Press ENTER for: en_US.UTF-8 UTF-8)?" && prompt && read locale
locale=${locale:-"en_US.UTF-8 UTF-8"}
echo "Your timezone (e.g., UTC, Australia/Sydney)?" && prompt && read timezone
timezone=${timezone:-"UTC"}

clear
if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    echo "=== Setting up Internet ==="
    ip link
    echo "Choose network interface (e.g., wlan0):" && prompt && read ifce
    iwctl station $ifce get-networks
    echo "Choose network to connect to:" && prompt && read networkname
    iwctl station $ifce connect $networkname
fi

clear
echo "=== Disk Partitioning ==="
lsblk
echo "Choose the disk (e.g., vda, sda, nvme0n1):" && prompt && read DISK
echo "Are you going to (a) use only Arch Linux or (b) dual-boot?" && prompt && read autopartconfirm

manual_part() {
    echo "Manually partition your disk using cfdisk (choose GPT table). Press ENTER to continue."
    read
    cfdisk /dev/$DISK
    lsblk
    echo "Enter EFI system partition (e.g., vda1, sda1):" && prompt && read EFI_PART
    EFI_PART="/dev/$EFI_PART"
    echo "Enter root partition (e.g., vda2, sda2):" && prompt && read ROOT_PART
    ROOT_PART="/dev/$ROOT_PART"
}

if [[ "$autopartconfirm" == "a" ]]; then 
    echo "Warning: This will erase all data on /dev/$DISK. Are you sure? (yes/no)"
    prompt && read confirm
    if [[ "$confirm" == "yes" || "$confirm" == "y" ]]; then
        parted /dev/$DISK --script mklabel gpt
        parted /dev/$DISK --script mkpart ESP fat32 1MiB 257MiB
        parted /dev/$DISK --script set 1 boot on
        parted /dev/$DISK --script mkpart primary ext4 257MiB 100%
        EFI_PART="/dev/${DISK}1"
        ROOT_PART="/dev/${DISK}2"
        mkfs.fat -F 32 "$EFI_PART"
    else
        manual_part
    fi
else 
    manual_part
fi

# Format and mount partitions
mkfs.ext4 "$ROOT_PART"
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot/efi
mount "$EFI_PART" /mnt/boot/efi

# Configure pacman
PACMANCONF="/etc/pacman.conf"
sed -i '/^SigLevel/c\SigLevel = Never' "$PACMANCONF"

# Install base system
# Configure best mirrors
if [[ "$timezone" == *"/"* ]]; then 
  country=${timezone%%/*} 
else 
  country="$timezone" 
fi
reflector --country "$country" --latest 5 --protocol http --protocol https --sort rate --save /etc/pacman.d/mirrorlist
echo "Any additional packages? Space seperated, no commas. There is no check if the packages exist so type carefully."
echo "Here is a good time to choose a graphical enviroment, like GNOME."
echo "Or, just hit ENTER to skip."
echo "(e.g. firefox vim gnome):" && prompt && read additional
echo "Sit back and relax (:"
pacstrap -K /mnt base grub efibootmgr linux linux-firmware sudo nano networkmanager $additional 
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot configuration
arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc
sed -i 's/#$locale/$locale/' /etc/locale.gen
locale-gen
echo "LANG=${locale%% *}" > /etc/locale.conf
echo "$hostnm" > /etc/hostname
echo "root:$rootps" | chpasswd
useradd -m -G wheel $usr
echo "$usr:$userps" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
mkinitcpio -P
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --modules="tpm" --disable-shim-lock
grub-mkconfig -o /boot/grub/grub.cfg
EOF

# Post-install instructions
curl -fsSL https://github.com/Typhoonz0/autoarch/raw/refs/heads/main/POSTINSTALL.txt -o /mnt/home/$usr/POSTINSTALL.txt

# Unmount and finish
clear
banner
echo "Installation complete! Remove installation media and type 'reboot'."
echo "After rebooting, check /home/$usr/POSTINSTALL.txt for further instructions."
umount -R /mnt
