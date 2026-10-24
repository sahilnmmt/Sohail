# Sohail firmware (P0 prototype)

ESP-IDF **v5.3.2** firmware for the ESP32-S3 desk robot: an animated face,
BLE Wi-Fi setup, and MQTT messaging between robots. This is phase **P0** of
the BRD roadmap ([`docs/03-BRD-v2-final.md`](../docs/03-BRD-v2-final.md) §15).

## What P0 does
| Feature | Status |
|---|---|
| Animated face: 9 expressions, blinking, gaze, idle motion | ✅ |
| BLE provisioning with a random 6-digit code shown on screen (FR-2) | ✅ |
| MQTT messaging: nudges, emoji reactions, text display (FR-12…16) | ✅ (no voice yet) |
| Unread queue, "tap to see", reminders, de-duplication (FR-16, FR-18) | ✅ |
| Offline companion mode when the cloud is unreachable (FR-22) | ✅ |
| Button gestures, optional capacitive touch head (FR-20) | ✅ |
| Chimes on an I²S amplifier | ✅ |
| Factory reset: hold the button for 10 s (FR-28) | ✅ |
| Presence (`online`/`offline`) via MQTT last will | ✅ |
| OTA partition layout + rollback enabled | ✅ (OTA update flow is P1) |
| Voice notes, accounts and claim codes, per-device TLS certs, secure boot | P1 |

## Hardware
- ESP32-S3 dev board with **N16R8** module (16 MB flash, 8 MB PSRAM), e.g. ESP32-S3-DevKitC-1-N16R8
- ST7789 SPI IPS display, 240×280 (1.69") or 240×240 (1.3"/1.54")
- Optional: MAX98357A I²S amp + 4 Ω/8 Ω speaker
- Optional: copper-tape touch pad on the head, wired to a touch GPIO

### Default wiring (change in `idf.py menuconfig` → *Sohail robot*)
| Signal | GPIO | | Signal | GPIO |
|---|---|---|---|---|
| LCD SCLK | 12 | | I²S BCLK | 15 |
| LCD MOSI (SDA) | 11 | | I²S LRCLK | 16 |
| LCD CS | 10 | | I²S DIN | 17 |
| LCD DC | 9 | | Button | 0 (BOOT) |
| LCD RST | 14 | | Touch pad | 4 (off by default) |
| LCD BL | 13 | | | |

Power the display and amp from 3V3 and 5V respectively. Avoid GPIO 26–37: on
N16R8 modules they are used by the flash and the octal PSRAM.

## Build and flash
```bash
# ESP-IDF v5.3.2 installed and exported (. $IDF_PATH/export.sh)
cd firmware
idf.py set-target esp32s3
idf.py menuconfig        # Sohail robot → MQTT broker URI, group, name, pins
idf.py build flash monitor
```
CI builds every push (`.github/workflows/firmware.yml`). The binaries are
attached to each run as the `sohail-esp32s3-firmware` artifact.

## Try it with two robots
1. **Start a broker** on a computer on the same Wi-Fi:
   `docker compose -f server/docker-compose.yml up -d`
   Then set the broker URI to `mqtt://<computer-LAN-IP>:1883` in menuconfig.
2. **Flash both robots** with the same *Group id* (default `family`) and
   different *Display names*.
3. **Set up Wi-Fi.** On first boot, or after a factory reset, each robot shows
   *Setup mode* and a 6-digit code. Use the **Sohail app** (`app/`, see its
   README) and tap ⊕. Or install Espressif's free **ESP BLE
   Provisioning** app (Google Play / App Store), turn on Bluetooth, then:
   1. Tap **Provision Device**.
   2. It asks to scan a QR code: tap **I don't have a QR code**.
   3. Pick `PROV_SOHAIL_XXXX` from the list.
   4. Enter the 6-digit code from the robot's screen as the
      **Proof of Possession** PIN.
   5. Choose your 2.4 GHz Wi-Fi network and type its password.

   The robot then shows *Connecting...* and goes green.
4. The status dot (top right) turns **green** when connected to the broker
   (amber = Wi-Fi only, red = offline).
5. Send to the other robot:
   | Gesture | Idle | New message waiting | Showing a message | Emoji picker |
   |---|---|---|---|---|
   | Press | send a **nudge** | open it | next / dismiss | next emoji |
   | Double-press | open the **emoji picker** | open it | **reply** with an emoji | send it |
   | Touch head | pet: happy reaction | open it | next / dismiss | send it |
   | Hold 3 s | "Hold 10s: reset" warning (release to cancel) | | | |
   | Hold 10 s | factory reset: erase Wi-Fi, reboot into setup | | | |

   After 5 minutes without activity the robot falls asleep. Any press or touch
   then just wakes it, and a new message wakes it straight to "new message".
6. Or play the app's role from the computer:
   ```bash
   pip install -r tools/requirements.txt
   python3 tools/sohail_cli.py --host <broker-ip> watch
   python3 tools/sohail_cli.py --host <broker-ip> send emoji love --name Mum
   python3 tools/sohail_cli.py --host <broker-ip> send text "Dinner's ready!"
   ```

## Test run and preview without hardware
- **Scripted test run:** `host_tests/test_scenario.c` walks a whole day in the
  robot's life through the real state machine and renderer:
  - setup code and a wrong password, then connecting
  - a nudge from Grandma and replying with an emoji
  - two queued messages, petting the head, going offline
  - falling asleep, and the reset warning

  `build/host/test_scenario <dir>` also saves one frame per step. CI uploads
  them as `storyboard.png`.
- **Interactive preview:** `sim/` compiles the same C code to WebAssembly (zig, wasm32-wasi). Open it with
  `python3 -m http.server -d firmware/sim/web 8000` and go to http://localhost:8000.
  It has a real on-screen button (it goes through the firmware's gesture decoder),
  a touch pad, simulated family messages, and Wi-Fi/server switches.
  After changing `sohail_core`, rebuild with `firmware/sim/build_wasm.sh` and commit `sim/web/sohail.wasm`.
  CI fails if it is stale.

## Code layout
```
firmware/
  main/                    ESP-IDF glue (one module per peripheral/service)
    app_main.c             startup + robot task (event queue → state machine → actions)
    display.c              ST7789 over SPI, double-buffered 40-row DMA bands
    ui.c                   25 fps face + text overlay renderer (core 1)
    net.c                  Wi-Fi station, BLE provisioning, reconnect backoff, SNTP
    messaging.c            MQTT client, topics, presence, send/receive
    input.c / audio.c      button + touch gestures / I²S chimes
  components/sohail_core/  hardware-independent logic, unit-tested on the host
    protocol.c             message JSON encode/decode + validation
    robot.c                behaviour state machine
    face.c gfx.c font5x7.c procedural face renderer, text, 5x7 font
    screen.c               full screen: face + title, status dot, code, wrapped text
    button.c touch_detect.c chime.c
  host_tests/              host unit tests, scripted test run, face preview renderer
  sim/                     virtual robot (sim.c) + WebAssembly build and browser preview (web/)
```
The robot logic is plain C with no ESP-IDF dependency, so you can change
behaviour and test it on a PC:
```bash
cmake -S firmware/host_tests -B build/host && cmake --build build/host -j
ctest --test-dir build/host --output-on-failure
build/host/render_faces /tmp/faces && python3 firmware/host_tests/contact_sheet.py /tmp/faces faces.png
```

## Security notes (prototype)
P0 is for a trusted home network. Known gaps, all scheduled for P1 in the BRD:
- The dev broker allows anonymous, unencrypted connections. Use `mqtts://` plus
  a username and password for anything beyond your desk.
- One shared group topic per family. No per-device ACLs yet.
- Secure boot, flash encryption and signed OTA are not enabled yet. They are
  one-way eFuse changes, so they are left for the production hardware.
