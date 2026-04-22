#!/usr/bin/env bash
# Seeds or clears ClaudeWatch's usage-history.json for development.
# Writes directly to the app's sandboxed Application Support directory,
# so the app must be relaunched (or simply reopen the popover) to pick up
# changes if it was already running.
#
# Usage:
#   ./seed-usage-history.sh              # seed 365 days of synthetic history
#   ./seed-usage-history.sh --days 90    # seed a custom window
#   ./seed-usage-history.sh --seed 42    # use a different RNG seed
#   ./seed-usage-history.sh --clear      # wipe all events

set -euo pipefail

BUNDLE_ID="com.elliotykim.claudewatch"
FILE="$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Application Support/ClaudeWatch/usage-history.json"

DAYS=365
SEED=12689630   # 0xC1A0DE — matches the former in-app default
CLEAR=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --days)  DAYS="$2"; shift 2 ;;
    --seed)  SEED="$2"; shift 2 ;;
    --clear) CLEAR=1; shift ;;
    -h|--help)
      sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

mkdir -p "$(dirname "$FILE")"

if [[ "$CLEAR" == "1" ]]; then
  printf '[]' > "$FILE"
  echo "Cleared $FILE"
  exit 0
fi

DAYS="$DAYS" SEED="$SEED" OUT="$FILE" python3 - <<'PY'
import json, os, datetime as dt

days = int(os.environ["DAYS"])
seed = int(os.environ["SEED"])
out  = os.environ["OUT"]

# xorshift64 — matches the Swift SeededRNG exactly so seeded runs reproduce.
MASK = (1 << 64) - 1
state = seed if seed != 0 else 0xDEADBEEF
def nxt():
    global state
    state ^= (state << 13) & MASK
    state ^= (state >> 7)  & MASK
    state ^= (state << 17) & MASK
    return state
def rnd():
    return (nxt() & 0xFFFFFFFF) / 0xFFFFFFFF

now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
session_len = dt.timedelta(hours=5)
cursor = now - dt.timedelta(days=days)

def iso(d: dt.datetime) -> str:
    return d.strftime("%Y-%m-%dT%H:%M:%SZ")

events = []
while cursor < now:
    r = rnd()
    if   r < 0.55: gap_h = rnd() * 4
    elif r < 0.90: gap_h = 4 + rnd() * 20
    else:          gap_h = 24 + rnd() * 48
    start = cursor + dt.timedelta(hours=gap_h)
    if start >= now: break
    resets = start + session_len

    r = rnd()
    if   r < 0.55: peak = 10 + rnd() * 35
    elif r < 0.90: peak = 45 + rnd() * 35
    else:          peak = 80 + rnd() * 18

    percent = 0.5
    events.append({
        "kind": "start", "at": iso(start),
        "percent": percent, "sessionResetsAt": iso(resets),
    })

    update_count = 1 + int(rnd() * 4)
    for i in range(1, update_count + 1):
        t = start + session_len * (i / (update_count + 1))
        if t >= now: break
        fraction = i / (update_count + 1)
        percent = min(peak, 0.5 + peak * fraction + rnd() * 2)
        events.append({
            "kind": "update", "at": iso(t),
            "percent": percent, "sessionResetsAt": iso(resets),
        })

    if resets <= now:
        events.append({
            "kind": "end", "at": iso(resets),
            "percent": percent, "sessionResetsAt": iso(resets),
        })

    cursor = resets

with open(out, "w") as f:
    json.dump(events, f)

print(f"Wrote {len(events)} events to {out}")
PY
