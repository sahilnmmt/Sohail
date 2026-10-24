# Device Protocol v1 (P0 prototype)

How Sohail robots and clients (the P0 CLI now, the companion app later) talk
over MQTT. It is documented so anyone can run their own server or client
(BRD NFR-11, gap G8).

## Transport
- MQTT 3.1.1. Use `mqtts://` (TLS) for any broker outside your LAN.
- Client id = device id, e.g. `sohail-a1b2c3` (`sohail-` + last 3 MAC bytes).
- Keepalive 30 s. Clean session.
- Messages use **QoS 1**, so receivers must de-duplicate by `id`. The robot
  remembers the last 16 ids.

## Topics
| Topic | Direction | Retained | Payload |
|---|---|---|---|
| `sohail/v1/group/<group>/inbox` | any member → group | no | message JSON |
| `sohail/v1/dev/<device>/inbox` | anyone → one robot | no | message JSON |
| `sohail/v1/dev/<device>/status` | robot → everyone | **yes** | `online` / `offline` (LWT) |

Ids (`<group>`, `<device>`, message `id`, `from`) are 1–24 characters from
`[A-Za-z0-9_-]`, so they cannot inject MQTT wildcards (`+`, `#`) or levels (`/`).

A robot subscribes to its own inbox and its group inbox. In P0 it publishes
nudges and reactions to the group, and ignores its own messages when the
broker echoes them back.

## Message JSON
```json
{"v":1,"id":"6e6697d2febb3c06","from":"sohail-a1b2c3","name":"Grandma",
 "type":"emoji","emoji":"love","ts":1761300000}
```
| Field | Required | Rules |
|---|---|---|
| `v` | yes | must be `1` |
| `id` | yes | unique per message (random hex recommended) |
| `from` | yes | sender's device or client id |
| `name` | no | display name, ≤ 16 bytes, no control characters |
| `type` | yes | `nudge`, `emoji` or `text` |
| `emoji` | if `type` = `emoji` | `happy`, `love`, `laugh`, `sad`, `wow`, `sleepy` |
| `text` | if `type` = `text` | 1–140 bytes UTF-8; `\n` allowed, no other control characters |
| `ts` | no | Unix seconds; `0` or missing if the sender's clock is not set |

Receivers drop anything that breaks these rules. They also drop payloads over
1 KB and unknown types. Unknown extra fields are ignored, so fields can be
added later without breaking older robots.

## Not in v1 (planned for P1)
- Per-device credentials (X.509) and broker ACLs limiting each device to its own topics.
- Account claim codes, contacts with mutual consent, and direct-message routing through the API.
- Voice notes: uploaded to object storage, and the message carries a pre-signed URL.
- Delivery and "played" receipts.
