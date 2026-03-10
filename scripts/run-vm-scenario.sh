#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/lib/vm-env.sh"

ENV_FILE=""
CONFIG_FILE=""
USER_PASSWORD=""
UNLOCK_TOKEN=""
SCENARIO=""
DEVICE_ID=""
ADMIN_TOKEN=""
ADMIN_URL=""
NETWORK_DENY_SERVER_URL=""
REPORT_FILE=""
REMOTE_CONFIG_PATH="/etc/corepost-preboot.conf"

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
    --scenario)
      SCENARIO="$2"
      shift 2
      ;;
    --device-id)
      DEVICE_ID="$2"
      shift 2
      ;;
    --admin-token)
      ADMIN_TOKEN="$2"
      shift 2
      ;;
    --admin-url)
      ADMIN_URL="$2"
      shift 2
      ;;
    --network-deny-server-url)
      NETWORK_DENY_SERVER_URL="$2"
      shift 2
      ;;
    --report-file)
      REPORT_FILE="$2"
      shift 2
      ;;
    --remote-config-path)
      REMOTE_CONFIG_PATH="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$CONFIG_FILE" ] || [ -z "$USER_PASSWORD" ] || [ -z "$UNLOCK_TOKEN" ] || [ -z "$SCENARIO" ]; then
  echo "usage: $0 --config <path/to/corepost-preboot.conf> --user-password <password> --unlock-token <token> --scenario allow|deny|network-deny [--env-file path/to/runtime.env]" >&2
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

ADMIN_URL="${ADMIN_URL:-${COREPOST_SERVER_BASE_URL:-}}"
ADMIN_TOKEN="${ADMIN_TOKEN:-${COREPOST_ADMIN_TOKEN:-}}"
NETWORK_DENY_SERVER_URL="${NETWORK_DENY_SERVER_URL:-${COREPOST_NETWORK_DENY_SERVER_URL:-}}"

. "$CONFIG_FILE"
: "${COREPOST_LUKS_NAME:?missing COREPOST_LUKS_NAME}"

run_remote_preboot() {
  local config_path="$1"
  printf '%s\n' "$USER_PASSWORD" | ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
    "sudo env COREPOST_PREBOOT_CONFIG_FILE='$config_path' /etc/initramfs-tools/scripts/local-top/corepost-preboot"
}

close_mapping() {
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
    "sudo cryptsetup close '$COREPOST_LUKS_NAME' >/dev/null 2>&1 || true"
}

mapping_is_open() {
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
    "sudo cryptsetup status '$COREPOST_LUKS_NAME' >/dev/null 2>&1"
}

set_device_state() {
  local target_state="$1"
  python3 - <<PY
import json
import urllib.request

payload = json.dumps({"deviceId": "$DEVICE_ID"}).encode()
req = urllib.request.Request(
    "$ADMIN_URL/admin/$target_state",
    data=payload,
    headers={"Content-Type": "application/json", "X-Admin-Token": "$ADMIN_TOKEN"},
    method="POST",
)
with urllib.request.urlopen(req) as response:
    print(response.status)
    print(response.read().decode())
PY
}

capture() {
  if [ -n "$REPORT_FILE" ]; then
    tee -a "$REPORT_FILE"
  else
    cat
  fi
}

if [ -n "$REPORT_FILE" ]; then
  : >"$REPORT_FILE"
fi

"$ROOT_DIR/scripts/install-into-vm.sh" --env-file "$ENV_FILE" --config "$CONFIG_FILE" | capture
"$ROOT_DIR/scripts/prepare-vm-demo.sh" --env-file "$ENV_FILE" --config "$CONFIG_FILE" --user-password "$USER_PASSWORD" --unlock-token "$UNLOCK_TOKEN" | capture
close_mapping

case "$SCENARIO" in
  allow)
    if [ -n "$DEVICE_ID" ] && [ -n "$ADMIN_TOKEN" ] && [ -n "$ADMIN_URL" ]; then
      set_device_state "recover" | capture
    fi
    if run_remote_preboot "$REMOTE_CONFIG_PATH" 2>&1 | capture; then
      if mapping_is_open; then
        echo "Scenario allow: PASS" | capture
      else
        echo "Scenario allow: FAIL (mapping is closed)" | capture
        exit 1
      fi
    else
      echo "Scenario allow: FAIL (preboot command returned non-zero)" | capture
      exit 1
    fi
    ;;
  deny)
    [ -n "$DEVICE_ID" ] || { echo "--device-id is required for deny" >&2; exit 1; }
    [ -n "$ADMIN_TOKEN" ] || { echo "--admin-token is required for deny" >&2; exit 1; }
    [ -n "$ADMIN_URL" ] || { echo "--admin-url or COREPOST_SERVER_BASE_URL is required for deny" >&2; exit 1; }
    set_device_state "lock" | capture
    if run_remote_preboot "$REMOTE_CONFIG_PATH" 2>&1 | capture; then
      echo "Scenario deny: FAIL (preboot unexpectedly succeeded)" | capture
      exit 1
    fi
    if mapping_is_open; then
      echo "Scenario deny: FAIL (mapping is open)" | capture
      exit 1
    fi
    set_device_state "recover" | capture
    echo "Scenario deny: PASS" | capture
    ;;
  network-deny)
    [ -n "$NETWORK_DENY_SERVER_URL" ] || { echo "--network-deny-server-url or COREPOST_NETWORK_DENY_SERVER_URL is required for network-deny" >&2; exit 1; }
    bad_config_host="$(mktemp)"
    bad_config_guest="/tmp/corepost-preboot-network-deny.conf"
    python3 - <<PY
from pathlib import Path

src = Path("$CONFIG_FILE").read_text().splitlines()
out = []
replaced = False
for line in src:
    if line.startswith("COREPOST_SERVER_URL="):
        out.append('COREPOST_SERVER_URL="$NETWORK_DENY_SERVER_URL"')
        replaced = True
    else:
        out.append(line)
if not replaced:
    out.append('COREPOST_SERVER_URL="$NETWORK_DENY_SERVER_URL"')
Path("$bad_config_host").write_text("\\n".join(out) + "\\n")
PY
    scp "${SCP_OPTS[@]}" "$bad_config_host" "$SSH_TARGET:$bad_config_guest"
    rm -f "$bad_config_host"
    if run_remote_preboot "$bad_config_guest" 2>&1 | capture; then
      echo "Scenario network-deny: FAIL (preboot unexpectedly succeeded)" | capture
      exit 1
    fi
    if mapping_is_open; then
      echo "Scenario network-deny: FAIL (mapping is open)" | capture
      exit 1
    fi
    echo "Scenario network-deny: PASS" | capture
    ;;
  *)
    echo "unsupported scenario: $SCENARIO" >&2
    exit 1
    ;;
esac
