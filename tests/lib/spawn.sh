#!/bin/bash
# Minimal Claude spawn helper for regression tests.
# Self-contained: opens a tmux pane, accepts permission prompts, sends task,
# waits for outbox file, returns result. No dep on external spawn tools.

# Required env: TEST_PROJECT_DIR (where Claude cd's into)
# Provided functions: spawn_agent, send_to_agent, wait_for_outbox,
#                     read_outbox, kill_agent, capture_pane

_TMUX_SESSION="${TESTS_TMUX_SESSION:-only-agent-tests}"

_tmux_ensure_session() {
  tmux has-session -t "$_TMUX_SESSION" 2>/dev/null \
    || tmux new-session -d -s "$_TMUX_SESSION" -x 200 -y 50
}

_send_text_then_enter() {
  local pane="$1" text="$2"
  tmux send-keys -t "$pane" -l "$text"
  sleep 2
  tmux send-keys -t "$pane" Enter
  # Verify submission: probe for unique prefix; if still in input box, retry.
  local probe
  probe=$(printf '%s' "$text" | head -c 30)
  for _ in 1 2 3; do
    sleep 2
    local tail_lines
    tail_lines=$(tmux capture-pane -t "$pane" -p 2>/dev/null | tail -8 || true)
    if echo "$tail_lines" | grep -qF "$probe"; then
      tmux send-keys -t "$pane" Enter
    else
      return 0
    fi
  done
  return 0
}

# spawn_agent <project_dir> <initial_prompt>
# Returns spawn_id on stdout. Stores mailbox at <project_dir>/scratch/test-spawns/<id>/.
spawn_agent() {
  local project_dir="$1" prompt="$2"
  [[ -d "$project_dir" ]] || { echo "spawn_agent: dir not found: $project_dir" >&2; return 1; }

  local id="test-$(date +%s)-$$"
  local mailbox="$project_dir/scratch/test-spawns/$id"
  mkdir -p "$mailbox/inbox" "$mailbox/outbox"
  echo "$prompt" > "$mailbox/inbox/001.md"
  echo "running" > "$mailbox/status"

  _tmux_ensure_session

  local wname="agent-$id"
  tmux new-window -d -a -t "$_TMUX_SESSION:" -n "$wname" \
    "cd '$project_dir' && unset CLAUDECODE && claude --dangerously-skip-permissions; echo 'CHILD EXITED'; sleep 60"

  local pane_id
  pane_id=$(tmux list-panes -t "$_TMUX_SESSION:$wname" -F '#{pane_id}' | head -1)
  echo "$pane_id" > "$mailbox/.pane"
  echo "$wname" > "$mailbox/.window"

  # Init phase: accept whichever permission prompt appears.
  # Two known prompts: "Yes, I trust this folder" (folder trust) and
  # "Yes, I accept" (bypass-permissions). Either may appear or both, in any order.
  local init_done=false
  for _ in $(seq 1 60); do
    sleep 1
    local content
    content=$(tmux capture-pane -t "$pane_id" -p 2>/dev/null || true)
    if echo "$content" | grep -q "CHILD EXITED"; then
      echo "spawn_agent: claude exited unexpectedly" >&2
      echo "dead" > "$mailbox/status"
      return 1
    fi
    if echo "$content" | grep -q "Yes, I trust this folder"; then
      tmux send-keys -t "$pane_id" Enter
      sleep 2
      continue
    fi
    if echo "$content" | grep -q "Yes, I accept"; then
      tmux send-keys -t "$pane_id" Down
      sleep 1
      tmux send-keys -t "$pane_id" Enter
      sleep 2
      continue
    fi
    if echo "$content" | grep -q "bypass permissions" && ! echo "$content" | grep -q "Yes, I"; then
      init_done=true
      break
    fi
  done
  $init_done || echo "spawn_agent: warn: init phase timeout, proceeding anyway" >&2

  local task_msg="Read the task in $mailbox/inbox/001.md. Execute it fully. When done, use the Write tool to write your complete result to $mailbox/outbox/001.md"
  _send_text_then_enter "$pane_id" "$task_msg"

  echo "$id"
}

# send_to_agent <id> <prompt>
send_to_agent() {
  local id="$1" prompt="$2"
  local mailbox project_dir
  project_dir=$(_resolve_project_dir "$id") || return 1
  mailbox="$project_dir/scratch/test-spawns/$id"

  local pane_id
  pane_id=$(cat "$mailbox/.pane")

  local n
  n=$(ls "$mailbox/inbox/" 2>/dev/null | wc -l | tr -d ' ')
  n=$((n + 1))
  local padded
  padded=$(printf "%03d" "$n")
  echo "$prompt" > "$mailbox/inbox/$padded.md"

  local task_msg="Read the task in $mailbox/inbox/$padded.md. Execute it fully. When done, use the Write tool to write your complete result to $mailbox/outbox/$padded.md"
  _send_text_then_enter "$pane_id" "$task_msg"
  echo "$padded"
}

# wait_for_outbox <id> [<num=001>] [<timeout_sec=300>]
wait_for_outbox() {
  local id="$1" num="${2:-001}" timeout="${3:-300}"
  local mailbox project_dir
  project_dir=$(_resolve_project_dir "$id") || return 1
  mailbox="$project_dir/scratch/test-spawns/$id"
  local file="$mailbox/outbox/$num.md"

  local elapsed=0
  while [[ ! -s "$file" ]]; do
    sleep 3
    elapsed=$((elapsed + 3))
    if [[ $elapsed -ge $timeout ]]; then
      echo "wait_for_outbox: timeout after ${timeout}s waiting for $file" >&2
      return 1
    fi
  done
  return 0
}

# read_outbox <id> [<num=001>]
read_outbox() {
  local id="$1" num="${2:-001}"
  local mailbox project_dir
  project_dir=$(_resolve_project_dir "$id") || return 1
  mailbox="$project_dir/scratch/test-spawns/$id"
  cat "$mailbox/outbox/$num.md"
}

# capture_pane <id>  (last 50 lines of TUI for debugging)
capture_pane() {
  local id="$1"
  local mailbox project_dir
  project_dir=$(_resolve_project_dir "$id") || return 1
  mailbox="$project_dir/scratch/test-spawns/$id"
  local pane_id
  pane_id=$(cat "$mailbox/.pane" 2>/dev/null) || return 1
  tmux capture-pane -t "$pane_id" -p 2>/dev/null | tail -50
}

# kill_agent <id>  (kill pane, mark dead, remove mailbox)
kill_agent() {
  local id="$1"
  local mailbox project_dir
  project_dir=$(_resolve_project_dir "$id") || return 0
  mailbox="$project_dir/scratch/test-spawns/$id"
  if [[ -f "$mailbox/.pane" ]]; then
    tmux kill-pane -t "$(cat "$mailbox/.pane")" 2>/dev/null || true
  fi
  rm -rf "$mailbox"
}

# Internal: find which project dir owns this spawn id.
# Looks under TEST_PROJECT_DIR if set, otherwise searches likely roots.
_resolve_project_dir() {
  local id="$1"
  if [[ -n "${TEST_PROJECT_DIR:-}" && -d "$TEST_PROJECT_DIR/scratch/test-spawns/$id" ]]; then
    echo "$TEST_PROJECT_DIR"
    return 0
  fi
  for root in "$HOME/only-agent" "$HOME/ai-workspace-vault"; do
    if [[ -d "$root/scratch/test-spawns/$id" ]]; then
      echo "$root"
      return 0
    fi
  done
  echo "_resolve_project_dir: unknown id $id" >&2
  return 1
}
