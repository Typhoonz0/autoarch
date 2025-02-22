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
# User inputs
usr="user"
echo "Your username?" && prompt && read usr
usr=${usr:-"user"}
echo "Your computer's hostname?" && prompt && read hostnm
hostnm=${hostnm:-"autoarch"}
echo "Your user's password (sudo)?" && prompt && read userps
userps=${userps:-"root"}
echo "Your root password (su)?" && prompt && read rootps
rootps=${rootps:-"root"}
echo "Your locale (Press ENTER for: en_US.UTF-8 UTF-8)?" && prompt && read locale
locale=${locale:-"en_US.UTF-8 UTF-8"}
echo "Your timezone (e.g., UTC, Australia/Sydney)?" && prompt && read timezone
timezone=${timezone:-"Australia/Tasmania"}
echo "Swapfile (in GB)?" && prompt && read swapfilesize
swapfilesize=${swapfilesize:-"0"}

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
echo "Are you going to (a) use only Arch Linux (auto partition) or (b) dual-boot (manual partition)?" && prompt && read autopartconfirm

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

get_partition_suffix() {
    if [[ "$DISK" =~ ^nvme || "$DISK" =~ ^mmcblk ]]; then
        echo "p"
    else
        echo ""
    fi
}

SUFFIX=$(get_partition_suffix)
#!/bin/bash

# Function to display a warning message using whiptail and get confirmation
confirm_action() {
    whiptail --title "Warning" --yesno "This will erase all data on /dev/$DISK. Are you sure you want to continue?" 20 60
    return $?  # Return the exit status of whiptail
}

# Check if autopartconfirm is set to "a"
if [[ "$autopartconfirm" == "a" ]]; then
    # Call the confirmation function
    if confirm_action; then
        # If confirmed, proceed with partitioning
        parted /dev/$DISK --script mklabel gpt
        parted /dev/$DISK --script mkpart ESP fat32 1MiB 257MiB
        parted /dev/$DISK --script set 1 boot on
        parted /dev/$DISK --script mkpart primary ext4 257MiB 100%
        
        # Define partition variables
        EFI_PART="/dev/${DISK}${SUFFIX}1"
        ROOT_PART="/dev/${DISK}${SUFFIX}2"
        
        # Format the EFI partition
        mkfs.fat -F 32 "$EFI_PART"
    else
        # If canceled, call manual_part function
        manual_part
    fi
else 
    # If autopartconfirm is not "a", call manual_part function
    manual_part
fi


# Format and mount partitions
mkfs.ext4 "$ROOT_PART"
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot/efi

echo "Would you like to format your EFI partition at $EFI_PART? This is only needed if you do NOT have any other bootloaders installed. (y/n)"
prompt && read confirmformat
if [[ "$confirmformat" == "y" || "$confirmformat" == "Y" ]]; then 
 mkfs.fat -F 32 "$EFI_PART"
 mount "$EFI_PART" /mnt/boot/efi
else
 mount "$EFI_PART" /mnt/boot/efi
fi

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
echo "(e.g. firefox vim gnome fastfetch):" && prompt && read additional
echo "Sit back and relax (:"
#!/bin/bash

# Function to display a message box with the installation status
show_installing() {
    while true; do
        # Display an "Installing" message
        whiptail --title "Installing" --msgbox "Installing... Please wait." 8 45
        # Check if the installation process is still running
        if ! pgrep -x "pacstrap" > /dev/null; then
            break  # Exit loop if pacstrap is no longer running
        fi
    done
}

# Function to play Tetris while waiting for installation
play_tetris() {
    # Run Tetris in the background
    autoload -Uz tetriscurses
    tetris &
    TETRIS_PID=$!  # Store the PID of the Tetris process
}

# Function to show dialog asking if the user wants to see the command in progress
show_command_progress() {
    if whiptail --title "Command Progress" --yesno "Do you want to see the command in progress?" 20 60; then
        # User wants to see the command output
        pacstrap -K /mnt base grub efibootmgr linux linux-firmware sudo nano networkmanager $additional
    else
        # User does not want to see the output
        # Redirect output to /dev/null unless there is an error
        {
            pacstrap -K /mnt base grub efibootmgr linux linux-firmware sudo nano networkmanager $additional
        } > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            # If there was an error, notify the user
            whiptail --title "Error" --msgbox "An error occurred during installation." 8 45
        fi

        # Ask if they want to play Tetris
        if whiptail --title "Tetris" --yesno "Do you want to play Tetris while you wait?" 20 60; then
            play_tetris  # Start Tetris in the background
            show_installing  # Show the installing message in a loop
            kill "$TETRIS_PID"  # Kill the Tetris game after installation
            whiptail --title "Done" --msgbox "Installation completed!" 8 45
        else
            # Show the installing message
            show_installing
            whiptail --title "Done" --msgbox "Installation completed!" 8 45
        fi
    fi
}

# Call the function to show the command progress
show_command_progress


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
banner
echo "Installation complete! Remove installation media and type 'reboot'."
echo "After rebooting, check /home/$usr/POSTINSTALL.txt for further instructions."
