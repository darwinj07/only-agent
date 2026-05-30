#!/bin/bash
# Minimal assertions for regression tests. Set FAIL_COUNT=0 in scenario.

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-expected substring not found}"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  FAIL: $msg"
    echo "    needle: $needle"
    echo "    haystack head: $(printf '%s' "$haystack" | head -c 200)"
    FAIL_COUNT=$((${FAIL_COUNT:-0} + 1))
    return 1
  fi
  echo "  ok: $msg"
  return 0
}

assert_not_contains() {
  local haystack="$1" needle="$2" msg="${3:-unexpected substring found}"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  FAIL: $msg"
    echo "    found: $needle"
    FAIL_COUNT=$((${FAIL_COUNT:-0} + 1))
    return 1
  fi
  echo "  ok: $msg"
  return 0
}

assert_file_exists() {
  local path="$1" msg="${2:-file should exist: $1}"
  if [[ ! -f "$path" ]]; then
    echo "  FAIL: $msg"
    FAIL_COUNT=$((${FAIL_COUNT:-0} + 1))
    return 1
  fi
  echo "  ok: $msg"
  return 0
}

assert_dir_not_exists() {
  local path="$1" msg="${2:-dir should not exist: $1}"
  if [[ -d "$path" ]]; then
    echo "  FAIL: $msg"
    FAIL_COUNT=$((${FAIL_COUNT:-0} + 1))
    return 1
  fi
  echo "  ok: $msg"
  return 0
}
