#!/usr/bin/env bash
# Run one OpenCode agent on DeepSeek v4.1 Flash with a concatenated brief.
# usage: run-agent.sh <repo> <briefs-dir> <task> [extra-brief.md ...]
#   reads <briefs-dir>/common.md, any extra briefs, then <briefs-dir>/<task>.md
#   writes <briefs-dir>/<task>.log and prints the exit code and the report tail.
# env: OPENCODE_MODEL (default opencode-go/deepseek-v4.1-flash), TAIL (default 60)
set -uo pipefail

repo="$(cd "${1:?repo}" && pwd)"
briefs="$(cd "${2:?briefs dir}" && pwd)"
task="${3:?task name}"
shift 3
model="${OPENCODE_MODEL:-opencode-go/deepseek-v4.1-flash}"

files=("$briefs/common.md")
for extra in "$@"; do files+=("$briefs/$extra"); done
files+=("$briefs/$task.md")
for f in "${files[@]}"; do [[ -f "$f" ]] || { echo "missing brief: $f" >&2; exit 2; }; done

cd "$repo"
# OpenCode resolves the project root from $PWD, not the process cwd.
PWD="$repo" opencode run -m "$model" "$(cat "${files[@]}")" > "$briefs/$task.log" 2>&1
code=$?
echo "$task exit $code"
tail -n "${TAIL:-60}" "$briefs/$task.log"
exit $code
