#!/usr/bin/env bash

# read and execute the content of the file
source $HOME/ArchTitus/configs/setup.conf

echo -ne "
-------------------------------------------------------------------------
                    Network Setup 
-------------------------------------------------------------------------
"
pacman -S --noconfirm --needed networkmanager dhclient
systemctl enable --now NetworkManager
