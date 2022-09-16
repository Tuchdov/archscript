#!/usr/bin/bash

# generete file to 


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
# install gptfdisk as partitioning tool btrfs fylesystem manegament tool and core GNU system libraries
pacman -S --noconfirm --needed gptfdisk btrfs-progs glibc


# formatting the disk
umount -A --recursive /mnt # unmounting all devices
# preperring the disk
sgdisk -Z ${DISK} # DESTROY the GPT and MBR data structures, use it if you want to repartition a disk afterwards
sgdisk -a 2048 -o ${DISK} # new gpt disk 2048 alignment

# Side note: mbr is a method of partitioning disks, this methed limits the possible size of the disk to 2tb and hence is very rare
# GPT is more modern and much more capable but every GPT has one MBR partition. if a disk boots with UEFI it probably uses GPT.

# create partitions
# new partition,  partition number:starting sector:ending sector K = kb, M = mb, G = Gb
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

# given the partition theyre variables
# =~ is an operator that matches the string to it's right
if [[  "${DISK}" =~ "nvme"  ]]; then
    partition2 = ${DISK}p2 
    partition3 = ${DISK}p3
else
    partition2 = ${DISK}p2 
    partition3 = ${DISK}p3
fi

## format according to the file system the user has chosen

# BTRFS setup
if [[ "${FS} == 'btrfs" ]]; then
    # in order for the system to boot we need to set an efi partition
    # format to FAT32 file system and label it
    mkfs.vfat -F32 -n "EFIBOOT" ${partition2}
    # format btrfs partition, name it root
    mkfs.btrfs -L ROOT ${partition3} -f
    # mount the btrfs root partition
    mount -t btrfs ${partition3} /mnt
    # use the helper functions we created before to mount the subvolumes
    subvolumesetup

# EXT4 setup
elif [[ "${FS}" == "ext4" ]]; then
    mkfs.vfat -F32 -n "EFIBOOT" ${partition2}
    mkfs.ext4 -L ROOT ${partition3}
    mount -t ext4 ${partition3} /mnt
    
# Disk encryption for the btrfs filesystem
elif [[ "${FS}" == "luks" ]]; then
    mkfs.vfat -F32 -n "EFIBOOT" ${partition2}
# enter luks password to cryptsetup and format root partition
    echo -n "${LUKS_PASSWORD}" | cryptsetup -y -v luksFormat ${partition3} -
# open luks container and ROOT will be place holder 
    echo -n "${LUKS_PASSWORD}" | cryptsetup open ${partition3} ROOT -
# now format that container
    mkfs.btrfs -L ROOT ${partition3}
# create subvolumes for btrfs
    mount -t btrfs ${partition3} /mnt
    subvolumesetup
# store uuid (a unique id) of encrypted partition for grub and save it to the config file
    echo ENCRYPTED_PARTITION_UUID=$(blkid -s UUID -o value ${partition3}) >> $CONFIGS_DIR/setup.conf
fi

# mount target
mkdir -p /mnt/boot/efi # p flag is used to create directories with perents
mount -t vfat -L EFIBOOT /mnt/boot/ # mount the partition you need for booting

# In case the drive is not mounted send error massages and reboot

if ! grep -qs '/mnt' /proc/mounts; then # the qs flags in grep are used to quiet and to surprees error massages if the file does not exist
    echo "Drive is not mounted can not continue"
    echo "Rebooting in 3 Seconds ..." && sleep 1
    echo "Rebooting in 2 Seconds ..." && sleep 1
    echo "Rebooting in 1 Second ..." && sleep 1
    reboot now
fi

echo -ne "
-------------------------------------------------------------------------
                    Arch Install on Main Drive
-------------------------------------------------------------------------
"

# pacstrap is the basic command to install the basic thins we need for arch
pacstrap /mnt base base-devel linux linux-firmware vim nano sudo archlinux-keyring wget libnewt --noconfirm --needed
# write the server we used to get the keys for program integrity to this location
echo "keyserver hkp://keyserver.ubuntu.com" >> /mnt/etc/pacman.d/gnupg/gpg.conf
# copy recursively the script directory and the mirror list
cp -R ${SCRIPT_DIR} /mnt/root/ArchTitus
cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlis

# genarate file system table aka fstab 
# fstab are used to contain the info of which filesystems the system can mount, to prevent repeating this manually everytime
genfstab -L /mnt >> /mnt/etc/fstab
echo " 
  Generated /etc/fstab:
"
cat /mnt/etc/fstab
echo -ne "
-------------------------------------------------------------------------
                    GRUB BIOS Bootloader Install & Check
-------------------------------------------------------------------------
"
if [[ ! -d "/sys/firmware/efi" ]]; then
    grub-install --boot-directory=/mnt/boot ${DISK}
else
    pacstrap /mnt efibootmgr --noconfirm --needed
fi
echo -ne "
-------------------------------------------------------------------------
                    Checking for low memory systems <8G
-------------------------------------------------------------------------
"
TOTAL_MEM=$(cat /proc/meminfo | grep -i 'memtotal' | grep -o '[[:digit:]]*')
if [[  $TOTAL_MEM -lt 8000000 ]]; then
    # Put swap into the actual system, not into RAM disk, otherwise there is no point in it, it'll cache RAM into RAM. So, /mnt/ everything.
    mkdir -p /mnt/opt/swap # make a dir that we can apply NOCOW to to make it btrfs-friendly.
    chattr +C /mnt/opt/swap # apply NOCOW, btrfs needs that.
    dd if=/dev/zero of=/mnt/opt/swap/swapfile bs=1M count=2048 status=progress
    chmod 600 /mnt/opt/swap/swapfile # set permissions.
    chown root /mnt/opt/swap/swapfile
    mkswap /mnt/opt/swap/swapfile
    swapon /mnt/opt/swap/swapfile
    # The line below is written to /mnt/ but doesn't contain /mnt/, since it's just / for the system itself.
    echo "/opt/swap/swapfile	none	swap	sw	0	0" >> /mnt/etc/fstab # Add swap to fstab, so it KEEPS working after installation.
fi
echo -ne "
-------------------------------------------------------------------------
                    SYSTEM READY FOR 1-setup.sh
---------------