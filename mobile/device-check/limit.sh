#!/usr/bin/env bash
# Sourced by flow.sh and tour.sh: run_limited <seconds> <log> <command>... runs the command with its output added to
# the log, and prints its exit status, or `hung` after it ran past the limit and was stopped with Maestro's driver.

stop_tree() {
  local child
  for child in $(pgrep -P "$1"); do stop_tree "$child"; done
  kill -TERM "$1" 2>/dev/null
}

# macOS has no `timeout`, so the loop counts the seconds.
run_limited() {
  local limit=$1 log=$2 second
  shift 2
  "$@" >> "$log" 2>&1 &
  local pid=$!
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
