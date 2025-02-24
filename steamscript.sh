#!/bin/bash
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

if ! whiptail --title "Get ProtonGE" --yesno "Download Proton GE? It is a better version of Proton that supports more games and I recommend it!" 20 30; then

prompt_input() {
    response=$(whiptail --title "$1" --inputbox "$2" 0 0 "$3" --ok-button "OK" --nocancel 3>&1 1>&2 2>&3)
    echo "$response"
}

sudo cp /etc/pacman.conf /etc/pacman.conf.bak
pconf="/etc/pacman.conf"
sudo sed -i '/#\[multilib\]/s/^#//' $pconf
sudo sed -i '/#Include = \/etc\/pacman.d\/mirrorlist/s/^#//' $pconf
sudo pacman -Sy
sudo pacman -S steam ttf-liberation xdg-desktop-portal

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
    flatpak install flathub net.davidotek.pupgui2
    if  whiptail --title "Run ProtonUp" --yesno --yes-button "Continue" --no-button "" "In this next menu, choose 'Add Version' > 'ProtonGE' > Newest version and make sure it is global." 20 30; then 
      flatpak run net.davidotek.pupgui2 &
    fi
  else
    yay -S protonup-qt
    if  whiptail --title "Run ProtonUp" --yesno --yes-button "Continue" --no-button "" "In this next menu, choose 'Add Version' > 'ProtonGE' > Newest version and make sure it is global." 20 30; then 
      protonup-qt & 
    fi
  fi
fi

if whiptail --title "Run Steam" --yesno --yes-button "Continue" --no-button "" "Sign in through Steam, click Steam > Settings > Compatibility > Choose ProtonGE if you installed it, otherwise choose the newst Proton" 20 30; then
  steam
else
  steam
fi

if  whiptail --title "Run Steam"  --yesno --no-button "" "Sign in through Steam, click Steam > Settings > Compatibility > Choose ProtonGE if you installed it, otherwise choose the newst Proton" 20 30; then 
  protonup-qt & 
fi


