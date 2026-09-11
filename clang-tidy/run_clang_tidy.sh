#!/bin/bash
# Runs clang-tidy against tinyxml2.cpp using the check set defined in
# .clang-tidy in this directory.
#
# Prerequisites: cmake, clang-tidy
#   Debian/Ubuntu: sudo apt install -y cmake clang-tidy
#   macOS:         brew install llvm   (clang-tidy ships with LLVM;
#                   Xcode Command Line Tools alone do not include it)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TINYXML2_DIR="$REPO_ROOT/tinyxml2"
BUILD_DIR="$TINYXML2_DIR/build_tidy"

# Resolve clang-tidy, preferring a Homebrew LLVM install on macOS if the
# plain `clang-tidy` isn't on PATH (Xcode Command Line Tools don't ship it).
# When we do use the Homebrew LLVM clang-tidy, we also point CMake at the
# matching Homebrew clang++ for the configure step below -- mixing Apple's
# system clang++ (used to generate compile_commands.json) with Homebrew's
# clang-tidy causes header-resolution errors (e.g. "'cctype' file not
# found"), since the two toolchains don't agree on standard library search
# paths. Using the same compiler for both steps avoids that entirely.
CLANG_TIDY_CXX=""
if command -v clang-tidy >/dev/null 2>&1; then
  CLANG_TIDY=clang-tidy
elif [ -x /opt/homebrew/opt/llvm/bin/clang-tidy ]; then
  CLANG_TIDY=/opt/homebrew/opt/llvm/bin/clang-tidy
  CLANG_TIDY_CXX=/opt/homebrew/opt/llvm/bin/clang++
elif [ -x /usr/local/opt/llvm/bin/clang-tidy ]; then
  CLANG_TIDY=/usr/local/opt/llvm/bin/clang-tidy
  CLANG_TIDY_CXX=/usr/local/opt/llvm/bin/clang++
else
  echo "clang-tidy not found. Install via 'brew install llvm' (macOS) or 'sudo apt install clang-tidy' (Linux)."
  exit 1
fi
echo "Using: $CLANG_TIDY ($($CLANG_TIDY --version | head -1))"

echo "=== 1. Generating compile_commands.json ==="
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
if [ -n "$CLANG_TIDY_CXX" ] && [ -x "$CLANG_TIDY_CXX" ]; then
  echo "Configuring with matching compiler: $CLANG_TIDY_CXX"
  cmake -S "$TINYXML2_DIR" -B "$BUILD_DIR" \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_COMPILER="$CLANG_TIDY_CXX" > /dev/null
else
  cmake -S "$TINYXML2_DIR" -B "$BUILD_DIR" \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCMAKE_BUILD_TYPE=Release > /dev/null
fi

echo "=== 2. Running clang-tidy (config: $SCRIPT_DIR/.clang-tidy) ==="
cd "$TINYXML2_DIR"
"$CLANG_TIDY" -p "$BUILD_DIR" --config-file="$SCRIPT_DIR/.clang-tidy" tinyxml2.cpp \
  > "$SCRIPT_DIR/results.log" 2>&1 || true

if grep -q "Found compiler error(s)" "$SCRIPT_DIR/results.log"; then
  echo ""
  echo "WARNING: clang-tidy reported compiler errors, not just style warnings."
  echo "Results may be incomplete. Check results.log for 'error:' lines before trusting the warning count."
fi

WARNING_COUNT=$(grep -c "warning:" "$SCRIPT_DIR/results.log" || true)
echo ""
echo "=== Done. $WARNING_COUNT warnings found. Full output: clang-tidy/results.log ==="

echo "=== 3. Warning breakdown by check ==="
grep -oE '\[[a-z0-9-]+(-[a-z0-9]+)*\]$' "$SCRIPT_DIR/results.log" | sort | uniq -c | sort -rn \
  | tee "$SCRIPT_DIR/results_breakdown.txt"