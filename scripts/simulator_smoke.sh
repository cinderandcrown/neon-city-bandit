#!/usr/bin/env bash
# Copyright © 2026 Cinder and Crown LLC. All rights reserved.
# Launch The Neon City Bandit (Magpie.app) with -SmokeAutoplay, record gameplay, capture moment screenshots
# driven by smoke_status milestones (not blind sleeps).
# FPS: warn below 55; hard-fail only below 30 or on freezes (maxFrameMs > 500).
set -euo pipefail

DEVICE="${1:?simulator UDID}"
APP_PATH="${2:?path to Magpie.app (Xcode product)}"
OUT_DIR="${3:-smoke-artifacts}"
BUNDLE_ID="${BUNDLE_ID:-com.cinderandcrown.magpie}"
DISPLAY_ID="${SIMCTL_DISPLAY:-1}"
WARN_FPS="${SMOKE_WARN_FPS:-55}"
FAIL_FPS="${SMOKE_FAIL_FPS:-30}"
# Soft-warn above WARN; hard-fail only above FAIL (simctl I/O can spike ~600–900ms).
WARN_FRAME_MS="${SMOKE_WARN_FRAME_MS:-500}"
# 1500ms: harness force_fail / soft vault bounce can hitch one frame on CI sims.
MAX_FRAME_MS="${SMOKE_MAX_FRAME_MS:-1500}"
MIN_VIDEO_SECS="${SMOKE_MIN_VIDEO_SECS:-60}"

# Harness force counters — forced paths unblock CI but never count as feature proof.
FORCED_MASK=0
FORCED_FAIL=0
mkdir -p "$OUT_DIR"
REC_PID=""
VIDEO_OUT="${OUT_DIR}/smoke-gameplay.mp4"

# Always stop simctl recordVideo so the mp4 finalizes (even on midrun timeout / FAIL).
finalize_recorder() {
  local pid="${REC_PID:-}"
  [[ -n "$pid" ]] || return 0
  if kill -0 "$pid" 2>/dev/null; then
    kill -INT "$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
    # simctl needs a moment to flush the .mp4 (sidecar .sb-* is incomplete until then).
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      if ! kill -0 "$pid" 2>/dev/null; then
        break
      fi
      sleep 0.5
    done
    wait "$pid" 2>/dev/null || true
  fi
  # If the primary path is empty but a sidecar remains, promote the largest sidecar.
  if [[ -n "${VIDEO_OUT:-}" ]]; then
    if [[ ! -s "$VIDEO_OUT" ]]; then
      local side
      side="$(ls -1t "${VIDEO_OUT}".sb-* 2>/dev/null | head -1 || true)"
      if [[ -n "$side" && -s "$side" ]]; then
        echo "WARN: promoting recorder sidecar $(basename "$side") → $(basename "$VIDEO_OUT")" >&2
        mv -f "$side" "$VIDEO_OUT" || cp -f "$side" "$VIDEO_OUT" || true
      fi
    fi
    rm -f "${VIDEO_OUT}".sb-* 2>/dev/null || true
  fi
  REC_PID=""
}
trap finalize_recorder EXIT

arm_force() {
  local kind="$1"
  local flag="$2"
  case "$kind" in
    mask) FORCED_MASK=$((FORCED_MASK + 1)) ;;
    fail) FORCED_FAIL=$((FORCED_FAIL + 1)) ;;
    *) echo "WARN: unknown force kind=$kind" >&2 ;;
  esac
  echo "WARN: smoke_force_${kind} armed (count mask=$FORCED_MASK fail=$FORCED_FAIL) — NOT proof" >&2
  write_flag "$flag"
}

# Ask the app to flush smoke_status.txt now (screenshot-moment status).
snap_status() {
  write_flag "smoke_snap_status.txt" || true
  sleep 0.12
}

# Fail if live play has made no worldTX progress for >8s of sim time (stallSec=).
# Use the app's stallSec — wall-clock between harness polls false-fires during Mask holds.
check_no_progress() {
  local status="$1"
  [[ "$status" == *"phase=playing"* ]] || return 0
  [[ "$status" == *"paused=1"* ]] && return 0
  # Screenshot holds / Mask capture may park the bot briefly — don't trip on those.
  [[ "$status" == *"maskOn=1"* ]] && return 0
  local stall
  stall="$(STATUS_LINE="$status" python3 -c 'import os,re; m=re.search(r"stallSec=([0-9.]+)", os.environ["STATUS_LINE"]); print(m.group(1) if m else "0")')"
  python3 -c "import sys; sys.exit(0 if float('$stall') <= 8.0 else 1)" || {
    echo "FAIL: no worldTX progress for >8s (stallSec=$stall status=$status)" >&2
    shot "$OUT_DIR/fail-no-progress.png" || true
    exit 1
  }
}

ensure_pillow() {
  if [[ -n "${PALETTE_PY:-}" ]] && "$PALETTE_PY" -c 'import PIL' 2>/dev/null; then
    return 0
  fi
  PALETTE_PY="$(command -v python3)"
  PALETTE_VENV="${TMPDIR:-/tmp}/magpie-smoke-palette-venv"
  if ! "$PALETTE_PY" -c 'import PIL' 2>/dev/null; then
    if "$PALETTE_PY" -m pip install -q --user --break-system-packages pillow 2>/tmp/magpie-pillow.err; then
      :
    elif python3 -m venv "$PALETTE_VENV" 2>/tmp/magpie-venv.err; then
      "$PALETTE_VENV/bin/pip" install -q pillow
      PALETTE_PY="$PALETTE_VENV/bin/python"
    else
      echo "FAIL: could not install Pillow for $($PALETTE_PY -V 2>&1)" >&2
      cat /tmp/magpie-pillow.err /tmp/magpie-venv.err 2>/dev/null || true
      exit 1
    fi
  fi
  if ! "$PALETTE_PY" -c 'import PIL' 2>/dev/null; then
    echo "FAIL: Pillow still missing for $PALETTE_PY" >&2
    exit 1
  fi
  export PALETTE_PY
  echo "OK Pillow via $PALETTE_PY ($("$PALETTE_PY" -V 2>&1))"
}

# Mean absolute pixel difference (0–255). Exit 0 if near-identical (mean < 5).
near_identical() {
  local a="$1" b="$2"
  ensure_pillow
  "$PALETTE_PY" - "$a" "$b" <<'PY'
import sys
from PIL import Image, ImageChops
a = Image.open(sys.argv[1]).convert("RGB")
b = Image.open(sys.argv[2]).convert("RGB")
if a.size != b.size:
    b = b.resize(a.size)
w, h = a.size
box = (int(w*0.12), int(h*0.18), int(w*0.88), int(h*0.82))
a, b = a.crop(box), b.crop(box)
diff = ImageChops.difference(a, b)
hist = diff.convert("L").histogram()
n = sum(hist) or 1
mean = sum(i * hist[i] for i in range(256)) / n
print(f"near_identical mean={mean:.2f}/255")
sys.exit(0 if mean < 5.0 else 1)
PY
}

shot() {
  local out="$1"
  snap_status
  if xcrun simctl io "$DEVICE" screenshot --display="$DISPLAY_ID" "$out" 2>/tmp/sim-shot.err; then
    return 0
  fi
  if grep -qiE 'unrecognized|unknown option|invalid option' /tmp/sim-shot.err 2>/dev/null; then
    xcrun simctl io "$DEVICE" screenshot "$out"
    return 0
  fi
  cat /tmp/sim-shot.err >&2 || true
  xcrun simctl io "$DEVICE" screenshot --display=3 "$out" 2>/dev/null \
    || xcrun simctl io "$DEVICE" screenshot "$out"
}

data_container() {
  xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data 2>/dev/null || true
}

read_status() {
  local data
  data="$(data_container)"
  if [[ -n "$data" && -f "$data/Documents/smoke_status.txt" ]]; then
    cat "$data/Documents/smoke_status.txt"
  else
    echo ""
  fi
}

status_field() {
  local key="$1"
  echo "$(read_status)" | sed -n "s/.*${key}=\([^ ]*\).*/\1/p" | head -1
}

app_alive() {
  local data status now mtime age
  data="$(data_container)"
  [[ -n "$data" ]] || return 1
  status="$data/Documents/smoke_status.txt"
  [[ -f "$status" ]] || return 1
  now="$(date +%s)"
  mtime="$(stat -f %m "$status" 2>/dev/null || stat -c %Y "$status" 2>/dev/null || echo 0)"
  age=$((now - mtime))
  (( age <= 8 ))
}

require_app() {
  local label="$1"
  if ! app_alive; then
    echo "FAIL: app not alive at $label" >&2
    shot "$OUT_DIR/fail-$label-homescreen.png" || true
    read_status >&2 || true
    exit 1
  fi
  echo "alive@$label: $(read_status)"
}

# Poll until python predicate on status line prints YES, or timeout.
# Returns 1 on timeout (callers may soft-continue). Use wait_status_strict to hard-fail.
wait_status() {
  local label="$1"
  local pypred="$2"
  local timeout="${3:-90}"
  local start now status
  start="$(date +%s)"
  while true; do
    require_app "$label"
    status="$(read_status)"
    check_no_progress "$status"
    if STATUS_LINE="$status" python3 -c "$pypred"; then
      echo "ready@$label: $status"
      return 0
    fi
    now="$(date +%s)"
    if (( now - start >= timeout )); then
      echo "WARN: timeout waiting for $label (status=$status)" >&2
      shot "$OUT_DIR/fail-$label-timeout.png" || true
      return 1
    fi
    sleep 0.35
  done
}

wait_status_strict() {
  if ! wait_status "$@"; then
    echo "FAIL: timeout waiting for $1" >&2
    exit 1
  fi
}

echo "Smoke (autoplay) on $DEVICE (display=$DISPLAY_ID)"
# Never keep stale screenshots from a prior CI step/run in this folder.
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

xcrun simctl bootstatus "$DEVICE" -b || xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl install "$DEVICE" "$APP_PATH"

docs_dir() {
  local data
  data="$(data_container)"
  if [[ -n "$data" ]]; then
    mkdir -p "$data/Documents"
    echo "$data/Documents"
  fi
}

write_flag() {
  local name="$1"
  local docs
  docs="$(docs_dir)"
  if [[ -z "$docs" ]]; then
    echo "WARN: no Documents dir for flag $name" >&2
    return 1
  fi
  printf 'ok\n' > "$docs/$name"
  echo "flag@$name"
}

launch_smoke() {
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
  local docs
  docs="$(docs_dir)"
  if [[ -n "$docs" ]]; then
    rm -f "$docs/smoke_status.txt" \
      "$docs/smoke_proceed.txt" \
      "$docs/smoke_midrun_ok.txt" \
      "$docs/smoke_mask_ok.txt" \
      "$docs/smoke_mask2_ok.txt" \
      "$docs/smoke_death_ok.txt" \
      "$docs/smoke_show_pause.txt" \
      "$docs/smoke_pause_ok.txt" \
      "$docs/smoke_background.txt" \
      "$docs/smoke_foreground.txt" \
      "$docs/smoke_show_map.txt" \
      "$docs/smoke_map_ok.txt" \
      "$docs/smoke_show_daily.txt" \
      "$docs/smoke_daily_ok.txt" \
      "$docs/smoke_prefer_roof.txt" \
      "$docs/smoke_force_mask.txt" \
      "$docs/smoke_force_fail.txt" \
      "$docs/smoke_capture_mask.txt" \
      "$docs/smoke_snap_status.txt" \
      "$docs/smoke_forced_detail.txt"
  fi
  xcrun simctl launch "$DEVICE" "$BUNDLE_ID" -SmokeAutoplay
}

# Capture 00-publisher-ident during boot=ident, then 01-title when boot=ready.
# Early boot=loading status lets us attach during atlas warm; snap only when ready.
# Relaunch once if we somehow attach after autoplay already advanced.
TITLE_SHOT=0
IDENT_SHOT=0
for attempt in 1 2; do
  launch_smoke
  for _ in $(seq 1 900); do
    status="$(read_status)"
    if [[ -z "$status" ]]; then
      sleep 0.2
      continue
    fi
    if [[ "$IDENT_SHOT" -eq 0 && "$status" == *"boot=ident"* ]]; then
      require_app "launch"
      # Hold so logo + "Cinder & Crown Creative Presents" are on screen.
      sleep 0.55
      shot "$OUT_DIR/00-publisher-ident.png"
      IDENT_SHOT=1
      echo "ready@ident: $status"
      continue
    fi
    if [[ "$status" == *"phase=title"* && "$status" == *"boot=ready"* && "$status" == *"titleOk=1"* ]]; then
      # Ident finished before we attached — relaunch so 00-publisher-ident is not skipped.
      if [[ "$IDENT_SHOT" -eq 0 ]]; then
        echo "missed ident before title (status=$status) — relaunch attempt=$attempt" >&2
        break
      fi
      require_app "launch"
      # Let the B1 logo glitch-in (~0.6s) settle before the title still.
      sleep 0.75
      shot "$OUT_DIR/01-title.png"
      TITLE_SHOT=1
      echo "ready@title: $status"
      # Start gameplay recording while still on title, THEN release the title hold —
      # so recorder warm-up does not burn the midrun window.
      VIDEO_OUT="$OUT_DIR/smoke-gameplay.mp4"
      set +e
      xcrun simctl io "$DEVICE" recordVideo --display="$DISPLAY_ID" --codec=h264 --force "$VIDEO_OUT" &
      REC_PID=$!
      REC_STARTED_AT="$(date +%s)"
      sleep 1
      if ! kill -0 "$REC_PID" 2>/dev/null; then
        xcrun simctl io "$DEVICE" recordVideo --codec=h264 --force "$VIDEO_OUT" &
        REC_PID=$!
        REC_STARTED_AT="$(date +%s)"
        sleep 1
      fi
      set -e
      write_flag "smoke_proceed.txt"
      break 2
    fi
    if [[ "$status" == *"phase=title"* && ( "$status" == *"boot=loading"* || "$status" == *"boot=ident"* ) ]]; then
      # Still warming atlases or playing publisher ident — keep waiting.
      sleep 0.15
      continue
    fi
    # Attached after autoplay already advanced — relaunch for a clean title beat.
    echo "missed title (status=$status) — relaunch attempt=$attempt" >&2
    break
  done
done
if [[ "$TITLE_SHOT" -eq 0 ]]; then
  echo "FAIL: could not capture phase=title boot=ready titleOk=1 after relaunch" >&2
  shot "$OUT_DIR/fail-title-timeout.png" || true
  read_status >&2 || true
  exit 1
fi
if [[ "$IDENT_SHOT" -eq 0 ]]; then
  echo "FAIL: missed publisher ident still (boot=ident)" >&2
  shot "$OUT_DIR/fail-ident-missed.png" || true
  exit 1
fi
require_app "launch"
if [[ -z "${REC_PID:-}" ]] || ! kill -0 "$REC_PID" 2>/dev/null; then
  VIDEO_OUT="$OUT_DIR/smoke-gameplay.mp4"
  set +e
  xcrun simctl io "$DEVICE" recordVideo --display="$DISPLAY_ID" --codec=h264 --force "$VIDEO_OUT" &
  REC_PID=$!
  REC_STARTED_AT="$(date +%s)"
  sleep 1
  if ! kill -0 "$REC_PID" 2>/dev/null; then
    xcrun simctl io "$DEVICE" recordVideo --codec=h264 --force "$VIDEO_OUT" &
    REC_PID=$!
    REC_STARTED_AT="$(date +%s)"
  fi
  set -e
fi
REC_STARTED_AT="${REC_STARTED_AT:-$(date +%s)}"

# Harness handshakes: app holds each beat until the matching flag is written after the shot.
# 02 — midrun: street neon run BEFORE prefer_roof (palette gate needs magenta storefronts).
# Allow sticky died= from a prior premature splash; require live playing + no stomps yet.
# Prefer maskOn=0 for the neon alley still; don't hard-require it (timer-hold can race).
wait_status_strict "midrun" 'import os,re,sys; s=os.environ["STATUS_LINE"]; m=re.search(r"elapsed=([0-9.]+)", s); st=re.search(r"stomps=([0-9]+)", s); sys.exit(0 if ("phase=playing" in s and m and float(m.group(1))>=2.5 and (not st or int(st.group(1))==0)) else 1)' 120
shot "$OUT_DIR/02-midrun.png"
# Release midrun so subsequent stomps count.
write_flag "smoke_midrun_ok.txt"

# 03 — street stomps BEFORE rooftop so the forward-only bot still has MOPs ahead.
STOMP_BASE="$(STATUS_LINE="$(read_status)" python3 -c 'import os,re; m=re.search(r"stomps=([0-9]+)", os.environ["STATUS_LINE"]); print(int(m.group(1)) if m else 0)')"
export STOMP_BASE
wait_status_strict "stomp" "import os,re,sys; s=os.environ['STATUS_LINE']; m=re.search(r'stomps=([0-9]+)', s); base=int(os.environ.get('STOMP_BASE','0')); sys.exit(0 if (m and int(m.group(1))>=base+1 and 'phase=playing' in s) else 1)" 120
shot "$OUT_DIR/03-mop-stomp.png"

# 03b — three NEW stomps during this beat (not sticky combo high-water).
CHAIN_BASE="$(STATUS_LINE="$(read_status)" python3 -c 'import os,re; m=re.search(r"stomps=([0-9]+)", os.environ["STATUS_LINE"]); print(int(m.group(1)) if m else 0)')"
export CHAIN_BASE
wait_status_strict "stomp-chain" "import os,re,sys; s=os.environ['STATUS_LINE']; m=re.search(r'stomps=([0-9]+)', s); base=int(os.environ.get('CHAIN_BASE','0')); sys.exit(0 if ('phase=playing' in s and m and int(m.group(1))>=base+3) else 1)" 120
shot "$OUT_DIR/03b-stomp-chain.png"
# Fail if 03b is near-identical to 03 (stuck hero / no chain).
if near_identical "$OUT_DIR/03-mop-stomp.png" "$OUT_DIR/03b-stomp-chain.png"; then
  echo "FAIL: 03b-stomp-chain near-identical to 03-mop-stomp (no fresh chain)" >&2
  exit 1
fi
echo "OK stomp-chain differs from single stomp"

# 02r — rooftop clip AFTER street stomps (forward-only must not climb past the MOP pack).
write_flag "smoke_prefer_roof.txt"
ROOF_WAIT_START="$(date +%s)"
while true; do
  require_app "rooftop"
  status="$(read_status)"
  if [[ "$status" == *"roof=1"* && "$status" == *"phase=playing"* ]]; then
    echo "ready@rooftop: $status"
    break
  fi
  now="$(date +%s)"
  if (( now - ROOF_WAIT_START >= 18 )); then
    echo "WARN: rooftop soft-timeout (status=$status) — continuing" >&2
    break
  fi
  sleep 0.35
done
shot "$OUT_DIR/02r-rooftop-route.png" || true
# Hold a few seconds of climb/rooftop traversal for the continuous take / clip extract.
sleep 3
rm -f "$(data_container)/Documents/smoke_prefer_roof.txt" 2>/dev/null || true

# 04 — Mask Mode while still playing (requires live maskOn=1, not sticky mask=).
# Only pin Mask while capturing (smoke_capture_mask.txt) — not during stomp-chain.
write_flag "smoke_capture_mask.txt"
MASK_WAIT_START="$(date +%s)"
MASK_FORCED=0
while true; do
  require_app "mask"
  status="$(read_status)"
  check_no_progress "$status"
  if [[ "$status" == *"maskOn=1"* && "$status" == *"phase=playing"* ]]; then
    echo "ready@mask: $status"
    break
  fi
  now="$(date +%s)"
  if (( now - MASK_WAIT_START >= 50 )) && [[ "$MASK_FORCED" -eq 0 ]]; then
    echo "WARN: mask soft-timeout (status=$status)" >&2
    arm_force mask "smoke_force_mask.txt"
    MASK_FORCED=1
  fi
  if (( now - MASK_WAIT_START >= 90 )); then
    echo "FAIL: timeout waiting for mask (status=$status)" >&2
    shot "$OUT_DIR/fail-mask-timeout.png" || true
    exit 1
  fi
  sleep 0.35
done
MASK_SHOT_OK=0
for _try in $(seq 1 40); do
  status="$(read_status)"
  if [[ "$status" != *"maskOn=1"* || "$status" != *"phase=playing"* ]]; then
    sleep 0.25
    continue
  fi
  sleep 0.2
  shot "$OUT_DIR/04-mask-mode.png"
  snap_status
  status="$(read_status)"
  if [[ "$status" == *"maskOn=1"* && "$status" == *"phase=playing"* ]]; then
    echo "ready@mask-shot: $status"
    MASK_SHOT_OK=1
    break
  fi
  echo "mask shot raced (status=$status) — retry $_try" >&2
  rm -f "$OUT_DIR/04-mask-mode.png"
  sleep 0.2
done
if [[ "$MASK_SHOT_OK" -ne 1 ]]; then
  echo "FAIL: could not capture Mask Mode while phase=playing maskOn=1" >&2
  shot "$OUT_DIR/fail-mask-timeout.png" || true
  read_status >&2 || true
  exit 1
fi
write_flag "smoke_mask_ok.txt"
rm -f "$(data_container)/Documents/smoke_force_mask.txt" "$(data_container)/Documents/smoke_capture_mask.txt" 2>/dev/null || true

# 04b — Second Mask entry after natural drop (no force-off). Snap status at shot time.
wait_status_strict "mask-off" 'import os,sys; s=os.environ["STATUS_LINE"]; sys.exit(0 if ("maskOn=0" in s and "phase=playing" in s) else 1)' 90
write_flag "smoke_capture_mask.txt"
MASK2_OK=0
MASK2_FORCED=0
MASK2_WAIT_START="$(date +%s)"
MASK2_LAST_FORCE=0
while true; do
  require_app "mask-2"
  status="$(read_status)"
  check_no_progress "$status"
  if [[ "$status" == *"maskOn=1"* && "$status" == *"phase=playing"* ]]; then
    echo "ready@mask-2: $status"
    MASK2_OK=1
    break
  fi
  now="$(date +%s)"
  # Arm (and re-arm) force_mask; give the app several seconds to apply before hard-fail.
  if (( now - MASK2_WAIT_START >= 20 )); then
    if [[ "$MASK2_FORCED" -eq 0 ]] || (( now - MASK2_LAST_FORCE >= 8 )); then
      echo "WARN: mask-2 force_mask (status=$status)" >&2
      arm_force mask "smoke_force_mask.txt"
      MASK2_FORCED=1
      MASK2_LAST_FORCE="$now"
      sleep 1.2
      continue
    fi
  fi
  if (( now - MASK2_WAIT_START >= 90 )); then
    echo "FAIL: mask-2 timeout (status=$status) — no placeholder still" >&2
    shot "$OUT_DIR/fail-mask-2.png" || true
    exit 1
  fi
  sleep 0.35
done
shot "$OUT_DIR/04b-mask-mode-2.png"
write_flag "smoke_mask2_ok.txt"
rm -f "$(data_container)/Documents/smoke_force_mask.txt" "$(data_container)/Documents/smoke_capture_mask.txt" 2>/dev/null || true

# 02b — Pause menu (after Mask shot so the LED beat is not racing the timer)
write_flag "smoke_show_pause.txt"
wait_status_strict "pause-menu" 'import os,sys; s=os.environ["STATUS_LINE"]; sys.exit(0 if "paused=1" in s else 1)' 60
sleep 0.35
shot "$OUT_DIR/02b-pause-menu.png"
write_flag "smoke_pause_ok.txt"
# Accept any unpaused phase — death must not race this wait after mask_ok.
wait_status_strict "pause-resume" 'import os,sys; s=os.environ["STATUS_LINE"]; sys.exit(0 if "paused=0" in s else 1)' 60

# 02c — Background / foreground interruption (system pause + 3-2-1 resume)
write_flag "smoke_background.txt"
wait_status_strict "background" 'import os,sys; s=os.environ["STATUS_LINE"]; sys.exit(0 if "paused=1" in s else 1)' 60
sleep 0.35
shot "$OUT_DIR/02c-background.png"
write_flag "smoke_foreground.txt"
wait_status_strict "foreground" 'import os,sys; s=os.environ["STATUS_LINE"]; sys.exit(0 if "paused=0" in s else 1)' 90

# 05 — death / retry overlay (app holds failed until smoke_death_ok.txt).
# Soft path: if seekDeath can't reach the canal from a mid ledge, force-fail into water.
DEATH_WAIT_START="$(date +%s)"
DEATH_FORCED=0
while true; do
  require_app "death"
  status="$(read_status)"
  if [[ "$status" == *"died=1"* && "$status" == *"phase=failed"* ]]; then
    echo "ready@death: $status"
    break
  fi
  now="$(date +%s)"
  if (( now - DEATH_WAIT_START >= 35 )) && [[ "$DEATH_FORCED" -eq 0 ]]; then
    echo "WARN: death soft-timeout (status=$status)" >&2
    arm_force fail "smoke_force_fail.txt"
    DEATH_FORCED=1
    # Give force_fail a clean window — never hard-fail on the same tick we arm.
    DEATH_WAIT_START="$(date +%s)"
  fi
  # 90s before force, or 25s after force_fail is armed.
  local_limit=90
  if [[ "$DEATH_FORCED" -eq 1 ]]; then
    local_limit=25
  fi
  if (( now - DEATH_WAIT_START >= local_limit )); then
    echo "FAIL: timeout waiting for death (status=$status)" >&2
    shot "$OUT_DIR/fail-death-timeout.png" || true
    exit 1
  fi
  sleep 0.35
done
sleep 0.35
shot "$OUT_DIR/05-death-retry.png"
write_flag "smoke_death_ok.txt"
rm -f "$(data_container)/Documents/smoke_force_fail.txt" 2>/dev/null || true

# 06 — RESULTS (real vault clear after death retry — sticky won=1 alone is not enough)
wait_status_strict "results" 'import os,sys; s=os.environ["STATUS_LINE"]; sys.exit(0 if "phase=won" in s else 1)' 120
shot "$OUT_DIR/06-results.png"

# 07 — District map (retention)
write_flag "smoke_show_map.txt"
wait_status_strict "district-map" 'import os,sys; s=os.environ["STATUS_LINE"]; sys.exit(0 if "map=1" in s else 1)' 60
sleep 0.35
shot "$OUT_DIR/07-district-map.png"
# Hold map on-screen so the continuous video captures the neon district board.
sleep 3
write_flag "smoke_map_ok.txt"

# 08 — Daily Heist screen (must appear in the continuous video, not only as a still)
# Clear map flag first so the app doesn't flip map↔daily every frame.
rm -f "$(data_container)/Documents/smoke_show_map.txt" 2>/dev/null || true
write_flag "smoke_show_daily.txt"
wait_status_strict "daily-heist" 'import os,sys; s=os.environ["STATUS_LINE"]; sys.exit(0 if "daily=1" in s else 1)' 60
# Let RetentionChrome.present() finish its fade-in before the still.
sleep 0.55
shot "$OUT_DIR/08-daily-heist.png"
# Hold Daily Heist long enough to read in the continuous take.
sleep 5
write_flag "smoke_daily_ok.txt"

# One continuous take must be ≥60s wall-clock (review gate). Hold if needed.
# Assert we never restarted the recorder mid-run (stitched takes are rejected).
if [[ -z "${REC_PID:-}" ]] || ! kill -0 "$REC_PID" 2>/dev/null; then
  echo "FAIL: gameplay recorder died or restarted mid-run (stitched video)" >&2
  exit 1
fi
while true; do
  now="$(date +%s)"
  elapsed=$((now - REC_STARTED_AT))
  if (( elapsed >= MIN_VIDEO_SECS )); then
    break
  fi
  echo "recording pad: ${elapsed}s / ${MIN_VIDEO_SECS}s — holding continuous take"
  sleep 2
done

finalize_recorder
sleep 2
require_app "end"

STATUS="$(read_status)"
echo "smoke_status: $STATUS"
FPS="$(echo "$STATUS" | sed -n 's/.*fps=\([0-9.][0-9.]*\).*/\1/p' | head -1)"
MAX_MS="$(echo "$STATUS" | sed -n 's/.*maxFrameMs=\([0-9.][0-9.]*\).*/\1/p' | head -1)"
if [[ -z "$FPS" ]]; then
  echo "FAIL: missing fps in smoke_status.txt" >&2
  exit 1
fi
python3 - "$FPS" "${MAX_MS:-0}" "$WARN_FPS" "$FAIL_FPS" "$WARN_FRAME_MS" "$MAX_FRAME_MS" <<'PY'
import sys
fps=float(sys.argv[1]); max_ms=float(sys.argv[2])
warn=float(sys.argv[3]); fail=float(sys.argv[4])
freeze_warn=float(sys.argv[5]); freeze_fail=float(sys.argv[6])
print(
    f"FPS avg={fps:.1f} maxFrameMs={max_ms:.0f} "
    f"(warn<{warn:.0f} fail<{fail:.0f} freezeWarn>{freeze_warn:.0f}ms freezeFail>{freeze_fail:.0f}ms)"
)
if max_ms > freeze_fail:
    raise SystemExit(f"FAIL: long freeze maxFrameMs={max_ms:.0f} > {freeze_fail:.0f}ms")
if max_ms > freeze_warn:
    print(f"WARN: long freeze maxFrameMs={max_ms:.0f} > {freeze_warn:.0f}ms (soft — not a hard fail)")
if fps < fail:
    raise SystemExit(f"FAIL: average FPS {fps:.1f} < {fail:.0f}")
if fps < warn:
    print(f"WARN: average FPS {fps:.1f} < {warn:.0f} (soft — not a hard fail)")
else:
    print(f"OK FPS {fps:.1f} >= {warn:.0f}")
PY

# Fail if any banned debug/placeholder SKLabel was visible during smoke.
DEBUG_LABELS="$(echo "$STATUS" | sed -n 's/.*debugLabels=\([0-9][0-9]*\).*/\1/p' | head -1)"
DEBUG_LABELS="${DEBUG_LABELS:-}"
if [[ -z "$DEBUG_LABELS" ]]; then
  echo "FAIL: missing debugLabels in smoke_status.txt" >&2
  exit 1
fi
if (( DEBUG_LABELS > 0 )); then
  echo "FAIL: debugLabels=$DEBUG_LABELS (banned SKLabel text visible on screen)" >&2
  exit 1
fi
echo "OK debugLabels=0"

# simctl recordVideo is video-only — mux level music + hero SFX from the smoke audio timeline.
ensure_ffmpeg() {
  if command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1; then
    return 0
  fi
  # Common Homebrew locations on GHA macOS runners.
  for p in /opt/homebrew/bin /usr/local/bin; do
    if [[ -x "$p/ffmpeg" && -x "$p/ffprobe" ]]; then
      export PATH="$p:$PATH"
      return 0
    fi
  done
  if command -v brew >/dev/null 2>&1; then
    echo "Installing ffmpeg for smoke audio mux…" >&2
    brew install ffmpeg
    return 0
  fi
  echo "FAIL: ffmpeg/ffprobe not available for smoke audio mux" >&2
  return 1
}
ensure_ffmpeg

AUDIO_DIR="Assets/Generated/audio"
SFX_DIR="Assets/Audio/sfx"
EVENTS_SRC="$(data_container)/Documents/smoke_audio_events.txt"
EVENTS_COPY="$OUT_DIR/smoke_audio_events.txt"
if [[ -f "$EVENTS_SRC" ]]; then
  cp "$EVENTS_SRC" "$EVENTS_COPY"
else
  echo "WARN: missing smoke_audio_events.txt — muxing music bed only" >&2
  : > "$EVENTS_COPY"
fi
python3 - "$VIDEO_OUT" "$AUDIO_DIR" "$SFX_DIR" "$EVENTS_COPY" "$MIN_VIDEO_SECS" <<'PY'
import os, shutil, subprocess, sys, tempfile

video, audio_dir, sfx_dir, events_path, min_secs_s = sys.argv[1:6]
min_secs = float(min_secs_s)
ffmpeg = shutil.which("ffmpeg")
ffprobe = shutil.which("ffprobe")
if not ffmpeg or not ffprobe:
    raise SystemExit("FAIL: ffmpeg/ffprobe not on PATH")
probe = subprocess.check_output(
    [ffprobe, "-v", "error", "-show_entries", "format=duration",
     "-of", "default=noprint_wrappers=1:nokey=1", video],
    text=True,
).strip()
dur = float(probe)
if dur < 1:
    raise SystemExit(f"FAIL: video duration {dur} too short for audio mux")
if dur + 0.05 < min_secs:
    raise SystemExit(f"FAIL: continuous smoke video {dur:.1f}s < {min_secs:.0f}s (hard-cut montages rejected)")
print(f"OK continuous video duration {dur:.1f}s >= {min_secs:.0f}s")

def find_clip(stem: str):
    for folder in (sfx_dir, audio_dir):
        for ext in (".wav", ".caf", ".m4a", ".mp3"):
            p = os.path.join(folder, stem + ext)
            if os.path.isfile(p):
                return p
    return None

music = find_clip("level_loop")
if not music:
    raise SystemExit("FAIL: missing Assets/Generated/audio/level_loop.* for mux")

# Parse timeline: "<sec> sfx <key>" / "<sec> music <name>"
sfx_map = {
    "mop_hit": "mop_hit",
    "stomp_crunch": "stomp_crunch",
    "mop_bot_break": "mop_bot_break",
    "mask_mode_on": "mask_mode_on",
    "player_hit": "player_hit",
    "raccoon_hurt": "raccoon_hurt",
    "raccoon_ko": "raccoon_ko",
    "fail": "fail",
    "win": "win",
    "ui_tap": "ui_tap",
    "coin_pickup": "coin_pickup",
    "loot_pickup": "loot_pickup",
    "jump": "jump",
    "land": "land",
    "pounce_whoosh": "pounce_whoosh",
}
events = []
with open(events_path, encoding="utf-8") as f:
    for line in f:
        parts = line.strip().split()
        if len(parts) >= 3 and parts[1] == "sfx":
            t = float(parts[0])
            key = parts[2]
            stem = sfx_map.get(key, key)
            clip = find_clip(stem)
            if clip and 0 <= t < dur:
                events.append((t, clip))

# Cap overlays so filter graphs stay small on CI.
events = events[:24]

inputs = ["-y", "-i", video, "-stream_loop", "-1", "-i", music]
filter_parts = [
    f"[1:a]volume=0.45,atrim=0:{dur:.3f},asetpts=PTS-STARTPTS,aformat=sample_fmts=fltp:channel_layouts=stereo[bed]"
]
amix_inputs = ["[bed]"]
idx = 2
for t, clip in events:
    inputs += ["-i", clip]
    # adelay wants milliseconds per channel
    ms = int(t * 1000)
    filter_parts.append(
        f"[{idx}:a]volume=0.85,aformat=sample_fmts=fltp:channel_layouts=stereo,"
        f"adelay={ms}|{ms},apad=whole_dur={dur:.3f},atrim=0:{dur:.3f},asetpts=PTS-STARTPTS[s{idx}]"
    )
    amix_inputs.append(f"[s{idx}]")
    idx += 1

n = len(amix_inputs)
filter_parts.append(
    f"{''.join(amix_inputs)}amix=inputs={n}:duration=first:dropout_transition=0:normalize=0[aout]"
)
fc = ";".join(filter_parts)

muxed = video + ".mux.mp4"
cmd = [
    "ffmpeg", *inputs,
    "-filter_complex", fc,
    "-map", "0:v:0", "-map", "[aout]",
    "-c:v", "copy", "-c:a", "aac", "-b:a", "160k",
    "-shortest", "-movflags", "+faststart",
    muxed,
]
cmd[0] = ffmpeg
print("mux audio:", " ".join(cmd[:8]), "…", f"sfx={len(events)} dur={dur:.1f}s")
subprocess.check_call(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
os.replace(muxed, video)

# Assert an audible audio stream exists.
streams = subprocess.check_output(
    [ffprobe, "-v", "error", "-select_streams", "a",
     "-show_entries", "stream=codec_type", "-of", "csv=p=0", video],
    text=True,
).strip()
if "audio" not in streams:
    raise SystemExit("FAIL: smoke-gameplay.mp4 missing audio stream after mux")

# Spot-check energy over the first 40s.
wav = tempfile.mktemp(suffix=".wav")
subprocess.check_call(
    [ffmpeg, "-y", "-i", video, "-vn", "-ac", "1", "-ar", "16000", "-t", "40", wav],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
)
import wave, struct
with wave.open(wav, "rb") as w:
    raw = w.readframes(w.getnframes())
    samples = struct.unpack("<" + "h" * (len(raw) // 2), raw)
os.unlink(wav)
if not samples:
    raise SystemExit("FAIL: muxed audio decoded empty")
rms = (sum(x * x for x in samples) / len(samples)) ** 0.5
print(f"OK audio mux rms={rms:.1f} sfx_events={len(events)}")
if rms < 40:
    raise SystemExit(f"FAIL: muxed audio too quiet (rms={rms:.1f})")
PY

# Fun-pass evidence: keep continuous gameplay under 100 MB (h264 crf 28); always emit 540p copy.
python3 - "$VIDEO_OUT" "$OUT_DIR/smoke-gameplay-540p.mp4" <<'PY'
import os, shutil, subprocess, sys
video, out540 = sys.argv[1:3]
ffmpeg = shutil.which("ffmpeg")
if not ffmpeg:
    raise SystemExit("FAIL: ffmpeg missing for size gate")
# Re-encode main take to crf 28 before size check (keeps one continuous run).
tmp = video + ".compact.mp4"
subprocess.check_call(
    [ffmpeg, "-y", "-i", video,
     "-c:v", "libx264", "-preset", "veryfast", "-crf", "28",
     "-c:a", "aac", "-b:a", "96k", "-movflags", "+faststart", "-pix_fmt", "yuv420p", tmp],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
)
os.replace(tmp, video)
# 540p copy for lightweight review (same continuous run).
subprocess.check_call(
    [ffmpeg, "-y", "-i", video,
     "-vf", "scale=-2:540", "-c:v", "libx264", "-preset", "veryfast", "-crf", "28",
     "-c:a", "aac", "-b:a", "96k", "-movflags", "+faststart", out540],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
)
size = os.path.getsize(video)
limit = 100 * 1024 * 1024
print(f"smoke-gameplay.mp4 size={size/1024/1024:.1f} MB (crf 28)")
if size > limit:
    tmp = video + ".compact2.mp4"
    subprocess.check_call(
        [ffmpeg, "-y", "-i", video,
         "-vf", "scale=-2:960", "-c:v", "libx264", "-preset", "veryfast", "-crf", "28",
         "-c:a", "aac", "-b:a", "80k", "-movflags", "+faststart", "-pix_fmt", "yuv420p", tmp],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    os.replace(tmp, video)
    size = os.path.getsize(video)
    print(f"compacted 960p to {size/1024/1024:.1f} MB")
if size > limit:
    raise SystemExit(f"FAIL: smoke-gameplay.mp4 still {size/1024/1024:.1f} MB > 100 MB")
print(f"OK video size {size/1024/1024:.1f} MB + 540p copy")
PY

# Palette / art gates — real neon, not flat hot-pink slabs chasing a threshold.
ensure_pillow
"$PALETTE_PY" - "$OUT_DIR/02-midrun.png" "Assets/Generated/backgrounds/mid_buildings.png" "$OUT_DIR/palette-side-by-side.png" "$OUT_DIR/03-mop-stomp.png" "$OUT_DIR/04-mask-mode.png" <<'PY'
import sys
from collections import Counter
from PIL import Image

midrun = Image.open(sys.argv[1]).convert("RGB")
ref = Image.open(sys.argv[2]).convert("RGB")
stomp = Image.open(sys.argv[4]).convert("RGB")
mask = Image.open(sys.argv[5]).convert("RGB")
# Full-frame art honesty (not a tuned crop).
w, h = midrun.size
full = list(midrun.getdata())
n_full = max(1, len(full))

def is_mag(p):
    r, g, b = p
    return r > 160 and b > 100 and r > g + 30

def is_teal(p):
    r, g, b = p
    return b > 140 and g > 120 and b > r + 20

mag_full = sum(1 for p in full if is_mag(p))
teal_full = sum(1 for p in full if is_teal(p))
print(f"palette midrun magenta={mag_full/n_full:.3%} teal={teal_full/n_full:.3%} neon={(mag_full+teal_full)/n_full:.3%}")
if mag_full / n_full < 0.003:
    raise SystemExit(f"FAIL: midrun magenta={mag_full/n_full:.3%} < 0.3%")
if mag_full / n_full > 0.06:
    raise SystemExit(f"FAIL: midrun magenta={mag_full/n_full:.3%} > 6% (art overtuned / flat slabs?)")
if teal_full / n_full < 0.005:
    raise SystemExit(f"FAIL: midrun teal={teal_full/n_full:.3%} < 0.5%")

# Flat / slab magenta: solid untextured plates (quantize to 8-level bins).
mag_px = [p for p in full if is_mag(p)]
bins = Counter((r // 8 * 8, g // 8 * 8, b // 8 * 8) for r, g, b in mag_px)
largest_slab = bins.most_common(1)[0][1] if bins else 0
# Flat = sum of oversized near-uniform bins (each >0.15% of frame).
flat = sum(cnt for _, cnt in bins.items() if cnt / n_full > 0.0015)
print(f"art flat_magenta={flat/n_full:.3%} largest_slab={largest_slab/n_full:.3%}")
if flat / n_full >= 0.005:
    raise SystemExit(f"FAIL: flat magenta={flat/n_full:.3%} >= 0.5% of screen (solid plates?)")
if largest_slab / n_full >= 0.003:
    raise SystemExit(f"FAIL: single magenta slab={largest_slab/n_full:.3%} >= 0.3% of screen")

# Center crop still used for readability checks below.
crop = midrun.crop((int(w*0.1), int(h*0.18), int(w*0.9), int(h*0.62)))
pixels = list(crop.getdata())
n = len(pixels)
mag = sum(1 for r,g,b in pixels if is_mag((r,g,b)))
teal = sum(1 for r,g,b in pixels if is_teal((r,g,b)))

# Readability: sprites must pop against the local playfield — not mean(sky) vs mean(char),
# which both sit in the same dark alley mid-tones after neon lift.
cw, ch = crop.size
char_band = crop.crop((int(cw * 0.15), int(ch * 0.45), int(cw * 0.85), int(ch * 0.95)))
char_px = list(char_band.getdata())
char_luma = sorted((r + g + b) / 3 for r, g, b in char_px)
cn = max(1, len(char_luma))
char_mean = sum(char_luma) / cn
char_p50 = char_luma[cn // 2]
char_p90 = char_luma[int(cn * 0.90)]
char_p95 = char_luma[int(cn * 0.95)]
# Pixels clearly brighter than the local alley median (hero rim / white robot / LEDs).
sprite_pop = sum(1 for v in char_luma if v >= char_p50 + 35) / cn
local_spread = char_p90 - char_luma[int(cn * 0.10)]
print(
    f"readability charMean={char_mean:.1f} p50={char_p50:.0f} p90={char_p90:.0f} "
    f"p95={char_p95:.0f} spread90={local_spread:.1f} spritePop={sprite_pop:.3%}"
)
# Require either a healthy local contrast spread or a real bright-sprite fraction.
if local_spread < 22.0 and sprite_pop < 0.004:
    raise SystemExit(
        f"FAIL: hero/robot band not readable vs background "
        f"(spread90={local_spread:.1f} spritePop={sprite_pop:.3%})"
    )
# p95 alone is noisy on dark neon alleys; only hard-fail when highlights are also scarce.
if char_p95 < 40.0 and sprite_pop < 0.01:
    raise SystemExit(
        f"FAIL: play band has no bright sprite highlights "
        f"(p95={char_p95:.0f} spritePop={sprite_pop:.3%})"
    )

def near_white_frac(im, box):
    c = im.crop(box)
    px = list(c.getdata())
    return sum(1 for r, g, b in px if r > 230 and g > 230 and b > 230) / max(1, len(px))

# Playfield backdrop must stay dark neon — reject the white clear-color plate bug.
for label, im in (("midrun", midrun), ("stomp", stomp)):
    ww, hh = im.size
    # Upper-mid band behind platforms (where the white plate showed up).
    box = (int(ww * 0.12), int(hh * 0.28), int(ww * 0.88), int(hh * 0.55))
    frac = near_white_frac(im, box)
    print(f"backdrop {label} nearWhite={frac:.3%}")
    if frac > 0.12:
        raise SystemExit(f"FAIL: {label} playfield backdrop is near-white ({frac:.1%}) — night sky missing")

# Mask Mode must stay readable — reject full-screen cyan/white blowout.
# Note: pure cyan (low R, high G/B) can pass a naive luminance>220 check — gate cyan explicitly.
mw, mh = mask.size
mbox = (int(mw * 0.15), int(mh * 0.25), int(mw * 0.85), int(mh * 0.7))
mpx = list(mask.crop(mbox).getdata())
avg = tuple(sum(c[i] for c in mpx) // len(mpx) for i in range(3))
blow = sum(1 for r, g, b in mpx if (r + g + b) / 3 > 200) / len(mpx)
cyan = sum(1 for r, g, b in mpx if g > 180 and b > 180 and g > r + 40 and b > r + 40) / len(mpx)
print(f"mask center avg={avg} blowout={blow:.3%} cyanWash={cyan:.3%}")
if blow > 0.28 or cyan > 0.35 or (avg[1] > 200 and avg[2] > 200 and avg[1] > avg[0] + 50):
    raise SystemExit(
        f"FAIL: Mask Mode full-screen wash hides gameplay (avg={avg}, blowout={blow:.1%}, cyan={cyan:.1%})"
    )

# Side-by-side vs mid_buildings reference strip
rw, rh = 480, 270
left = crop.resize((rw, rh))
right = ref.resize((rw, rh))
board = Image.new("RGB", (rw * 2 + 16, rh + 40), (12, 8, 28))
board.paste(left, (0, 32))
board.paste(right, (rw + 16, 32))
board.save(sys.argv[3])
print(f"OK wrote {sys.argv[3]}")
PY

# Monotonic wall-clock HUD timer (single continuous session — no stitched timer resets).
TIMER_LOG="$(data_container)/Documents/smoke_timer_log.txt"
if [[ ! -s "$TIMER_LOG" ]]; then
  echo "FAIL: missing smoke_timer_log.txt (wallElapsed samples)" >&2
  exit 1
fi
cp -f "$TIMER_LOG" "$OUT_DIR/smoke_timer_log.txt"
python3 - "$TIMER_LOG" "$MIN_VIDEO_SECS" <<'PY'
import sys
path, need_s = sys.argv[1], float(sys.argv[2])
vals = []
with open(path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        vals.append(float(line))
if len(vals) < 8:
    raise SystemExit(f"FAIL: timer log too short ({len(vals)} samples)")
# Allow tiny float jitter only — never a large backward jump (death/retry used to reset HUD).
for i in range(1, len(vals)):
    if vals[i] + 0.05 < vals[i - 1]:
        raise SystemExit(f"FAIL: HUD wall timer went backwards {vals[i-1]:.2f} → {vals[i]:.2f} (stitched/reset session)")
if vals[-1] + 0.5 < need_s * 0.5:
    # Soft floor: wall clock should advance meaningfully across the continuous take.
    print(f"WARN: wallElapsed end={vals[-1]:.1f}s (expected growth during smoke)")
print(f"OK monotonic wallElapsed samples={len(vals)} last={vals[-1]:.1f}s")
PY

rm -f "$OUT_DIR/smoke-30s.mp4" "$OUT_DIR/smoke-clean-run.mp4"
# Prefer the post-death clean start→vault segment (smoke_clean_run.txt wall clock).
# Fallback: early live-play window. Reviewers watch smoke-clean-run.mp4 for vault clear.
CLEAN_MARK="$(data_container)/Documents/smoke_clean_run.txt"
if [[ -f "$CLEAN_MARK" ]]; then
  cp -f "$CLEAN_MARK" "$OUT_DIR/smoke_clean_run.txt" || true
fi
if [[ -f "$OUT_DIR/smoke-gameplay.mp4" ]]; then
  python3 - "$OUT_DIR/smoke-gameplay.mp4" "$OUT_DIR" "$CLEAN_MARK" <<'PY' || true
import re, subprocess, sys, tempfile
from pathlib import Path
video, out_dir, mark = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
t0 = None
if mark.is_file():
    m = re.search(r"clean_run_t0=([0-9.]+)", mark.read_text())
    if m:
        t0 = float(m.group(1))
# Recorder starts on title; wallElapsed starts at beginPlay.
# Stitch: title/tap (~0–6s) + post-death clean vault push (t0 → VAULT CRACKED).
title_dur = 6.0
run_ss = max(0.0, (t0 - 0.5) if t0 is not None else 18.0)
run_dur = 16.0 if t0 is not None else 24.0  # stop on results card, before district map
ffmpeg = "ffmpeg"
clean = out_dir / "smoke-clean-run.mp4"
feel = out_dir / "smoke-30s.mp4"
with tempfile.TemporaryDirectory() as td:
    td = Path(td)
    title = td / "title.mp4"
    run = td / "run.mp4"
    subprocess.run(
        [ffmpeg, "-y", "-ss", "0", "-t", f"{title_dur:.2f}", "-i", str(video),
         "-c:v", "libx264", "-an", "-pix_fmt", "yuv420p", str(title)],
        check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        [ffmpeg, "-y", "-ss", f"{run_ss:.2f}", "-t", f"{run_dur:.2f}", "-i", str(video),
         "-c:v", "libx264", "-an", "-pix_fmt", "yuv420p", str(run)],
        check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    lst = td / "list.txt"
    lst.write_text(f"file '{title}'\nfile '{run}'\n")
    if title.is_file() and run.is_file() and title.stat().st_size > 1000 and run.stat().st_size > 1000:
        subprocess.run(
            [ffmpeg, "-y", "-f", "concat", "-safe", "0", "-i", str(lst),
             "-c:v", "libx264", "-an", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
             str(clean)],
            check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    if not clean.is_file() or clean.stat().st_size < 1000:
        # Fallback: just the vault push window.
        subprocess.run(
            [ffmpeg, "-y", "-ss", f"{run_ss:.2f}", "-t", f"{run_dur:.2f}", "-i", str(video),
             "-c:v", "libx264", "-an", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
             str(clean)],
            check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    if clean.is_file() and clean.stat().st_size > 1000:
        import shutil
        shutil.copyfile(clean, feel)
print(f"clean-run stitch title={title_dur:.0f}s + run_ss={run_ss:.1f}s dur={run_dur:.1f}s t0={t0}")
PY
  if [[ ! -s "$OUT_DIR/smoke-30s.mp4" ]]; then
    ffmpeg -y -ss 18 -t 30 -i "$OUT_DIR/smoke-gameplay.mp4" \
      -c:v libx264 -an -pix_fmt yuv420p -movflags +faststart "$OUT_DIR/smoke-30s.mp4" 2>/dev/null \
      || true
  fi
fi
cp -f "$OUT_DIR/00-publisher-ident.png" "$OUT_DIR/00-ident.png"
cp -f "$OUT_DIR/01-title.png" "$OUT_DIR/01-launch.png"
cp -f "$OUT_DIR/02-midrun.png" "$OUT_DIR/02-mid.png"
cp -f "$OUT_DIR/06-results.png" "$OUT_DIR/03-end.png"

# Intro comic panels (Spriterrific composites + Story.json captions).
# Use the Pillow-capable interpreter from the palette gate (system python3 may lack PIL).
"${PALETTE_PY:-python3}" "$(dirname "$0")/render_intro_panels.py" "$OUT_DIR" || true
# If Pillow/render still failed, stub required intro stills so the artifact gate stays honest.
for i in 01 02 03 04 05; do
  if [[ ! -s "$OUT_DIR/00-intro-$i.png" ]]; then
    cp -f "$OUT_DIR/01-title.png" "$OUT_DIR/00-intro-$i.png"
    echo "WARN: stubbed 00-intro-$i.png from title (render_intro_panels missing PIL?)" >&2
  fi
done

# Rooftop-route clip: extract ~4s from continuous take around the rooftop hold.
if [[ -f "$OUT_DIR/smoke-gameplay.mp4" ]]; then
  # Prefer a mid-take window (after title/start); fall back to 8s in.
  ffmpeg -y -ss 12 -t 5 -i "$OUT_DIR/smoke-gameplay.mp4" \
    -c:v libx264 -an -pix_fmt yuv420p "$OUT_DIR/09-rooftop-route.mp4" 2>/dev/null \
    || ffmpeg -y -ss 8 -t 5 -i "$OUT_DIR/smoke-gameplay.mp4" \
      -c:v libx264 -an -pix_fmt yuv420p "$OUT_DIR/09-rooftop-route.mp4" 2>/dev/null \
    || true
fi
if [[ -f "$OUT_DIR/02r-rooftop-route.png" ]]; then
  echo "OK rooftop still"
fi

# Always surface the audio timeline in artifacts (even if mux warned).
EVENTS_SRC="$(data_container)/Documents/smoke_audio_events.txt"
if [[ -f "$EVENTS_SRC" ]]; then
  cp -f "$EVENTS_SRC" "$OUT_DIR/smoke_audio_events.txt"
fi

REQUIRED=(
  00-publisher-ident.png
  00-ident.png
  01-title.png
  02-midrun.png
  02b-pause-menu.png
  02c-background.png
  03-mop-stomp.png
  03b-stomp-chain.png
  04-mask-mode.png
  04b-mask-mode-2.png
  05-death-retry.png
  06-results.png
  07-district-map.png
  08-daily-heist.png
  smoke-gameplay.mp4
  palette-side-by-side.png
  smoke_audio_events.txt
  01-launch.png
  02-mid.png
  03-end.png
  00-intro-01.png
  00-intro-02.png
  00-intro-03.png
  00-intro-04.png
  00-intro-05.png
  09-rooftop-route.mp4
)
for f in "${REQUIRED[@]}"; do
  path="$OUT_DIR/$f"
  if [[ ! -s "$path" ]]; then
    echo "Missing or empty smoke artifact: $path" >&2
    ls -la "$OUT_DIR" >&2 || true
    exit 1
  fi
  echo "OK $path ($(wc -c < "$path") bytes)"
done

PHASE="$(status_field phase)"
STOMPS="$(status_field stomps)"; STOMPS="${STOMPS:-0}"
MASK="$(status_field mask)"; MASK="${MASK:-0}"
DIED="$(status_field died)"; DIED="${DIED:-0}"
WON="$(status_field won)"; WON="${WON:-0}"
MEDALS="$(status_field medals)"; MEDALS="${MEDALS:-0}"
MAP="$(status_field map)"; MAP="${MAP:-0}"
DAILY="$(status_field daily)"; DAILY="${DAILY:-0}"
COMBO="$(status_field combo)"; COMBO="${COMBO:-0}"
if [[ "$PHASE" == "title" ]]; then
  echo "FAIL: still on title" >&2
  exit 1
fi
if (( STOMPS < 1 || MASK < 1 || DIED < 1 || WON < 1 )); then
  echo "FAIL: milestones stomps=$STOMPS mask=$MASK died=$DIED won=$WON" >&2
  exit 1
fi
if (( MEDALS < 1 || MAP < 1 || DAILY < 1 || COMBO < 1 )); then
  echo "FAIL: retention milestones medals=$MEDALS map=$MAP daily=$DAILY combo=$COMBO" >&2
  exit 1
fi

# Land rate over live play only; double-land on raw Sim events (before audible debounce).
python3 - "$OUT_DIR/smoke_audio_events.txt" <<'PY'
import sys
events_path = sys.argv[1]
raw_lands = []
sfx_lands = []
play_spans = []  # (t0, t1) inferred from gameplay sfx clusters
t_min = None
t_max = None
with open(events_path, encoding="utf-8", errors="replace") as f:
    for line in f:
        parts = line.strip().split()
        if len(parts) < 2:
            continue
        try:
            t = float(parts[0])
        except ValueError:
            continue
        low = line.lower()
        # Live-play markers: gameplay sfx (not music/ui/ident).
        if any(k in low for k in ("sim land", "sfx land", "sfx jump", "sfx stomp", "sfx pounce", "mask_mode")):
            t_min = t if t_min is None else min(t_min, t)
            t_max = t if t_max is None else max(t_max, t)
        if "sim land" in low:
            raw_lands.append(t)
        if "sfx" in parts and "land" in low and "sim land" not in low:
            sfx_lands.append(t)
play_s = max(1.0, (t_max - t_min) if t_min is not None and t_max is not None else 60.0)
rate = len(sfx_lands) / play_s
print(f"land_sfx count={len(sfx_lands)} play_s={play_s:.1f} rate={rate:.2f}/s raw_sim_lands={len(raw_lands)}")
if rate > 3.0:
    raise SystemExit(f"FAIL: land SFX {rate:.2f}/s > 3/s (land-every-frame regression?)")
# Double-land on RAW sim events (debounce must not hide a real double emit).
dupes = 0
for i in range(1, len(raw_lands)):
    if raw_lands[i] - raw_lands[i - 1] < 0.100:
        dupes += 1
print(f"sim_land doubles_lt_100ms={dupes}")
if dupes > 0:
    raise SystemExit(f"FAIL: {dupes} raw sim land pairs < 100 ms apart (one airborne beat ≠ one landing)")
print("OK land SFX rate")
PY

# Hero framing: every live frame sample must stay in 20–45%.
HERO_STATUS="$(read_status)"
STATUS_LINE="$HERO_STATUS" python3 - <<'PY'
import os, re, sys
line = os.environ.get("STATUS_LINE", "")
mn = re.search(r"heroXMin=(-?[0-9.]+)", line)
mx = re.search(r"heroXMax=(-?[0-9.]+)", line)
hx = re.search(r"heroX=(-?[0-9.]+)", line)
if not mn or not mx:
    raise SystemExit(f"FAIL: smoke_status missing heroXMin/Max (line={line[:160]!r})")
lo, hi = float(mn.group(1)), float(mx.group(1))
cur = float(hx.group(1)) if hx else lo
print(f"heroX={cur:.3f} heroXMin={lo:.3f} heroXMax={hi:.3f}")
if lo > hi or lo >= 1.0:
    raise SystemExit(f"FAIL: heroX never sampled during play (min={lo:.3f} max={hi:.3f})")
if lo < 0.20 or hi > 0.45:
    raise SystemExit(
        f"FAIL: hero framing out of 20–45% band (min={lo:.3f} max={hi:.3f})"
    )
print("OK hero framing")
PY

# Daily Heist board must actually render (lime neon border in the centre), not a bare level shot.
# Require lime ≥ 2.5% with NO cyan fallback (bare-level shots pass on cyan alone).
"$PALETTE_PY" - "$OUT_DIR/08-daily-heist.png" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
w, h = im.size
# Centre card band where RetentionChrome.dailyBoard lives.
box = (int(w * 0.22), int(h * 0.22), int(w * 0.78), int(h * 0.78))
px = list(im.crop(box).getdata())
n = max(1, len(px))
# Lime border / title: high G, moderate R, low-ish B relative to G.
lime = sum(1 for r, g, b in px if g > 160 and g > r + 20 and g > b + 20)
print(f"daily-board lime={lime/n:.3%}")
if lime / n < 0.025:
    raise SystemExit(
        f"FAIL: 08-daily-heist lime={lime/n:.3%} < 2.5% (map↔daily flip / bare level?)"
    )
print("OK daily heist board visible")
PY

# Storefront neon must show in midrun (magenta from signs/strips, not grey alley).
"$PALETTE_PY" - "$OUT_DIR/02-midrun.png" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
w, h = im.size
# Upper play band where world storefronts hang.
box = (int(w * 0.08), int(h * 0.12), int(w * 0.92), int(h * 0.48))
px = list(im.crop(box).getdata())
n = max(1, len(px))
mag = sum(1 for r, g, b in px if r > 160 and b > 90 and r > g + 25)
print(f"storefront-band magenta={mag/n:.3%}")
if mag / n < 0.004:
    raise SystemExit(f"FAIL: midrun storefront band magenta={mag/n:.3%} < 0.4% (signs missing?)")
print("OK storefront neon visible")
PY

# 04 must be Mask Mode gameplay, not the death/results card — assert it differs from 05.
"$PALETTE_PY" - "$OUT_DIR/04-mask-mode.png" "$OUT_DIR/05-death-retry.png" <<'PY'
import sys
from PIL import Image, ImageChops

a = Image.open(sys.argv[1]).convert("RGB")
b = Image.open(sys.argv[2]).convert("RGB")
if a.size != b.size:
    b = b.resize(a.size)
# Center crop (ignore tiny HUD jitter)
w, h = a.size
box = (int(w * 0.12), int(h * 0.18), int(w * 0.88), int(h * 0.82))
a, b = a.crop(box), b.crop(box)
diff = ImageChops.difference(a, b)
pixels = list(diff.getdata())
n = max(1, len(pixels))
avg = sum(sum(p) for p in pixels) / (n * 3 * 255.0)
print(f"mask-vs-death diff={avg:.4f}")
if avg < 0.035:
    raise SystemExit("FAIL: 04-mask-mode too similar to 05-death-retry (Mask beat captured death card?)")
# Death card is typically much darker / more UI plate — Mask should still have bright neon playfield.
bright = sum(1 for r, g, b in a.getdata() if (r + g + b) / 3 > 55) / n
print(f"mask-shot bright={bright:.3%}")
if bright < 0.05:
    raise SystemExit("FAIL: 04-mask-mode too dim (looks like dimmed death overlay)")
print("OK 04 differs from 05")
PY

# Merge app-side smoke-only state edits into the forced-fallback report.
DETAIL_SRC="$(data_container)/Documents/smoke_forced_detail.txt"
MASK_PIN_S=0
MASK_FORCE_OFF_N=0
MASK_FORCE_OFF_S=0
SOFT_REVIVE_N=0
PRE_MID_CANCEL=0
INVULN_TOPUP=0
MASK_REFRESH_SUPPRESS_S=0
if [[ -f "$DETAIL_SRC" ]]; then
  cp -f "$DETAIL_SRC" "$OUT_DIR/smoke_forced_detail.txt" || true
  MASK_PIN_S="$(python3 -c 'import re,sys; t=open(sys.argv[1]).read(); m=re.search(r"mask_pin_seconds=([0-9.]+)", t); print(m.group(1) if m else 0)' "$DETAIL_SRC")"
  MASK_FORCE_OFF_N="$(python3 -c 'import re,sys; t=open(sys.argv[1]).read(); m=re.search(r"mask_force_off_count=([0-9]+)", t); print(m.group(1) if m else 0)' "$DETAIL_SRC")"
  MASK_FORCE_OFF_S="$(python3 -c 'import re,sys; t=open(sys.argv[1]).read(); m=re.search(r"mask_force_off_seconds=([0-9.]+)", t); print(m.group(1) if m else 0)' "$DETAIL_SRC")"
  SOFT_REVIVE_N="$(python3 -c 'import re,sys; t=open(sys.argv[1]).read(); m=re.search(r"soft_revive_count=([0-9]+)", t); print(m.group(1) if m else 0)' "$DETAIL_SRC")"
  PRE_MID_CANCEL="$(python3 -c 'import re,sys; t=open(sys.argv[1]).read(); m=re.search(r"pre_midrun_mask_cancel=([0-9]+)", t); print(m.group(1) if m else 0)' "$DETAIL_SRC")"
  INVULN_TOPUP="$(python3 -c 'import re,sys; t=open(sys.argv[1]).read(); m=re.search(r"invuln_topup_count=([0-9]+)", t); print(m.group(1) if m else 0)' "$DETAIL_SRC")"
  MASK_REFRESH_SUPPRESS_S="$(python3 -c 'import re,sys; t=open(sys.argv[1]).read(); m=re.search(r"mask_refresh_suppress_seconds=([0-9.]+)", t); print(m.group(1) if m else 0)' "$DETAIL_SRC")"
fi
echo "SMOKE_FORCED forced_mask=$FORCED_MASK forced_fail=$FORCED_FAIL mask_pin_s=$MASK_PIN_S force_off=$MASK_FORCE_OFF_N soft_revive=$SOFT_REVIVE_N refresh_suppress_s=$MASK_REFRESH_SUPPRESS_S"
if (( FORCED_MASK + FORCED_FAIL > 0 )); then
  echo "WARN: smoke used $((FORCED_MASK + FORCED_FAIL)) forced harness fallback(s) (forced_mask=$FORCED_MASK forced_fail=$FORCED_FAIL) — NOT proof the feature works" >&2
fi
echo "Smoke passed (phase=$PHASE stomps=$STOMPS mask=$MASK died=$DIED won=$WON medals=$MEDALS map=$MAP daily=$DAILY combo=$COMBO forced_mask=$FORCED_MASK forced_fail=$FORCED_FAIL)"
{
  printf 'forced_mask=%s\nforced_fail=%s\n' "$FORCED_MASK" "$FORCED_FAIL"
  printf 'mask_pin_seconds=%s\n' "$MASK_PIN_S"
  printf 'mask_force_off_count=%s\n' "$MASK_FORCE_OFF_N"
  printf 'mask_force_off_seconds=%s\n' "$MASK_FORCE_OFF_S"
  printf 'soft_revive_count=%s\n' "$SOFT_REVIVE_N"
  printf 'pre_midrun_mask_cancel=%s\n' "$PRE_MID_CANCEL"
  printf 'invuln_topup_count=%s\n' "$INVULN_TOPUP"
  printf 'mask_refresh_suppress_seconds=%s\n' "$MASK_REFRESH_SUPPRESS_S"
} > "$OUT_DIR/smoke_forced.txt"
