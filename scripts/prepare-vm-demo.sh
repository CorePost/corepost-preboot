#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/vm-env.sh"

ENV_FILE=""
CONFIG_FILE=""
USER_PASSWORD=""
UNLOCK_TOKEN=""
LUKS_SIZE_MB="256"
USB_SIZE_MB="32"

while [ $# -gt 0 ]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    --user-password)
      USER_PASSWORD="$2"
      shift 2
      ;;
    --unlock-token)
      UNLOCK_TOKEN="$2"
      shift 2
      ;;
    --luks-size-mb)
      LUKS_SIZE_MB="$2"
      shift 2
      ;;
    --usb-size-mb)
      USB_SIZE_MB="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$CONFIG_FILE" ] || [ -z "$USER_PASSWORD" ] || [ -z "$UNLOCK_TOKEN" ]; then
  echo "usage: $0 --config <path/to/corepost-preboot.conf> --user-password <password> --unlock-token <token> [--env-file path/to/runtime.env]" >&2
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "config not found: $CONFIG_FILE" >&2
  exit 1
fi

. "$CONFIG_FILE"

: "${COREPOST_LUKS_DEVICE:?missing COREPOST_LUKS_DEVICE}"
: "${COREPOST_LUKS_NAME:?missing COREPOST_LUKS_NAME}"
: "${COREPOST_UNLOCK_PROFILE:?missing COREPOST_UNLOCK_PROFILE}"
COREPOST_USB_KEY_PATH="${COREPOST_USB_KEY_PATH:-/dev/disk/by-label/COREPOST_USB}"

COMBINED_SECRET="${USER_PASSWORD}${UNLOCK_TOKEN}"

load_runtime_env "$ENV_FILE"
resolve_vm_env
build_vm_ssh
wait_for_vm

ssh "${SSH_OPTS[@]}" "$SSH_TARGET" sudo bash -s -- \
  "$COREPOST_LUKS_DEVICE" \
  "$COREPOST_LUKS_NAME" \
  "$COMBINED_SECRET" \
  "$COREPOST_UNLOCK_PROFILE" \
  "$COREPOST_USB_KEY_PATH" \
  "$LUKS_SIZE_MB" \
  "$USB_SIZE_MB" <<'EOF'
set -euo pipefail

luks_device="$1"
luks_name="$2"
combined_secret="$3"
unlock_profile="$4"
usb_key_path="$5"
luks_size_mb="$6"
usb_size_mb="$7"

state_dir="/var/lib/corepost-preboot"
luks_image="$state_dir/demo-luks.img"
usb_image="$state_dir/demo-usb.img"

mkdir -p "$state_dir" "$(dirname "$luks_device")" "$(dirname "$usb_key_path")"
modprobe loop >/dev/null 2>&1 || true

if cryptsetup status "$luks_name" >/dev/null 2>&1; then
  cryptsetup close "$luks_name"
fi

existing_luks_loop="$(readlink -f "$luks_device" 2>/dev/null || true)"
if [[ "$existing_luks_loop" == /dev/loop* ]]; then
  losetup -d "$existing_luks_loop" >/dev/null 2>&1 || true
fi

rm -f "$luks_device"
truncate -s "${luks_size_mb}M" "$luks_image"
luks_loop="$(losetup --find --show "$luks_image")"
printf '%s' "$combined_secret" | cryptsetup luksFormat "$luks_loop" --batch-mode --type luks2 --key-file=-
ln -s "$luks_loop" "$luks_device"

if [ "$unlock_profile" = "3fa" ]; then
  existing_usb_loop="$(readlink -f "$usb_key_path" 2>/dev/null || true)"
  if [[ "$existing_usb_loop" == /dev/loop* ]]; then
    losetup -d "$existing_usb_loop" >/dev/null 2>&1 || true
  fi
  rm -f "$usb_key_path"
  truncate -s "${usb_size_mb}M" "$usb_image"
  usb_loop="$(losetup --find --show "$usb_image")"
  mkfs.ext4 -F -L COREPOST_USB "$usb_loop" >/dev/null
  ln -s "$usb_loop" "$usb_key_path"
fi
EOF

echo "Prepared LUKS demo device $COREPOST_LUKS_DEVICE for $COREPOST_UNLOCK_PROFILE."
