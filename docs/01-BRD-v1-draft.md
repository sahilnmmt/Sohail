# BRD v1 (Draft) — "Sohail" ESP32 Desk Companion Robot

> **Status:** Superseded by [`03-BRD-v2-final.md`](03-BRD-v2-final.md).
> This draft is kept on purpose: [`02-competitor-analysis.md`](02-competitor-analysis.md)
> reviews it against the market, and v2 fixes the gaps found.

## 1. Executive summary
Build a small desk robot on an ESP32 with a colour display "face", Wi-Fi, and
user accounts, so two or more people can send each other messages that show up
on each other's robots.

## 2. Problem statement
Phones are distracting and not suitable for young children or elderly relatives.
People want a simple, friendly, always-on device to stay in touch with family.

## 3. Objectives
- Expressive animated face on a display.
- Wi-Fi connectivity.
- Account-based messaging between paired robots.
- Low-cost hobbyist-friendly hardware.

## 4. Scope
**In scope:** device firmware, cloud backend, simple mobile/web app for sign-up.
**Out of scope:** video calling, mobility (wheels), third-party integrations.

## 5. Stakeholders
Product owner, firmware developer, backend developer, end users (families).

## 6. Functional requirements
| ID | Requirement |
|----|-------------|
| F1 | Robot shows animated eyes/face on a display. |
| F2 | User connects robot to Wi-Fi by entering SSID/password in a hard-coded config. |
| F3 | User creates an account with email + password. |
| F4 | User links robot to account using its serial number. |
| F5 | Users can add friends by username. |
| F6 | Users send **text** messages from app; robot displays them. |
| F7 | Robot shows a notification animation on new message. |
| F8 | Touch button to acknowledge / dismiss a message. |

## 7. Non-functional requirements
- Messages delivered within 10 s.
- Backend over HTTP REST; robot polls every 10 s.
- Cost target: under $25 BOM.

## 8. Hardware (proposed)
- ESP32-WROOM-32 (4 MB flash, no PSRAM)
- 1.3" 240×240 ST7789 SPI LCD
- 1 push button
- USB powered

## 9. Assumptions
- Users have home Wi-Fi.
- Cloud service is always available.

## 10. Success metrics
- Working prototype; messages appear on robot.
