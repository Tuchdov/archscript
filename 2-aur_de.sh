#!/usr/bin/env bash

echo -ne "
-------------------------------------------------------------------------
Installing AUR Software
-------------------------------------------------------------------------
"
source $HOME/ArchTitus/configs/setup.conf
    # change to home directory
    cd ~
    # make the directory .cache
    mkdir "/home/$USERNAME/.cache"
    # make the txt file zshhistory
    touch "/home/$USERNAME/.cache/zshhistory"
    git clone "https://github.com/ChrisTitusTech/zsh"
    # clones only the latest commit from the repo, mainly used for pulling automation scripts
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/powerlevel10k
    # ln command is used to create links to files or directories
    # it's used ln [options] file-name link-name
    # -s is for creating symbolic links, hard links share the inode number, sumbolic links do not
    ln -s "~/zsh/.zshrc" ~/.zshrc

    # read the install type the user has chosen
sed -n '/'$INSTALL_TYPE'/q;p' ~/ArchTitus/pkg-files/${DESKTOP_ENV}.txt | while read line
do
    if [[ ${line} == '--END OF MINIMAL INSTALL--' ]]
    then 
        # If selected installation type is FULL, skip the --END OF THE MINIMAL INSTALLATION-- line
        continue
    fi
    echo "INSTALLING: ${line}"
    sudo pacman -S --noconfirm --needed ${line}
done

echo -ne "
-------------------------------------------------------------------------
Installing AUR Helper
-------------------------------------------------------------------------
"

# check if user wanten an aur helper
## double negetive? maybe hust do != ?
if [[ ! $AUR_HELPER == none]]; then
    cd ~
    git clone "https://aur.archlinux.org/$AUR_HELPER.git"
    cd ~/$AUR_HELPER
    makepkg -si --noconfirm
    # sed $INSTALL_TYPE is using install type to check for MINIMAL installation, if it's true, stop
    # stop the script and move on, not installing any more packages below that line
    sed -n '/'$INSTALL_TYPE'/q;p' ~/ArchTitus/pkg-files/aur-pkgs.txt | while read line
    do
        if [[ ${line} == '--END OF MINIMAL INSTALL--' ]]; then
      # If selected installation type is FULL, skip the --END OF THE MINIMAL INSTALLATION-- line
         continue
        fi
    echo "INSTALLING: ${line}"
    # install the foreign packages with the aur helper
    $AUR_HELPER -S --noconfirm --needed ${line}
    done
fi

export PATH=$PATH:~/.local/bin
# Theming DE if user chose FULL installation
if [[ $INSTALL_TYPE == "FULL"]]; then
    if [[ $DESKTOP_ENV == kde]]; then
        cp -r ~/ArchTitus/configs/.config/* ~/.config/
        pip install konsave # makes tranfering kde customiztions easily
        konsave -i ~/ArchTitus/configs/kde.knsv
        # wait one second 
        sleep 1
        konsave -a kde
    elif [[ ~/ArchTitus/configs/kde.knsv ]]; then
    cd ~
    git clone https://github.com/stojshic/dotfiles-openbox
    ./dotfiles-openbox/install-titus.sh
    fi
fi

echo -ne "
-------------------------------------------------------------------------
                    SYSTEM READY FOR 3-post-setup.sh
-------------------------------------------------------------------------
"
exit