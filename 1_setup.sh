#!/usr/bin/env bash

# read and execute the content of the file
source $HOME/archscript/configs/setup.conf

echo -ne "
-------------------------------------------------------------------------
                    Network Setup 
-------------------------------------------------------------------------
"
pacman -S --noconfirm --needed networkmanager dhclient
systemctl enable --now NetworkManager
# usually poeple do two commands, systemctl start and systemctl enable 
# using --now makes both of those actions

echo -ne "
-------------------------------------------------------------------------
                    Setting up mirrors for optimal download 
-------------------------------------------------------------------------
"
pacman -S --noconfirm --needed pacman-contrib curl
pacman -S --noconfirm --needed reflector rsync grub arch-install-scripts git
# make a backup of original mirror list
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak

# number of cores in cpu
nc=$(grep -c ^processor /proc/cpuinfo)

echo -ne "
-------------------------------------------------------------------------
                    You have " $nc" cores. And
			changing the makeflags for "$nc" cores. Aswell as
				changing the compression settings.
-------------------------------------------------------------------------
"
# get total ram mamory
TOTAL_MEM=$(cat /proc/meminfo | grep -i 'memtotal' | grep -o '[[:digit:]]*')
# In bash -gt inside the if statement means greater then
if [[  $TOTAL_MEM -gt 8000000 ]]; then
# tell the system that we have nc number of cores
sed -i "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j$nc\"/g" /etc/makepkg.conf
# to utilize multiple cores on compression with xz
sed -i "s/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -c -T $nc -z -)/g" /etc/makepkg.conf
fi

# Note: by using sed (stream editor) we can edit files without opening them
# to substitute we do 's/sub_this/to_that/'' file_to_work_with.bar

echo -ne "
-------------------------------------------------------------------------
                    Setup Language to US and set locale  
-------------------------------------------------------------------------
"

sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
timedatectl --no-ask-password set-timezone ${TIMEZONE}
timedatectl --no-ask-password set-ntp 1
localectl --no-ask-password set-locale LANG="en_US.UTF-8" LC_TIME="en_US.UTF-8"
ln -s /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
# Set keymaps
localectl --no-ask-password set-keymap ${KEYMAP}


# Add sudo no password rights
# note: manually it's recommended to use visudo to change /etc/sudoers
# NOPASSWD will not require to use a passwd for sudo command for the users in this category
sed -i 's/^# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers
sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers

#Add parallel downloading
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf

#Enable multilib (used to install 32-bit packeges and also steam)
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
pacman -Sy --noconfirm --needed


echo -ne "
-------------------------------------------------------------------------
                    Installing Base System  
-------------------------------------------------------------------------
"

# sed $INSTALL_TYPE is using install type to check for MINIMAL installation, if it's true, stop
# stop the script and move on, not installing any more packages below that line.
if [[ ! $DESKTOP_ENV == server ]]; then # If the environment is not the server envorinment
  sed -n '/'$INSTALL_TYPE'/q;p' $HOME/archscript/pkg-files/pacman-pkgs.txt | while read line
  do
    if [[ ${line} == '--END OF MINIMAL INSTALL--' ]]; then
      # If selected installation type is FULL, skip the --END OF THE MINIMAL INSTALLATION-- line
      continue
    fi
    # Full installation
    echo "INSTALLING: ${line}" 
    sudo pacman -S --noconfirm --needed ${line}
  done
fi

echo -ne "
-------------------------------------------------------------------------
                    Installing Microcode
-------------------------------------------------------------------------
"
# microcode are  basic instructions for the cpu
# These instructions add a layer of complexity to improve the performance of basic operations and security.
# for further reading check this link https://history-computer.com/microcode/

# determine processor type and install microcode
proc_type=$(lscpu)# here we use $(command) to store var
if grep -E "GenuineIntel" <<< ${proc_type}; then
    echo "Installing Intel microcode"
    pacman -S --noconfirm --needed intel-ucode
    proc_ucode=intel-ucode.img
elif grep -E "AuthenticAMD" <<< ${proc_type}; then
    echo "Installing AMD microcode"
    pacman -S --noconfirm --needed amd-ucode
    proc_ucode=amd-ucode.img
fi

echo -ne "
-------------------------------------------------------------------------
                    Installing Graphics Drivers
-------------------------------------------------------------------------
"
# find all gpus and install graphic drivers
gpu_type=$(lspci)
if grep -E "NVIDIA|GeForce" <<< ${gpu_type}; then # if nvidia gpu exists
    pacman -S --noconfirm --needed nvidia
	nvidia-xconfig
elif lspci | grep 'VGA' | grep -E "Radeon|AMD"; then # if amd gpu exists
    pacman -S --noconfirm --needed xf86-video-amdgpu
elif grep -E "Integrated Graphics Controller" <<< ${gpu_type}; then
    pacman -S --noconfirm --needed libva-intel-driver libvdpau-va-gl lib32-vulkan-intel vulkan-intel libva-intel-driver libva-utils lib32-mesa
elif grep -E "Intel Corporation UHD" <<< ${gpu_type}; then
    pacman -S --needed --noconfirm libva-intel-driver libvdpau-va-gl lib32-vulkan-intel vulkan-intel libva-intel-driver libva-utils lib32-mesa
fi

# IF SETUP IS WRONG RUN THIS
# note: this is a long if statement
if ! source $HOME/archscript/configs/setup.conf; then
  # loop through user input until the user gives a valid username
  while true
  do
    read -p "Please enter username:" username
    # username regex per response here https://unix.stackexchange.com/questions/157426/what-is-the-regex-to-validate-linux-users
		# lowercase the username to test regex
    if [[ "${username,,}" =~ ^[a-z_]([a-z0-9_-]{0,31}|[a-z0-9_-]{0,30}\$)$ ]]
    then
      break
    fi
    echo "Incorrect username."
  done

# convert name to lowercase before saving to setup.conf
echo "username=${username,,}" >> ${HOME}/archscript/configs/setup.conf

# set password
  read -p "Please enter password:" password
echo "password=${password,,}" >> ${HOME}/archscript/configs/setup.conf
  # Loop through user input until the user gives a valid hostname, but allow the user to force save 
  while true
  do 
    read -p "Please name your machine:" name_of_machine
		# hostname regex (!!couldn't find spec for computer name!!)
    if [[  "${name_of_machine,,}" =~ ^[a-z][a-z0-9_.-]{0,62}[a-z0-9]$ ]]
    then 
      break
    fi
  	# if validation fails allow the user to force saving of the hostname
    read -p "Hostname doesn't seem correct. Do you still want to save it? (y/n)" force
    if [[ "${force,,}" = "y"  ]]
    then
      break
    fi
  done
echo "NAME_OF_MACHINE=${name_of_machine,,}" >> ${HOME}/archscript/configs/setup.conf
fi

echo -ne "
-------------------------------------------------------------------------
                    Adding User
-------------------------------------------------------------------------
"

# if this is the root user make a home directory and allow using sudo and virtualization
if [ $(whoami) = root]; then
  groupadd libvirt
  useradd -m -G wheel,libvirt -s /bin/bash $USERNAME
  echo "$USERNAME created, home directory created, added to wheel and libvirt group, default shell set to /bin/bash"

# use chpasswd to enter $USERNAME:$password
# Reads a file of login name and password pairs, and updates the passwords.
# chpasswd is used for systems with many users (and probably for this script to be more convenient)
# for only one user just use passwd
  echo "$USERNAME:$PASSWORD" | chpasswd
  echo "$USERNAME password set"

  # copy all files from archscript to the new username
  cp -R $HOME/archscript /home/$USERNAME
  # change the owner of all the files to te new username
  chown -R $USERNAME: /home/$USERNAME/archscript
  echo "archscript copied to home directory"

# write $NAME_OF_MACHINE to /etc/hostname
  echo $NAME_OF_MACHINE > /etc/hostname
else
  echo "You are already a user proceed with aur installs"
fi

# if the user decided to encrypt his system with luks
if [[ ${FS} =='luks']]; then
# Making sure to edit mkinitcpio conf if luks is selected
# add encrypt in mkinitcpio.conf before filesystems in hooks
# note: in sed the suffix /g is a command to gloabally replace e.g replacce all the occurences of the string in the line
  sed -i 's/filesystems/encrypt filesystems/g' /etc/mkinitcpio.conf
   # making mkinitcpio with linux kernel
  mkinitcpio -p linux
fi 
echo -ne "
-------------------------------------------------------------------------
                    SYSTEM READY FOR 2-user.sh
-------------------------------------------------------------------------
"