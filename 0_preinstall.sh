#!/usr/bin/bash

# generete file to 
# github-action genshdoc

# source command is used to read and execute the content of the file
source $configs_dir/setup.conf

# get the country iso from the ip the user
iso = curl( -4 ifconfig.co/country-iso)

# enable setting time and date from online sources
timedatectl set-ntp true 

# update keyrings to latest to prevent packages failing to install
pacman -S --noconfirm archlinux-keyring 
# install usefull scripts for pacman and font that will be used as default system font
pacman -S --noconfirm --needed pacman-contrib terminus-font

# set the new font as default 
setfont ter-v22b

# modify the config file with the sed express text editor. i flag is for insert
# probably make parallel downloads possible

sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf

# install reflector to get latest mirrors, rsync to synchoronize files and grub for boot load
pacman -S --noconfirm --needed reflector rsync grub
# make a backup of initial mirrors
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup

# setting up the country mirrors and saving them in the mirror list
reflector -a 48 -c $iso -f 5 -l 20 --sort rate --save /etc/pacman.d/mirrorlist
mkdir /mnt &>/dev/null # Because it's a script wi will hide error messages if any

# Installing the perequisites
# install gptfdisk as partitioning tool btrfs fylesystem menegement tool and core GNU system libraries
pacman -S --noconfirm --needed gptfdisk btrfs-progs glibc


# formatting the disk
umount -A --recursive /mnt # unmounting all devices
# preperring the disk
sgdisk -Z ${DISK} # DESTROY the GPT and MBR data structures, use it if you want to repartition a disk afterwards
sgdisk -a 2048 -o ${DISK} # new gpt disk 2048 alignment

# Side note: mbr is a method of partitioning disks, this methed limits the possible size of the disk to 2tb and hence is very rare
# GPT is more modern and much more capable but every GPT has one MBR partition. if a disk boots with UEFI it probably uses GPT.

# create partitions
# new partition,  partition number:starting sector:ending sector K = lb, M= mb, G = Gb
# typecode is the id of partitiontype, for example 0x83 is the code used for the ext2 filesystem

sgdisk -n 1::+1M --typecode=1:ef02 --change-name:'BIOSBOOT' ${DISK} # partition 1 (BIOS Boot Partition)
sgdisk -n 2::+300M --typecode=2:ef00 --change-name=2:'EFIBOOT' ${DISK} # partition 2 (UEFI Boot Partition)
sgdisk -n 3::-0 --typecode=3:8300 --change-name=3:'ROOT' ${DISK} # partition 3 (Root), default start,use all remaining data

###
if [[ ! -d "/sys/firmware/efi" ]]; then # Checking for bios system
    sgdisk -A 1:set:2 ${DISK}
fi

# use partprobe command to let the system know of the partition table changes we made
partprobe ${DISK} # reread partition table to ensure it is correct

# Creating the chosen filesystems

# We will define a function. In BASH to define a function we write.
# function_name () {
    # commands
# }

# @description Creates the btrfs subvolumes. 
createsubvolumes () {
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@var
    btrfs subvolume create /mnt/@tmp
    btrfs subvolume create /mnt/@.snapshots
}

# @description Mount all btrfs subvolumes after root (that's in partition) has been mounted.
mountallsubvol () {
    mount -o ${MOUNT_OPTIONS},subvol=@home ${partition3} /mnt/home
    mount -o ${MOUNT_OPTIONS},subvol=@tmp ${partition3} /mnt/tmp
    mount -o ${MOUNT_OPTIONS},subvol=@var ${partition3} /mnt/var
    mount -o ${MOUNT_OPTIONS},subvol=@.snapshots ${partition3} /mnt/.snapshots
}

# @description BTRFS subvolulme creation and mounting.
subvolumesetup () {
# create non root subvolumes 
    createsubvolumes
# unmount root to remount with subvolume 
    umount mnt/
# mount @ subvolume
    mount -o ${MOUNT_OPTIONS},subvol=@ ${partition3} /mnt
# make directories home, .snapshots, var, tmp
    mkdir -p /mnt/{home, var, tmp, .snapshots}
# mount subvolumes
    mountallsubvol
}