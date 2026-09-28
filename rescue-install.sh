#!/bin/bash
# Run as root inside rescue, while the system disk is not mounted.
# The script does not reboot the machine: afterwards disable rescue in the provider panel and boot from the disk.
set -euo pipefail

IMAGE_URL="https://github.com/siderolabs/talos/releases/download/v1.14.1/metal-amd64.raw.zst"
IMAGE_SHA256="71e05502114b77f8a91081be6d30dc1b9ffe18601d828cc92031b31240e77875"
VERSION="v1.14.1"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Root is required." >&2
  exit 1
fi

if ! command -v zstd >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y zstd
  else
    echo "zstd is missing in rescue. Install the zstd package and run the script again." >&2
    exit 1
  fi
fi

echo "Disks:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS,MODEL
echo
echo "Disk expected by Ansible: /dev/vda"
echo "Image: ${VERSION}  ${IMAGE_URL}"
echo

DISK="${1:-}"
if [[ -z "${DISK}" ]]; then
  read -r -p "Whole disk path, for example /dev/vda or /dev/nvme0n1: " DISK
fi

if [[ ! -b "${DISK}" ]]; then
  echo "No block device ${DISK}" >&2
  exit 1
fi

disk_type="$(lsblk -dno TYPE "${DISK}" 2>/dev/null || true)"
if [[ "${disk_type}" != "disk" ]]; then
  echo "${DISK} has type '${disk_type:-unknown}'. A whole disk is required, not a partition." >&2
  exit 1
fi

mounts="$(lsblk -no MOUNTPOINTS "${DISK}" | tr -d '[:space:]')"
if [[ -n "${mounts}" ]]; then
  echo "${DISK} or its partitions are mounted. Unmount them and run the script again." >&2
  lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS "${DISK}" >&2
  exit 1
fi

echo "Writing will erase everything on ${DISK}."
read -r -p "Type the disk path again to continue: " confirm
if [[ "${confirm}" != "${DISK}" ]]; then
  echo "Path did not match, write cancelled." >&2
  exit 1
fi

tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT

curl -fL --retry 5 --retry-delay 2 -o "${tmp}" "${IMAGE_URL}"
echo "${IMAGE_SHA256}  ${tmp}" | sha256sum -c -

zstd -d -c "${tmp}" | dd of="${DISK}" bs=4M conv=fsync status=progress
sync

echo
echo "Talos image ${VERSION} written to ${DISK}."
echo "Next, manually: disable rescue in the provider panel and reboot the server from the disk."
echo "Do not reboot while the panel keeps the server in rescue: it will boot rescue again, not Talos."
