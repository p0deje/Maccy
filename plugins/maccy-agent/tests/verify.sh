#!/usr/bin/env bash
#
# verify.sh — end-to-end gate for maccy-agent. Builds, then runs the REAL
# capture paths (daemon mode, pbcopy / NSPasteboard injections) and asserts
# on the resulting history.json. Exit non-zero on any failure.
#
#   ./tests/verify.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

AGENT="$(pwd)/.build/release/maccy-agent"
[[ -x "$AGENT" ]] || swift build -c release >/dev/null

pkill -f maccy-agent 2>/dev/null || true
sleep 0.5
trap 'pkill -f maccy-agent 2>/dev/null || true' EXIT

D=$(mktemp -d /tmp/maccy-verify.XXXXXX)
H="$D/history.json"
JQ() { python3 -c "
import json, sys
d = json.load(open('$H'))
print(eval(sys.argv[1]))" "$1"; }
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "PASS: $1"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

"$AGENT" --history-path "$H" --check-interval 0.25 --heartbeat-interval 3600 &
sleep 1

# 1. fresh empty history
[[ $(JQ "d['itemCount']") == 0 ]] && ok "fresh empty history" || bad "fresh empty history"

# 2. text captured
printf 'hello lightweight maccy' | pbcopy; sleep 1.2
[[ $(JQ "any(x['string'] == 'hello lightweight maccy' for x in d['items'])") == "True" ]] \
  && ok "text captured" || bad "text captured"

# 3. adjacent duplicate collapsed (count must not grow on an identical recopy)
N1=$(JQ "len(d['items'])")
printf 'hello lightweight maccy' | pbcopy; sleep 1.2
N2=$(JQ "len(d['items'])")
[[ "$N2" == "$N1" ]] && ok "adjacent duplicate deduped ($N1 → $N2)" || bad "adjacent duplicate deduped ($N1 → $N2)"

# 4. multi-line → first-line title
printf 'first line\nsecond line\n' | pbcopy; sleep 1.2
[[ $(JQ "any(x['title'] == 'first line' for x in d['items'])") == "True" ]] \
  && ok "first-line title" || bad "first-line title"

# 5. file URL (real public.file-url, like Finder ⌘C)
swift -e 'import AppKit; let pb = NSPasteboard.general; pb.clearContents(); pb.setString("file:///etc/hosts", forType: .fileURL)' >/dev/null 2>&1
sleep 1.2
[[ $(JQ "any(('fileURLs' in x) and x['fileURLs'] == ['file:///etc/hosts'] for x in d['items'])") == "True" ]] \
  && ok "file URL captured" || bad "file URL captured"

# 6. image captured (small PNG, base64 round-trip)
screencapture -x "$D/shot.png" >/dev/null 2>&1
sips -z 64 64 "$D/shot.png" --out "$D/small.png" >/dev/null 2>&1
swift -e 'import AppKit; let data = try! Data(contentsOf: URL(fileURLWithPath: "'"$D"'/small.png")); let pb = NSPasteboard.general; pb.clearContents(); let it = NSPasteboardItem(); it.setData(data, forType: .png); pb.writeObjects([it])' >/dev/null 2>&1
sleep 1.2
BYTES=$(JQ "next((x for x in d['items'] if x.get('imageType') == 'png'), None) and len(next((x for x in d['items'] if x.get('imageType') == 'png'))['image'])")
[[ "$BYTES" =~ ^[0-9]+$ && "$BYTES" -gt 100 ]] && ok "image captured (png, $BYTES bytes)" || bad "image captured"

# 7. oversized image skipped (2MB cap) — count must not grow
python3 - "$D" <<'PY' >/dev/null
import os, struct, sys, zlib
p = sys.argv[1] + "/big.png"
def chunk(t, d):
    c = struct.pack(">I", len(d)) + t + d
    return c + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
# Incompressible-ish noise per row so the file is genuinely > 2MB.
ihdr = struct.pack(">IIBBBBB", 2048, 2048, 8, 2, 0, 0, 0)
raw = b"".join(b"\x00" + os.urandom(2048 * 3) for _ in range(2048))
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
open(p, "wb").write(png)
assert os.path.getsize(p) > 2 * 1024 * 1024, "test png not actually > 2MB"
PY
N1=$(JQ "len(d['items'])")
swift -e 'import AppKit; let data = try! Data(contentsOf: URL(fileURLWithPath: "'"$D"'/big.png")); let pb = NSPasteboard.general; pb.clearContents(); let it = NSPasteboardItem(); it.setData(data, forType: .png); pb.writeObjects([it])' >/dev/null 2>&1
sleep 1.2
N2=$(JQ "len(d['items'])")
[[ "$N2" == "$N1" ]] && ok "oversized image skipped ($N1 → $N2)" || bad "oversized image skipped ($N1 → $N2)"

# 8. marker type skipped (plugin restore path)
N=$(JQ "len(d['items'])")
swift -e 'import AppKit; let pb = NSPasteboard.general; pb.clearContents(); pb.setString("marker-test", forType: .string); pb.setString("x", forType: NSPasteboard.PasteboardType("com.ebowwa.maccy.agent.copied"))' >/dev/null 2>&1
sleep 1.2
[[ $(JQ "len(d['items'])") == "$N" ]] && ok "marker type skipped" || bad "marker type skipped"

# 9. U+FFFC sanitized out of titles (macOS 26 CoreText hang guard)
python3 -c "import subprocess; subprocess.run(['pbcopy'], input='bad\ufffctitle'.encode())"
sleep 1.2
[[ $(JQ "any(x['title'] == 'badtitle' for x in d['items'])") == "True" ]] \
  && ok "unsafe scalars sanitized" || bad "unsafe scalars sanitized"

kill %1 2>/dev/null || true

# 10. caps: --max-items 3 keeps newest 3
H2="$D/caps.json"
"$AGENT" --history-path "$H2" --max-items 3 --check-interval 0.25 --heartbeat-interval 3600 &
sleep 1
for i in cap-one cap-two cap-three cap-four cap-five; do printf "$i" | pbcopy; sleep 0.9; done
kill %1 2>/dev/null || true
JQ2() { python3 -c "
import json, sys
d = json.load(open('$H2'))
print(eval(sys.argv[1]))" "$1"; }
[[ $(JQ2 "d['itemCount']") == 3 && $(JQ2 "d['items'][0]['title']") == "cap-five" ]] \
  && ok "history capped at 3, newest first" || bad "history capped at 3"

# 11. heartbeat refreshes mtime quietly
H3="$D/hb.json"
"$AGENT" --history-path "$H3" --heartbeat-interval 1 --check-interval 10 &
sleep 1; M1=$(stat -f %m "$H3"); sleep 2.2; M2=$(stat -f %m "$H3")
kill %1 2>/dev/null || true
[[ "$M2" -gt "$M1" ]] && ok "heartbeat refreshes mtime" || bad "heartbeat refreshes mtime"

# 12. history survives an agent restart (the ISO-8601 load bug: a restart used
# to decode with the default epoch strategy, wipe the file to 0 at startup)
H4="$D/restart.json"
"$AGENT" --history-path "$H4" --check-interval 0.25 --heartbeat-interval 3600 &
sleep 1
printf 'restart-persistence-probe' | pbcopy; sleep 1.2
kill %1 2>/dev/null || true; wait %1 2>/dev/null || true
"$AGENT" --history-path "$H4" --check-interval 0.25 --heartbeat-interval 3600 &
sleep 1.5
kill %1 2>/dev/null || true; wait %1 2>/dev/null || true
JQ4() { python3 -c "
import json, sys
d = json.load(open('$H4'))
print(eval(sys.argv[1]))" "$1"; }
[[ $(JQ4 "d['itemCount']") == 1 && $(JQ4 "d['items'][0]['title']") == "restart-persistence-probe" ]] \
  && ok "history survives restart" || bad "history survives restart"

echo
echo "maccy-agent verify: $PASS passed, $FAIL failed"
rm -rf "$D"
[[ "$FAIL" == 0 ]]