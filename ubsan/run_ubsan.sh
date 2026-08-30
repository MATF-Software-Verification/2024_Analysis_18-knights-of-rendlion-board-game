#!/bin/bash
# Builds tinyxml2, the existing xmltest.cpp suite, and our self-authored
# unit_tests.cpp with UndefinedBehaviorSanitizer instrumentation, runs both,
# and reports whether any undefined-behavior issues (signed integer
# overflow, misaligned pointer access, invalid enum values, etc.) were
# detected.
#
# Built and reported separately from AddressSanitizer (see ../asan/) since
# the two catch different classes of bugs.
#
# Prerequisites: g++ (or clang++) with UBSan support (standard on both
# Linux/GCC and macOS/Clang, no extra install needed).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TINYXML2_DIR="$REPO_ROOT/tinyxml2"
BUILD_DIR="$TINYXML2_DIR/build_ubsan"

echo "=== 1. Compiling with UndefinedBehaviorSanitizer instrumentation ==="
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
g++ -std=c++11 -g -O1 -fsanitize=undefined -fno-omit-frame-pointer -I.. -c ../xmltest.cpp -o xmltest.o
g++ -std=c++11 -g -O1 -fsanitize=undefined -fno-omit-frame-pointer -I.. -c ../tinyxml2.cpp -o tinyxml2.o
g++ -std=c++11 -g -O1 -fsanitize=undefined -fno-omit-frame-pointer -I.. -c "$SCRIPT_DIR/../tests/unit_tests.cpp" -o unit_tests.o
g++ -fsanitize=undefined xmltest.o tinyxml2.o -o xmltest_ubsan
g++ -fsanitize=undefined unit_tests.o tinyxml2.o -o unit_tests_ubsan

echo "=== 2. Running existing xmltest.cpp suite under UBSan ==="
( cd "$TINYXML2_DIR" && ./build_ubsan/xmltest_ubsan ) | tee "$SCRIPT_DIR/results_xmltest.log"

echo "=== 3. Running our self-authored unit tests under UBSan ==="
( cd "$TINYXML2_DIR" && ./build_ubsan/unit_tests_ubsan ) | tee "$SCRIPT_DIR/results_unit_tests.log"

echo "=== 4. Checking for UBSan runtime error reports ==="
if grep -qE "runtime error:|SUMMARY: UndefinedBehaviorSanitizer" \
    "$SCRIPT_DIR/results_xmltest.log" "$SCRIPT_DIR/results_unit_tests.log"; then
  echo "UndefinedBehaviorSanitizer reported issues -- see results_*.log above."
  exit 1
else
  echo "No UndefinedBehaviorSanitizer errors detected in either test run."
fi
