#!/usr/bin/env bash
# =============================================================================
#  Digital Radio (DAB/FM) - Raspberry Pi + Si4689 (uGreen) - installer
#
#  Installs the radio web service, its system configuration and the systemd
#  autostart unit on a fresh Raspberry Pi OS (bookworm+) image.
#
#  Usage:
#      sudo ./install.sh
#
#  After the install completes, REBOOT the Raspberry Pi: the config.txt
#  changes (SPI/I2S + board overlay) are applied at boot, then the radio
#  service starts automatically and the web UI is served on port 8686.
# =============================================================================
set -euo pipefail

# ----------------------------------------------------------------------------
#  Configuration (edit if your hardware differs)
# ----------------------------------------------------------------------------
INSTALL_DIR="/opt/digital-radio"          # where the project gets installed
PORT="8686"                               # web UI port
RST_PIN="23"                              # Si4689 reset GPIO
                                         #   uGreen board      -> 23
                                         #   raspiaudio shield -> 25
OVERLAY="ugreen-dabboard,card-name=si4689_i2s"
                                         # board I2S overlay:
                                         #   uGreen board      -> ugreen-dabboard,card-name=si4689_i2s
                                         #   raspiaudio shield -> adau7002-simple,card-name=si4689_i2s
RECORD_DEVICE="dabdsnoop"                # ALSA dsnoop device (from /etc/asound.conf)
RECORD_FORMAT="mp3"                      # wav or mp3

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_SRC="$SCRIPT_DIR/project"

# ----------------------------------------------------------------------------
#  Helpers
# ----------------------------------------------------------------------------
say()  { printf '\033[1;34m[install]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

require_root() {
  [ "$(id -u)" -eq 0 ] || die "Run as root: sudo ./install.sh"
}

require_source() {
  [ -d "$PROJECT_SRC" ] || die "Project sources not found at $PROJECT_SRC (is the package intact?)"
  [ -f "$PROJECT_SRC/radio.py" ] || die "radio.py missing in $PROJECT_SRC"
}

detect_config_file() {
  if [ -f /boot/firmware/config.txt ]; then
    CONFIG_FILE="/boot/firmware/config.txt"        # Raspberry Pi OS bookworm+
  elif [ -f /boot/config.txt ]; then
    CONFIG_FILE="/boot/config.txt"                 # older images
  else
    die "Cannot find config.txt"
  fi
}

# ----------------------------------------------------------------------------
#  1. System packages
# ----------------------------------------------------------------------------
install_packages() {
  say "Installing system packages (python3, spidev, RPi.GPIO, alsa-utils, ffmpeg)..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y python3 python3-spidev python3-rpi.gpio alsa-utils ffmpeg
  ok "Packages installed"
}

# ----------------------------------------------------------------------------
#  2. config.txt: SPI, I2S, I2C and the board overlay
# ----------------------------------------------------------------------------
patch_config_txt() {
  detect_config_file
  say "Patching $CONFIG_FILE (SPI / I2S / board overlay)..."
  cp -a "$CONFIG_FILE" "$CONFIG_FILE.install-backup"

  local changed=0
  for line in "dtparam=spi=on" "dtparam=i2s=on" "dtparam=i2c_arm=on"; do
    if ! grep -q "^${line}\b" "$CONFIG_FILE"; then
      printf '\n%s\n' "$line" >> "$CONFIG_FILE"
      changed=1
    fi
  done
  if ! grep -q "^dtoverlay=${OVERLAY}\b" "$CONFIG_FILE"; then
    {
      printf '\n[all]\n'
      printf '# Digital Radio board overlay (added by install.sh)\n'
      printf 'dtoverlay=%s\n' "$OVERLAY"
    } >> "$CONFIG_FILE"
    changed=1
  fi

  if [ "$changed" -eq 1 ]; then
    ok "config.txt patched (a reboot is required to apply it)"
  else
    ok "config.txt already configured"
  fi
}

# ----------------------------------------------------------------------------
#  3. /etc/asound.conf - shared dsnoop capture (live stream + recording)
# ----------------------------------------------------------------------------
install_asound_conf() {
  local conf="/etc/asound.conf"
  local marker="Digital Radio dsnoop"

  if [ -f "$conf" ] && grep -q "$marker" "$conf"; then
    ok "/etc/asound.conf already configured"
    return
  fi
  if [ -f "$conf" ]; then
    cp -a "$conf" "$conf.install-backup"
    say "Existing /etc/asound.conf backed up to $conf.install-backup"
  fi
  cat > "$conf" <<EOF
# $marker (installed by install.sh)
# Shared capture device: lets the live stream and the recorder
# open the I2S capture at the same time.
pcm.dabdsnoop {
    type dsnoop
    ipc_key 8192
    ipc_key_add_uid yes
    slave {
        pcm "hw:1,0"
        format S16_LE
        rate 48000
        channels 2
    }
}
EOF
  ok "/etc/asound.conf written (pcm.dabdsnoop)"
}

# ----------------------------------------------------------------------------
#  4. Project files
# ----------------------------------------------------------------------------
install_project() {
  say "Copying project to $INSTALL_DIR ..."
  mkdir -p "$INSTALL_DIR"
  cp -a "$PROJECT_SRC/." "$INSTALL_DIR/"
  chown -R root:root "$INSTALL_DIR"
  find "$INSTALL_DIR" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
  ok "Project installed at $INSTALL_DIR"
}

# ----------------------------------------------------------------------------
#  5. systemd autostart service
# ----------------------------------------------------------------------------
install_service() {
  local unit="/etc/systemd/system/raspiaudio-radio.service"
  say "Installing systemd service $unit ..."
  if [ -f "$unit" ]; then
    cp -a "$unit" "$unit.install-backup"
  fi
  sed -e "s|__INSTALL_DIR__|$INSTALL_DIR|g" \
      -e "s|__RST_PIN__|$RST_PIN|g" \
      -e "s|__PORT__|$PORT|g" \
      -e "s|__RECORD_DEVICE__|$RECORD_DEVICE|g" \
      -e "s|__RECORD_FORMAT__|$RECORD_FORMAT|g" \
      "$SCRIPT_DIR/config/raspiaudio-radio.service" > "$unit"
  systemctl daemon-reload
  systemctl enable raspiaudio-radio.service
  ok "Service installed and enabled (starts at boot)"
}

# ----------------------------------------------------------------------------
#  main
# ----------------------------------------------------------------------------
main() {
  require_root
  require_source
  install_packages
  patch_config_txt
  install_asound_conf
  install_project
  install_service

  printf '\n\033[1;32m=============================================\033[0m\n'
  printf '\033[1;32m  INSTALLATION COMPLETE\033[0m\n'
  printf '\033[1;32m=============================================\033[0m\n'
  printf '  The Raspberry Pi needs a REBOOT to apply the\n'
  printf '  SPI/I2S configuration. After reboot the radio\n'
  printf '  service starts automatically.\n\n'
  printf '  Next steps:\n'
  printf '    1. sudo reboot\n'
  printf '    2. open  http://<ip-of-the-pi>:%s\n' "$PORT"
  printf '    3. press "DAB" or "FM", then "Scan stations"\n\n'
  printf '  Uninstall:  sudo %s/uninstall.sh\n' "$SCRIPT_DIR"
}

main "$@"
