# WiFi Watch (Android)

A personal app that shows the devices on your home Wi-Fi and how much data
each one uses. It reads your TP-Link router the way the router's own web page
does, so nothing leaves your home network.

- **Devices:** who is online now, their IP address, Wi-Fi band or wired, live
  speed, and data used today. Offline devices show when they were last seen.
- **Usage:** total for today, 7 or 30 days, a bar per day, and the top devices.
- **Device page:** give a device a name ("Mom's phone"), see its last 7 days.
- **New device alert:** a banner when a device joins for the first time.
- **Demo mode:** pretend devices, to try the app without a router.

## Install the APK
On your Android phone, open
**https://github.com/sahilnmmt/Sohail/releases/download/wifi-watch-latest/wifi-watch.apk**
and open the downloaded file. Android asks you to allow installing apps from
your browser the first time. CI updates that link after every push. Each
Actions run also keeps the APK as the `wifi-watch-apk` artifact.

## First run
The app starts in **Demo** mode. To use your router:
1. Connect the phone to your home Wi-Fi.
2. **Settings** (gear icon) → **My router**.
3. Router address `192.168.0.1`, user name `admin`, and the router's **admin
   password** (the one for its web page, not the Wi-Fi password).
4. Tap **Test connection**. It logs every step; the copy button copies the log
   (the password is never in it) so you can send it for help.
5. **Save**.

## Things to know
- **Bridge mode for extra routers.** A second router in *router* mode hides
  every device behind it: the main router sees one device. Put it in
  bridge/access-point mode so each device shows separately.
- **One login at a time.** TP-Link routers allow one admin session. While the
  app is open it holds that session, so the router's web page may log you out,
  and opening the web page logs the app out (it logs in again by itself).
- **Usage is counted while the app is open,** unless the router keeps its own
  per-device byte counters (some MR/VR models do; the app then uses those and
  nothing is missed). Without counters, usage is estimated from live speeds
  every few seconds.
- After a wrong password the app stops trying, because routers lock the login
  after a few failures. Fix the password in Settings.

## Supported routers
TP-Link routers whose web page uses the encrypted `cgi_gdpr` interface: the
ISP and LTE families (Archer MR, VR, EX, XC, VX and XX models). The app tries
each known variant and remembers the one that works:

| Variant | Routers | Device list | Usage |
|---|---|---|---|
| `ex-gcm`, `ex-cbc` | EX, XC, VX, XX (ISP fibre/VoIP) | yes | from live speed, once the fields are known for the model |
| `vr-cbc` | Archer VR (DSL) | yes | router counters if traffic statistics is on |
| `mr-cbc`, `mr-gcm` | Archer MR (LTE) | yes | router counters if traffic statistics is on |

The protocol details come from the open-source
[tplinkrouterc6u](https://github.com/AlexandrErohin/TP-Link-Archer-C6U)
library (GPL-3.0). The `mr-gcm` login is a best guess: the library has no
working version of it to compare against.

**Archer XX530v:** not yet tried on the real router. Run **Test connection**
on your home Wi-Fi and send the log: it lists every per-device field the
router reports, so traffic for this model can be added.

## How it fits together
| Part | Where |
|---|---|
| Router login and requests (RSA signature, AES-CBC/GCM) | `lib/src/router/tplink_client.dart`, `tplink_crypto.dart` |
| Demo network | `lib/src/router/demo_source.dart` |
| Devices and daily usage, saved on the phone | `lib/src/usage.dart` |
| Polling while the app is open | `lib/src/monitor.dart` |
| Screens | `lib/src/ui/` |

## Tests
```bash
flutter analyze && flutter test
```
The client tests log in to a test router (`test/support/fake_tplink_router.dart`)
that checks signatures, keys, sessions and tokens like a real one, in every
variant. `test/tplink_interop_test.dart` checks that test router against the
tplinkrouterc6u library itself; it runs only with
`TPLINK_PYTHON=/path/to/python-with-tplinkrouterc6u`.
