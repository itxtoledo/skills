#!/usr/bin/env bash
#
# Delete local and remote branches whose work is already merged into the base branch.
#
# Handles both merge styles found in real repositories:
#   1. merge commits / fast-forwards  -> git ancestry
#   2. squash / rebase merges         -> GitHub merged PRs, verified against the PR head
#
# Dry-run by default. Nothing is deleted without --apply.
#
# Usage: cleanup-merged-branches.sh [options]
#   --apply              delete instead of printing the plan
#   --local              local branches only
#   --remote [name]      remote branches only (deletes on the remote)
#   --base <branch>      base branch (default: remote HEAD, then gh, then main/master)
#   --remote-name <name> remote to inspect and delete from (default: origin)
#   --keep <branch>      never delete this branch (repeatable)
#   --keep-regex <re>    replace the protected-branch regex
#   -h, --help           this help
#
set -euo pipefail

APPLY=0
DO_LOCAL=1
DO_REMOTE=1
REMOTE=""
BASE=""
KEEP=()
KEEP_REGEX='^(main|master|trunk|develop|development|dev|release|release/.*|staging|stage|homolog|homologation|production|prod|beta|alpha|next)$'

usage() {
  sed -n '/^# Usage:/,/^#   -h, --help/p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
warn() { printf 'warning: %s\n' "$*" >&2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --local) DO_LOCAL=1; DO_REMOTE=0 ;;
    --remote)
      DO_LOCAL=0; DO_REMOTE=1
      # Optional remote name: "--remote upstream" (but not "--remote --apply").
      if [ $# -ge 2 ] && [ "${2#-}" = "$2" ]; then REMOTE="$2"; shift; fi
      ;;
    --base) [ $# -ge 2 ] || die "--base needs a value"; BASE="$2"; shift ;;
    --base=*) BASE="${1#*=}" ;;
    --remote-name) [ $# -ge 2 ] || die "--remote-name needs a value"; REMOTE="$2"; shift ;;
    --remote-name=*) REMOTE="${1#*=}" ;;
    --keep) [ $# -ge 2 ] || die "--keep needs a value"; KEEP+=("$2"); shift ;;
    --keep=*) KEEP+=("${1#*=}") ;;
    --keep-regex) [ $# -ge 2 ] || die "--keep-regex needs a value"; KEEP_REGEX="$2"; shift ;;
    --keep-regex=*) KEEP_REGEX="${1#*=}" ;;
    -h|--help) usage 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
  shift
done

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository"
cd "$REPO_ROOT"

TAB=$(printf '\t')
TMP=$(mktemp -d "${TMPDIR:-/tmp}/branch-cleanup.XXXXXX")
FETCHED_REFS=""
cleanup() {
  local ref
  for ref in $FETCHED_REFS; do
    git update-ref -d "$ref" 2>/dev/null || true
  done
  rm -rf "$TMP"
}
trap cleanup EXIT

# ---------------------------------------------------------------- locate remote/base
if [ -z "$REMOTE" ]; then
  if git remote | grep -qx 'origin'; then
    REMOTE=origin
  else
    REMOTE=$(git remote | head -n 1 || true)
  fi
fi

if [ -n "$REMOTE" ]; then
  git remote get-url "$REMOTE" >/dev/null 2>&1 || die "remote '$REMOTE' not found (see --remote-name)"
fi

if [ -z "$BASE" ]; then
  if [ -n "$REMOTE" ]; then
    BASE=$(git symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null | sed "s#^$REMOTE/##" || true)
  fi
  if [ -z "$BASE" ] && command -v gh >/dev/null 2>&1; then
    BASE=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || true)
  fi
  if [ -z "$BASE" ]; then
    for candidate in main master trunk; do
      if git show-ref --verify --quiet "refs/heads/$candidate"; then BASE=$candidate; break; fi
    done
  fi
fi
[ -n "$BASE" ] || die "could not determine the base branch; pass --base <name>"

if [ -n "$REMOTE" ] && git show-ref --verify --quiet "refs/remotes/$REMOTE/$BASE"; then
  BASE_REF="$REMOTE/$BASE"
else
  BASE_REF="$BASE"
fi
git rev-parse --verify --quiet "$BASE_REF^{commit}" >/dev/null || die "base ref '$BASE_REF' not found"

if [ "$DO_REMOTE" -eq 1 ]; then
  if [ -z "$REMOTE" ]; then
    warn "no remote configured; skipping remote branches"
    DO_REMOTE=0
  else
    printf 'Fetching and pruning %s ...\n' "$REMOTE"
    git fetch --prune "$REMOTE" >/dev/null 2>&1 || warn "fetch failed; using the local view of $REMOTE"
  fi
fi

# ---------------------------------------------------------------- protected branches
CURRENT=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
printf '%s\n' "$BASE" "$CURRENT" > "$TMP/keep"
if [ ${#KEEP[@]} -gt 0 ]; then
  for b in "${KEEP[@]}"; do printf '%s\n' "$b" >> "$TMP/keep"; done
fi

WORKTREE_BRANCHES=""
if git worktree list --porcelain >/dev/null 2>&1; then
  WORKTREE_BRANCHES=$(git worktree list --porcelain | awk '/^branch /{sub("^branch refs/heads/",""); print}')
fi

is_kept() { # name
  local name="$1"
  grep -qxF -- "$name" "$TMP/keep" 2>/dev/null && return 0
  printf '%s\n' "$name" | grep -Eq -- "$KEEP_REGEX" && return 0
  return 1
}

is_worktree() {
  printf '%s\n' "$WORKTREE_BRANCHES" | grep -qxF -- "$1"
}

# ---------------------------------------------------------------- GitHub data
PR_FILE="$TMP/prs.tsv"
OPEN_FILE="$TMP/open.tsv"
: > "$PR_FILE"
: > "$OPEN_FILE"
GH_OK=0
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  GH_OK=1
  gh pr list --state merged --limit 1000 \
    --json headRefName,headRefOid,number,mergedAt,isCrossRepository \
    --jq '.[] | select(.isCrossRepository|not) | [.headRefName,.headRefOid,(.number|tostring),.mergedAt] | @tsv' \
    > "$TMP/prs.raw" 2>/dev/null || true
  # Keep only the most recently merged PR per branch name.
  if [ -s "$TMP/prs.raw" ]; then
    sort -t "$TAB" -k1,1 -k4,4r "$TMP/prs.raw" | awk -F'\t' '!seen[$1]++' > "$PR_FILE"
  fi
  gh pr list --state open --limit 1000 \
    --json headRefName,isCrossRepository \
    --jq '.[] | select(.isCrossRepository|not) | .headRefName' \
    > "$OPEN_FILE" 2>/dev/null || true
else
  if command -v gh >/dev/null 2>&1; then
    warn "gh is not authenticated; squash-merged branches will be skipped. Run 'gh auth login'."
  else
    warn "gh not installed; squash-merged branches will be skipped."
  fi
fi

pr_lookup() { # branch -> "sha<TAB>number"
  awk -F'\t' -v b="$1" '$1==b {print $2 "\t" $3; exit}' "$PR_FILE"
}

has_open_pr() {
  grep -qxF -- "$1" "$OPEN_FILE" 2>/dev/null
}

# ---------------------------------------------------------------- classification
RESULTS="$TMP/results"
: > "$RESULTS"
record() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$RESULTS"; }

classify() { # kind ref name
  local kind="$1" ref="$2" name="$3"
  local commit entry prsha prnum extra

  if is_kept "$name"; then
    record "$kind" "$name" keep "protected branch"
    return 0
  fi
  if has_open_pr "$name"; then
    record "$kind" "$name" skip "an open PR still uses this branch"
    return 0
  fi
  if [ "$kind" = "local" ] && is_worktree "$name"; then
    record "$kind" "$name" skip "checked out in another worktree"
    return 0
  fi

  commit=$(git rev-parse --verify --quiet "$ref^{commit}" 2>/dev/null || true)
  if [ -z "$commit" ]; then
    record "$kind" "$name" skip "cannot resolve commit"
    return 0
  fi

  if git merge-base --is-ancestor "$commit" "$BASE_REF" 2>/dev/null; then
    record "$kind" "$name" delete "contained in $BASE_REF"
    return 0
  fi

  entry=$(pr_lookup "$name")
  if [ -z "$entry" ]; then
    record "$kind" "$name" skip "no merged PR and not contained in $BASE_REF"
    return 0
  fi
  prsha=${entry%%"$TAB"*}
  prnum=${entry#*"$TAB"}

  if [ "$commit" = "$prsha" ]; then
    record "$kind" "$name" delete "merged via PR #$prnum (tip matches PR head)"
    return 0
  fi

  # The branch tip differs from the PR head. It is only safe when the branch is a
  # stale subset of what the PR merged. Fetch the PR head if we do not have it.
  if ! git cat-file -e "$prsha^{commit}" 2>/dev/null; then
    if [ -n "$REMOTE" ] && git fetch --quiet "$REMOTE" "refs/pull/$prnum/head:refs/branch-cleanup/pr-$prnum" >/dev/null 2>&1; then
      FETCHED_REFS="$FETCHED_REFS refs/branch-cleanup/pr-$prnum"
      prsha=$(git rev-parse --verify --quiet "refs/branch-cleanup/pr-$prnum^{commit}" 2>/dev/null || printf '%s' "$prsha")
    fi
  fi

  if [ "$commit" != "$prsha" ] && git merge-base --is-ancestor "$commit" "$prsha" 2>/dev/null; then
    record "$kind" "$name" delete "stale subset of merged PR #$prnum head"
    return 0
  fi

  extra=$(git rev-list --count "$prsha..$commit" 2>/dev/null || printf '?')
  record "$kind" "$name" skip "has $extra commit(s) that were never merged (PR #$prnum)"
}

if [ "$DO_LOCAL" -eq 1 ]; then
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    classify local "refs/heads/$name" "$name"
  done <<EOF
$(git for-each-ref --format='%(refname:short)' refs/heads)
EOF
fi

if [ "$DO_REMOTE" -eq 1 ] && [ -n "$REMOTE" ]; then
  while IFS= read -r ref; do
    name=${ref#"refs/remotes/$REMOTE/"}
    [ "$name" = "HEAD" ] && continue
    [ -n "$name" ] || continue
    classify remote "$ref" "$name"
  done <<EOF
$(git for-each-ref --format='%(refname)' "refs/remotes/$REMOTE")
EOF
fi

# ---------------------------------------------------------------- plan
count() { awk -F'\t' -v s="$1" -v k="$2" '$3==s && $1==k' "$RESULTS" | wc -l | tr -d ' '; }

printf '\nRepository: %s\n' "$REPO_ROOT"
printf 'Base:       %s\n' "$BASE_REF"
printf 'Mode:       %s\n' "$([ "$APPLY" -eq 1 ] && echo apply || echo 'dry-run (pass --apply to delete)')"
printf 'PR lookup:  %s\n' "$([ "$GH_OK" -eq 1 ] && echo 'gh (squash merges detected)' || echo 'unavailable (ancestry only)')"

for kind in local remote; do
  [ "$kind" = local ] && [ "$DO_LOCAL" -eq 0 ] && continue
  [ "$kind" = remote ] && [ "$DO_REMOTE" -eq 0 ] && continue
  printf '\n%s branches\n' "$(printf '%s' "$kind" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
  for status in delete skip keep; do
    n=$(count "$status" "$kind")
    [ "$n" -eq 0 ] && continue
    case "$status" in
      delete) label="DELETE ($n)" ;;
      skip) label="SKIP ($n)" ;;
      keep) label="KEEP ($n)" ;;
    esac
    printf '  %s\n' "$label"
    awk -F'\t' -v s="$status" -v k="$kind" '$3==s && $1==k {printf "    %-56s %s\n", $2, $4}' "$RESULTS"
  done
done

total_delete=$(( $(count delete local) + $(count delete remote) ))
total_skip=$(( $(count skip local) + $(count skip remote) ))

if [ "$total_delete" -eq 0 ]; then
  printf '\nNothing to delete.\n'
  exit 0
fi

if [ "$APPLY" -eq 0 ]; then
  printf '\nDry-run only: %d branch(es) would be deleted, %d skipped. Re-run with --apply.\n' \
    "$total_delete" "$total_skip"
  exit 0
fi

# ---------------------------------------------------------------- apply
printf '\nDeleting ...\n'
deleted_local=0
deleted_remote=0
failed=0

while IFS="$TAB" read -r kind name status detail; do
  [ "$status" = delete ] || continue
  if [ "$kind" = local ]; then
    if git branch -D -- "$name" >/dev/null 2>&1; then
      printf '  local   %s\n' "$name"
      deleted_local=$((deleted_local + 1))
    else
      printf '  local   %s  FAILED\n' "$name" >&2
      failed=$((failed + 1))
    fi
  else
    if git push --quiet "$REMOTE" --delete "$name" >/dev/null 2>&1; then
      printf '  remote  %s\n' "$name"
      deleted_remote=$((deleted_remote + 1))
    else
      printf '  remote  %s  FAILED (protected or already gone?)\n' "$name" >&2
      failed=$((failed + 1))
    fi
  fi
done < "$RESULTS"

printf '\nDone: %d local, %d remote deleted, %d skipped, %d failed.\n' \
  "$deleted_local" "$deleted_remote" "$total_skip" "$failed"
[ "$failed" -eq 0 ]
