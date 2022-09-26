#!/bin/bash
# Entrance script, it launches the other scripts for each phase of the installation.

# Find the name of the folder the scripts are in
set -a # sets and then exports the created/modified varibles and/or functions to export
MAIN_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
SCRIPTS_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"/scripts
CONFIGS_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"/configs
set +a

echo -ne "
-------------------------------------------------------------------------
                    Automated Arch Linux Installer
-------------------------------------------------------------------------
                Scripts are in directory named archscript
"
    ( bash $MAIN_DIR/scripts/startup.sh )|& tee startup.login
    source $CONFIGS_DIR/setup.conf
    ( bash $SCRIPT_DIR/scripts/0-preinstall.sh)|& tee 0-preinstall.log
    (arch-chroot /mnt $HOME/archscript/scripts/1-setup.sh )|& tee 1-setup.log
    if [[ ! $DESKTOP_ENV == server ]]; then
      ( arch-chroot /mnt /usr/bin/runuser -u $USERNAME -- /home/$USERNAME/archscript/scripts/2-aur_de.sh )|& tee 2-aur.log
    fi
    ( arch-chroot /mnt $HOME/archscript/scripts/3-post-setup.sh )|& tee 3-post-setup.log
    cp -v *.log /mnt/home/$USERNAME    


echo -ne "

-------------------------------------------------------------------------
                    Automated Arch Linux Installer
-------------------------------------------------------------------------
                Done - Please Eject Install Media and Reboot
"