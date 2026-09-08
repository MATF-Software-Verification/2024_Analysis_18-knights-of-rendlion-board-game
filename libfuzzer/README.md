# Tool 4: LLVM libFuzzer

Coverage-guided fuzz testing of `XMLDocument::Parse()`, tinyxml2's main entry
point for untrusted/adversarial XML input. Covered in course labs, but
applied here specifically to this library's parsing surface.

## Why this matters for tinyxml2

Fuzzing generates *new* inputs the existing test suite and our own unit
tests never tried, guided by code coverage feedback (libFuzzer mutates
inputs that reach new code paths more often). This complements the
sanitizer runs ([`../asan/`](../asan), [`../ubsan/`](../ubsan)): those
prove no errors occur on a *fixed* set of inputs, while fuzzing actively
searches for inputs that might trigger one.

## How it works

`fuzz_parse.cpp` is a minimal harness: it takes the raw bytes libFuzzer
generates and passes them directly into `XMLDocument::Parse()`. The
harness itself makes no assumptions about what a "good" result is — a
successful parse and a graceful `XMLError` are both fine; only crashes,
hangs, and sanitizer-detected memory errors count as findings.

The fuzz binary is built with `-fsanitize=fuzzer,address`, so any memory
error libFuzzer's mutated inputs happen to trigger is caught by ASan during
the fuzzing run itself, not just by a separate tool.

**Seed corpus:** the 8 XML files already bundled with tinyxml2's own test
suite (`resources/*.xml`, including `dream.xml` and the UTF-8 test files),
giving the fuzzer realistic starting points rather than fuzzing from
nothing.

## Reproduce

```bash
./run_libfuzzer.sh [seconds]
```

Default duration is 300 seconds if not specified. Requires **Clang**
specifically — libFuzzer is a Clang/LLVM feature, not available via GCC.

For a more thorough run than the results below (which were capped for
practical turnaround time), a longer duration — e.g. `./run_libfuzzer.sh 3600`
for one hour — is recommended and only requires more wall-clock time, no
setup changes.

## Results

- **Run duration:** 121 seconds
- **Total executions:** 163,391
- **Corpus growth:** 8 seed files → 477 discovered inputs
- **Crashes / hangs / memory errors found: none**

Full output: [`fuzz_run.log`](./fuzz_run.log). Summary: [`results_summary.txt`](./results_summary.txt).

**Conclusion:** no crashing, hanging, or memory-unsafe input was found for
`XMLDocument::Parse()` within this run's execution budget. This is a
time-bounded result, not a proof of absence — a longer run explores more of
the input space (see note above on running for longer).

## Notes

- If a crash *is* found (in a longer local run), libFuzzer writes a
  `crash-<hash>` file to the build directory reproducing it exactly. The
  script detects this, fails with a non-zero exit code, and tells you to
  preserve the artifact rather than discard it — do not delete such a file
  if you ever see one; it's the minimal input that triggers the issue as
  well as being directly re-runnable (`./fuzz_parse crash-<hash>`) for
  debugging.
- The corpus (`corpus/`) is not committed to the repository (regenerated
  fresh from `resources/*.xml` each run) to avoid bloating the repo with
  binary/near-binary fuzzer-generated files.
