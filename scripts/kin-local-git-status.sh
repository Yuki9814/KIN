#!/bin/zsh

set -u

usage() {
  cat <<'EOF'
Usage: scripts/kin-local-git-status.sh [--watch] [task-commit-or-branch]

Without a task revision, reports whether main is clean and verified.
With a task revision, also reports whether that exact commit is in main.
--watch refreshes the result every two seconds.
EOF
}

watch_mode=false
task_revision=""

for argument in "$@"; do
  case "$argument" in
    --watch)
      watch_mode=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -n "$task_revision" ]]; then
        usage >&2
        exit 2
      fi
      task_revision="$argument"
      ;;
  esac
done

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "STATE=NOT_A_GIT_REPOSITORY"
  exit 2
}

main_worktree() {
  git -C "$repo_root" worktree list --porcelain | awk '
    /^worktree / { path = substr($0, 10) }
    $0 == "branch refs/heads/main" { print path; exit }
  '
}

render_status() {
  local main_sha verified_sha main_path main_tree task_sha task_state state

  main_sha="$(git -C "$repo_root" rev-parse refs/heads/main 2>/dev/null)" || {
    echo "STATE=MAIN_MISSING"
    return 2
  }

  verified_sha="$(git -C "$repo_root" rev-parse --verify refs/kin/verified-main 2>/dev/null || true)"
  main_path="$(main_worktree)"

  if [[ -z "$main_path" ]]; then
    main_tree="MISSING"
  elif [[ -n "$(git -C "$main_path" status --porcelain=v1 --untracked-files=all)" ]]; then
    main_tree="DIRTY"
  else
    main_tree="CLEAN"
  fi

  task_sha=""
  task_state="NOT_REQUESTED"
  if [[ -n "$task_revision" ]]; then
    task_sha="$(git -C "$repo_root" rev-parse "${task_revision}^{commit}" 2>/dev/null)" || {
      echo "STATE=TASK_REVISION_MISSING"
      echo "TASK_REVISION=$task_revision"
      return 2
    }
    if git -C "$repo_root" merge-base --is-ancestor "$task_sha" "$main_sha"; then
      task_state="MERGED"
    else
      task_state="NOT_MERGED"
    fi
  fi

  if [[ -n "$task_revision" && "$task_state" == "NOT_MERGED" ]]; then
    state="NOT_MERGED"
  elif [[ "$main_tree" == "CLEAN" && -n "$verified_sha" && "$verified_sha" == "$main_sha" ]]; then
    state="SAFE_TO_USE"
  elif [[ -n "$task_revision" && "$task_state" == "MERGED" ]]; then
    state="MERGED_BUT_UNVERIFIED"
  else
    state="UNVERIFIED_MAIN"
  fi

  echo "TIME=$(date '+%Y-%m-%d %H:%M:%S')"
  echo "STATE=$state"
  echo "MAIN_SHA=$main_sha"
  echo "VERIFIED_MAIN_SHA=${verified_sha:-MISSING}"
  echo "MAIN_TREE=$main_tree"
  echo "MAIN_WORKTREE=${main_path:-MISSING}"
  if [[ -n "$task_revision" ]]; then
    echo "TASK_SHA=$task_sha"
    echo "TASK_STATE=$task_state"
  fi
}

if [[ "$watch_mode" == true ]]; then
  while true; do
    render_status
    echo
    sleep 2
  done
else
  render_status
fi
