#!/usr/bin/env bash
# Deliberately no `set -e`: the whole point of this script is to survive one
# destination being unreachable/misconfigured and still attempt the rest (see
# the `fail-on-error` input for the opt-in "fail the step if any destination
# failed" behavior). `set -u` still catches genuine bugs (unset vars).
set -uo pipefail

repo="${REPO_INPUT:-$GITHUB_REPOSITORY}"
branch="${BRANCH_INPUT:-$GITHUB_REF_NAME}"
sha="${SHA_INPUT:-$GITHUB_SHA}"
lcov_path="$LCOV_PATH"
connect_timeout="${CONNECT_TIMEOUT:-5}"
max_time="${MAX_TIME:-15}"

if [ -z "$lcov_path" ]; then
  echo "::error::lcov-path input is required"
  exit 1
fi
if [ ! -f "$lcov_path" ]; then
  echo "::error::lcov-path '$lcov_path' does not exist (did the test/coverage step run first?)"
  exit 1
fi

# Written to a file rather than held in a shell variable: lcov reports embed
# one entry per line/branch/function in the project, so the JSON-wrapped
# payload routinely exceeds Linux's ~128KB single-argument limit
# (MAX_ARG_STRLEN). Passing it as a literal `-d "$payload"` argument then
# fails execve() with E2BIG, which bash reports as exit 126 — indistinguishable
# at a glance from a real curl/network failure. `--data @file` reads the body
# from disk instead, so there's no argument-size ceiling.
payload_file=$(mktemp)
trap 'rm -f "$payload_file"' EXIT

jq -n \
  --arg repo "$repo" \
  --arg branch "$branch" \
  --arg sha "$sha" \
  --rawfile lcov "$lcov_path" \
  '{repoFullName:$repo, branch:$branch, commitSha:$sha, lcov:$lcov}' > "$payload_file"

# Uploads to one destination. Never lets curl's exit status (or a bad HTTP
# status) escape as a script-ending error — the caller decides what to do
# with the return code.
upload_one() {
  local url="$1" token="$2" status curl_exit body_file

  # Trim surrounding whitespace and a trailing slash so a copy-pasted URL
  # (e.g. "https://host/v1/coverage/ ") still hits the right endpoint.
  url="$(printf '%s' "$url" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s#/*$##')"

  if [ -z "$url" ] || [ -z "$token" ]; then
    echo "::warning::skipping destination with empty url or token"
    return 1
  fi

  body_file=$(mktemp)
  status=$(curl -s -o "$body_file" -w '%{http_code}' \
    --connect-timeout "$connect_timeout" --max-time "$max_time" \
    -X POST "$url" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    --data "@$payload_file" 2>/dev/null)
  curl_exit=$?

  if [ "$curl_exit" -ne 0 ]; then
    echo "::warning::coverage upload to $url failed — unreachable or timed out (curl exit $curl_exit)"
    rm -f "$body_file"
    return 1
  fi

  if [ "$status" = "200" ]; then
    echo "✓ uploaded coverage to $url"
    rm -f "$body_file"
    return 0
  fi

  echo "::warning::coverage upload to $url failed (HTTP $status)"
  sed 's/^/    /' "$body_file" 2>/dev/null && echo
  rm -f "$body_file"
  return 1
}

attempted=0
failures=0

if [ -n "${DESTINATIONS_INPUT:-}" ]; then
  while IFS= read -r line; do
    line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$line" ] && continue
    url="${line%%=*}"
    token="${line#*=}"
    attempted=$((attempted + 1))
    upload_one "$url" "$token" || failures=$((failures + 1))
  done <<< "$DESTINATIONS_INPUT"
else
  url="${GATEWAY_URL_INPUT:-}"
  token="${OBIGUARD_COVERAGE_TOKEN:-}"

  if [ -z "$url" ]; then
    echo "::error::gateway-url input (or destinations) is required"
    exit 1
  fi
  if [ -z "$token" ]; then
    echo "::error::OBIGUARD_COVERAGE_TOKEN env var is required — pass it via this step's env:, e.g. \${{ secrets.OBIGUARD_COVERAGE_TOKEN }}"
    exit 1
  fi

  attempted=1
  upload_one "$url" "$token" || failures=1
fi

succeeded=$((attempted - failures))
echo "Coverage upload: ${succeeded}/${attempted} destination(s) succeeded"

if [ "$failures" -gt 0 ] && [ "${FAIL_ON_ERROR:-false}" = "true" ]; then
  exit 1
fi
exit 0
