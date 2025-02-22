#!/bin/bash

banner() {
    whiptail --title "Arch Linux Automated Install Script" --msgbox "
 █████╗ ██╗   ██╗████████╗ ██████╗  █████╗ ██████╗  ██████╗██╗  ██╗
██╔══██╗██║   ██║╚══██╔══╝██╔═══██╗██╔══██╗██╔══██╗██╔════╝██║  ██║
███████║██║   ██║   ██║   ██║   ██║███████║██████╔╝██║     ███████║
██╔══██║██║   ██║   ██║   ██║   ██║██╔══██║██╔══██╗██║     ██╔══██║
██║  ██║╚██████╔╝   ██║   ╚██████╔╝██║  ██║██║  ██║╚██████╗██║  ██║
╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝
        === Arch Linux Automated Install Script ===
                   Press ENTER to start...
" 20 72
}

prompt_input() {
    local title="$1"
    local prompt="$2"
    local default="$3"
    
    # Show input box with only OK button
    response=$(whiptail --title "$title" --inputbox "$prompt" 0 0 "$default" --ok-button "OK" --cancel-button " " 3>&1 1>&2 2>&3)
    echo "$response"
}

clear

# Ensure UEFI mode
if [[ $(cat /sys/firmware/efi/fw_platform_size) -ne 64 ]]; then
    whiptail --title "Error" --msgbox "System is not in UEFI mode. Exiting." 8 40
    exit 1
fi

banner

# User inputs
usr=$(prompt_input "User Input" "Your username?" "user")
hostnm=$(prompt_input "User Input" "Your computer's hostname?" "autoarch")
userps=$(prompt_input "User Input" "Your user's password (sudo)?" "root")
rootps=$(prompt_input "User Input" "Your root password (su)?" "root")
locale=$(prompt_input "User Input" "Your locale?" "en_US.UTF-8 UTF-8")
timezone=$(prompt_input "User Input" "Your timezone (e.g., UTC, Australia/Tasmania)?" "UTC")
swapfilesize=$(prompt_input "User Input" "Swapfile (in GB)?" "0")

clear

if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    whiptail --title "Setting up Internet" --msgbox "Choose network interface (e.g., wlan0):" 8 40
    ifce=$(prompt_input "Network Interface" "Enter network interface:" "")
    iwctl station "$ifce" get-networks
    networkname=$(prompt_input "Network" "Choose network to connect to:" "")
    iwctl station "$ifce" connect "$networkname"
fi

clear


# Collect disk options from lsblk, filtering for disks
DISK_OPTIONS=$(lsblk -o NAME,SIZE,TYPE | grep disk | awk '{print $1 " " $2}')

# Check if any disks were found
if [ -z "$DISK_OPTIONS" ]; then
    whiptail --title "Disk Selection" --msgbox "No disks found." 8 45
    exit 1
fi

# Prepare the options for whiptail in the correct format
MENU_OPTIONS=()
while IFS= read -r line; do
    NAME=$(echo "$line" | awk '{print $1}')
    SIZE=$(echo "$line" | awk '{print $2}')
    MENU_OPTIONS+=("$NAME" "$NAME ($SIZE)")  # Pair of name and description
done <<< "$DISK_OPTIONS"

# Check if MENU_OPTIONS array is empty
if [ ${#MENU_OPTIONS[@]} -eq 0 ]; then
    whiptail --title "Disk Selection" --msgbox "No disks available for selection." 8 45
    exit 1
fi

# Call whiptail directly with formatted options
DISK=$(whiptail --title "Disk Selection" \
    --menu "Choose the disk:" \
    20 60 10 \
    "${MENU_OPTIONS[@]}" 3>&1 1>&2 2>&3)

autopartconfirm=$(whiptail --title "Partitioning Method" --menu "Choose an option:" 20 60 2 \
    a "Use only Arch Linux (auto partition)" \
    b "Dual-boot (manual partition)" \
    --ok-button "OK" --cancel-button " " 3>&1 1>&2 2>&3)

manual_part() {
    whiptail --title "Manual Partitioning" --msgbox "Manually partition your disk using cfdisk (choose GPT table). Press ENTER to continue." 8 40
    cfdisk "/dev/$DISK"
    EFI_PART=$(prompt_input "Partition Input" "Enter EFI system partition (e.g., vda1, sda1):" "")
    EFI_PART="/dev/$EFI_PART"
    ROOT_PART=$(prompt_input "Partition Input" "Enter root partition (e.g., vda2, sda2):" "")
    ROOT_PART="/dev/$ROOT_PART"
}

get_partition_suffix() {
    if [[ "$DISK" =~ ^nvme || "$DISK" =~ ^mmcblk ]]; then
        echo "p"
    else
        echo ""
    fi
}

SUFFIX=$(get_partition_suffix)
if [[ "$autopartconfirm" == "a" ]]; then 
    # Show confirmation dialog
    if whiptail --title "Warning" --yesno "This will erase all data on /dev/$DISK. Are you sure?" 8 40; then
        # User confirmed, proceed with partitioning
        parted "/dev/$DISK" --script mklabel gpt
        parted "/dev/$DISK" --script mkpart ESP fat32 1MiB 257MiB
        parted "/dev/$DISK" --script set 1 boot on
        parted "/dev/$DISK" --script mkpart primary ext4 257MiB 100%
        
        # Define partition variables
        EFI_PART="/dev/${DISK}${SUFFIX}1"
        ROOT_PART="/dev/${DISK}${SUFFIX}2"
        
        # Format the EFI partition
        mkfs.fat -F 32 "$EFI_PART"
    else
        # User chose not to proceed, call manual partitioning function
        manual_part
    fi
else 
    # If autopartconfirm is not "a", call manual partitioning function
    manual_part
fi


# Format and mount partitions
mkfs.ext4 "$ROOT_PART"
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot/efi

if whiptail --title "Format EFI Partition" --yesno "Would you like to format your EFI partition at $EFI_PART? This is only needed if you do NOT have any other bootloaders installed." 20 30; then
     mkfs.fat -F 32 "$EFI_PART"
fi

mount "$EFI_PART" /mnt/boot/efi
# Configure pacman
PACMANCONF="/etc/pacman.conf"
sed -i '/^SigLevel/c\SigLevel = Never' "$PACMANCONF"

# Install base system
if [[ "$timezone" == *"/"* ]]; then 
    country=${timezone%%/*} 
else 
    country="$timezone" 
fi

reflector --country "$country" --latest 5 --protocol http --protocol https --sort rate --save /etc/pacman.d/mirrorlist
additional=$(prompt_input "Additional Packages" "Any additional packages? Space separated, no commas. (e.g. firefox vim gnome fastfetch):" "")

pacstrap -K /mnt base grub efibootmgr linux linux-firmware sudo nano networkmanager $additional 

SWAP_FILE="/mnt/swapfile"  
if [[ "$swapfilesize" == "0" ]]; then
  echo 
else
  dd if=/dev/zero of="$SWAP_FILE" bs=1M count=$((swapfilesize * 1024)) status=progress
  chmod 600 "$SWAP_FILE"
  mkswap "$SWAP_FILE"
  swapon "$SWAP_FILE"
fi

genfstab -U /mnt >> /mnt/etc/fstab
rm /mnt/etc/pacman.conf
cp /etc/pacman.conf /mnt/etc/pacman.conf
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
curl -fsSL https://github.com/Typhoonz0/lutil/raw/refs/heads/main/lutil.sh -o /mnt/home/$usr/lutil.sh
curl -fsSL https://github.com/Typhoonz0/dots/raw/refs/heads/main/download-dots.sh -o /mnt/home/$usr/get-my-dots.sh

clear
whiptail --title "Installation Complete" --msgbox "
 █████╗ ██╗   ██╗████████╗ ██████╗  █████╗ ██████╗  ██████╗██╗  ██╗
██╔══██╗██║   ██║╚══██╔══╝██╔═══██╗██╔══██╗██╔══██╗██╔════╝██║  ██║
███████║██║   ██║   ██║   ██║   ██║███████║██████╔╝██║     ███████║
██╔══██║██║   ██║   ██║   ██║   ██║██╔══██║██╔══██╗██║     ██╔══██║
██║  ██║╚██████╔╝   ██║   ╚██████╔╝██║  ██║██║  ██║╚██████╗██║  ██║
╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝
Installation finished! Remove installation media and type 'reboot'. After rebooting, check /home/$usr/POSTINSTALL.txt for further instructions." 20 72
