# Contributing to NURL

Thanks for considering a contribution. NURL is a young project and the
language is still finding its shape, so the bar for "is this worth
discussing" is pretty low — open an issue or a PR and we'll figure it
out from there.

This document is intentionally short. If something here is unclear or
seems wrong, that's a contribution opportunity too.

## Ways to help

- **File bugs.** A reproducible `.nu` snippet plus the actual vs
  expected behaviour is plenty. Smaller is better — if you can shrink
  the repro to the few lines that trigger the issue, that's already
  most of the fix.
- **Improve documentation.** README, grammar comments, stdlib
  docstrings, `docs/GOTCHAS.md`, and example programs all benefit
  from extra eyes.
- **Write examples.** New `.nu` programs in `examples/` that
  demonstrate idioms, stdlib usage, or interesting algorithms are
  always welcome.
- **Stdlib modules.** The standard library is incomplete by design.
  If you need something useful and general, propose it.
- **Compiler / runtime work.** Bug fixes, performance improvements,
  better error messages, missing features from the roadmap — all
  fair game. Open an issue first for anything non-trivial so we can
  align on approach before you write a lot of code.
- **Tooling.** Editor extensions, formatters, language-server work,
  package management, build integrations — there's plenty of green
  field.

## Asking questions

For real bugs in the compiler, stdlib, or playground, use the
[GitHub issue tracker](https://github.com/nurl-lang/nurl/issues).

For open-ended questions, design discussions, "is this a bug or am
I holding it wrong", show-and-tell, and anything else community-shaped,
the subreddit is a better home: <https://www.reddit.com/r/nurllang>.

If you're not sure which is right, pick either. We'll redirect if
needed and nobody will be grumpy about it.

## Filing a good bug report

Issues that include all of the following get resolved much faster:

1. **What you did.** A minimal `.nu` source file (or inline snippet)
   that triggers the issue.
2. **What you expected** to happen.
3. **What actually happened.** Full stderr output if relevant, plus
   the produced LLVM IR if you have it (`nurlc <file>` prints to
   stdout).
4. **Your environment.** OS, clang/LLVM version, and whether you're
   running the native compiler, the wasm build, or the playground.

If the issue is in the playground specifically, mention your browser.
If it's a regression, "this worked in commit X but breaks at commit
Y" is gold.

## Suggesting a feature

For language-level changes (new syntax, grammar tweaks, type-system
work), open an issue or a subreddit thread *first*. The grammar is
deliberately small and every addition has to earn its keep, so it's
worth aligning before anyone writes a parser patch.

For stdlib additions, a short rationale + proposed signatures is
enough — we'll iterate on the design in the issue thread.

## Pull requests

- **Small, focused PRs** are easier to review than sprawling ones.
  Split unrelated changes into separate PRs.
- **Match the surrounding style.** The compiler and stdlib have
  consistent conventions; mimic what's nearby rather than
  introducing new patterns ad-hoc.
- **Run the existing tests** before pushing:
  ```sh
  ./build.sh
  cd compiler/tests && ./run_tests.sh
  ```
  The bootstrap requires byte-identical LLVM IR on its second pass —
  if your change is non-deterministic, the build will reject it.
- **Add or update tests** for compiler changes. New language features
  belong in `compiler/tests/` as `.nu` snippets, each with a per-test
  golden under `compiler/tests/outputs/` (record it with
  `compiler/tests/run_tests.sh --update <name>`; run a single test with
  `run_tests.sh <name>`). Programs that must be *rejected* go in as
  `should_fail_*.nu` / `borrow_*.nu`, with their expected diagnostic as
  the golden.
- **Update docs** if you change observable behaviour. The README is a
  thin overview that links to topic docs under [`docs/`](docs/); update
  the relevant one (`docs/spec.md`, `docs/LIMITATIONS.md`,
  `docs/NETWORKING.md`, …), the EBNF grammar in `spec/`, or
  `docs/GOTCHAS.md`, and add a `CHANGELOG.md` entry, as appropriate.
- **Keep commit messages descriptive.** A one-line subject is fine
  for small fixes; multi-line bodies are welcome for larger changes
  that warrant context.

There's no formal review SLA — we'll try to look at PRs reasonably
promptly, but be patient if it takes a few days.

## Development setup

The full bootstrap chain:

```sh
git clone https://github.com/nurl-lang/nurl
cd nurl

# One-time: build the C runtime
clang -c stdlib/runtime.c -o stdlib/runtime.o

# Bootstrap the self-hosted compiler (committed snapshot IR → NURL → NURL fixed point)
./build.sh
```

Requirements: clang/LLVM 15+. Nothing else — Python was removed
from the build path 2026-05-23; the bootstrap snapshot now lives
as committed LLVM IR (`compiler/nurlc_lastgood.ll`) that clang
links directly into a working boot compiler. Windows users have
`build.bat`; macOS works with Homebrew LLVM (`brew install llvm`).

Compile and run a single program:

```sh
./nurl.sh examples/fizzbuzz.nu
```

The browser playground lives under `nurlapi/`; see its `README.md`
(and [`docs/PLAYGROUND.md`](docs/PLAYGROUND.md)) for the container/dev setup.

## Style conventions

Run **`nurlfmt --write`** before pushing. It applies the canonical `.nu`
format (indentation, spacing, import grouping) and is idempotent and
IR-preserving; CI **hard-gates** on `nurlfmt --check`, and a pre-commit
hook under `.githooks/` formats on commit. See [`docs/FORMAT.md`](docs/FORMAT.md).

A few conventions the formatter does **not** enforce, so apply them by hand:

- **Naming**: `snake_case` for functions and bindings, `PascalCase`
  for types, `SCREAMING_CASE` for top-level constants.
- **Comments**: `//` for single-line. Avoid restating what the code
  obviously does; document *why* when the answer isn't immediately
  obvious from context.
- **Non-`.nu` files**: 2 spaces in TypeScript/JSON.

## Licensing

NURL is dual-licensed under [MIT](LICENSE-MIT) or
[Apache-2.0](LICENSE-APACHE), at your option. By submitting a
contribution you agree that your work may be distributed under both
licenses.

There's no CLA. Contributions are made under the project's existing
licensing; please don't include code you don't have the right to
contribute.

## Code of conduct

Be decent to each other. Disagree about the work, not the person.
Help newcomers. Assume good faith.

If something specific goes wrong and isn't handled well in public,
contact a project maintainer privately and we'll sort it out.

## Thanks

Every issue, PR, comment, example, and question helps shape what
NURL becomes. We appreciate you taking the time.
