# Tool 5: clang-tidy

Static style/quality checks. This is this project's one allowed
style/formatting tool (course rule: max 1). Covered in course labs
(Clang tooling), applied here specifically to tinyxml2.

## Check set and why

Configured via [`.clang-tidy`](./.clang-tidy) in this directory:
`bugprone-*`, `cert-*`, `clang-analyzer-*`, `performance-*`, `readability-*`,
with three exclusions:

- `readability-magic-numbers` — would flag essentially every numeric
  constant in a binary/text parser; not meaningful signal here.
- `readability-implicit-bool-conversion` — extremely common, idiomatic
  C-style pattern throughout this codebase; flagging it project-wide adds
  noise, not insight.
- `readability-identifier-length` — flags conventional short names (`p`,
  `q`, `i`) that are completely normal in low-level parsing code. Running
  with this enabled produced 97 warnings out of 168 total (58%) that were
  entirely this one check; excluding it leaves the genuinely informative
  findings below.

## Reproduce

```bash
./run_clang_tidy.sh
```

Requires `cmake` and `clang-tidy`. On macOS, install via
`brew install llvm` (Xcode Command Line Tools alone don't include
clang-tidy); the script auto-detects the Homebrew path and, when it uses
that path, also configures CMake to use the matching Homebrew `clang++` —
mixing Apple's system compiler with Homebrew's clang-tidy causes header
resolution errors (`'cctype' file not found`), since the two toolchains
don't agree on standard library search paths.

## Results differ by platform/clang-tidy version — both are legitimate

| Platform | clang-tidy version | Total warnings |
|---|---|---|
| Linux | 18.1.3 | 71 |
| macOS (Apple Silicon) | 23.1.0 | 91 |

This gap is **not** a bug or inconsistency in our setup — the check
*categories* (`bugprone-*`, `readability-*`, etc.) are identical on both
platforms via `.clang-tidy`, but newer clang-tidy releases add new checks
*within* those same wildcard categories over time. Checks present on
macOS/23.1.0 but not available at all in Linux/18.1.3 include
`bugprone-signed-bitwise`, `readability-use-concise-preprocessor-directives`,
`readability-trailing-comma`, `readability-use-std-min-max`,
`readability-redundant-nested-if`, and `readability-inconsistent-ifelse-braces`
— the configuration didn't change, the available checks did. Full output:
[`results.log`](./results.log). Breakdown: [`results_breakdown.txt`](./results_breakdown.txt).

### macOS/23.1.0 breakdown (91 warnings)

| Check | Count |
|---|---|
| `cert-err33-c` | 16 |
| `bugprone-signed-bitwise` | 13 |
| `readability-redundant-member-init` | 9 |
| `readability-inconsistent-declaration-parameter-name` | 8 |
| `readability-simplify-boolean-expr` | 5 |
| `readability-function-cognitive-complexity` | 5 |
| `readability-named-parameter` | 4 |
| `readability-braces-around-statements` | 4 |
| `bugprone-easily-swappable-parameters` | 3 |
| `readability-use-concise-preprocessor-directives` | 2 |
| `readability-trailing-comma` | 2 |
| `readability-redundant-parentheses` | 2 |
| `readability-else-after-return` | 2 |
| `readability-convert-member-functions-to-static` | 2 |
| `cert-dcl50-cpp` | 2 |
| `bugprone-unchecked-string-to-number-conversion` + `cert-err34-c` (combined) | 1 |
| `readability-use-std-min-max` | 1 |
| `readability-redundant-nested-if` | 1 |
| `readability-inconsistent-ifelse-braces` | 1 |
| `readability-avoid-unconditional-preprocessor-if` | 1 |
| `bugprone-branch-clone` | 1 |
| `clang-analyzer-security.ArrayBound` | 1 |

(Linux/18.1.3's 71-warning breakdown is unchanged from the earlier run —
same set, minus the version-specific checks listed above.)

### Highlighted finding 1: unchecked `sscanf` in numeric parsing (both platforms)

tinyxml2's own number-parsing functions (`XMLUtil::ToInt`, `ToUnsigned`,
`ToFloat`, `ToDouble`, `ToInt64`, `ToUnsigned64` in `tinyxml2.cpp`) are
implemented via `sscanf`. Both clang-tidy versions flag this (Linux as
plain `cert-err34-c`; macOS's newer version additionally attaches
`bugprone-unchecked-string-to-number-conversion` to the same finding).
CERT's rule here is that `sscanf`'s return value doesn't reliably
distinguish all conversion failure modes across platforms the way
`strtol`/`strtod`-family functions do (via `errno` and the `endptr` output
parameter). This is a legitimate, actionable finding — not a false
positive — and connects directly to our earlier unit-test findings on
`XMLUtil::ToBool` (tool 1): both point at the same general area of the
codebase (manual string-to-value conversion) as worth extra scrutiny,
found independently by two completely different methods.

### Highlighted finding 2: `bugprone-signed-bitwise` (macOS/23.1.0 only, 13 instances)

tinyxml2 stores parser state as a signed `int` bitmask (`_flags`) and
manipulates it throughout with bitwise operators (`_flags & NEEDS_DELETE`,
`flags |= StrPair::NEEDS_WHITESPACE_COLLAPSING`, etc.). Bitwise operations
on *signed* integers are technically implementation-defined for negative
operands in C++, which is why this check exists. In practice here, the
flag constants are all small positive values and `_flags` never goes
negative in normal use, so this is lower actionable risk than the
`sscanf` finding above — but it's a good concrete example of a check that
only exists in the newer clang-tidy version, demonstrating why the
platform/version comparison table above matters rather than just picking
one number to report.

### Highlighted finding 3: `clang-analyzer-security.ArrayBound` on `XMLDocument::LoadFile` (macOS/23.1.0 only)

The Clang Static Analyzer's symbolic execution traced a potential
out-of-bounds heap write at `_charBuffer[size] = 0` in `LoadFile`, showing
the "taint" path from `fread()`'s return value through to the array index.
This is a deeper class of finding than the pattern-based checks above —
worth manually reading that code path to assess whether it's a real,
reachable issue or a false positive (the surrounding code does check
`read != size` before this line, which may or may not fully guard it).
Good candidate to walk through live at defense as a demonstration of
actually engaging with a tool's output rather than just reporting counts.

## Notes

- `cert-err33-c` findings are largely about `fopen`/`fclose`/`fwrite`
  return values in both `xmltest.cpp`'s test harness and `tinyxml2.cpp`'s
  own file I/O and print functions — the ones inside `tinyxml2.cpp` itself
  (e.g. `SaveFile`, `XMLPrinter::Write`) are higher priority than any in
  the test harness, since they're in code that ships to users.
- `readability-inconsistent-declaration-parameter-name` findings are
  purely cosmetic — parameter names in a declaration vs. definition don't
  affect behavior in C++ — but consistent naming aids readability, which
  is why the check exists.