#!/bin/bash

clear
echo "=== Checking if you can run ArchFR... ==="

# Sanity checks
[ -d /run/archiso ] || { echo "You have already installed Arch!"; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "Please run as root."; exit 1; }
grep -qi '^ID=arch' /etc/os-release || { echo "Not an Arch Linux ISO!"; exit 1; }
[ "$(cat /sys/firmware/efi/fw_platform_size 2>/dev/null)" = 64 ] || { echo "Not a UEFI system."; exit 1; }
echo "=== System Check Passed ==="

# User details
clear
echo "=== Enter your details: ==="
read -rp "Username [user]: " username; username=${username:-user}
read -rp "Hostname [autoarch]: " host; host=${host:-autoarch}
read -rp "User password [root]: " userpass; userpass=${userpass:-root}
read -rp "Root password [root]: " rootpass; rootpass=${rootpass:-root}
read -rp "Locale [en_US.UTF-8 UTF-8]: " locale; locale=${locale:-en_US.UTF-8 UTF-8}
read -rp "Timezone [Australia/Sydney]: " timezone; timezone=${timezone:-Australia/Sydney}
read -rp "Swapfile size in GB [0]: " swapfilesize; swapfilesize=${swapfilesize:-0}

# Internet setup if offline
if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
    clear
    echo "=== Internet Setup ==="
    while true; do
        ip link | awk -F: '$1 ~ /^[0-9]+$/ {print $2}' | sed 's/ //g'
        read -rp "Choose network interface: " ifce
        ip link show "$ifce" &>/dev/null && break || echo "Invalid interface."
    done

    while true; do
        iwctl station "$ifce" get-networks
        read -rp "Choose network: " net
        iwctl station "$ifce" get-networks | grep -q "$net" || { echo "Network not found."; continue; }

        while true; do
            read -rp "Wi-Fi password (or 'back'): " pass
            [ "$pass" = "back" ] && break
            iwctl --passphrase "$pass" station "$ifce" connect "$net" && ping -c 1 -W 3 8.8.8.8 &>/dev/null && {
                echo "Internet verified."; break 3
            }
            echo "Connection failed. Try again or type 'back'."
        done
    done
fi

# Package selection
clear
read -rp "1 - Minimal install, 2 - Recommended packages (1/2): " pkg
my_packages=(neovim git fastfetch gnome ghostty tmux zsh os-prober)

# Partitioning
clear
echo "=== Disk Partitioning ==="
lsblk
read -rp "Select disk (e.g., /dev/sda): " DISK
[[ -b "$DISK" ]] || { echo "Invalid disk."; exit 1; }

read -rp "Use (a) auto partition or (b) manual? [a/b]: " autopartconfirm

manual_part() {
    read -p "Use cfdisk to partition. Press ENTER to continue."
    cfdisk "$DISK"
    lsblk
    read -rp "EFI partition (e.g., /dev/sda1): " EFI_PART
    [[ -b "$EFI_PART" ]] || { echo "Invalid EFI partition."; exit 1; }
    read -rp "Root partition (e.g., /dev/sda2): " ROOT_PART
    [[ -b "$ROOT_PART" ]] || { echo "Invalid root partition."; exit 1; }
    read -rp "Format EFI partition $EFI_PART? (y/n): " confirmformat
    [[ "$confirmformat" =~ ^[Yy]$ ]] && mkfs.fat -F32 "$EFI_PART"
}

if [[ "$autopartconfirm" == "a" ]]; then
    read -rp "WARNING: Erases all data on $DISK. Confirm (yes/no): " confirm
    if [[ "$confirm" =~ ^(yes|y)$ ]]; then
        parted "$DISK" --script mklabel gpt
        parted "$DISK" --script mkpart ESP fat32 1MiB 257MiB
        parted "$DISK" --script set 1 boot on
        parted "$DISK" --script mkpart primary ext4 257MiB 100%
        EFI_PART="${DISK}1"; ROOT_PART="${DISK}2"
        mkfs.fat -F32 "$EFI_PART"
    else
        manual_part
    fi
else
    manual_part
fi

# Mount and install
mkfs.ext4 "$ROOT_PART"
mount "$ROOT_PART" /mnt
mount --mkdir "$EFI_PART" /mnt/boot/efi

sed -i '/^SigLevel/c\SigLevel = Never' /etc/pacman.conf

[[ "$pkg" == 1 ]] && pacstrap /mnt base linux linux-firmware sudo nano networkmanager grub efibootmgr || \
    pacstrap /mnt base linux linux-firmware sudo nano networkmanager grub efibootmgr "${my_packages[@]}"

if [[ "$swapfilesize" != 0 ]]; then
    dd if=/dev/zero of=/mnt/swapfile bs=1M count=$((swapfilesize*1024)) status=progress
    chmod 600 /mnt/swapfile
    mkswap /mnt/swapfile
    swapon /mnt/swapfile
fi

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
useradd -m -G wheel $username
echo "$username:$userpass" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
sed -i 's|^ExecStart=.*|ExecStart=-/sbin/agetty -a '"$username"' - \${TERM}|' /etc/systemd/system/getty.target.wants/getty@tty1.service
cat /etc/systemd/system/getty.target.wants/getty@tty1.service
mkinitcpio -P
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --modules="tpm" --disable-shim-lock
grub-mkconfig -o /boot/grub/grub.cfg
EOF

systemctl --root=/mnt enable gdm &>/dev/null

echo "=== Installation Complete! Remove installation media and reboot. ==="
