# Sohail — ESP32 Companion Messenger Robot

A small ESP32-S3 desk robot with an animated display face, Wi-Fi and
account-based messaging (voice notes, nudges, emoji reactions) between family
and friends.

## Documents
1. [`docs/01-BRD-v1-draft.md`](docs/01-BRD-v1-draft.md): the first draft of the business requirements.
2. [`docs/02-competitor-analysis.md`](docs/02-competitor-analysis.md): market comparison and the gaps found in v1 (G1–G14).
3. [`docs/03-BRD-v2-final.md`](docs/03-BRD-v2-final.md): **the current BRD**, with every gap fixed and traced.
4. [`docs/04-device-protocol.md`](docs/04-device-protocol.md): MQTT topics and message format used by the robots.

## Code
- [`firmware/`](firmware/README.md): ESP32-S3 prototype firmware (ESP-IDF v5.3.2). See its README for wiring, build and a two-robot demo.
- [`app/`](app/README.md): Android companion app (Flutter). Sets up robots over Bluetooth and sends messages. CI builds the APK.
- [`web/`](web/README.md): accounts website on Firebase (sign-in, families, invites, roles, robot registration).
- [`wifi_watch/`](wifi_watch/README.md): a separate personal Android app (Flutter) that shows the devices on your home Wi-Fi and their data usage, read from a TP-Link router.
- [`tools/sohail_cli.py`](tools/sohail_cli.py): command-line client for testing.
- [`server/`](server/docker-compose.yml): local Mosquitto broker for development.
