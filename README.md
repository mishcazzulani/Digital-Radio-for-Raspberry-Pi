# Digital Radio for Raspberry Pi (DAB+ / FM + RDS)

**DAB+ and FM receiver** for the Raspberry Pi with the **uGreen (Si4689)** board:
full web UI, **correctly decoded RDS**, MP3/WAV recording, FM scan with real station
names, manual FM tuning and automatic start at boot.

An improved fork of [RASPIAUDIOadmin/Digital-Radio-for-Raspberry-Pi](https://github.com/RASPIAUDIOadmin/Digital-Radio-for-Raspberry-Pi),
adapted and fixed for the uGreen DAB/FM board.

---

## Features

- **DAB+**: scan, 150+ stations, labels decoded in **EBU Latin** (correct names:
  "Radio Libertà", "#RTL102.5 napulè"...), live **DLS** artist/title, firmware **6.0.9** tested
- **FM**: scan with the **real RDS station names**, full **RadioText**, **PI**, **PTY**
- **RDS decoded at the root** (no heuristics): PS segment = block B bits 1-0,
  RT segment = block B low nibble, **BLER** filtering of corrupted blocks
- **Manual FM tuning**: type a frequency (87.5–108 MHz) right from the web UI
- **MP3 or WAV recording** named `YYYYMMDD-HHMMSS_<mode>_<station>.mp3`
  with **delete** from the web UI
- **Simultaneous listening + recording** thanks to the shared ALSA device (`dabdsnoop`)
- Web UI: **DAB and FM only** (no HD/AM), per-mode metadata panel
  (DAB → artist/title/live text; FM → RT/PI/PTY), 4-column station layout
- **One-command installation** (`install.sh`) on a fresh Raspberry Pi OS
- **Autostart at boot** (systemd service)

## Hardware requirements

- Raspberry Pi 3/4/5 with Raspberry Pi OS (bookworm or newer)
- **uGreen DAB/FM board** (Si4689), RST on GPIO 23
  *(original raspiaudio shield: RST on GPIO 25 and overlay `adau7002-simple`)*
- FM/DAB antenna connected

## Quick install

```bash
unzip digital-radio-pkg.zip
cd digital-radio-pkg
sudo ./install.sh
sudo reboot
```

After the reboot open `http://<ip-of-the-pi>:8686`, pick **DAB** or **FM** and press
**Scan stations**.

The package also ships `uninstall.sh` and a full `README.md` with the configuration
options (`RST_PIN`, `OVERLAY`, `PORT`, `RECORD_FORMAT`).

---

## What we changed

Every change was developed and **verified empirically on the real hardware**
(uGreen board + Raspberry Pi).

### RDS decoding (the main work)

| Before | After |
|---|---|
| Rotated/garbled PS ("LOMBD.", "RTL1 .5") | **Correct, stable PS**: "RADIO 24", "RTL102.5", "LOMBARD.", "\*Radio2" |
| Mixed-up RT ("(2009) \*ORRESANGICeluono") | **Clean RT**: "GIGI D'ALESSIO - MEZZE VERITA'", "PAOLA & CHIARA - FESTA TOTALE" |
| — | **PI** and **PTY** (with type name) shown in the UI |

How: the Si4689 chip already reports RDS characters as plain ASCII bytes in the
blocks (no 6-bit table needed). The segment field was in the wrong place:

1. **PS segment = block B bits 1-0** (verified on 120 samples: the "RT"/"L1"/"02"/".5"
   pairs are placed by `B & 0x3` → "RTL102.5")
2. **RT segment = block B low nibble** (`B & 0xF`; the initial block-C hypothesis
   was a coincidence on a single station)
3. **BLER filter** on corrupted blocks — official kernel mapping:
   A=bits 7-6, B=bits 5-4, C=bits 3-2, D=bits 1-0 (our first version was inverted
   and let ~1 character in 40 through corrupted)
4. **RadioText reset on text change** (stale segments used to stay mixed in) and
   **padding stop** (all-space segments)

### FM scan with real names

- During the scan every found station stays tuned ~2.5 s to capture its RDS PS →
  the list shows "CAPITAL", "DEEJAY", "MileniuM", "RADIO 24"...
- Plus BLER filtering and a full dwell for a stable name

### Recording and audio

- **MP3 recording** (`--record-format mp3`, pipeline `arecord | ffmpeg libmp3lame 128k`)
  in addition to WAV
- **Shared ALSA device `dabdsnoop`** (`/etc/asound.conf`, dsnoop S16_LE 48 kHz):
  without it, simultaneous listening and recording failed ("Device or resource busy");
  S16_LE is mandatory on the uGreen (the automatic dsnoop in S32_LE yields no data)
- **Recording deletion** from the web UI (`DELETE /api/recordings/...`)

### Web UI

- Simplified modes: **DAB and FM only** (HD and AM removed)
- Per-mode metadata panel: DAB → Artist/Title/Live text; FM → **RT, PI, PTY**
- **Manual FM tune** (frequency input + Tune button, visible in FM mode only)
- Artwork with full text (the PS used to be truncated to 4 characters),
  4-column station layout, 3-column recordings
- English labels, fixed alignments and spacing

### uGreen platform

- `--rst-pin 23` (the raspiaudio shield default of 25 does not reset the uGreen)
- `ugreen-dabboard` overlay in `config.txt`
- Firmware **DAB 6.0.9** (tested; `rom00_patch.016` identical across boards)

### Autostart and distribution

- **systemd service** `raspiaudio-radio.service` with the correct command,
  enabled at boot (the "Start server automatically" switch in the UI shows active)
- The old dabradio project removed from autostart
- **Installation package** with an automated `install.sh`, tested on a wiped
  Raspberry Pi: packages, config.txt (SPI/I2S/overlay), asound.conf, project at
  `/opt/digital-radio`, service enabled

---

## Useful commands

```bash
# manual start (without systemd)
python3 radio.py serve --port 8686 --rst-pin 23 --i2s-master \
  --record-device dabdsnoop --record-format mp3

# service
sudo systemctl status raspiaudio-radio
sudo systemctl restart raspiaudio-radio
```

## Acknowledgements and license

Based on [RASPIAUDIOadmin/Digital-Radio-for-Raspberry-Pi](https://github.com/RASPIAUDIOadmin/Digital-Radio-for-Raspberry-Pi)
(no license declared in the original repository — all rights on the original code
remain with its authors). The changes in this fork are for personal/hobby use.
