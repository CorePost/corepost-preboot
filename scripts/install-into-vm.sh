#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/vm-env.sh
. "$SCRIPT_DIR/lib/vm-env.sh"

ENV_FILE=""
CONFIG_FILE=""
HOOK_DEST="/etc/initramfs-tools/hooks/corepost-preboot"
SCRIPT_DEST="/etc/initramfs-tools/scripts/local-top/corepost-preboot"
CONFIG_DEST="/etc/corepost-preboot.conf"

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
    --hook-dest)
      HOOK_DEST="$2"
      shift 2
      ;;
    --script-dest)
      SCRIPT_DEST="$2"
      shift 2
      ;;
    --config-dest)
      CONFIG_DEST="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$CONFIG_FILE" ]; then
  echo "usage: $0 --config <path/to/corepost-preboot.conf> [--env-file path/to/runtime.env]" >&2
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "config not found: $CONFIG_FILE" >&2
  exit 1
fi

load_runtime_env "$ENV_FILE"
resolve_vm_env
build_vm_ssh
wait_for_vm

scp "${SCP_OPTS[@]}" \
  "$ROOT_DIR/initramfs-tools/hooks/corepost-preboot" \
  "$SSH_TARGET:/tmp/corepost-preboot-hook"

scp "${SCP_OPTS[@]}" \
  "$ROOT_DIR/initramfs-tools/scripts/local-top/corepost-preboot" \
  "$SSH_TARGET:/tmp/corepost-preboot-script"

scp "${SCP_OPTS[@]}" \
  "$CONFIG_FILE" \
  "$SSH_TARGET:/tmp/corepost-preboot.conf"

ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
  sudo bash -s -- "$HOOK_DEST" "$SCRIPT_DEST" "$CONFIG_DEST" <<'EOF'
set -euo pipefail

hook_dest="$1"
script_dest="$2"
config_dest="$3"

install -D -m 0755 /tmp/corepost-preboot-hook "$hook_dest"
install -D -m 0755 /tmp/corepost-preboot-script "$script_dest"
install -D -m 0600 /tmp/corepost-preboot.conf "$config_dest"
update-initramfs -u
current_initrd="/boot/initrd.img-$(uname -r)"
lsinitramfs "$current_initrd" | grep -E 'corepost-preboot|corepost-preboot.conf' >/dev/null
EOF

echo "Installed preboot hook and config into VM."
