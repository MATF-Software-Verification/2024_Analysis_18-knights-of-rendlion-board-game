#!/bin/bash
# Runs cppcheck static analysis against tinyxml2.cpp (and transitively
# tinyxml2.h).
#
# Prerequisites: cppcheck
#   Debian/Ubuntu: sudo apt install -y cppcheck
#   macOS:         brew install cppcheck

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TINYXML2_DIR="$REPO_ROOT/tinyxml2"

if ! command -v cppcheck >/dev/null 2>&1; then
  echo "cppcheck not found. Install via 'brew install cppcheck' (macOS) or 'sudo apt install cppcheck' (Linux)."
  exit 1
fi
echo "Using: $(cppcheck --version)"

echo "=== Running cppcheck ==="
cd "$TINYXML2_DIR"
cppcheck \
  --enable=warning,style,performance,portability \
  --std=c++11 \
  --language=c++ \
  --suppress=missingIncludeSystem \
  tinyxml2.cpp \
  > "$SCRIPT_DIR/results.log" 2>&1 || true

FINDING_COUNT=$(grep -cE '\[[a-zA-Z0-9_]+\]$' "$SCRIPT_DIR/results.log" || true)
echo ""
echo "=== Done. $FINDING_COUNT findings. Full output: cppcheck/results.log ==="

echo "=== Breakdown by finding type ==="
grep -oE '\[[a-zA-Z0-9_]+\]$' "$SCRIPT_DIR/results.log" | sort | uniq -c | sort -rn \
  | tee "$SCRIPT_DIR/results_breakdown.txt"
