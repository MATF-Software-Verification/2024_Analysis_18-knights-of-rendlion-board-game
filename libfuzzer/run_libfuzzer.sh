#!/bin/bash
# Builds a libFuzzer harness (fuzz_parse.cpp) that feeds arbitrary byte
# sequences into tinyxml2's XMLDocument::Parse(), seeded from the project's
# own existing test XML files, and fuzzes for a fixed duration.
#
# Requires Clang (libFuzzer is a Clang/LLVM feature, not available via GCC).
#   Debian/Ubuntu: sudo apt install -y clang
#   macOS:         Xcode Command Line Tools already include a libFuzzer-
#                   capable clang -- run `xcode-select --install` if needed.
#
# Usage:
#   ./run_libfuzzer.sh [seconds]
#   Default duration is 300 seconds (5 minutes) if not specified.

set -e

DURATION="${1:-300}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TINYXML2_DIR="$REPO_ROOT/tinyxml2"
BUILD_DIR="$TINYXML2_DIR/build_fuzz"

# On some macOS setups, the Command Line Tools clang++ accepts
# -fsanitize=fuzzer at compile time but is missing the actual libFuzzer
# runtime archive at link time. If CXX isn't already set, prefer a
# Homebrew LLVM clang++ when present, since that ships the full runtime.
if [ -z "$CXX" ]; then
  if [ -x /opt/homebrew/opt/llvm/bin/clang++ ]; then
    CXX=/opt/homebrew/opt/llvm/bin/clang++
  elif [ -x /usr/local/opt/llvm/bin/clang++ ]; then
    CXX=/usr/local/opt/llvm/bin/clang++
  else
    CXX=clang++
  fi
fi
echo "Using compiler: $CXX ($($CXX --version | head -1))"

echo "=== 1. Compiling fuzz target with libFuzzer + AddressSanitizer ==="
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
$CXX -std=c++11 -g -O1 -fsanitize=fuzzer,address -I.. -c ../tinyxml2.cpp -o tinyxml2.o
$CXX -std=c++11 -g -O1 -fsanitize=fuzzer,address -I.. -c "$SCRIPT_DIR/fuzz_parse.cpp" -o fuzz_parse.o
$CXX -fsanitize=fuzzer,address tinyxml2.o fuzz_parse.o -o fuzz_parse

echo "=== 2. Seeding corpus from the project's own existing test XML files ==="
mkdir -p corpus
cp "$TINYXML2_DIR"/resources/*.xml corpus/
echo "Seed corpus: $(ls corpus | wc -l | tr -d ' ') files"

echo "=== 3. Fuzzing for ${DURATION} seconds ==="
./fuzz_parse -max_total_time="$DURATION" corpus/ 2>&1 | tee "$SCRIPT_DIR/fuzz_run.log"

echo "=== 4. Checking for crash/timeout/OOM artifacts ==="
if ls "$BUILD_DIR" 2>/dev/null | grep -qE "^(crash-|timeout-|oom-)"; then
  echo "Fuzzer found a crashing/hanging input! Artifact files:"
  ls "$BUILD_DIR" | grep -E "^(crash-|timeout-|oom-)"
  echo "Copy the artifact file into libfuzzer/ and report it -- do not discard it."
  exit 1
else
  echo "No crash/timeout/OOM artifacts produced."
fi

echo "=== 5. Saving corpus statistics ==="
{
  echo "Fuzz run: $(date)"
  echo "Duration requested: ${DURATION}s"
  echo "Seed corpus size: $(ls "$TINYXML2_DIR"/resources/*.xml | wc -l | tr -d ' ') files"
  echo "Final corpus size: $(ls corpus | wc -l | tr -d ' ') files"
  echo ""
  echo "--- Full run summary (see fuzz_run.log for complete output) ---"
  tail -20 "$SCRIPT_DIR/fuzz_run.log"
} > "$SCRIPT_DIR/results_summary.txt"

echo ""
echo "Done. See libfuzzer/fuzz_run.log (full output) and libfuzzer/results_summary.txt (summary)."