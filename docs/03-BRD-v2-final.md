# Business Requirements Document (v2) — "Sohail" ESP32 Companion Messenger Robot

| Field | Value |
|---|---|
| Version | 2.0 (replaces v1 draft) |
| Date | 2026-10-24 |
| Status | Ready for review |
| Related | [`01-BRD-v1-draft.md`](01-BRD-v1-draft.md), [`02-competitor-analysis.md`](02-competitor-analysis.md) |

Gap IDs (G1–G14) refer to the competitor analysis; each one is marked where v2 fixes it.

---

## 1. Executive summary
Sohail is a small, expressive desk robot built on the **ESP32-S3**. It has an
animated display face, a microphone and speaker, and Wi-Fi. Each robot belongs
to a user **account**, and people send **voice notes, nudges, emoji reactions
and short texts** to each other's robots or from a companion app. It is aimed
at families who want to stay in touch, especially with **children and elderly
relatives** who should not need a smartphone.

Positioning: *a friendship lamp with a face and a voice*. It has the emotional
pull of companion robots (EMO, Vector) and the guardian-controlled contacts of
kids' communication devices (Tin Can, Relay), with **no mandatory
subscription** and an **open, self-hostable backend**.

## 2. Problem statement
1. Smartphones are distracting, expensive and unsuitable for young children
   and some elderly people.
2. Existing companion robots have personality but no way for **people** to
   talk through them.
3. Existing kids' communication devices work but have no personality, and many
   require monthly plans.
4. Cloud-dependent gadgets lose features or stop working when the vendor
   changes course (the Vector/Jibo experience). (G8)

## 3. Business objectives
| ID | Objective | Measure |
|---|---|---|
| BO1 | Launch a Lite and a Plus SKU in the $59–119 retail band. (G12) | Retail price met with ≥ 60 % gross margin at 1k units. |
| BO2 | Make setup easy for non-technical users. (G2) | ≥ 90 % of users finish setup in < 5 min without support. |
| BO3 | Deliver messages reliably in real time. (G6) | p95 delivery < 2 s; ≥ 99.5 % delivered. |
| BO4 | Earn trust with families and guardians. (G5, G11) | Zero critical security incidents; COPPA/GDPR compliant at launch. |
| BO5 | Keep users engaged. (G13) | ≥ 40 % of devices active weekly at day 90; return rate < 5 %. |

## 4. Scope
**In scope (MVP)**
- Device firmware (ESP32-S3), animated face, audio, touch, OTA.
- Cloud backend: accounts, devices, contacts, messaging, push.
- Companion app (iOS/Android; Flutter or React Native) and a basic web portal.
- Self-host package (Docker Compose) and documented device API. (G8)

**Out of scope (MVP) — candidates for later releases**
- Live two-way voice/video calls (later: WebRTC-based live voice on Plus).
- Wheels / mobility.
- LLM voice assistant (later, opt-in only, guardian controlled).
- Smart-home integrations.

## 5. Stakeholders & personas
| Stakeholder | Interest |
|---|---|
| Product owner | Positioning, pricing, roadmap |
| Firmware, backend, app engineers | Build and maintain the system |
| Industrial / PCB designer | Enclosure, PCB, certification readiness |
| Compliance / legal | COPPA, GDPR, CE/FCC/RED, battery transport |

| Persona | Needs |
|---|---|
| **Aisha, 7 (child)** | Send a voice note to grandma by holding one button; can't read well yet. |
| **Farah, 38 (parent / guardian)** | Approve who her child can talk to; set quiet hours; see device status. |
| **Rashid, 72 (grandparent)** | Large clear face, loud speaker, no app needed day to day. |
| **Long-distance friends/couples** | Cute "thinking of you" nudges and reactions. |
| **Makers** | Open API, custom faces, self-hosting. |

## 6. Functional requirements
Priority: **M** = Must (MVP), **S** = Should, **C** = Could.

### 6.1 Onboarding & accounts
| ID | Requirement | Pri | Fixes |
|---|---|---|---|
| FR-1 | Users sign up in the app with email + password or Sign in with Apple/Google; email verification required. | M | — |
| FR-2 | Robot is set up over **BLE provisioning** from the app (Wi-Fi SSID/password sent encrypted). **SoftAP captive portal** fallback when no app is available. | M | G2 |
| FR-3 | Robot shows a **6-digit, short-lived claim code** (and QR) on screen; the account enters/scans it to claim the device. Serial numbers alone can never claim a device. | M | G4 |
| FR-4 | A device can be released (factory reset or from the app) and re-claimed. | M | — |
| FR-5 | **Guardian accounts** can manage child profiles; a child profile has no email and no login of its own. | M | G5 |
| FR-6 | Multiple Wi-Fi networks can be saved (home, grandparents' house). | S | — |

### 6.2 Contacts & safety
| ID | Requirement | Pri | Fixes |
|---|---|---|---|
| FR-7 | Contacts are added by **invite link / QR / username**, and are **mutual-consent**: both sides (or their guardians) must accept. | M | G5 |
| FR-8 | For child profiles, the guardian must approve every contact. | M | G5 |
| FR-9 | Block and report a contact; blocked users cannot see or message the device. | M | G5 |
| FR-10 | **Quiet hours / do-not-disturb** schedule per device; messages queue and play afterwards. | M | — |
| FR-11 | Groups (e.g. "Family") of up to 20 members. | S | — |

### 6.3 Messaging
| ID | Requirement | Pri | Fixes |
|---|---|---|---|
| FR-12 | **Push-to-talk voice notes** from the robot (hold the head/button, up to 30 s) and from the app. | M | G1 |
| FR-13 | **Nudges** — one-tap "thinking of you" signal with a matching face animation on the receiver. | M | G1 |
| FR-14 | **Emoji reactions** shown as face expressions (happy, love, laugh, sad, wow, sleepy). | M | G1 |
| FR-15 | Short **text** messages (≤ 140 chars), scrolled on the display; optional text-to-speech on Plus. | S | G1 |
| FR-16 | New-message animation + sound; message waits until the user touches to play it. | M | — |
| FR-17 | Delivery and "played" receipts in the app. | S | — |
| FR-18 | Offline robots get queued messages when they reconnect (stored for up to 7 days). | M | — |

### 6.4 Personality & device behaviour
| ID | Requirement | Pri | Fixes |
|---|---|---|---|
| FR-19 | Animated face with idle behaviours (blink, look around, sleep at night). | M | — |
| FR-20 | Capacitive touch on the head (pet = happy reaction, hold = record). | M | G10 |
| FR-21 | Clock, weather and day/night face modes. | S | — |
| FR-22 | **Local fallback mode**: if the cloud is unreachable, the robot still works as a clock + expressive companion and can message other robots on the same LAN. | M | G8 |
| FR-23 | Downloadable face packs / skins. | C | — |
| FR-24 | Plus SKU: servo head tilt synced to emotions. | C | G10 |

### 6.5 Device management
| ID | Requirement | Pri | Fixes |
|---|---|---|---|
| FR-25 | **Signed OTA firmware updates** with A/B partitions and automatic rollback on failed boot. | M | G7 |
| FR-26 | App shows device status: online, battery, firmware version, Wi-Fi strength. | M | — |
| FR-27 | Volume, brightness and quiet hours controlled from the app and the device. | M | — |
| FR-28 | Factory reset by long-pressing the button for 10 s. | M | — |

## 7. Non-functional requirements
| ID | Category | Requirement | Fixes |
|---|---|---|---|
| NFR-1 | Latency | p95 message delivery < 2 s when both ends are online. | G6 |
| NFR-2 | Transport | Device ↔ cloud over **MQTT 3.1.1/5 on TLS 1.2+** (persistent connection, no polling); app ↔ cloud over HTTPS REST + push notifications (APNs/FCM). Voice files uploaded/downloaded via pre-signed HTTPS URLs. | G4, G6 |
| NFR-3 | Device identity | Per-device credential (X.509 cert or rotating token) provisioned in the factory; MQTT ACLs limit each device to its own topics. | G4 |
| NFR-4 | Firmware security | ESP32-S3 **Secure Boot v2 + flash encryption** enabled in production; OTA images signed; JTAG disabled. | G4, G7 |
| NFR-5 | Data protection | Encryption in transit everywhere and at rest in the cloud. Voice notes deleted after 30 days by default (configurable shorter). End-to-end encryption is a v2.x goal. | G11 |
| NFR-6 | Privacy | **Hardware mic-mute switch** with an LED; mic only records while the record gesture is held. No always-listening wake word in MVP. | G11 |
| NFR-7 | Availability | Cloud ≥ 99.9 % monthly uptime. | — |
| NFR-8 | Scalability | Backend handles 100k devices on the initial architecture without redesign. | — |
| NFR-9 | Power | Plus SKU: ≥ 24 h typical use on battery; idle Wi-Fi current minimised with modem sleep. | G9 |
| NFR-10 | Usability | Setup ≤ 5 min; core actions (send voice, nudge, play) need no reading. | G1, G2 |
| NFR-11 | Openness | Device ↔ server protocol documented; server available as open-source self-host package; user can point a device at their own server. | G8 |
| NFR-12 | Longevity | Commitment: security updates for ≥ 3 years; if the service ends, publish an unlock firmware and server. | G8 |
| NFR-13 | Localisation | UI strings localisable; launch with English, plus at least one more language (e.g. Urdu/Hindi/Arabic). | — |

## 8. Hardware requirements
| Component | Lite SKU | Plus SKU | Notes / fixes |
|---|---|---|---|
| MCU | **ESP32-S3-WROOM-1 N16R8** (16 MB flash, 8 MB PSRAM) | same | Enough RAM for frame buffer + audio + TLS. (G3) |
| Display | 1.69"–2.0" IPS, 240×280 / 240×320, ST7789, SPI | 2.0"–2.4" IPS, optional touch | LVGL for UI and animations. |
| Microphone | I²S MEMS (e.g. INMP441 class) | same | |
| Speaker | I²S amp (MAX98357A class) + 1–2 W speaker | same | (G10) |
| Input | Capacitive touch pad (head) + 1 button | + touch panel | (G10) |
| Privacy | Hardware mic-mute switch + LED | same | (G11) |
| Power | USB-C 5 V | USB-C + 1500–2000 mAh Li-ion, charger IC (e.g. TP4056/IP5306 class) with protection, fuel gauge | (G9) |
| Motion | — | 1 micro servo (head tilt) | (G10) |
| Status | RGB LED | RGB LED | |
| Enclosure | ABS/PC, kid-safe, no small detachable parts | same | |
| Target BOM @1k units | ~$18–28 | ~$30–40 | Realistic vs. retail. (G14) |

## 9. System architecture (summary)
```
 [Robot ESP32-S3] --MQTT/TLS--> [MQTT broker (EMQX/Mosquitto)]
        |                                   |
        |--HTTPS (voice upload/download)--> [Object storage (S3-compatible)]
        |                                   |
 [Companion app] --HTTPS REST--> [API service] -- [PostgreSQL]
        ^                                   |
        +------ APNs / FCM push <-----------+
```
- **Firmware:** ESP-IDF (FreeRTOS), LVGL, ESP-ADF/I²S audio (Opus encoding for voice notes), esp-mqtt, esp_https_ota, wifi_provisioning (BLE).
- **Backend:** containerised API (e.g. Node/TypeScript or Go), PostgreSQL, MQTT broker, object storage; shipped as Docker Compose for self-hosting.
- **App:** cross-platform; handles sign-up, BLE provisioning, contacts, messaging, guardian controls.

## 10. Compliance & regulatory (G11)
- **Children's privacy:** COPPA (US) verifiable parental consent; UK Age-Appropriate Design Code; GDPR/GDPR-K (EU).
- **Data protection:** GDPR/UK GDPR, data export and account deletion in the app.
- **Radio & EMC:** FCC Part 15 (US), CE RED (EU), UKCA; use a pre-certified module to reduce cost.
- **Safety:** IEC 62368-1; toy-safety review (EN 71 / ASTM F963) if marketed to children; UN 38.3 for battery shipping (Plus).
- **Security baseline:** align with ETSI EN 303 645 / EU Cyber Resilience Act (no default passwords, update policy, vulnerability disclosure).
- **Environmental:** RoHS, WEEE.

## 11. Business model & pricing (G12)
| Item | Lite | Plus |
|---|---|---|
| Target retail | $59–79 | $99–119 |
| Bundle | "Family 2-pack" at ~10 % discount (messaging needs two robots) | Same |
| Subscription | **None required.** Optional "Family+" (~$2–3/month): longer voice history, larger groups, extra face packs. | Same |
| Channels | Direct web store, Amazon, crowdfunding launch (Kickstarter/Indiegogo) | Same |

Competitive price check: below EMO/Vector/Loona, at or slightly above friendship lamps and Tin Can, while offering more than either category.

## 12. Assumptions, constraints & dependencies
- Users have 2.4 GHz Wi-Fi (ESP32-S3 does not support 5 GHz) — state this clearly on the box and in setup. 
- Messaging needs at least one other robot or app user; bundle and app-to-robot messaging lower this barrier.
- Depends on Apple/Google push services and app-store approval.
- Cloud is **not** assumed always-available; device must degrade gracefully (FR-22). (G8)

## 13. Risks & mitigations
| Risk | Impact | Mitigation |
|---|---|---|
| Device hijack / unwanted contact with a child | Critical | Claim codes, mutual consent, guardian approval, block/report, security audit before launch. |
| Vendor/cloud shutdown bricks devices | High | Open protocol, self-host server, unlock pledge (NFR-11/12). |
| Big-tech smart displays undercut price | Medium | Compete on personality, privacy, kid safety, no subscription. |
| Network effect — robot useless alone | High | 2-pack bundle, app-to-robot messaging, local companion features. |
| Certification delays / cost | Medium | Pre-certified module, early pre-scan testing. |
| Battery safety (Plus) | Medium | Protected cell, certified charger IC, UN 38.3. |
| Component supply / price swings | Medium | Second-source display and audio parts. |

## 14. Success metrics / KPIs (G13)
| KPI | Target |
|---|---|
| Setup success without support | ≥ 90 % |
| Median setup time | ≤ 5 min |
| p95 message delivery latency | < 2 s |
| Message delivery success | ≥ 99.5 % |
| Weekly active devices at day 90 | ≥ 40 % |
| Messages per active device per week | ≥ 10 |
| Return rate | < 5 % |
| App store rating | ≥ 4.3 |

## 15. Roadmap & milestones
| Phase | Duration | Deliverables |
|---|---|---|
| P0 — Prototype | 4–6 weeks | ESP32-S3 dev board + display + I²S audio; face animation; MQTT messaging between two robots; BLE provisioning. |
| P1 — MVP | 8–12 weeks | Accounts, claim codes, contacts with consent, voice notes, nudges, reactions, OTA, app v1, guardian controls. |
| P2 — Beta | 6–8 weeks | Custom PCB + enclosure, 50–100 beta families, security audit, KPI instrumentation. |
| P3 — Launch | 8–12 weeks | Certification, manufacturing run, crowdfunding/web store, self-host package release. |
| Later | — | Live voice calls, opt-in AI assistant, face pack store, smart-home hooks. |

## 16. Change log from v1
| v1 item | v2 change | Gap |
|---|---|---|
| Text-only messages | Voice notes, nudges, emoji reactions; text optional | G1 |
| Hard-coded Wi-Fi | BLE provisioning + SoftAP fallback | G2 |
| ESP32-WROOM, no PSRAM | ESP32-S3 N16R8 | G3 |
| HTTP, serial-number linking | TLS, per-device credentials, claim codes, secure boot, flash encryption | G4 |
| Anyone can message by username | Mutual consent, guardian approval, block/report | G5 |
| 10 s polling | MQTT push, < 2 s p95 | G6 |
| No OTA | Signed A/B OTA with rollback | G7 |
| Cloud always available | Local fallback, open protocol, self-host, unlock pledge | G8 |
| USB only | Battery option on Plus SKU | G9 |
| One button, no audio | Mic, speaker, capacitive touch, optional servo | G10 |
| No privacy/compliance | Mic-mute switch, retention limits, compliance plan | G11 |
| No pricing/positioning | Lite/Plus SKUs, no mandatory subscription | G12 |
| Prototype-only metrics | Measurable KPIs | G13 |
| $25 BOM | Realistic BOM per SKU | G14 |
