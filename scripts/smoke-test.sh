#!/usr/bin/env bash
# End-to-end smoke test. Usage: API_KEY=... scripts/smoke-test.sh BASE_URL
# Runs identically against local Docker, CI and AWS.
set -u

BASE_URL="${1:?usage: smoke-test.sh BASE_URL}"
BASE_URL="${BASE_URL%/}"
API_KEY="${API_KEY:-dev-api-key}"
RUN="$(date +%s)$RANDOM"
START=$(date +%s)
FAILED=0

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
step() { STEP_START=$(date +%s); printf '[%s] STEP %s\n' "$(ts)" "$1"; }
ok() { printf '[%s]   PASS (%ss) %s\n' "$(ts)" "$(( $(date +%s) - STEP_START ))" "$1"; }
fail() { printf '[%s]   FAIL %s\n' "$(ts)" "$1"; FAILED=1; summary; exit 1; }
summary() {
  local total=$(( $(date +%s) - START ))
  if [ "$FAILED" -eq 0 ]; then echo "RESULT: PASS in ${total}s ($BASE_URL)"; else echo "RESULT: FAIL after ${total}s ($BASE_URL)"; fi
}

api() { # method path [body] [extra curl args...]
  local method="$1" path="$2" body="${3:-}"
  if [ -n "$body" ]; then
    curl -sS -m 15 -X "$method" "$BASE_URL$path" -H "X-API-Key: $API_KEY" -H 'Content-Type: application/json' -d "$body"
  else
    curl -sS -m 15 -X "$method" "$BASE_URL$path" -H "X-API-Key: $API_KEY"
  fi
}
field() { sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p" | head -1; }
event() { # key user device type playSeconds
  local play=""
  [ -n "${5:-}" ] && play=",\"playSeconds\":$5"
  api POST /events "{\"idempotencyKey\":\"$1\",\"userId\":\"$2\",\"deviceId\":\"$3\",\"ip\":\"10.0.0.1\",\"type\":\"$4\"$play,\"occurredAt\":\"$(now)\"}"
}
alerts_total() { api GET /actuator/prometheus | grep '^sentinel_alerts_total' | awk '{print $NF}' | head -1 | cut -d. -f1; }

echo "Sentinel smoke test against $BASE_URL (run $RUN) started $(ts)"

step "1 health is UP"
for _ in $(seq 1 30); do
  curl -fsS -m 5 "$BASE_URL/actuator/health" 2>/dev/null | grep -q '"status":"UP"' && break
  sleep 2
done
curl -fsS -m 5 "$BASE_URL/actuator/health" | grep -q '"status":"UP"' || fail "health is not UP"
ok "status UP"

# make sure a previous run did not leave the velocity rule in shadow mode
api PUT /rules/velocity '{"enabled":true,"shadow":false,"params":{"maxEvents":5,"windowSeconds":60}}' > /dev/null
ALERTS_BEFORE=$(alerts_total); ALERTS_BEFORE=${ALERTS_BEFORE:-0}

step "2 normal event is ALLOW"
R=$(event "n-$RUN" "user-n-$RUN" "dev-n-$RUN" INSTALL)
echo "  $R"
echo "$R" | grep -q '"decision":"ALLOW"' || fail "expected ALLOW"
ok "ALLOW"

step "3 velocity burst escalates"
for i in 1 2 3 4 5 6 7; do R=$(event "b-$RUN-$i" "user-b-$RUN" "dev-b-$RUN" INSTALL); done
echo "  $R"
echo "$R" | grep -Eq '"decision":"(REVIEW|BLOCK)"' || fail "expected REVIEW or BLOCK on last burst event"
EVENT_ID=$(echo "$R" | field eventId)
ok "$(echo "$R" | field decision)"

step "4 idempotent replay"
R1=$(event "i-$RUN" "user-i-$RUN" "dev-i-$RUN" INSTALL)
R2=$(event "i-$RUN" "user-i-$RUN" "dev-i-$RUN" INSTALL)
[ "$(echo "$R1" | field eventId)" = "$(echo "$R2" | field eventId)" ] && [ -n "$(echo "$R1" | field eventId)" ] || fail "replay returned a different eventId"
ok "same eventId"

step "5 open case exists"
CASES=$(api GET "/cases?status=OPEN")
echo "$CASES" | grep -q '"id"' || fail "no OPEN case found"
CASE_ID=$(echo "$CASES" | field id)
ok "case $CASE_ID"

step "6 resolve case"
R=$(api POST "/cases/$CASE_ID/resolve" '{"status":"APPROVED"}')
echo "$R" | grep -q '"status":"APPROVED"' || fail "resolve failed: $R"
ok "APPROVED"

step "7 rule update writes audit row"
R=$(api PUT /rules/velocity '{"enabled":true,"shadow":true,"params":{"maxEvents":5,"windowSeconds":60}}')
echo "  $R"
echo "$R" | grep -Eq '"shadow":true' && echo "$R" | grep -Eq '"auditId":[0-9]+' || fail "rule update or audit missing"
api PUT /rules/velocity '{"enabled":true,"shadow":false,"params":{"maxEvents":5,"windowSeconds":60}}' > /dev/null
ok "audit row written"

step "8 SQS consumer produced alerts (sentinel_alerts_total)"
GOT=0
for _ in $(seq 1 15); do
  NOW=$(alerts_total); NOW=${NOW:-0}
  if [ "$NOW" -gt "$ALERTS_BEFORE" ]; then GOT=1; break; fi
  sleep 2
done
[ "$GOT" -eq 1 ] || fail "sentinel_alerts_total did not increase within 30s (was $ALERTS_BEFORE)"
ok "alerts $ALERTS_BEFORE -> $NOW"

summary
exit 0
