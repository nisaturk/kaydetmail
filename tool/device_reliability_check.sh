#!/usr/bin/env bash
set -euo pipefail

PKG="${1:-com.example.kaydetmail}"
OFFLINE_TEXT="Bağlantı yok"
LOGIN_TEXT="Devam"
failures=0

screen_text() {
  adb shell uiautomator dump /sdcard/kaydet_ui.xml >/dev/null 2>&1 || true
  adb exec-out cat /sdcard/kaydet_ui.xml 2>/dev/null || true
}

wait_for() {
  local needle="$1" present="$2" timeout="${3:-90}" waited=0
  while (( waited < timeout )); do
    if screen_text | grep -q "$needle"; then
      [[ "$present" == yes ]] && return 0
    else
      [[ "$present" == no ]] && return 0
    fi
    sleep 3
    waited=$((waited + 3))
  done
  return 1
}

check() {
  local name="$1"; shift
  if "$@"; then echo "PASS  $name"; else echo "FAIL  $name"; failures=$((failures + 1)); fi
}

launch() {
  adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 5
}

set_network() {
  adb shell svc wifi "$1" >/dev/null 2>&1 || true
  adb shell svc data "$1" >/dev/null 2>&1 || true
}

trap 'set_network enable; adb shell dumpsys deviceidle unforce >/dev/null 2>&1 || true' EXIT

launch
check "app starts signed in" wait_for "$LOGIN_TEXT" no 30

set_network disable
adb shell input swipe 500 700 500 1500 300
check "network lost shows offline banner" wait_for "$OFFLINE_TEXT" yes 120

set_network enable
check "network restored clears offline banner" wait_for "$OFFLINE_TEXT" no 180

adb shell am force-stop "$PKG"
launch
check "killed app restores the session" wait_for "$LOGIN_TEXT" no 30

adb shell input keyevent KEYCODE_HOME
adb shell dumpsys deviceidle force-idle >/dev/null
sleep 20
adb shell dumpsys deviceidle unforce >/dev/null
launch
check "app recovers after doze" wait_for "$OFFLINE_TEXT" no 120

echo "failures=$failures"
exit "$failures"
