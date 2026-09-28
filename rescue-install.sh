#!/bin/bash
# Запускать от root внутри rescue, когда системный диск не смонтирован.
# Скрипт не перезагружает машину: после него выключите rescue в панели провайдера и загрузитесь с диска.
set -euo pipefail

IMAGE_URL="https://github.com/siderolabs/talos/releases/download/v1.14.1/metal-amd64.raw.zst"
IMAGE_SHA256="71e05502114b77f8a91081be6d30dc1b9ffe18601d828cc92031b31240e77875"
VERSION="v1.14.1"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Нужен root." >&2
  exit 1
fi

if ! command -v zstd >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y zstd
  else
    echo "В rescue нет zstd. Поставьте пакет zstd и запустите скрипт снова." >&2
    exit 1
  fi
fi

echo "Диски:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS,MODEL
echo
echo "Ожидаемый диск из Ansible: /dev/vda"
echo "Образ: ${VERSION}  ${IMAGE_URL}"
echo

DISK="${1:-}"
if [[ -z "${DISK}" ]]; then
  read -r -p "Путь к целому диску, например /dev/vda или /dev/nvme0n1: " DISK
fi

if [[ ! -b "${DISK}" ]]; then
  echo "Нет блочного устройства ${DISK}" >&2
  exit 1
fi

disk_type="$(lsblk -dno TYPE "${DISK}" 2>/dev/null || true)"
if [[ "${disk_type}" != "disk" ]]; then
  echo "${DISK} имеет тип '${disk_type:-unknown}'. Нужен целый диск, не раздел." >&2
  exit 1
fi

mounts="$(lsblk -no MOUNTPOINTS "${DISK}" | tr -d '[:space:]')"
if [[ -n "${mounts}" ]]; then
  echo "${DISK} или его разделы смонтированы. Размонтируйте их и запустите скрипт снова." >&2
  lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS "${DISK}" >&2
  exit 1
fi

echo "Запись сотрёт всё на ${DISK}."
read -r -p "Введите путь диска ещё раз, чтобы продолжить: " confirm
if [[ "${confirm}" != "${DISK}" ]]; then
  echo "Путь не совпал, запись отменена." >&2
  exit 1
fi

tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT

curl -fL --retry 5 --retry-delay 2 -o "${tmp}" "${IMAGE_URL}"
echo "${IMAGE_SHA256}  ${tmp}" | sha256sum -c -

zstd -d -c "${tmp}" | dd of="${DISK}" bs=4M conv=fsync status=progress
sync

echo
echo "Образ Talos ${VERSION} записан на ${DISK}."
echo "Дальше вручную: выключите rescue в панели провайдера и перезагрузите сервер с диска."
echo "Не делайте reboot, пока панель держит сервер в rescue: он снова поднимется в rescue, а не в Talos."
