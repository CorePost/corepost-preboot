#!/bin/bash

load_runtime_env() {
  local env_file="${1:-${COREPOST_ENV_FILE:-}}"

  if [ -z "$env_file" ]; then
    return 0
  fi

  if [ ! -f "$env_file" ]; then
    echo "runtime env file not found: $env_file" >&2
    return 1
  fi

  set -a
  . "$env_file"
  set +a
}

resolve_vm_env() {
  COREPOST_VM_ROOT="${COREPOST_VM_ROOT:-}"
  COREPOST_VM_HOST="${COREPOST_VM_HOST:-}"
  COREPOST_VM_PORT="${COREPOST_VM_PORT:-}"
  COREPOST_VM_USER="${COREPOST_VM_USER:-}"

  if [ -n "$COREPOST_VM_ROOT" ]; then
    COREPOST_VM_KEY_PATH="${COREPOST_VM_KEY_PATH:-$COREPOST_VM_ROOT/id_ed25519}"
    COREPOST_VM_KNOWN_HOSTS_PATH="${COREPOST_VM_KNOWN_HOSTS_PATH:-$COREPOST_VM_ROOT/logs/known_hosts}"
    COREPOST_VM_WAIT_FOR_SSH="${COREPOST_VM_WAIT_FOR_SSH:-$COREPOST_VM_ROOT/wait-for-ssh.sh}"
  else
    COREPOST_VM_KEY_PATH="${COREPOST_VM_KEY_PATH:-}"
    COREPOST_VM_KNOWN_HOSTS_PATH="${COREPOST_VM_KNOWN_HOSTS_PATH:-}"
    COREPOST_VM_WAIT_FOR_SSH="${COREPOST_VM_WAIT_FOR_SSH:-}"
  fi

  : "${COREPOST_VM_HOST:?missing COREPOST_VM_HOST}"
  : "${COREPOST_VM_PORT:?missing COREPOST_VM_PORT}"
  : "${COREPOST_VM_USER:?missing COREPOST_VM_USER}"
  : "${COREPOST_VM_KEY_PATH:?missing COREPOST_VM_KEY_PATH}"
  : "${COREPOST_VM_KNOWN_HOSTS_PATH:?missing COREPOST_VM_KNOWN_HOSTS_PATH}"
}

build_vm_ssh() {
  SSH_OPTS=(
    -i "$COREPOST_VM_KEY_PATH"
    -o BatchMode=yes
    -o StrictHostKeyChecking=accept-new
    -o UserKnownHostsFile="$COREPOST_VM_KNOWN_HOSTS_PATH"
    -o Port="$COREPOST_VM_PORT"
  )
  SCP_OPTS=(
    -i "$COREPOST_VM_KEY_PATH"
    -o BatchMode=yes
    -o StrictHostKeyChecking=accept-new
    -o UserKnownHostsFile="$COREPOST_VM_KNOWN_HOSTS_PATH"
    -P "$COREPOST_VM_PORT"
  )
  SSH_TARGET="$COREPOST_VM_USER@$COREPOST_VM_HOST"
}

wait_for_vm() {
  if [ -n "${COREPOST_VM_WAIT_FOR_SSH:-}" ]; then
    "$COREPOST_VM_WAIT_FOR_SSH" >/dev/null
  fi
}
