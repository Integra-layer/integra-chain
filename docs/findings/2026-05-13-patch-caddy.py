#!/usr/bin/env python3
"""
Atomic Caddy patch — adds transport http { ... } block to every
reverse_proxy localhost:8545 in /etc/caddy/Caddyfile.
Backs up, patches, validates, reloads. Aborts if anything looks off.
"""
import hashlib
import os
import shutil
import subprocess
import sys
import time

CADDYFILE = "/etc/caddy/Caddyfile"
BACKUP = f"/etc/caddy/Caddyfile.bak.{int(time.time())}"

TRANSPORT = "\t\t\ttransport http {\n" \
            "\t\t\t\tmax_conns_per_host 64\n" \
            "\t\t\t\tdial_timeout 3s\n" \
            "\t\t\t\tresponse_header_timeout 12s\n" \
            "\t\t\t\tread_timeout 14s\n" \
            "\t\t\t\twrite_timeout 14s\n" \
            "\t\t\t}"

REPLACEMENTS = [
    # 1. /evm/* in testnet.integralayer.com
    (
        "\thandle_path /evm/* {\n\t\treverse_proxy localhost:8545 {\n\t\t\theader_down -Access-Control-Allow-Origin\n\t\t\theader_down -Access-Control-Allow-Methods\n\t\t\theader_down -Access-Control-Allow-Headers\n\t\t}\n\t}",
        "\thandle_path /evm/* {\n\t\treverse_proxy localhost:8545 {\n\t\t\theader_down -Access-Control-Allow-Origin\n\t\t\theader_down -Access-Control-Allow-Methods\n\t\t\theader_down -Access-Control-Allow-Headers\n" + TRANSPORT + "\n\t\t}\n\t}",
    ),
    # 2. /evm (no slash) in testnet.integralayer.com
    (
        "\thandle_path /evm {\n\t\treverse_proxy localhost:8545 {\n\t\t\theader_down -Access-Control-Allow-Origin\n\t\t\theader_down -Access-Control-Allow-Methods\n\t\t\theader_down -Access-Control-Allow-Headers\n\t\t}\n\t}",
        "\thandle_path /evm {\n\t\treverse_proxy localhost:8545 {\n\t\t\theader_down -Access-Control-Allow-Origin\n\t\t\theader_down -Access-Control-Allow-Methods\n\t\t\theader_down -Access-Control-Allow-Headers\n" + TRANSPORT + "\n\t\t}\n\t}",
    ),
    # 3 & 4. plain /evm reverse_proxy with no body — testnet.explorer & admin.testnet.explorer
    (
        "\thandle_path /evm {\n\t\treverse_proxy localhost:8545\n\t}",
        "\thandle_path /evm {\n\t\treverse_proxy localhost:8545 {\n" + TRANSPORT + "\n\t\t}\n\t}",
    ),
]


def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        h.update(f.read())
    return h.hexdigest()


with open(CADDYFILE, "r") as f:
    original = f.read()

print("[INFO] original md5:", md5(CADDYFILE))
print("[INFO] original size:", len(original), "bytes")

new = original
hits = {}
for i, (old, repl) in enumerate(REPLACEMENTS, 1):
    count = new.count(old)
    hits[i] = count
    if count > 0:
        new = new.replace(old, repl)

print("[INFO] replacement hit counts:", hits)
total = sum(hits.values())
if total < 4:
    print("[FAIL] expected >= 4 total replacements, got", total, "- aborting")
    sys.exit(1)
if total > 6:
    print("[FAIL] suspiciously many replacements (", total, ") - aborting")
    sys.exit(1)

tcount = new.count("transport http")
print("[INFO] 'transport http' blocks in new file:", tcount)
if tcount < 4:
    print("[FAIL] not enough transport blocks - aborting")
    sys.exit(1)

shutil.copy2(CADDYFILE, BACKUP)
print("[OK] backup written:", BACKUP)

tmp = CADDYFILE + ".new"
with open(tmp, "w") as f:
    f.write(new)
print("[INFO] wrote", tmp, "(", len(new), "bytes, md5", md5(tmp), ")")

print("[INFO] running caddy validate on tmp file...")
r = subprocess.run(["caddy", "validate", "--config", tmp, "--adapter", "caddyfile"],
                   capture_output=True, text=True, timeout=15)
print("--- caddy validate stdout ---")
print(r.stdout)
print("--- caddy validate stderr ---")
print(r.stderr)
if r.returncode != 0:
    print("[FAIL] caddy validate returned", r.returncode, "- aborting, NOT swapping file")
    print("[INFO] failed tmp file kept at", tmp, "for inspection")
    sys.exit(2)

os.replace(tmp, CADDYFILE)
print("[OK] swapped", tmp, "->", CADDYFILE)
print("[INFO] new md5:", md5(CADDYFILE))

print("[INFO] running systemctl reload caddy...")
r = subprocess.run(["systemctl", "reload", "caddy"], capture_output=True, text=True, timeout=15)
print("rc =", r.returncode, "| stdout:", r.stdout, "| stderr:", r.stderr)
if r.returncode != 0:
    print("[WARN] caddy reload failed - rolling back to backup")
    shutil.copy2(BACKUP, CADDYFILE)
    subprocess.run(["systemctl", "reload", "caddy"])
    sys.exit(3)

print("[OK] caddy reloaded successfully")
print("[ROLLBACK] cp", BACKUP, CADDYFILE, "&& systemctl reload caddy")
