#!/bin/bash

echo "=== Checking if you can run ArchFR... ==="

# Exit if not in Arch ISO
#[ -d /run/archiso ] || { echo "You have already installed Arch! Ignore"; exit 1; }

# Exit if not root
[ "$(id -u)" -eq 0 ] || { echo "Please run this script with sudo or as the root user."; exit 1; }

# Exit if not Arch Linux
grep -qi '^ID=arch' /etc/os-release || { echo "You aren't running an Arch Linux ISO!"; exit 1; }

# Exit if not UEFI
[ "$(cat /sys/firmware/efi/fw_platform_size 2>/dev/null)" = 64 ] || { echo "You are not on a UEFI system."; exit 1; }

echo "=== You can run ArchFR! ==="


# Enter script - ask for user details
echo "=== Enter your details: ==="
username="user"
printf "Your username? " && read username
username=${username:-"user"}
printf "Your computer's hostname? " && read host
host=${host:-"autoarch"}
printf "Your user's password (sudo)? " && read userpass
userpass=${userpass:-"root"}
printf "Your root password (su)? " && read rootpass
rootpass=${rootpass:-"root"}
printf "Your locale (Press ENTER for: en_US.UTF-8 UTF-8)? " && read locale
locale=${locale:-"en_US.UTF-8 UTF-8"}
printf "Your timezone (e.g., UTC, Australia/Sydney)? " && read timezone
timezone=${timezone:-"Australia/Sydney"}
printf "Swapfile (in GB)? " && read swapfilesize
swapfilesize=${swapfilesize:-"0"}

if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
    echo "=== Setting up Internet ==="

    while true; do
        ip link | awk -F: '$1 ~ /^[0-9]+$/ {print $2}' | sed 's/ //g'
        read -p "Choose network interface? " ifce
        ip link show "$ifce" &>/dev/null && break || echo "Invalid interface."
    done

    while true; do
        iwctl station "$ifce" get-networks
        read -p "Choose network? " net
        iwctl station "$ifce" get-networks | grep -q "$net" || { echo "Network not found."; continue; }

        while true; do
            read -p "Wi-Fi password (or 'back' to choose another network): " pass
            [ "$pass" = "back" ] && break
            iwctl --passphrase "$pass" station "$ifce" connect "$net" && {
                echo "Connected. Checking internet..."
                ping -c 1 -W 3 8.8.8.8 &>/dev/null && {
                    echo "Internet connection verified."
                    exit 0
                } || {
                    echo "Connected to Wi-Fi, but no internet. Try again or 'back'."
                    iwctl station "$ifce" disconnect
                }
            }
            echo "Failed to connect. Try again or type 'back'."
        done
    done
fi

printf "1 - Minimal install, 2 - Recommended packages (1/2)? " && read pkg

my_packages=(neovim git fastfetch gnome ghostty tmux zsh os-prober)

echo "=== Disk Partitioning ==="
lsblk
read -rp "Choose the disk (e.g., /dev/vda, /dev/sda, /dev/nvme0n1): " DISK
[[ -b "$DISK" ]] || { echo "Disk $DISK not found."; exit 1; }

read -rp "Use (a) auto partition (wipe) or (b) manual partition? [a/b]: " autopartconfirm

manual_part() {
    echo "Run cfdisk to manually partition (use GPT table if asked). Press ENTER to continue."
    read
    cfdisk "$DISK"
    lsblk
    read -rp "Enter EFI partition (full path, e.g., /dev/sda1): " EFI_PART
    [[ -b "$EFI_PART" ]] || { echo "EFI partition $EFI_PART not found."; exit 1; }
    read -rp "Enter root partition (full path, e.g., /dev/sda2): " ROOT_PART
    [[ -b "$ROOT_PART" ]] || { echo "Root partition $ROOT_PART not found."; exit 1; }
}

if [[ "$autopartconfirm" == "a" ]]; then
    read -rp "WARNING: This will erase all data on $DISK. Confirm (yes/no): " confirm
    if [[ "$confirm" =~ ^(yes|y)$ ]]; then
        parted "$DISK" --script mklabel gpt
        parted "$DISK" --script mkpart ESP fat32 1MiB 257MiB
        parted "$DISK" --script set 1 boot on
        parted "$DISK" --script mkpart primary ext4 257MiB 100%
        EFI_PART="${DISK}1"
        ROOT_PART="${DISK}2"
        mkfs.fat -F32 "$EFI_PART"
    else
        manual_part
    fi
else
    manual_part
fi

mkfs.ext4 "$ROOT_PART"
mount "$ROOT_PART" /mnt

read -rp "Format EFI partition $EFI_PART? (y/n): " confirmformat
[[ "$confirmformat" =~ ^[Yy]$ ]] && mkfs.fat -F32 "$EFI_PART"
mount --mkdir "$EFI_PART" /mnt/boot/efi

sed -i '/^SigLevel/c\SigLevel = Never' /etc/pacman.conf

country=${timezone%%/*}
[[ "$timezone" != */* ]] && country="$timezone"

if [[ "$pkg" == 1 ]]; then
  pacstrap /mnt base linux linux-firmware sudo nano networkmanager grub efibootmgr
else
  pacstrap /mnt base linux linux-firmware sudo nano networkmanager grub efibootmgr "${my_packages[@]}"
fi

[[ "$swapfilesize" != 0 ]] && dd if=/dev/zero of=/mnt/swapfile bs=1M count=$((swapfilesize*1024)) status=progress && chmod 600 /mnt/swapfile && mkswap /mnt/swapfile && swapon /mnt/swapfile

genfstab -U /mnt >> /mnt/etc/fstab

# Chroot configuration
arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc
sed -i 's/#$locale/$locale/' /etc/locale.gen
locale-gen
echo "LANG=${locale%% *}" > /etc/locale.conf
echo "$host" > /etc/hostname
echo "root:$rootpass" | chpasswd
useradd -m -G wheel $user
echo "$user:$userpass" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
mkinitcpio -P
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --modules="tpm" --disable-shim-lock
grub-mkconfig -o /boot/grub/grub.cfg
EOF

echo "Installation complete! Remove installation media and type 'reboot'."
systemctl --root=/mnt enable gdm >/dev/null 2>&1
