#!/usr/bin/env bash
set -euo pipefail

PLATFORM=$(uname -s)
if [[ "$PLATFORM" != Linux ]]; then
  printf 'NOT TESTED: API process/SIGTERM integration requires Linux; run it on a Linux host or the GitHub-hosted runner.\n'
  exit 2
fi

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT="$ROOT/applications/dotnet-sample-api/DevOpsLab.SampleApi.csproj"
TMP_ROOT=$(cd -- "${TMPDIR:-/tmp}" && pwd)
TEMP_DIR=$(mktemp -d "$TMP_ROOT/devops-dotnet-api.XXXXXXXX")
APP_LOG="$TEMP_DIR/app.log"
NUGET_CONFIG="$TEMP_DIR/NuGet.Config"
NUGET_PACKAGES_PATH="$TEMP_DIR/packages"
APPDATA_DIR="$TEMP_DIR/appdata"
HOME_DIR="$TEMP_DIR/home"
DOTNET_HOME="$TEMP_DIR/dotnet-home"
APP_PID=''
APP_NAME_VALUE="devops-lab-smoke-${TEMP_DIR##*.}"
BASE_URL=''

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

export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
export DOTNET_NOLOGO=1

mkdir -p "$APPDATA_DIR/NuGet" "$HOME_DIR/.nuget/NuGet" "$DOTNET_HOME"
cat > "$NUGET_CONFIG" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
  </packageSources>
</configuration>
XML

if command -v cygpath >/dev/null 2>&1; then
  APPDATA_DIR=$(cygpath -aw "$APPDATA_DIR")
  HOME_DIR=$(cygpath -aw "$HOME_DIR")
  NUGET_PACKAGES_PATH=$(cygpath -aw "$NUGET_PACKAGES_PATH")
  DOTNET_HOME=$(cygpath -aw "$DOTNET_HOME")
fi

APPDATA="$APPDATA_DIR" HOME="$HOME_DIR" DOTNET_CLI_HOME="$DOTNET_HOME" NUGET_PACKAGES="$NUGET_PACKAGES_PATH" \
  dotnet restore "$PROJECT" --configfile "$NUGET_CONFIG" --packages "$NUGET_PACKAGES_PATH"
APPDATA="$APPDATA_DIR" HOME="$HOME_DIR" DOTNET_CLI_HOME="$DOTNET_HOME" NUGET_PACKAGES="$NUGET_PACKAGES_PATH" \
  dotnet publish "$PROJECT" --configuration Release --no-restore --output "$TEMP_DIR/publish"

ASPNETCORE_URLS='http://127.0.0.1:0' APP_NAME="$APP_NAME_VALUE" \
  dotnet "$TEMP_DIR/publish/DevOpsLab.SampleApi.dll" >"$APP_LOG" 2>&1 &
APP_PID=$!

ready=0
process_match=0
process_check_available=0
for _ in {1..30}; do
  if ! kill -0 "$APP_PID" 2>/dev/null; then break; fi
  if [[ "$PLATFORM" == Linux && -r "/proc/$APP_PID/cmdline" ]]; then
    process_check_available=1
    if tr '\0' ' ' < "/proc/$APP_PID/cmdline" | grep -Fq "$TEMP_DIR/publish/DevOpsLab.SampleApi.dll"; then
      process_match=1
    fi
  fi
  API_PORT=$(sed -nE 's/.*Now listening on: http:\/\/127\.0\.0\.1:([0-9]+).*/\1/p' "$APP_LOG" | tail -n 1)
  if [[ "$API_PORT" =~ ^[0-9]{1,5}$ ]]; then
    BASE_URL="http://127.0.0.1:$API_PORT"
    if curl --fail --silent --max-time 2 "$BASE_URL/health/ready" >/dev/null 2>&1; then
      ready=1
      break
    fi
  fi
  sleep 1
done
if (( ready != 1 || (process_check_available == 1 && process_match != 1) )); then
  printf 'FAIL: unique API process did not bind a random loopback port and become ready.\n' >&2
  tail -n 12 "$APP_LOG" >&2 || true
  exit 1
fi
printf 'PASS: Kestrel selected a free loopback port; endpoint identity will be checked against the unique process token.\n'

root_payload=$(curl --fail --silent --show-error --max-time 5 "$BASE_URL/")
if [[ "$root_payload" != *"\"service\":\"$APP_NAME_VALUE\""* || "$root_payload" != *'"status":"ok"'* || "$root_payload" != *'"version":"'* ]]; then
  printf 'FAIL: GET / did not return the configured service payload.\n' >&2
  exit 1
fi
printf 'PASS: root endpoint matched the unique smoke instance token.\n'
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
if ! grep -Fq 'Application stopping; readiness withdrawn' "$APP_LOG"; then
  printf 'FAIL: readiness was not withdrawn when application stopping began.\n' >&2
  exit 1
fi
printf 'PASS: SIGTERM graceful shutdown observed.\n'
