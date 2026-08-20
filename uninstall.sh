#!/usr/bin/env bash
# =============================================================================
#  Digital Radio (DAB/FM) - uninstaller
#
#  Usage:
#      sudo ./uninstall.sh
#
#  Removes the radio service and the installed project. The config.txt
#  changes (SPI/I2S/overlay) are left in place (harmless) with a note.
# =============================================================================
set -euo pipefail

INSTALL_DIR="${1:-/opt/digital-radio}"
SERVICE="raspiaudio-radio.service"

say() { printf '\033[1;34m[uninstall]\033[0m %s\n' "$*"; }
ok()  { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root: sudo ./uninstall.sh"

if systemctl list-unit-files 2>/dev/null | grep -q "^${SERVICE}"; then
  say "Stopping and disabling $SERVICE ..."
  systemctl stop "$SERVICE" 2>/dev/null || true
  systemctl disable "$SERVICE" 2>/dev/null || true
  rm -f "/etc/systemd/system/$SERVICE"
  systemctl daemon-reload
  ok "Service removed"
fi

if [ -d "$INSTALL_DIR" ]; then
  say "Removing $INSTALL_DIR ..."
  rm -rf "$INSTALL_DIR"
  ok "Project removed"
fi

printf '\n\033[1;33mNote\033[0m: the lines added to config.txt by install.sh\n'
printf '(dtparam=spi=on, dtparam=i2s=on, dtparam=i2c_arm=on and the\n'
printf 'dtoverlay board line) were left in place - they are harmless and\n'
printf 'useful for other I2C/SPI boards. To remove them, edit the file\n'
printf 'manually. A backup of your original file (if one existed) is at\n'
printf '%s.install-backup\n' "$( [ -f /boot/firmware/config.txt ] && echo /boot/firmware/config.txt || echo /boot/config.txt )"
ok "Uninstall complete"
