#!/usr/bin/env bash
# Mount persistent data EBS volume at /data
# Handles both new volumes (format) and existing volumes (mount only)
set -e

DEVICE="/dev/xvdf"
NVME_DEVICE="/dev/nvme1n1"
MOUNT_POINT="/data"
MAX_WAIT=60
LOG_TAG="mount-data-volume"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$LOG_TAG] $1"
    logger -t "$LOG_TAG" "$1"
}

get_device() {
    # EC2 Nitro instances use NVMe, others use xvd
    if [[ -b "$NVME_DEVICE" ]]; then
        echo "$NVME_DEVICE"
    elif [[ -b "$DEVICE" ]]; then
        echo "$DEVICE"
    else
        echo ""
    fi
}

wait_for_device() {
    log "Waiting for EBS volume device..."
    local waited=0
    local dev=""

    while [[ $waited -lt $MAX_WAIT ]]; do
        dev=$(get_device)
        if [[ -n "$dev" ]]; then
            log "Device found: $dev"
            echo "$dev"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done

    log "ERROR: Device not found after ${MAX_WAIT}s"
    return 1
}

format_if_new() {
    local dev="$1"

    # Check if device has a filesystem
    if blkid "$dev" &>/dev/null; then
        log "Existing filesystem detected on $dev"
        return 0
    fi

    log "No filesystem found, formatting $dev as ext4..."
    mkfs.ext4 -L data "$dev"
    log "Format complete"
}

mount_volume() {
    local dev="$1"

    # Create mount point if needed
    if [[ ! -d "$MOUNT_POINT" ]]; then
        mkdir -p "$MOUNT_POINT"
        log "Created mount point: $MOUNT_POINT"
    fi

    # Check if already mounted
    if mountpoint -q "$MOUNT_POINT"; then
        log "$MOUNT_POINT already mounted"
        return 0
    fi

    # Mount the device
    mount "$dev" "$MOUNT_POINT"
    log "Mounted $dev at $MOUNT_POINT"

    # Add to fstab if not present
    if ! grep -q "$MOUNT_POINT" /etc/fstab; then
        local uuid
        uuid=$(blkid -s UUID -o value "$dev")
        echo "UUID=$uuid $MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab
        log "Added $MOUNT_POINT to fstab"
    fi
}

create_directories() {
    local dirs=("consul" "vault" "nomad")

    for dir in "${dirs[@]}"; do
        local path="$MOUNT_POINT/$dir"
        if [[ ! -d "$path" ]]; then
            mkdir -p "$path"
            log "Created directory: $path"
        fi
    done

    # Set ownership for Consul, Vault, and Nomad
    chown -R consul:consul "$MOUNT_POINT/consul" 2>/dev/null || true
    chown -R vault:vault "$MOUNT_POINT/vault" 2>/dev/null || true
    chown -R nomad:nomad "$MOUNT_POINT/nomad" 2>/dev/null || true
    chmod 750 "$MOUNT_POINT/consul" "$MOUNT_POINT/vault" "$MOUNT_POINT/nomad"

    log "Directory permissions set"
}

main() {
    log "=== Starting data volume mount ==="

    local dev
    dev=$(wait_for_device) || exit 1

    format_if_new "$dev"
    mount_volume "$dev"
    create_directories

    log "=== Data volume mount complete ==="
    log "Mount status: $(df -h $MOUNT_POINT | tail -1)"
}

main "$@"
