# WiFi Watch (Android)

A personal app that shows the devices on your home Wi-Fi and how much data
each one uses. It reads your TP-Link router the way the router's own web page
does, so nothing leaves your home network.

- **Devices:** who is online now, their IP address, Wi-Fi band or wired, live
  speed, and data used today. Offline devices show when they were last seen.
- **Usage:** total for today, 7 or 30 days, a bar per day, and the top devices.
- **Device types:** a phone, TV, laptop, router... icon, guessed from the
  device's name; you can change it.
- **Search and filters:** find a device by name, IP or MAC; show all, online
  or unknown devices.
- **New and unknown devices:** a banner when a device joins for the first
  time. It stays *Unknown* until you tap *It's ours*.
- **Device page:** give a device a name ("Mom's phone"), see its data for the
  last 7 days, time online per day and its recent visits.
- **Daily limits:** set a limit for a device or the whole network; a warning
  shows when it goes over.
- **Demo mode:** pretend devices, to try the app without a router.

How it compares with Fing and TP-Link Tether: [COMPETITORS.md](COMPETITORS.md).
The build id is in Settings and in the connection test log.

## Install the APK
On your Android phone, open
**https://github.com/sahilnmmt/Sohail/releases/download/wifi-watch-latest/wifi-watch.apk**
and open the downloaded file. Android asks you to allow installing apps from
your browser the first time. CI updates that link after every push. Each
Actions run also keeps the APK as the `wifi-watch-apk` artifact.

Each build is signed with the same key, kept in the Actions cache, so a new
build installs over the old one. If Android says *"package conflicts with an
existing package"*, the key changed (GitHub drops a cache unused for 7 days):
uninstall WiFi Watch once and install again. Settings and history are lost.

## First run
The app starts in **Demo** mode. To use your router:
1. Connect the phone to your home Wi-Fi.
2. **Settings** (gear icon) → **My router**.
3. Router address `192.168.0.1` and the router's **admin password** (the one
   for its web page, not the Wi-Fi password). If the router's login page asks
   only for a password, leave the user name empty: the app tries `user`, then
   `admin`, and remembers the one that works. Never your TP-Link ID email:
   that login goes through TP-Link's cloud and gives the app no session.
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

**Archer XX530v:** logs in with `ex-cbc` (password-only page). Not yet
confirmed end to end. Run **Test connection**
on your home Wi-Fi and send the log: it lists every per-device field the
router reports, so traffic for this model can be added.

## How it fits together
| Part | Where |
|---|---|
| Router login and requests (RSA signature, AES-CBC/GCM) | `lib/src/router/tplink_client.dart`, `tplink_crypto.dart` |
| Demo network | `lib/src/router/demo_source.dart` |
| Devices, visits and daily usage, saved on the phone | `lib/src/usage.dart` |
| Device type guessing | `lib/src/device_kind.dart` |
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
