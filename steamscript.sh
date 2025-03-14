#!/bin/bash
# autosteam (:
set -e

if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
  echo "Error: You don't have internet."
fi

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
    whiptail --title "autosteam" --msgbox "
 █████╗ ██╗   ██╗████████╗ ██████╗ ███████╗████████╗███████╗ █████╗ ███╗   ███╗
██╔══██╗██║   ██║╚══██╔══╝██╔═══██╗██╔════╝╚══██╔══╝██╔════╝██╔══██╗████╗ ████║
███████║██║   ██║   ██║   ██║   ██║███████╗   ██║   █████╗  ███████║██╔████╔██║
██╔══██║██║   ██║   ██║   ██║   ██║╚════██║   ██║   ██╔══╝  ██╔══██║██║╚██╔╝██║
██║  ██║╚██████╔╝   ██║   ╚██████╔╝███████║   ██║   ███████╗██║  ██║██║ ╚═╝ ██║
╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝ ╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝
            This will install steam, fonts and your graphics drivers, 
          enable the multilib repo, and optionally install compatibility
             tools. If you don't want this, CTRL-C now. Otherwise, 
                          Press Enter to continue. 
    " 20 83
}

banner

prompt_input() {
    response=$(whiptail --title "$1" --inputbox "$2" 0 0 "$3" --ok-button "OK" --nocancel 3>&1 1>&2 2>&3)
    echo "$response"
}

GPU_VENDOR=$(prompt_input "Graphics Card" "Enter your graphics card vendor in lowercase (intel, amd, nvidia):" "")

case "$GPU_VENDOR" in
    intel)
        sudo pacman -S --noconfirm xf86-video-intel mesa vulkan-intel
        ;;
    amd)
        sudo pacman -S --noconfirm xf86-video-amdgpu mesa vulkan-radeon
        ;;
    nvidia)
        sudo pacman -S --noconfirm nvidia nvidia-utils mesa vulkan-icd-loader
        ;;
    *)
        echo "Unknown vendor. Please install the driver manually."
        exit 1
        ;;
esac

sudo cp /etc/pacman.conf /etc/pacman.conf.bak
pconf="/etc/pacman.conf"
sudo sed -i '/#\[multilib\]/s/^#//' $pconf
sudo sed -i '/#Include = \/etc\/pacman.d\/mirrorlist/s/^#//' $pconf
sudo pacman -Sy
sudo pacman -S --noconfirm steam ttf-liberation xdg-desktop-portal

if whiptail --title "Get ProtonGE" --yesno "Download Proton GE? It is a better version of Proton that supports more games and I recommend it!" 20 30; then
  rm -rf /tmp/proton-ge-custom
  mkdir /tmp/proton-ge-custom
  cd /tmp/proton-ge-custom
  
  echo "Fetching tarball URL..."
  tarball_url=$(curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest | grep browser_download_url | cut -d\" -f4 | grep .tar.gz)
  tarball_name=$(basename $tarball_url)
  echo "Downloading tarball: $tarball_name..."
  curl -# -L $tarball_url -o $tarball_name --no-progress-meter
  
  echo "Fetching checksum URL..."
  checksum_url=$(curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest | grep browser_download_url | cut -d\" -f4 | grep .sha512sum)
  checksum_name=$(basename $checksum_url)
  echo "Downloading checksum: $checksum_name..."
  curl -# -L $checksum_url -o $checksum_name --no-progress-meter

  echo "Verifying tarball $tarball_name with checksum $checksum_name..."
  sha512sum -c $checksum_name
  
  echo "Creating Steam directory if it does not exist..."
  mkdir -p ~/.steam/root/compatibilitytools.d
  
  # extract proton tarball to steam directory
  echo "Extracting $tarball_name to Steam directory..."
  tar -xf $tarball_name -C ~/.steam/root/compatibilitytools.d/
  echo "All done :)"
  if  whiptail --title "Get ProtonUp" --yesno --yes-button "Flatpak" --no-button "Yay" "Download ProtonUp (needed for ProtonGE) through flatpak or through yay?" 20 30; then 
    if ! flatpak >/dev/null 2>&1; then
      sudo pacman -S flatpak
    fi
    flatpak install flathub net.davidotek.pupgui2
  else
    yay -S protonup-qt
  fi
fi

if whiptail --title "Run Steam" --yesno --yes-button "Continue" --no-button "" "Sign in through Steam, click Steam > Settings > Compatibility > Enable Steam Play, Restart. Choose the newest Proton, or if you downloaded Proton-GE, open ProtonUp-QT, choose 'Add Version' > 'ProtonGE' > Newest version, restart steam, and add Proton-GE. Your install is finished!" 20 30; then
  steam
else
  steam
fi
