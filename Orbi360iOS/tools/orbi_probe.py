#!/usr/bin/env python3
import argparse
import json
import socket
import sys
import time


DELIMITER = b"\r\n\r\n"


def recv_until(sock, marker, timeout):
    sock.settimeout(timeout)
    data = b""
    while marker not in data:
        chunk = sock.recv(16384)
        if not chunk:
            raise RuntimeError("connection closed before a full reply arrived")
        data += chunk
    return data.split(marker, 1)[0]


def send_command(sock, command_id, command, timeout):
    payload = {"id": command_id, "cmd": command}
    if command == "get-status":
        payload["mode_short"] = True
    raw = json.dumps(payload, separators=(",", ":")).encode("utf-8") + DELIMITER
    sock.sendall(raw)
    return recv_until(sock, DELIMITER, timeout)


def print_reply(command, raw):
    print("")
    print("----- %s -----" % command)
    text = raw.decode("utf-8", errors="replace")
    try:
        parsed = json.loads(text)
        print(json.dumps(parsed, ensure_ascii=False, indent=2))
    except json.JSONDecodeError:
        print(text)


def main():
    parser = argparse.ArgumentParser(
        description="Simple ORBI glasses probe. Connect the computer to the glasses Wi-Fi first."
    )
    parser.add_argument("--host", default="192.168.2.1")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--timeout", type=float, default=8.0)
    parser.add_argument(
        "--media",
        action="store_true",
        help="Also request get_media_list. This is read-only but can take longer.",
    )
    args = parser.parse_args()

    commands = ["get_info", "get-status", "get-settings"]
    if args.media:
        commands.append("get_media_list")

    print("ORBI quick probe")
    print("Target: %s:%s" % (args.host, args.port))
    print("Tip: the computer must already be connected to the glasses Wi-Fi.")
    started = time.time()

    try:
        with socket.create_connection((args.host, args.port), timeout=args.timeout) as sock:
            print("TCP: connected")
            for index, command in enumerate(commands, start=1):
                raw = send_command(sock, index, command, args.timeout)
                print_reply(command, raw)
    except TimeoutError:
        print("")
        print("FAILED: timed out.")
        print("Most likely the glasses control service is not running on 192.168.2.1:8080.")
        return 1
    except OSError as error:
        print("")
        print("FAILED: %s" % error)
        print("Check that the computer is connected to the glasses Wi-Fi, not your home Wi-Fi.")
        return 1
    except Exception as error:
        print("")
        print("FAILED: %s" % error)
        return 1

    print("")
    print("Done in %.1fs." % (time.time() - started))
    return 0


if __name__ == "__main__":
    sys.exit(main())
