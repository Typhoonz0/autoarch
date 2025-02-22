#!/bin/bash
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

banner() {
    whiptail --title "Arch Linux Automated Install Script" --msgbox "
 █████╗ ██╗   ██╗████████╗ ██████╗  █████╗ ██████╗  ██████╗██╗  ██╗
██╔══██╗██║   ██║╚══██╔══╝██╔═══██╗██╔══██╗██╔══██╗██╔════╝██║  ██║
███████║██║   ██║   ██║   ██║   ██║███████║██████╔╝██║     ███████║
██╔══██║██║   ██║   ██║   ██║   ██║██╔══██║██╔══██╗██║     ██╔══██║
██║  ██║╚██████╔╝   ██║   ╚██████╔╝██║  ██║██║  ██║╚██████╗██║  ██║
╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝
        === Arch Linux Automated Install Script ===
    NOTE: THIS SCRIPT DOES NOT CHECK FOR INPUT ERRORS. BE CAREFUL!
                 Press ENTER to start..." 20 72
}

prompt_input() {
    response=$(whiptail --title "$1" --inputbox "$2" 0 0 "$3" --ok-button "OK" --cancel-button " " 3>&1 1>&2 2>&3)
    echo "$response"
}

clear

if [[ $(cat /sys/firmware/efi/fw_platform_size) -ne 64 ]]; then
    whiptail --title "Error" --msgbox "System is not in UEFI mode. Exiting." 8 40
    exit 1
fi

banner


usr=$(prompt_input "User Input" "Your username?" "user")
hostnm=$(prompt_input "User Input" "Your computer's hostname?" "autoarch")
userps=$(prompt_input "User Input" "Your user's password (sudo)?" "root")
rootps=$(prompt_input "User Input" "Your root password (su)?" "root")
locale=$(prompt_input "User Input" "Your locale? Leave as-is if unsure" "en_US.UTF-8 UTF-8")
timezone=$(prompt_input "User Input" "Your timezone? Country/City e.g. Australia/Tasmania" "UTC")
swapfilesize=$(prompt_input "User Input" "Swapfile (in GB)?" "0")


echo -e "User: $usr\nHostname: $hostnm\nLocale: $locale\nTimezone: $timezone\nSwapfile Size: ${swapfilesize}GB"

clear

DISK_OPTIONS=$(lsblk -o NAME,SIZE,TYPE | grep disk | awk '{print $1 " " $2}')

if [ -z "$DISK_OPTIONS" ]; then
    whiptail --title "Disk Selection" --msgbox "No disks found." 8 45
    exit 1
fi

MENU_OPTIONS=()
while IFS= read -r line; do
    NAME=$(echo "$line" | awk '{print $1}')
    SIZE=$(echo "$line" | awk '{print $2}')
    MENU_OPTIONS+=("$NAME" "$NAME ($SIZE)")
done <<< "$DISK_OPTIONS"

DISK=$(whiptail --title "Disk Selection" --menu --nocancel "Choose the disk:" 20 60 10 "${MENU_OPTIONS[@]}" 3>&1 1>&2 2>&3)

autopartconfirm=$(whiptail --title "Partitioning Method" --menu --nocancel "Choose an option:" 20 60 2 \
    a "Use only Arch Linux (auto partition)" \
    b "Dual-boot (manual partition)" \
    --ok-button "OK" 3>&1 1>&2 2>&3)

manual_part() {
    whiptail --title "Manual Partitioning" --msgbox "Manually partition your disk using cfdisk. Press ENTER to continue." 8 40
    cfdisk "/dev/$DISK"
    EFI_PART=$(prompt_input "Partition Input" "Enter EFI system partition (e.g., vda1, sda1):" "")
    ROOT_PART=$(prompt_input "Partition Input" "Enter root partition (e.g., vda2, sda2):" "")
    if [[ "$EFI_PART" == "$ROOT_PART" || -z "/dev/$EFI_PART" || -z "/dev/$ROOT_PART" ]]; then
        whiptail --title "Error" --msgbox "Invalid partition selection." 8 40
        manual_part
    fi
}

SUFFIX="$( [[ "$DISK" =~ ^nvme || "$DISK" =~ ^mmcblk ]] && echo "p" || echo "")"
if [[ "$autopartconfirm" == "a" ]]; then
    if whiptail --title "Warning" --yesno "This will erase all data on /dev/$DISK. Are you sure?" 8 40; then
        parted "/dev/$DISK" --script mklabel gpt
        parted "/dev/$DISK" --script mkpart ESP fat32 1MiB 257MiB
        parted "/dev/$DISK" --script set 1 boot on
        parted "/dev/$DISK" --script mkpart primary ext4 257MiB 100%
        EFI_PART="/dev/${DISK}${SUFFIX}1"
        ROOT_PART="/dev/${DISK}${SUFFIX}2"
    else
        manual_part
    fi
else
    manual_part
fi

if [ ! -b "$EFI_PART" ] || [ ! -b "$ROOT_PART" ]; then
    whiptail --title "Error" --msgbox "Invalid partitions detected. Exiting." 8 40
    exit 1
fi


FS_TYPE=$(whiptail --title "Filesystem Selection" --menu --nocancel "Choose a filesystem for your root partition:" 15 50 3 \
"ext4" "Choose this if unsure" \
"btrfs" "" \
"xfs" "" 3>&1 1>&2 2>&3)

case $FS_TYPE in
    ext4)
        mkfs.ext4 "$ROOT_PART"
        ;;
    btrfs)
        mkfs.btrfs "$ROOT_PART"
        ;;
    xfs)
        mkfs.xfs "$ROOT_PART"
        ;;
    *)
        echo "Invalid selection."
        exit 1
        ;;
esac

mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot/efi
if whiptail --title "Format EFI Partition" --yesno "Would you like to format your EFI partition at $EFI_PART? Click 'yes' if you only plan on using Arch Linux, click 'no' if you want to use Arch Linux alongside other existing operating systems." 20 30; then
     if whiptail --title "Are you sure?" --yesno "Are you sure you want to format $EFI_PART? If you plan on using existing operating systems on this disk, click no. Otherwise, click yes." 20 30; then
         mkfs.fat -F 32 "$EFI_PART"
     fi
fi
mount "$EFI_PART" /mnt/boot/efi

PACMANCONF="/etc/pacman.conf"
sed -i '/^SigLevel/c\SigLevel = Never' "$PACMANCONF"

reflector --country "${timezone%%/*}" --latest 5 --protocol http --protocol https --sort rate --save /etc/pacman.d/mirrorlist
additional=$(prompt_input "Additional Packages" "Any additional packages? Type them correctly as there is no check if the packages exist. Space separated:" "vim")

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
echo "$hostnm" > /etc/hostname
echo "root:$rootps" | chpasswd
useradd -m -G wheel $usr
echo "$usr:$userps" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
mkinitcpio -P
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --modules="tpm" --disable-shim-lock
grub-mkconfig -o /boot/grub/grub.cfg
EOF

whiptail --title "Arch Linux Automated Install Script" --msgbox "
 █████╗ ██╗   ██╗████████╗ ██████╗  █████╗ ██████╗  ██████╗██╗  ██╗
██╔══██╗██║   ██║╚══██╔══╝██╔═══██╗██╔══██╗██╔══██╗██╔════╝██║  ██║
███████║██║   ██║   ██║   ██║   ██║███████║██████╔╝██║     ███████║
██╔══██║██║   ██║   ██║   ██║   ██║██╔══██║██╔══██╗██║     ██╔══██║
██║  ██║╚██████╔╝   ██║   ╚██████╔╝██║  ██║██║  ██║╚██████╗██║  ██║
╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝
Installation finished! Check postinstall.txt after reboot. Click OK, remove installation media and type 'reboot'." 20 72
# Post-install instructions
curl -fsSL https://github.com/Typhoonz0/autoarch/raw/refs/heads/main/POSTINSTALL.txt -o /mnt/home/$usr/POSTINSTALL.txt
curl -fsSL https://github.com/Typhoonz0/lutil/raw/refs/heads/main/lutil.sh -o /mnt/home/$usr/lutil.sh
curl -fsSL https://github.com/Typhoonz0/dots/raw/refs/heads/main/download-dots.sh -o /mnt/home/$usr/get-my-dots.sh

clear

