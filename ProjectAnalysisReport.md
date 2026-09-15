# Project Analysis Report

## 1. General Information

This report documents the software verification analysis of TinyXML2
performed for the Software Verification course at the Faculty of
Mathematics, University of Belgrade.

|  |  |
| --- | --- |
| Author | Darko Mladenovski, 1067/2024 |
| Analysis repository | `2024_Analysis_18-knights-of-rendlion-board-game` |
| Original project | [TinyXML2](https://github.com/leethomason/tinyxml2) |
| Analyzed branch | `master` |
| Analyzed commit | `8224e427b655b83dae5e2298f1e6919523a78737` |
| Project reference | Git submodule in `tinyxml2/` |

## 2. Project Description

TinyXML2 is a small, self-contained C++ library for parsing, constructing,
modifying, and printing XML documents. It has no STL or external
dependencies and consists almost entirely of two files, which is unusual
for a project of this kind and made it practical to read and understand
the full implementation within the scope of this analysis.

The library supports:

- parsing XML text into an in-memory DOM tree (`XMLDocument`, `XMLNode`,
  `XMLElement`, `XMLAttribute`, `XMLText`, `XMLComment`, `XMLDeclaration`,
  `XMLUnknown`);
- programmatic construction and modification of documents;
- typed attribute and text access and conversion (int, unsigned, `int64_t`,
  `uint64_t`, `bool`, `float`, `double`, string);
- printing/serialization back to XML text, including a streaming
  `XMLPrinter` mode;
- custom memory management via a pool allocator (`MemPool`, `DynArray`).

The source tree consists of:

- `tinyxml2.h` / `tinyxml2.cpp` — the entire library implementation;
- `xmltest.cpp` — the project's own bundled test suite (528 cases);
- `resources/` — XML files used by the bundled test suite (`dream.xml`,
  UTF-8 test files, and others), reused in this analysis as fuzzing seed
  inputs.

## 3. Analysis Goals and Scope

The goal is to look for correctness defects, memory-safety errors,
undefined behavior, and static-analysis findings by applying six
verification tools and techniques, combining dynamic methods (execution
against real and fuzzer-generated inputs) with static methods (analysis
without execution).

Unit testing, coverage measurement, both sanitizers, and fuzzing all
exercise the parsing and DOM-construction code paths in `tinyxml2.cpp`
directly. clang-tidy and Cppcheck statically inspect the full
implementation, including code paths not reachable by the test suite.

The analysis does not include the library's file I/O functions
(`LoadFile`/`SaveFile`) under the sanitizers or fuzzer, since the fuzz and
sanitizer harnesses parse in-memory buffers directly; file I/O is,
however, covered by the existing test suite and by static analysis.
Multi-threaded use of the library was not tested, since the library itself
does not provide any threading and is documented as not being
thread-safe.

## 4. Environment

The committed results were produced on two separate environments, since
the analysis was independently verified on both before being finalized:

| Component | Linux | macOS (Apple Silicon) |
| --- | --- | --- |
| Operating system | Ubuntu 24.04 | macOS (Homebrew toolchain) |
| CMake | 3.28.3 | (system CMake via Homebrew) |
| C++ compiler | GCC 13.3.0 | AppleClang (build verification); Homebrew LLVM Clang for analysis tools |
| C++ standard | C++11 | C++11 |
| lcov | 2.0-1 | 2.5_1 |
| clang-tidy | 18.1.3 | 23.1.0 (Homebrew LLVM) |
| Cppcheck | 2.13.0 | 2.21.0 |
| Clang (for libFuzzer) | 18 | Homebrew LLVM Clang |

Where results differ between the two environments, this is stated
explicitly in the relevant subsection below, along with the reason (tool
version differences enabling additional checks, or compiler differences in
coverage instrumentation) rather than being treated as an inconsistency.

## 5. Reports for Applied Tools

### 5.1 Unit Testing and lcov Coverage

#### 5.1.1 Motivation

The project's own bundled test suite (`xmltest.cpp`) was extended with a
self-authored suite (`tests/unit_tests.cpp`) rather than relied upon
alone, since running only pre-existing tests does not itself demonstrate
testing work. The additional tests were written after first measuring the
bundled suite's own coverage and identifying concrete, specific gaps.

#### 5.1.2 Test Scope

`unit_tests.cpp` contains 16 assertions targeting three areas the bundled
suite's coverage report showed were untested:

- the word-form branches of `XMLUtil::ToBool` (`"true"`/`"True"`/`"TRUE"`,
  `"false"`/`"False"`/`"FALSE"`, and its invalid-input path — the bundled
  suite only exercises the numeric `"0"`/`"1"` form);
- both overloads of `XMLNode::ChildElementCount()` (unfiltered and
  name-filtered), not called anywhere in the bundled suite;
- malformed numeric character references — an invalid decimal digit
  (`&#zz;`), an invalid hex digit (`&#xzz;`), and a reference with no
  terminating semicolon anywhere in the remaining document (`&#65` with no
  `;`) — the bundled suite covers out-of-range values but not structurally
  malformed ones.

Every expected value in `unit_tests.cpp` was verified against the
library's actual behavior with a standalone probe program before being
written as a formal assertion.

#### 5.1.3 Reproduction

From the repository root, run:

```bash
./tests/run_coverage.sh
```

The script compiles `tinyxml2.cpp`, `xmltest.cpp`, and `unit_tests.cpp`
with `--coverage` instrumentation, runs both resulting binaries against a
shared instrumented object file so their coverage accumulates, and
generates an lcov report.

#### 5.1.4 Results

The combined test result is:

```text
xmltest.cpp:    Pass 528, Fail 0
unit_tests.cpp: 16 passed, 0 failed
```

The filtered coverage result (Linux, GCC 13.3.0) is:

```text
lines......: 92.2% (1350 of 1464 lines)
functions..: 92.8% (193 of 208 functions)
```

On macOS (Clang/LLVM gcov), the result is:

```text
lines......: 91.7% (1607 of 1752 lines)
functions..: 92.8% (205 of 221 functions)
```

The differing total line counts (1464 vs. 1752) reflect how GCC and Clang
instrument inline/template code differently; the resulting percentages
agree closely, which supports the measurement being meaningful rather than
a toolchain artifact. Adding the self-authored tests to the bundled suite
alone raised Linux coverage from 90.8%/91.8% to 92.2%/92.8% — a gain of
exactly two functions, matching the two `ChildElementCount` overloads
targeted.

Coverage summaries are stored in `tests/coverage_summary.txt`, with full
trace data in `tests/coverage.info`.

### 5.2 AddressSanitizer

#### 5.2.1 Motivation and Scope

AddressSanitizer was selected instead of Valgrind for memory-error
detection, since it is not covered in course labs and TinyXML2 performs
extensive manual, pointer-based memory management (a custom `MemPool`
allocator, hand-rolled string and entity parsing) over untrusted input,
making it a strong candidate for compiler-based memory-safety
instrumentation. It runs the same 544 test cases as Section 5.1 (528
bundled plus 16 self-authored), instrumented to detect memory errors
rather than measure coverage.

#### 5.2.2 Reproduction

From the repository root, run:

```bash
./asan/run_asan.sh
```

The script compiles `tinyxml2.cpp`, `xmltest.cpp`, and `unit_tests.cpp`
with `-g -O1 -fsanitize=address -fno-omit-frame-pointer`, runs both
resulting binaries, and checks the output for AddressSanitizer error
markers independently of the tests' own pass/fail count.

#### 5.2.3 Results

The unit tests pass under AddressSanitizer on both platforms. The result
is:

```text
xmltest.cpp:    528 passed, 0 failed, 0 AddressSanitizer errors
unit_tests.cpp: 16 passed, 0 failed, 0 AddressSanitizer errors
```

No heap, stack, or global buffer overflows, use-after-free, double-free,
or (via the LeakSanitizer component bundled with ASan on Linux) memory
leaks were detected.

Full logs are stored in `asan/results_xmltest.log` and
`asan/results_unit_tests.log`.

### 5.3 UndefinedBehaviorSanitizer

#### 5.3.1 Motivation and Scope

UndefinedBehaviorSanitizer was run as a separate tool from
AddressSanitizer, built and reported independently rather than combined
into a single sanitizer flag, since the two detect distinct classes of
defects (memory-safety violations versus violations of specific C++
standard preconditions such as signed-integer overflow or misaligned
access). It runs the same 544 test cases as Sections 5.1–5.2.

#### 5.3.2 Reproduction

From the repository root, run:

```bash
./ubsan/run_ubsan.sh
```

The script rebuilds the same two binaries with `-fsanitize=undefined`
instead, and checks every output line for the literal string
`runtime error:`, since UBSan does not halt the program by default on a
violation — a finding could otherwise pass unnoticed inside an
apparently-successful test run.

#### 5.3.3 Results

```text
xmltest.cpp:    528 passed, 0 failed, 0 UndefinedBehaviorSanitizer errors
unit_tests.cpp: 16 passed, 0 failed, 0 UndefinedBehaviorSanitizer errors
```

No signed-integer overflow, misaligned access, invalid enum value, or
similar undefined-behavior violation was triggered by any of the 544 test
cases on either platform.

Full logs are stored in `ubsan/results_xmltest.log` and
`ubsan/results_unit_tests.log`.

### 5.4 LLVM libFuzzer

#### 5.4.1 Motivation and Scope

Fuzzing was applied specifically to `XMLDocument::Parse()`, the library's
entry point for untrusted, potentially adversarial XML input. Unlike
Sections 5.1–5.3, which exercise a fixed set of inputs, fuzzing generates
new inputs under coverage feedback, searching for inputs the fixed test
suite does not already cover. The fuzz harness (`libfuzzer/fuzz_parse.cpp`)
is built with `-fsanitize=fuzzer,address`, so any memory-safety violation
triggered by a generated input is also caught during the run.

#### 5.4.2 Reproduction

From the repository root, run:

```bash
./libfuzzer/run_libfuzzer.sh [seconds]
```

The script compiles the fuzz target, seeds the corpus from the project's
own bundled test XML files (`tinyxml2/resources/*.xml`), and fuzzes for
the given duration (default 300 seconds). Building this target requires
Clang specifically, since libFuzzer is LLVM-specific tooling not available
through GCC.

#### 5.4.3 Results

```text
Run duration:      301 seconds
Total executions:  2,384,729
Crashes/hangs/OOM: none
```

No crashing, hanging, or memory-unsafe input was found within this run's
execution budget. This is a time-bounded result rather than a proof of
absence of defects, but the absence of any finding across nearly 2.4
million adversarially-mutated inputs, well beyond what the fixed test
suite exercises, is a meaningful positive result given the library's
manual, pointer-based parsing of untrusted text.

The full run log is stored in `libfuzzer/fuzz_run.log`, with a summary in
`libfuzzer/results_summary.txt`.

### 5.5 clang-tidy

#### 5.5.1 Scope and Configuration

clang-tidy checked `tinyxml2.cpp` (and, transitively, `tinyxml2.h`) with
the `bugprone-*`, `cert-*`, `clang-analyzer-*`, `performance-*`, and
`readability-*` check categories enabled via `.clang-tidy`, with three
checks explicitly excluded: `readability-identifier-length` (flags
conventional short names such as `p`, `q`, `i` that are standard in dense
parsing code, and alone accounted for 58% of all warnings before
exclusion), `readability-magic-numbers` (a parser is inherently full of
small constants with obvious meaning from context), and
`readability-implicit-bool-conversion` (a pervasive, idiomatic C-style
pattern throughout the existing codebase). Style and performance findings
were included; the "style tool" role in this project's six required tools
is filled by clang-tidy as a whole, per the course's limit of one such
tool.

The analysis is reproduced from the repository root with:

```bash
./clang-tidy/run_clang_tidy.sh
```

The script generates `compile_commands.json` via CMake before invoking
clang-tidy. On macOS, the script configures CMake to use the same
Homebrew LLVM `clang++` as the `clang-tidy` binary being used; mixing
Apple's system compiler with Homebrew's clang-tidy was found during this
analysis to cause a header-resolution error (`'cctype' file not found`),
since the two toolchains disagree on standard-library search paths.

#### 5.5.2 Results

| Platform | clang-tidy version | Total warnings |
| --- | --- | --- |
| Linux | 18.1.3 | 71 |
| macOS (Apple Silicon) | 23.1.0 | 91 |

The difference is attributable to newer clang-tidy releases adding checks
within the same enabled wildcard categories (for example,
`bugprone-signed-bitwise` and `readability-use-std-min-max` exist only in
23.1.0); the check configuration itself is identical on both platforms.

| Finding | Assessment | Proposed action |
| --- | --- | --- |
| `cert-err34-c` — `sscanf` used for numeric conversion in `XMLUtil::ToInt`/`ToUnsigned`/`ToFloat`/`ToDouble` (`tinyxml2.cpp`) | **Real, actionable.** `sscanf`'s return value does not reliably distinguish all conversion failure modes across platforms. Independently corroborated by the `ToBool` gap found in Section 5.1. | Replace with `strtol`/`strtod`-family functions. |
| `bugprone-signed-bitwise` — signed `int` flag bitmask manipulated with bitwise operators (13 instances, macOS/23.1.0 only) | **Low priority.** Technically implementation-defined for negative operands, but the flag constants involved are always small and positive in this codebase. | No change required; note for awareness. |
| `clang-analyzer-security.ArrayBound` — potential out-of-bounds write in `XMLDocument::LoadFile` (macOS/23.1.0 only) | **Needs manual review.** Symbolic execution traced a taint path from `fread()`'s return value to an array index; the surrounding `read != size` check may or may not fully guard it. | Manually re-verify the guard condition. |
| `readability-inconsistent-declaration-parameter-name` (8 instances) | **Cosmetic.** Header and definition use different parameter names for the same function; legal C++, no behavior difference. | Optional, for readability only. |
| `cert-err33-c` — unchecked return values from `fopen`/`fclose`/`snprintf` (16–19 instances depending on platform) | **Mixed priority.** Instances inside `tinyxml2.cpp` itself are higher priority than those inside the `xmltest.cpp` test harness, since the former ship to users. | Cast to `void` where intentionally ignored, or check explicitly. |

Full output is stored in `clang-tidy/results.log`.

### 5.6 Cppcheck

#### 5.6.1 Scope and Configuration

Cppcheck checked `tinyxml2.cpp` (and, transitively, `tinyxml2.h`) with
`--enable=warning,style,performance,portability` and `--std=c++11`.
`--enable=all` was deliberately not used, since it also includes
`unusedFunction`, which requires whole-program analysis to be meaningful
and produces high-noise false positives for a library where most
functions are legitimately part of the public API. Cppcheck was run as a
second, architecturally independent static analyzer alongside clang-tidy:
it uses its own C/C++ parser and its own dataflow model rather than
Clang's AST and symbolic-execution tooling, so it was expected to surface
different findings rather than duplicate Section 5.5.

The analysis is reproduced from the repository root with:

```bash
./cppcheck/run_cppcheck.sh
```

#### 5.6.2 Results

| Platform | Cppcheck version | Total findings |
| --- | --- | --- |
| Linux | 2.13.0 | 13 |
| macOS (Apple Silicon) | 2.21.0 | 28 |

As with clang-tidy, the difference is attributable to the newer version
enabling additional checks (`missingOverride`, `functionStatic`) not
present in 2.13.0.

| Finding | Assessment | Proposed action |
| --- | --- | --- |
| `invalidPrintfArgType_sint` — `%d` used with `size_t` arguments in a debug-only `printf` trace (5 instances) | **Real, low impact.** Debug-only tracing code, not part of the parsing path. | Use `%zu` instead of `%d`. |
| `uninitMemberVar` — `DynArray::_pool` reported uninitialized (3 instances) | **Likely false positive.** `_pool` is a fixed-size inline array; only the portion tracked by a separate size counter is ever read, and that portion is always written first. The check cannot see this cross-variable invariant. | No change required. |
| `noExplicitConstructor` — three single-argument constructors not marked `explicit` | **Real, minor.** Defensive-coding improvement; no evidence of an actual implicit-conversion defect in the codebase. | Mark constructors `explicit`. |
| `nullPointerRedundantCheck` — `XMLElement::ParseAttributes` (2 instances) | **Likely false positive.** The checker applies a later null-check on a *reassigned* value of `p` (after `attrib->ParseDeep(...)`) backward onto an earlier, logically distinct use of `p`, already guarded by the enclosing `while(p)` loop. | No change required. |
| `missingOverride` — virtual destructors not marked `override` (11 instances, macOS/2.21.0 only) | **Real, minor.** C++11 modernization suggestion; harmless as-is since `virtual` alone is sufficient for correct dispatch. | Add `override` where applicable. |
| `functionStatic` — `InsertChildPreamble`, `DeleteNode` do not use `this` (2 instances, macOS/2.21.0 only) | **Real, minor.** Independently agrees with clang-tidy's `readability-convert-member-functions-to-static` finding on the same two functions. | Mark both `static`. |
| `syntaxError` — reported at `tinyxml2.h:150` under one automatically-generated preprocessor configuration (macOS/2.21.0 only) | **Tool artifact, not a defect.** `TIXMLASSERT` is conditionally defined by the header itself; Cppcheck's automatic configuration exploration constructed a synthetic, unrealistic macro combination that predefines it externally, which does not occur in any real build. | No change required. |
| `knownConditionTrueFalse` — `FirstChild()` re-checked redundantly inside an `if (FirstChild())` block | **Real, minor.** Harmless but redundant. | Remove the redundant condition. |

Full output is stored in `cppcheck/results.log`.

## 6. Conclusions

All 544 fixed test cases (528 from the project's own suite plus 16
self-authored) pass on both Linux and macOS. Neither AddressSanitizer nor
UndefinedBehaviorSanitizer found any error across those same cases on
either platform, and fuzzing found no crash, hang, or memory-safety
violation across nearly 2.4 million adversarially-generated inputs beyond
the fixed test set. The library's core parsing logic held up against every
dynamic method applied to it.

Static analysis surfaced a small number of real, mostly low-severity
findings, concentrated in the library's manual C-style numeric-conversion
functions (`sscanf`-based parsing) — flagged independently by clang-tidy's
CERT-based checks and corroborated by a gap identified separately through
targeted unit testing (Section 5.1), a genuine convergence between two
unrelated methods rather than a finding from either tool in isolation.
Three static-analysis findings (`nullPointerRedundantCheck` and
`uninitMemberVar` from Cppcheck, and one `syntaxError`) were investigated
by reading the flagged code directly and assessed as tool imprecision
rather than real defects, with the specific reasoning recorded above
rather than a bare false-positive label.

clang-tidy and Cppcheck produced almost entirely non-overlapping finding
categories, evidence that the two tools' different underlying analysis
techniques (AST and symbolic execution versus independent dataflow
modeling) have different blind spots; the one point of agreement
(`functionStatic`/`readability-convert-member-functions-to-static`, both
flagging the same two functions) is a useful example of independent
cross-validation between tools. Results for both static analyzers differed
between the Linux and macOS environments, in both cases attributable to
newer tool versions enabling additional checks within the same configured
categories rather than to any difference in the code analyzed.

Two toolchain-integration issues were encountered and resolved during this
analysis: a missing libFuzzer runtime in macOS's Command Line Tools clang
(resolved by installing LLVM via Homebrew), and a header-resolution
failure in clang-tidy caused by mixing Apple's system compiler with
Homebrew's clang-tidy binary (resolved by aligning both to the same
compiler). Both are recorded in Section 5 as practical findings from
running this analysis on real hardware rather than purely as setup notes.