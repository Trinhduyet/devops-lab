#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT="$ROOT/applications/dotnet-sample-api/DevOpsLab.SampleApi.csproj"
TMP_ROOT=$(cd -- "${TMPDIR:-/tmp}" && pwd)
TEMP_DIR=$(mktemp -d "$TMP_ROOT/devops-dotnet-api.XXXXXXXX")
APP_LOG="$TEMP_DIR/app.log"
APP_PID=''
APP_NAME_VALUE=devops-lab-smoke
API_PORT=${API_PORT:-5089}
BASE_URL="http://127.0.0.1:$API_PORT"

stop_app() {
  local app_state='' index wait_status
  [[ -n "$APP_PID" ]] || return 0

  if kill -0 "$APP_PID" 2>/dev/null; then kill -TERM "$APP_PID" 2>/dev/null || true; fi
  for ((index = 0; index < 10; index++)); do
    app_state=$(ps -o stat= -p "$APP_PID" 2>/dev/null || true)
    if [[ -z "$app_state" || "$app_state" == Z* ]]; then break; fi
    sleep 1
  done

  app_state=$(ps -o stat= -p "$APP_PID" 2>/dev/null || true)
  if [[ -n "$app_state" && "$app_state" != Z* ]]; then
    printf 'FAIL: API did not stop within 10 seconds; sending SIGKILL.\n' >&2
    kill -KILL "$APP_PID" 2>/dev/null || true
    for ((index = 0; index < 10; index++)); do
      app_state=$(ps -o stat= -p "$APP_PID" 2>/dev/null || true)
      if [[ -z "$app_state" || "$app_state" == Z* ]]; then break; fi
      sleep 1
    done
    app_state=$(ps -o stat= -p "$APP_PID" 2>/dev/null || true)
    if [[ -n "$app_state" && "$app_state" != Z* ]]; then
      printf 'FAIL: API process remains after bounded SIGKILL wait; preserving its temporary files.\n' >&2
      return 1
    fi
    if wait "$APP_PID"; then :; else :; fi
    APP_PID=''
    return 1
  fi

  if wait "$APP_PID"; then
    APP_PID=''
    return 0
  else
    wait_status=$?
    APP_PID=''
    return "$wait_status"
  fi
}

cleanup() {
  local result=$?
  trap - EXIT
  if [[ -n "$APP_PID" ]]; then
    if stop_app; then :; else result=1; fi
  fi
  if [[ -n "$APP_PID" ]]; then
    printf 'FAIL: retaining temporary output because the API process is still present.\n' >&2
    result=1
  elif [[ "$TEMP_DIR" == "$TMP_ROOT"/devops-dotnet-api.* && -d "$TEMP_DIR" ]]; then
    if rm -rf -- "$TEMP_DIR"; then
      if (( result == 0 )); then printf 'PASS: test process and temporary output cleanup verified.\n'; fi
    else
      printf 'FAIL: temporary output cleanup failed.\n' >&2
      result=1
    fi
  else
    printf 'FAIL: refusing cleanup outside the unique test directory.\n' >&2
    result=1
  fi
  exit "$result"
}
trap cleanup EXIT

if [[ ! "$API_PORT" =~ ^[0-9]{1,5}$ ]] || (( API_PORT < 1024 || API_PORT > 65535 )); then
  printf 'FAIL: API_PORT must be an unprivileged port from 1024 through 65535.\n' >&2
  exit 2
fi

dotnet publish "$PROJECT" --configuration Release --output "$TEMP_DIR/publish"

ASPNETCORE_URLS="$BASE_URL" APP_NAME="$APP_NAME_VALUE" \
  dotnet "$TEMP_DIR/publish/DevOpsLab.SampleApi.dll" >"$APP_LOG" 2>&1 &
APP_PID=$!

ready=0
for _ in {1..30}; do
  if curl --fail --silent --max-time 2 "$BASE_URL/health/ready" >/dev/null 2>&1; then
    ready=1
    break
  fi
  if ! kill -0 "$APP_PID" 2>/dev/null; then break; fi
  sleep 1
done
if (( ready != 1 )); then
  printf 'FAIL: API did not become ready on the loopback test port.\n' >&2
  tail -n 12 "$APP_LOG" >&2 || true
  exit 1
fi

root_payload=$(curl --fail --silent --show-error --max-time 5 "$BASE_URL/")
if [[ "$root_payload" != *"\"service\":\"$APP_NAME_VALUE\""* || "$root_payload" != *'"status":"ok"'* || "$root_payload" != *'"version":"'* ]]; then
  printf 'FAIL: GET / did not return the configured service payload.\n' >&2
  exit 1
fi
printf 'PASS: GET / returned configured environment and version fields.\n'

live_payload=$(curl --fail --silent --show-error --max-time 5 "$BASE_URL/health/live")
if [[ "$live_payload" != *'"status":"live"'* ]]; then
  printf 'FAIL: GET /health/live returned an unexpected payload.\n' >&2
  exit 1
fi
printf 'PASS: GET /health/live.\n'

ready_payload=$(curl --fail --silent --show-error --max-time 5 "$BASE_URL/health/ready")
if [[ "$ready_payload" != *'"status":"ready"'* ]]; then
  printf 'FAIL: GET /health/ready returned an unexpected payload.\n' >&2
  exit 1
fi
printf 'PASS: GET /health/ready.\n'

if ! stop_app; then
  printf 'FAIL: API did not exit successfully after SIGTERM within the bounded shutdown period.\n' >&2
  exit 1
fi
if ! grep -Fq 'Application shutdown completed gracefully' "$APP_LOG"; then
  printf 'FAIL: graceful shutdown log event was not observed.\n' >&2
  exit 1
fi
printf 'PASS: SIGTERM graceful shutdown observed.\n'
