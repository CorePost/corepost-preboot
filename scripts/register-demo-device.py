#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
import urllib.request


def request_json(method: str, url: str, headers: dict[str, str], body: dict) -> dict:
    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode(),
        headers={**headers, "Content-Type": "application/json"},
        method=method,
    )
    with urllib.request.urlopen(req) as response:
        return json.load(response)


def main() -> int:
    parser = argparse.ArgumentParser(description="Register a dedicated preboot demo device on the CorePost server.")
    parser.add_argument("--server-url", required=True)
    parser.add_argument("--admin-token", required=True)
    parser.add_argument("--display-name", default="corepost-preboot-demo")
    parser.add_argument("--unlock-profile", choices=("2fa", "3fa"), default="2fa")
    parser.add_argument("--usb-key-id", default=None)
    parser.add_argument("--output", default=None, help="Optional path to save the provisioning bundle JSON.")
    args = parser.parse_args()

    payload = {
        "displayName": args.display_name,
        "unlockProfile": args.unlock_profile,
    }
    if args.usb_key_id:
        payload["usbKeyId"] = args.usb_key_id

    bundle = request_json(
        "POST",
        f"{args.server_url.rstrip('/')}/admin/register",
        {"X-Admin-Token": args.admin_token},
        payload,
    )

    if args.output:
        with open(args.output, "w", encoding="utf-8") as fh:
            json.dump(bundle, fh, indent=2)
            fh.write("\n")

    json.dump(bundle, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
