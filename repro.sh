#!/usr/bin/env bash
set -euo pipefail

DEVENV_REV="${DEVENV_REV:-863b4204725efaeeb73811e376f928232b720646}"
KEEP_REPRO_DIR="${KEEP_REPRO_DIR:-0}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
workdir="$(mktemp -d "${TMPDIR:-/tmp}/devenv-import-cache-repro.XXXXXX")"

cleanup() {
  if [ "$KEEP_REPRO_DIR" = "1" ]; then
    printf 'Keeping repro directory: %s\n' "$workdir" >&2
  else
    rm -rf "$workdir"
  fi
}
trap cleanup EXIT

if [ -n "${DEVENV_BIN:-}" ]; then
  devenv_cmd=("$DEVENV_BIN")
else
  devenv_cmd=(nix --accept-flake-config run "github:cachix/devenv/${DEVENV_REV}" --)
fi

run_devenv() {
  "${devenv_cmd[@]}" --no-tui "$@"
}

capture() {
  local label="$1"
  shift

  printf ':: %s\n' "$label" >&2
  local output status
  set +e
  output="$(run_devenv "$@" 2>&1)"
  status=$?
  set -e

  if [ "$status" -ne 0 ]; then
    printf 'ERROR: %s failed with exit code %s\n' "$label" "$status" >&2
    printf '%s\n' "$output" >&2
    exit "$status"
  fi

  printf '%s\n' "$output"
}

require_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"

  if ! grep -Fq "$needle" <<<"$haystack"; then
    printf 'ERROR: expected %s to contain %q\n' "$label" "$needle" >&2
    printf '%s\n' "$haystack" >&2
    exit 1
  fi
}

copy_fixture() {
  (
    cd "$repo_root"
    tar \
      --exclude=.git \
      --exclude=.devenv \
      --exclude=.direnv \
      --exclude=devenv.lock \
      -cf - .
  ) | tar -xf - -C "$workdir"
}

rewrite_leaf_to_v2() {
  perl -0pi \
    -e 's/leaf-v1/leaf-v2/g; s/repro:task-v1/repro:task-v2/g; s/proc-v1/proc-v2/g' \
    "$workdir/modules/lower.nix"
}

main() {
  copy_fixture
  cd "$workdir"

  printf 'Using temp repro directory: %s\n' "$workdir" >&2
  printf 'Using devenv: %s\n' "${devenv_cmd[*]}" >&2

  local seed_shell seed_eval seed_tasks seed_processes
  seed_shell="$(capture "seed shell cache" --refresh-eval-cache shell -- bash -c 'printf "%s\n" "$REPRO_VALUE"')"
  seed_eval="$(capture "seed env eval" eval env.REPRO_VALUE)"
  seed_tasks="$(capture "seed tasks list" tasks list)"
  seed_processes="$(capture "seed processes eval" eval processes)"

  require_contains "$seed_shell" "leaf-v1" "seed shell output"
  require_contains "$seed_eval" "leaf-v1" "seed env eval output"
  require_contains "$seed_tasks" "repro:task-v1" "seed tasks output"
  require_contains "$seed_processes" "proc-v1" "seed processes output"

  rewrite_leaf_to_v2

  local cached_shell cached_eval cached_tasks cached_processes
  local fresh_shell fresh_eval fresh_tasks fresh_processes
  cached_shell="$(capture "cached shell after lower module edit" shell -- bash -c 'printf "%s\n" "$REPRO_VALUE"')"
  cached_eval="$(capture "cached env eval after lower module edit" eval env.REPRO_VALUE)"
  cached_tasks="$(capture "cached tasks list after lower module edit" tasks list)"
  cached_processes="$(capture "cached processes eval after lower module edit" eval processes)"

  fresh_shell="$(capture "fresh shell after lower module edit" --no-eval-cache shell -- bash -c 'printf "%s\n" "$REPRO_VALUE"')"
  fresh_eval="$(capture "fresh env eval after lower module edit" --no-eval-cache eval env.REPRO_VALUE)"
  fresh_tasks="$(capture "fresh tasks list after lower module edit" --no-eval-cache tasks list)"
  fresh_processes="$(capture "fresh processes eval after lower module edit" --no-eval-cache eval processes)"

  require_contains "$fresh_shell" "leaf-v2" "fresh shell output"
  require_contains "$fresh_eval" "leaf-v2" "fresh env eval output"
  require_contains "$fresh_tasks" "repro:task-v2" "fresh tasks output"
  require_contains "$fresh_processes" "proc-v2" "fresh processes output"

  local stale=0
  if grep -Fq "leaf-v1" <<<"$cached_shell"; then stale=1; fi
  if grep -Fq "leaf-v1" <<<"$cached_eval"; then stale=1; fi
  if grep -Fq "repro:task-v1" <<<"$cached_tasks"; then stale=1; fi
  if grep -Fq "proc-v1" <<<"$cached_processes"; then stale=1; fi

  printf '\n== Cached outputs after edit ==\n'
  printf '\n-- shell --\n%s\n' "$cached_shell"
  printf '\n-- eval env --\n%s\n' "$cached_eval"
  printf '\n-- tasks --\n%s\n' "$cached_tasks"
  printf '\n-- processes --\n%s\n' "$cached_processes"

  printf '\n== Fresh outputs after edit ==\n'
  printf '\n-- shell --\n%s\n' "$fresh_shell"
  printf '\n-- eval env --\n%s\n' "$fresh_eval"
  printf '\n-- tasks --\n%s\n' "$fresh_tasks"
  printf '\n-- processes --\n%s\n' "$fresh_processes"

  if [ "$stale" -eq 1 ]; then
    printf '\nREPRODUCED: cached devenv output stayed stale after imported module changed.\n'
    exit 0
  fi

  printf '\nNOT REPRODUCED: cached output matched the changed imported module.\n'
  exit 2
}

main "$@"
