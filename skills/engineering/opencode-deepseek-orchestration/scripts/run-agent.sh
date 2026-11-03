#!/usr/bin/env bash
# Run one OpenCode agent on DeepSeek v4.1 Flash with a concatenated brief.
# usage: run-agent.sh <repo> <briefs-dir> <task> [extra-brief.md ...]
#   reads <briefs-dir>/common.md, any extra briefs, then <briefs-dir>/<task>.md
#   writes <briefs-dir>/<task>.log and prints the exit code and the report tail.
# env: OPENCODE_MODEL (default opencode-go/deepseek-v4.1-flash), TAIL (default 60),
#      STALL_SECS (default 300: kill if the log stops growing), MAX_SECS (default 2400)
# exit: agent's code; 3 = stalled; 4 = timed out
set -uo pipefail

repo="$(cd "${1:?repo}" && pwd)"
briefs="$(cd "${2:?briefs dir}" && pwd)"
task="${3:?task name}"
shift 3
model="${OPENCODE_MODEL:-opencode-go/deepseek-v4.1-flash}"
stall="${STALL_SECS:-300}"
max="${MAX_SECS:-2400}"
log="$briefs/$task.log"

files=("$briefs/common.md")
for extra in "$@"; do files+=("$briefs/$extra"); done
files+=("$briefs/$task.md")
for f in "${files[@]}"; do [[ -f "$f" ]] || { echo "missing brief: $f" >&2; exit 2; }; done

cd "$repo"
# OpenCode resolves the project root from $PWD, not the process cwd.
# --standalone: a private server per run; the shared background service can hang clients.
PWD="$repo" opencode run --standalone -m "$model" "$(cat "${files[@]}")" > "$log" 2>&1 &
pid=$!

elapsed=0; idle=0; last=-1; code=0
while kill -0 "$pid" 2>/dev/null; do
  sleep 10; elapsed=$((elapsed + 10))
  size=$(wc -c < "$log")
  if [[ "$size" == "$last" ]]; then idle=$((idle + 10)); else idle=0; fi
  last=$size
  if (( idle >= stall )); then echo "$task STALLED (${stall}s without output)"; kill "$pid"; code=3; break; fi
  if (( elapsed >= max )); then echo "$task TIMEOUT (${max}s)"; kill "$pid"; code=4; break; fi
done
if (( code == 0 )); then wait "$pid"; code=$?; fi
echo "$task exit $code"
tail -n "${TAIL:-60}" "$log"
exit $code
