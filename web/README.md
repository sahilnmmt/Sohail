# Sohail accounts website

Family accounts for Sohail robots, on Firebase:
- **Sign in:** email and password (with email verification and password reset),
  or Google.
- **Families:** create one; you are its owner. Each family's id is also the
  MQTT group id its robots and phones use.
- **Invites:** adults create 7-day invite links (as adult or child). Anyone with
  the link can join, so share it privately. Invites can be cancelled.
- **Roles:**
  - Owner: everything.
  - Adult: invite people, add, rename and remove robots.
  - Child: view only.

  The owner changes roles and removes members.
- **Robots:** register a robot by its ID (`sohail-a1b2c3`). A robot belongs to
  one family at a time.
- **Connection details:** the family's group id and message server, to type
  into the app and the robot firmware.

- **Virtual robot (`/robot`):** a robot in the browser that runs the real
  firmware logic (`firmware/sim`, compiled to WebAssembly). It connects to a
  real MQTT server over WebSocket, so the Android app can talk to it before you
  build hardware. Signed-in adults can register it to their family in one tap.

Uses only Firebase Authentication, Cloud Firestore and Hosting. That fits the
free Spark plan: no Cloud Functions or billing needed.

## Put it online (one-time setup)
1. Go to https://console.firebase.google.com and click **Create a project**
   (for example `sohail-family`). Google Analytics is not needed.
2. **Build → Authentication → Get started.** Under *Sign-in method*, enable
   **Email/Password** and **Google**.
3. **Build → Firestore Database → Create database.** Choose *production mode*
   and a region close to you (for example `asia-south1`, Mumbai). The region
   cannot be changed later.
4. **Project settings (gear) → Your apps → Web (`</>`).** Register an app called
   `sohail-web`. Firebase shows a config with `apiKey`, `authDomain`,
   `projectId` and `appId`. These are public identifiers, not secrets: the
   security rules decide what anyone can do.
5. Deploy, using either option:
   - **Automatic (GitHub Actions):** in the GitHub repo, open
     *Settings → Secrets and variables → Actions*.
     - Add four **Variables**: `FIREBASE_API_KEY`, `FIREBASE_AUTH_DOMAIN`,
       `FIREBASE_PROJECT_ID`, `FIREBASE_APP_ID`.
     - Add one **Secret**, `FIREBASE_SERVICE_ACCOUNT`. To get it, open Firebase
       *Project settings → Service accounts*, click *Generate new private key*,
       and paste the whole JSON file.

     Every push then tests and deploys the site, rules and indexes. **Keep the
     private key secret: never paste it into a chat or commit it.**
   - **From your computer:**
     ```bash
     cd web
     cp .env.example .env.local     # fill in the four values
     npm ci && npm run build
     npx firebase login
     npx firebase deploy --project YOUR_PROJECT_ID --only hosting,firestore:rules,firestore:indexes
     ```
6. Open `https://YOUR_PROJECT_ID.web.app`. To use your own domain, go to
   *Hosting → Add custom domain*. If Google sign-in complains, add that domain
   under *Authentication → Settings → Authorized domains*.

## Develop and test locally
No Firebase project is needed: the site uses the local emulators when no
config is set (a yellow bar says so).
```bash
cd web
npm ci
npx firebase emulators:start --project demo-sohail    # terminal 1 (needs Java)
npm run dev                                            # terminal 2 → http://127.0.0.1:5173
```
Tests:
- `npm run test:rules`: 21 security-rule tests against the Firestore emulator.
  They check who can read and change families, members, invites and robots.
- `npm run test:e2e`: builds in emulator mode, then a real browser runs the whole story with
  three users (create, invite, join, roles, robots, delete) and saves
  screenshots to `test-results/e2e`.

## Test the app with the virtual robot
1. Open `https://YOUR_PROJECT_ID.web.app/robot` on a computer or a second phone.
2. Enter the family group from the family page (or pick the family if you are
   signed in), keep **broker.hivemq.com**, and tap **Connect robot**.
3. In the Android app's Settings, use the same group, server
   `broker.hivemq.com`, port `1883`, TLS off.
4. The robot appears in the app's robot list. Send a nudge, emoji or text from
   the app, and the robot reacts. Press the robot's button to send a nudge back.

Public brokers like broker.hivemq.com are fine for testing, but anyone can read
the messages there. Your own server needs a `wss://` WebSocket listener for the
browser robot, because the site is served over HTTPS.

`npm run test:robot` (with an MQTT server on TCP 1883 and WebSocket 8080)
checks the whole exchange in a real browser.

## Data model
| Path | What | Who can read / write |
|---|---|---|
| `users/{uid}` | name, email | only that user |
| `families/{id}` | name, owner, optional message server | members read; owner changes |
| `families/{id}/members/{uid}` | role, display name | members read; join only with a valid invite |
| `invites/{code}` | family, role, expiry (≤ 7 days) | anyone signed in who knows the code; adults create and cancel |
| `robots/{deviceId}` | family, name | family members read; adults add, rename and remove |

All rules are in `firestore.rules`.

## Not done yet
- **The message server does not check accounts yet.** Robots and phones still
  join by family group id and server address. Next step: give every robot and
  phone its own server login tied to the family, so the server refuses anyone
  else.
- **Robot registration is first come, first served by ID.** A robot should show
  a one-time claim code on its screen instead (BRD G4); that needs firmware
  support.
- The Android app does not sign in with these accounts yet.
