#!/usr/bin/env python3
"""Stand-in for the companion app during P0: send messages to Sohail robots and
watch group traffic.

Examples:
    python3 tools/sohail_cli.py --host 192.168.1.10 send nudge
    python3 tools/sohail_cli.py send emoji love --name Grandma
    python3 tools/sohail_cli.py send text "Dinner at 7!" --to sohail-a1b2c3
    python3 tools/sohail_cli.py watch

The wire format is documented in docs/04-device-protocol.md.
"""
import argparse
import json
import re
import secrets
import ssl
import sys
import time

import paho.mqtt.client as mqtt

PROTO_VERSION = 1
EMOJIS = ("happy", "love", "laugh", "sad", "wow", "sleepy")
ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,24}$")
NAME_MAX = 16
TEXT_MAX = 140


def valid_id(value):
    if not ID_RE.match(value):
        raise argparse.ArgumentTypeError(f"{value!r}: use 1-24 letters, digits, '-' or '_'")
    return value


def build_message(sender, name, kind, emoji=None, text=None):
    msg = {"v": PROTO_VERSION, "id": secrets.token_hex(8), "from": sender, "type": kind,
           "ts": int(time.time())}
    if name:
        if len(name.encode()) > NAME_MAX:
            raise ValueError(f"name must be at most {NAME_MAX} bytes")
        msg["name"] = name
    if kind == "emoji":
        if emoji not in EMOJIS:
            raise ValueError(f"emoji must be one of {', '.join(EMOJIS)}")
        msg["emoji"] = emoji
    elif kind == "text":
        if not text or len(text.encode()) > TEXT_MAX:
            raise ValueError(f"text must be 1-{TEXT_MAX} bytes")
        msg["text"] = text
    return msg


def topic_for(args):
    if args.to:
        return f"sohail/v1/dev/{args.to}/inbox"
    return f"sohail/v1/group/{args.group}/inbox"


def connect(args):
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=args.client_id)
    if args.user:
        client.username_pw_set(args.user, args.password)
    if args.tls:
        client.tls_set(cert_reqs=ssl.CERT_REQUIRED)
    client.connect(args.host, args.port, keepalive=30)
    return client


def cmd_send(args):
    try:
        msg = build_message(args.client_id, args.name, args.kind, args.value if args.kind == "emoji" else None,
                            args.value if args.kind == "text" else None)
    except ValueError as e:
        sys.exit(f"error: {e}")
    client = connect(args)
    client.loop_start()
    info = client.publish(topic_for(args), json.dumps(msg), qos=1)
    info.wait_for_publish(timeout=10)
    client.loop_stop()
    client.disconnect()
    if not info.is_published():
        sys.exit("error: broker did not acknowledge the message")
    print(f"sent {args.kind} to {topic_for(args)} ({msg['id']})")


def cmd_watch(args):
    client = connect(args)
    topics = [f"sohail/v1/group/{args.group}/inbox", "sohail/v1/dev/+/status"]

    def on_connect(c, userdata, flags, reason, props):
        for t in topics:
            c.subscribe(t, qos=1)
        print(f"watching {', '.join(topics)} (Ctrl-C to stop)", flush=True)

    def on_message(c, userdata, m):
        payload = m.payload.decode(errors="replace")
        if m.topic.endswith("/status"):
            print(f"[status] {m.topic.split('/')[3]}: {payload}", flush=True)
            return
        try:
            msg = json.loads(payload)
            who = msg.get("name") or msg.get("from")
            detail = msg.get("emoji") or msg.get("text") or ""
            print(f"[{msg.get('type')}] {who} {detail}".rstrip(), flush=True)
        except (ValueError, AttributeError):
            print(f"[invalid] {payload!r}", flush=True)

    client.on_connect = on_connect
    client.on_message = on_message
    try:
        client.loop_forever()
    except KeyboardInterrupt:
        pass


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--host", default="localhost")
    p.add_argument("--port", type=int, default=1883)
    p.add_argument("--tls", action="store_true", help="use TLS (usually with --port 8883)")
    p.add_argument("--user")
    p.add_argument("--password")
    p.add_argument("--group", type=valid_id, default="family")
    p.add_argument("--client-id", type=valid_id, default=f"cli-{secrets.token_hex(3)}")
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("send", help="send a message")
    s.add_argument("kind", choices=("nudge", "emoji", "text"))
    s.add_argument("value", nargs="?", help="emoji name or message text")
    s.add_argument("--to", type=valid_id, help="device id for a direct message (default: the group)")
    s.add_argument("--name", default="CLI", help=f"sender name shown on the robot (max {NAME_MAX} bytes)")
    s.set_defaults(func=cmd_send)

    w = sub.add_parser("watch", help="print group messages and robot presence")
    w.set_defaults(func=cmd_watch)

    args = p.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
