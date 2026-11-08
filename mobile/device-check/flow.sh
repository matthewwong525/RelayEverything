#!/usr/bin/env bash
# Runs one Maestro flow for Claude. A run past 120 s is stopped with its driver and tried once more, so one stuck tap
# does not end the check. The last line is result=passed|failed|hung.
set -uo pipefail
flow=${1:?usage: bash mobile/device-check/flow.sh <flow.yaml>}
limit=${FLOW_LIMIT:-120}
log="${flow%.yaml}.log"

stop_tree() {
  local child
  for child in $(pgrep -P "$1"); do stop_tree "$child"; done
  kill -TERM "$1" 2>/dev/null
}

# Prints the run's exit status, or `hung`. macOS has no `timeout`, so the loop counts the seconds.
run_once() {
  maestro test "$flow" >> "$log" 2>&1 &
  local pid=$! second
  for ((second = 0; second < limit; second++)); do
    kill -0 "$pid" 2>/dev/null || { wait "$pid"; echo $?; return; }
    sleep 1
  done
  stop_tree "$pid"
  pkill -TERM -f 'maestro-driver' 2>/dev/null
  sleep 3
  kill -KILL "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  echo hung
}

: > "$log"
end=$(run_once)
if [ "$end" = hung ]; then
  echo "The flow ran over $limit s and was stopped. Trying once more." | tee -a "$log"
  end=$(run_once)
fi
tail -n 30 "$log"
case "$end" in
  0) echo "result=passed" ;;
  hung) echo "result=hung"; exit 1 ;;
  *) echo "result=failed"; exit 1 ;;
esac
