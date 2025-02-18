#!/bin/bash

clear
cat <<EOF

 █████╗ ██╗   ██╗████████╗ ██████╗  █████╗ ██████╗  ██████╗██╗  ██╗
██╔══██╗██║   ██║╚══██╔══╝██╔═══██╗██╔══██╗██╔══██╗██╔════╝██║  ██║
███████║██║   ██║   ██║   ██║   ██║███████║██████╔╝██║     ███████║
██╔══██║██║   ██║   ██║   ██║   ██║██╔══██║██╔══██╗██║     ██╔══██║
██║  ██║╚██████╔╝   ██║   ╚██████╔╝██║  ██║██║  ██║╚██████╗██║  ██║
╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝
        === Arch Linux Automated Install Script ===

EOF


if [[ $(cat /sys/firmware/efi/fw_platform_size) -ne 64 ]]; then
    echo "Error: System is not in UEFI mode. Exiting."
    exit 1
fi

prompt() {
    echo -ne "[\e[31m$usr\e[0m@\e[32mautoarch\e[0m] \e[36m$\e[0m "
}

echo "Your username? "
echo -ne "[\e[31muser\e[0m@\e[32mautoarch\e[0m] \e[36m$\e[0m "
read usr

echo "Your computer's hostname? "
prompt
read hostnm

echo "Your user's password (sudo)? "
prompt
read userps

echo "Your root password (su root)? "
prompt
read rootps

echo "Your locale (Type 'en_US.UTF-8 UTF-8' WITHOUT QUOTES if you are unsure)? "
prompt
read locale

echo "Your timezone (e.g. UTC, Canada/Vancouver, Australia/Sydney, Europe/Amsterdam, etc)? "
prompt
read timezone

clear
echo "=== Setting up Internet ==="

if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    echo "Internet is available, proceeding"
else
    ip link
    echo "Choose the network interface you wish to use (choose wlan0 if it is above and you are unsure)?"
    prompt
    read ifce
    iwctl station $ifce get-networks
    echo "Choose the network to connect above?"
    prompt
    read networkname
    iwctl station $ifce connect $networkname
fi

clear
# Partitioning
echo "=== Disk Partitioning ==="
lsblk
echo "Choose the DISK (vda, sda, nvme0n1 etc.) you wish to install Arch on."
prompt
read DISK
echo "You are going to manually partition your disk using cfdisk. Type 'help' WITHOUT QUOTES if you need it, otherwise just press ENTER."
echo "Choose the gpt table option if it asks you."
read A

if [[ "$A" == "help" ]]; then
    echo "If you plan to only use Linux:"
    echo "Create a 250m partition and change the type to EFI system, then use the remaining space to create a Linux Filesystem partition."
    echo "If you plan to use Linux alongside something else:"
    echo "Shrink a partition of your choice (choose the largest if unsure) then in the new space, create a Linux Filesystem partition."
    echo "If you need more info than this, google 'cfdisk tutorial'"
    echo "Press ENTER to continue."
    read A
fi
cfdisk /dev/$DISK
echo "=== Partitioning Complete ==="
sleep 1
lsblk
echo "What is your EFI system PARTITION? (e.g. vda1, sda1, nvme0n1p1 etc) "
prompt
read EFI_PART
EFI_PART="/dev/$EFI_PART"

echo "What is your ROOT PARTITION? (e.g. vda2, sda2, nvme0n1p2 etc) "
prompt
read ROOT_PART
ROOT_PART="/dev/$ROOT_PART"

echo "=== Formatting Partitions ==="
mkfs.ext4 "$ROOT_PART"
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot/efi
echo "Do you want to keep other bootloaders (Windows etc.) (y/n)? "
prompt
read CHOOSE

if [[ "$CHOOSE" == "n" || "$CHOOSE" == "N" ]]; then
    echo "User has chosen to format $EFI_PART"
    mkfs.fat -F 32 "$EFI_PART"
fi

mount "$EFI_PART" /mnt/boot/efi

PACMAN_CONF="/etc/pacman.conf"

sed -i '/^SigLevel/c\SigLevel = Never' "$PACMAN_CONF"

if grep -q "^SigLevel = Never" "$PACMAN_CONF"; then
    echo 
else
    echo "Failed to modify the SigLevel line in $PACMAN_CONF."
fi
clear 

echo "=== Installing Base System ==="
echo "Finding the best mirrors..."
country=${timezone%%/*}
reflector --country $country --latest 5 --protocol http --protocol https --sort rate --save /etc/pacman.d/mirrorlist
clear
echo "Which graphical enviroment would you like?"
echo "plasma for KDE Plasma, gnome for Gnome etc."
echo "Or hit ENTER to skip." 
prompt 
read additional
clear
echo "This install script comes with the following packages:"
echo "base linux linux-firmware grub efibootmgr sudo nano networkmanager"
echo "This will leave you with a working computer, but you will certainly need more apps to be productive."
echo "Any additional packages? Space seperated, no commas. There is no check if the packages exist so type carefully."
echo "e.g: firefox vim pulseaudio bluez"
echo "Or hit ENTER to skip."
prompt
read additionaltw
pacstrap -K /mnt base grub efibootmgr linux linux-firmware sudo nano networkmanager $additional $additionaltw

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot and Configure System
arch-chroot /mnt /bin/bash <<EOF
echo "=== Configuring System ==="
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc

sed -i 's/#$locale/$locale/' /etc/locale.gen
locale-gen

localetwo=${locale%% *}

echo "LANG=$localetwo" > /etc/locale.conf

echo "$hostnm" > /etc/hostname
echo "root:$rootps" | chpasswd
useradd -m -G wheel $usr

echo "$usr:$userps" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Configure Bootloader
mkinitcpio -P
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --modules="tpm" --disable-shim-lock
grub-mkconfig -o /boot/grub/grub.cfg

EOF
# Unmount and Finish
clear 

touch /mnt/home/$usr/POSTINSTALL.txt
cat <<EOF > /mnt/home/$usr/POSTINSTALL.txt
After Installation:

I have no internet?
Type sudo systemctl enable --now NetworkManager to enable the network utility, then use the settings app on your computer to connect, or alternatively, type nmtui into the command line.

How do I install apps?
Apps on Linux are called packages, and you install them on the command line through a package manager.
Arch Linux uses the pacman package manager.
Type sudo pacman -S <package> to install a package.

How do I remove apps?
Type sudo pacman -R <package>.

How do I update my computer?
Type sudo pacman -Syu.

I'm still in a black box? 
Install a graphical enviroment such as plasma-desktop or gnome and enable the appropriate service, e.g. for Gnome:
sudo systemctl enable --now gdm

thanks for using autoarch - liam
EOF

cat <<EOF
Thanks for using...

 █████╗ ██╗   ██╗████████╗ ██████╗  █████╗ ██████╗  ██████╗██╗  ██╗
██╔══██╗██║   ██║╚══██╔══╝██╔═══██╗██╔══██╗██╔══██╗██╔════╝██║  ██║
███████║██║   ██║   ██║   ██║   ██║███████║██████╔╝██║     ███████║
██╔══██║██║   ██║   ██║   ██║   ██║██╔══██║██╔══██╗██║     ██╔══██║
██║  ██║╚██████╔╝   ██║   ╚██████╔╝██║  ██║██║  ██║╚██████╗██║  ██║
╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝

EOF


echo "=== Installation Complete ==="
umount -R /mnt
echo "Remove installation media and type 'reboot' to finish."
echo "After rebooting, cat /home/$usr/POSTINSTALL.txt for instructions after the installation."
