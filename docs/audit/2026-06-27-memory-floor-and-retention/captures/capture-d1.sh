#!/bin/bash
# =============================================================================
# D1 — MallocStackLogging memory capture for Maccy (06-27 memory-floor audit).
# Run on a Mac (needs Xcode CLT: leaks/heap/vmmap/malloc_history/footprint).
#
# Resolves the TWO fork points blocking the memory plan:
#   (1) Is the 41.7 MB `non-object` blind spot AttributeGraph (app-slimmable via
#       U1-style view-tree work) or CoreText/CoreSVG/framework cache (NOT
#       app-reclaimable)?                            → Group B malloc_history
#   (2) Are the 17.5 MB SwiftData content blobs reclaimable at all, or pinned
#       by mainContext's _KKMDBackingData (→ F1 separate blob store MANDATORY)?
#                                                    → Group E scroll experiment
# Plus the true floor (A), per-item cost (B), window-closed rebound (D).
#
# Usage:  bash capture-d1.sh [/path/to/Maccy.app/Contents/MacOS/Maccy]
# Output: ./d1-<timestamp>/{A,B,Dclosed,E*}.{leaks,heap,vmmap.summary,
#         footprint,malloc_history}.txt  (+ E.scroll-trace.txt)
#
# The exact commit doesn't matter for attribution (U1 is ~0.1 MB); your normal
# installed Maccy is fine. MSL makes the process ~2-3x slower + bigger — that's
# expected, it's a diagnostic build, don't ship it.
# =============================================================================
set -u
APP="${1:-/Applications/Maccy.app/Contents/MacOS/Maccy}"
OUT="./d1-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
echo "App : $APP"
echo "Out : $OUT"
echo

# capture <prefix> <pid> [msl]
capture() {
  local p="$1"; local pid="$2"; local msl="${3:-}"
  leaks "$pid"           > "$OUT/$p.leaks.txt" 2>&1
  heap "$pid"            > "$OUT/$p.heap.txt" 2>&1
  vmmap --summary "$pid" > "$OUT/$p.vmmap.summary.txt" 2>&1
  footprint "$pid"       > "$OUT/$p.footprint.txt" 2>&1
  # NOTE: malloc_history needs a MODE (-callTree/-allBySize/-allByCount/-allEvents),
  # NOT a bare `--eventsByStack` (that prints usage and exits — the 2026-06-27 first
  # run produced a 1.9 KB usage-error file). -callTree aggregates by stack and is the
  # most useful for attributing the non-object blind spot.
  [ "$msl" = "msl" ] && malloc_history "$pid" -callTree > "$OUT/$p.malloc_history.txt" 2>&1
  echo "  captured $p — phys_footprint: $(footprint "$pid" 2>/dev/null | grep -i 'phys_footprint' | head -1)"
}

echo "Launching Maccy FRESH with MallocStackLogging=1 ..."
MallocStackLogging=1 "$APP" &
PID=$!
echo "PID = $PID"
echo "Waiting 30s for the process to settle ..."
sleep 30

echo
echo "=== Group A — just-launched, popup CLOSED (TRUE FLOOR) ==="
echo "  Keep the popup CLOSED (menu bar only). If history is large, that's fine;"
echo "  an EMPTY/near-empty history is ideal for the floor — clear it first if you can."
echo "  Press ENTER when ready."
read -r
capture A "$PID"

echo
echo "=== Group B — popup OPEN, ~20 items visible (PER-ITEM COST + MSL ATTRIBUTION) ==="
echo "  >>> Open the popup, scroll so ~20 rows are visible, wait a couple seconds,"
echo "      then come back here and press ENTER."
read -r
capture B "$PID" msl

echo
echo "=== Group D — popup CLOSED after use (window-closed rebound) ==="
echo "  >>> Close the popup (Esc / click away). Wait ~5s. Press ENTER."
sleep 5
read -r
capture Dclosed "$PID"

echo
echo "=== Group E — scroll experiment (BLOB RECLAIMABILITY — the fork decider) ==="
echo "  >>> Reopen the popup. We will snapshot __DataStorage + non-object as you scroll."
echo "      Scroll SLOWLY top → bottom. After each chunk (~50 rows) come back, press ENTER."
for step in E-top E-50 E-100 E-150 E-bottom; do
  echo "  >>> Scroll to the next chunk, then press ENTER ($step)."
  read -r
  {
    echo "=== $step ==="
    heap "$PID" 2>/dev/null | grep -iE "__DataStorage|non-object|NSImage"
    footprint "$PID" 2>/dev/null | grep -iE "phys_footprint|swapped|compressed"
    echo
  } | tee -a "$OUT/E.scroll-trace.txt"
done
echo
echo "  >>> Now scroll all the way back to the TOP, wait 30s (let any purge settle), press ENTER."
read -r
sleep 30
{
  echo "=== E-rebound (scrolled back to top, waited) ==="
  heap "$PID" 2>/dev/null | grep -iE "__DataStorage|non-object|NSImage"
  footprint "$PID" 2>/dev/null | grep -iE "phys_footprint|swapped|compressed"
} | tee -a "$OUT/E.scroll-trace.txt"

echo
echo "================================================================"
echo "Done. Captures in: $OUT"
echo
echo "What to read (paste these back, or zip the whole dir):"
echo "  A.footprint.txt        → true floor (window closed). Expect ~50-60 MB."
echo "                          If >70 MB → something preloads content; investigate."
echo "  B.malloc_history.txt   → attribute the 41.7 MB non-object: sort by stack,"
echo "                          see if AG (view graph) or CoreText/CoreSVG dominates."
echo "                          AG dominant → U1-style view slimming helps."
echo "                          CoreText/SVG → framework cache, not app-reclaimable."
echo "  E.scroll-trace.txt     → __DataStorage as you scroll:"
echo "                            monotonic growth, no drop on rebound → blobs PINNED"
echo "                              by mainContext → F1 (separate blob store) MANDATORY."
echo "                            drops on scroll-back → windowing reclaims → C5 viable"
echo "                              (modulo its search/UX caveats)."
echo
echo "Drop the dir into docs/audit/2026-06-27-memory-floor-and-retention/captures/"
echo "or paste the key reads. Kill Maccy when done:  kill $PID"
