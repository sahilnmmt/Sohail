# WiFi Watch: competitors

What home users can already get for "who is on my Wi-Fi and how much data
do they use", checked October 2026.

| | Fing (free / paid) | TP-Link Tether | WiFi Watch |
|---|---|---|---|
| List devices on the network | yes | yes | yes |
| Device type and icon | yes, automatic | rename and change icon | guessed from the name, you can change it |
| Live speed per device | with Fingbox hardware | yes | yes, if the router reports it |
| **Data used per device, per day** | with Fingbox hardware | no, live speed only | **yes** |
| Usage history (7 / 30 days) | with Fingbox hardware | no | **yes** |
| New-device alert | paid (Starter, $2.99/month) | no | yes, while the app is open |
| Online / offline history | paid (Premium, $6.99/month), needs an always-on agent | no | yes, while the app is open |
| Unknown devices filter | yes | no | yes |
| Daily data limit warnings | no | no | **yes** |
| Block a device / parental control | paid, with Fingbox | yes | no (planned) |
| Works without a cloud account | needs an account for most features | needs a TP-Link ID | **yes, nothing leaves home** |

Sources: [Fing pricing](https://www.fing.com/pricing/),
[Fing Premium guide](https://www.fing.com/?p=996),
[Fing app listing](https://www.apkmirror.com/?p=5733131),
[TP-Link Tether listing](https://apps.apple.com/app/id599496594),
[TP-Link community: Tether shows speed, no totals](https://community.tp-link.com/en/home/uc/post/3130642?page=3).

## Where WiFi Watch is ahead
Per-device data totals and history, without buying hardware or a
subscription, with daily limit warnings. Tether shows only live speed; Fing
needs a Fingbox for bandwidth per device.

## Gaps still open
1. **Alerts while the app is closed.** Fing and Tether use an always-on box
   or the router's cloud. WiFi Watch only watches while open. Next step: an
   Android background service with a notification (uses some battery).
2. **Blocking and pausing devices.** Tether can do it through the router.
   Possible with the same router login once the XX530v connection works.
3. **Vendor from the MAC address** (Fing shows "Samsung", "Xiaomi"...). Needs
   the IEEE vendor list bundled in the app (about 1 MB). Phones now use
   private addresses, so this helps mostly for TVs and smart-home devices.
4. **Speed test and Wi-Fi signal strength.**
