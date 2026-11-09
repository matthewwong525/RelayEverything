#!/usr/bin/env bash
# Runs one Maestro flow for Claude. A run past 120 s is stopped with its driver and tried once more, so one stuck tap
# does not end the check. The last line is result=passed|failed|hung.
set -uo pipefail
flow=${1:?usage: bash mobile/device-check/flow.sh <flow.yaml>}
limit=${FLOW_LIMIT:-120}
log="${flow%.yaml}.log"

source "$(dirname "$0")/limit.sh"

: > "$log"
end=$(run_limited "$limit" "$log" maestro test "$flow")
if [ "$end" = hung ]; then
  echo "The flow ran over $limit s and was stopped. Trying once more." | tee -a "$log"
  end=$(run_limited "$limit" "$log" maestro test "$flow")
fi
tail -n 30 "$log"
case "$end" in
  0) echo "result=passed" ;;
  hung) echo "result=hung"; exit 1 ;;
  *) echo "result=failed"; exit 1 ;;
esac
