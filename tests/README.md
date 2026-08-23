# Tool 1: Unit tests + coverage (lcov)

Combines the project's existing test suite (`xmltest.cpp`, 528 cases) with a
set of **self-authored unit tests** (`unit_tests.cpp`) written specifically
to cover functionality left untested by the existing suite. Coverage
(lcov/gcov) is measured across both.

## Why self-authored tests, not just the existing suite

Running `xmltest.cpp` alone measures the coverage of tests we didn't write —
that's a baseline, not a testing deliverable. `unit_tests.cpp` was written by
first measuring xmltest.cpp's own coverage, identifying concretely uncovered
functions/branches, and writing targeted tests for them:

- **`XMLUtil::ToBool` word forms** — existing tests only exercise the numeric
  path (`"0"`/`"1"`); the `"true"/"True"/"TRUE"/"false"/"False"/"FALSE"`
  string branches, and the invalid-input path, were entirely untested.
- **`XMLNode::ChildElementCount()`** (both the unfiltered and name-filtered
  overloads) — not called anywhere in the existing suite.
- **Malformed numeric character references** — existing tests cover
  out-of-range values (e.g. `&#110000;`) but not structurally malformed ones:
  an invalid digit (`&#zz;`, `&#xzz;`) or a reference with no terminating
  semicolon anywhere in the remaining document (`&#65` with no `;`). These
  are realistic adversarial-input cases given the library parses arbitrary
  user-supplied XML.

Every assertion in `unit_tests.cpp` was verified against the library's
actual real behavior (via a throwaway probe program) before being written
as a formal test — not guessed.

## Reproduce

```bash
./run_coverage.sh
```

Requires `g++` and `lcov` (see comment at top of the script for install
commands per platform).

## Results

| Platform / compiler | Lines | Functions |
|---|---|---|
| Linux, GCC 13.3.0 | 92.2% (1350/1464) | 92.8% (193/208) |
| macOS (Apple Silicon), AppleClang/LLVM gcov | 91.7% (1607/1752) | 92.8% (205/221) |

Raw line/function *counts* differ between GCC and Clang because the two
compilers instrument inline/template code differently (different total
"instrumentable" lines), but the resulting **percentages agree closely**,
which is a useful cross-check that the measurement itself is meaningful
and not a toolchain artifact.

For reference, `xmltest.cpp` alone (before adding our own unit tests), on
Linux/GCC: 90.8% lines (1330/1464), 91.8% functions (191/208) — i.e. our
tests add +20 lines / +2 functions of coverage on that platform.

`unit_tests.cpp`: **16/16 assertions pass on both platforms.**

See [`coverage_summary.txt`](./coverage_summary.txt) for the combined lcov
summary and [`coverage.info`](./coverage.info) for the full trace data
(regenerate an HTML view locally via `genhtml coverage.info -o html`).

## Notes

- Coverage is measured against `tinyxml2.cpp` only — `tinyxml2.h` and the
  test files themselves are excluded, since we're measuring coverage of the
  library, not of the tests.
- Branch coverage was not available in this lcov/gcov configuration; line
  and function coverage are reported instead.
- The +2 functions gained (191→193) correspond exactly to the two
  `ChildElementCount` overloads we targeted — a useful sanity check that the
  new tests are doing what we intended.
