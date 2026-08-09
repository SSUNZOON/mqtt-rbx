#!/usr/bin/env bash
# mqtt-rbx skill - talk to your own local MQTT broker from the shell.
#
# Unlike mqtt-classroom, this broker requires a username/password (no
# anonymous access) and defaults to *your* machine, not a shared one.
#
# Requires the mosquitto clients (mosquitto_pub / mosquitto_sub):
#   Windows  installer from https://mosquitto.org/download/ (adds them to
#            C:\Program Files\mosquitto - add that folder to PATH)
#   macOS    brew install mosquitto
#   Linux    sudo apt install mosquitto-clients
#
# Override the broker without editing this file:
#   export MQTT_HOST=192.168.0.32
#   export MQTT_PORT=1883
#   export MQTT_USER=RBX_esp01
#   export MQTT_PASS=...

set -euo pipefail

MQTT_HOST="${MQTT_HOST:-127.0.0.1}"
MQTT_PORT="${MQTT_PORT:-1883}"
BASE="RBX"

# Your own board's name + credentials, so you don't retype them on every
# command. Saved by `./skill.sh name <id>` / `./skill.sh login <id> <pass>`;
# MQTT_DEVICE / MQTT_USER / MQTT_PASS in the environment win over the file.
CONFIG_FILE="${HOME}/.mqtt-rbx"

die() { echo "error: $*" >&2; exit 1; }

config_get() {
  [ -f "$CONFIG_FILE" ] || return 0
  sed -n "s/^$1=//p" "$CONFIG_FILE" | head -1
}

load_device() {
  if [ -n "${MQTT_DEVICE:-}" ]; then
    echo "$MQTT_DEVICE"
  else
    config_get device
  fi
}

load_user() {
  if [ -n "${MQTT_USER:-}" ]; then
    echo "$MQTT_USER"
  else
    config_get user
  fi
}

load_pass() {
  if [ -n "${MQTT_PASS:-}" ]; then
    echo "$MQTT_PASS"
  else
    config_get pass
  fi
}

# Commands take an explicit id, or fall back to the saved one.
resolve_device() {
  local id="${1:-}"
  [ -n "$id" ] || id="$(load_device)"
  [ -n "$id" ] || die "no device id. Pass one, or save yours: ./skill.sh name RBX_esp01"
  echo "$id"
}

# Auth args for mosquitto_pub/sub. Empty (anonymous) is allowed so `check`
# can still tell you the broker is up even before you've logged in.
auth_args() {
  local u p; u="$(load_user)"; p="$(load_pass)"
  if [ -n "$u" ]; then
    printf -- '-u\n%s\n' "$u"
    [ -n "$p" ] && printf -- '-P\n%s\n' "$p"
  fi
}

# The Windows installer does not put mosquitto on PATH, and Git Bash inherits
# that, so look in the usual install locations before giving up.
need_clients() {
  if command -v mosquitto_sub >/dev/null 2>&1 && command -v mosquitto_pub >/dev/null 2>&1; then
    return 0
  fi

  local dir
  for dir in \
    "/c/Program Files/mosquitto" \
    "/c/Program Files (x86)/mosquitto" \
    "$HOME/scoop/apps/mosquitto/current" \
    "/opt/homebrew/bin" \
    "/usr/local/bin"
  do
    if [ -x "$dir/mosquitto_sub" ] || [ -x "$dir/mosquitto_sub.exe" ]; then
      PATH="$PATH:$dir"
      export PATH
      return 0
    fi
  done

  die "mosquitto_sub / mosquitto_pub not found.
  Windows  install from https://mosquitto.org/download/ (default location is detected automatically)
  macOS    brew install mosquitto
  Linux    sudo apt install mosquitto-clients"
}

usage() {
  local saved_id saved_user
  saved_id="$(load_device)"; saved_user="$(load_user)"
  cat <<EOF
mqtt-rbx - broker ${MQTT_HOST}:${MQTT_PORT}
your device: ${saved_id:-<not set - run: ./skill.sh name RBX_espNN>}
your login:  ${saved_user:-<not set - run: ./skill.sh login RBX_espNN PASSWORD>}

  ./skill.sh name [ID]          save your board's name (no arg = show current)
  ./skill.sh login ID PASSWORD  save broker credentials
  ./skill.sh check              test that the broker is reachable
  ./skill.sh devices            list boards that are online right now
  ./skill.sh watch [ID]         stream every message (or just one board's)
  ./skill.sh led [ID] on|off|toggle
  ./skill.sh sensor [ID]        stream that board's A0 readings
  ./skill.sh pub TOPIC PAYLOAD  publish anything (escape hatch)

ID defaults to your saved name, so once you run \`./skill.sh name RBX_esp01\`
you can just type \`./skill.sh led on\`. It must match DEVICE_NAME in the
board's arduino_secrets.h, and login must match an account the broker's
password file actually has (created by setup/install-broker.ps1).

Topics
  ${BASE}/<id>/led/set      on | off | toggle      (you publish)
  ${BASE}/<id>/led/state    on | off               (retained)
  ${BASE}/<id>/sensor/a0    {"raw":2048,"mv":1650}
  ${BASE}/<id>/status       online | offline       (retained)
EOF
}

cmd_check() {
  need_clients
  local topic="${BASE}/_check/$$"
  echo "publishing to ${MQTT_HOST}:${MQTT_PORT} ..."
  if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" $(auth_args) -t "$topic" -m "hello" 2>/dev/null; then
    echo "OK - broker reachable"
  else
    echo "FAILED - broker not reachable at ${MQTT_HOST}:${MQTT_PORT}" >&2
    echo "  - is the mosquitto service running on that machine?" >&2
    echo "  - right MQTT_HOST (broker PC's LAN IP, not this PC's if remote)?" >&2
    echo "  - if allow_anonymous is off, did you run './skill.sh login ID PASSWORD'?" >&2
    exit 1
  fi
}

cmd_devices() {
  need_clients
  echo "boards reporting in (2s, Ctrl-C to stop early):"
  # Retained status messages arrive immediately on subscribe.
  mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" $(auth_args) -t "${BASE}/+/status" -v -W 2 2>/dev/null |
    while read -r topic payload; do
      id="${topic#${BASE}/}"; id="${id%/status}"
      printf '  %-12s %s\n' "$id" "$payload"
    done || true
}

cmd_name() {
  local id="${1:-}"
  if [ -z "$id" ]; then
    local saved; saved="$(load_device)"
    if [ -n "$saved" ]; then
      echo "your device: ${saved}"
      [ -n "${MQTT_DEVICE:-}" ] && echo "(from MQTT_DEVICE in the environment)"
    else
      echo "no device saved yet - run: ./skill.sh name RBX_espNN"
    fi
    return
  fi

  # Topic level, so keep it free of MQTT wildcards and separators.
  case "$id" in
    */*|*'#'*|*'+'*|*' '*) die "device name must not contain / # + or spaces" ;;
  esac

  local user pass
  user="$(config_get user)"; pass="$(config_get pass)"
  {
    printf 'device=%s\n' "$id"
    [ -n "$user" ] && printf 'user=%s\n' "$user"
    [ -n "$pass" ] && printf 'pass=%s\n' "$pass"
  } > "$CONFIG_FILE"
  echo "saved: ${id}  (${CONFIG_FILE})"
  echo "this must match DEVICE_NAME in your board's arduino_secrets.h"
}

cmd_login() {
  local id="${1:-}" pass="${2:-}"
  [ -n "$id" ] && [ -n "$pass" ] || die "usage: ./skill.sh login ID PASSWORD"

  local dev; dev="$(config_get device)"
  {
    [ -n "$dev" ] && printf 'device=%s\n' "$dev"
    printf 'user=%s\n' "$id"
    printf 'pass=%s\n' "$pass"
  } > "$CONFIG_FILE"
  echo "saved login: ${id}  (${CONFIG_FILE})"
}

cmd_watch() {
  need_clients
  local id="${1:-}"
  [ -n "$id" ] || id="$(load_device)"
  [ -n "$id" ] || id="+"          # nothing saved: watch every board
  echo "watching ${BASE}/${id}/# (Ctrl-C to stop)"
  mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" $(auth_args) -t "${BASE}/${id}/#" -v
}

cmd_led() {
  need_clients
  local id state
  # Accept both `led on` (saved device) and `led RBX_esp02 on`.
  case "${1:-}" in
    on|off|toggle) id="$(resolve_device)"; state="$1" ;;
    *)             id="$(resolve_device "${1:-}")"; state="${2:-}" ;;
  esac
  [ -n "$state" ] || die "usage: ./skill.sh led [ID] on|off|toggle"
  case "$state" in
    on|off|toggle) ;;
    *) die "state must be on, off or toggle" ;;
  esac
  mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" $(auth_args) -t "${BASE}/${id}/led/set" -m "$state"
  echo "sent '${state}' to ${id}"
}

cmd_sensor() {
  need_clients
  local id; id="$(resolve_device "${1:-}")"
  echo "streaming ${BASE}/${id}/sensor/a0 (Ctrl-C to stop)"
  mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" $(auth_args) -t "${BASE}/${id}/sensor/a0"
}

cmd_pub() {
  need_clients
  local topic="${1:-}" payload="${2:-}"
  [ -n "$topic" ] || die "usage: ./skill.sh pub TOPIC PAYLOAD"
  mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" $(auth_args) -t "$topic" -m "$payload"
  echo "published to ${topic}"
}

case "${1:-help}" in
  name)    shift; cmd_name "$@" ;;
  login)   shift; cmd_login "$@" ;;
  check)   shift; cmd_check "$@" ;;
  devices) shift; cmd_devices "$@" ;;
  watch)   shift; cmd_watch "$@" ;;
  led)     shift; cmd_led "$@" ;;
  sensor)  shift; cmd_sensor "$@" ;;
  pub)     shift; cmd_pub "$@" ;;
  help|-h|--help) usage ;;
  *) usage; exit 1 ;;
esac
