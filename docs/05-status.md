# Project status (end of 2026-10-24)

## Live
- **Website:** https://minirobot-app.web.app (also sohail-family-jbqkl.web.app).
  Sign-in, families, invite codes, roles, robot registration.
- **Virtual robot:** https://minirobot-app.web.app/robot. Real firmware logic
  over MQTT (WebSocket); test the app without hardware.
- **Android app APK:** https://github.com/sahilnmmt/Sohail/releases/download/app-latest/sohail-app.apk
- **Firebase project:** `sohail-family-jbqkl`, free Spark plan.
  - Auth: email/password and Google.
  - Firestore in `asia-south1`; rules and index deployed.
  - Hosting: sites `minirobot-app` and `sohail-family-jbqkl`.

## In the repo
| Part | Folder | Tests |
|---|---|---|
| BRD, competitor analysis, protocol | `docs/` | — |
| ESP32-S3 firmware | `firmware/` | host unit tests, scripted journey, ESP-IDF build in CI |
| Browser robot preview / simulator | `firmware/sim/` | wasm cross-checked against native |
| Android app (Flutter) | `app/` | 24 tests incl. ESP-IDF provisioning harness and MQTT broker |
| Accounts website + virtual robot | `web/` | 21 rules tests, browser end-to-end, virtual-robot MQTT test |

## Known gaps / next steps (agreed order)
1. **App sign-in:** log in with the website account and pick a family. The
   app then sets the group and server itself, and shows only that family's
   registered robots. Today it lists every robot on the server.
2. **Robot joins the family during Bluetooth setup:** the app sends the
   family group and server to the robot and registers it. Today the group is
   set at firmware build time (menuconfig).
3. **Message server checks accounts:** per-device logins and topic ACLs
   (BRD G4/G5). Today anyone who knows a group id can join.

Also open:
- Choose a permanent message server; public brokers are for testing only.
- Optional: rename the product "Sohail" to "Mini Robot".
- Optional: custom domain (e.g. minirobot.com if available).
- Automatic deploys from GitHub need the `FIREBASE_SERVICE_ACCOUNT` secret and
  `FIREBASE_*` variables (web/README.md). Until then, deploys are manual.
- Nothing has run on real ESP32 hardware or a real phone + robot pair yet.
