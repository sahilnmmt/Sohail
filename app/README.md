# Sohail app (Android)

Flutter companion app for Sohail robots:
- **Set up a robot:** find it over Bluetooth, enter the 6-digit code from its
  screen, pick your Wi-Fi.
- **Family feed:** send nudges, emoji reactions and short texts to every robot
  in your family group, and see what the robots and other phones send.
- **Robot presence:** see which robots are online.

## Install the APK
1. Open the latest run of the **app** workflow in GitHub Actions and download
   the `sohail-app-apk` artifact. Unzip it to get `app-release.apk`.
2. Copy it to the phone and open it. Android asks you to allow installing apps
   from that source the first time.

The APK is signed with Flutter's debug key, which is fine for installing it
yourself. For Google Play you need your own signing key.

Needs Android 7.0 or newer with Bluetooth LE.

## First run
1. **Settings:** enter your name, the family group (the same *Group id* as on
   the robots, default `family`) and the message server address, for example the
   computer running `server/docker-compose.yml`, on port 1883.
2. **Set up a robot** (the ⊕ button):
   1. Hold the robot's button for 10 s until it shows *Setup mode* and a code.
   2. Tap the robot when it appears in the list.
   3. Type the code.
   4. Choose your 2.4 GHz Wi-Fi and enter its password.
3. Send a nudge. The robot shows "*your name* is thinking of you".

## How it fits together
| Part | Where |
|---|---|
| Wi-Fi setup protocol: ESP-IDF provisioning, security 1 (X25519, AES-256-CTR, 6-digit code), in pure Dart | `lib/src/provisioning/` |
| Bluetooth transport (flutter_reactive_ble, BSD licence) | `lib/src/provisioning/ble_transport.dart` |
| Message format and MQTT messaging, same rules as the firmware | `lib/src/messaging/` |
| Screens | `lib/src/ui/` |

## Tests
```bash
flutter analyze && flutter test
```
Two groups of tests need extra programs and are skipped without them. CI runs
both, and fails if anything is skipped.
- **Provisioning interop:** builds ESP-IDF's own device-side provisioning code
  (protocomm, security1, Wi-Fi config and scan handlers) into a host program and
  runs the app's setup flow against it:
  ```bash
  IDF_PATH=~/esp/esp-idf tool/prov_harness/build.sh      # ESP-IDF v5.3 with submodules
  flutter test                                           # finds tool/prov_harness/build/prov_harness
  ```
- **Messaging:** two app instances plus a simulated robot through a real broker:
  `MQTT_TEST_PORT=1883 flutter test` with mosquitto or `amqtt` running locally.

## Known limits (prototype)
- No accounts yet: you join a family by entering the same group and server as
  the robots. Accounts, invites and guardian approval are BRD phase P1.
- The message server password is stored in the app's private storage, not in
  the Android Keystore.
- Not yet tried on a real phone with a real robot: the protocol is tested
  against ESP-IDF's code, but the Bluetooth layer needs a hardware check.
