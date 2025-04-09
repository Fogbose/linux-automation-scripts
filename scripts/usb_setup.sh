#!/usr/bin/env bash

###############################################################################
# Name        : usb_setup.sh
# Description : Prepares a 124GB USB key with 4 partitions:
#               - LIVE (FAT32, 16GB)
#               - DATA_PUBLIC (exFAT, 60GB)
#               - DATA_SECURE (LUKS + ext4, 30GB)
#               - BACKUPS_APPS (ext4, 18GB)
# Author      : Simon POLET
# Warning     :
#   - All data on the device will be deleted.
#   - This script requires sudo rights.
#   - Use only with removable devices (USB key).
#   - Do NOT run without validating the correct device (/dev/sdX).
# Logging     :
#   - All operations are logged in usb_setup.log (in the script folder).
###############################################################################

set -o pipefail

LOGFILE="./usb_setup.log"

# GLOBAL VARIABLES
USB_DEVICE=""
LUKS_NAME="secure_usb"
PART_LIVE=""
PART_PUBLIC=""
PART_SECURE=""
PART_BACKUPS=""
PASSPHRASE=""

# LOGGING
log() {
    local msg="$1"
    printf "[%s] %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$msg" | tee -a "$LOGFILE"
}

fail() {
    local msg="$1"
    printf "[ERROR] %s\n" "$msg" >&2
    printf "[%s] [ERROR] %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$msg" >> "$LOGFILE"
}

# CLEANUP ON SIGNAL
cleanup() {
    if sudo cryptsetup status "$LUKS_NAME" &>/dev/null; then
        sudo cryptsetup close "$LUKS_NAME"
        log "LUKS device $LUKS_NAME closed due to interrupt."
    fi
    fail "Script interrupted by signal."
    exit 1
}
trap cleanup INT TERM

# DEPENDENCY CHECK
check_dependencies() {
    local deps=(lsblk sudo parted mkfs.vfat mkfs.exfat mkfs.ext4 cryptsetup grep awk sed tee)

    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            fail "Missing command: $cmd"
            return 1
        fi
    done
}

# USER PROMPT FOR DEVICE
detect_usb_device() {
    log "Detecting USB devices..."
    if ! lsblk -o NAME,SIZE,TYPE,MODEL,TRAN | grep -Ei 'usb|removable' | tee -a "$LOGFILE"; then
        fail "No removable device detected."
        return 1
    fi

    printf "\nEnter the name of the USB device to be prepared (ex: sdx): "
    read -r user_input
    user_input=$(printf "%s" "$user_input" | tr -d -c 'a-z')

    if [[ ! "$user_input" =~ ^sd[a-z]$ ]]; then
        fail "Invalid device name."
        return 1
    fi

    USB_DEVICE="/dev/$user_input"

    if ! lsblk "$USB_DEVICE" &>/dev/null; then
        fail "Device not found: $USB_DEVICE"
        return 1
    fi
    
    lsblk "$USB_DEVICE"
    
    if lsof "$USB_DEVICE" &>/dev/null || mount | grep -q "$USB_DEVICE"; then
        fail "The $USB_DEVICE device is currently in use (mounted or open). Please unmount it before continuing."
        return 1
    fi

    printf "\n*** WARNING *** All data on %s will be DELETED. Continue? (Y/N): " "$USB_DEVICE"
    read -r confirm
    confirm=$(printf "%s" "$confirm" | tr '[:lower:]' '[:upper:]' | tr -d -c 'YN')

    if [[ "$confirm" != "Y" ]]; then
        fail "Operation cancelled by user."
        return 1
    fi

    return 0
}

# ASK LUKS PASSPHRASE
ask_luks_passphrase() {
    printf "Enter passphrase for secure LUKS partition: "
    read -rs pass1
    printf "\nConfirm passphrase: "
    read -rs pass2
    printf "\n"

    if [[ "$pass1" != "$pass2" ]] || [[ -z "$pass1" ]]; then
        fail "Passphrases do not match or are empty."
        return 1
    fi
    
    if [[ ${#pass1} -lt 8 || ! "$pass1" =~ [A-Z] || ! "$pass1" =~ [0-9] ]]; then
        fail "Passphrase must be at least 8 characters long and include both digits and uppercase letters."
        return 1
    fi

    PASSPHRASE="$pass1"
    unset pass1 pass2
}

# PARTITION CREATION
create_partitions() {
    log "Creating GPT partition table on $USB_DEVICE..."
    sudo parted -s "$USB_DEVICE" mklabel gpt || return 1

    log "Creating LIVE (16GB FAT32)"
    sudo parted -s "$USB_DEVICE" mkpart LIVE fat32 1MiB 16385MiB || return 1
    sudo parted -s "$USB_DEVICE" set 1 boot on

    log "Creating DATA_PUBLIC (60GB exFAT)"
    sudo parted -s "$USB_DEVICE" mkpart DATA_PUBLIC 16385MiB 77825MiB || return 1

    log "Creating DATA_SECURE (30GB LUKS)"
    sudo parted -s "$USB_DEVICE" mkpart DATA_SECURE ext4 77825MiB 108865MiB || return 1

    log "Creating BACKUPS_APPS (18GB ext4)"
    sudo parted -s "$USB_DEVICE" mkpart BACKUPS_APPS ext4 108865MiB 100% || return 1

    sudo partprobe "$USB_DEVICE"
    sleep 2

    PART_LIVE="${USB_DEVICE}1"
    PART_PUBLIC="${USB_DEVICE}2"
    PART_SECURE="${USB_DEVICE}3"
    PART_BACKUPS="${USB_DEVICE}4"
}

# FORMATTING FILESYSTEMS
format_partitions() {
    log "Formatting LIVE as FAT32"
    sudo mkfs.vfat -F32 -n "LIVE" "$PART_LIVE" || return 1

    log "Formatting DATA_PUBLIC as exFAT"
    sudo mkfs.exfat -n "DATA_PUBLIC" "$PART_PUBLIC" || return 1

    log "Configuring LUKS on DATA_SECURE"
    if ! echo -n "$PASSPHRASE" | sudo cryptsetup luksFormat "$PART_SECURE" --batch-mode --key-file=-; then
        fail "LUKS configuration failed."
        return 1
    fi

    log "Opening LUKS container"
    if ! echo -n "$PASSPHRASE" | sudo cryptsetup open "$PART_SECURE" "$LUKS_NAME" --key-file=-; then
        fail "Failed to open LUKS partition."
        return 1
    fi

    if [[ ! -b "/dev/mapper/$LUKS_NAME" ]]; then
        fail "LUKS mapping failed: /dev/mapper/$LUKS_NAME not found."
        return 1
    fi

    log "Formatting /dev/mapper/$LUKS_NAME as ext4"
    sudo mkfs.ext4 -L "DATA_SECURE" "/dev/mapper/$LUKS_NAME" || return 1
    
    sleep 2

    sudo cryptsetup close "$LUKS_NAME"
    log "LUKS container closed"

    log "Formatting BACKUPS_APPS as ext4"
    sudo mkfs.ext4 -L "BACKUPS_APPS" "$PART_BACKUPS" || return 1
}

# FINAL CHECKS
verify_setup() {
    log "Verifying partition layout on $USB_DEVICE"
    if ! lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$USB_DEVICE" | tee -a "$LOGFILE"; then
        fail "Verification failed."
        return 1
    fi
}

show_summary() {
    printf "\n\n=========== Summary ===========\n"
    lsblk -o NAME,SIZE,FSTYPE,LABEL "$USB_DEVICE"
    printf "\n\nPartitions created and formatted successfully.\n"
    printf "Live partition: 16GB FAT32\n"
    printf "Data partition: 60GB exFAT\n"
    printf "Secure partition: 30GB ext4 (LUKS encrypted)\n"
    printf "Backups partition: 18GB ext4\n"
}

# MAIN FUNCTION
main() {
    log "========== Starting USB key preparation =========="

    if ! check_dependencies; then
        fail "Missing dependencies. Aborting."
        return 1
    fi

    if ! detect_usb_device; then
        fail "Device detection failed."
        return 1
    fi

    if ! ask_luks_passphrase; then
        fail "LUKS passphrase setup failed."
        return 1
    fi

    if ! create_partitions; then
        fail "Partition creation failed."
        return 1
    fi

    if ! format_partitions; then
        fail "Partition formatting failed."
        return 1
    fi

    verify_setup
    
    show_summary

    log "========== USB key successfully prepared =========="
    return 0
}

main "$@"

