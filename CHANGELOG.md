# Changelog

All notable changes to NURL — Neural Unified Representation Language —
are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **`packages/lsmdb` — an embedded, crash-safe key/value store in pure
  NURL.** A real LSM tree: a write-ahead log, a skip-list memtable over
  a byte arena, immutable SSTables (CRC-32 per block, Bloom filter,
  block index, 48-byte footer), ordered range scans, compaction, and
  snapshot reads. A write is fsynced before `put` returns; every crash
  point in the flush and compact sequences recovers to a correct state;
  a torn log tail loses exactly the write that was never acknowledged;
  a block that fails its checksum fails the read rather than returning
  something wrong. Ships as a CLI and as a library.

- **`file_sync` / `dir_sync` (`std/fs`) — there was no fsync at all.**
  `file_flush` pushes libc's buffer into the kernel, which survives the
  process dying and not the machine dying, so nothing in the tree could
  promise a write had reached the device. `file_sync` is the barrier a
  write-ahead log needs, and `dir_sync` is what makes a
  publish-by-rename durable: the file's bytes and the directory entry
  naming them are separate writes, and syncing only the file can leave
  a recovered tree where the data is on disk and the name reaching it
  is not. One runtime shim behind both (`fsync` on unix, `_commit` on
  Windows, a no-op on WASI).

- **`file_truncate` (`std/fs`).** The operation an append-only file
  cannot do without: after a crash, recovery keeps the records up to
  the last intact one and the file has to END there. Leaving the torn
  bytes in place is not untidiness — replay stops at them, so every
  later append lands behind bytes the next replay refuses to walk past
  and is silently invisible from then on.

- **`write_bytes` (`core/io`) — binary stdout.** NURL could read binary
  from stdin (`read_n_bytes`) but not write it back out: every print
  takes a NUL-terminated string, so a program holding arbitrary bytes —
  a value out of a database, a decoded image, a proxied response body —
  had its output silently truncated at the first zero byte.
  `write_bytes` emits the buffer exactly, sharing stdout's buffer and
  tty-flush rule with the ordinary prints so mixing the two never
  reorders output.

### Changed

- **`std/deflate`'s CRC-32 is table-driven.** It computed the checksum
  bitwise — eight shift-mask-xor rounds per byte — which a profile
  found taking 66 % of the cycles of a database point read. It now
  builds a Sarwate table for inputs from 512 bytes up (2048 steps to
  build, then one lookup per byte; the two break even near 300) and
  keeps the bitwise path for short inputs, which would otherwise pay
  the setup to checksum a gzip header. A new `Crc32` context
  (`crc32_ctx` / `crc32_ctx_hash`) holds the table for callers that
  checksum thousands of buffers instead of one. Same values as before:
  `tools/crc32_gate.sh` checks 610 of them — every length across the
  threshold, plus chained updates — against python3's `zlib.crc32`, and
  now runs in CI. Measured on a 4 KiB block: 7.8x. Every gzip, tar and
  PNG user gets it.

## [0.44.2] — 2026-08-16

The last package that could not be installed, and the three defects
standing behind it.

0.44.1 took the registry from 42 of 48 installable to 44. `yoloe` was
the one left, and reaching it meant going through a chain where each
link only became visible once the one in front of it was gone.

### Fixed

- **The FFI sentinel described the machine that BUILT the toolchain,
  not the one running it.** `stdlib/runtime.<lib>` tells nurlc an FFI
  library is available, and `build.sh` writes it by probing the box it
  runs on — which for a release archive is the CI runner. That runner
  has no libX11-dev, so no release has ever shipped `runtime.X11`, and
  `nurlpkg install yoloe` failed at compile time telling the user to
  install libX11-dev and re-run `build.sh` — on a machine that already
  had libX11 and cannot run `build.sh` at all. The installer now probes
  the machine it is installing *onto*, with the same test. No library
  → no sentinel → the same clean compile-time message as before, which
  is the right answer on a headless box: `nurl.sh` would otherwise
  reach the linker and fail there instead.

- **A second FFI declaration of one symbol silently retargeted its
  calls.** Two declarations of the same linker symbol cannot both be
  emitted, so the first wins the `declare` — while every later one
  overwrote the call-site metadata (parameter types, variadic
  signature, return type). Calls were then lowered against a signature
  the module never declared:

  ```
  call i64 (i8*, i32, ...) @open(i8* %path, i64 %r1)
  ```

  nurlc exited 0 and clang delivered the news, about generated IR.
  One linker symbol has one ABI, so a *disagreement* is now an error
  naming both signatures and pointing at the `&` rather than at the
  next declaration the lexer had already reached. Identical
  redeclarations stay legal — two modules declaring the same extern is
  ordinary, and the stdlib relies on it.
  (`should_fail_ffi_sig_conflict`)

- **The version-string gate could not see past a parenthesis.** Its
  `cli_new[^)]*` matcher stopped at the first `)`, and `yoloe`'s
  about-string is "…segmentation (pure NURL, GPU)" — so the version sat
  behind a parenthesis *inside the description* and the gate written to
  check it saw nothing. yoloe shipped 0.6.6 announcing 0.6.0. It now
  takes the last backticked semver on the line; 14 literals checked.


## [0.44.1] — 2026-08-16

A patch cut for one reason: 0.44.0 could not compile a correct program,
and a published package was the proof.

Installing all 48 registry packages with 0.44.0 — the standing rule that
publishing proves nothing, so install it — turned up six that did not
build. Five were the ecosystem's own defects and are fixed in the
packages. The sixth was the compiler's.

### Fixed

- **A ternary may end a condition; the `{` after it is the body.** The
  n-ary arity trap (0.37.0) fires when a `{` follows a completed
  ternary: `? & a b c d { then } { else }` means an n-ary AND, `& a b`
  takes two operands, `c` and `d` are eaten as the bare then/else, and
  the blocks become stray statements. Real trap, worth the hard error
  it became.

  That signal has a second and entirely correct source:

  ```
  ~ & ok < i0 ? >= stopat 0 stopat N { body }
  ```

  Here the ternary is part of the **loop's** condition and the `{`
  opens the loop body. Nothing is stray, there is no rewrite that
  avoids the diagnostic, and it is an error by default — so a correct
  program could not be compiled at all. The `?`-condition form has it
  too. `packages/lingbot-map` had exactly this shape and could not be
  installed by any toolchain.

  The check now stays silent while a condition is being parsed and
  fires exactly as before everywhere else. Inside a condition the two
  cases are genuinely indistinguishable — the `{` is the enclosing
  construct's block either way — so silence is the only answer that
  keeps correct code compiling, and it is the direction every other
  diagnostic here takes: miss, never invent. The corpus compiles to
  byte-identical IR; the only exit-code change anywhere is the new test.
  (`arity_ternary_in_condition`, with `arity_strict_nary` unmoved)

- **Two published packages that could not be installed, and five that
  announced the wrong version.** `gguf` passed an `i` where a `b` was
  declared; `lingbot-map` carried stray fourth blocks on two `?`
  statements. Both failed identically under 0.43.0 — they had simply
  been uninstallable since publication, and nothing was looking,
  because `nurlpkg publish` does not build what it publishes.

  Then the freshly published `gguf 0.3.1` printed `gguf 0.3.0`: the
  gate added days earlier to stop exactly that checks
  `cli_new prog about VERSION`, and gguf prints its version with a bare
  `nurl_print` of the literal `gguf 0.3.0`. It now also matches a literal
  carrying the package's **own name** followed by a semver, went from
  checking 1 literal to 13, and found four more drifted packages —
  `safetensor` was two minors behind. All are bumped rather than
  corrected in place: each had already shipped announcing the wrong
  number, and a published version can be yanked, never replaced.


## [0.44.0] — 2026-08-16

The order-independent release. Every entry started from the same
question, asked once and then asked again of each rule in turn: *does
this check answer a question, or does it recognise a shape?* Three
things turned out to be shapes.

A stack reference was safe until it rode a `?`. `^ f` was an error and
`^ ? c f f` compiled clean — a branch that cannot change the answer,
since both arms hand the caller the same dead frame. The same was true
of a field store, and of a join nested inside a `??` arm. Every one is
a confirmed `stack-use-after-return` or heap use-after-free under
AddressSanitizer.

And *where you wrote a function* still decided two verdicts. A helper
defined below its caller has no summary yet, and an empty summary reads
as "does not mutate" rather than "not compiled yet". Both rules that
still consulted one inline now park what they cannot answer and resolve
it after the module — §2.10 by parking the finished report rather than
the question, because its diagnostic fires at a later read of the
pointer and there is no call site to park at. **No rule in the memory
model depends on definition order any more.**

Underneath both is one method: §2.3 was the only default-on rule with
no `tools/metamorph` class, which is exactly why its interprocedural
cousins had been swept twice and the rule they build on never had. Ask
what is *not* in the harness, not what is. The harness itself gained a
second axis for the one part of the model no compile verdict can
answer — the panic-unwind journal, whose question is an LSan run — and
that oracle was found broken by mutation-testing it before it was
trusted.

### Fixed

- **The same reference, however it leaves the function.**
  `docs/MEMORY.md` listed four boundaries around the two
  interprocedural escape checks. Enumerating the spellings found
  **eleven**, and every one had the shape the whole 0.43.0 cycle had:
  the check asked its question at one syntax and said nothing at the
  others. Out through the result (§2.8) missed a nested aggregate, a
  closure that captured the reference, a local name given to it, a
  second helper, a ternary, and a callee defined below the call or
  written generically. In through a parameter (§2.7) missed a whole
  chain defined below its caller, a helper whose own escaping callee
  sat below it, a generic escaping parameter, and a *field* of the
  parameter reaching `thread_spawn`. ASan reports
  `stack-use-after-return` on all of them.

  Three mechanisms close them. A binding carries the parameters its
  initialiser carried, and a call result carries those at the callee's
  returned positions, so a reference does not lose provenance by being
  given a name or taking another hop. Propagation between summaries is
  parked as an implication and run to a **fixed point** before any
  parked check replays — which is what makes a forward chain behave
  like the same functions written bottom-up. And the return-escape
  check parks what it cannot answer at a forward or generic call.

  §2.4 and §2.10 were the two checks with no coverage class at all, and
  each turned out to have one gap: strict-mode aliased mutation knew
  `. c n` but not `( peek c )`, so the *depth* of the expression
  decided the verdict; and the stale-borrow rule knew only a direct
  stdlib mutator, so `( grow v )` was silent where `( vec_push v … )`
  warned — which reads as "wrap the push in a function" being the cure
  for the diagnostic rather than for the bug.

- **`tools/metamorph` was not running in CI, and its baseline was
  stale.** The harness had run only by hand. `known_gaps.json` still
  listed two gaps that had already been fixed, and a stale baseline is
  not cosmetic — it would have absorbed the regression had either hole
  come back. It is a CI step now and the baseline is empty. Separately,
  `--verify` could not see a stack bug at all: ASan instruments only
  functions carrying `sanitize_address`, which the C frontend adds and
  nurlc's hand-written IR does not, so escalations saw only what the
  runtime's malloc interceptors caught and every dangling stack
  reference ran clean and was filed UNCONFIRMED. The escalation now
  stamps the attribute on the generated module and runs with
  `detect_stack_use_after_return=1`. The gate also fails loudly when
  `llvm-as` is missing rather than quietly reporting every module
  valid.

- **A stack reference stopped being safe the moment it rode a `?`.**
  Reference-ness propagated through closure literals, aggregate
  literals, copies and `=` assignments — but not through the phi of a
  conditional, so `^ f` was an error and `^ ? c f f` compiled clean. The
  branch cannot change the answer: both arms hand the caller a pointer
  into the frame that is about to disappear. AddressSanitizer reports
  `stack-use-after-return` on every spelling — the ternary, the `??`,
  the join bound to a local first, a struct literal built from one, a
  ternary between two structs, and the same join reaching `vec_push` or
  `thread_spawn` instead of a return.

  Two more of the same shape came with it. `= . box cb f` — a field
  store — walked a stack reference into a longer-lived struct with
  nothing said, and returning that struct handed out the dead frame;
  the field form now has the two effects the whole-binding form always
  had (the struct inherits the reference, and a store into a struct
  that outlives the referent is reported at the store). And a join
  nested inside a `??` arm dropped the handle candidates `gen_cond` has
  carried up since 0.42.0, so `?? c { 1 → ? d a a  _ → ( make ) }`
  handed `a`'s buffer over with nothing recorded: freeing both names
  compiled clean into a heap use-after-free.

  §2.3 was the only default-on rule with no `tools/metamorph` class,
  which is why its interprocedural cousins had been swept twice and the
  rule they build on never had. It has one now — eighteen spellings —
  and so does the strict `# *T` escape check, which found no gap and
  now cannot grow one. Four new controls pin the other direction: a
  join between closures that capture nothing, a join that stays in its
  frame, a same-region field store, an ordinary scalar field store.
  (`borrow_escape_join`, `borrow_escape_field_store`,
  `borrow_strict_nested_join_alias`)

- **Iterator invalidation stopped depending on definition order too.**
  §2.5 follows a container mutation one call deep through the
  per-function mutation summary, and that summary is built in codegen
  order — so `~ y xs { ( grow xs ) }` was diagnosed when `grow` sat
  above the loop and silent when it sat below. The call now parks the
  question and replays it against the final summary.

- **Definition order can no longer change any verdict the borrow
  checker gives.** §2.10 was the last rule where it could: a pointer
  borrowed with `vec_data` goes stale when the container is grown
  through a helper, and that was reported when the helper sat above the
  borrow and silent when it sat below, because an empty mutation
  summary reads as "does not mutate" rather than "not compiled yet".

  §2.5 parks that question at the call, where its diagnostic fires.
  This one fires at a later *read* of the pointer, so there is no
  single site to park; what is parked is the finished report plus the
  callee it is conditional on. The call kills the pointer
  provisionally, and the condition rides *inside* the stale-set entry
  rather than in a side table — a question parked before a `?` and a
  certain kill inside one arm are precisely the pair that meet at the
  join, and a side table does not survive the union. A certain mutation
  supersedes a parked one, entry and line together, so the report names
  the call that really reallocates.
  (`should_warn_stale_borrow_forward`)

- **`anomaly --version` told the truth for the first time since 0.5.2.**
  `cli_new` takes the version as a string literal and nothing derived
  it from `nurl.toml`, so the two drifted the moment a release bumped
  one and forgot the other — invisibly, because no test ran `--version`
  and compared it to anything. anomaly shipped 0.5.3 and 0.5.4 while
  `--version` kept answering 0.5.2; a version can be yanked, never
  replaced. `tools/check_package_version_strings.sh` now compares every
  package's manifest against the literal it passes to `cli_new` and
  fails on a mismatch, with comments stripped so the doc example in
  `packages/cli` is not mistaken for a real call. All 45 packages
  audited; anomaly was the only real drift.

- **A regression test that had never run once.** `test_skips.sh`
  skipped any test whose *name* ended in `_mod` / `_helper` / `_lib`,
  on the theory that those are importable modules with no `main()`.
  `diag_thread_arc_shared_mutation_helper.nu` — the regression test for
  the Arc shared-mutation race one call deep — has a `main()` and was
  skipped by name. It had no golden either, and neither the
  MISSING-golden check nor the ORPHAN check fires for a skipped test,
  so the only trace was the SKIP count. The rule now asks the *file*
  whether it has a `main()`.

- **~1.2 MB of generated test scratch had been committed to
  `packages/anomaly`.** Model blobs and `data.jsonl` written by
  `timevector_test.nu`, swept in by a `git add -A` and about to go into
  a published tarball — the same class as the packer defect fixed in
  0.41.0. Removed, and `.gitignore` now excludes the directory the test
  writes to.

### Added

- **`tools/metamorph` grew a second axis, for the one part of the
  memory model no compile verdict can answer.** Every class in the
  harness asks the compiler a question and compares verdicts across
  spellings. The panic-unwind allocation journal is a *runtime*
  mechanism: a `panic` longjmps past the scope-exit frees the compiler
  queued, and the journal reclaims what it skipped, so the question is
  whether the program leaks — or frees something the caller still owns.
  The `panic-reclaim` class asks it as an LSan run over nine spellings
  of one abandoned allocation: a `?` arm, a `??` arm, a loop body, two
  frames deep, a nested extent (the inner unwind must not touch the
  outer's scratch), a second extent after the first (a stale journal
  would drain twice), an extent that never panics, and the escape case
  where a value moved into a caller's binding must *not* be freed. All
  nine come back clean — the journal is uniform across them, measured
  rather than assumed.

  The oracle was broken first, and mutation-testing it is what found
  that: under LSan's defaults a deliberately-leaking control reported
  CLEAN, because the buffer's only owner is a live `main` frame and so
  it reads as still reachable. With `use_stacks=0` the control reads
  `leak` and a double free reads `crash`. At process exit an allocation
  the program still owns *is* the leak being asked about; the stack
  must not launder it. The gate runs in the sanitizers job, where the
  `--san` build has already produced the runtime it needs, and it skips
  *loudly* without one.

### Changed

- **The cross-file `__` path is obsolete, and nothing first-party uses
  it any more.** A `__name` function is file-scoped by design; calling
  one from another file resolved anyway, as a compatibility shim for
  code written under the old flat namespace, and warned that it was
  deprecated. The stdlib had been quietly living on that shim: seventeen
  helpers — `_p256_scr_new`, `_p256_mul_d`, `_mag8` and the rest — were
  defined `__`-private in `p256_field.nu` and called from
  `ecdsa_p256.nu`, so every build of the crypto stack printed warnings
  telling its own author to rename them. Four in-tree packages
  (`anomaly`, `gpukit`, `whisper`) did the same within their own trees.

  All twenty-one are renamed to the single-underscore shared-internal
  spelling, at the definition and at every call site. Compiling the
  whole stdlib now produces **zero** cross-file `__` warnings, as do the
  packages, the examples and the tooling; the only three call sites left
  in the repo are the fixtures that exist to pin the diagnostic itself.

  The warning is relabelled from *deprecated* to **obsolete** and now
  says the path will stop resolving. It is not removed yet, and the
  reason is narrow: package versions **already published** were compiled
  under it, and deleting the path would break `nurlpkg install` of a
  release nobody can go back and edit. It goes when those have turned
  over.

## [0.43.0] — 2026-08-15

The same-verdict release. Every entry below started from one
observation: the checker was recognising *shapes* where it should have
been answering *questions*. It knew that `: T b a` gives a handle a
second name, that a payload slot holds a box, that a thread closure must
not capture something spelled `Rc` — and every one of those is a
spelling, not a property. Written another way, the same situation got a
different verdict.

`tools/metamorph` is the instrument that made that measurable: it
enumerates one semantic situation across N spellings and fails when the
verdicts disagree. It found gaps in three checks that had shipped days
earlier — one of them hours old — and it stays behind as a gate, now at
nine situation classes plus the controls that guard the other direction,
reporting zero gaps and zero control regressions.

The headline is `Send` / `Sync`. Thread safety had been a single line,
"is this capture spelled `Rc`?", and twelve probe programs found ten
ways to write the same undefined behaviour that compiled clean. It is
now a property derived over a type's whole graph, checked at every
boundary a value can cross, with a marker for each of the two directions
a structural derivation can be wrong in.

### Added

- **`Send` / `Sync` — thread safety as a property of the type, not of
  its spelling.** Two marker traits (`stdlib/core/marker.nu`) name the
  two questions a thread boundary asks: `Send` ("may this value MOVE to
  another thread?") and `Sync` ("may two threads reach ONE of these at
  once?"). Both are **derived structurally over a type's whole graph** —
  struct fields, enum variant payloads, generic arguments, aggregate
  members, closure captures — from two language-level leaves: `Rc` is
  neither (its refcount is not atomic) and `Cell` is Send but not Sync
  (a raw byte buffer with unsynchronised writes).

  The derivation is checked where a value actually crosses:
  `thread_spawn` and `spawn` (every capture must be Send — a fiber runs
  on whichever M:N worker picks it up, so it is a thread boundary too),
  `chan_send` (the value must be Send), and `Arc T`, whose payload must
  be Send **and** Sync because an Arc exists to be shared. `[T: Send]`
  and `[T: Sync]` bounds are answered by the same derivation instead of
  by an impl lookup, so they accept `i`, `s` and `( Vec i )` with no
  impl block anywhere.

  What this replaces is a single line asking "is this capture spelled
  `Rc`?". It caught that one spelling. The same undefined behaviour
  written with the Rc one struct field, one Vec element, one Box, one
  Arc payload, one option, one enum variant, one nested closure, or one
  different boundary away compiled clean — ten ways to write one bug,
  one of them diagnosed. `tools/metamorph` now enumerates fifteen
  spellings of it plus three of the Sync half, and the diagnostic names
  the *reason* (`it reaches an 'Rc' …`) rather than the shape it
  happened to recognise.

  Because the derivation is structural it can be wrong in two
  directions, and there is a marker for each. `% Send T { }` /
  `% Sync T { }` assert safety the compiler cannot see — `Mutex` is
  `{ Cell c }` and is nonetheless the thing that *makes* contents
  shareable, so `stdlib/std/thread.nu` marks `Mutex`, `Cond`, `Thread`
  and `Semaphore` by hand. `% NotSend T { }` / `% NotSync T { }` assert
  danger it cannot see: NURL spells `String` and every opaque FFI handle
  `i8*`, so a `sqlite3*` derives as Send and there is no way for the
  compiler to know better. A marker impl is NURL's spelling of Rust's
  `unsafe impl` — an assertion, not a proof — and a negative one
  outranks a positive one on the same type.

  Send/Sync answer "may this value cross?", never "is this program
  race-free": `( Vec i )` is Send and Sync, correctly, because sharing
  one read-only is ordinary code. Two threads *mutating* it is the race
  the existing shared-mutation check catches, at the mutation. The two
  are complementary and neither subsumes the other; `MEMORY.md` §6.5 and
  `LIMITATIONS.md` state exactly what each one does and does not
  guarantee.
  (`diag_send_struct_field`, `diag_send_generic_arg`,
  `diag_send_enum_payload`, `diag_send_nested_closure`,
  `diag_send_chan_send`, `diag_send_fiber_spawn`,
  `diag_send_notsend_marker`, `diag_sync_arc_cell`,
  `diag_send_generic_bound`, `send_sync_markers_ok`)


- **`tools/metamorph` doubled its classes — and stopped lying to
  itself.** Four classes to eight (use-after-free, loop-carried-free,
  iterator-invalidation, thread-nonsend) plus four controls for the
  documented §2.6 exemptions, which turned up two more gaps of the usual
  shape. The more valuable half is the three fixes to the *harness*,
  each a way it could have handed back a confident wrong answer:

  - A template with a **typo** compiled to a syntax error, which the
    harness read as "rejected — the checker caught it": a false negative
    wearing coverage's clothes. A rejection must now match the
    diagnostic its class is about, and anything else is reported INVALID
    against the template, never against nurlc. It immediately caught
    three of the new templates, including `( ? … )` — which in NURL is a
    call to a function named `?`.
  - Controls were compared with `>=`, so a control that got **rejected**
    counted as "better than asked" — precisely the false positive that
    class exists to catch, passing in silence. Fixing it exposed a
    second modelling error: controls were held to `--strict-borrowck`,
    which is documented to over-flag. The no-false-positive contract is
    the *default* checker's, so that is the bar now.
  - Three gaps were reported as "hung (weak signal)". They were not
    hung: ASan had already printed `SEGV on 0xfffffffffffffff8, WRITE`
    and was stalling in its symbolizer, and the harness threw that away
    on timeout. It now scans partial output and runs with
    `symbolize=0`. A weak label on strong evidence is its own kind of
    wrong answer.

  Classes now carry a severity and the worklist ranks by it, because not
  every disagreement is memory unsafety. `iterator-invalidation`
  deliberately is not: measured, a forced realloc mid-iteration does not
  dangle — a Vec is a handle to a control block and the loop reads
  through it — so §2.5 is a conservative guard and a gap there is a
  diagnostic inconsistency, not corruption. Ranking it alongside the
  double frees would have sent the next reader at the wrong thing first.

  The sequencing trap that cost the most time is documented in the
  harness README: `--verify` wants a sanitized *runtime*, never a
  sanitized *compiler*. Leaving `build/nurlc` sanitized turns the sweep
  from 1.5 seconds into ~50 minutes and looks hung. The tool now warns,
  and takes `$NURL_SAN_RUNTIME` so the sanitized runtime survives a
  normal rebuild.

- **Two measured semantics pinned as `tools/metamorph` controls.** Both
  were suspected bugs and turned out to be defined behaviour, so they
  are now guarded against silent drift rather than "fixed": a partially
  filled struct literal **zero-fills** (the aggregate starts as
  `zeroinitializer` — `@ P { 7 }` gives `7, 0, 0`, not garbage), and a
  match arm may bind a **prefix** of a variant's payloads and ignore the
  rest. An under-fill check written before measuring rejected the first
  and broke five tests that rely on it deliberately.


- **`tools/metamorph` gains an `invalid-input` class and an IR-validity
  invariant.** The classes so far asked "the same situation spelled N
  ways — does the verdict agree?". This adds the other question: *bad
  input must be diagnosed, never lowered.* Two shipped bugs escaped
  exactly there, and both times nurlc exited 0 and clang reported the
  problem against generated IR rather than the line to change.

  The invariant is the stronger half and applies to **every** spelling in
  every class, not just the new one: whenever nurlc exits 0, the module
  must pass the LLVM verifier (`llvm-as`). Unlike everything else in the
  harness this is never a template bug — whatever a program says, if the
  compiler accepted it then what it emitted has to verify.


- **`tools/metamorph` — a metamorphic coverage harness for the checker.**
  The fuzzers in `tools/fuzz` ask whether a program computes the right
  value. This asks a different question, on the axis where the
  diagnostics have actually been wrong: *the same semantic situation,
  written N ways, must get the same verdict*.

  Four consecutive fixes were one shape — the checker asked its question
  at one syntactic spelling and missed the others (#898 generic vs plain
  wrapper, #899 `: T b a` vs `?`/`??`/`=`/returned argument, #901 boxed
  vs typed payload slot, #902 mutation inline vs one call deep). None was
  the analysis being too weak in theory; each was coverage nobody had
  enumerated.

  A disagreement is not assumed to be a compiler bug: a spelling accepted
  where its class says reject is rebuilt with `--no-borrowck` and run
  under AddressSanitizer, and reported as UNCONFIRMED if it runs clean —
  the template is then the thing to look at. That escalation is what
  separates a bug finder from a generator of plausible-looking noise. A
  `controls` class of correct programs guards the other direction, and
  fails separately and loudly, because a false positive is the worse
  failure.

### Changed

- **The error summary says what was *not* checked.** Diagnostic recovery
  is per top-level declaration: a reported error skips the rest of the
  `@` it fired in, so two bad statements in one body produce one error
  and `aborting due to 1 previous error`. Nothing there is false, but the
  silence reads as "the rest was checked and passed" — and for anything
  driving nurlc in a loop, an adversarial sweep or a model fixing its own
  output, that inference is systematically wrong: nine of ten broken
  constructs look accepted when nine were never examined. The summary now
  adds one line saying the count is a lower bound.

  Reporting every statement instead was implemented and reverted. With no
  statement terminator to resync on and no poison bindings, the extra
  errors were *derived*: a failed `: 5 n 0` made the next line's `^ n`
  read as "undefined identifier 'n'", one fixture reported the same error
  twice, and another desynchronised its braces into "unexpected '}' at
  the top level". Naming an innocent line costs a reader more than
  staying silent about it does; the real fix needs poison bindings and
  derived-error suppression, and the reasoning is recorded at the site.

### Fixed

- **A `pub` prefix leaked out of its declaration — and out of its
  file.** Found while adding the marker traits above, and unrelated to
  them. The `scan_fn_sigs` pre-pass set a pending-`pub` flag before
  dispatching on the declaration kind, but only the `@`-function arm
  ever cleared it. A `pub` on anything else — a trait, an impl, a
  struct, an enum, a const — left the flag set, and the next `@` the
  scanner reached inherited it. Once the scan crossed an import
  boundary that `@` was in a *different file*: importing a module whose
  last declaration was `pub % Trait [T] { }` silently made the
  importer's next function public and flipped the importer into
  strict-visibility mode, at which point its own unmarked types stopped
  being visible across files. The error blamed a declaration nowhere
  near the `pub` that caused it. The flag is now read-and-cleared where
  the prefix is parsed, and `gen_import_decl` consumes one too.
  (`pub_prefix_scoped`)

- **A struct/handle in a payload slot declared as a number.** The
  pointer form was rejected earlier, and the user-enum form after that.
  A `Vec` reaches the option/result payload path as `%Vec__i64` — a
  *named struct*, not a raw pointer — so it took the struct-handle
  branch, which folds the value to an i64 and hands it to the slot. The
  `??` arm read it back as the declared type: `@ ?i { T d }` with a Vec
  `d` returned **192**, the low byte of a heap address. Same lie as the
  first two, one branch over.

- **Mutating an iterated container one call deep.** A `~ x xs` foreach
  holds a borrow of `xs` (§2.5) and the direct `( vec_push xs … )` in
  the body has been rejected for a long time; the same push inside a
  helper was not, which reads as "wrap it in a function" being a cure
  for a borrow violation. A per-function summary records which
  parameters' containers a body mutates, inferred in codegen order like
  the sink / escape / shared-mutation summaries, and the call site
  consults it. Measured, this shape is not memory-unsafe today — a Vec
  is a handle to a control block, so a forced realloc mid-iteration does
  not dangle — but a guard that applies to one spelling and not its twin
  teaches the wrong cure.
  (`diag_payload_struct_into_number`, `diag_foreach_mutate_one_call_deep`)

  With these, `tools/metamorph` reports **zero gaps**: every spelling of
  every class now gets the same verdict as its siblings.


- **A user enum's payload slot is a number, and a pointer folded into
  it is read back as arithmetic.** The option/result form of this was
  fixed earlier; the user-enum side kept the hole. `@ E { A `s` }` where
  `A` declares an `i` payload compiled clean, linked, ran, and returned
  **96** — the low byte of a `.rodata` address — from an arm the writer
  expected to yield a number.

  `docs/MEMORY.md` has carried a "user enums: SCALAR payloads only"
  gotcha for exactly this. A gotcha in prose is what a compiler says
  when it has no diagnostic; this is the diagnostic.

  Found by `tools/metamorph`'s invalid-input class — and *not* by its
  IR-validity invariant, because the emitted module verifies fine. It is
  a wrong value, not malformed IR, which is why that class enumerates
  plausible-wrong inputs as well as checking what gets lowered.
  (`diag_enum_payload_ptr_into_int`)


- **Returning a handle where a number is declared.** `^ ( vec_new [i] )`
  from a `→ i` function lowered `ret %Vec__i64 %r1` out of a
  `define i64`. The return-type chain asked about every pair of shapes it
  knew — float/float, int/int, `{…}`/`{…}`, struct/struct, int/enum — and
  a struct beside a plain number matched none of them, so it fell through
  to the emit.

- **A generic called with the wrong number of arguments.** The call-site
  arity check was conditioned on `call_name == fname`, which is false for
  a generic, and generics recorded no parameter count anyway:
  `( vec_push [i] v )`, one argument short, was accepted, and a missing
  argument reads an unset ABI register — the same silent failure the FFI
  arity check exists to prevent. The template's count is now recorded
  under `__garity`, deliberately not the shared `__arity`: a file may
  define its own non-generic function with the same name as an imported
  generic, and writing the template's count into the shared key made
  every call to the *local* function look one argument short.
  (`diag_ret_struct_and_generic_arity`)


- **A `??` arm must name something the scrutinee can be.** Nothing
  checked that, and the consequence was not a diagnostic: an
  unrecognised name fell through to the enum-variant path, which emits
  `load i64, i64* @<name>` for a global that was never defined, and the
  arm's payload binding got an empty type —

  ```llvm
  %r8 = alloca                    ; "Cannot allocate unsized type"
  %r5 = load i64, i64* @Ok        ; a global that does not exist
  ```

  — so nurlc exited 0 and clang delivered the news, about generated IR
  rather than about the arm the writer has to change.

  The shape that surfaced it is the Rust habit rather than a typo:

  ```
  ?? ( int_parse `123` ) { Ok val → val  _ → -1 }
  ```

  so the message names the NURL spelling instead of only rejecting the
  wrong one — `T` and `F`, not `Ok`/`Err`/`Some`/`None`. A misspelled
  variant of a named enum is reported the same way, and lists the
  variants that type actually has.
  (`diag_match_arm_not_a_variant`)


- **Three more ways a heap handle acquires a second name.** #899 closed
  the copy, the `?` / `??` join, the assignment and the
  callee-returns-its-argument spellings. `tools/metamorph` enumerated the
  same situation across spellings and found three the verdict did not
  agree on — each an ASan-confirmed double free (SEGV on a write):

  - **a nested `?`** — the outer join's arm is not a bare identifier, so
    the outer published no candidates and the inner's were dropped. One
    level worked, two did not. Arms now hand their candidates up.
  - **an aggregate-literal field** — `@ Holder { a }`. The lint already
    treated this as released and the code comment already called it a
    move; only the checker had not been told. Measured: the field and the
    binding share a data pointer, and a push through one is visible
    through the other.
  - **a closure capture** — a closure that frees what it captured. Moves
    recorded inside a closure body are deliberately dropped, since its
    statements must not inline into the enclosing function's list; that
    dropped this one too. The body's consumes are now replayed against
    the capture list.

  All three are maybe-moves, reported under `--strict-borrowck`, for the
  reason that made the assignment case conditional in #899: the handover
  is certain, but the old name may still be a legal way to use the live
  buffer, and only liveness — which this checker does not compute — could
  say when it stops being one. For the closure there is a second reason:
  the checker knows the capture, not the call count, and a closure that
  frees its capture but is never called leaks rather than double-frees.

  Recording the aggregate case as a *definite* move was tried first and
  reverted: it rejected the option-wrapper idiom the MCP tests are built
  on, where `@ ?Json { T p1 }` is a transient argument wrapper and `p1`
  is still the caller's to free.

  Default-mode acceptance is unchanged across stdlib, examples and 320
  package files. Three stdlib files gain a `--strict-borrowck`
  diagnostic, all the documented mutually-exclusive-frees pattern that
  strict mode is stated to flag (a handle either returned inside an
  option or freed, never both). (`borrow_strict_handle_second_name_more`)


- **The shared-mutation summary is transitive.** #902 rejected a thread
  closure that mutates an `Arc`'s contents through a helper, but the
  summary stopped at depth one: `closure → outer → inner` was accepted
  while `closure → inner` was rejected, leaving open the exact
  "wrap it one level further" escape the summary exists to close. A
  function that calls a mutating function is now itself recorded as one.
  Found by `tools/metamorph` on its first run, hours after #902 shipped.


- **Two threads mutating one `Arc`'s contents is now a compile error.**
  `docs/MEMORY.md` §6.5 named this as the concrete unchecked data race —
  "`Arc` makes the *refcount* atomic, not your data" — and it was
  reachable from ordinary code: no `*T`, no FFI, not a single cast.

  ```
  : ( Arc ( Vec i ) ) a ( arc_new [( Vec i )] d )
  : ( @ v ) w1 \ → v { : ( Vec i ) v ( arc_get [( Vec i )] a )  ( vec_push [i] v k ) }
  : ( @ v ) w2 \ → v { … the same … }
  ```

  Measured, two workers × 2000 pushes: **5 of 8 runs segfaulted**, and
  the survivors returned 2000 / 2996 / 3166 instead of 4000. `arc_get`
  over a manually-managed handle hands back a *copy of the handle*
  aliasing the one buffer, so both workers write the same length and the
  same backing pointer, and whichever reallocates first frees the buffer
  the other still holds.

  `thread_spawn` now rejects a closure that mutates the contents of an
  `Arc` it did not create, whether the mutation is inline or inside a
  helper it calls — moving a `vec_push` into a function must not move it
  out of the check, so a per-function summary carries it, inferred in
  codegen order like the sink and escape summaries.

  The error fires at the *detach*, not at the mutation: mutating an
  Arc's contents from one thread is ordinary correct code. Four shapes
  stay legal and are pinned as a control — single-threaded mutation, a
  read-only worker, a worker mutating its own Vec, and **the cure**:
  mutation under a lock the worker takes itself. That last one matters
  most, because a diagnostic that forbids the fix it recommends is worse
  than no diagnostic; it is verified to compile *and* to return
  4000/4000 over ten runs. Lock depth is counted rather than proved, and
  reset when a closure body is entered — a lock the defining thread
  holds says nothing about the thread the closure is detached onto — so
  the check can only miss a race, never invent one.
  (`diag_thread_arc_shared_mutation`,
  `diag_thread_arc_shared_mutation_helper`,
  `thread_arc_shared_mutation_ok`)

- **An option/result payload must be the type the option was declared
  over.** Field 1 carries T's real type in both forms — `? i` lowers to
  `{ i1, i64 }`, `! i s` to `{ i1, i64, i8* }` — but the payload
  coercion believed a comment saying a result's slot "is always i64" and
  folded *any* pointer into it with `ptrtoint`. That is the correct
  representation for a slot which is an untyped box, and the wrong one
  for a slot declared as a number. Two shapes got past nurlc:

  ```
  @ ?s { T 42 }     // nurlc exited 0; clang rejected the insertvalue
  @ ?i { T `x` }    // compiled clean, linked, and RAN
  ```

  The second is the dangerous one. The fold made the address fit, so
  `?? o { T v → ^ v }` returned the low byte of a `.rodata` address from
  a `^ v` the writer expected to be a number — a silent miscompile with
  no diagnostic anywhere. The first only ever failed at clang, in a
  message about `{ i1, i8* }` and `i64` that named neither the option nor
  the line to change.

  The fold now asks what the slot *is* before reinterpreting an address
  as arithmetic, and a backstop refuses to emit an `insertvalue` the
  coercion chain could not legally bridge — so a payload mismatch is a
  NURL diagnostic naming both types, not IR handed to the next tool.
  (`diag_opt_payload_ptr_into_int`, `diag_opt_payload_type_mismatch`)

- **Five more network tests raced their own client.** `tls_large_record`
  failed in CI with the client's two output lines missing — exactly the
  shape `http_server_pipelined` had in 0.42.0. Its IR was byte-identical
  before and after the branch it failed on, so the program under test had
  not moved.

  The cause is the one fixed there: the client is spawned with `&` from a
  shell that then exits, orphaning it, and the collector later runs
  `wait $(cat pid)` in a *different* shell where that pid is not a child.
  The wait fails instantly — which is what the `2>/dev/null` was hiding —
  and only a fixed `sleep` makes it work, which a loaded runner defeats.

  The 0.42.0 note that no other test used the pattern was wrong: the grep
  it rested on was mis-escaped and matched nothing. A correct search finds
  `http_server_tls`, `http_server_seq`, `net_loopback`,
  `http_server_limits` (two clients) and `tls_large_record` — six sites in
  total. All six now use the deterministic handoff: the client writes a
  `.part` file and **renames** it when done (rename(2) is atomic, so the
  collector sees all or nothing), stale files are cleared first, the
  background group redirects its own stdout so it cannot hold the pipe
  `process_run_shell` reads, and the collector polls for the renamed file
  instead of assuming it has arrived. Verified against the failure mode
  rather than assumed: six rounds of all six tests under 24-way CPU
  saturation, 6/6 clean.

## [0.42.0] — 2026-08-14

The second-owner release. A heap handle in NURL has exactly one owner,
and the borrow checker's job is to notice when a second name acquires
it. It recognised exactly one way for that to happen — the copy
`: T b a` — and five other ways were invisible: a `?` or `??` that
selects between handles, an assignment that hands one over, a callee
that hands an argument back, and a generic wrapper that consumes its
parameter. Every one of them compiled clean and double-freed under
AddressSanitizer.

Neither bug was the analysis reaching a wrong answer. Both were the
analysis never being asked: the ownership question was asked at one
syntactic shape, and values arrive by more routes than that. What made
the generic case worse than a gap is that it was a *regression under
abstraction* — the non-generic wrapper was rejected correctly, so adding
`[T]` to a working program silently removed its checking.

**Upgrading:** code that this release rejects was double-freeing before.
The default checker now errors on the unconditional shapes; the
conditional ones need `--strict-borrowck`, because refusing them by
default would also refuse the mutually-exclusive-frees pattern, which is
correct code. If a rejection is a false positive, it is a bug worth
reporting — the default checker is meant to have none, and the whole
first-party tree (stdlib, examples, 320 package files) compiles with no
acceptance change in either mode.

### Fixed

- **A heap handle can reach a second name without being copied — the
  borrow checker now follows it there.** Move tracking recognised
  exactly one way for two bindings to end up owning one buffer: the
  syntactic copy `: T b a`. But any construct that yields a *value* can
  yield an existing handle, and three that do were ownership blind
  spots — both names looked like sole owners, so freeing both compiled
  clean and double-freed at runtime (all three confirmed under ASan):

  ```
  : ( Vec i ) chosen ? flag a ( make )   // a `?` selects between handles
  = prev t                               // an assignment hands one over
  : ( Vec i ) c ( pick a 1 )             // a callee hands an argument back
  ```

  `gen_cond` / `gen_match` now publish which bindings their live arms
  could select and whether every live arm selects the same one; the
  `:` / `=` receiving the value turns that into a move. When the result
  IS one binding's handle on every path it is an ordinary move, reported
  by default. Otherwise it is a **maybe-move** — `Owned ⊔ Moved` in the
  existing lattice — reported under `--strict-borrowck`, which is also
  where the assignment and interprocedural forms land.

  Those two are conditional even though the handover is certain, and
  that is a statement about the analysis rather than the code: after
  `= prev t` the old name is still a legal way to read the live buffer
  (the stdlib's HKDF expansion does exactly that), and only liveness —
  which this checker does not compute — could say when it stops being
  one. Reads of a maybe-moved binding are never flagged; only a second
  consume is. Flagging the reads instead would have rejected 77 passing
  tests' worth of correct code.

  The interprocedural case reads a new returned-handle summary,
  `g_fn_ret_alias`, kept deliberately separate from §2.8's
  returned-parameter summary: that one answers "may the result be a
  stack reference?" and drives refdepth propagation, this one answers
  "may it be an argument's heap handle?" and drives move tracking.
  Widening one map to answer both would have moved every escape
  diagnostic that reads it. Each shape names its own reason in the
  diagnostic rather than sending the reader to hunt for a free on a line
  that only aliased. (`borrow_phi_alias_definite`,
  `borrow_strict_phi_alias`, `borrow_strict_assign_alias`,
  `borrow_strict_ret_alias`)

- **A generic function that frees its parameter is a `sink` again.** The
  borrow checker infers an auto-`sink` when a body consumes a parameter,
  so the caller of a wrapper loses the binding and a second call is a
  use-after-move. That inference is a by-product of *compiling the body*
  — and a generic body is not compiled where it is written. It is stored
  and instantiated later, under a mangled name, so the summary reached
  neither the generic name nor any call site that preceded the deferred
  instantiation. The result was a hole with no diagnostic at all:

  ```
  @ dispose [T] ( Vec T ) xs → v { ( vec_free [T] xs ) }
  ( dispose [i] xs ) ( dispose [i] xs )     // compiled clean; double free
  ```

  The identical non-generic wrapper was rejected. `compute_generic_inout_sink`
  now reads the stored template's body for the auto-`sink` case as well as
  the declared markers, so the generic and ordinary forms are checked
  alike — under the default checker for the unconditional shape, and under
  `--strict-borrowck` when the first free is on one arm of a `?`. The
  template scan reads the first argument of a call rather than every
  argument position, so it can miss, never invent.
  (`borrow_generic_sink_wrapper`, `borrow_strict_generic_maybe_double_free`)

- **`http_server_pipelined` no longer races its own client.** The test
  spawned the client with `&` from a shell that then exits — orphaning
  it — and later ran `wait $(cat pid)` in a *different* shell, where that
  pid is not a child. The wait failed instantly (hence the `2>/dev/null`
  hiding it) and only a fixed `sleep 0.10` made the test pass, which is
  not enough on a loaded CI runner. The client now writes a `.part` file
  and renames it when done — `rename(2)` is atomic, so the collector sees
  all or nothing — and the collector polls for it instead of assuming it
  has arrived. Verified against the real failure mode: under 32-way CPU
  saturation the old test dropped its client's output 1 run in 10, the
  new one 0 in 10.

## [0.41.0] — 2026-08-14

The honest-failure release. Nothing here is a new capability; every entry
is a place where the system already knew what had gone wrong and threw
the answer away before anyone could read it. The compiler emitted invalid
IR and let clang deliver the news from another function entirely. The
package manager mapped curl's exit code to a precise transport error and
then flattened four distinct causes into one `PubHttp`. A cluster read
the top byte of a big-endian partial as a status flag and reported every
healthy chunk as failed. And `nurlpkg` packed whatever happened to be
lying in the directory, so the same commit published different bytes from
different clones.

The through-line is that each of these failures pointed away from itself.
That is the expensive kind: a wrong answer costs one debugging session, an
answer that indicts the wrong component costs several.

### Added

- **The stdlib HTTP client takes a deadline.** `httpc_request_timeout`
  caps one exchange in seconds, and `httpc_default_max_time` names the
  300 s default that was previously an unexplained literal in the curl
  argument list. A server that calls an external service on a request
  path needs this: with only the default, a hung peer is indistinguishable
  from a hang of your own program, and 300 s is far past the point where
  an interactive caller should have given up.

- **`packages/nurlpkg-smoketest`** — a dependency-free ~1.8 KB package
  whose only purpose is to exercise the registry end to end (pack →
  publish → index → resolve → download → verify → extract → build → run)
  and to act as the canary for packer determinism: two clean clones must
  produce one checksum. It also retires an old hazard — probing the
  publish endpoint used to mean uploading a real package, and a garbage
  body once became a real published version.

### Changed

- **`nurlpkg publish` says which transport failed.** `PublishErr` gains
  `PubTimeout`, `PubConnect`, `PubDns` and `PubTls`, each with its own
  hint. The information was always there — `http_cli` maps curl's exit
  code to `HttpcErr` — but `pkg_publish` collapsed every variant into
  `PubHttp`, which reads identically whether the registry is down, a
  proxy is eating the request, or the upload stalled mid-flight.

- **The MCP ready event identifies the transport, not a server name.**
  The SSE `event: ready` payload carried a hardcoded
  `{"server":"nurl-mcp"}` from inside the stdlib, which was wrong for
  every other server built on it; it now reports
  `{"transport":"streamable-http"}`.

### Fixed

- **A closure containing a short-circuit `|` or `&` emitted IR that
  named a block in a different function.** A closure is lifted into its
  own `define` whose first block is `entry`, but the body inherited the
  enclosing function's `__cur_lbl__`. The first construct to phi over the
  block it started in then wrote an incoming label belonging to the
  parent — `phi i1 [ 1, %divok_11 ], …` inside a closure that has no
  `divok_11` — and the user met clang's "use of undefined value" pointing
  at neither the closure nor the cause. The bug hid from reduced repros
  because it only appears once the enclosing function has left its own
  entry block; below that, the stale name coincides with the closure's
  `entry` and the IR happens to be valid. The regression test seeds a
  branch before the closure so the shape actually reproduces.

- **`# name expr` where `name` is a binding compiled to a phantom type.**
  `llvm_type` maps any unknown identifier to the named type `%name`, so
  `# d + d 1` — a mistyped `= d + d 1` — passed with rc=0 and a discarded-
  value warning, then emitted `insertvalue %d undef, i64 …` against a type
  the module never declares. It is now a pointing diagnostic that names
  the likely typo. The check fires only when the cast target is a bare
  `%ident` that is neither a declared struct nor an enum *and* is a live
  binding, so every legitimate cast is untouched.

- **The same commit packed to different bytes in different clones.**
  `nurlpkg`'s file filter was a fixed name blacklist (`deps`, `nurl.lock`,
  `target`, `build`, dotfiles) with no notion of compiler output, so a
  stray `wasmbuilder.ll` left by a local build was swept into the tarball:
  269 147 bytes from one checkout against 35 847 from another, at the same
  revision, under different checksums. Build output is now excluded by
  extension (`.ll`, `.o`, `.obj`, `.a`, `.so`, `.dylib`, `.dll`, `.exe`).
  The filter is still extension-based, so an extensionless compiled binary
  left in the package root is packed as before — `build/` and `target/`
  remain the intended homes for it.

- **A publish whose connection died mid-transfer sat for the full 300 s.**
  `--max-time` alone cannot tell a stalled transfer from a slow one, so a
  dead upload held the terminal for five minutes and then reported
  `PubHttp`. The client now passes `--speed-limit 1 --speed-time 30`: a
  transfer that stops moving gives up in about half a minute, while a
  genuinely slow upload keeps its full deadline. Measured against a real
  fault, 300 s → 37 s.

- **Every local wasm build whose IR declared `open`/`fcntl`/`printf`
  failed to link.** `wasmbuilder` mirrored a `declare`'s parameters into a
  libc shim and copied the vararg marker in as a *named* parameter
  (`define i32 @__nurl_open_shim(i8* %a0, i32 %a1, ... %a2)`), which is not
  legal LLVM. The shim had no call sites at all. Dropping the `...` in
  `__wb_ir_decl_params` restores the whole generated-kernel family
  (`gpu_smoke.sh` 7/7, was 0/7). Shipped as `wasmbuilder` 0.1.5, with
  `nurl-mcp` 0.10.1 and `swarm-mcp` 0.24.0 requiring `^0.1.5` — a `^0.1.0`
  requirement could still resolve the broken 0.1.4.

- **A distributed task reported healthy chunks as failed, and a dead
  worker was never evicted.** `swarm-mcp` 0.24.0: the retry plan read
  `body[0]` as an "ok" flag, but an expression chunk answers with a bare
  `[partial:8]` whose top big-endian byte is almost always 0, so every
  successful chunk looked like a failure; frames are now parsed by job
  kind. Because `dist/job` *forwards* a job whose key the receiving node
  does not own, expiring members on the coordinator alone made workers
  bounce re-dispatched chunks back to a dead peer forever — every node now
  ages its own roster, and never itself (a node hears no HELLO of its own,
  and without the exemption would time itself out of its own ring).

## [0.40.0] — 2026-08-13

The machine-width release. NURL could always describe what a CPU does
one word at a time; what it could not describe was the two shapes every
fast numeric kernel is actually written in — a 128-bit product and a
vector register. Both are now in the language: `nurl_umulhi` gives the
high half of a 64×64 multiply, `nurl_addc`/`nurl_subb`/`nurl_mac` give
carry chains the backend recognises, and `v128` is a first-class
by-value type over ~27 primitives that each cost exactly one machine
instruction. None of it is a target-feature gamble — 128-bit vectors and
a 64×64→128 multiply are baseline on every 64-bit target NURL supports.

The point is what came downstream, all of it in ordinary high-level
NURL: ChaCha20 at 1.84×, HTTP head parsing sixteen bytes at a time, and
a pure-NURL TLS 1.3 handshake at 2 470 → 4 894 handshakes/s — with no
assembly, no AES-NI-tier intrinsics and no OpenSSL anywhere in the path.
Alongside: the build now caches (an empty program links in 99 ms instead
of 305, a warm `json_parse` rebuild is cheaper than that row's *cold* C
compile), the unikernel boots off a USB stick on real PC hardware, and
the MCP layer speaks the tasks extension.

### Added

- **MCP tasks extension — `stdlib/ext/mcp_tasks.nu`.** The
  `io.modelcontextprotocol/tasks` extension lets a server answer a
  `tools/call` with an asynchronous task handle instead of a final
  result, so expensive work no longer has to hold a JSON-RPC response
  open. The new module is the whole protocol side of it: a task store
  (unguessable 32-hex ids, TTL sweep, bounded retention), the wire
  shapes (`CreateTaskResult` with `resultType: "task"`, the
  `DetailedTask` body `tasks/get` and `notifications/tasks` share),
  per-request capability negotiation, and handlers for `tasks/get`,
  `tasks/update` and `tasks/cancel` — including the two rules the spec
  makes non-negotiable: a `CreateTaskResult` may never go to a client
  that did not declare the extension **on that request**, and a
  non-declaring client issuing a `tasks/*` method gets −32003 with
  `data.requiredCapabilities`. Multi-round-trip execution is supported
  through `inputRequests`/`inputResponses`, with responses to unknown or
  already-answered keys ignored as the spec requires.

  The module deliberately does not run the work: a server that wants
  tasks already owns a job engine, so a task carries an opaque `link`
  integer to tie the handle back to it, and the server drives
  `mcp_task_complete` / `mcp_task_fail` / `mcp_task_request_input`
  itself. `packages/swarm-mcp` 0.23.0 is the first consumer — its
  `compute_submit` family now hands a task-capable client a
  `CreateTaskResult` it polls over the protocol instead of through the
  bespoke `compute_result` tool.

  Note: the extension draft pins MISSING_REQUIRED_CLIENT_CAPABILITY to
  −32003, whereas the base 2026-07-28 spec renumbered its own reserved
  codes into −32020…−32099. The extension is normative for its own
  methods, so `mcp_tasks_err_missing_capability` is −32003 while
  `mcp_err_missing_client_capability` stays −32021.

- **The build caches: a rebuild costs less than a C compile.** On
  native Linux, `nurl.sh` now links with ThinLTO by default and keeps
  three caches under `~/.cache/nurl`: the link's per-module backend
  codegen (`stdlib/runtime.o` is thin bitcode now, so the runtime —
  re-optimised from scratch by every full-LTO link since the language
  existed — is a cache hit for every build after the first, of *any*
  program), the pre-link `-c` object keyed by content hash of the
  emitted IR (a rebuild whose IR didn't change is a file copy, per
  split part), and the driver's toolchain probes (~190 ms of trial
  compiles that answered questions about the toolchain, not the
  program). What made thin-with-cache safe as the *default* rather
  than a dev-mode trade is running the ThinLTO backend at O3: plain
  thin at O2 loses full LTO's second optimisation round —
  `bench/sort_window`'s compare/exchange mill came out 2.3× the
  instructions — and the O3 backend restores every such case measured,
  improving one outright (`bench/nbody` retires 36% fewer
  instructions). Measured: empty program 305 → 99 ms, `json_parse`
  840 → 156 ms (rebuild) / 574 ms (rebuild after a one-line edit),
  `http_server` 1.96 s → 0.67 s. `bench/RESULTS.md` §2 now carries a
  "NURL rebuild" column — a warm NURL rebuild (129 ms on `json_parse`)
  is cheaper than that row's *cold* C compile (144 ms) — with the cold
  columns still measured against a wiped cache so the C and Rust
  comparisons stay honest. `NURL_LTO=full` + `NURL_SPLIT=0` remains
  the maximal-inlining release build; `NURL_CACHE=0` opts out;
  `NURL_SPLIT_MIN=16384` is the opt-in fastest-edit-loop knob
  (`json_parse` edit rebuild 574 → 310 ms, at +7% run-time
  instructions). Scope: native Linux clang; the zig-cc, macOS ld64 and
  Windows paths keep the previous behaviour. One runtime fix rode
  along: the fiber test hooks' context structs are now extern — a
  ThinLTO link may import `nurl__ctx_bounce` into another module, and
  the asm string inside it names those structs, which LTO cannot see
  (the `used`-is-load-bearing comment in `runtime_ctx.c`, one clause
  further). Details: docs/BUILDING.md → The ThinLTO cache.

- **SIMD in the language: the `v128` type and its primitive layer.**
  NURL now has a vector register. `v128` is a first-class by-value type
  (bindings, parameters, returns) lowered to LLVM's target-independent
  `<4 x i32>`, with ~27 `nurl_v128_*` primitives — load/store, lane
  arithmetic, shifts, rotates, lane permutes, byte-compare bitmasks and
  ASCII case folding — each emitted `alwaysinline` so it costs exactly
  one machine instruction. 128 bits is baseline on every 64-bit target
  NURL supports (SSE2 is part of the x86-64 ABI, NEON part of AArch64),
  so a vector kernel needs no CPUID probe, no target-feature attribute
  and no fallback path; it lowers to `simd128` on wasm and scalarises
  anywhere else. Scalar bit primitives ship alongside — `nurl_ctz`,
  `nurl_clz`, `nurl_popcnt`, `nurl_bswap32/64`, `nurl_rotl/rotr32/64`.
  See docs/spec.md §4.1b.

- **`nurl_umulhi` — the high half of a 64×64 multiply.** NURL's `*`
  already gave the low 64 bits; together they are the 64×64→128 multiply
  the language could not spell, and its absence was the reason every
  wide-radix numeric kernel in the stdlib had to pick a narrow limb size
  that kept partial products inside an i64. Defined in
  `stdlib/runtime_core.c` over `unsigned __int128` (with a 32-bit-halves
  fallback under `NURL_NO_INT128`) **and** emitted as a
  `linkonce_odr`/`alwaysinline` i128 definition in nurlc's preamble,
  exactly like `nurl_peek` — so it inlines to one `mul`/`umulh` with or
  without LTO, on every backend, while runtime.o's C definition still
  wins at link. Every crypto speedup below is downstream of it.

- **Wide arithmetic: `nurl_addc`, `nurl_subb`, `nurl_mac`.** The
  companions to `nurl_umulhi` — the high half of a sum, of a difference,
  and of a multiply-accumulate (`a·b + c + d`, which cannot overflow 128
  bits and is exactly one limb step of a Montgomery multiply). The
  language could already *spell* a carry; what it could not spell was a
  shape the backend recognises. Measured on a four-limb add: 15
  instructions through these, against 26 for the hand-rolled wrap test
  they replace — the four limbs now legalise to `add; adc; adc; adc`.

- **The unikernel boots on real hardware, off a USB stick.** The x86_64
  image booted QEMU, Firecracker and cloud-hypervisor because they read
  its PVH note; no PC firmware does — a BIOS reads a boot sector, UEFI
  reads a PE binary off a FAT partition. The same ELF now carries a
  second door, a Multiboot2 header and `_mb2_start` beside the PVH note,
  and `build_bootable_image.sh` packages it into a hybrid BIOS+UEFI disk
  that `dd` writes straight to a stick. The two entries meet six
  instructions later — they hand over in the same machine state — so
  `kmain` and `mem_init` are untouched and the PVH gate stays 20/20.
  Four things a PC has that a microvm does not, each fixed at the root:
  no serial port (`boot/console.c` draws the same bytes on the screen —
  EGA text under BIOS, a linear framebuffer with an 8×16 font under
  UEFI, armed only on a Multiboot2 boot); nobody states the TSC
  frequency and on an AMD part neither CPUID leaf exists
  (`pit_calibrate_khz` counts TSC ticks against PIT channel 2 for 10 ms,
  and `nurl_clock_source` reports which of five sources answered); GRUB
  re-quotes the command line, so `build_argv` now finds the key and lets
  the quoting decide where the value ends; and the UART wait loop was
  unbounded, so a chipset answering 0x00 would hang before printing what
  would have said why. `grub-mkrescue` is deliberately not used — its
  `-d` takes one platform directory and derives nothing, so outside
  `/usr/lib/grub` it silently omits one firmware's image; the two boot
  images are built with `grub-mkstandalone` and assembled with
  `xorriso`, so the build runs unprivileged and in CI.
  `demos/baremetal.nu` is what goes on the stick first, and
  `tests/baremetal_gate.sh` checks the header structurally everywhere
  and boots the hybrid disk under SeaBIOS where the tooling exists
  (three mutations caught). Verified end to end under both SeaBIOS and
  OVMF. Font glyphs are generated from Spleen (BSD-2-Clause); NOTICE
  carries the notice.

- **`stdlib/std/p256_scalar.nu` — fixed-width arithmetic mod the P-256
  group order.** The point multiply already ran on the fast Montgomery
  field mod *p*; the SCALAR arithmetic mod *n* (`r·d`, `z+r·d`, and
  above all `k⁻¹`) still ran on variable-length `std/bigint.nu`, where
  `k⁻¹` is a 256-iteration Fermat modpow that clones a heap magnitude
  every step. The new module gives *n* the same treatment *p* had: four
  64-bit limbs, Montgomery CIOS via `nurl_umulhi`, no allocation in the
  multiply, Fermat inversion over that field. *n* has no `p ≡ −1
  (mod 2^64)` shortcut, so the reduction carries the general Montgomery
  constant `n0 = −n⁻¹ mod 2^64`. It exposes reduce / mulmod / addmod /
  inv over 32-byte big-endian scalars — the shape ECDSA already carries
  them in.

- **The HTTP benchmark measures TLS, and its report is generated.**
  `bench/run_http.sh` measured only plaintext and printed a table
  someone pasted into a hand-maintained `bench/HTTP_RESULTS.md`. It now
  runs a second HTTPS pass against all three peers — NURL through the
  same `HttpApp` facade's `http_app_listen_tls`, Rust through
  `tokio-rustls` (the stack axum/warp use), Node through the built-in
  `https` module, each switched at startup so the plaintext path is
  unchanged — with a self-signed EC P-256 cert generated per run. The
  measurements feed `bench/gen_http_results.py`, which overwrites
  `HTTP_RESULTS.md` wholesale, giving it the same "do not edit by hand"
  contract `bench/RESULTS.md` has. `.github/workflows/http-bench.yml`
  runs the same install → build → run → commit flow as `bench.yml`,
  deliberately `workflow_dispatch` only: HTTP load numbers on a shared
  CI VM are far noisier than the wall-clock suite, so a refresh is
  opt-in.

- **`tools/check_windows_paths.sh` — a CI gate for paths Windows cannot
  represent.** Reserved DOS device names (CON, PRN, AUX, NUL, COM1–9,
  LPT1–9, at every directory, in any case, with any extension),
  reserved characters, trailing dots or spaces (Win32 strips them, so
  the file that arrives is not the one committed), and paths differing
  only in case. Catching these on Windows is catching them too late —
  the failure lands at the *checkout* step, upstream of anything that
  can explain itself, and the log names neither the rule nor the file.
  The gate reports it on Linux, naming both. 4/4 mutations caught.

### Changed

- **The pure-NURL TLS 1.3 handshake is ~2× faster: 2 470 → 4 894
  handshakes/s.** A profile of the handshake put its cost in four
  places, and each was taken in turn — all in high-level NURL, with no
  assembly and no AES-NI-tier intrinsics. `nurl_umulhi` (above) is what
  made every one of them expressible.

  - **Poly1305 to radix 2^44.** The accumulator was five 26-bit limbs,
    a radix chosen only so each `h·r` partial product stayed under 2^63
    and plain i64 arithmetic sufficed. Rewritten as poly1305-donna-64:
    three 44/44/42-bit limbs, each `h·r` term a full 128-bit product
    accumulated as an explicit (lo, hi) pair — nine multiplies a block
    instead of twenty-five. Poly1305 alone 1 206 → 1 617 MB/s (+34%);
    ChaCha20-Poly1305 seal 397 → 432 MB/s, open 398 → 435 MB/s.
  - **P-256 field multiply to 4×64 CIOS.** `__p256_mul_d` was
    Montgomery CIOS over eight 32-bit limbs — 64 partial products a
    multiply. It now works in four 64-bit limbs (16 full 64×64→128
    products) while the field's external representation stays 8×32, so
    add / sub / conditional-subtract, every constant table and the whole
    point-addition and inversion layer are untouched. P-256 ECDH keygen
    654 → 375 µs/op (−43%).
  - **X25519 and Ed25519 field to 5×51 donna-c64.** The shared
    GF(2^255−19) field was the TweetNaCl 10-limb radix-2^25.5 form,
    whose limbs are narrow precisely so ten accumulate inside an i64.
    Rewritten as curve25519-donna-c64: five unsigned 2^51 limbs, so the
    multiply is 25 products against 100 and the square 15. The ladder,
    Fermat inversion and public surface are untouched. X25519 scalar
    mult 137 → 69 µs/op (2.0×); Ed25519 sign 387 → 225 µs/op (−42%).
  - **ECDSA signing off generic bigint.** `ecdsa_p256_sign`'s tail
    swaps its five bigint operations for `p256_scalar` (above),
    dropping the generic path and its allocation churn out of the hot
    path entirely. Handshake-crypto microbench 47.4G → 12.3G
    instructions; live handshake rate 2 470 → 6 079/s single-core.
  - **Fixed-base combs for `k·G` and `x25519_base`.** Both are
    fixed-base multiplies — the base is the same constant every time —
    so the doublings a variable-base ladder pays can be precomputed
    away. `p256ct_scalarmult_base` is a 4-tooth Lim–Lee comb over a
    baked 15-entry table: ~64 D + 64 A against ~256 D + 64 A, still
    fully constant-time (it reuses the masked table scan the secret-path
    window ladder already uses). For X25519 the Montgomery x-only ladder
    *cannot* precompute — x-only has no complete addition — so
    `x25519_base` instead computes `scalar·B` on twisted Edwards, which
    does, and converts to the Montgomery u-coordinate via
    `u = (Z+Y)/(Z−Y)`; self-contained in `x25519.nu` on its own
    donna-c64 field, so it adds no dependency on `ed25519.nu`. Both
    variable-base paths (ECDH shared secret) are unchanged.
    Handshake-crypto microbench 12.3G → 7.9G instructions;
    `x25519_base` alone 73.5 → 50 µs (1.47×).

  Every one of these was ported **Python-first**: a reference oracle
  reproduced the exact limb arithmetic and was diffed against a bigint
  or reference implementation before a line of NURL changed. That is how
  the P-256 reduction's carry bug (a wrap flag read against the
  just-overwritten accumulator limb, always false) was found at the
  source rather than worked around. RFC 8439 / RFC 7748 / RFC 6979
  vectors, `crypto_evp`, `noise_handshake` and `minisign_verify` pass
  throughout, and the changed paths are ASan-clean. All compiler-clean
  apart from `nurl_umulhi` itself — no bootstrap movement.

- **ChaCha20 is a vector kernel: 577 → 1064 MB/s (1.84×).** Written in
  pure NURL on the `v128` primitives, two blocks interleaved. The
  one-block kernel was the instructive failure: a quarter of the
  instructions but only a twentieth of the time, because a single
  ChaCha block is one dependency chain and retires 1.5 instructions per
  cycle where the scalar path's four independent quarter-rounds run at
  the machine's 4.2 issue limit. Two chains fill the pipeline. Output is
  byte-identical to the scalar path, which remains as the reference and
  as the big-endian implementation (`compiler/tests/chacha20_simd_agree.nu`
  pins every length 0–300 at three counters and offsets).

- **HTTP head parsing scans sixteen bytes at a time.** `__find_head_end`,
  `__bindex_crlf`, `__bindex_byte`, `__skip_ows` and `__string_eq_ci`
  now run on `stdlib/std/simd.nu`'s vector scanners instead of per-byte
  loops (and one libc `memmem`). The CRLF and `\r\n\r\n` searches are a
  single pass: compare against CR and LF, then AND the two bitmasks
  against themselves shifted, so a bit survives only where the sequence
  actually begins. Case-insensitive header matching folds only `A`–`Z`,
  so `^` and `~` — both legal HTTP token characters, and both folded
  together by the usual `x | 32` trick — stay distinct.

- **P-256, P-256 scalar and X25519 field arithmetic on the new
  primitives.** The CIOS Montgomery loops in `__p256_mul_d` and
  `__sn_mul` are unrolled and register-resident; `__sn_mul` no longer
  allocates and frees a 48-byte accumulator on every scalar multiply.
  The five hash modules take their rotations from `nurl_rotl/rotr`
  rather than a shift pair and an `or`.

- **Measured end to end** (12-core Haswell-E, C=10, keep-alive, against
  the same host's `hyper` / `tokio-rustls`): plaintext 20.90 → 20.10 µs
  CPU per request, TLS 27.60 → 26.40 µs. NURL was already cheaper per
  request than hyper on plaintext (22.70 µs) and is now cheaper than
  tokio-rustls on TLS too (26.70 µs).

- **The QEMU guest gates boot the SIMD corpus on all three
  architectures.** `v128` is the one part of the language whose codegen
  genuinely differs per ISA — `nurl_v128_eqmask8` is a `pmovmskb` on
  x86-64 and a shift-and-narrow sequence on AArch64, and an `align 1`
  vector load is a different instruction on each — so a lane or bit
  order that came out backwards would be silent everywhere the tests
  did not look. `run_qemu_tests.sh`, `run_qemu_arm64_tests.sh` and
  `run_qemu_riscv64_tests.sh` now boot `simd_scan`, `wide_arith`,
  `chacha20_simd_agree` and `http_request_parser` against the same
  hosted goldens, alongside the existing corpus. Four seconds under TCG.
  Verified: AArch64 19/19, RISC-V 20/20 (both including `httpd`, the
  guest HTTP server against a host client), x86-64 boots the four new
  ones too. The hosted cross-builds were driven as well — the
  `bench/http_server.nu` binary cross-linked for `aarch64-linux-musl`
  and `riscv64-linux-musl` serves correct plaintext responses under
  qemu-user, and negotiates TLS 1.3 `TLS_CHACHA20_POLY1305_SHA256` with
  a real OpenSSL client on both.

- **The HTTP benchmark report says where its own numbers stop being
  trustworthy.** The high-concurrency latency cells were a closed-loop
  coordinated-omission artifact: at C=200 NURL's 10 blocking workers
  saturate, the other ~190 connections queue inside `oha` and never
  reach the server, so a p50 of 0.06 ms describes the handful in flight
  — not the 200 offered. Every closed-loop cell now carries its mean
  latency, the renderer computes the in-flight count by Little's law,
  and a cell is marked `‡` when that falls ≥2 connections below the
  offered concurrency. Throughput stays — it is the server's true
  saturation figure — but latency winners are now chosen only among
  non-starved cells, so a starved 0.06 ms no longer bolds or beats a
  real one (Rust's genuine 0.63 ms at C=200 wins that row). A new
  connection-setup section measures what the keep-alive tables amortise
  away: HTTP conn/s and, for HTTPS, TLS handshakes/s — the cost a
  short-lived-connection edge deployment actually pays — which also
  corrects an old note that claimed the TLS tables measured the
  handshake and then contradicted itself. A "planned rigor" section
  names what the harness does *not* yet do (open-loop latency, core
  isolation, µs/req via getrusage, large-body record throughput), so the
  limits are on the page instead of left for a reader to discover.

### Fixed

- **The Windows CI job died at `Checkout`, before a line of the build
  ran.** `unikernel/boot/con.c` — the obvious name for a console — is a
  path Windows cannot create: CON is a reserved character device at
  every directory, in any case, with any extension, so git refuses to
  try. Renamed to `console.c`/`console.h` with a `console_*` prefix so
  nothing is left that tempts the name back, and the class as a whole is
  now gated on Linux (see `tools/check_windows_paths.sh` above).

## [0.39.0] — 2026-08-12

The diagnostics-hardening release. A corpus-wide mutation probe (one
realistic mistake injected into each of the ~790 test programs, ~5 400
mutants per run) drove six root-cause series (#874–#879): at the start it
found 401 broken programs the compiler accepted and only the LLVM
verifier/linker rejected, plus 9 inputs that hung the compiler forever;
at the end it finds **zero** — every mutant either compiles correctly or
dies with a single anchored `file:line:col: error:` naming the rule and
the cure.

### Fixed

- **A missing `}` cascade now leads with the real cause, and the
  no-generic error carries a full location.** A function declaration
  swallowed into the previous body by a missing `}` parsed as a
  struct-literal opener and died with "expected '{' but found 'b'" —
  blaming a missing operand on the wrong line entirely (263 of the
  probe's drop-close-brace mutants cascaded from that misdiagnosis).
  An `@ name …` statement whose tail reads like a function header (a
  `→` before any `{`) now says exactly that: declarations do not nest,
  the `}` above never closed the previous function. And the "call to
  generic function … but no generic of that name" error gained its
  column (`file:line:col: error:` like every other diagnostic).

- **A surplus operand spilling into a statement-form arm's tail is now
  a diagnostic, not a silent no-op.** `= fails + fails 1 1` inside a
  `? … { }` statement parsed as `= fails + fails 1` plus a bare
  literal `1`, which the dangling-operand check exempted as "the
  block's value" — but the conditional's value is discarded, so the
  literal was dead and the mistake invisible (85 of the mutation
  probe's extra-operand mutants compiled silently through exactly this
  hole). The exempted literal is now recorded instead; a value join
  (phi) consumes the record — `: i x ? c { 1 } { 2 }` stays legal —
  and a `?`/`??` statement that finishes void with the record still
  set dies with the caret on the surplus literal and the arity
  cascade named.

- **Errors inside generic bodies now point at the template's real
  file and line — and a missing import is a real diagnostic.** A
  diagnostic raised while re-parsing a generic instantiation used to
  read `<generic scale2__i64 from file:N>:1:C: …` — a "filename" with
  spaces no tool can parse, pointing at line 1 of a one-line buffer
  nobody can open. Template capture is now line-preserving and the
  re-lex buffer is padded to the template's own start line, so the
  same error reads `stdlib/std/sort.nu:37:9: error: …`; the
  instantiation half of the story (mangled name, first call site,
  "may depend on the concrete type arguments") is appended to the
  message via a nesting-safe context suffix every die/warn emitter
  understands. The no-generic-found error gained its missing `error:`
  tag, and a `$` import naming a nonexistent file — formerly a bare
  `nurlc: cannot open '<path>'` from the C runtime with no location —
  is now anchored at the `$` directive in all four places imports are
  read (the three pre-scans and the parser), with the resolution
  order spelled out.

- **The last invalid-IR escape hatches from the mutation probe are
  closed.** Four more ways broken source reached the LLVM verifier
  (rc 0 from nurlc, a .ll line number, no source location) are now
  front-end diagnostics, and one is now simply correct output:

  * a top-level declaration with type and name swapped
    (`: PI_FIXED i 314`) emitted an undefined-type global; with a type
    keyword in the name slot the diagnostic names the swap and spells
    the corrected declaration;
  * a generic template's bare name used as a type (`Pair p` field,
    `JArr Vec` enum payload) emitted unsized `%Pair` / `%Vec`; both
    sites now run the known-type check, which learned to say "a
    generic names a family of types" with the instantiation spelling;
  * an aggregate value as a binary-operator operand (`= cnt + cnt`
    swallowing the `??` below it) emitted `add i64 …, { i1, i64 }`;
    rejected with both facets named — no aggregate arithmetic, and the
    arity cascade that put one there;
  * a surplus value in an anonymous aggregate literal
    (`@ ?i { T + n 2 2 }`) emitted an insertvalue past the last slot
    (or silently overwrote a result's sibling arm); anonymous shapes
    now get the arity check named structs already had;
  * statements after a terminator (`^ 1` then a call; cleanup + a
    defensive `^` after an infinite loop) rode LLVM's
    implicit-block-after-terminator quirk and were invalid IR whenever
    the dead run did not itself end in `^`; dead statements now
    compile into a fresh unreferenced block — valid IR on every shape,
    identical semantics, and LLVM's DCE drops it.

- **A missing `}` in a generic template or a closure body no longer
  hangs the compiler.** `collect_fn_body` (generic function/struct
  template capture) and `simple_capture_analysis` (closure capture
  pre-scan) walked braces with no EOF guard, so `nurlc file.nu` spun
  forever on an unclosed body — the drop-close-brace mutation hung on
  every generic-using corpus program (9/9). Both loops now stop at EOF
  with a hard error anchored at the opening `{` that never closed,
  naming the cure (add the `}`; an extra `{` inside skews the count
  the same way) and pointing at nurlfmt, whose re-indent makes the
  runaway nesting visible.

- **Every value a function hands back is now type-checked — the
  implicit fall-off tail and closure tails included, and the
  integer→pointer hole is closed at all four value positions.** A
  corpus-wide mutation probe (one realistic mistake per program, 5331
  mutants) found 401 broken programs that nurlc accepted (rc 0) and
  only clang/the LLVM verifier rejected — three build stages later,
  with a .ll line number and no source location. 390 of them were one
  hole: an integer value where a pointer/string type is declared
  (`^ n` from a `→ s` fn emitted `ret i64 %n` out of a `define i8*`).
  The old carve-outs for a "null idiom" (`^ 0`, `: *T p 0`, `@ P { 0 }`)
  protected IR that was itself invalid — `store i64* 0` /
  `insertvalue %P …, i64 0` never linked, so no working program used
  them. Implicit integer→pointer conversion is now rejected at return,
  binding init, assignment, and struct-literal fields, each with the
  cure spelled out (`# *T expr`; the null pointer is `# *T 0`), and the
  spec's null-idiom paragraph is rewritten to match reality.

  The return-agreement battery (float/pointer/width/aggregate/nominal/
  enum checks + the enum wrap) moved into one shared helper
  (`ret_ty_agree`) that every return path runs — explicit `^`, the
  function fall-off tail, and closure tails. Fall-off consequences:

  * a value-returning body that falls off with **no value** used to
    emit `ret i64 undef` — *valid* IR returning garbage; it is now the
    "function body ends without a return value" error (with the
    count-your-braces hint, since an extra `}` truncating a body is the
    other way to arrive there);
  * a **bare enum variant** or a **`??` whose value arms are all
    variants of the declared enum** returned by fall-off used to emit
    `ret %Color <i64 tag>` — invalid IR; both now wrap correctly
    (gen_match learned to publish the join-variant proof gen_cond
    already had);
  * an exhaustive `??` whose arms all `^`-return now terminates its
    end label (`unreachable`) even without a fallback edge, so the
    two-way T/F result dispatch counts as a closed path;
  * a tail call into a noreturn chain is exempt: `nurl_exit` /
    `nurl_panic` seed a registry, functions whose bodies contain no
    `^` and whose tails diverge are inferred noreturn (private-name
    mangling respected), and a `~ T` loop with no `break` targeting it
    counts as diverging — so `die`-style helpers and loop-only-return
    functions (stdlib's Hoare partition) need no dead `^`.

  `llvm_to_nurl` also learned to spell pointers back as NURL types
  (`i64*` → `*i`), so the new messages name types the way the user
  wrote them. Re-running the probe: 0 of the 488 wrong-return-type
  mutants reach the linker; each dies with one diagnostic naming the
  rule and the fix.

## [0.38.0] — 2026-08-11

### Fixed

- **A local callable now shadows a same-named trait/impl method at call
  sites — `nurlpkg install nurllama` works again.** On v0.37.1 the
  install died inside the *stdlib*:

  ```
  <generic vec_free_with__String from stdlib/std/path.nu:352>: error:
  method 'drop' has no impl for receiver type 'String'
  ```

  `vec_free_with [A] v ( @ v A ) drop` calls its callback **parameter**
  as `( drop . buf i )`. Function-typed parameters resolve via the
  `__param` marker, not `__ptr` — and impl-method dispatch only excused
  `__ptr`/`__arity`/`__ffi` names. So the moment any file with a
  `% Drop <T>` impl entered the import closure (nurllama 0.16.0's new
  `history.nu` imports `ext/sqlite.nu`, which impls `% Drop Database`),
  every call through a parameter named `drop` was treated as trait
  dispatch. Worse than the error: a receiver type that *did* have an
  impl would have silently called the impl instead of the parameter.
  The callee is now checked for a local callable (closure-struct or
  fn-pointer typed `__ptr`/`__param` binding) before impl dispatch,
  exactly as locals already shadow the bare-`@fn` arity check; scalar
  and named-struct locals sharing a method's name still dispatch.
  Gate: a differential sweep of all 1437 tracked `.nu` files —
  byte-identical IR/stderr/exit everywhere except the two files that
  flip from compile-error to compiling (`nurllama/history.nu`,
  `registry/db.nu` — the same sqlite + path combination). (#868)

- **A string-literal `?`-arm used directly as a call argument no longer
  leaks the picked literal per evaluation.** `( f ? cond `a` `b` )`
  materialised the chosen literal as an owned heap temporary that no
  drop was ever emitted for — ~32 bytes *per evaluation*, which a
  4-billion-parameter LoRA finetune turned into ~3.6 MB/step of host
  leak (the per-launch kernel-name prefix had exactly this shape) and
  the kernel OOM killer ended two 5-hour training runs. Literal/literal
  joins are now uniformly borrowed with zero allocations; literal/owned
  mixes are repaired at the join block (copy the picked pointer, free
  the owned original through a null-select); owned/literal keeps a
  correctly-gated eager copy. Covered by a test running every
  ownedness mix through both paths. (#865)

- **`server_run_async` no longer leaks ~192 bytes per accepted
  connection.** The accept loop spawns a fire-and-forget closure per
  connection, and `spawn` BORROWS its env — there was no correct place
  to free it (LSan: 101 allocations for 101 connections). The loop now
  uses the new `spawn_owned` (below). (#867)

- **The whole fiber `spawn` family is now `noinline` — closing a
  TLS-under-LTO miscompile window.** Adding a new spawn entry point
  made the async HTTP test hang *deterministically*: LTO inlined it
  into NURL code and mislowered the `__thread` scheduler-worker access
  (the exact class the existing `noinline` on `nurl_fiber_current` /
  `yield` / `park` documents), so the spawned fiber was enqueued onto a
  queue no worker drains. The existing entry points dodged this only by
  the optimizer's inlining choices. (#867)

### Added

- **`spawn_owned` — a fire-and-forget fiber that owns its closure
  env.** `( spawn_owned \ → v { … } )` transfers the env to the fiber;
  the runtime frees it right after the body returns. Use it for
  per-item inline closures nothing else holds a handle to (one fiber
  per accepted connection); plain `spawn` still borrows, which is right
  for a long-lived closure the spawner frees later. (#867)

### Changed

- **HTTP serving got measurably faster at the root, not the margins.**
  Profiled under load (perf + `strace -c` + per-thread CPU accounting)
  and removed every per-request cost that was structural rather than
  essential: the keep-alive loop built **and freed a full fallback-500
  response on every request** (now hoisted to the connection, rebuilt
  only after a panic actually consumed it); the Connection-header
  checks allocated an owned String copy per request even on a miss (now
  an allocation-free in-place scan); carry-buffer compaction was three
  per-byte copies (now one `memmove`); header serialisation indexed
  with `nurl_str_get` — strlen per byte, O(n²) — and pushed
  byte-at-a-time (now one scan + one `memcpy`). The async net wrappers
  toggled `O_NONBLOCK` per operation — **4 fcntl syscalls per request,
  46 % of the async server's syscall time** — now memoized on the
  handle; an HTTP request is served in 2 syscalls. (#866)

- **The async scheduler stopped paying for work it wasn't doing.**
  Under an HTTP load the work-stealing path ran **26 steal attempts per
  request with a 0.008 % hit rate** — ~24 futile victim-lock
  acquisitions per request; each worker now keeps an exact queue length
  read lock-free by the probe, and stealing skips empty/singleton
  victims without touching their lock. Every reactor park also
  calloc'd/free'd its wait entry across threads; entries now recycle
  through a freelist under the existing lock. Async hello server:
  **44.4 → 38.4 µs CPU/request, C=200 throughput 237k → 261k rps**.
  (#867)

- **`bench/http_server.nu` now serves through the `packages/http`
  HttpApp facade** — the surface a real NURL service deploys — and
  `bench/HTTP_RESULTS.md` is refreshed (the old table was months
  stale). Fresh medians (i7-5930K, oha, 3×10 s): **NURL 15.3k / 166k /
  144k / 151k req/s at C=1/10/50/200 — ahead of Rust hyper at C=1 and
  C=10** with p50 flat at 0.06 ms; the C≥50 gap is the blocking-pool
  ceiling, and the async path's remaining reactor serialization is
  recorded in the backlog with measurements. The packages/http facade
  itself (0.3.2) dropped a recover layer that duplicated the stdlib
  server's unconditional panic→500 guarantee — one throwaway
  500-response build per request for zero added safety. (#866)

## [0.37.1] — 2026-08-11

### Fixed

- **`json_parse` back to fastest in the benchmark table — the RFC 8259
  control-byte scan was accidentally quadratic.** The conformance fix
  in 0.36.0 (#817) added `__jp_span_ctrl`, a linear scan over the
  escape-free fast path's span, and indexed it with `nurl_str_get` —
  whose bounds check re-runs `strlen` on every call. The span is a
  pointer into the *middle* of the document, so every one of those
  strlens walked to the document's end: the "linear" scan was
  O(span × rest-of-document), and the benchmark's `json_parse` went
  from fastest of the five languages (8.8 ms) to slowest of the
  compiled three (42 ms). The scan now reads through a raw pointer,
  the way the accessor's own documentation says every parser loop
  must. Conformance is untouched — the same tests pass — and the row
  is NURL's again.

- **Playground: the "container is not running" rollout window no longer
  reaches users.** During the v0.37.0 image rollout play.nurl-lang.org
  served `Error proxying request to container: The container is not
  running, consider calling start()` — the Durable Object proxied to an
  instance that no longer existed, and the Worker's recovery policy,
  which knows the *not listening* wedge and the transient restart
  strings, did not know this one, so it passed through as a 500 instead
  of triggering a teardown and cold-start retry. The string now
  classifies as wedged: destroy clears the stale instance state and the
  replay lands on a fresh container. Covered by `test:recovery` with
  the literal production body.

## [0.37.0] — 2026-08-11

### Added

- **`tools/check_diag_coverage.sh` — a diagnostic is not finished when it
  is written, it is finished when something has read it.** The `ax` work
  scored diagnostics by scanning `compiler/nurlc.nu`: does the message
  name a cure, state the rule, show a spelling. That instrument is blind
  to the one thing that decides whether a message is any good — whether
  it is ever REACHED. The new gate compiles the corpus, matches every
  emitted diagnostic back to its source site, and reports the sites
  nothing made speak. It found **88 of 220 sites unread** on its first
  run. At this release: **191 of 229 exercised, 17 never fired, 14
  ambiguous, 7 unmatchable by text** — the three categories after
  "exercised" are the tool declining to claim more than it can prove.

  An unfired message is unverified in every way that matters. Its wording
  has never been read next to the program that caused it, which is how
  the one FALSE message found in `ecc058c` survived a source scan that
  scored it as excellent. Its caret has never been checked. It may be
  dead outright, preempted by a looser check upstream — so the good
  message exists and the user still gets the generic one.

  The count ratchets against `tools/diag_coverage_baseline.txt`: existing
  gaps do not fail the build, a new die site with no test that fires it
  does. Adding a diagnostic and adding the program that triggers it are
  one change, not two.

- **macOS is a host platform CI actually checks (Apple Silicon, tier 1).**
  `docs/PLATFORMS.md` used to say macOS was "expected to build from
  source with Homebrew LLVM; unverified". Expected-to-build was a claim
  nobody had run, and running it found five real defects — four of them
  invisible from Linux and FreeBSD, because those two share a heritage
  macOS does not (GNU-ld-family linkers, `timeout(1)` in base).

  The new `macos-tests` workflow runs the full host path on every push to
  `main` and every PR: `./build.sh` (bootstrap fixed point + the corpus),
  the `nurl.sh` driver end to end, and the examples gate. The corpus runs
  against the **same** `compiler/tests/outputs/` goldens as Linux and
  FreeBSD rather than a divergent `outputs-macos/` tree, so a macOS-only
  miscompile cannot hide as a platform difference — it passed 641 of 641
  when the leg landed, and the corpus has grown to 780 files since.

  Apple Silicon only. `macos-13`, GitHub's last Intel image, never left
  the queue across ten runs, and a required check that cannot schedule
  blocks every PR — so macOS x86_64 stays tier 3 rather than being
  claimed on a gate that never reports.

- **`tools/check_diag_anchor.sh` — a diagnostic must point at the
  mistake.** Coverage answers "has anything ever printed this?"; it
  cannot answer "did it point at the right thing?", and the two are not
  equally bad. A precise message against the wrong line is worse for a
  reader than a vague one against the right line, because it sends them
  somewhere real to look for a problem that is not there.

  No annotation is needed to catch the mechanical case. Many checks can
  only fire once their operands are consumed, and by then the lexer sits
  past the statement — so `die lex` anchors on whatever came next. When
  the mistake is a function's LAST statement, what came next is the
  closing brace, and the compiler prints a caret under a `}`. The gate
  reads the committed goldens (they already hold the location, the
  echoed line and the caret) and rejects two shapes: an anchor line
  holding nothing but closing delimiters, and a caret column past the
  end of the line it echoes. Unterminated-construct messages are exempt
  — there, end-of-input really is the subject.

  **It found nine on its first run**, and a tenth once the column rule
  was added. Fixed and held at zero, so this one gates rather than
  ratchets.

- **`tools/diag_mutate.py` — one realistic mistake in a real program.**
  Every negative test in the corpus is minimal by construction: the
  mistake *is* the program, so there is nothing after it to go wrong. A
  model writes a hundred lines and gets one of them wrong, usually not
  the last one. This probe takes working programs, injects a single
  mistake a model plausibly makes, and counts what comes out — one
  diagnostic (good), several (a cascade to triage), or **none**.

  Not a gate: the mutation set is a judgement about what models get
  wrong, and the interesting result is a program to go and read, never a
  number to enforce. Its first run reported six programs silently
  accepted; every one was the mutation landing inside a comment, which
  is the same masking lesson `diag_coverage.py` already carries, learned
  the same way.

### Changed

- **The n-ary `&`/`|` arity trap is a hard error by default;
  `--no-strict-arity` demotes it back to a warning.** As a warning the
  trap was the worst possible outcome: `? & a b c d { … } { … }`
  compiled to `status: ok` and a binary whose conditional logic is
  wrong, and nothing downstream could tell — the whole reason
  `--strict-arity` and its CI gate existed. The first-party tree has
  been strict-clean since that gate landed, so the default now matches
  what the repo already enforced. `--strict-arity` stays accepted as a
  no-op for compatibility.

  The check has two known legitimate-but-flagged shapes — a `~` loop
  whose condition is a bare-arm `?` (`~ ? flip < n 3 < n 5 { … }`), and
  a bare `{ … }` scoping block immediately after a bare-arm `?` — both
  with trivial rewrites (fold the ternary into `&`/`|` logic; drop or
  move the scoping block). A tree that hits them faster than it can fix
  them builds with `--no-strict-arity`, and the error message names
  that escape hatch.

- **Coverage fingerprints now discriminate rather than merely being
  long.** Picking the longest literal at a site is the obvious rule and
  the wrong one: the longest run is usually the shared explainer tail
  two sibling messages both end with, while the sentence that differs —
  the one naming which construct was rejected — is shorter and got
  discarded. Nine sites read as indistinguishable for that reason alone,
  which was the instrument's fault and not the compiler's. The tool now
  prefers a literal no other site carries. **Six real gaps came out from
  behind a sibling's hit**, having been counted as exercised for as long
  as the tool has existed.

- **The diagnostic-coverage number was overstated, and now is not.**
  Matching is by message text, so two sites emitting the *same sentence*
  are indistinguishable — one test made both read as exercised. Eleven
  such groups existed, covering 30 sites; the worst prints
  `cannot store a value of type … into an element of type …` from **six**
  places. Those are reported as **ambiguous** rather than folded into
  "exercised". A number that flatters the instrument is worse than a
  smaller one that is true, and this instrument had been reporting its
  own best case for eight passes. The correction cost 28 sites at the
  time; the entry above carries the figure as it stands at release,
  since a later pass sharpened the matching again.

### Fixed

- **Five silent-compile sweeps landed without release notes.** They were
  merged after 0.36.0 was cut and each shipped its own tests, but none
  wrote a `CHANGELOG` entry, so the release would have understated what
  it contains. Recorded here from their commits:

  * **Trait dispatch.** Calling a trait method with a receiver whose
    type has no impl fell through dispatch and emitted a call against an
    undefined symbol — an error only clang reported, far from the call.
    Impl-method calls, static and through the vtable, never checked
    arity at all: `( speak d )` against `speak Dog d i volume`
    assembled, and the callee read an unset register. Five pre-existing
    leaks in the dyn path went with it.
  * **FFI call arity, float casts, and `u8`.** `( sin 1.0 2.0 )` against
    a one-parameter declaration assembled and ran with the surplus
    ignored; `( pow 2.0 )` read an unset ABI register. `# f x` emitted
    `sitofp` from a struct, an enum or a string — invalid IR only clang
    saw. And the documented `u8` spelling had never worked: it was
    missing from `llvm_type`'s ladder, so every `: u8 x` carried a
    phantom `%u8` type.
  * **Generic call type-argument arity.** A surplus type argument
    compiled clean and resolved to a monomorph no other site shares —
    silently meaning something else. A deficit died deep inside
    instantiation with an unrelated substitution error.
  * **Aggregate, enum and payload shapes.** Returning a `?f` out of a
    `→ ?i`, a differently-signed closure out of a declared closure
    return, a number into an enum parameter, and a float payload into a
    declared integer payload — the last bitcast the bits into the slot,
    so the `??` arm read 4609434218613702656.
  * **Dead-store clash checks fired on a `?` join whose arms both
    return.** A store that can never execute was diagnosed as a type
    error, which broke the playground image build.

- **A binary operator one operand short swallowed the next statement and
  compiled.** `= n + n` followed by `( side )` took the call as its
  second operand; a `v`-returning call's value is `undef`, so nurlc
  emitted `add i64 %r2, undef` **with status 0**. The program linked,
  ran, computed garbage, and still performed the swallowed call as a side
  effect of an addition. `die_if_void` could not see it — it tests the
  operand's *value* against `void`, and a void call's value is `undef`.
  The rule now lives at the binary-operator site alone: an initialiser
  may legitimately take a `?` whose arms both return, which also yields
  `undef`.

- **`stdlib/ext/json.nu` emitted the `:` separator unconditionally.**
  Two lines read `? + k 1 < n {`, which in prefix form is the condition
  `k + 1` — always true — followed by a dead `< n { … }`. The IR shows
  it plainly: `icmp ne i64 %r4, 0` as the branch test, and
  `icmp slt i64 %r6, undef` computed and discarded. Written `? < + k 1 n
  {`. Found by the new probe, via the guard above: the object emitter had
  been taking the value branch whether or not a value followed.

- **Three pairs of diagnostics were word-for-word identical, so neither
  member said which construct it meant.** A closure's parameter list and
  a declaration's printed the same sentence; a repeated variant inside an
  or-pattern was reported as "a match arm already covers" it; and the
  unresolved-operand message for `&` and for `|` did not name the
  operator. Each now identifies itself — which a reader needs
  independently of any tooling, since the two members are reached by
  different mistakes.

- **Six element-store diagnostics never said what type the element
  was.** They named the value's type and then said "into this element",
  leaving the reader to find the container's declaration to learn what
  was wanted. All six had the expected type in scope at the point of the
  message. They print it now.

- **`# S { 1 }` was accepted silently for every single-field struct.**
  The guard that catches `'#' is the cast operator; struct/enum literals
  use '@'` tested whether the name is a struct by reading the key for
  field **index 1** — the *second* field. A struct with one field failed
  that test and the literal went through unremarked, while a two-field
  struct was caught all along, which is what kept the gap invisible. A
  single-field struct is the newtype wrapper, one of the commonest
  shapes there is.

- **A forgotten `→` on a guarded match arm was reported as a
  non-exhaustive match.** The guard scan ran to the next `→` at paren
  depth 0, and braces do not affect that depth — so `A v ? > v 0 { ^ v }
  B → 0` swallowed the arm's body *and the whole next variant*, and the
  failure surfaced as "no arm covers variant 'A'" about the arm the
  writer had just finished writing. A guard is one expression and never
  contains a brace at depth 0, so a `{` there is the missing arrow and
  nothing else.

- **Two enums were reported as a "wrong struct type".** The check that
  runs first has no symbol table to test enum-ness with, so it described
  every named-type mismatch as a struct one. Its parenthetical was
  already accurate; the lead was not, and *struct* is the word a reader
  takes away. Both kinds are nominal, which is the rule that matters and
  is true of either.

- **"likely a conditional with incompatible branch types" was a guess,
  and the wrong one.** Returning a call whose declared return type is
  `v` is the commonest way to reach that error and went unmentioned. It
  is named first now.

- **Assigning to a field of a by-value struct parameter emitted invalid
  IR, silently.** A by-value struct parameter has no alloca to GEP from,
  so `= . s a 5` printed `getelementptr %S, %S* , i32 0, i32 0` — with
  an **empty pointer operand** — and nurlc exited 0. Only clang objected,
  as "expected value token" against generated IR the author never wrote.
  Rejected at the source now, naming both cures: take the argument as
  `inout` if the caller should see the write, or copy it into a `: ~`
  local first.

- **"that type holds -128..255" is not true of `i8`.** The narrow-operand
  literal check accepts the signed range *union* the unsigned one,
  because it does not read the operand's signedness — so the window is a
  fact about eight bits, not about `i8`, which holds -128..127. Stating
  it as the type's range taught a rule the language does not have. The
  semantics are unchanged; only the claim is.

- **A supertrait ':' written on an impl silently deleted the impl.**
  `% Speaker : Dog { @ speak Dog self → i { ^ 1 } }` consumes `Dog` as a
  supertrait name, which leaves the lexer on `{` — so the declaration is
  read as a *re-declaration of the trait*, and the impl body vanishes.
  No `speak` was emitted at all, and the program still compiled and
  linked. The supertrait-on-impl message that exists for this can never
  fire for that shape, because by then it is not being read as an impl.

  The hole underneath was that structs, enums and impls each guard
  against a duplicate declaration and **traits did not** — so a second
  `% Name { … }` quietly replaced the first. Traits now carry the same
  position-keyed guard, which makes import replay idempotent and this
  shape an error that names both the duplicate and the impl spelling.

- **`->` where NURL's `→` belongs said "expected a type".** The ASCII
  pair does not lex as an arrow at all: `-` and `>` are two separate
  operators, so the parse died asking for a type and never mentioned the
  arrow. A model that cannot emit U+2192 had no way to learn that from
  the answer. The token table was telling the same lie from the other
  side — it rendered `TT_ARROW` as `'->'`, naming a spelling that cannot
  produce that token, so "found '->'" sent the reader looking for two
  characters their source does not contain. Both now say `'→'`, and the
  minus-then-greater-than pair gets a message of its own.

- **Ten diagnostics pointed somewhere the mistake could not be.** Nine
  printed a caret under a bare `}` — closure and fn-pointer call arity,
  dyn and impl method arity, the no-impl dispatch miss, three
  return-type mismatches and enum arithmetic — and one printed a caret
  two columns past the end of the line it echoed. All ten are the same
  cause the three fixed in the previous release had: the check runs
  after `gen_expr` has consumed the operands. Anchored with `die_stmt`,
  which now has 17 callers, up from 7.

- **A top-level sum type with no name got the generic message.**
  `: | { A B }` answered "expected '{' but found 'A'" and blamed the
  fixed-arity operand trap, which is not what happened: `gen_enum_decl`
  took the name on trust, registered whatever `{` renders as, and then
  failed at the brace it had already eaten. `parse_type_enum` had
  carried the right message all along, but it only sees `: |` in TYPE
  position — the top-level declaration is a different path and never
  consulted it. Both spellings now answer alike.

- **A binding's type was the one type position nothing validated.**
  `check_type_known` already guarded parameter, struct-field, return and
  FFI types — and not the place a type is written most often. So
  `: *Foo p …` against an undeclared `Foo` leaked `%Foo` into the IR,
  nurlc exited 0, and clang objected a stage later about generated code.
  Same helper, same wording as the parameter case, so the two now agree
  instead of disagreeing by omission.

- **`: n i 0` — the name first, then the type — said "use of undefined
  identifier 'i'".** That is how Go and Rust spell a binding, so it is a
  mistake worth expecting; the old answer named the token and then called
  it the wrong thing, sending the reader to look for a binding that was
  never the problem. A bare type keyword yields no value and so can never
  open a legitimate initialiser: in the inference branch it is this swap
  and nothing else, and the message now says which order NURL uses.

- **An `inout` field diagnostic ended mid-quote.** `struct 'S' has no
  field 'zz` — its `nurl_str_cat4` had no room left for the closing
  quote, so the message trailed off exactly where the field name ended.

- **Three messages taught an associated-type syntax the compiler
  rejects.** The binding is three tokens — `type Elem i` — as
  `docs/spec.md` §4.9, `docs/LIMITATIONS.md` and
  `__parse_assoc_binding`'s own comment all say. All three diagnostics
  about it said `type Name = ConcreteType`, and the one that fires on a
  malformed binding said it *while rejecting the very form it asked
  for*: write `type Elem = i` and the compiler answers "must be bound to
  a simple type name — write `type Name = i`". A model that did what the
  message said hit the same message again, with nothing in the text to
  break the loop.

  Found by probing the never-fired list, which is what it is for. The
  coverage gate then flagged all three rewrites as unread — a rewritten
  message has been read by nobody, which is why the ratchet keys on
  message identity and not on a count.

- **A select arm that lost its `[T]` was told about the default arm.**
  The default-arm branch tested only "is this an identifier", so
  `ints → oi { … }` was accepted *as* the `_` marker and the parse then
  failed one token later with "expected '{' to open the default arm's
  body" — a message about a construct the writer never used, offering a
  cure (`_ → { body }`) with no bearing on the mistake. The marker must
  literally be `_`; anything else is a channel arm missing its brackets,
  and the arm-shape message that was already written for exactly this
  now gets to say so.

- **Two mistakes every other language teaches now get an answer.** Both
  produced a message with no die site of its own — the compiler fell
  through to something generic — so both were invisible to the source
  scan and to the coverage gate alike, and only writing the wrong
  program found them:

  * `@ Point { x : 3 y : 4 }` (named struct-literal fields) died as
    **"use of undefined identifier 'x'"**, pointing at the field name as
    though it were a typo. It now states that literals are positional
    and shows the declaration beside the literal that builds it.
  * `@ E A 1` (the variant outside the braces, as in `E::A(1)`) died as
    **"expected '{' but found 'A'"**, blaming the fixed-arity operand
    trap — which is not what happened. It now names the variant and
    shows where it goes. The check fires only when the ident really is a
    declared variant, so a genuine stray token still gets the arity
    message it deserves.

- **"NURL has no defaults and no overloading" — said by the function
  named `__kw_default_or_die`.** NURL has had default parameter values
  since kwargs landed (`@ box s label i width = 10 → v`), and this error
  fires *precisely* when the skipped parameter has none. The message
  asserted the opposite as a language rule, so a model that read it
  learned to never use a feature the language has. It now names the
  parameter, states the real rule (optional iff the declaration gives it
  a default), and offers all three cures including adding one.

  The first thing the coverage gate found, and the second message of this
  shape after the bool-widening one in `ecc058c` — both shipped because
  nothing ever printed them.

- **Three diagnostics printed a correct message against the wrong line.**
  The bool-mix checks in `gen_logical_or` / `gen_logical_and` and the
  missing-argument check in `__kw_default_or_die` all fire only after
  `gen_expr` has consumed the operands, by which point the lexer sits on
  the NEXT statement — `die lex` blamed it. Anchored with `die_stmt`,
  which exists for exactly this and already had four callers. A model
  reading a precise message about the wrong line is worse off than with a
  vague message about the right one.

- **Five defects the macOS leg found, three of which were never about
  macOS.** Bringing the platform under CI turned up:

  * **`fcntl`, `open` and `ioctl` were declared fixed-arity** though all
    three are variadic in C. x86-64 SysV and Linux AAPCS64 pass variadic
    arguments in the same registers as fixed ones, so the wrong
    declaration is indistinguishable from the right one there; Apple's
    arm64 convention passes them on the *stack*. So
    `fcntl(fd, F_SETFD, FD_CLOEXEC)` set some other value, silently:
    `__set_cloexec` did nothing, the exec-errno pipe's write end survived
    `execvp`, and `process_spawn` waited forever for an EOF that could
    not come — while `__set_nonblock`, the same call, left sockets
    blocking so every async server stalled its worker thread instead of
    parking on the reactor. Ten corpus failures, one wrong arity. The
    `...` marker (already used by `ext/sqlite.nu` for exactly this
    reason) now says so.
  * **aarch64 and riscv64 hosts ran fibers on `ucontext`.** The backend
    gate named `NURL_CTX_X86_64` alone, so two ISAs whose context switch
    `runtime_ctx.c` has long provided — and whose AArch64 backend passes
    the unikernel gate in CI — fell through to the libc path. Harmless
    on glibc, fatal on Apple's deprecated arm64 `makecontext`. Both gates
    now ask one name, `NURL_CTX_AVAILABLE`, defined where the coverage is
    decided.
  * **`fs_glob` would not descend a symlinked directory.** `glob(3)`
    resolves links in intermediate components; the helpers were using the
    lstat-based classifier that `dir_remove_all` needs (so an `rm -rf`
    cannot follow a link out of its tree) and rejecting type 3. macOS
    made it total — `/tmp` is a symlink there — but it reproduces on
    Linux, which is what `fs_glob_symlink.nu` pins.
  * **The "is this clang new enough" gate read a version string.** Apple
    numbers its releases independently, so `Apple clang 15` passed a
    check meant to admit LLVM 15 and then failed inside LLVM's IR parser,
    naming our bootstrap snapshot for what is a toolchain problem. A
    capability probe decides now, and names Homebrew LLVM in the cure.
  * **`-Wl,--as-needed` reached Apple's ld64**, which errors on an
    unknown flag rather than ignoring it. `-dead_strip_dylibs` is the
    same intent, picked by `uname` in both `build.sh` and `nurl.sh` —
    both, because the driver carries its own link line.

  Supporting plumbing: `run_tests.sh` resolves `timeout`/`gtimeout`
  rather than assuming the former, and `build.sh` exports the compiler
  and link flags it resolves so `split_equivalence.sh` and the
  `tools/*/build.sh` scripts stop each working them out again — that
  drift is how a run reached for the system Apple clang in the middle of
  a Homebrew-LLVM build.

- **The scalar-agreement sweep: nine ways a wrong-typed value slid
  through a call, and the boundaries around it.** Found live via the
  playground: `( twice y )` with `y` a float against `@ twice i x`
  compiled clean and returned garbage — under opaque pointers a call
  carries its own function type, so `call i64 @twice(double …)` is
  textually valid IR, clang assembles it, and the callee reads a
  register the caller never wrote. Probing that class systematically
  found the same hole in nine coats:

  * **positional calls** — float↔integer in either direction, now
    rejected with the register-level consequence spelled out;
  * **FFI calls** — the width-coercion block handled ints and pointers
    but let `( labs y )` hand a double to C's `long` parameter;
  * **generic calls** — checked after tparam substitution
    (`( vec_push [i] v 1.5 )` dies). Root cause was two-layer: the
    call-site checks skip generic callees by design, *and* any
    `[T]`-generic's parameter roster was silently abandoned because `T`
    lexes as a boolean literal and `scan_skip_type` refused it at a
    type position;
  * **kwargs calls** — the `name:` reorder path bypassed *every*
    per-argument check and spliced default values verbatim (`u k = 5`
    put a raw `i64 5` in the call's argument list); it now runs the same
    battery, and stores lowered types so a `u`-typed argument no longer
    prints an internal spelling into the IR;
  * **closures** — a `(@ f f)` closure passed to a `(@ i i)` parameter
    invoked it with the declared signature and reinterpreted every
    argument; now compared whitespace-blind and rejected;
  * **`inout` arguments** — passed by address, so `( bump n )` with
    `: ~ i n` against `inout f x` had the callee storing a double's bits
    into the caller's integer; the binding's type must now match the
    declared parameter type exactly;
  * **`b` parameters** — a wider integer used to be emitted raw
    (mismatched signature); the fix surfaced that toml_basic.nu itself
    passed `0/1/2` into a `b kind` parameter and silently double-printed
    through two `? == kind N` arms. Narrowing int→`b` is now rejected
    (a parameter is a contract; the truncation keeps only the low bit),
    while `b` still widens losslessly into integer parameters — and an
    `i1` now always zero-extends (`T` is 1, never the -1 a sign-extend
    produced);
  * **float widths** — `f32` ↔ `f` now coerce at call boundaries via
    `fpext`/`fptrunc` (the binding law; previously a mismatched call
    signature), and a **return** must match the declared float width
    exactly, like integer widths (`^ x` of `f32` from `→ f` emitted
    `ret float` out of a `define double`);
  * **literals in operators** — `+ 10 flag` printed `add i64 10, %c`
    with `%c: i1` (invalid IR, clang-only error). A bool operand now
    widens (10 or 11, the C reading), an integer literal evaluates at
    the typed operand's width and must fit it (`+ 300 u8val` is
    rejected, not wrapped), an `f32` register widens against a float
    literal, and two registers of different float widths are rejected
    like their integer duals.

  The same law now guards the remaining aggregate boundaries:
  **slice-literal elements** (`[ i | 1 2.5 3 ]` used to emit
  `store i64 2.5` — invalid IR with a `.ll` line number and no source
  location; widths coerce, float↔int and pointer↔scalar die) and
  **struct-literal fields** (a pointer value into a scalar field died
  only in clang; the `@ P { 0 }` null idiom and handle-stash coercion
  stay legal).

  **Conditions grew a type.** `?` / `~` accept `b` or an integer
  (tested non-zero) — that part is unchanged — but a float, string,
  enum, or aggregate condition used to become `icmp ne double %r, 0` /
  `icmp ne i8* %r, 0`: invalid IR only clang reported. Each now dies at
  the source with the comparison to write instead (floats get the NaN
  caveat, strings get both readings — emptiness vs null-ness, enums get
  "which variant would be false?"). `# b` of a float — poison for any
  value but 0/1 — is rejected the same way.

  Every new diagnostic names the argument position, both types in NURL
  spelling, the exact runtime consequence being prevented, and the cure
  with the operator to type. All are pinned as `diag_*` goldens so the
  text itself is regression-checked (16 new), plus a behavioral test
  pinning the *legal* coercions (`call_scalar_width_coercions`).
  net_inet.nu (an `i` result into a `b` parameter) and toml_basic.nu
  were fixed where the new checks caught them red-handed, and
  toml_basic's golden no longer bakes in the double-print. The
  misleading `'( f inout v )'` call-syntax suggestion in three inout
  diagnostics — a form the language never accepted — now shows the real
  shape and where the `inout` marker actually lives.

## [0.36.0] — 2026-08-08

### Added

- **`break` and `continue` (grammar v2.4).** Every parsing loop in this
  tree was `: ~ b run T` plus `= run F` plus a condition that reads the
  flag — three lines for one, and three places to forget the reset.
  Both are **reserved identifiers**, classified by the lexer like `pub`,
  not symbols: every two-character prefix spelling collides with a
  program that already exists. `~>` in particular would have swallowed
  the 28 loops written `~ > cond { … }`, turning `~ > i idx {` into
  `continue i idx {`. Two identifier names is the cheaper price.

  Both terminate the block they appear in, exactly as `^` does, and both
  bind to the **innermost** `~` body. Using either outside a loop is a
  compile error naming the reason rather than a silent no-op.

  The subtlety is ownership. A jump leaves the block without running the
  code the normal path would, so the compiler emits the loop body's
  whole drop sequence at the jump before branching. Getting that wrong
  is invisible in a functional test: the first implementation leaked
  because the drop emitters *rewrite* the owned-value lists they walk —
  correct at a function's single exit, wrong at a branch, because the
  fall-through still runs on every other iteration and still needs its
  own drops. A `continue` taken once left 49 of 50 iterations' closure
  environments unfreed. The lists are now snapshotted and restored
  around the jump, and the ASan+LSan gates cover both jumps over a
  capturing closure.

- **`--strict-arity`, and a CI gate that runs it over the whole tree.**
  The n-ary `&`/`|` foot-gun is the language's one remaining
  source-level trap, and its outcome is the worst available: `? & a b c
  d { … } { … }` reads as `? (& a b) c d`, so the last two comparisons
  become the bare then/else values, both blocks run as ordinary
  statements, the conditional logic is wrong — and the compiler emits a
  working binary with `status: ok`, so nothing downstream can notice.
  `nurlc --strict-arity` makes it an error; the default stays a warning
  (now naming the flag) so existing trees keep building.
  `tools/check_strict_arity.sh` runs the strict compiler over every
  first-party `.nu` file and is wired into CI.

  The gate found the shape it was written for on its first run.
  `examples/audio_sparcles2.nu` had `? & >= x 0 < x W & >= y 0 < y H {}
  { = . plife i 0 }` for "kill particles that wander off-screen": the
  condition was only the x test, the y test was swallowed as the bare
  then-value, and the kill ran unconditionally — culling **every**
  particle on **every** frame. Fixed with the third `&` it always needed.

- **`--lint` reports a `Vec` or `String` nobody releases.** Those two
  are the handles the compiler deliberately does *not* auto-drop
  (docs/MEMORY.md §7.4), so forgetting one leaks with no diagnostic
  anywhere — and it is the mistake a language model makes most, because
  the type looks owned and the code looks finished.

  Ownership leaves a binding by the routes the compiler already models,
  and the report fires only when none of them was taken: a `*_free`
  destructor, a `sink` argument, an alias copy into an immutable
  binding, a `^`-return, a store into an aggregate literal, a store into
  a struct field, or an argument the callee embeds.

  Two of those the compiler could not previously see, so they are new
  summaries — deliberately **separate** from `g_fn_escapes` rather than
  folded into it. Escape means the value outlives the whole call chain,
  so a stack reference handed there must be rejected; embedding a value
  in an aggregate does not imply that (`wrap` puts a closure in a `Slot`
  the caller may consume in the referent's own scope, which
  `ret_escape_agg_ok` exists to keep legal). Conflating them turns that
  negative control red — which is how the distinction was found.

  Measured against stdlib + examples + the corpus while it was built:
  **645 → 126** warnings, stdlib **97 → 14**, each step a root cause
  rather than a suppression. What remains is dominated by forward
  references — a callee that frees its parameter, defined after its call
  site, so the sink summary is not yet known — a limitation the existing
  inference already documents for itself.

- **`nurl_docs` reads a section instead of a document.** Answering "who
  frees a String?" cost the whole 44 KB of MEMORY.md, and `spec.md`
  (63 KB) did not fit the per-call cap at all. Documents are already
  carved into headings, so: `query=` searches every section of every
  document — whole-word, ranked by coverage, headings outranking body
  prose — and returns the best few *with the keys to fetch them*;
  `outline=true` is one document's heading map (1.5 KB for MEMORY.md);
  `section='7.4'` or `section='manually-managed'` returns one section
  (3.4 KB). Search and retrieval deliberately use different boundaries:
  retrieval is hierarchical, so asking for §2 includes its §2.x
  children, while search treats each heading's own prose as the unit —
  otherwise a document's H1, having no same-level sibling, spans the
  entire file, outscores every real subsection, and hands back exactly
  the 44 KB the feature exists to avoid.

- **`nurl_build_native run=true` — compile and run in one call.** The
  hosted playground could build a native binary and hand back a download
  link, but the only way to see a program's OUTPUT was
  `nurl_build_unikernel`: boot it as its own kernel under QEMU and read
  the guest console. That works and stays the sandboxed path, but it is
  a heavyweight answer to "what does this print".

  `run=true` executes the program under the same `timeout(1)` wrapper
  every build tool uses and returns exit code, stdout and stderr.

  It ships **off**. Executing a freshly compiled binary is unsandboxed
  code execution against the container's filesystem, network and
  environment, and the hosted instance is an unauthenticated public
  compile farm. `NURL_ALLOW_RUN=1` is the operator saying otherwise —
  the same switch, and the same reasoning, as `nurl-mcp --allow-run`
  over HTTP. Asking for a run while it is off returns an error naming
  both the switch and the sandboxed alternative, rather than a build
  with no output, which a caller would read as "it printed nothing".

### Changed

- **Compiler diagnostics: every error now says what to write instead.**
  The compiler is the only teacher an agent has, so a message that names
  what it wanted without naming the cure costs a whole iteration. This
  release swept the 173 `die` sites; **170 now carry an explanation, up
  from 95**.

  Severity came first, and centrally: the four `die` emitters printed
  `file:line:col: message` with no `error:`, while the borrow checker's
  diagnostics carried one, so a single build printed two lines that
  looked like different kinds of output. All ~160 sites gained it at
  once.

  Then the messages. Parser errors name what was **found** as well as
  what was expected, and the correct form with an example — arms,
  bindings, declarations, closure bodies, field access, `select`,
  or-patterns, traits, `inout`. Type and borrow errors state the rule
  that transfers: *a heap handle has exactly one owner*; *NURL has no
  overloading and no file-scope shadowing*; *every parameter must be
  supplied*. The use-after-move error now names **what** consumed the
  value (`by string_free`, `by an alias copy`) rather than only the
  line.

  Two messages were not terse but wrong, and both were found by writing
  the mistake and reading the answer rather than by scanning the source:

    * `^ f 1` — a call with the parentheses left off — led with the
      closure reading and told the writer to wrap working code in a
      closure. The likely cure leads now.
    * returning a bool from an `→ i` function asserted *"NURL has no
      implicit conversions"*, which is false: a bool widens into an
      integer binding, deliberately. An agent that believed the sentence
      would have learned a rule the compiler does not enforce. It now
      states the real one.

  A 30-case probe suite over realistic mistakes backs the sweep, and it
  is what found the missing check listed under Fixed below — a program
  that compiled clean is the worst outcome of all, because no wording
  can teach what the compiler never says.

- **Windows is a per-PR merge gate — tier 1.** The `windows-tests`
  workflow ran on `main` pushes only, reasoning that PRs were already
  gated by the Linux+FreeBSD corpus and that "a main breakage surfaces
  here within one push". That rationale was falsified twice in one
  batch: `run_tests.ps1` is a separate implementation of *how do I run
  this test*, so two corpus additions carrying a compiler flag
  (`arity_strict_*` → `--strict-arity`, `lint_*` → `--lint`) passed
  every PR gate and turned `main` red on merge. Surfacing within one
  push is not the same as being caught, and each cost a second PR to
  undo.

  It now runs on PRs as well, with a `changes` classify job so a
  docs-only PR does not spend an hour of the slowest runner, and a
  concurrency group so a superseded run is cancelled.
  `docs/PLATFORMS.md` moves Windows from tier 2 to tier 1 on both
  tables, which is what the tier definition has always said: tier 1 is
  "every push and PR".

  `RELEASING.md` claimed no test corpus ran on Windows in CI at all.
  That stopped being true when the workflow landed and is now corrected.

### Fixed

- **The borrow checker did not know `vec_free_with` frees its Vec.** The
  destructor rule keyed on a `_free` SUFFIX, so `vec_free` consumed its
  argument and `vec_free_with` did not — even though it releases
  strictly more: the container, and every element through the dropper it
  is handed. That is how the stdlib frees every `Vec` of owned elements,
  so the blind spot sat on the most common shape. A Vec read after
  `vec_free_with` compiled clean, with no diagnostic, and ran on freed
  memory. It is now a `use of moved value` error like every other
  use-after-free, with a `borrow_vec_free_with` regression.

- **No ordering between an address and a number.** The pointer/scalar
  operand check exempted all comparisons, for a reason that is only
  about equality: `== ptr 0` is a null check and pointer-to-pointer
  compares in i64. Written as "comparisons", the exemption also covered
  `<` `>` `<=` `>=`, where a pointer against an integer means nothing —
  so `? > 1 \`s\`` compiled clean, linked, and produced a running binary
  that silently compared an i64 against an address.

  Found by the diagnostic probe suite, in the group that compiled with
  no diagnostic at all. A missing check is the worst AX outcome there
  is: no wording can teach what the compiler never says.

  Ordering comparisons are checked now; equality keeps the exemption
  exactly as before, pinned from the other side by `cmp_ptr_null_ok`.

- **`ext/json` string parsing now follows RFC 8259, and the module's own
  promise holds.** json.nu states "the serializer's output is guaranteed
  valid JSON". Two string paths falsified it. §7 forbids unescaped
  U+0000..U+001F inside a string; a raw one was accepted — by *two*
  routes, because the escape-free fast path memcpy'd its span without
  looking at it and only strings that also carried a backslash ever
  reached the decoder. Both are checked now, so a future optimisation
  that reintroduces a blind copy fails the test rather than the spec.
  §8.1 requires the text to be UTF-8, and a lone surrogate half has no
  UTF-8 encoding: `["\uD800"]` decoded through the 3-byte path to the
  bytes ED A0 80 (WTF-8) and `json_stringify` handed them straight back,
  so a round-trip produced output no conforming parser accepts. Lone
  halves now become U+FFFD, substituted at the single choke point every
  code point passes through, so no future caller can reopen the hole. A
  valid surrogate *pair* is untouched — 😀 still decodes to U+1F600.
  Found while fixing this: `json_basic` asserted that a raw newline
  inside a string parses, because a NURL backtick literal turns `\n`
  into a real 0x0A; the test was encoding the bug, and now uses the
  conforming spelling for the same value.

- **The arity warning points at the `?`, not at the `}` that revealed
  it.** `? & a b c d { … } { … }` — the n-ary foot-gun the language
  documents — can only be detected once the `{` after the conditional is
  reached, and the diagnostic reported the lexer's position at that
  moment. For a multi-line body the caret landed on the closing `} {}`,
  several lines below the mistake, pointing at the consequence. gen_cond
  already captured the `?`'s line for the borrow checker; it now keeps
  the column too and reports there, via a new `warn_pos` (the non-fatal
  twin of the existing `die_pos`, which exists for exactly this reason).

## [0.35.1] — 2026-08-07

### Added

- **MCP tool `nurl_docs` — the documentation tree an agent could not
  reach.** `nurl_api` answers "what is the signature"; it never answers
  "who frees this", "which cipher suites ship", or "does this target
  have threads". Those answers live in `docs/MEMORY.md`,
  `docs/CRYPTO.md` and `docs/PLATFORMS.md`, and until now exactly one of
  the fourteen documents had a tool (`nurl_read_gotchas`) — so a model
  driving NURL through MCP guessed at precisely the questions the
  project has already written down. `nurl_docs` with no argument lists
  the tree (path, size, title); with `name=` it returns one document.
  The name is matched forgivingly — `MEMORY`, `memory.md`,
  `docs/MEMORY.md` and `./memory.md` all reach the same file, and a bare
  basename reaches a nested one (`COMPILER_INTERNALS` →
  `dev/COMPILER_INTERNALS.md`) — because a model that has to guess the
  exact spelling will spend calls guessing it. Documents are capped at
  48 KB per call and the truncation line prints the exact `offset` to
  pass for the rest, so `spec.md` is reachable in two calls instead of
  being silently cut. A name that matches nothing answers with the index
  rather than a bare error, which turns a wrong guess into the right
  next call. Both servers expose it: the hosted playground
  (`NURL_DOCS_DIR`, default `/opt/nurl/docs`) and the local `nurl-mcp`
  package (`$NURL_DOCS`, else `$NURL_STDLIB/docs`) —
  `install-toolchain.{sh,bat}` now ship `docs/` into the prefix, so an
  installed toolchain carries its own documentation.

### Changed

- **`nurl_api` answers concept queries instead of shrugging at them.**
  The query search AND-matches its terms, which is right when a model
  names one thing two ways and wrong when it names a concept: nothing in
  the stdlib is one declaration that contains all of `string`, `builder`
  and `append`, and `vec_push new string_new` is three *different*
  functions. Both used to return zero and jump straight to examples and
  the package registry — past `string_push_str`, which was sitting right
  there. Now a zero-hit query is re-run as an OR over the same
  declaration blocks, with two rules that keep the result small. Terms
  match as WHOLE words (the adjacent byte must not be a letter, so
  `string` hits `string_push_str`, `string_new` and "a string", and
  misses `substring`), and each hit is ranked by how much of the query it
  covers — terms weighted by LENGTH, since `new` is three characters half
  the constructors contain while `vec_push` is eight that name one
  function, and a term in the declaration's own name outranks one in its
  prose. The top twelve come back labelled `[2/3 terms]`. Only if the OR
  pass finds nothing does the reply widen to examples and the registry as
  before, so the corpus fallback no longer buries a real answer. Shared
  engine (`stdlib/ext/mcp_search.nu`), so the playground and the local
  `nurl-mcp` gained it together.

## [0.35.0] — 2026-08-07

### Added

- **TLS works on RISC-V: entropy from a virtio-rng device**
  (`unikernel/boot/virtio_rng.c`). This architecture has no entropy
  INSTRUCTION — the `seed` CSR is the optional Zkr extension and
  QEMU's rv64 CPU does not implement it — so the answer comes from a
  device, at the same layer x86 answers with RDRAND and AArch64 with
  RNDR. With `-device virtio-rng-device` an RSA-2048 TLS 1.3 handshake
  against the guest completes (84 s under TCG — the interpreter's
  price, not the protocol's); without it the machine refuses BY NAME
  rather than inventing anything, because "your TLS handshake failed"
  is a much worse way to learn a device is missing.

  The driver is C in the boot layer and deliberately not the NURL
  virtqueue: `getrandom` must work with no NURL module linked, for a
  program that never touches the socket layer. One queue, one buffer,
  no negotiation beyond the version bit. It trusts the device for
  bytes and not for the count — one claiming to have written more than
  the buffer holds is refused. The gate checks both halves, because a
  fake source passes the obvious one: with the device a draw must be
  neither all zeroes nor equal to the next draw, and without it the
  refusal must name the device.

- **The AArch64 image now boots on Firecracker and cloud-hypervisor
  too** — as a flat `Image`, the container those two take on this
  architecture where x86 gives them the ELF's PVH note.
  `boot/boot_arm64.S` carries the format's 64-byte header at offset 0
  and `build_unikernel_arm64.sh` emits `prog.Image` beside `prog.elf`;
  `POST /build_unikernel` returns it as `image_artifact`. One program,
  two wrappers, no second build: `code0` is a branch over the header,
  so a loader jumping to offset 0 and an ELF loader jumping to the
  entry point arrive at the same instruction. `text_offset` is 2 MiB
  because the image is **not** position-independent — the field is
  what makes a loader place it where its absolute addresses already
  point — and `image_size` covers `.bss`. The hypervisor gate checks
  the header the way it checks the PVH note (magic, `code0` really a
  branch, `text_offset` equal to the link offset, `image_size` ≥ the
  file), with four mutations caught; QEMU boots the flat Image, which
  is what proves the branch and the load address agree. Booting the
  other two on this container needs an AArch64 **host** — neither
  emulates — and the gate says so instead of implying coverage.

- **A NURL program boots as its own kernel on RISC-V too** — the third
  architecture, and the one that proves the second was not a
  coincidence. QEMU's `virt` board with OpenSBI underneath, four files
  and a linker script (`boot_riscv64.S`, `platform_riscv64.c`,
  `tls_guest_riscv64.c`, `nolibc/setjmp_riscv64.S`, `link_riscv64.ld`)
  plus an RV64 fiber switch in `runtime_ctx.c`. Gate
  `unikernel/run_qemu_riscv64_tests.sh` is **15/15** — the same corpus
  programs against the same hosted goldens, the device demos, faults
  reported with exit 126, and an HTTP server in the guest answering
  curl on the host. CI builds and boots all three architectures on
  every commit.

  Three things this machine made explicit rather than let pass:
  **`fp` IS `s0`** on this ISA, so parking the device-tree pointer in
  `s0` and ending the frame-pointer chain three instructions later
  zeroed it — the guest reported "no device tree", which was a true
  statement about a register the boot code had just cleared, and an
  assembly probe of the firmware handover is what told the two apart.
  **The firmware talks**: OpenSBI prints on the same UART before the
  kernel runs, so the guest marks its own first byte and the run
  script drops everything before it — a rule that belongs to us rather
  than to whatever the banner looks like this year. And **there is no
  entropy source**: RISC-V's `seed` CSR is the optional Zkr extension
  and QEMU's rv64 CPU does not implement it, so this port panics on a
  request for randomness, naming what is missing, instead of inventing
  it.

- **A NURL program boots as its own kernel on AArch64 too** (unikernel
  plan phase U6). QEMU's `virt` board, and the port is the size the
  design predicted: **four files** differ — `boot/boot_arm64.S`
  (EL2→EL1, FP/SIMD, vector table, stacks, `.bss`),
  `boot/platform_arm64.c` (PL011, device tree, MMU, generic timer,
  RNDR, PSCI), `boot/tls_guest_arm64.c` (the thread pointer) and
  `nolibc/setjmp_aarch64.S`. Everything above that bottom edge is the
  same code the x86_64 image runs, which the gate proves rather than
  claims: `unikernel/run_qemu_arm64_tests.sh` is **15/15** — the same
  corpus programs against the same hosted goldens, the device demos,
  faults reported with exit 126, and an HTTP server in the guest
  answering curl on the host. A hello image is 131 784 bytes, within a
  kilobyte of the x86_64 one; the memory floor is 5 MiB. CI builds and
  boots it on every commit, with zig as the cross toolchain — the same
  zig the ecosystem installs.

  `stdlib/runtime_ctx.c` gained an AArch64 fiber switch (AAPCS64:
  x19–x28, x29/x30, d8–d15 and FPCR) beside the x86 one, so fibers,
  channels and the M:N runtime work there natively rather than falling
  back to ucontext.

  Three machine differences are absorbed in the port rather than
  pushed upward: `virt` announces its virtio-mmio devices in the DEVICE
  TREE, so `platform_arm64.c` parses the tree and synthesizes the same
  `virtio_mmio.device=` entries the x86 guest reads off its command
  line; `virt` defaults to LEGACY virtio-mmio exactly as microvm does
  (the guest read `version=1` and refused every device — correctly);
  and the clock states its own frequency in `CNTFRQ_EL0`, so the
  `tsc_khz=` handshake turns out to be an x86 quirk rather than part
  of the contract. The TLS image's offset from the thread pointer is
  MEASURED, not assumed: the boot code places the image, reads a
  canary `__thread` back through the compiler's own addressing, and
  refuses to run if the value is not there — a thread-local block off
  by sixteen bytes reads plausible garbage.

- **MCP tool `nurl_build_unikernel`** (plan phase U5). An agent builds
  a bootable image and — because the tool's `boot` defaults ON, and an
  agent cannot run qemu — gets the guest console and exit status back
  in the tool result: write program → build → read the boot log →
  iterate. `files` bakes a read-only filesystem, `args` is the guest
  argv, and the ELF comes back as a download link, never inline bytes.
  Listed in tools/list, /mcp-info and the server's instructions text.

- **The playground UI builds and boots unikernels** (plan phase U4).
  The target dropdown gains **Unikernel x86_64 · bootable image**: one
  Build click compiles the editor's program into a PVH image, boots it
  in the playground, and renders the guest console with its exit
  status, the image download, and both ready-to-paste QEMU commands. A
  guest-args field appears for the kernel command line's `args="…"`.
  The examples dropdown greys out what cannot boot — **measured, not
  listed**: `unikernel/measure_capability.sh` links every bundled
  example at image-build time exactly as a request would (42/64
  capable today) and GET /examples serves each verdict with the
  missing symbols as the reason, so the tooltip says *why* (signals,
  canvas/audio, hosted-HTTP FFI). A deployment that never measured
  skips the annotation instead of faking it.

- **`boot: true` — the playground proves the image boots** (plan phase
  U3). `POST /build_unikernel` can now boot the image it just built,
  inside the container: TCG (no /dev/kvm there), no network device,
  its own wall-clock bound via timeout(1) (`NURL_UNIKERNEL_BOOT_SECS`,
  default 20 s), concurrency bounded by the compile permit the request
  already holds. The reply's `boot_result` carries the guest console
  (CR-stripped, capped at 64 KB), the parsed `[nurl-exit]` status,
  `timed_out`, and qemu's own stderr — a failed boot is a diagnosis,
  not an empty log. A server program that would listen forever still
  proves it boots: the log holds what it printed, `exit` stays null.
  qemu-system-x86 adds ~72 MB to the image. e2e: the booted guest's
  print and exit 0 are asserted through the HTTP surface; a deployment
  without qemu answers `ran: false` with a reason instead of failing.

- **`POST /build_unikernel` — the playground builds bootable unikernel
  images** (plan phase U2). Body: `source` (+ `filename`), optional
  `args` (the guest's argv — returned inside the boot command, never
  executed server-side), optional `files` (`{relative/path: base64}`
  baked into the image as a read-only filesystem; keys are refused on
  a leading `/`, a backslash, or any empty/`.`/`..` segment, because
  the tar is built with `tar -C dir .`). The reply carries the ELF
  artifact + size and a `boot` object with ready-to-paste QEMU
  commands — the exact flags the guest gate boots 20/20 with, plus a
  networked variant — verified by pasting them verbatim: the built
  image boots and prints. Rate limiting, the compile semaphore, body
  caps and artifact GC all apply automatically (`/build*` prefix).
  End-to-end tests cover build, download, initfs bake, all four
  traversal shapes, and that a broken program answers with the
  compiler's own diagnosis.

- **The playground container can build unikernel images** (plan phase
  U1). The nurlapi Docker image ships `unikernel/` (477 kB), plain
  binutils, and a pre-warmed boot-object cache (205 kB), and its build
  now ends with a smoke check that compiles two images with the exact
  toolchain a request will use — a hello, and a listener that pulls
  the NURL socket layer through the `nm` seam. If either does not
  link, `docker build` fails: the playground can never ship an image
  whose unikernel toolchain is broken. Building an image inside the
  running container as the unprivileged server user takes ~1 s warm
  (132 KB hello ELF). The HTTP endpoint over this is the next phase.

### Changed

- **The device-tree walk is shared rather than copied**
  (`unikernel/boot/fdt.c`). AArch64 and RISC-V need the same three
  answers out of the same format, and the third port is the right
  moment to stop copying the second's. Generalising it found a real
  narrowness in the AArch64 original: it classified nodes at a
  hard-coded depth, and RISC-V's virt puts its devices under `/soc`
  where AArch64's puts them at the root — so the walker found nothing
  and the guest reported "no virtio-net device" about a machine that
  had one. Nodes are now classified by NAME at any depth, with
  address/size cells tracked per level because a bus node may state
  its own.

- **The image is not a QEMU image, and there is now a gate that says
  so** (plan phase U7). Firecracker and cloud-hypervisor both boot an
  x86_64 kernel by reading the same `XEN_ELFNOTE_PHYS32_ENTRY` note
  QEMU reads, so the artifact needs no repackaging for either.
  `unikernel/tests/hypervisor_gate.sh` checks the note structurally on
  any machine — present, owned by `Xen`, type 18, four-byte
  descriptor, and the address in it **equal to the ELF's entry point**,
  which are set by two different files and whose disagreement is a
  boot that works under one loader and not another — and then boots
  the image under cloud-hypervisor and Firecracker where `/dev/kvm`
  exists, skipping loudly where it does not (neither has an
  interpreter fallback). Three mutations (entry moved, note type
  changed, section renamed) are all caught. On AArch64 the gate gives
  the honest answer instead: PVH is x86-only, QEMU's virt board loads
  the ELF directly, and the other two want a PE-format `Image` there —
  a packaging step not taken rather than a property claimed.

- **The playground builds AArch64 unikernel images too.** `POST
  /build_unikernel` takes `arch` (`"x86_64"` default, `"aarch64"`),
  the MCP tool takes the same field, and the target dropdown gains
  **Unikernel AArch64 · bootable image (QEMU virt)**. Everything the
  x86_64 path already had follows the field: the smoke boot runs
  `qemu-system-aarch64 -M virt`, the returned boot commands name the
  right machine, and the AArch64 ones carry no `tsc_khz=` because that
  clock states its own frequency. An unknown arch is a 400, never a
  silent build for the default — an image that builds, downloads and
  does not boot is the worst possible answer. e2e covers both
  architectures end to end, including the guest console from each.

- **`unikernel/build_unikernel.sh` is a tool now, not a repo-rooted
  script** (unikernel-in-the-playground plan, phase U0). It takes
  `--out-dir`, compiles the program-independent objects once into a
  locked, stamped cache (`NURL_UNIKERNEL_CACHE`; warm rebuild of a
  hello image: 0.14 s), names every per-program artifact after the
  program so concurrent builds cannot clobber each other, and with
  both directories pointed elsewhere never writes the repository at
  all. `compile_nu.sh` defaults `NURL_STDLIB` to the repo it lives in
  — a package build from a foreign cwd used to die with "cannot open
  stdlib/core/string.nu", and die SILENTLY, because compile errors
  went to a file nothing printed; failures now carry the compiler's
  message on stderr (`NURL_COMPILE_QUIET=1` restores the silence for
  the corpus runner, which classifies by exit code). All four
  properties are pinned by a new unit gate
  (`unikernel/tests/build_tool_gate.sh`): foreign-cwd build,
  read-only repo, concurrent byte-identical ELFs, loud failure.

### Fixed

- **nolibc was missing `getchar`** and nothing noticed, because
  glibc's `<stdio.h>` defines it as a macro (`getc(stdin)`) — every
  x86 build resolved the call in the preprocessor and never reached
  the library. A libc whose completeness depends on which headers
  happen to be installed is not complete; the AArch64 port, whose
  headers declare it as a function, found it at the link line.
  `nolibc/math.c`'s `sqrt` likewise assumed `sqrtsd`; it now selects
  the architecture's instruction and refuses to compile (rather than
  answer differently) on one where neither is known.

## [0.34.0] — 2026-08-07

### Added

- **A NURL program boots as its own kernel** (unikernel Track B,
  PRs #780–#792). `unikernel/build_unikernel.sh prog.nu` produces a
  PVH ELF that QEMU's microvm machine boots directly — no host OS, no
  libc, no interpreter: the same `runtime_core.c`, the same nolibc,
  and exactly three files that talk to the machine (`boot/boot.S`,
  `boot/platform_x86.c`, `boot/tls_guest.c`). What the image contains,
  in the order it was earned: real guard pages under every coroutine
  stack and a clock that is *told* (`tsc_khz=`, `wallclock=` on the
  kernel command line) rather than guessed (#781); the virtio-mmio
  transport with the ring logic host-tested before it ever met a
  device (#782–#784); virtio-net and DHCP, so the guest asks the
  network who it is (#785–#787); a filesystem baked into the image as
  a tar and program arguments from the command line's `args="…"` key
  (#788); TLS 1.3 served from the guest — RSA certificate read from
  the image, RDRAND entropy, X.509 validity checked against the told
  wallclock (#790); and an MCP endpoint that IS the machine,
  answering initialize / tools/list / tools/call from a client on the
  host (#792). Measured, under TCG (an interpreter — the floor, not
  the ceiling): 354 KB plaintext image, 378 KB with TLS; hello
  answers on a 3 MiB guest, the HTTPS server on 4 MiB; cold VM to
  first HTTP answer 2.5–6.6 s. The `unikernel` CI job runs the boot
  gates on every commit (#789), and the guest gate stands at 20/20.

- **Threads and fibers with no operating system under them**
  (`unikernel/runtime_bare.c`, PR #774). One coroutine type carries
  both `thread_spawn` and `spawn` on a single vCPU, cooperatively.
  The property the design buys: deadlock is DECIDABLE — with no
  coroutine runnable, no timer armed and no device that could deliver
  unprompted, the runtime prints which wait can never be satisfied
  and exits, instead of hanging. nolibc also grew a libm whose
  coefficients are generated, not copied, with Payne–Hanek reduction
  — accurate on purpose, gated differentially against glibc.

- **The TCP/IP stack itself, in pure NURL, sans-IO** (phase A4,
  PRs #776–#779). `stdlib/net/` gains ethernet, ARP, IPv4, ICMP,
  TCP (connection table, retransmit, persist probes, TIME_WAIT), UDP
  as a mailbox that preserves datagram boundaries, and DHCP — none
  of it touches an fd, a clock or a device, which is what lets it be
  tested under a scripted clock and fuzzed frame-by-frame
  (`net_frame_fuzz`, 5 injected parser bugs caught). On top of it
  `unikernel/net/sockets.nu` implements the socket ABI
  (`nurl_tcp_*`, `nurl_reactor_*`) in NURL, so the ordinary corpus
  — async servers, websockets, HTTP — runs with **no libc and no
  kernel sockets: 452 tests pass** against their unmodified goldens.
  A socket wait parks on its fd (#778): a machine whose every waiter
  is parked is provably idle rather than merely quiet.

- **A connection flood is refused, not fatal** (PR #796). The socket
  layer takes an fd ceiling (`sock_max_fds`, default 1024,
  `sock_set_max_fds` to change, 0 = none), checked before accept
  dequeues so a refused connection is never half-adopted. Reported as
  an accept error, not EAGAIN — EAGAIN plus a still-readable listener
  is a reactor spin.

- **`unikernel/README.md`** (#794): what this machine promises, what
  it refuses (fork/exec, signals, a writable filesystem), and what it
  costs, with the measured numbers above pinned in one place.

### Fixed

- **A socket's timeout survives being read from a fiber** (PR #799).
  `std/net.nu`'s async paths parked on the reactor with a hard-coded
  "for ever", so `tcp_set_timeout` was silently discarded the moment
  a read happened inside a coroutine — invisible on hosted targets
  (threads are OS threads there), fatal on the bare runtime (a thread
  IS a coroutine there). The socket now keeps its deadline in the
  handle (`nurl_tcp_timeout_ms`, both runtimes) and the fiber paths
  honour it. Fixing it uncovered three more, each real on its own:
  the bare scheduler's idle sleep waited for the next *coroutine*
  timer regardless of the caller's own deadline; the bare reactor had
  no `timeout_ms == 0` POLL semantics (0 fell into "no deadline" and
  blocked — it had always been wrong, and passed only because the
  deadlock detector's −1 read as "not readable"); and the HTTP/2
  client's readiness probe counted that poll's honest "not ready" as
  READABLE (`>= 0` where the contract is `== 1`), sending its drain
  loop into a blocking frame read with no frame coming — this last
  one lived in the hosted stdlib too. End to end: the swarm-mcp
  unikernel appliance now forms its cluster, serves MCP over HTTPS,
  and completes a submitted compute task with the correct result.

- **`spawn` can no longer hand back a fiber that does not exist**
  (PR #795). When a fiber stack cannot be allocated, both runtimes
  abort with `cannot create a fiber — out of memory for its stack
  (N live)` instead of returning a phantom handle that made a
  200-fiber program quietly compute with 11. A fiber costs 68 KiB
  (64 KiB stack + 4 KiB guard); the figure is now in `docs/ASYNC.md`.

- **The guest stopped failing silently** (PR #794, the hardening
  pass — every item is a bug the previous gates could not see). No
  IDT meant every CPU exception was indistinguishable from a clean
  shutdown: 256 stubs now report vector/err/rip/rsp/rflags/cr2 and
  exit 126, with #DF and #PF on their own interrupt stack because the
  fault worth surviving is a stack that hit its guard page. The boot
  stack had no guard page and page 0 was mapped, so a null store
  quietly succeeded — both unmapped. `munmap` was a no-op over a bump
  pointer, so alloc/free cycles ran a 256 MiB guest out of memory at
  ~250 iterations — replaced with a real page allocator, fuzzed on
  the host against a model. virtio-net leaked a 2 KiB buffer per
  transmitted frame (5.2 MB per 200 requests) — the soak gate now
  proves the heap flat. And DHCP took `yiaddr`/mask off the wire
  unchecked, so a hostile or broken server could configure the guest
  off the network silently.

- **A machine can talk to itself, and a sleeping main does not stop
  it** (PR #797 — five bugs found by running the real swarm-mcp
  package as an image, three of them in the hosted runtime's own
  contract). `sleep_ms` in the main context was a nanosleep that
  froze every coroutine on the cooperative runtime — it now runs
  whatever is runnable while the clock catches up
  (`nurl_runtime_is_cooperative` is the twin seam). The stack's
  transmit path had no source-address parameter, so a guest with a
  NIC checksummed loopback replies against the wrong pseudo-header
  and dropped them without moving a counter. A guest with a device
  was declared deadlocked while every coroutine legitimately waited
  on the network — a device gets a poller coroutine, and
  loopback-only programs keep the deadlock proof. `access()` refused
  everything, so `file_exists` could not see the baked-in
  certificate. And the guest console was fully buffered, so a server
  that never exits never printed a byte.

- **nurlc: a pointer to one struct was accepted as a pointer to
  another** (in PR #794's run-up). Four argument-clash families
  existed; the hole was exactly two different named types with a
  pointer on at least one side — `( takes_alpha b )` with `b : *Beta`
  compiled clean and reinterpreted memory at run time. Now a
  compile-time mismatch, with zero false positives over all 1202
  `.nu` files in the tree.

- **NURL can read back the infinities it writes**. `nurl_fast_atof`
  — the parser the formatter's round-trip guarantee is stated
  against — stopped at digits and answered 0.0 for `inf`, `-inf` and
  `nan`, so a CSV float column holding an infinity came back as zero
  silently. The three conversions now round-trip, and the stdlib's
  own paths go through the one parser instead of through libc.

- **A NURL function may define a symbol an FFI declaration names**
  (PR #775): a definition supersedes the declare instead of
  colliding with it — the rule that lets `unikernel/net/sockets.nu`
  BE the socket ABI without `std/net.nu` changing a line.

- **A package's imports resolve from the package, not the repo**
  (PR #793): `compile_nu.sh` ran nurlc from the repository root, so
  the first real package handed to the unikernel build stopped at
  "cannot open deps/…" — true statement, wrong directory.

## [0.33.0] — 2026-08-05

### Added

- **`unikernel/nolibc` — NURL programs that link no libc at all**
  (unikernel plan A3). The freestanding libc subset the runtime calls:
  `mem*`/`str*`, an allocator, buffered stdio over six syscalls, exact
  `%f`/`%e`/`%g`, `setjmp`/`longjmp`, and the thread-pointer setup
  `__thread` needs. **394 corpus tests build and run with `-nostdlib`
  and glibc nowhere in the link line**, matching their ordinary
  goldens (394 once the libc surface NURL *programs* call — `atoll`,
  `strstr`, `strchr`, the mechanical syscall wrappers, real `readdir`
  and `stat` — was added on top of the 49 the runtime itself needs);
  85 more still call into `runtime_ffi` (sockets, threads, entropy) and
  `unikernel/run_nolibc_tests.sh` prints the missing symbols for each,
  so the remaining work is measured rather than guessed. A hello-world built this way is a 75 KB static binary that
  makes four syscalls in its whole life.

  Gated by three differentials, not by "it didn't crash":
  `mem*`/`str*` against glibc swept over every alignment and length
  (645 440 checks), `%f`/`%e`/`%g` against glibc at every precision
  0–20 over random and adversarial doubles (1.2 M conversions), and a
  400 000-op allocator fuzzer that keeps a pattern in every live block
  — ASan cannot supervise an allocator it has replaced, so the data is
  the oracle. Everything except `syscall_linux.c` and the two `.S`
  files is portable C the guest will run unchanged.

- **`tcp_listen` accepts port 0, and `tcp_local_addr` reads back what
  the kernel picked** (`stdlib/std/net.nu`, `stdlib/runtime_ffi.c`).
  Binding an ephemeral port is the POSIX contract and the only way to
  take a listening port without racing whoever else wants it.
  `nurl_udp_bind` had always accepted it and `nurl_udp_local_addr` had
  always existed to read the result back; the TCP half of the same
  runtime section had neither — `nurl_tcp_listen` rejected `port == 0`
  as invalid and reported `NetBind`, a bind failure that never
  happened. New `nurl_tcp_local_addr` / `tcp_local_addr` return an
  owned `"ip:port"` from `getsockname`, mirroring the UDP pair
  including the ownership rule (caller frees with `string_free`).

### Changed

- **Float formatting generates its digits instead of asking libc five
  times** (`stdlib/runtime_core.c` §2b, `stdlib/nurl_pow5_table.h`,
  `tools/gen_pow5_table.py`). `nurl_str_float` used to find the shortest
  round-tripping text by printing with `snprintf("%.*g")` and parsing it
  back with `strtod`, binary-searching the precision — five of those
  pairs per number. It now computes the shortest digits directly (Ryū,
  over generated 125-bit power-of-five tables): **28–55× faster**
  (4398 → 80 ns per value on full-precision doubles, 1853 → 67 ns on
  short "data" floats, measured on an idle box), and `snprintf`,
  `strtod` and `floor` leave `runtime_core`'s libc surface entirely
  (52 → 49 undefined symbols), which is what the freestanding/unikernel
  target needs from this file.

  The text is unchanged for every double except **46 of the 2098 powers
  of two**, where the old search could not find the shortest form and
  printed one digit too many (e.g. `7.1202363472230444e-307`, now
  `7.120236347223045e-307` — same double, one digit shorter). A power of
  two's rounding interval is asymmetric, so the shortest decimal inside
  it is not always the one a correctly-rounding `printf` produces at that
  precision, and a search that only ever sees `printf` output cannot
  reach it. Verified byte-for-byte against the old implementation over
  systematic (every power of two, both neighbours of each, denormal and
  overflow edges) and random doubles, with every output independently
  re-parsed to prove the round trip; `float_shortest` pins it.

- **The landing page's contributor strip is faces and names only.** It
  read `Built by` and hung a role line under each name — editorial text
  that had to be written by hand in `nurlweb/contributors.json` for
  everyone who shipped something, and that fell back to a raw commit
  count for everyone who was not listed yet. The strip is now headed
  `Contributors` and carries nothing but the avatar and the name, so a
  new contributor appears complete rather than tagged with a number.
- **The strip is ordered by commits, and asks for two of them.** The
  order used to be the order logins were written in
  `contributors.json`, with everyone else appended by commit count —
  an editorial ranking that had to be maintained by hand and that
  said nothing a reader could check. It is now most commits first,
  full stop, and new `min_commits` (default 2) keeps a single merged
  typo fix off the page; `limit` (6) still caps it. Both cuts are
  reported by name-count on stdout rather than applied silently, and
  GitHub's own contributor page remains the exhaustive list.
  `contributors.json` shrinks to a login → display-name map — listing
  someone there no longer places or moves them, it only spells their
  name for when they qualify. `limit` and `exclude` are unchanged.

### Fixed

- **`nurl_fast_atof` is correctly rounded — NURL could not read back the
  floats it wrote** (`stdlib/runtime_core.c` §2c). The parser behind
  `stdlib/ext/csv.nu`'s typed float columns accumulated digits in a
  double (`r = r*10 + d`, then `r += d * scale` with `scale *= 0.1`) and
  applied the exponent by binary powering of `10.0`. Measured against
  `strtod`: **33.5 % of ordinary six-to-nine-significant-digit values
  came back at least one ulp off**, every value below ~1e-308 parsed as
  **0** (the multiplier overflows to `inf` and `r / inf` is 0), and the
  largest finite double parsed as **`inf`**. A CSV of doubles written by
  NURL's own formatter did not survive its own round trip.

  Replaced with a correctly-rounded parser — same double `strtod`
  returns, ties to even — that is also **4.5–8.4× faster than `strtod`**
  and faster than the inexact loop it replaces (12 ns vs 26 ns per value
  on plain decimals, `strtod` 101 ns). Three paths ordered by the work the answer needs: exact
  double arithmetic where one IEEE operation settles it; one 128-bit
  product against the same power-of-five table the formatter uses, taken
  *only* when the rounding is provably identical for every value the
  product could stand for; and an exact big-integer comparison for the
  rest, which needs no division and is reached by 0 of 900 000 values on
  realistic data. Correctness rests on the fast path declining what it
  cannot prove — including every exact tie — not on it usually being
  right. Verified against `strtod` over 16 M formatter round trips, 8 M
  random digit strings, long (> 19-digit) inputs and **exact midpoints
  between adjacent doubles**, with and without `__int128`, under
  ASan/UBSan; `float_parse` pins it.

- **nurlc leaked while compiling a `select`.** `gen_select` builds the
  construct's real body as source and compiles it through a sub-lexer;
  `gen_stmt` returns that statement's IR value, which for a block is an
  owned string, and the call was left unbound — 6 bytes per `select`
  compiled. The self-compile leak gate could not see it: `nurlc.nu`
  contains no `select`, so `gen_select` never runs on its own input.
  `select_basic` — the only test in the corpus that compiles one — is
  now pinned in the CI leak gate, which leak-checks nurlc's compile as
  well as the program's run. (Its own producer closure, escaped through
  `thread_spawn`, is freed the way §7.4 says a consumer must.)
- **SIGINT could not stop a server's accept loop on FreeBSD or macOS.**
  The listener-shutdown bridge woke the accepting thread by calling
  `shutdown(2)` on the *listening* socket — a Linux extension. Linux
  wakes a blocked `accept`/`poll`; BSD returns `ENOTCONN` and leaves the
  thread parked, so the signal arrived, the flag was set, and the server
  slept on. The listener already carries the self-pipe that cross-thread
  `nurl_tcp_shutdown` uses, and both a plain store and `write(2)` are on
  SUSv4 §2.4.3's async-signal-safe list, so the signal path now uses the
  same mechanism (with the `shutdown(2)` call kept as the Linux fast
  path and as the fallback when `pipe()` failed at listen time).
- **Unix-domain sockets never worked on FreeBSD or macOS.**
  `std/unixsock.nu` built `struct sockaddr_un` with the Linux layout —
  a 2-byte `sun_family` at offset 0. BSD and macOS put a 1-byte
  `sun_len` there and `sun_family` at offset 1, so the Linux encoding
  landed `AF_UNIX` in `sun_len` and left `sun_family` as `AF_UNSPEC`:
  every `bind` and `connect` failed. The layout now comes from
  `posix_const` (`SOCKADDR_UN_FAMILY_OFF` / `_FAMILY_SIZE` /
  `_PATH_OFF` / `_PATH_MAX`), which the C side computes with `offsetof`
  and `sizeof` against the platform's own header rather than
  enumerating OS macros — a platform this list has never heard of gets
  the right answer without a change.
- **nurlc leaked while recording a return-site ownership transfer.**
  `__dret_skip_add` built its new skip list with
  `( nurl_sym_set … ? c w ( nurl_str_cat3 … ) )`, a value-level ternary
  joining an untracked ident (a parameter) with an owning call result.
  The join publishes "not owned" — `s` also spells an opaque handle, so
  the ident arm is deliberately never copied — and the `cat3` buffer
  leaked. Two statement arms instead. Invisible until the sanitized
  runner stopped sending nurlc's own stderr to `/dev/null`.
- **The compiler test corpus gated its own live surface out of CI.**
  Both runners consulted hand-kept lists of test *names* while the
  facts lived in the tests, and the lists had drifted: `net_basic`
  binds 127.0.0.1 and ran by default while `net_loopback` binds
  127.0.0.1 and was gated; `http_date`/`http_jwt` open no sockets yet
  were held back for having an `http_` prefix; and exactly one test in
  the corpus contacts a third party (`http_basic` → httpbin.org) while
  the env var named for it held back everything else. The cost was the
  whole live surface of the runtime — threads, channels, semaphores,
  select, signals, unix sockets, async TCP, the HTTP server, its TLS
  path, websockets, the package-install e2e — never running in CI.
  Tests now declare what they need on a `// requires:` line (`live`,
  `internet`, or the name of a tool that must be on `$PATH`); pure is
  the default, so a test that forgets to declare fails loudly instead
  of silently never running. Sixteen tests gained goldens they never
  had. The per-test second gate (`env_get NURL_NET_TESTS` inside each
  live section) is gone with it — per-test goldens are byte-exact, so
  a half-run test could never have matched one, making those "skipped"
  branches unreachable dead code.

  `run_tests.ps1` reads the same declarations, so Windows and POSIX
  now share one contract instead of three copies of a name list. One
  token differs there by capability, not policy: `fibers` is off,
  because NURL has no Win64 context-switch backend, so a test pairing
  a fiber-side server with a blocking client would wait forever for a
  peer that cannot exist (`async_tcp`, `async_http_server`). **The
  Windows goldens for the tests whose live sections now run need one
  regeneration pass** — `windows-tests.yml`'s `update_goldens`
  workflow_dispatch, the canonical way those goldens are produced.
  `compiler/tests/run_tests.bat` was deleted rather than carried: it
  compared against a monolithic `correct.txt` that is not in the repo,
  so its first run wrote its own baseline and declared success — a
  runner that could not fail — and nothing invoked it.
- **`net_basic` asserted the port-0 bug it should have caught**
  (`listen_port_0=NetBind`, with a comment explaining the rejection as
  intended) — a test written from the implementation, with a golden
  pinning the defect. It now asserts the bind succeeds and that
  `tcp_local_addr` reports a real, non-zero port.
- **Both test runners now use `timeout -k 5s`.** Plain `timeout` sends
  SIGTERM only, and a test spinning in a tight loop with no handler
  ignores it indefinitely — four such processes from an earlier
  mutation-testing run were found burning a core each 12.5 hours after
  the run that started them. Declaring a hang is not the same as
  ending it.
- **`signal_basic`'s live shutdown assertion is no longer racy.**
  `NetAccept` and `NetClosed` both mean "the listener went away
  cleanly" and which one surfaces depends on thread timing; the test
  collapses the pair instead of printing a racy name into a byte-exact
  golden. Its listener also binds port 0 now, so parallel runs cannot
  collide on a fixed port.

## [0.32.0] — 2026-08-03

The MCP release. The Model Context Protocol shipped revision
**2026-07-28**, which removes the `initialize` handshake and
protocol-level sessions in favor of a stateless core — a
backwards-incompatible change to the protocol every NURL MCP server and
client speaks. NURL now implements it **dual-era**: one endpoint serves
both the new stateless clients and every existing handshake-based one,
so nothing that works today stops working.

### Added

- **MCP 2026-07-28 (the stateless revision) — the stdlib MCP stack is
  now dual-era.** The new spec revision removes the
  `initialize`/`notifications/initialized` handshake and protocol-level
  sessions: a *modern* request carries its protocol version, client
  identity and capabilities in `params._meta`
  (`io.modelcontextprotocol/protocolVersion` & co), and servers MUST
  implement `server/discover`. NURL's stack now serves **both eras on
  the same endpoint**, per the spec's own dual-era compatibility
  matrix — nothing was removed, so every existing legacy client keeps
  working:

  * `mcp_registry.nu` — `server/discover` dispatch; requests declaring
    an unsupported `_meta` version get the spec-shaped
    `UnsupportedProtocolVersionError` (−32022 with `data.supported`);
    results for modern requests carry `_meta` serverInfo; `initialize`
    now echoes the client's requested handshake-era revision when
    supported (previously it always pinned the latest). The stdio serve
    loop was unified onto `mcp_registry_envelope` — which also fixed a
    latent double-free (`json_free` after the consuming
    `mcp_send_message`).
  * `mcp.nu` — `mcp_protocol_version` is now `2026-07-28`;
    `mcp_protocol_version_initialize` (2025-11-25) is what handshake
    responses advertise. New: `mcp_version_supported`,
    `mcp_supported_versions_json`, `mcp_request_protocol_version` /
    `mcp_request_is_modern`, `mcp_client_meta`, `mcp_discover_result`,
    `mcp_result_set_cacheable` / `mcp_result_set_server_info`,
    `mcp_response_error_data` / `mcp_unsupported_version_response`, and
    error-code constants −32020…−32022. Every result built via
    `mcp_response_result` now carries `resultType: "complete"`
    (required in 2026-07-28, additive for older clients), and
    `mcp_tools_list_result` fills the now-required CacheableResult
    fields (`ttlMs`, `cacheScope`) — as do the registry's list/read
    dispatchers.
  * `mcp_http.nu` — validates the 2026-07-28 header-routing headers
    (`Mcp-Method`, `Mcp-Name`) against the body when present
    (mismatch → `HeaderMismatchError` −32020; absent headers stay
    legal for legacy clients) and allows them through CORS.
  * `mcp_client.nu` — modern era client calls: `mcp_call_modern` /
    `mcp_tools_call_modern` (per-request `_meta` + routing headers),
    `mcp_discover`, and the dual-era probe `mcp_server_is_modern`.
    `mcp_stdio.nu` grew `mcp_stdio_discover` (the spec's stdio
    backward-compat probe). Both `initialize` wrappers now send the
    handshake-era revision instead of the latest one.
  * `examples/mcp_echo_server.nu` demonstrates the `server/discover`
    handler; new offline regression `compiler/tests/mcp_dual_era.nu`
    locks the dual-era wire shapes byte-for-byte.

### Changed

- **The playground's MCP endpoint is off its pinned revision.**
  `nurlapi`'s `/mcp` hard-coded `protocolVersion: "2025-03-26"` (chosen
  for FastMCP parity). It now negotiates: a client asking for
  `2025-03-26` still gets exactly that, newer handshake clients get
  theirs, and modern clients get `server/discover` plus per-request
  `_meta`. Its static `tools/list`, `resources/list`, `prompts/list`
  and `resources/read` results carry `cacheScope: "public"` with a
  1-hour `ttlMs`, so shared intermediaries can cache them.
- **`packages/nurl-mcp` 0.8.0** and **`packages/swarm-mcp` 0.22.0**
  adopt the dual-era layer in their hand-rolled dispatch loops
  (`server/discover`, the −32022 version gate, `_meta` serverInfo,
  handshake-revision echo).

### Fixed

- **swarm-mcp's MCP handshake reported a stale version.**
  `serverInfo.version` was a hand-written `0.20.0` while the package
  was at 0.21.1. The handshake, `server/discover`, and the `--version`
  banner now all read one `sm_version` source.
- **A latent double-free in the registry's stdio serve loop.** It
  called `json_free` on the response *after* `mcp_send_message`, which
  already consumes its argument. Unifying the loop onto
  `mcp_registry_envelope` removed the second free.

## [0.31.1] — 2026-08-03

A one-fix patch release: TLS servers did not work on FreeBSD at all, and
the reason was a socket flag, not the cryptography.

### Fixed

- **Every TLS server on FreeBSD failed its handshake, because `accept()`
  inherits `O_NONBLOCK` there and does not on Linux.** `nurl_tcp_listen`
  puts the listening socket in non-blocking mode — the accept-wakeup pipe
  needs it — and POSIX leaves it *unspecified* whether `accept()` hands
  that flag to the new socket. Linux does not; the BSDs do. So on FreeBSD
  every accepted connection came back non-blocking.

  `net.nu`'s `tcp_read_chunk` survived that (it loops on `EAGAIN`), which
  is why plain TCP servers worked and the bug stayed hidden. But
  `tls.nu`'s `__fill` deliberately issues **one raw blocking
  `nurl_tcp_read`** — its comment explains why — so it got `EAGAIN`
  instead of the ClientHello, and every pure-NURL TLS handshake died with
  `TlsRead` before a single byte was parsed. Nothing to do with the
  crypto: the same box passes every RFC and FIPS vector.

  `nurl_tcp_accept` now clears `O_NONBLOCK` on the accepted socket, so
  every platform behaves the way the net stack was written against. A
  caller that wants non-blocking still asks for it through
  `nurl_tcp_set_nonblock`.

  Found by installing the toolchain on an OPNsense box and watching
  `swarm-mcp`'s HTTPS control surface refuse every connection; reduced to
  a 30-line reproducer (`x509_selfsigned_p256` → `tcp_listen_tls` →
  `tcp_accept`). Not a regression — v0.30.0 fails identically.

  **This had no test.** `compiler/tests/http_server_tls*.nu` are gated
  behind `NURL_NET_TESTS=1` *and* use an openssl-generated RSA
  certificate, so the pure server's EC P-256 path — the one `x509_gen`
  produces and every NURL-native TLS server uses — was never exercised in
  CI on any platform.

## [0.31.0] — 2026-08-02

A cryptography release, plus the compiler change that made the rest of
the cycle bearable to iterate on. Every asymmetric primitive in the
stack was rewritten around the same three findings, in this order: the
representation was chosen for a machine that no longer exists, the hot
loop allocated its own temporaries, and the ladder paid for bits it
could have consumed in nibbles. A P-256 key generation went from 4.77 ms
to 0.62 ms and from 44124 allocations to 100; X25519 from 0.58 ms to
0.135 and from 6146 allocations to 26; Ed25519 signing from 735 µs to
360; AES-GCM from 0.3 MB/s to 113; SHA-256 from 112 MB/s to 222. A TLS
1.3 client handshake — which pays for a key share in *both* offered
groups before one application byte moves — spent 57.4 ms in pure
arithmetic when the cycle opened; the same client now completes a whole
handshake against a stock TLS 1.3 server, network round trips and
certificate verification included, in about **2 ms**.

None of it changes what any of these primitives computes — every step is
pinned to RFC or NIST vectors — and none of it weakens the constant-time
properties: the ladders keep fixed step counts, the window tables are
read in full and merged under arithmetic masks rather than indexed by a
secret, and `docs/CRYPTO.md` records the argument primitive by primitive.

On the compiler side, `nurlc --split=N` emits the module as N
independent ones so clang can lower them at once, taking the compiler's
own build from 12.0 s to 2.8 s, and the runtime now recycles small
string allocations.

### Added

- **`nurlc --split=N` — the module, emitted as N independent modules, so
  N clang processes lower it at once. 5.6× off the clang step.** After
  0.30.0's dead-function elimination, what a NURL build waits on is
  still clang, and it is *one* single-threaded LLVM `-O2` pipeline over
  *one* module: emitting the compiler's own 3.2 MB of IR takes 0.46 s,
  lowering it takes 11.3 s, and a machine with twelve idle cores
  finishes no sooner than one with two. No driver flag fixes that —
  `-flto` with `-plugin-opt=jobs=12` parallelises only the codegen tail
  and still measures 11.1 s; ThinLTO over a single module measures 7.9 s.
  The parallelism has to come from the *emitter*.

  `--split=N` writes the finished module as up to N of them.
  `--split-out=PREFIX` says where; `--split-min=BYTES` (default 131072)
  is the floor on a part's size. stdout still carries the whole module,
  so the `.ll` artifact and everything that reads it are unchanged and
  one `nurlc` run produces both. `nurl.sh` and `build.sh` lower the
  parts concurrently and link them with `-flto=thin`.

  | on twelve cores | one module, `-flto` | split, `-flto=thin` |
  |---|---:|---:|
  | `compiler/nurlc.nu` clang step | 11.3 s | **2.0 s** |
  | `compiler/nurlc.nu` end to end | 12.0 s | **2.8 s** |
  | `examples/claude_agent.nu` end to end | 5.7 s | **2.6 s** |
  | `examples/static_server.nu` end to end | 4.6 s | **2.7 s** |
  | bootstrap stage-1 link | 11.3 s | **2.0 s** |

  **It is not free, and the drivers are configured around that.** ThinLTO
  imports across a module boundary but not unconditionally, so a caller
  separated from a callee it wanted inlined stays separated: the
  split-built compiler retires **3.4% more instructions** than the
  single-module one (3.242e9 vs 3.135e9, `perf stat`, self-compile).
  A 5.6× cheaper build for 3.4% of the program's speed is worth it
  while you iterate and not worth it for what you ship, so `nurl.sh`
  splits *your* program — which you rebuild constantly — while
  `build.sh` splits only the throwaway stage-1 compiler and links the
  stage-2 one it installs as `build/nurlc` as a single module.
  `NURL_SPLIT=0` restores the old behaviour exactly; use it for a
  release build. `NURL_SPLIT=N` sets the ceiling, `NURL_SPLIT_MIN`
  moves the floor.

  N is a ceiling, not an instruction: `nurlc` splits only as far as it
  can keep every part above the floor, so a program under ~256 KB of IR
  is not split at all. That floor is not a build-time heuristic —
  cutting a small module up makes the program *slower*.
  `bench/sort_window.nu` (10 KB of IR) runs 20–42% slower split at any
  part count and `bench/hash_join.nu` (27 KB) 23% slower at twelve,
  while the compiler's 3.2 MB is unaffected at every count tried.
  For the same reason the parts are *contiguous* runs of the emission
  order rather than a balanced interleaving: emission order is
  call-graph order, and the better-balanced partition scatters every
  caller away from its callee.

  The partition is a text-level pass over the finished IR, on the same
  footing as the dead-function pass it runs on top of — it knows nothing
  about what emitted any given function, so monomorphs, closures, drop
  glue and dyn thunks need no special casing. A function body goes to
  one part and every part declares what it does not define; `private`
  globals follow the functions that name them (duplicating one is always
  sound — it is module-local by definition); module-level globals are
  defined in part 0 and declared `external` in the rest; `linkonce_odr`
  bodies are replicated rather than declared, since `declare
  linkonce_odr` is not legal IR. A reference that lands in the wrong
  part is an unparseable module or an undefined symbol at link time,
  never a silently wrong binary.

  Off for `--emit-ir`, `--emit-asm`, `-O0`, `NURL_SAN=1` and
  `--debug`/`--coverage`; `nurlc` refuses `--split` together with `--g`,
  because DWARF is a per-module metadata graph that a function's `!dbg`
  attachments point into. Windows (`nurl.bat`) links a single module and
  is unaffected. Documented in
  [`docs/BUILDING.md`](docs/BUILDING.md) → *Parallel lowering*.

- **`compiler/tests/split_equivalence.sh` — a hard gate that a program
  built from N parts is the same program.** Rebuilds a structurally
  varied corpus (dyn trait objects and vtables, generic monomorphs,
  closures, `% Drop` glue, struct and closure return types) both ways and
  compares stdout, exit status, and the module written to stdout; then
  builds `nurlc` itself from four parts and requires the IR it emits to
  be byte-identical to what the single-module compiler emits. Runs on
  every `./build.sh`. The 598-program compiler corpus and all 64
  examples were swept through the partition once by hand as well — every
  failure was a pre-existing one (`-lsqlite3`, `canvas.o`, a module with
  no `main`) reproduced identically by the unsplit build.

- **`bench/crypto_hotpath.nu` — AEAD record throughput, without a socket
  in the way.** One "op" is one 16384-byte record, the largest TLS 1.3
  allows and so the size the record layer actually works in; it reports
  ns/op, allocations/op and the MB/s those imply for both suites TLS 1.3
  defines. It is what found the cipher-preference bug below: the two
  suites are three orders of magnitude apart on a CPU NURL cannot reach
  the AES instructions of, and nothing was measuring that.

### Changed

- **Ed25519 signing is 2× faster — 735 → 360 µs — and makes 208
  allocations instead of 18568.** Two changes, both of them ones
  `std/p256_field` already had.

  *The addition stopped allocating.* One twisted-Edwards addition needs
  nine field temporaries, and `__ed_add` allocated and freed all nine on
  every call — 512 calls per scalar multiply, so about nine thousand
  allocations per multiply, a quarter of the run time spent in the
  allocator for a routine whose work is nine field multiplies. They come
  from an `EdScratch` built once per scalar multiply now. **735 → 501 µs.**

  *The ladder consumes the scalar a nibble at a time.* The bit-at-a-time
  ladder paid two complete additions per scalar bit. A fixed 4-bit window
  pays four doublings and one addition per nibble, reading `digit·Q` from
  a sixteen-entry table that costs fourteen additions to build: **334
  point additions instead of 512**, and **501 → 360 µs**.

  The digit is secret, so the table is never indexed by it —
  `__ed_tbl_get_d` reads all sixteen entries every window and merges each
  under an arithmetic equality mask. One difference from the P-256
  version worth noting: gf limbs here are **signed**, so the mask is a
  full 64-bit −1 rather than `0xffffffff`, which would clip a negative
  limb's sign extension. Digit 0 reads the identity, which the complete
  addition formula absorbs.

  | | before | after |
  |---|---:|---:|
  | `ed25519_sign_pure` | 735 µs | **360 µs** |
  | point additions per scalar multiply | 512 | **334** |
  | allocations per signature | 18568 | **208** |

  Verification benefits the same way — it runs two scalar multiplies.
  This is the signature `std/minisign` verifies packages with, and the
  one behind Ed25519 certificates in `std/x509` and EdDSA in `ext/jwt`.

  Constant time is unchanged: a fixed `2·len(scalar bytes)` windows
  regardless of the scalar, no branch on secret data, no secret-dependent
  address. RFC 8032 vectors pass.

- **SHA-256 is 2× faster (112 → 222 MB/s) and SHA-512 2.05×
  (170 → 349 MB/s), because the hash cores stopped going through
  bounds-checked Vec accessors.** One SHA-256 block made about 380 of
  them — 64 pushes to build the message schedule, 192 gets to expand it,
  128 more to read the round constants and the schedule back in the round
  loop — plus one allocation for the schedule itself, all for a
  compression function whose real work is 64 rounds of ALU. Every index
  is fixed-count and provably in range, so every check was overhead. It
  showed up as **12% of a TLS handshake** in `vec_push`/`vec_get` alone.

  The schedule now lives in a scratch owned by the hash (allocated once
  instead of once per block) and every limb — state, schedule, round
  constants, and the block's own bytes — is reached through a raw `*u32`
  / `*u64`. The round-constant tables are filled by index too: they are
  rebuilt on every `sha256_init`, and TLS's key schedule runs one of
  those per HMAC leg.

  | | before | after |
  |---|---:|---:|
  | SHA-256 | 112 MB/s | **222 MB/s** |
  | SHA-512 | 170 MB/s | **349 MB/s** |
  | HMAC-SHA-256, short input | 3.47 µs | **2.30 µs** |

  This is the same change `std/p256_field` and `std/x25519` got, applied
  to the hash every part of the stack leans on: the TLS 1.3 key schedule
  and transcript, HMAC and HKDF, package hashing, the CAS Merkle tree,
  JWT. Ed25519 signing is *unchanged* — SHA-512 is not where its time
  goes (18568 allocations per signature are).

- **X25519 is 4.3× faster — 0.58 → 0.135 ms, and 26 allocations instead
  of 6146 — because the 25519 field stopped being sixteen 16-bit limbs.**
  `std/x25519` carried TweetNaCl's `gf`: sixteen signed limbs of about
  16 bits each. That shape needs **16×16 = 256 products** per field
  multiply, and `_M` allocated a fresh 31-limb accumulator for every one
  of the 1280 multiplies a scalar multiply performs.

  A field element is now ten signed limbs at radix 2^25.5 — limb `i`
  weighing `2^ceil(25.5·i)`, alternately 26 and 25 bits — which is the
  classic 32-bit curve25519 layout. Ten limbs need **100 products**, and
  a 26×26 → 52-bit product still leaves room to accumulate ten of them
  times the folding factors inside a signed 64-bit limb. The multiply is
  register-resident: it reads its operands into locals, computes the ten
  output limbs and carries, allocating nothing.

  The two coefficient shapes are folded into the *operands* rather than
  the terms, so each of the hundred products is a single multiply: a
  product of two odd-indexed limbs lands one bit low (because
  `ceil(25.5j) + ceil(25.5k) = ceil(25.5(j+k)) + 1` when both are odd) and
  is taken against a pre-doubled operand; a product that runs past limb 9
  wraps by `2^255 ≡ 19` and is taken against a pre-nineteened one.

  | | before | after |
  |---|---:|---:|
  | products per field multiply | 256 | **100** |
  | `x25519_base` | 0.58 ms | **0.135 ms** |
  | allocations per scalar multiply | 6146 | **26** |
  | TLS 1.3 client handshake | ~4.2 ms | **~3.0 ms** |

  **Ed25519 rides along** — `std/ed25519` builds on the same field, and
  its constants are already decoded through `_unpack25519`, so they
  re-encode themselves.

  Constant time is unchanged: the ladder keeps its fixed iteration count
  and its branchless conditional swap, and the new field has no branch on
  data anywhere. Verified against RFC 7748 §5.2 and §6.1 and RFC 8032,
  and the whole representation — multiply, carry chain, byte decode and
  byte encode — was checked as a model first, including a full ladder
  simulation that reproduces the RFC vectors and pins the worst-case
  intermediate at 2^57 against a 2^63 ceiling.

- **The P-256 ladder consumes the scalar a nibble at a time: 334 point
  additions instead of 512, a keygen 0.93 → 0.62 ms.** The bit-at-a-time
  always-add ladder paid two complete additions per scalar bit — one to
  double, one to add the base whether or not the bit was set. A fixed
  4-bit window pays four doublings and *one* addition per nibble, reading
  `digit·B` out of a sixteen-entry table that costs fourteen additions to
  build.

  The digit is four bits of the secret scalar, so the table is never
  indexed by it: `__p256_tbl_get_d` reads **all sixteen entries every
  time** and merges each under a mask that is all-ones exactly when
  `d == digit`. The mask is arithmetic rather than a comparison —
  `d ^ digit` is zero only on a match, and subtracting one from zero
  borrows into the top bit, which nothing else can set for a 4-bit value.
  The table walk costs about 4% of one point addition per window.

  Digit 0 reads the identity, which the RCB **complete** addition formula
  absorbs correctly — that is what lets the zero digit stay on the same
  path as every other one.

  Constant time is unchanged, on the same terms as before: a fixed
  `2·len(scalar bytes)` windows regardless of the scalar's value, no
  branch on secret data, and now no secret-dependent address either.

  `compiler/tests/p256_ct_field.nu` cross-checked its 60 random scalar
  multiplies against `p256_ecdh_keygen` — which calls the very ladder
  under test, so the check was vacuous. It now compares against
  `std/ecdsa_p256`'s BigInt Jacobian ladder, which shares no code with it
  (different coordinates, different field, different addition formula);
  a mutation of the base point makes it fail, as it should. The four
  reference functions it needs are renamed from `__` to a single
  underscore, which is what the compiler's own deprecation says to do.

- **The P-256 Montgomery reduction performs no multiplies at all — a
  keygen is 1.07 → 0.93 ms.** The reduction half of CIOS multiplies `m`
  by the modulus limb by limb, and P-256's modulus is
  `[2^32−1, 2^32−1, 2^32−1, 0, 0, 0, 1, 2^32−1]` in the radix the field
  now uses. Every one of those partial products is a shift, a zero, or
  `m` itself. `-p^-1 mod 2^32` is 1 as well, so `m` is simply `t[0]`,
  which makes the first step's low word cancel by construction and the
  next two limbs fall through unchanged.

  A Montgomery multiply is 64 machine multiplies instead of 128, and
  `__p256_mul_d` compiles to 8 `imul` per outer iteration instead of 16.
  This is what "Montgomery-friendly prime" buys and it was being paid
  for without being spent.

- **A P-256 key generation takes 1.07 ms instead of 4.77 ms, and makes 98
  allocations instead of 44 124 — a TLS 1.3 handshake is 8.5 → 4.9 ms.**
  Two changes to `std/p256_field`, the constant-time field behind every
  ECDHE key share and every ECDSA signing nonce.

  *The limb radix went from 2^16 to 2^32.* The field was transcribed with
  16-bit limbs so that a product would fit an `i64`, which meant a
  Montgomery multiply ran 16×16 = 256 schoolbook steps and another 256
  reduction steps. NURL has a real `u64`, and a 32×32 → 64 product is one
  machine multiply, so the same operation is now 8×8 = 64 and 64. The CIOS
  bound is exactly why 2^32 is the largest radix that works without a
  double-word carry: `t[j] + a[j]·b[i] + C ≤ (2^32−1) + (2^32−1)² +
  (2^32−1) = 2^64 − 1`, which a `u64` holds precisely.

  *The ladder stopped allocating.* Every field operation used to allocate
  its result, and `vec_with_cap` is two allocations (control block +
  buffer), so ~3000 field operations per keygen cost ~44 000 of them —
  25% of the run time once the multiply got cheap. Each operation now has
  a `_d` form that writes into a destination the caller owns, the six
  registers RCB point addition works in live in the per-scalar-multiply
  scratch, and the always-add ladder runs its 512 point additions in
  registers allocated before it starts. The allocating `p256ct_*` API is
  unchanged — it is those workers plus one `__mag8`.

  | | before | after |
  |---|---:|---:|
  | `p256_ecdh_keygen` | 4.77 ms | **1.07 ms** |
  | allocations / keygen | 44 124 | **98** |
  | TLS 1.3 client handshake | 8.47 ms | **4.87 ms** |

  Constant time is untouched: the loops keep their fixed trip counts, stay
  branch-free in the data, and the field is still never normalized. The
  `_d` workers may be called with `dst` aliasing a source — safe by
  construction, because each reads all of its operands into the scratch
  accumulator before writing `dst` (`__p256_inv_d`, the one exception,
  documents it). Verified by `compiler/tests/p256_ct_field.nu` (400 random
  field trials against the bigint reference plus 60 scalar multiplies),
  the ECDH known-answer vectors, the RFC 6979 signing vectors, and the
  full suite under ASan + UBSan.

- **`./build.sh` takes 23.6 s instead of 36.3 s — 35% off every build —
  because the bootstrap no longer optimises the two compilers it throws
  away.** Stages 0 and 1 are scaffolding: neither binary is shipped,
  neither is benchmarked, and each one does exactly one job — compile
  `nurlc.nu` once — before the build deletes it. Both were nonetheless
  linked at `-O2 -flto`, and stage 0 is the one link `--split` cannot
  help (it links the committed `nurlc_lastgood.ll` snapshot, which is a
  single file by definition), so it was ~13 s of single-threaded ThinLTO
  spent to make a 0.8 s job take 0.35 s.

  They are built `-O0` now. Stage 2 — the one copied to `build/nurlc` —
  keeps `-O2`, and its link flags are untouched.

  | step | before | after |
  |---|---:|---:|
  | stage 0 link | 12.89 s | **0.75 s** |
  | stage 1 link | 1.93 s | **0.30 s** |
  | stage 1 ir | 0.38 s | 0.88 s |
  | stage 2 ir | 0.35 s | 0.78 s |
  | stage 2 link | 12.54 s | 12.49 s |
  | **`--no-tests`, end to end** | **36.3 s** | **23.6 s** |

  Twelve cores, clang 18. The scaffolding gets ~2× slower at the one
  thing it does, and the build still comes out a third shorter.

  **Nothing about the shipped compiler changes.** The IR a stage emits is
  byte-identical at either optimisation level, which is the only property
  the bootstrap depends on — and the fixed-point check (stage 1 ≡ stage 2,
  byte for byte) proves it on every single build rather than taking it on
  trust. `build/nurlc` verified to emit the same 3,330,125 bytes of IR,
  hash for hash, at the same 0.34 s self-compile as before.

  `--san` builds stay `-O2` throughout: LTO is already off there, so the
  link is not the expensive part, and the instrumented self-compile is
  the stage that runs closest to CI's memory and time ceilings. `build.bat`
  gets the same treatment for the two throwaway stages (untested on
  Windows beyond the flag swap — the structure is identical).

- **AES-GCM is bitsliced: 0.3 MB/s → 113 MB/s, a 334× record layer.**
  `std/aes_gcm.nu` computed the AES S-box algebraically, per byte, as
  `Affine(x²⁵⁴)` — constant-time, which is the whole point (a table
  indexed by key bytes leaks the key through the cache), but about a
  thousand operations for one substitution. Ten rounds of sixteen of
  those put AES-128-GCM at **0.3 MB/s** against ChaCha20-Poly1305's 370,
  and AES-GCM is the one cipher suite RFC 8446 requires every TLS 1.3
  implementation to have. A peer that insisted on it made an 8 MB
  download take half a minute.

  Constant time was never the thing to give up, so the block cipher is
  **bitsliced** instead (a port of BearSSL's `aes_ct64`, Thomas Pornin,
  MIT). The state is transposed so each of eight 64-bit words holds one
  bit position of 64 bytes, and `SubBytes` becomes Boyar and Peralta's
  113-gate boolean circuit evaluated on those words: one pass
  substitutes 64 bytes, so the S-box costs under two operations per byte
  instead of a thousand — with no table and no data-dependent branch,
  the same guarantee as before. Four blocks travel together, which is
  what CTR mode wants anyway.

  GHASH was the other half: multiplying in GF(2¹²⁸) bit by bit is 128
  iterations of a 16-byte shift-and-mask per block. It is now carry-less
  multiplication built out of ordinary 64-bit integer multiplies
  (`ghash_ctmul64`) — each operand split into four interleaved bit
  groups so no carry crosses a kept bit, recombined by Karatsuba. After
  the rewrite the two halves cost about the same (perf: 45% cipher, 47%
  GHASH), which is where a balanced implementation should land.

  | 16 KB record | before | after |
  |---|---:|---:|
  | `aes128_gcm_seal` | 48 312 827 ns | **144 591 ns** |
  | | 0.3 MB/s | **113.3 MB/s** |
  | `aes128_gcm_open` | 48 296 068 ns | **144 861 ns** |
  | | 0.3 MB/s | **113.1 MB/s** |
  | allocations / record | 30 835 | **15** |

  The public surface is unchanged (`aes128_gcm_encrypt` / `_decrypt`,
  `aes256_gcm_encrypt` / `_decrypt`), and so is the ciphertext: a
  differential sweep over every plaintext length 0–200 × every AAD
  length 0–40 × both key sizes, plus a 16 KB record, matches the
  previous implementation byte for byte in all 33 166 cases, clean under
  ASan/UBSan/LSan. `compiler/tests/aes_gcm_vectors.nu` additionally
  gained the empty, single-block, AAD-only and 300-byte cases — lengths
  chosen to walk every path through the four-block loop — checked
  against OpenSSL rather than against the code they test.

  Two caveats, both documented in `docs/CRYPTO.md`: the key schedule
  still uses the old per-byte S-box (it runs once per key, ~2.5% of a
  record, and is not worth bitslicing), and GHASH's constant-timeness
  now rests on the CPU's integer multiplier being data-independent —
  true of every mainstream 64-bit core, not true of some small in-order
  ARM cores. TLS keeps preferring ChaCha20-Poly1305, which is still 3×
  faster; the comments in `tls.nu` / `tls_server.nu` explaining that
  preference by a 700× gap have been corrected to the 3× one.

- **A P-256 scalar multiply allocates 44 000 times instead of 164 000 —
  22% off the handshake's instruction count.** With the accessor calls
  gone (below), what was left in front of the arithmetic was the
  allocator: `vec_with_cap` is *two* allocations — a 24-byte control
  block and the data buffer — so a Montgomery multiply that built the
  modulus, the CIOS accumulator, the difference and its result made
  eight of them, and one complete point addition performs about thirty
  field operations.

  The modulus and the two temporaries now live in a `P256Scratch` built
  once per scalar multiply and threaded down through the point layer,
  so only each operation's *result* is allocated. The public field API
  (`p256ct_mul` / `_add` / `_sub` / `_inv` / `_to_mont` / `_from_mont`)
  is unchanged — each is a wrapper that makes a scratch, calls the
  scratch-taking sibling and frees it. A scratch is never shared between
  scalar multiplies, so there is no state to race over, and no
  arithmetic changed: the same limbs are written in the same order.

  | `p256_ecdh_keygen` | before | after |
  |---|---:|---:|
  | allocations | 163 986 | **44 124** |
  | time | 6.2 ms | **4.7 ms** |
  | handshake, instructions retired | 437.4 M | **341.0 M** |

  (Instructions rather than wall clock for the handshake: the loopback
  harness has a Python peer in the loop and cannot resolve 20% — the
  count is reproducible to four significant figures, the wall clock is
  not.)

- **A TLS handshake costs 10.5 ms of arithmetic instead of 57.4 —
  5.5×.** The ClientHello carries a key share for *both* groups, so every
  connection runs an X25519 and a P-256 keygen — and then a third scalar
  multiply for the shared secret — before a single application byte
  moves. Short-lived connections (a package fetch, an API call, one
  HTTPS request) are dominated by that. Both curves were built out of
  bounds-checked `Vec` accessors: 61% of the whole handshake was
  `vec_get` / `vec_set` / `vec_push` calls, not arithmetic.

  `std/p256_field.nu` and `std/x25519.nu` now index their limbs through a
  raw `*i` in the hot routines — the Montgomery multiply, the conditional
  subtract, add/sub/merge/clone on the P-256 side; `_M`, `_A`, `_Z`,
  `__car25519`, `_sel25519` and the gf copies on the X25519 side. Every
  one of those loops is fixed-count over a 16- or 31-limb magnitude, so
  the bounds check was provably redundant, and **constant time is
  unaffected**: the trip counts stay fixed and the data still takes no
  branch. Two smaller ones came with it — the modulus is passed into
  `__p256_cond_sub_p` instead of being rebuilt there (it was being
  reconstructed on each of the ~3000 field operations a scalar multiply
  performs), and the fixed-size magnitudes are filled by index rather
  than through a per-limb `vec_push` capacity check.

  | | before | after |
  |---|---:|---:|
  | TLS handshake (loopback, OpenSSL peer) | 57.4 ms | **10.5 ms** |
  | `x25519_base` | 3.1 ms | **0.59 ms** |
  | `p256_ecdh_keygen` | 15.7 ms | **6.4 ms** |

- **ChaCha20 keeps its state in `u32` instead of masked `i64` limbs —
  another 26% on the AEAD.** The kernel held the sixteen state words as
  `i` and put `& 4294967295` after every add and every rotate, and wrote
  each rotate as `shl | shr | and` because a 64-bit value cannot say
  `rol` on 32 bits. NURL has a native 32-bit integer that wraps, so the
  masks are gone and all thirty-two rotations in a double-round are now
  single `rol` instructions. Only the widening at the block's edges
  needed adding.

  | 16 KB records | before | after |
  |---|---:|---:|
  | `aead_encrypt` | 302 MB/s | **375 MB/s** |
  | `aead_decrypt` | 305 MB/s | **377 MB/s** |
  | `tls_write` over loopback | 261 MB/s | **307 MB/s** |

  `bench/crypto_hotpath.nu` grew the two key-exchange rows, so the
  handshake side is measured too and not just the byte-throughput side.

- **A pure-NURL TLS server no longer picks the cipher suite it is 500×
  slower at — 24.9 s → 0.15 s for an 8 MB response.** `tls_server.nu`
  walked the ClientHello and took the *client's* first acceptable suite.
  Chrome, Firefox and Go's `crypto/tls` all list `TLS_AES_128_GCM_SHA256`
  ahead of ChaCha20 when the CPU has AES instructions, so those clients
  got AES-GCM — and NURL has no AES-NI path. `std/aes_gcm.nu` derives
  every S-box byte through a constant-time GF(2^8) inversion instead of
  a cache-timing-visible table, which is the right call for security and
  costs about four thousand cycles a byte. Measured on 16 KB records
  (`bench/crypto_hotpath.nu`): **AES-128-GCM 0.5 MB/s, ChaCha20-Poly1305
  306 MB/s.** The server now prefers ChaCha20-Poly1305 whenever the
  client offers it at all. Downloading 8 MB from a NURL HTTPS server
  with `openssl s_client -ciphersuites
  'TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256'` went from
  **24.87 s to 0.151 s**. Clients that offer *only* AES-128-GCM still
  negotiate it and still work — RFC 8446 makes that suite mandatory, so
  it cannot simply be dropped; a software-only stack preferring ChaCha
  is what OpenSSL itself does on a CPU without AES instructions.

- **The ChaCha20-Poly1305 record path stopped copying every record
  through a bounds-checked byte loop — TLS reads 150 → 214 MB/s.**
  `aead_decrypt` extracted the ciphertext from the `ciphertext‖tag`
  buffer with one `vec_get` and one `vec_push` *per byte* before either
  the MAC or the keystream would look at it: a quarter of the whole
  receive path, and the same shape a comment three functions up records
  having already fixed once. Both consumers now take a range —
  `chacha20_xor_range` is the new entry point, `__mac_data` takes an
  offset and length — so nothing is copied out of the record at all.

  Two more in the same file. `chacha20_block` was a second, accessor-based
  copy of the round function, ~960 bounds-checked `Vec` calls a block,
  and the AEAD ran one per record for the Poly1305 one-time key; it is
  now the register-resident kernel applied to a zero plaintext, and the
  duplicate quarter-round helpers are gone. And the kernel XORs a whole
  64-byte block through eight 8-byte loads and stores when both buffers
  are 8-byte aligned — a `Vec`'s storage is malloc'd, so they are —
  instead of sixty-four of each with their shifts and masks. The byte
  path stays as the fallback for unaligned offsets and big-endian
  machines, which the file now probes for rather than assumes, and a new
  vector pins the two paths to the same output.

  | 16 KB records | before | after |
  |---|---:|---:|
  | `aead_encrypt` | 282 MB/s, 15 allocs/op | **313 MB/s, 12 allocs/op** |
  | `aead_decrypt` | 198 MB/s, 17 allocs/op | **306 MB/s, 12 allocs/op** |
  | `tls_read` over loopback | 150 MB/s | **214 MB/s** |
  | `tls_write` over loopback | 218 MB/s | **259 MB/s** |

- **Every string a NURL program allocates comes off the runtime's
  recycling allocator — 27% off `nurlc`'s own run time.** 0.30.0 put a
  per-thread size-class freelist behind `nurl_alloc`/`nurl_free`, and
  `String` and `Vec` buffers have used it ever since. The string
  *primitives* never did: `nurl_str_cat`, `nurl_str_slice`,
  `nurl_str_int`, and every `strdup` in the symbol table took their
  block straight from libc, while the compiler-inserted auto-drop handed
  that same block back through `nurl_free`. The loop was open at one
  end. Nothing was ever taken *out* of the cache, so the classes filled
  to their 1 MB budget once and from then on every free paid a
  usable-size query only to hand the block to libc anyway — the cache
  was pure overhead on the program that allocates hardest, and turning
  it off with `NURL_ALLOC_CACHE=0` made a self-compile *faster*.

  Closing the loop is one rule applied everywhere: allocate what
  `nurl_free` will free with `nurl_alloc`. The primitives in
  `compiler/nurlc.nu` and `stdlib/core/{string,symtab}.nu` call
  `nurl_alloc`; copies go through a new `nurl_strdup` (same block, same
  lifetime, an ordinary libc chunk — so a site that frees one with plain
  `free()` still works); and the code generator emits `@nurl_strdup`
  rather than `@strdup` for the copies it mints — an owned string
  reassigned, a match arm's result, an owned struct field — so a user
  program's copies recycle too.

  | `nurlc compiler/nurlc.nu` | before | after |
  |---|---:|---:|
  | wall clock | 469.9 ms | **346.2 ms** |
  | retired instructions | 3.137e9 | **2.101e9** |
  | libc `malloc` calls | 6 006 395 | **96 199** |
  | peak RSS | 25.9 MB | **18.0 MB** |

  98.4% of the compiler's allocations no longer reach libc at all, and
  the ones that do stop fragmenting an arena that was being handed six
  million short-lived blocks — which is where a third of the peak RSS
  went. `NURL_ALLOC_CACHE=0` still turns the cache off, and with it the
  self-compile goes back to 0.43 s: the whole gap is the cache, now that
  something finally takes blocks out of it.

  It is worth what it is worth and no more: this moves programs whose
  time is string-primitive churn, and not others. A loop of
  `nurl_str_int` + two concatenations + a slice, 300 k iterations, runs
  **2.07× faster** (49.6 ms → 24.0 ms). `bench/json_parse`, whose `Vec`
  and `String` buffers were already on the cache, measures unchanged, as
  does `nurlfmt` — neither is allocator-bound. `nurlc` is the outlier
  because it is a program that does almost nothing but build small
  strings.

- **`nurl_str_int` formats its digits by hand.** The runtime's hottest
  formatter — `nurlc` names every SSA register through it — spent its
  time in `snprintf("%lld")`: a format-string parse, a locale check and
  an internal output buffer, to produce at most twenty digits. glibc's
  printf machinery measured 3% of a self-compile on its own. The
  replacement writes digits backwards into a stack buffer and takes the
  one allocation it needs from `nurl_alloc`. The magnitude is
  accumulated in an `unsigned long long`, so `LLONG_MIN` — whose
  absolute value has no signed representation — formats like any other
  value; the output is byte-identical to `snprintf` across the full
  `i64` edge set and 400 000 consecutive values.

- **Every clang invocation is quiet about the target triple.** `nurlc`
  emits no `target triple`, so clang announced that it was supplying the
  host one on every single build. There was never anything to act on,
  and under `--split` it was printed once per part.

## [0.30.0] — 2026-07-31

A compiler-efficiency release. Everything in it is about what `nurlc`
spends — memory, syscalls, and the work it hands to clang — and nothing
in it changes what a NURL program means. The self-compile went from
leaking 2.8 million allocations to leaking none and from 115.9 MB peak
RSS to 18.5; the borrow checker's state representation was rewritten and
took 20.7% of the compiler's instructions with it; printing stopped
paying a write syscall per fragment; and `nurlc` now emits only the
functions a program can actually reach, which is 30–40% off the clang
step for anything that imports a stdlib module. Four new CI gates keep
each of those from decaying back.

### Added

- **Self-compile leak gate — `nurlc compiler/nurlc.nu` must leak nothing,
  and CI now enforces it.** The ownership campaign took the self-compile
  from 2,793,226 leaked allocations / 33.4 MB to zero (peak RSS
  115.9 → 18.5 MB), and nothing was watching while those leaks accumulated
  one unowned helper at a time — they decay back the same way. `tools/leakgate.sh`
  runs the self-compile under ASan+LSan with `detect_leaks=1` and fails on
  ANY report: no budget to raise, unlike the peak-RSS gate, because the
  number a leak gate accepts is zero. ASan/UBSan findings in the same run
  fail it too, and it refuses to run against an uninstrumented build rather
  than passing while checking nothing. It is a step in the existing
  `sanitizers` job (already a required check), so it reuses that job's
  `./build.sh --san` and costs ~3 s; it runs when `compiler/nurlc.nu` — the
  source that owns the allocations in question — or the gate script itself
  changed. Verified in both directions: green on the current compiler, and
  it fails as designed on a pre-campaign build (2.8M allocations reported).

### Changed

- **`nurlc` emits only the functions `main` can reach — 30–40% off the
  clang step on any stdlib-heavy program.** An import brings in a whole
  module: a program that imports `stdlib/ext/json.nu` for `json_parse`
  also got `json_clone`, `json_eq`, the pretty-printer and the float
  formatter. clang then ran its entire `-O2` pipeline over all of it and
  LTO deleted the unreachable half at link time — after the optimising
  was already paid for. On `examples/static_server.nu` that was 947 of
  1,416 emitted functions, 60,000 of 94,244 IR lines, and 2.7 s of a
  6.5 s clang step.

  | | before | after |
  |---|---:|---:|
  | `examples/static_server.nu` | 7.19 s | **4.32 s** |
  | `examples/ws_echo.nu` | 6.70 s | **4.04 s** |
  | `examples/h2c_server.nu` | 6.64 s | **4.41 s** |
  | `examples/wordcount.nu` | 291 ms | **178 ms** |
  | `bench/json_parse.nu` | 815 ms | **611 ms** |
  | test corpus wall clock (`./build.sh`) | 1 m 11 s | **42 s** |

  (`nurlc` + `clang -O2 -flto`, best of three. The self-compile is
  unchanged at −0.6%: a compiler uses nearly all of itself.)

  The pass is a linker-style collection over the **finished IR text**,
  not a source-level call graph — closures, generic monomorphisations,
  drop glue, `% Drop` impls and dyn method thunks are all just `@name`
  references by then, so it needs to know nothing about how any of them
  got there, and a future construct that emits a function is covered the
  day it is written. Roots are `main` plus every function named at
  module scope, which is where a `@__vt.<Trait>.<T>` vtable constant
  names its thunks. A file with **no `main`** is a module compiled for
  something else to link against and is left whole; `--no-dce` disables
  the pass outright.

  Two properties make it safe on by default: the output is a
  *sub-sequence* of the unfiltered IR — nothing is rewritten, reordered
  or renamed, only dropped — and dropping something still referenced is
  an undefined symbol at link time, never a silently wrong binary. The
  final binaries are byte-for-byte as capable as before; LTO was already
  removing the same code, just later.

  `tools/dcegate.sh` (new, wired into CI) pins the half the corpus
  cannot see. 567 passing tests prove nothing *live* is dropped — that
  would fail to link — but a pass that decided everything was reachable
  would also stay green while costing nothing but wall clock, which is
  exactly what an off-by-one in the block scanner did during
  development: a `define` following a closing brace with no blank line
  went unseen, its body counted as module scope, and static_server went
  from 947 droppable functions to 0 with every test still passing. The
  gate asserts unreachable code is gone, that the four indirect
  reachability routes survive, and that both builds behave identically;
  it is verified to fail against a compiler without the pass.

  Enabling this needed the output-buffer stack in `runtime_core.c` to
  become offset-based: a frame now records where its bytes start instead
  of snapshotting and restoring the whole enclosing buffer, so nesting
  one frame per function inside a module-sized outer frame is free
  rather than quadratic. The buffer also grows on demand now — it was a
  fixed 8 MB that `nurl_print` silently dropped writes past, which would
  have truncated a large module into invalid IR with no diagnostic.
  Self-compile peak RSS 18 → 24 MB (budget 600 MB).

- **`nurl_print` stops paying a `write(2)` per print — 16.7× faster
  output, 19–25% off every `nurlc` run.** The runtime flushed stdout
  after *every* print call. NURL code prints in small pieces (nurlc
  emits one IR line as ~8 separate prints), so the flush, not the
  formatting, was the cost: compiling `examples/static_server.nu` issued
  **188,713** write syscalls, and a program printing 300k lines spent
  16× longer in the kernel than in its own loop. stdout is now
  block-buffered when it is a pipe or a file and still flushed per print
  on a terminal — the same split C and Python make, so an interactive
  prompt with no trailing newline still appears before its read
  (verified against a pty).

  | | before | after |
  |---|---:|---:|
  | `nurlc examples/static_server.nu` — write syscalls | 188,713 | **725** |
  | `nurlc compiler/nurlc.nu` (self-compile IR) | 601 ms | **449 ms** |
  | `nurlc examples/static_server.nu` | 693 ms | **556 ms** |
  | `nurlc examples/ws_echo.nu` | 637 ms | **517 ms** |
  | 300k-line print loop | 435 ms | **26 ms** |

  Buffered bytes are never lost or reordered: `exit` flushes, every
  `abort()` path (`nurl__oom`, `nurl_panic`, the wasi panic stub)
  flushes stdout first, `stdlib/std/process.nu` flushes before its two
  `fork`s so the child cannot re-emit the parent's pending bytes, and
  **`nurl_eprint`/`nurl_eprintln` drain stdout before writing** — so
  anything merging the streams (a terminal, `2>&1`, a CI log) sees them
  in the order the program produced them. That last rule is stricter
  than before: `compiler/tests/outputs/mcp_hardening.txt` recorded a
  stderr line jumping *ahead* of a `puts` printed earlier, and the
  golden now shows true program order. The one case the runtime cannot
  see — a raw `write(2)` on fd 1, which bypasses stdio — needs an
  explicit `( flush )`, exactly as mixing `printf` and `write(1, …)`
  does in C; `stdlib/core/io.nu` documents both that and the
  follow-my-redirected-log case, and `compiler/tests/stdout_flush_order.nu`
  pins all three ordering rules.

- **MCP build tools answer with links/paths, never an inline base64
  module.** A compiled module returned as base64 in a tool result lands
  verbatim in the calling model's context — hundreds of KB spent on bytes
  the model can't read. The playground MCP tool `nurl_build_wasm` now
  returns `wasm_artifact` + `ll_artifact` download URLs (backed by a new
  `links_only:true` field on `POST /build_wasm`; the default REST response
  keeps the inline `wasm_base64` the playground consumes, and now carries
  the artifact objects too — `ll_artifact` even when the link step failed,
  which is exactly when the IR is wanted). The local `nurl-mcp` server
  (0.7.4) does the file-system equivalent: inline-source `nurl_build_wasm`
  keeps the module and its `.ll` on disk and returns `wasm_path` /
  `ll_path`, and `nurl_build_project` returns `binary_path` / `ll_path`
  instead of `binary_base64`.

- **Web docs build on fumadocs 16.14.**

### Performance

- **The borrow checker's per-binding state is a direct-indexed lattice
  array — 20.7% off the whole compiler's instruction count.** The state
  was a space-separated `name=digit` token string: every lookup
  `memmem`'d the whole thing (11.2% of a self-compile sat inside libc
  `memmem`), every update rebuilt the string token by token, and a join
  probed each token of one side against the whole of the other —
  O(na·nb). Binding names are now interned once per function into dense
  ids at `bck_explode` time (generation-stamped entries on `g_bck`, so
  there is no clearing pass; `rv_<id>` keeps the reverse map for
  diagnostics), and a state is a byte string indexed by id: get is a
  byte load, set a memcpy plus one store, join and the loop-carry seed
  pointwise passes.

  Self-compile, pinned, `perf stat -r 5`: instructions 3.318 G → 2.631 G
  (−20.7%), cycles −13.2%, wall 0.528 → 0.459 s, peak RSS 125 → 115 MB.
  The borrow checker's own overhead — the delta against `--no-borrowck`
  — drops 44%. Gated by a differential sweep over all 1,654 `.nu` files
  in the tree: IR, diagnostics and exit codes byte-identical.

### Fixed

- **The compiler stopped leaking: 2,793,226 allocations / 33.4 MB per
  self-compile → zero, peak RSS 115.9 → 18.5 MB.** A single-owner
  language whose own compiler leaks a third of its address space is
  making an argument it does not believe, and every step of this
  campaign found leaks that had sat unnoticed for months because nothing
  was looking. About thirty commits, each closing a *class* rather than
  a site — the recurring roots were worth naming:

  - **Ownership hidden behind a cast.** The strdup-returning getters
    (`nurl_sym_get`/`get2`, `nurl_lex_val`/`filename`/`peek_val`,
    `nurl_llty`, …) returned `^ # s ( strdup … )`, and the cast hid the
    freshness from return-site inference, so no caller ever freed the
    copy. `nurl_sym_get` alone leaked 1.77 M strdups per self-compile.
  - **Ownership as a per-path guess.** Return inference is now
    all-paths-or-nothing: any `i8*` return site that cannot prove
    freshness sets a poison that vetoes the marker. One owned
    `^ ( slice … )` beside a borrowed `^ param` tail used to mark the
    whole function owned — and callers then freed the borrow.
  - **The def-order gap.** A helper defined *below* its caller had no
    ownership summary yet at the call site, so its result went
    uncollected. Fixed both by hoisting and by a forward-call ownership
    channel that lets a call ask a not-yet-compiled callee, at run time,
    whether the pointer it returned was fresh.
  - **Copies nobody consumes.** A `?`/`??` arm whose value merely
    aliases a binding was copied like any other tracked value, while the
    binding's own scope-exit drop already owned that buffer — so every
    `? c { = x y } {}` minted a buffer with no consumer. The single
    biggest remaining class.
  - **Mixed joins.** A join with a borrowed parameter on one side and a
    tracked local on the other never collected the tracked arm's copy:
    71 k leaks on one `ws_echo` compile, through `subst_source` alone.

  Two of these were live-memory bugs, not just leaks: reassigning a
  tracked mutable string could `free` a `.rodata` literal or a borrow,
  and an over-eager owned marker made callers free a value they did not
  own. `arm_local_trailing_drop` and `ret_owned_propagation` pin the
  copy contract as regressions.

  The self-compile is the workload `nurlc.nu` exercises, and it has no
  `$` imports and instantiates no generics — so the whole
  mangling/substitution path was untested by it. Compiling an
  import-heavy program was taken the same way: 96 k → 7.6 k → **zero**
  leaked allocations, at `-O0` as well as `-O2` (an `-O0` ASan build
  elides no allocations and was the honest measurement). `tools/leakgate.sh`
  above is what keeps all of it at zero.

## [0.29.0] — 2026-07-30

A discoverability release, cut from one field report about seams a
newcomer hits in the first hour: the grammar's own import examples
didn't compile, the print function every language model reaches for
didn't exist, and the API-search tool couldn't see the runtime surface
the compiler itself provides. All four changes close the gap between
what the toolchain documents and what it accepts.

### Added

- **The runtime-builtin surface is discoverable** (`stdlib/core/builtins.nu`).
  Field report: `nurl_api query='float string convert'` returned zero stdlib
  hits even though `nurl_str_float` exists — it is a C-runtime builtin the
  compiler pre-registers, not a stdlib declaration, so no indexed surface
  mentioned it. The whole pre-registered surface (114 functions: printing,
  stdin, conversions, byte scanning, files, process/args/env, output capture,
  allocators, raw HTTP/subprocess/TCP-TLS handles, panic/recover, the libc
  pass-throughs) now lives in a documented module that nurldoc renders,
  `nurl_api` indexes, and `nurl_grep` / `nurl_read_stdlib` see. Hand-written
  prose, machine-checked list: `tools/check_builtins_doc.sh` gates it against
  the compiler preamble in CI, both directions.

- **FFI-redeclaring a runtime builtin is now harmless.** `& `c` @
  nurl_str_float f x → s` used to make LLVM reject the whole module with
  "invalid redefinition of function", because the compiler re-emitted a
  `declare` its own preamble already carried. The preamble now marks each
  symbol it declares with the same dedup key user FFI declarations use, so
  the duplicate is skipped — which is also what lets `core/builtins.nu` be
  imported at all.

- **Extensionless import paths.** The grammar's own import examples write
  `$ `stdlib/core/string`` — extensionless — while the compiler required
  `.nu` and rejected the documented spelling with a bare
  `nurlc: cannot open`. The resolver now retries every lookup tier
  (importer-relative, cwd, `$NURL_STDLIB`) with `.nu` appended, but only
  after the path as written missed all of them, so all existing imports —
  including a file that really has no extension — resolve exactly as
  before. Both spellings dedup to the same file.

- **`nurl_println`** — `nurl_print` plus a trailing newline, callable
  everywhere without an import, next to the long-standing `nurl_print` /
  `nurl_eprintln`. Language models writing NURL routinely assume it
  exists; now it does. Routed through `nurl_print` so output capture
  (`nurl_print_buf_*`) sees it too.

## [0.28.0] — 2026-07-29

A field-report release. Everything here was found by running the thing —
a Windows user on a machine shaped unlike any CI runner, a browser pulling
a 100 MB point cloud through the pure-NURL TLS stack, a port whose
bool-returning wrapper compiled to IR the verifier rejected three stages
later — and each fix lands with the regression that would have caught it.

### Added

- **`ply view --host/--addr` and `--tls`** (ply 0.2.x, registry): the viewer
  can bind 0.0.0.0 or one adapter and serve HTTPS under a fresh self-signed
  P-256 certificate (std/x509_gen) — listed here because the enabling
  stdlib work ships with this toolchain.

- **`nbody` — the benchmark suite's first row over floating point.**
  Every other row is an integer or byte kernel, so
  nothing in the suite touched `f` codegen, and nothing exercised the FPU's
  long-latency, non-pipelined sqrt and divide units: 500k symplectic-Euler
  steps of the Sun and four gas giants put ten sqrt/divide pairs on the
  critical path per step. It is also the one row where JavaScript is not
  handicapped. The u64 rows force that port onto `BigInt` because JS has no
  integer type, and Node loses them by 30–50×; here JS's single numeric type
  *is* the IEEE-754 double the benchmark is written in, so Node runs the
  same arithmetic as the compiled backends and lands near 2× C. A table in
  which one language loses every row by two orders of magnitude invites the
  suspicion that the corpus was picked to make it lose — this is the row
  that answers it.

  The checksum is the final energy's **bit pattern**, not a rounded
  decimal, so the gate asserts bit-exactness across all five languages
  rather than approximate agreement. That is achievable because `+`, `-`,
  `*`, `/` and `sqrt` are all correctly rounded by IEEE-754, and it costs
  three constraints, documented in `bench/nbody.c`: no `-ffast-math`, no
  multiply-add contraction (moot at the suite's baseline `x86-64` target,
  which has no FMA — but a future `-march=` flag would need
  `-ffp-contract=off` here), and the same operation order in all five
  ports. The five also share one data layout, struct-of-arrays: an
  array-of-structs C port is ~6% faster (274.0M retired instructions
  against 290.1M), but mixing layouts would have had the row reporting a
  6% spread that has nothing to do with floating point. Pinned to one
  layout the three compiled backends land within 3.5% of each other on
  instruction count. Native suite only for now — `wasmbench.sh` reads the
  same manifest but is not run in CI.

### Changed

- **nurlc rejects integer-width mismatches at return position.** `^ ( ffi )`
  in a `→ b` function lowered `ret i64 …` out of an `i1` LLVM function (and
  `^ == a b` from `→ i`, the mirror image, `ret i1` out of an i64 one):
  invalid IR that nurlc accepted with rc 0 and only the LLVM verifier
  rejected, three build stages later, with a line number into the `.ll`.
  The return-type agreement check now dies on integer width like it
  already did on float↔int and pointer↔scalar, with the cure per
  direction (`^ != 0 ( … )` to get a `b`, `^ ? cond 1 0` to widen one).
  No codegen change: accepted programs lower identically, and a program
  hitting the new diagnostic could never have linked.

- **ChaCha20-Poly1305 rewritten for the register allocator — a served TLS
  download goes 27 → ~170 MB/s.** The quarter-round made twelve
  bounds-checked Vec accessor calls per invocation (~960 per 64-byte
  block) with three Vec allocations per block and a per-byte `vec_push`
  output loop. The sixteen state words are now locals, key/nonce words
  are hoisted out of the block loop, full blocks XOR through raw
  pointers, and a block allocates nothing; Poly1305 reads full 16-byte
  blocks off the message pointer. Single-core: `chacha20_xor` 296 MB/s,
  `poly1305_mac` 1.3 GB/s — past gigabit wire speed for the whole served
  path, which is what a LAN can carry. RFC vectors and the TLS corpus
  tests pass unchanged.

- **`nurlpkg install` closes by naming what landed.** A tool install ends
  with `<name> <version> installed → <path>` (after the postinstall hint,
  so it is genuinely the last line); a project's dependency install ends
  with `<name> <version>: dependencies installed` — instead of a bare
  "done." either way.

- **`affine_mix` is gone; the suite is back to fifteen rows.** It was the
  closest pair in the corpus to `lcg` — both 20M-iteration serial xorshift
  mixing chains — and `chaincheck.sh` recorded the giveaway: the two rows
  carry the *same* documented floor of 6 cycles per iteration
  (`imul(3)+add(1)+shr(1)+xor(1)` against
  `lea(1)+and(1)+shr(1)+xor(1)+lea(1)+and(1)`). Different instruction mix,
  identical critical-path length, and so identical cells: the last run had
  the C column at 40.6 ms for `lcg` and 40.0 ms for `affine_mix`. That is
  the same objection that retired `stream_lcg` — it made the table longer
  without making it say more. `ring_write` and `histogram_bins` share that
  6-cycle chain too but each bolts something on it (an off-chain store, a
  read-modify-write), so they stay.

- **`hash_join` now runs 5M probes, up from 500k.** By the suite's own
  reading advice — "the rows worth comparing are the ones in the tens of
  milliseconds and up" — the row did not qualify: it measured 4.9–6.2 ms
  against a 1.8 ms process floor, so roughly three quarters of the cell
  was start-up. It was the one row the report told you to discount. The
  build table, capacity, Bloom width and probe pattern are unchanged, and
  the query count stays above the `use_partitioned` threshold, so the
  algorithm and its shape are the same — there is simply ten times as much
  of it. The compiled cells now land near 38–44 ms. The checksum changes
  with the query count, as expected.

### Fixed

- **Windows: `runtime.mingw.o` could not link `std/net` or `ext/http`.**
  `clock_gettime` / `nanosleep` / `readlink` and ten friends lived in the
  MSVC-only compat tier on the theory that mingw-w64 ships them — its
  headers do, but the functions live in libwinpthread (or nowhere), and
  the bundled zig links neither, so thirteen symbols came up undefined.
  Field-reported on v0.27.0 from a machine with no system LLVM — the
  exact path CI's runners, which all have LLVM, never walked. The compat
  code is now split into a shared `_WIN32` tier (what neither ABI
  provides) and an MSVC-only tier (what mingw genuinely has), verified
  by cross-linking the wide stdlib surface with
  `zig cc -target x86_64-windows-gnu`, and the Windows smoke test now
  imports that surface on both compiler paths instead of `core/io` alone.

- **Windows: every registry request failed before curl was even spawned,
  and nurlpkg reported it as "package not found".** The HTTP shim staged
  request/response bodies under `$TMPDIR`-or-`/tmp`; Windows spells its
  temp dir `TEMP` (or `TMP`) and has no `/tmp`, so the tempfile creation
  died first on machines without a stray `C:\tmp` — zero network calls,
  masked as a missing package. The temp dir now resolves
  `TMPDIR → TEMP → TMP → /tmp`, and `pkg_fetch_index` reports a transport
  failure as a transport failure, with the URL and a hint; only a genuine
  404 stays silent.

- **`nurlpkg test` and `nurlpkg bench` only worked inside a toolchain
  checkout.** Both resolved their build driver to a bare `./nurl.sh`, a path
  that exists in the NURL repo and nowhere else — so in a package built against
  an *installed* toolchain every single test failed identically with
  `/bin/sh: 1: ./nurl.sh: not found`, reported as `(compile error)`, which reads
  like the package is broken rather than the runner. They now resolve the driver
  the way `build`, `install` and the publish gate already do: `$NURL_CC` first,
  then a checkout's own `./nurl.sh` / `nurl.bat` when you are standing in one
  (so a toolchain build keeps testing with the compiler it just built), then
  `$NURL`, then the installed `nurl` on PATH. Both commands also resolve `deps/`
  first, like `build` does — a test importing `deps/<pkg>/src/...` no longer
  needs a separate `nurlpkg install` to compile.

- **Each bench results commit fired a second full CI round.** Now that the
  suite re-measures on every merge to main, the commit it pushes back — two
  data files, no code — re-triggered `ci.yml` (three required checks, one of
  them a FreeBSD VM) and `windows-tests.yml`, neither of which has a paths
  filter. Not a loop: `bench.yml` already excludes the results files from its
  own filter, so it never re-triggered itself. Just a doubling of CI cost per
  merge, against code that did not change. The results commits now carry
  `[skip ci]`; the numbers in them come from a run that passed the correctness
  gate and chaincheck before committing.

- **The bench results push authenticated as the wrong actor, and its retry
  destroyed the run's numbers.** Two defects in the freshly-landed direct-push
  path, both caught on its first real run. `actions/checkout` writes an
  `Authorization` header for `GITHUB_TOKEN` into the local git config, and that
  header **wins over credentials embedded in the remote URL** — so the push
  went out as `github-actions[bot]` and was refused with GH013 even though
  `BENCH_PUSH_TOKEN` was set. The header is now unset before the push. And the
  retry replayed with `reset --soft` + `commit --amend`, which rewrote the tip
  commit that had landed while the suite ran; the remote refused that as a
  non-fast-forward, turning one refusal into three. Worse, the replay stashed
  the results by path — but they are committed by then, so nothing was stashed,
  `stash@{0}` did not exist, and a successful replay would have published the
  *old* numbers. The files are now copied outside the worktree before the first
  push and restored onto whatever tip arrived; a replay that finds the new tip
  already carrying them exits clean. Verified against a real contended push.

- **nurl-lang.org published the previous release's benchmark table.** Two
  workflows fire on a `v*` tag: `web-deploy.yml` checks out the **tag** and
  renders the landing page's table from `bench/results/latest.json` as of
  that commit, while `bench.yml` starts at the same moment and needs tens of
  minutes. A tag is immutable, so it can never contain numbers measured
  after it was cut — and once `bench.yml` finally landed its results,
  nothing redeployed the site. Routing those results through a pull request
  (which is what changed) guaranteed they arrived after the deploy every
  time; before that they were usually already on main, which is why this
  looked like a regression rather than a design gap.

  Fixed from both ends. `bench.yml` now re-measures and **commits on every
  merge to main**, not only on tags and manual runs, so main is
  continuously current and a tag carries correct numbers by construction;
  the results files are already excluded from its own paths filter, so it
  does not re-trigger itself, and the push replays onto the tip if another
  merge lands during the run. And `web-deploy.yml` now takes the two
  results files **from main** rather than from the checked-out ref, so the
  deploy publishes the newest measured numbers however it was triggered —
  tag push or manual — instead of depending on when the tag was cut.
  Everything else the page is built from still comes from the checked-out
  ref, so a tag deploy still describes that tag.

  The committed table this release shipped with was measured at
  `fe2fc2930`, two releases back.

## [0.27.0] — 2026-07-27

A WebAssembly release. The toolchain could already compile NURL to
`wasm32-wasi` and run it on a runtime written in NURL; what was missing was
an honest measurement of what that costs — and building one turned up the
reason nobody had noticed the cost was wrong.

`bench/wasmbench.sh` compiles every benchmark in the corpus to native *and*
wasm in three languages and runs each module on two runtimes: the reference
`wasmtime` and `packages/wasmtime`. Running both is what earns its keep. A
JIT re-optimises whatever it is handed, so it reports about the same number
for a good module and a bad one; an interpreter executes exactly what is in
the module. That asymmetry exposed `zig cc` silently dropping `-O` for LLVM
IR inputs — **every wasm module the toolchain had ever produced shipped
unoptimised**, invisible in the reference column and a 5.5× gap in the
interpreter's.

With that fixed, the numbers became worth acting on. NURL's steady-state
wasm throughput is 1.0–2.1× native on most rows, at or better than clang's
own wasm output. The start-up gap that remained was all dead code, so
`--gc-sections` became the link default — after re-testing the closure
hazard that had blocked it at exactly the documented scale, where a
`--gc-sections` `nurlc.wasm` self-compiles the 65k-line compiler
byte-identically. And the interpreter itself went from walking raw bytes to
a predecoded register form: **191 → 56 host instructions per wasm
instruction**, and a full compiler self-host on it from 5m45s to 24s.

Also here: `nurl upgrade`, so the toolchain updates itself instead of
telling you to re-run a curl one-liner; `--version` on every binary; and
several toolchain seams that had been failing quietly — a missing
`realpath` stub that broke every wasm build reaching `path_canonical`
(`nurlc.wasm` included), the served installer still wiping the install
prefix, and `./build.sh` never building `nurlpkg`.

### Changed

- **`packages/wasmtime`: linear-memory access in words, frames from a
  pool.** Two follow-ups to the register core, measured separately. Memory
  first: `__mem_load`/`__mem_store` did a bounds-checked `Vec` access per
  *byte* — an `i64.load` was eight of them. Now one bounds check up front,
  then raw word access: any access that fits inside one 8-byte word (every
  naturally-aligned load and store) is a single machine load or one
  read-modify-write, and `memory.copy`/`fill` are `memmove`/`memset` on
  the raw buffer. Worth ~5 % on store-heavy rows — the dispatch loop, not
  the memory path, is what remains. Second: every call allocated and
  zero-filled a fresh slot array and freed it on return. Frames now
  recycle through a per-function pool; a reused frame only re-zeroes its
  declared locals (parameters are overwritten and register form writes
  stack slots before reading them). `fib` — pure call/return — drops
  5.7 s → 2.3 s, `json_parse` 2.1 s → 1.6 s, and the self-host compile
  30.5 s → 24.0 s, still byte-identical. The pool's high-water mark is the
  deepest recursion into that one function, already capped by max_depth.

- **`packages/wasmtime` executes in register form — the value stack is gone
  from the hot path.** wasm validation guarantees a static stack height at
  every instruction, so predecode now assigns the value at height h to slot
  (locals + h) of one flat per-frame array and resolves every operand to an
  absolute slot index. `local.get`/`set`/`tee` become register moves,
  `block`/`loop`/`end` emit nothing at all, and branches are direct jumps
  carrying their statically-computed result moves — there is no runtime
  control stack and no push/pop; a hot op is three raw word accesses. Code
  made unreachable by `br`/`return`/`unreachable` is parsed structurally
  (alignment survives hostile bytes; the hardening suite passes as-is) but
  emits nothing. Cold ops — floats, conversions, the 0xfc family, imports —
  bridge through the old value stack, so their semantics are the previous
  executor's arms verbatim.

  The interpreter now retires **56 host instructions / 18.9 cycles per wasm
  instruction**, from 191 / 54 at the start of this cycle. Same modules,
  predecode core → register core: `sort_window` 13.3 s → 5.4 s, `matmul`
  3.5 s → 1.5 s, `collatz` 2.1 s → 0.9 s, `lcg` 1.6 s → 0.9 s,
  `json_parse` 4.0 s → 2.1 s; `fib` is flat — its cost is now frame
  allocation per call, the next known target. The compiler self-hosting on
  the interpreter: 1m22s → **30.5 s**, still byte-identical (5m45s at the
  start of the cycle — 11x across the two rewrites). All 7 package suites
  pass unchanged.

- **`packages/wasmtime` executes predecoded function bodies.** The
  interpreter used to walk raw bytes: every operand LEB128-decoded again on
  every execution, and — much worse — every `block`/`loop`/`if` *scanned
  forward through its own body* to find the matching `end` each time it
  executed, because the byte stream stores no widths. Function bodies are
  now decoded once, on first call, into flat fixed-width records (opcode,
  operands, branch targets as record indices, plus the original byte offset
  so trap backtraces still point into the module image), and the execution
  loop reads those records with raw loads. The scans and the re-decoding
  are gone; `__find_end`/`__find_else` no longer exist.

  Measured on the wasm suite's modules, old core → new core: `json_parse`
  31.4 s → 5.75 s (**5.5×** — recursive descent is nested blocks all the
  way down), `fib` 15.9 s → 10.6 s, `binary_search` 18.2 s → 15.9 s, and
  the straight-line rows (`lcg`, `collatz`) ±5 % — their loops contained
  nothing to scan. The compiler self-hosting on the interpreter drops from
  5m45s to **1m22s**, still byte-identical to the native compiler. All 7
  package test suites pass unchanged, hardening included: predecode keeps
  the same bounded-input discipline (`__skip_imm` still steps over
  unsupported 0xfd/0xfe immediates so record alignment survives hostile
  bytes; execution still traps on them).

  What this deliberately does not fix: the remaining floor is the value
  stack — every push/pop is a bounds-checked `Vec` call, and at 2.5 IPC
  the loop is now latency-bound on that memory round-trip, not
  instruction-bound. The next real step is a register-form predecode
  (static stack-slot assignment, direct-jump branches, no runtime control
  stack), which this record layout was shaped to grow into.

- **`wasmbuilder` links with `--gc-sections` by default.** The previous
  default, `--no-gc-sections`, guarded against a real trap: NURL closures
  store function-table indices, section GC renumbers that table, and
  `nurlc.wasm` was observed to `call_indirect`-trap under it at >150
  functions. Before flipping, that blocker was re-tested at exactly the
  documented scale — a `--gc-sections`-linked `nurlc.wasm` **self-compiles
  the 65k-line compiler byte-identically to the native binary** under both
  the reference `wasmtime` and the pure-NURL `wt`, and the closure corpus
  (`test_05_closures_and_capture`, `test_06_torture_chamber`) passes.
  Whatever produced the historical trap, today's `wasm-ld` relocates
  address-taken functions correctly through GC.

  What the old default cost, measured by `bench/wasmbench.sh`: ~25 % of
  every module (`lcg`: 1064 → 820 KiB) and ~83 % of an empty program's
  module-load floor on the reference JIT (~60 → ~10 ms) — the single
  largest start-up gap between NURL wasm and C wasm. `--no-gc-sections`
  (library: `WbOpts.no_gc_sections`, replacing the short-lived
  `gc_sections` field) remains as the escape hatch; an indirect-call trap
  that appears only under the default would be the renumbering bug
  resurfacing and should be reported. The suite now measures the escape
  hatch as its tenth cell instead of the GC build, so its price stays a
  number. `nurlapi`'s `/build_wasm` still links `--no-gc-sections` — its
  wasi-sdk container path has not been re-validated the same way; the
  comment there now records the evidence for flipping it.

### Added

- **`nurl upgrade` — the toolchain updates itself.** Until now the only way
  to move to a new release was to re-run the website's one-liner, which the
  "a newer NURL toolchain is available" notice duly printed at you. There is
  now a command, and it is the one the notice prints:

  ```
  nurl upgrade                    # install the newest release, in place
  nurl upgrade --check            # report only; install nothing
  nurl upgrade --version v0.25.0  # pin a release (or go back to one)
  nurl upgrade --force            # reinstall this version / replace a dev build
  ```

  `nurl update`, `nurlpkg self-update` and `nurlpkg upgrade` are the same
  command — the spellings people guess all land in one place. `nurlpkg
  update` deliberately keeps its existing meaning (a *project's* dependency
  requirements); quietly repurposing it would have been worse than any
  naming win.

  It does not reimplement the installer: the release archive's checksum
  gate, signature gate and "replace the toolchain's files, keep the rest of
  the prefix" rule live in one script, and that script now ships *inside*
  the toolchain at `<prefix>/libexec/get-nurl.sh`. So an upgrade runs the
  installer that came with the version you already trust, rather than
  downloading a script and piping it to a shell — and there is no second
  implementation to keep in step. On Windows the same command drives the
  bundled `get-nurl.ps1`.

- **`--version` / `-v` on every binary in the toolchain.** `nurlfmt` had no
  version flag at all; `nurlc` only had the long form; `nurl` and `nurlpkg`
  accepted `--version` but never mentioned it. All four now answer to
  `--version`, `-v` and (where it isn't ambiguous) the bare word `version`,
  and say so in their usage text.

- **A wasm benchmark suite: `bench/wasmbench.sh` → `bench/WASMRESULTS.md`.**
  The sibling of `bench.sh`, same roster and same protocol, one axis
  rotated. `bench.sh` asks how fast NURL is against four other languages;
  this asks what *targeting wasm* costs, and what running that wasm on
  **NURL's own runtime** costs. Every benchmark's NURL, C and Rust sources
  are compiled twice — native and `wasm32-wasi` — and each module is run
  on two runtimes: the reference `wasmtime` (Cranelift JIT) and
  `packages/wasmtime`, the WebAssembly interpreter written in pure NURL.
  Ten timed cells per row, all gated on printing the same line as the
  native NURL binary, the interpreter *inside* the gate rather than beside
  it — a runtime that gets the wrong answer quickly is not a fast runtime.

  - **C and Rust are the control, not decoration.** A NURL-only
    wasm-vs-native ratio cannot tell "wasm is slower here" from "NURL's
    wasm pipeline is slower here". And modules emitted by two other LLVM
    frontends are the only honest test of a runtime developed against
    NURL's own output: `packages/wasmtime` runs all 15 benchmarks from all
    three languages with output identical to native.
  - **Everything under test is built from the working tree** — `nurlc`,
    `stdlib/runtime.o`, `packages/wasmbuilder` and `packages/wasmtime` —
    so the numbers describe this repo and not whatever is in `$NURL_HOME`.
  - **Running both runtimes is what found the bug.** A JIT re-optimises
    whatever it is given, so it reports roughly the same number for a good
    module and a bad one; an interpreter executes exactly what is in the
    module and reports the difference. The `-Xclang -O2` defect below had
    been shipping in every wasm build and was invisible in the reference
    column — it showed up as a 5.5× gap in the interpreter column.
  - **The reference runtime's compiled-module cache is turned off**
    (`-C cache=n`). Its CLI enables that cache by default, which made a
    cell mean "Cranelift ran" or "Cranelift did not run" depending on what
    happened to be in `~/.cache/wasmtime` — including for the floor row,
    whose whole job is to be subtracted from the others. Measured across
    that boundary, `lcg` came out *ten times faster* than its own empty
    program. Off, both runtimes are measured doing the same work: read the
    module, translate it, run it.

- **`wasmbuilder --no-gc-sections`**, and `WbOpts.no_gc_sections` for
  embedders — the escape hatch for the new `--gc-sections` default (see
  Changed). Section GC renumbers the wasm function table, and NURL closures
  store indices into it; if that ever produces a `call_indirect` trap again,
  this switches the old behaviour back on. `bench/wasmbench.sh` builds every
  benchmark both ways and holds both to the same output, so what the hatch
  costs stays a measured number: ~25 % more module and most of a JIT
  runtime's module-load floor.

- **`wasmtime --version` / `--help`.** The package had neither, while its
  sibling `wasmbuilder` had both, so nothing that shelled out to it could
  record which runtime produced a result.

### Fixed

- **`./build.sh` never built `nurlpkg`,** so a developer's `build/nurlpkg` was
  whatever they last built by hand while the same script handed them a fresh
  `nurlc` — the local toolchain could be months out of step with itself and
  look current. Only `.github/workflows/release.yml` ran
  `tools/nurlpkg/build.sh`. This is not hypothetical: a months-old `nurlpkg`
  predating `publish --dry-run` (and predating the unknown-flag rejection that
  was added to catch exactly this) silently ignored the flag and published for
  real. `build.sh` now builds it as a soft step, like `nurlfmt`.

- **`wasmbuilder`'s version stayed at 0.1.3 while its behaviour changed under
  it.** 0.1.3 is already published; the `--gc-sections` default flip, the
  `-Xclang` optimisation fix, the `realpath` stub and the declare-stripper fix
  all landed without a bump, and the README and `--help` text had already been
  written against "0.1.4". Now 0.1.4 in the manifest and in `--version`
  together — the same trap as the earlier 0.1.1/0.1.3 mismatch, in the other
  direction: there the literal lagged the manifest, here both lagged the code.

- **Every wasm build of a program whose imports reached `path_canonical`
  failed — including `nurlc.wasm` itself.** Two stacked defects, one seam.
  wasi-libc ships no `realpath(3)`, and it was missing from `wasi_ir.nu`'s
  POSIX stub list, so the symbol became an `env` wasm import and the
  reference `wasmtime` refused to *instantiate* the module (`unknown
  import: env::realpath`). Adding the stub exposed the second defect: the
  stub machinery removes the now-renamed `declare` line by *reconstructing*
  it with single spacing, but nurlc has two declare emitters — the FFI path
  prints `declare i64 @fork()`, the column-aligned prelude prints
  `declare i8*  @realpath(i8*, i8*)` — so the rebuilt line missed the
  padded kind, the stale declare collided with the appended define, and
  clang rejected the module ("invalid redefinition"). The stripper now
  locates the actual line by symbol (`__wb_ir_decl_line`) instead of
  guessing its spelling. The stub returns NULL, which `path_canonical`
  already maps to `None` — the honest wasm answer. `find_clone` (whose
  import graph spans the whole POSIX-stub surface) joins the wasmbuilder
  corpus so this seam stays covered.

- **The installer served from nurl-lang.org still wiped the whole install
  prefix.** `tools/get-nurl.{sh,ps1}` stopped doing that in July —
  an upgrade had been deleting the registry token, `models/`, `share/` and
  every program installed with `nurlpkg install`. But `nurlweb/public/
  install.{sh,ps1}`, the copies actually downloaded by
  `curl … | sh`, are made by a *manual* npm script that nobody re-ran, so
  the one-liner on the website kept handing out the destructive version.
  The copies are re-synced, and `tools/check_installer_sync.sh` now runs in
  CI so this class of drift cannot outlive a pull request.

- The prefix's `models/` cache and `libexec/` are now named explicitly in
  the installers' keep/remove rules, and the Windows installer renames a
  file it cannot delete instead of failing: `nurl upgrade` is a process
  upgrading the tree it is executing from, and Windows refuses to unlink a
  running `.exe` (POSIX allows it, which is why the same code path is
  uneventful there).

- **Every wasm module `wasmbuilder` ever produced shipped unoptimised code.**
  `zig cc` drops `-O` for LLVM IR inputs — it forwards the level for C, but
  for a `.ll` it passes nothing to cc1 and cc1 defaults to `-O0`. This
  pipeline hands zig a `.ll`, so nothing the user wrote was optimised: no
  mem2reg, so a loop counter stayed a linear-memory load/store pair, and
  `bench/lcg.nu`'s inner loop reloaded the same value twice per iteration.

  `nurl.sh` has carried the workaround for native builds since it was
  discovered there (`-Xclang <level>`, which reaches cc1 and survives);
  `wasmbuilder` never got the wasm half of it. Now it does.

  A JIT hid this completely, which is why it lasted: Cranelift re-optimises
  whatever it is handed, so the reference `wasmtime` timings moved by
  nothing. An interpreter cannot — `packages/wasmtime` ran `lcg` at 1M
  iterations in 1.09 s before and 0.20 s after, and the full 20M-iteration
  benchmark went **17.86 s → 2.77 s**. The gap between those two columns is
  what made the bug visible at all, and it is the reason the wasm suite runs
  both runtimes rather than only the fast one.

- **`packages/wasmtime`: the interpreter loop re-read its frame on every
  instruction.** The frame stack only moves on a call, a return, or falling
  off the end of a body, but the loop did a bounds-checked `vec_get`, an
  Option unwrap and a dependent load per *instruction*, then copied
  `pos`/`end` into the cursor and back out again. The cursor is now the
  authority on where execution is and the frame is cached until the stack
  moves; `pos` is written back exactly where something reads it (a call
  suspending the frame, a trap printing a backtrace). Worth 3–4 %.

  Two other candidates were tried and reverted, both measured: bisecting the
  opcode dispatch chain (−5 %) and a single-byte fast path in the LEB128
  reader (−12 %). The dispatch chain reads like a 177-comparison linear scan
  in the source but LLVM already lowers it to jump tables — one indirect jump
  in `__exec_op`, two in `__exec_num` — so "reordering by frequency" only
  split a working table into five. At 3.4 IPC and a 0.05 % branch-miss rate
  the interpreter is not stalling anywhere; it retires ~191 host
  instructions per wasm instruction, and that cost is spread across
  decode-at-execution and bounds-checked container access on every stack and
  local touch. Bringing it down needs a pre-decoded instruction
  representation, not local edits.

- **`wasmbuilder --version` reported 0.1.1 when the package was 0.1.3.** A
  version string is what a bug report quotes; a stale one misattributes the
  bug. Both this and the new `wasmtime` version literal carry a comment
  saying to keep them in step with `nurl.toml`.

- **`wasmbuilder`'s `--cflags`, `--obj` and `--asyncify-imports` were
  undocumented** — implemented in the CLI, absent from the README, so the
  only way to find them was `--help` or the source.

## [0.26.0] — 2026-07-26

A measurement release. Nothing here changes the language; what changes is
what the project can prove about itself.

The benchmark corpus is rebuilt into one suite — 15 benchmarks, each
implemented in NURL, C, Rust, Node **and** Python, each row timed only
after all five implementations print the same result — and the landing
page's table is now generated from the last run of that suite instead of
being typed by hand. Building it out to five languages turned up two
defects in the corpus itself: `hash_join` had been checksumming to zero
in every report it ever produced, because a random 64-bit probe key never
matches a 160-row table, so it was timing nothing but a Bloom filter's
reject path — and one C draw depended on the unspecified evaluation order
of `|`, i.e. on which compiler happened to build it.

The same instinct runs through the performance work: two hot paths were
paying for something nobody read (a `lock xadd` per allocation) or doing
work quadratically that they described removing elsewhere (four
borrow-checker scans re-running `strlen` per byte), and a self-compile is
11.6 % fewer instructions for it. One real miscompile is fixed —
an array *store* at a `u64` index emitted invalid IR that only clang
rejected, so a program could read at an unsigned index but not write at
one.

### Changed

- **One benchmark suite instead of two, five languages instead of
  three-or-four, and the landing page's table now comes out of the
  measurements instead of out of someone's memory.** `bench/` carried two
  runners with overlapping corpora — `run.sh` (3 benchmarks × NURL /
  Python / Rust / Node) and `run_micro.sh` (10 u64 kernels × NURL / C /
  Rust) — each with its own protocol, its own report format, and no
  language in common across the whole set. They are replaced by
  `bench/bench.sh`: one runner, one roster (`bench/manifest.tsv`), one
  contract, and every benchmark implemented in **all five** of NURL, C,
  Rust, Node and Python.

  - **The contract is now uniform.** Every implementation prints exactly
    one line — its checksum in decimal, masked to 63 bits so the
    languages without an unsigned 64-bit type can print it. The runner
    compares all five lines and refuses to time a row whose
    implementations disagree, which replaces the u64 set's dual-build
    `--verify` / `-DBENCH_VERIFY` / `--cfg bench_verify` machinery (and
    halves its compiles).
  - **31 implementations written** to fill the matrix: C for `lcg`,
    `sieve`, `fib`, `collatz`, `matmul` and `json_parse`; Python and Node
    for the nine u64 kernels. Where a kernel is genuinely 64-bit wide,
    the Node port uses `BigInt`, and where 32 bits suffice it uses
    Numbers with `Math.imul`; each file states which and why, and the
    checksum gate is what keeps "each language at its fastest exact
    representation" from drifting into "each language computing
    something else".
  - **`hash_join` was measuring nothing.** Its checksum was all-zero in
    every report because probe keys were drawn at random from a 64-bit
    space and a 160-row table never matched one — so the benchmark only
    ever exercised the Bloom filter's reject path, which the report
    dutifully noted and nobody acted on. Every second query now probes a
    key that was actually built, with the LCG stream advanced identically
    on both sides of the branch.
  - **`stream_lcg` removed** as a duplicate: it was `lcg` with 32-bit
    constants, so it made the table longer without making it say
    anything new. No two rows in the suite now measure the same shape.
  - **Workloads retuned** so the compiled languages land in a range wall
    clock can resolve and the interpreted ones stay finite: `matmul`
    128 → 256, `json_parse` 5 → 20 parses, `bloom_filter` 1M → 4M
    queries, `sort_window` 5M → 2M, `affine_mix` / `ring_write` 50M →
    20M, `packet_classifier` 50M → 25M. Slow cells get fewer repetitions
    (`--budget-ms`) rather than a shorter workload, so every language
    runs the same computation.
  - **Two artefacts per run**: `bench/results/latest.json`
    (machine-readable) and `bench/RESULTS.md` (run times, compile times,
    correctness gate, and a process-start-up floor row to subtract).
    `.github/workflows/bench.yml` runs the suite weekly and on demand and
    commits both.
  - **nurl-lang.org's "Measured, not promised" table is generated** from
    that JSON at publish time by `tools/gen-bench-table.mjs`, wired into
    nurlweb's `predeploy` hook. The page stays 100 % static at serve time
    and can no longer drift from the measurements: the three hand-typed
    rows are gone, replaced by all fifteen, with the fastest cell in each
    row highlighted.
  - `bench/verify.sh` now defaults to the `genacc/` task list (it is the
    correctness gate for the generation-accuracy and token studies, whose
    string tasks are deliberately not benchmarks), and `bench/perfstat.sh`
    reads the roster from `manifest.tsv` and the new one-line checksum.

### Performance

- **The runtime's allocation counters cost more than the allocations
  they counted.** `nurl_alloc` / `nurl_zalloc` / `nurl_free` each bumped
  a process-wide `unsigned long long` with a RELAXED atomic, on the
  recorded grounds that it "costs nothing measurable next to the malloc
  itself". On x86 a relaxed read-modify-write is still a `lock xadd` —
  ~20 cycles plus a store-buffer stall — and every NURL program paid it
  twice per allocate/free pair whether or not anything ever read the
  counter. Each thread now counts into a heap block of its own with
  plain arithmetic and readers sum the blocks, so the totals and their
  monotonicity are unchanged (verified across threads) and the lock
  prefix is gone. Measured on a pinned core: `bench/stdlib_hotpath.nu`'s
  `sort_32_desc` −10.0 % cycles, `string_build_16` −9.7 %,
  `vec_push_64` −3.9 %; parsing `bench/data.json` −8.1 % cycles / −9.4 %
  wall clock.

- **Four borrow-checker scans were quadratic in their own input.**
  `bck_st_set`, `bck_join_state`, `bck_field` and `bck_explode` walked
  their strings with `nurl_str_get`, which re-runs `strlen` on every
  call — so each byte examined cost a pass over the whole string, in the
  functions whose own comments described removing exactly that cost
  elsewhere. They now read through hoisted `*u` pointers, like the
  neighbouring `__bck_st_get_at`. A nurlc self-compile drops 3.69 G →
  3.26 G instructions (−11.6 %) and 552 ms → 514 ms (−7.0 %); the borrow
  checker was 42 % of the compiler's run time before the change. Gate:
  all 1122 `.nu` files under `compiler/tests`, `stdlib`, `examples` and
  `packages` compile to byte-identical IR *and* byte-identical
  diagnostics.

### Fixed

- **The benchmark workflow could not publish its own results.** Its
  refresh step pushed `bench/results/latest.json` and `bench/RESULTS.md`
  straight to `main`, which a repository ruleset declines with GH013:
  changes to `main` must arrive through a pull request. The suite ran,
  the gate passed, the report was written — and the last step threw it
  away with a red X. It now commits to a `bench-results/<date>-<run>`
  branch and opens a PR (pushing a new branch is allowed), so the
  numbers reach `main` the way every other change does. The step
  documents what is still needed for that PR to merge itself: a PR
  opened with the built-in `GITHUB_TOKEN` does not trigger workflow
  runs, so the required checks never start and `--auto` cannot complete
  — either the Actions bot needs a ruleset bypass, or the step needs a
  PAT.

- **`bench_auto` could report a regression for a build that got
  faster.** Its iteration ramp multiplies by 4 and stops at the first
  pass clearing 50 ms, so a body whose cost sits near that threshold
  lands on opposite sides for two builds and the two results then come
  from runs 4× apart in length. On `sort_32_desc` that reported +5 %
  ns/op for a build that was 8 % faster on both cycle count and wall
  clock. `bench_auto` now scales back onto the target window and
  measures once more, so every reported number comes from a run of about
  the same length.

- **An array store at an unsigned index emitted invalid IR.** `= . p idx v`
  where `idx` had a sized unsigned type printed the NURL type name into
  the getelementptr — `getelementptr i64, i64* %p, u64 %idx` — instead of
  lowering it like every other type on the line. nurlc accepted it with
  rc 0 and only clang rejected it, with a bare `error: expected type` and
  no NURL source location. The four index-store paths in `gen_stmt` now
  lower the index operand through `nurl_llty`, as the matching load paths
  already did; before this, a program could *read* at a `u64` index but
  not *write* at one. Regression: `compiler/tests/gep_unsigned_index_store.nu`.

### Added

- `bench/` gains nine u64 kernels — `affine_mix`, `packet_classifier`,
  `ring_write`, `histogram_bins`, `prefix_scan`, `binary_search`,
  `sort_window`, `bloom_filter`, `hash_join` — each a deliberately
  different shape (branch misprediction, dependent stores, pointer
  chasing, a compare/branch mill, an early-out plus a rare slow path).
  They are part of the five-language suite described above, so each ships
  with a NURL, C, Rust, Node and Python implementation.

- `bench/perfstat.sh` — the same kernels measured in retired
  instructions and core cycles instead of wall clock, with a
  save/compare mode for A/B-ing a compiler or runtime change. Wall clock
  on this set drifts by several per cent between runs, which is enough
  to invent a language difference that is not there: the first report
  showed `histogram_bins` at 1.15× against C when the two binaries
  retire the same instructions in the same cycles. Counters make a 1 %
  change legible and a regression impossible to miss.

## [0.25.1] — 2026-07-26

A Windows repair release. 0.25.0 taught the driver to prefer the zig the
archive has always bundled — the whole point of bundling it being that a
machine with no Visual Studio can still build a program — and nothing had
ever driven that path end to end. It could not link anything, in three
different ways, each hidden behind the one before it. The release
workflow would not have caught it either: that runner has LLVM, so the
driver fell back to clang and passed.

Nothing here changes the compiler or the language; every fix is in the
Windows build and link path, plus the CI that was supposed to be watching
it.

### Fixed

- **Windows: the bundled zig could not link a program at all.** The
  archive ships a zig so a machine with no Visual Studio can still build,
  and 0.25.0 taught `nurl.bat` to prefer it — but nothing had ever driven
  that path end to end. It failed three ways, each hidden behind the one
  before it. `zig cc` targets `x86_64-windows-gnu`, so:
  - `bcrypt` and `ws2_32` were requested only by `#pragma comment(lib,
    ...)` directives inside `runtime.o`, which is how the MSVC toolchain
    finds an import lib without anyone naming it. Under MinGW those
    directives are mangled to `libbcrypt.a`, a name nothing in this
    toolchain produces (zig synthesises `bcrypt.lib`), so the link died
    on a file it could never open. The pragmas are now MSVC-only, as
    `runtime_core.c` has always had them, and `nurl.bat` names the import
    libs the way `nurlapi`'s mingw-w64 cross link always has.
  - Underneath that, `runtime.o` is clang-built and therefore MSVC-ABI:
    it references `_setjmp`, `__chkstk` and `_fltused`, none of which
    MinGW's CRT provides. The two ABIs cannot share one object, so
    `build.bat` now also emits `stdlib\runtime.mingw.o` with zig when a
    zig is present, and `nurl.bat` links whichever object matches the
    compiler it chose. Programs built through the bundled zig cannot use
    the canvas FFI or the zstd FFI (both MSVC-only artifacts); the driver
    now says so instead of leaving it to the linker.
  - The release workflow fetched its zig *after* running `build.bat`, so
    the archive would have shipped without the MinGW runtime — and its
    smoke test would not have caught it, because the release runner has
    LLVM and the driver falls back to clang. Both workflows now fetch zig
    first, and the release smoke test asserts the object is in the
    archive and builds a program both ways.
- **A stale Windows golden.** `float_extra`'s expected output was written
  in June and never grew the seven `erf`/`erfc` lines 0.25.0 added, so
  Windows CI went red one push later. `tools/check_windows_goldens.sh`
  now catches that shape from Linux — a Windows golden missing lines its
  Linux counterpart has — since the Windows leg only runs on `main`.

## [0.25.0] — 2026-07-26

The release that makes `packages/torchpt` and everything above it
installable: the zip64 reading a 4.6 GB PyTorch checkpoint needs landed
an hour after 0.24.1 was tagged, so every package built on it has been
unbuildable by the released toolchain until now.

Also the largest compiler speed-up so far, and a codegen fix that made
`vec_extend` uncompilable for struct elements.

### Added

- **zip64 reading, and archives over a pointer.** `stdlib/ext/zip.nu`
  gained `zip_open_ptr` (open an archive over a memory-mapped range
  without copying it into a `Vec u` first), `zip_find`, `zip_csize_at`,
  `zip_method_at`, `zip_data_off`, and zip64 central-directory support —
  the 64-bit size/offset extra field, so an archive over 4 GB is
  readable at all. A PyTorch `.pt` checkpoint is a zip, and a 4.6 GB one
  needs every part of that: `packages/torchpt` reads the 1342 tensors of
  a real checkpoint in 0.01 s and 31 MB of RSS by mapping the file and
  never copying an entry it is not asked for.
- **`erf` / `erfc`** in `stdlib/std/float.nu` — the exact GELU a
  transformer wants (`x·Φ(x)`), not the tanh approximation.

### Changed

- **The compiler is 34% faster and uses a third of the memory.** A
  self-compile went 0.83 s → 0.55 s and peak RSS 405 MB → 122 MB, with
  the IR and diagnostics of all 1121 `.nu` files in the tree byte-for-byte
  unchanged. The borrow checker was 56% of a compile; it is now 40%.
  Four findings, all of them shape rather than constant:
  - **The symbol table was being used as an accumulator, and `def`
    shadows rather than replaces.** `bck_record` appended one line per
    statement by fetching the whole accumulated list (a `strdup`),
    concatenating, and defining it back (another `strdup`) — three
    copies of the entire list per statement, with every older copy left
    in the table because a define pushes a new entry. That is O(N²) time
    AND O(N²) live memory per function. `nurl_sym_set` overwrites in
    place when the newest entry is at the current depth (which is always,
    for a table that is never pushed or popped), and `nurl_sym_append`
    grows the value with one `nurl_realloc`. This is where most of both
    wins came from.
  - **62% of symbol lookups built their key just to hash it.**
    Metadata queries are keyed `<name>__field_count`,
    `<name>__variants` and so on — 740k per self-compile, each
    materialising the key with a malloc, two memcpys and a free.
    `nurl_sym_get2` takes the two parts and never joins them: FNV-1a is
    a streaming hash, so the hash of the parts IS the hash of the
    concatenation, and the chain compare comes apart the same way.
  - **`str_contains_word` re-sliced the tail per word.** The same shape
    already found and fixed inside the borrow checker's state lookup was
    still in the helper 87 call sites use: `str_first_word` scans with
    `nurl_str_get` (strlen per byte) and allocates the word,
    `str_skip_word` allocates a copy of the whole remaining tail. O(L²)
    bytes and 2W mallocs per containment test. It searches for the word
    and checks the boundaries now, allocating nothing.
  - **The borrow checker's state lookup walked token by token**, calling
    `memmem` once per token to find the next separator — ~100 calls per
    lookup on a 1 KB state, 41M of them per self-compile, each scanning
    ten bytes, where the call overhead *is* the cost. One search for the
    name replaces the whole walk.
  - Also: `nurl_sym_len` / `nurl_sym_len2` answer "is this set?" without
    copying the value out, at the 77 sites that asked
    `nurl_str_len ( nurl_sym_get … )`.

### Changed

- **`nurl_str_float` searched linearly for the shortest round-tripping
  decimal.** It tried `%.1g`, `%.2g`, … up to `%.17g`, parsing each back
  with `strtod` until one matched — seventeen `snprintf` + `strtod` pairs
  for the worst case, which is *the common case*: a double that came from
  an f32 needs ~17 significant digits. That is ~2.5 us per number, and it
  is on the path of every float any NURL program prints. "p digits round
  trip" is monotone in p, so it is a binary search: five probes instead
  of seventeen. Found by profiling a point-cloud writer, where formatting
  three coordinates per point cost more than the neural network that
  produced them.

### Fixed

- **`= . p + k 0 v` did not compile when the element type was a
  struct.** A store through a computed pointer index died with
  `unknown field or variable: +`, naming the operator as if it were a
  field. The READ path had always accepted the same expression; only the
  store peeked at the token after the pointer and, finding something
  that was not an identifier, fell through to the error.
  `stdlib/core/vec.nu`'s `vec_extend` hits it the moment its element
  type is an aggregate — the generic monomorphises and fails with a
  diagnostic pointing at nothing the caller wrote.
- **wasm builds trapped at runtime for programs calling libc `rand`.**
  The wasm32 ABI shims hardcoded each shim's signature from a letter
  table, but the signature the CALL SITES use comes from the NURL
  source. They are derived from the IR now.

- **Canvas examples that call libc `rand` died on the playground with
  "runtime error: unreachable".** `doomfire.nu`, `sand.nu` and
  `starfield.nu` compiled (BUILD OK, a well-formed .wasm) and then
  trapped — doomfire and starfield on their first frame, sand on the
  first mouse-drawn grain. `gameoflife.nu` declares `rand` but never
  calls it, which is why it kept working and made the failure look like
  a canvas problem.

  The wasm32 libc ABI shims in the `/build_wasm` IR rewriter
  (`nurlapi/main.nu`, mirrored in `packages/wasmbuilder/src/wasi_ir.nu`)
  hardcoded each shim's signature from a letter table. But the signature
  the call sites use comes from the NURL source: nurlc's own prelude
  declares `puts` / `strcmp` / `fseek` with C-accurate i32 returns, while
  `& \`libc\` @ rand → i` emits `declare i64 @rand()`. Since v0.9.x the
  table's `i` letter meant "shim returns i32", so every FFI-declared
  `→ i` libc function got an i32 shim under i64 call sites. wasm-ld does
  not reject that mismatch — it resolves it with a stub whose body is a
  single `unreachable`, so the module links and traps at the call.

  The rewriter now reads the `declare` line back out of the IR and
  mirrors it, converting widths in the wrapper (trunc on the way in,
  sext/zext on the way out); the letters only describe the wasm32 libc
  side. This also repairs `open` / `close` / `read` / `write`, whose
  shims were mismatched the same way for every `std/fs.nu` and
  `core/posix.nu` caller on wasm, and stops `%r = tail call void @exit(…)`
  — invalid IR — from being emitted for the void-returning entries.
  `nurlapi/e2e_test.py` now asserts every `__nurl_*_shim` definition
  matches its call sites.

## [0.24.1] — 2026-07-25

A patch for a display bug that read as a transfer bug: model downloads
were reported as steadily slowing down when they were not.

### Fixed

- **The transfer progress bar reported a falling rate on a transfer that
  was not slowing down.** `stdlib/std/progress.nu` derived its rate from
  `cur / (now - started)` — an average over the whole transfer. Two
  consequences, both visible on a model download:

  * On a **resume**, the caller sets the already-downloaded bytes with
    `progress_set` immediately after `progress_new`, so the first render
    divided (say) 400 MB by 0.2 s and printed **3.7 GB/s**, then decayed
    continuously — 763 MB/s, 381 MB/s, 191 MB/s — while the actual
    throughput sat at a constant 1 MB/s. That is the "starts at full
    speed and steadily declines" report.
  * Even from zero, a cumulative average cannot react: a transfer that
    settles at its real rate after a fast first second spends minutes
    crawling down toward the truth.

  The rate is now the **current** throughput — an exponential moving
  average over roughly the last second of samples, the number `curl` and
  `wget` show — measured from the resume point, so bytes that came off
  the disk never count as network throughput. `progress_done` reports the
  average over this session's bytes.

  Measured on the same synthetic resume (400 MB present, steady 1 MB/s):
  before `3.7 GB/s → 763 → 381 → 191 → 127 MB/s`; after a flat
  `975 KB/s`.

  The transfer itself was never slow: a 4-minute, 195 MB download through
  the same stdlib path (TLS + `file_write_chunk` + `sha256_update`) held
  462 → 939 KB/s with no trend, at 15% CPU and flat RSS, against 725 KB/s
  for `curl` on the same URL at the same time.

## [0.24.0] — 2026-07-25

The **performance** release. No new language surface — this one is about
making what already exists fast, and about how the slow parts were found.
Three discovery routes, each catching a class the others would have missed:
reading the primitives, surveying allocations per operation, and finally
profiling a real workload. The last one turned on the compiler itself.

`nurlc` compiles its own 1 MB source **4× faster** (3.43 s → 0.86 s), and
the stdlib's byte-level paths — hex, base64, percent-encoding, case
mapping, the TOML/XML/URL parsers, regex — are between 2× and 656× faster.
Emitted IR is byte-identical throughout: every change here is a
same-output, less-work change, and the bootstrap fixed point holds.

One correctness fix rode along: `string_eq` compared with `strcmp`, so two
Strings differing only after an embedded NUL compared equal.

### Added

- **`nurlpkg` tells you when your toolchain is behind.**
  `stdlib/ext/update_check.nu` prints at most one line to stderr *after*
  a command's output when a newer release exists. Best-effort and
  non-fatal (never blocks the command, never changes its exit code),
  cached to at most one network probe per day (`$NURL_HOME/
  .update-check`), and silent where the notice would be noise: opt-out
  via `$NURL_NO_UPDATE_CHECK`, in CI, when stderr is not a terminal, and
  on a dev/dirty build. This closes the real hazard behind the
  "`publish --dry-run` published for real" scare — a stale binary
  predating `--dry-run` running against today's registry.

- **`packages/benchmark` 0.1.1 — reproduce NURL's performance claims on
  your own machine.** sha256 / json / sort / cbor / utf8 / int-loop plus
  a 1 M-row CSV sort (parse with the stdlib CSV reader, sort by
  `(type, date, uuid)`). Renamed from `bench` — the registry reserves
  that name. 0.1.1 fixes an O(N²) in the utf8 benchmark that reported
  0 MB/s in the wild.

- **`packages/hub` 0.1.1 — fetch models from Hugging Face into one
  shared, verified cache** (`~/.nurl/models`). `embed` 0.1.4,
  `whisper` 1.0.4 and `nurllama` 0.12.10 now accept a Hugging Face ref
  directly and fetch through it.

- **`string_reserve_at` / `string_commit` (`stdlib/core/string.nu`) — a
  bulk emission cursor.** `string_push_char` costs a call, three
  `nurl_peek`s and a `nurl_poke` per byte — ~1.7 ns even on its fast
  path, because the compiler must re-read the control block every time
  (the store could alias it). An encoder that knows how many bytes it is
  about to produce can now reserve the room once, write straight through
  a `*u`, and commit at the end: measured **565 ns vs 7 061 ns** for
  4096 bytes (12.5×). The reserved pointer is valid only until the next
  operation that can grow the buffer — the contract is spelled out at
  the definition. Committing fewer bytes than reserved is allowed, so
  encoders whose output size is only an upper bound (percent-encoding)
  can use it too.

- **`nurl_str_at str len idx` (`stdlib/core/string.nu`) — the O(1) byte
  accessor scan loops want.** Same contract as `nurl_str_get` (0 when
  `idx` is outside `[0, len)`, which is what parsers rely on when they
  peek one or two bytes past the cursor), but the caller passes the
  length it already knows, so no `strlen` runs. `nurl_str_get` stays for
  one-off reads where no length is at hand.

### Changed

- **Two more quadratics inside `nurlc` — self-compile 1.01 s → 0.86 s.**
  Found with `perf` (the previous compiler fix came from gprof), which
  showed 20% of the compiler's runtime inside libc `strlen` and named
  the two callers:

  * `emit_hoisted` materialised **every IR line** with `nurl_str_slice`,
    which re-runs `strlen` over the *whole function body* and mallocs a
    copy — per line, and twice, since the pass runs once for allocas and
    once for everything else. That is quadratic in function-body size
    (8.7% of total runtime in `strlen` alone, plus a leaked allocation
    per emitted line). Lines are now printed in place: write a NUL over
    the terminating newline, print from the buffer, restore the byte.
    `nurl_print` consumes its argument synchronously and
    `nurl_print_buf_stop` returns an independent `strdup`, so the swap is
    never observable.
  * `__bck_st_get_at` — the borrow checker's per-binding state lookup,
    called 14.8M times per self-compile — scanned its space-separated
    state string with `nurl_str_get`, i.e. a `strlen` per byte examined
    (17% of the profile, plus 5% more inside `strlen`). The token walk
    now runs on `memmem` + `memcmp`.

  Emitted IR is byte-identical and the bootstrap fixed point holds. Peak
  RSS is unchanged. `memchr` was tried in place of `memmem` for the
  one-byte needles and made no measurable difference, so it was dropped
  rather than carried for the extra FFI declaration.

- **`nurlc` recomputed the current line number by rescanning the source
  from byte 0 on every parser backtrack — 3.3× faster self-compile.**
  `nurl_lex_set_pos` counted newlines from the start of the file to
  derive `LX_LINE`, so each backtrack cost O(source size). The parser
  backtracks per closure body, per `??` guard arm and per
  paren-disambiguation probe, which makes the total quadratic in file
  size for closure- and match-heavy sources. `nurl_lex_new` now builds a
  newline-offset index once (one O(n) pass) and `set_pos` binary-searches
  it.

  Measured: nurlc compiling **its own 1 MB source drops 3.43 s → 1.03 s**.
  Emitted IR is byte-identical, and the bootstrap fixed point still
  holds. The effect scales with source size — on a synthetic
  closure-heavy file, 32 KB is unchanged while 264 KB goes 0.58 s →
  0.30 s and the growth curve turns from super-linear to linear:

  | source | before | after |
  |---|---|---|
  | 32 KB | 0.05 s | 0.04 s |
  | 65 KB | 0.09 s | 0.07 s |
  | 131 KB | 0.28 s | 0.14 s |
  | 264 KB | 0.58 s | 0.30 s |
  | 1 017 KB (nurlc.nu) | 3.43 s | 1.03 s |

  Whole-build wall-clock moves less than this suggests: `./build.sh` is
  dominated by clang/LTO, and nurlc is ~10 s of it across the bootstrap
  stages. Found by profiling (gprof) rather than by reading — the old
  `set_pos` was 89% of nurlc's self-compile profile.

- **Per-item overhead removed from the hot emitters and from the regex
  engine.** Two distinct costs, same shape — work repeated per byte or
  per loop iteration that only needed doing once:

  *Cursor emission.* `bytes_to_hex`, `hex_encode`, `__b64_emit`,
  `url_percent_encode`, `string_to_lower` / `_to_upper` / `_reverse` and
  `__fmt_emit` produced their output one `string_push_char` at a time.
  They now reserve the exact (or upper-bound) output length once and
  write through the new cursor; `__fmt_emit` additionally copies each
  literal run between placeholders in one `string_push_bytes` instead of
  a push per byte.

  *Scratch reuse.* `__rx_run_at` allocated **four `Vec[i]` on every start
  position** of a search — 8 005 allocations for a 2 KB `regex_replace` —
  and re-zeroed them with a per-state loop each time. The four buffers
  carry no state between runs, so every public regex entry point now
  builds one `RxScratch` up front and reuses it for the whole scan.
  Passing the scratch explicitly (rather than caching it inside the
  `Regex`) keeps a compiled `Regex` reentrant.

  Measured (`std/bench.nu`, `-O2`, ns/op):

  | | before | after | |
  |---|---|---|---|
  | `string_to_lower` 4 KB | 14 325 | 366 | **39×** |
  | `hex_encode` 4 KB | 25 573 | 1 004 | **25×** |
  | `bytes_to_hex` 4 KB | 25 342 | 1 058 | **24×** |
  | `regex_replace` 2 KB | 557 647 | 77 382 | **7.2×** |
  | `b64_encode` 4 KB | 16 349 | 4 270 | **3.8×** |
  | `url_percent_encode` 1 KB | 6 902 | 2 157 | **3.2×** |
  | `regex_test` 2 KB | 1 924 | 595 | **3.2×** |
  | `fmt1`, 512 B template | 1 758 | 548 | **3.2×** |

  `regex_replace` drops from 8 005 to 5 allocations per call and
  `regex_test` from 28 to 4. Byte-for-byte output is unchanged: the
  encoders are covered by the RFC known-answer vectors in the corpus
  (blake2b, chacha20poly1305, x25519, ed25519, aes-gcm, hkdf, pbkdf2,
  ecdsa-p256), and the whole suite is ASan/UBSan-clean — the check that
  matters for an API that hands out a raw write cursor.

- **The `nurl_str_get` scan loops are gone from the parsers — 278 of the
  426 call sites migrated to `nurl_str_at`.** Follow-up to the hot-path
  work in the previous entry: `nurl_str_get` re-runs `strlen` per call,
  and in any loop that also writes (i.e. every parser) LLVM cannot hoist
  that `strlen`, so the scan is quadratic in input size. Migrated
  `ext/{yaml,toml,xml,nurldoc,websocket,http_router,http_request,
  http_multipart,regex,tar,csv,json,semver}` and
  `std/{url,time,path,fs,decimal,encode}`. Measured (`std/bench.nu`,
  `-O2`, ns/op):

  | | before | after | |
  |---|---|---|---|
  | `toml_parse` 2 KB | 82 965 | 21 018 | **3.9×** |
  | `url_parse` 600 B | 6 195 | 2 581 | **2.4×** |
  | `xml_parse` 3 KB | 152 096 | 74 278 | **2.05×** |
  | `path_normalize` 450 B | 24 872 | 19 883 | 1.25× |
  | `regex_replace` 2 KB | 610 963 | 501 084 | 1.22× |
  | `http_date_parse` | 165 | 159 | 1.04× |
  | `semver_req_parse` | 3 106 | 3 090 | ~1× |
  | `yaml_parse` 2 KB | 51 535 | 52 095 | ~1× |

  The two flat rows are expected and worth recording: `semver` inputs are
  a few dozen bytes, and `yaml_parse` splits the document into short
  lines through an accessor that was already O(1) before scanning them —
  so neither was quadratic in practice. The gain tracks input size, so
  the parsers fed whole files (`toml`, `xml`, `nurldoc`, `tar`, `csv`)
  are where it shows. No API or behaviour change: `nurl_str_at` keeps
  `nurl_str_get`'s out-of-range-returns-0 contract, and every migrated
  site passes a length that is already the string's own.

- **`stdlib/std/tls.nu` — offer ChaCha20-Poly1305 ahead of AES-128-GCM
  (~3× faster HTTPS downloads).** The record layer, not the network, was
  the ceiling on every large `https://` transfer: our AES-128-GCM is the
  deliberately table-free constant-time S-box (recomputed per byte, ~160
  S-box evaluations per 16-byte block), which measures **0.5 MB/s**,
  while the pure-NURL ChaCha20-Poly1305 next to it runs **~25 MB/s** —
  a 50× difference the ClientHello was throwing away by listing 0x1301
  first. Both TLS 1.3 suites use the same SHA-256 key schedule, so the
  reorder touches nothing else in the handshake, and AES-only peers
  still get 0x1301 from the same list. Measured end-to-end on
  `nurllama run LumiOpen/Llama-Poro-2-8B-Instruct` (Hugging Face → its
  CloudFront CDN, which honours client preference), same 8 MB back to
  back: **188 KB/s → 594 KB/s**, with per-transfer CPU dropping
  **25.1 s → 2.0 s** — i.e. the client went from CPU-bound to
  network-bound, and now tracks `curl` on the same link (675 KB/s).
  Against `speed.cloudflare.com`: 487 KB/s → 1185 KB/s (curl:
  1174 KB/s). The per-byte CPU ceiling is now ~8.5 MB/s rather than
  ~0.34 MB/s, so the download-side numbers vary with what the far end
  will give. Servers that pin their own preference to AES (e.g.
  `huggingface.co`'s API host, which serves only the small metadata
  files and the redirect) still negotiate AES-128-GCM and remain slow —
  a bitsliced constant-time AES is the fix there, not a lookup table.
- **`stdlib/std/tls.nu` / `stdlib/std/bytes.nu` — memcpy the record-layer
  copies.** `_tls_cat` and `bytes_slice` were per-byte `vec_push` loops
  sitting on the receive hot path, where every TLS record is copied four
  times (socket → `rxbuf`, body out, remainder back, plaintext →
  `appbuf`). Both now go through `nurl_memcpy` (`bytes_extend_bytes` /
  `bytes_extend_raw`): ~0.3 s less CPU per 10 MB downloaded, and the
  slice+concat cost for 10 MB of 16 KB records is now 1 ms. (Companion
  to the `nurl_str_get` / `vec_get` sweep below, which left `bytes_slice`
  untouched.)
- **stdlib hot paths — the per-byte `nurl_str_get` / `vec_get` walks are
  gone.** `nurl_str_get` re-runs `strlen` on every call, so a loop that
  scans a string with it is O(n²). In a read-only loop LLVM hoists that
  `strlen` away, which is why the cost hid for so long — but every real
  parser *writes* while it scans, and the store blocks the hoist. Six
  stdlib functions were paying it, plus four more that walked a byte
  buffer through an `?u`-returning `vec_get` (a bounds check and an
  Option per byte) where a `memcpy` / `memcmp` / `memmem` was available.
  Measured (`std/bench.nu`, `-O2`, ns/op, same machine):

  | | before | after | |
  |---|---|---|---|
  | `bytes_from_str` 4 KB | 117 497 | 179 | **656×** |
  | `bytes_to_str` 4 KB | 16 820 | 171 | **98×** |
  | `bytes_eq` 4 KB | 1 481 | 55 | **27×** |
  | `bytes_from_hex` 2 KB | 20 047 | 3 322 | 6.0× |
  | `parse_request_head` 4 KB | 16 776 | 5 244 | 3.2× |
  | `url_percent_decode` 768 B | 6 216 | 1 764 | 3.5× |
  | `url_percent_encode` 768 B | 11 248 | 4 000 | 2.8× |
  | `fmt1`, 512 B template | 5 092 | 1 845 | 2.8× |
  | `bytes_to_hex` 1 KB | 9 122 | 6 895 | 1.32× |
  | `string_push_char` ×1024 | 4 035 | 2 693 | 1.50× |

  `string_push_char` also gained an inline fast path: it used to run two
  independent capacity checks per byte (one in `vec_push`, one in
  `_string_seal`'s `vec_reserve`) even on a pre-sized buffer. It is the
  most-called mutator in the stdlib, so every text builder — JSON, CBOR,
  YAML, TOML, `fmt`, hex — gets the 1.5×. No API or allocation-count
  change anywhere.

- **`stdlib/std/sort.nu` — insertion-sort cutoff for small subranges.**
  `sort_by` / `binary_search`'s quicksort now hands ranges of ≤16 elements to
  a straight insertion sort instead of partitioning them all the way down.
  Measured ~22% faster end-to-end on the `benchmark` suite's `sort i64` row
  (18 → 22 M/s) and ~15% on a 2 M-element i64 sort, with no allocation or API
  change. Investigation note: the win is the algorithm, not closure
  elimination — a monomorphic comparator closure is branch-predicted and
  costs ~1-2% over a hand-inlined compare (measured), so higher-order sorting
  in NURL is already essentially free. As a side effect small all-equal
  ranges now keep their input order (insertion sort is stable below the
  cutoff); `sort_by` still makes no general stability guarantee.

### Fixed

- **`string_eq` compared with `strcmp`, ignoring everything after an
  embedded NUL.** `String` stores inner NUL bytes verbatim, so two
  strings of equal length differing only past a NUL compared *equal*.
  Now `memcmp` over the full byte range — which is also 1.3× faster.

- **A 403 from the registry is not an expired token.** `pkg_publish`
  mapped both 401 and 403 to `PubAuth`, so `nurlpkg` answered a refused
  *name* (reserved, typosquat lookalike, or outside the token's scope)
  with "registry tokens expire after 90 days — run `nurlpkg login`",
  sending the user to re-authenticate a perfectly valid token. 401 keeps
  the token-expiry hint; 403 is now `PubForbidden` and names the real
  causes.

- **The `## [0.23.0]` heading in this file.** It was replaced, rather
  than pushed down, by an entry added after that release was tagged, so
  0.23.0's notes had silently become part of `[Unreleased]`. Restored.

## [0.23.0] — 2026-07-24

The **ecosystem** release. v0.22.0 made the registry a training stack;
v0.23.0 closes the loop around it — the missing packages that turn "train
a model" into "train it, save it, serve it, retrieve with it", the
host-memory and mixed-precision work that makes f32 training usable at
scale, browsable API docs on the registry, and the MCP tooling that lets
an LLM *discover, read, and build against every package in the ecosystem*.
The compiler is unchanged from 0.22.0; the one toolchain-level change is
`ext/mcp_search` (below). Everything else ships as registry packages and
the live registry Worker.

### Added

- **`packages/nn` 0.1.0 — neural-network layers on the grad tape.** The
  reusable middle the training stack was missing: `nn_linear` /
  `nn_lora_linear`, `nn_rmsnorm` / `nn_layernorm`, `nn_silu` / `nn_swiglu`,
  NEOX `nn_rope`, grouped-query `nn_gqa_attention`, `nn_cross_entropy` —
  each a pure tape builder, so backward is derived and device replay +
  megakernel fusion come free. Lifted from grad's PyTorch-f64-verified LoRA
  block and gated against the same oracle (loss 3.3e-16, adapter grads
  1e-13); nurllama's finetune now consumes it, byte-for-byte unchanged.
- **`packages/safetensor` 0.3.0 — a writer** (round-trip partner of the
  reader). `stw_add_f32` / `_f64` / `_f16` / `_bf16` / `_i64` +
  `stw_finish` / `stw_write`; the reference `safetensors` Python library
  reads NURL-written files bit-exact across every dtype. Closes the loop:
  train on the tape → save through the package writer → serve through
  nurllama (nurllama's inline emitter folded into it).
- **`packages/data` 0.1.0 — a training DataLoader.** Seeded reproducible
  Fisher-Yates shuffle, epoch reshuffling, drop-last, worker sharding, and
  disk streaming (the `.ndf` format, random-access preads so a corpus
  larger than RAM never loads whole). Determinism is a gate: same seed →
  same batch order; N shards partition exactly once; streamed batches equal
  in-memory batches.
- **`packages/vindex` 0.1.0 — a vector index (the RAG piece).** Exact
  brute-force + IVF-flat (k-means coarse quantiser + inverted lists),
  cosine/L2, `.vix` save/load. Recall@10 vs the exact index is a measured
  gate. Completes embed → vindex → nurllama.
- **`grad` megakernel fusion (0.7.0) + mixed precision (0.8.1).** Fusion
  generates the fused-kernel shape from the captured tape — a row-local
  chain plus the scalar tail become ~5 kernels under one CUDA graph
  (~18× the CPU tape on the AE bench, bit-identical to the per-node
  replay). Mixed precision (`gput_capture_dt(…, 2)`: f32 storage, f64
  accumulation) makes the half-VRAM f32 path numerically usable at scale —
  ~35× closer to the f64 reference than pure f32 at identical memory.
- **`grad` 0.8.0 + `nurllama` 0.12.9 — host-memory training.**
  `tape_drop_consts` frees the tape's const nodes after device capture, and
  nurllama frees + streams the model's base weights (identical loader path,
  so the merge stays byte-exact) — the host-RAM wall that gated building a
  large model's graph is gone. `nurllama finetune --f32 / --mixed`.
- **Registry API documentation** (`registry` 0.4.0 + the deployed Worker).
  Every published release now has a browsable API page — nurldoc over its
  `src/*.nu`, at `/packages/<name>/<version>/api` — plus a symbol index so
  search matches a package by a function whose name you couldn't guess
  (`?q=gqa_attention` → `nn`, with `matched_symbols`).
- **MCP ecosystem discovery** (`nurl-mcp` + `ext/mcp_search`). `nurl_api`
  gains a `package` param — streams a published tarball and renders its API
  surface with the same nurldoc engine. Registry hits now carry the next
  step (`add: nn = "^0.1.1" · API: nurl_api package=nn`) and the matched
  symbols. And **`nurl_build_project`** compiles a program that *uses* a
  registry package: it synthesises a workspace + manifest, resolves the
  deps with `nurlpkg install` (transitive, checksum + signature verified),
  and compiles with the local toolchain — closing the loop from discovery
  to a working binary.

### Changed

- **`ext/mcp_search`** (the one toolchain-level change) gains
  `msearch_api_package` (registry-package API surface) and the actionable
  registry-hit footer. This is why nurl-mcp 0.6.0+ needs this toolchain.

### Fixed

- **Registry symbol search escaping.** The query sanitiser stripped
  underscores (to neutralise the LIKE `_` wildcard), so every underscored
  symbol name was unfindable; it now escapes the LIKE metacharacters
  (`\ % _`) with `ESCAPE '\'` instead of dropping them.

## [0.22.0] — 2026-07-22

The **training** release: the registry's inference-only stack becomes a
training stack. A new reverse-mode autodiff package (`grad`) is the
keystone; `mlp` derives its backprop from it, `nurllama` finetunes real
models with it on the GPU, and `swarm-mcp` runs gradient kernels *emitted
from it* across a cluster — no backward pass in the ecosystem is
hand-written anymore.

### Added

- **`packages/grad` 0.4.0 — reverse-mode automatic differentiation over
  `tensor`** (new package, four releases in one arc). Define-by-run
  tape-recording ops (`g_add`, `g_matmul`, `g_softmax`, …) with one flat
  single-owner arena; `backward(loss)` is a deterministic reverse sweep
  with requires-grad propagation (a frozen-const branch costs no compute
  and no gradient memory). SGD/Adam optimizers with per-parameter L2 and
  global-norm clipping. A **bit-exact GPU replay engine** (`gput_capture`)
  mirrors a recorded episode onto the device — one kernel launch per node
  under the aegpu rounding discipline — so an entire training run lands on
  bit-equal weights on CUDA and the CPU backend alike (~5× the CPU tape on
  an RTX 4090 for the AE benchmark). A **CUDA-C emitter**
  (`gemit_cuda_grad`) prints a scalar tape as `compute_iterate`'s
  `__device__ grad()`; the emitted C is bit-equal to the tape under
  `gcc -ffp-contract=off`, and a live-swarm linear regression landed
  bit-identical to the local tape run. Verified by central finite
  differences, hand-derived bit-exact identities, and a PyTorch float64
  oracle fed raw bit patterns (loss ~1e-16, grads ~1e-13).
- **`nurllama` 0.12.1 — the engine now trains.** `nurllama finetune
  <model.gguf> <data.txt>` learns LoRA adapters on the GPU over the grad
  tape: the whole transformer forward + cross-entropy is one tape graph
  (llama-family NORM rope handled by un-permuting q/k at load; qwen2
  native), the corpus round-robins through fixed windows with two device
  uploads per switch, adapters save as safetensors, and `--merged` writes
  a genuine HF-layout full-model safetensors runnable via `--weights`.
  Proven by a wiring oracle against the inference engine (top-1 identical,
  2e-7 on the top logit) and by the merged model reproducing its training
  text verbatim through greedy decode.
- **`packages/mlp` 0.3.1 — two training engines.** `mlp_fit_grad` runs the
  exact sklearn recipe with gradients from the grad tape instead of
  hand-derived layer deltas; both engines pass the sklearn oracle
  independently and agree to ~14 significant digits.
- **`packages/anomaly` 0.5.1 — GPU autoencoder training, bit-exact.** The
  `/train/autoencoder` path runs on a CUDA device when present at ~34× the
  CPU, with the standing guarantee intact: backend choice can never change
  a result (explicit `__d*_rn` kernels, serial accumulation in the CPU's
  order, host-side transcendentals).
- **`swarm-mcp` 0.21.0** (six releases): `compute_iterate` — GD *and*
  general fixpoints (k-means, EM, power iteration) with the loop in the
  engine, now also **async** (`{"async":true}` returns a task_id;
  `compute_iterate_status` advances the run in bounded time slices, so a
  long training never dies to an HTTP timeout); typed datasets
  (f32/i32/i64); file-backed datasets streamed from disk up to 64 GiB;
  automatic chunk re-dispatch when a worker dies mid-task; shuffle
  cardinality that scales with the cluster (per-chunk tables, overflow
  detected rather than dropped); coordinator crash-restart recovery with
  dataset persistence; `swarm_help` topic help for driving agents.
- **`nurlpkg`: help never acts, `publish --dry-run`, unknown-flag
  rejection, `nurlpkg build`.** `nurlpkg publish --help` used to PUBLISH —
  help is now resolved before dispatch, every subcommand has its own
  `--help`, `--dry-run`/`--dryrun` runs every publish gate and uploads
  nothing (no token needed), a typo'd flag is an error instead of being
  silently ignored, and `nurlpkg build [<dep>]` compiles an installed
  application package in place (arranging the deps link its root-relative
  imports need).

### Fixed

- **`nurl_str_float` now round-trips instead of truncating to 6 significant
  digits.** The runtime formatted every float with `"%g"`, whose default
  precision is 6 significant digits — so any value needing more was silently
  truncated and could not be parsed back. A sum of `41943040` printed as
  `4.1943e+07` (= `41943000`), and `π` printed as `3.14159`. This corrupted
  float output everywhere it mattered: JSON serialization (`json_float`),
  `std/fmt`, `std/log`, `std/bytes`, string building. Now an integer-valued
  double within the exactly-representable range prints as a plain integer
  (`41943040` — readable and exact), and every other value uses the *shortest*
  `%g` form that parses back to the identical double (1–17 significant digits),
  so the text always round-trips. Non-finite values get stable spellings
  (`nan`, `inf`, `-inf`). Only one test golden changed (`cbor`'s `double_pi`,
  now the full `3.141592653589793`).
- **nurlc: a float↔double width mismatch at a store miscompiled to invalid
  IR.** `: f a ( bits_to_f32 b )` — or any f32 value bound/assigned to an
  `f` slot, or the reverse — fell through every branch of the store
  coercion (the never-valid-mix check fires only when exactly one side is
  a float) and emitted `store double %float_val`, which nurlc accepted and
  only clang rejected, with no source location. Float widths now follow
  the integer-width rule in the same helper: `fpext` on widen, `fptrunc`
  on narrow, at lets, `=` reassignment and result-field stores.
- **nurlc: a bare integer supplied for a plain named-struct field in an
  aggregate literal is now a source-located error** (previously invalid
  IR only clang caught). Enum-typed fields and single-pointer-handle
  structs still coerce legally. Also: `: i T 5` now explains that `T`/`F`
  are the boolean literals.
- **mlp: Adam's bias correction was frozen at t = 1** — the step counter
  lived as a scalar field on a by-value struct, so every minibatch after
  the first ran with a permanently inflated effective learning rate.
  Found by the anomaly package's bit-exact GPU parity mirror. Trained
  networks change versus 0.1.x; the sklearn oracle passes with 100 %
  flag agreement.
- **gpu/gpukit: f64 matmul determinism.** gpukit's f64 matmul/bmm kernels
  claimed bit-identity with a sequential host loop, but NVRTC's default
  fmad contraction fused `s+=a*b` — through tensor's silent ≥100k-flop
  GPU fast path, "CPU" results depended on whether a GPU was present. The
  kernels now spell their accumulation with explicit `__d*_rn` intrinsics
  (F32 kernels unchanged: their contract is true-float32, pinned by the
  verified model goldens); the gpu CPU backend gained the intrinsics and
  compiles with `-ffp-contract=off`, so the bit-exactness discipline holds
  on both backends.
- **nurllama: two safetensors-path correctness holes**, both of the
  "runs fine, silently produces nonsense" class. (1) The HF norm-name
  table was gemma3-centric: HF llama/qwen2 call the pre-FFN norm
  `post_attention_layernorm`, gemma3 uses that name for its *extra*
  attention-output norm — so a llama checkpoint's norms loaded as gemma
  norms and enabled a spurious per-layer normalization. (2) A genuine HF
  llama-family checkpoint stores rotary q/k lanes half-split while the
  NORM rope kernel rotates adjacent lanes; llama.cpp permutes at
  GGUF-conversion time, the `--weights` path never did. The loader now
  applies the converter's interleave at load. Every real HF
  llama/SmolLM/TinyLlama checkpoint through `--weights` was affected;
  both paths are pinned by the finetune merge round-trip (12/12 greedy).
- **stdlib/net/relay: a multi-MiB frame spanning several recv windows was
  dropped on a mid-frame timeout**, leaving its unread body in the socket
  and desyncing every following frame — the root cause behind large
  dataset blocks never arriving. A mid-frame timeout with partial data now
  retries (bounded); `net_is_timeout` joined `std/net`.

### Changed

- **Web documentation moved from VitePress to Fumadocs.** The
  `docs.nurl-lang.org` site is now `webdocs/` (Next.js + Fumadocs),
  replacing the old `web-docs/` (VitePress), which has been removed.
  Deploys as a static export (`next build` → `wrangler deploy`), the same
  assets-only Cloudflare Worker pattern the old site used; search runs
  against a build-time Orama index queried client-side instead of a live
  API route. Known limitation: the scaffold's automatic markdown
  content-negotiation for LLM/agent requests (`proxy.ts`) had to be
  dropped, since Next.js middleware isn't supported under static export.
  `/llms.txt`, `/llms-full.txt`, and per-page markdown routes are
  unaffected and still directly fetchable.

## [0.21.0] — 2026-07-19

The **diffusion** release: `nurllama` grows a whole non-autoregressive
decode and serves LLaDA2.x — a 16B-A1B Mixture-of-Experts diffusion
language model that converts from its Hugging Face checkpoint and answers
its own model-card example correctly through the CLI, chat and the ollama
API — on the back of a new streaming GGUF writer that converts a model
larger than RAM at constant memory. The toolchain itself ships four
owned-slice memory-safety fixes across control flow and a new invalid-IR
diagnostic, so auto-drop is now correct through `?`/`??` arms,
reassignments and moves. Plus the ecosystem's first *trainable* package
(`mlp`), an autoencoder anomaly detector, and the distributed compute
layer's data + iterate + failover + shuffle primitives (`swarm-mcp`
0.10 – 0.14).

### Added

- **Diffusion language models — `nurllama` serves LLaDA2.x (`nurllama` 0.9.0).**
  The engine grows a whole non-autoregressive decode: the `llada2`
  architecture (a 16B-A1B Mixture-of-Experts diffusion LM) converts from its
  Hugging Face checkpoint and answers the model card's own example correctly
  through the CLI, chat and the ollama API.
  - **`nurllama convert <hf-dir> <out.gguf> [--type q8_0|f16|bf16|f32]`** turns
    a `llada2_moe` checkpoint (config.json + tokenizer.json + safetensors
    shards) into a GGUF following llama.cpp's `llada2` conventions — fused
    `attn_qkv` left unpermuted, the 256 per-expert tensors fused into one 3D
    `ffn_*_exps` per projection, an F32 router and `exp_probs_b`,
    `tokenizer.ggml.pre = bailingmoe2` — cross-checked key-for-key and
    shape-for-shape against the community LLaDA2.0 GGUF (interop both ways).
    The conversion **streams**: a 30 GB checkpoint converts to a 17 GB Q8_0
    GGUF in ~2½ min at constant memory, on a machine smaller than the model.
  - The `llada2` forward pass: **bidirectional** attention (a new `causal`
    flag in the attention kernels), a Mixture-of-Experts FFN (an fp32 sigmoid
    router with a selection-only bias and group-limited top-k picking 8 of 256
    experts, evaluated as row ranges inside the still-quantised fused tensors,
    plus an always-on shared expert), partial NEOX rotary, and per-head Q/K
    norms.
  - The **block-diffusion decode** (`src/diffuse.nu`): the LLaDA2.1
    "JointThreshold + editing" loop — parallel commits above a confidence
    threshold, revision of already-committed tokens, post-resolution passes,
    EOS early stop — with completed blocks **freezing** their K/V so a step
    costs O(window) where the reference recomputes the whole prefix.
  - The **bailingmoe2** tokenizer pre-split (Ling 2.0 / LLaDA2), proven
    token-for-token equal to Hugging Face `tokenizers` on a multilingual
    battery, and the **Bailing** chat dialect
    (`<role>HUMAN</role>…<|role_end|>`) detected from the model's own template.
- **`gguf` 0.3.0 — a streaming writer and quantisation encoders.** The `gws_*`
  streaming writer declares every metadata key and tensor shape up front, then
  streams payloads to disk in chunks — constant memory, so a model conversion
  larger than RAM just works — and its output is byte-identical to the
  in-memory writer's. New `gq_f16_encode` / `gq_bf16_encode` / `gq_q8_0_encode`
  follow ggml's reference quantisers, verified against the dequant oracle.
  Selftest 40 → 50 checks. (The foundation `nurllama convert` streams through.)
- **`mlp` 0.1.0 — the ecosystem's first *trainable* neural-network package.**
  A seedable, deterministic MLP regressor faithful to sklearn's `MLPRegressor`
  recipe: Glorot-uniform init from `std/rng` (a fixed seed gives a
  bit-identical network on every platform), minibatch Adam with bias
  correction and L2, per-epoch seeded shuffles, and early stopping on a
  held-out split that restores the best weights seen. Everything else in the
  stack (onnx, embed, whisper, nurllama) runs inference; this trains.
- **`anomaly` 0.4.0 — the autoencoder detector.** An explicitly-trained
  reconstruction model over the new `mlp` package: a temporary Isolation
  Forest drops the ring's anomalies first (the AE must learn only normal
  behaviour), the survivors are MinMax-scaled, and an MLP autoencoder learns
  to reconstruct them; the threshold is the p95 of the training
  reconstruction errors. `timevector` also became a real, configurable-size
  sliding window.
- **`swarm-mcp` 0.10.0 – 0.14.0 — the distributed data + compute layer.**
  Content-addressed datasets (BLAKE3-256 1 MiB blocks, verified on arrival)
  so data moves **once** and is referenced by hash instead of re-shipped in
  every payload; `compute_iterate`, which runs a whole gradient-descent loop
  inside the coordinator (a distributed GPU `vecreduce` per round) instead of
  a round per language-model message; relay **failover** (a list of relays,
  workers rotate to the next and re-form when one dies — no single point of
  failure); and `compute_shuffle`, the group-by-key / reduce-by-key primitive,
  whose per-key reduce now runs distributed on the GPU as a MapReduce combiner
  rather than on the coordinator.

### Fixed

- **`nurlc` — owned-slice memory-safety fixes across control flow (four in
  this family).** A `:` binding whose right-hand side is a `?` ternary
  (#541), a `??` match, an `=` reassignment or a bare-identifier move (#543),
  or a `?`/`??` arm whose last statement is an assignment (this release)
  all mishandled owned-slice ownership — the value flowed a slice buffer
  through the join without the auto-drop machinery seeing it, leaking the
  buffer at function exit (and, for reassignment/move, risking a double
  free). Ownership provenance is now tracked through each of these
  constructs (`__last_slice_owned__`, reset at every statement boundary),
  the arm-local fall-through drop fires for void **and plain-scalar** arm
  values (a scalar is copied through the phi, so freeing arm-local buffers
  behind it can never dangle), and pointer/slice/aggregate arms stay
  conservative (leak-not-UAF). LSan-pinned regressions.
- **`nurlc` — a scalar bound into an aggregate target emitted invalid IR.**
  `: ?T x ( vec_set … )` (where `vec_set` returns `b`) compiled to
  `zext i1 … to { i1, %T }` — nurlc accepted it (rc 0) and only clang
  rejected it, with no source location. The i1-widen path now requires an
  integer target, and the mismatch dies with the standard
  no-implicit-conversions message and the binding's source location.
- **`nurllama` — device out-of-memory is now a loud load error.** A failed
  `cuMemAlloc` during weight upload used to be silent: the load
  "succeeded", the affected tensors stayed zero on the device, and the model
  "ran" — emitting token 0 forever. Every device allocation in the loader
  now checks for a null pointer and fails the load naming the cause.
- **`stdlib/net/relay.nu` — a multi-megabyte frame was dropped mid-read on a
  blocking relay client.** `__read_exact` treated a recv **timeout**
  (`SO_RCVTIMEO`, which the relay client sets deliberately) as a connection
  failure, so a frame whose body spanned more than one recv window was
  abandoned — and its unread bytes desynced the stream, turning every
  following frame into garbage. A timeout mid-frame now means "the rest is
  still coming" and is retried (bounded); a timeout with nothing yet read
  still reports "no frame available"; a real close/error still fails.
  New `net_is_timeout` predicate in `stdlib/std/net.nu`.

### Changed

- **CI skips the build + test corpus when only web docs changed** — a docs-only
  PR no longer waits on the full toolchain build.
- **Playground native builds link with `-Wl,--as-needed`** — a binary a user
  downloads from the playground runs without the container's libraries.


## [0.20.0] — 2026-07-18

The **one kernel library** release: the ML stack's device layer is
unified — gpukit's dev layer becomes the single dtype-generic kernel
library that tensor, onnx and the new embedding server all run on
(onnx's private kernel file is deleted outright, byte-identical outputs
proving the move) — plus a Unigram tokenizer engine, a pure-NURL
embedding server that is drop-in for a FastAPI/sentence-transformers
service, three stdlib performance root-causes found by profiling real
250 k-piece vocabularies, and the documentation site going live at
docs.nurl-lang.org.

### Added

- **`utf8_decode_n`** (`stdlib/std/utf8.nu`) — `utf8_decode` with the
  byte length supplied by the caller. The old shape re-ran `strlen` for
  every byte access (up to five per character), which made every UTF-8
  scan quadratic in the string length; `utf8_decode` now runs strlen
  once and delegates, the module's own scan loops use the `_n` form,
  and `nurl_str_get`'s O(strlen)-per-call cost is documented at its
  definition with the pointer-read idiom to use in loops.
- **gpukit 0.4.0** — the dev layer grows the full operator family a
  CNN / transformer forward pass needs, lifted math-exact from onnx's
  proven f32 kernels and generalised over the element type: `GK_I64`
  buffers with exact `Vec i` host views, N-D stride-broadcast
  elementwise (numpy broadcasting as a stride table, with a host-side
  proof the strides stay in bounds), batched matmul with per-operand
  batch broadcast, gather/scatter with ONNX index semantics, gemm
  (alpha/beta/transB/bias), conv2d / convtranspose2d / maxpool2d,
  batchnorm, layernorm, softmax over an interior axis, erf, clip,
  leakyrelu, axis concat/slice, N-D transpose, nearest resize, expand,
  L2 reduction, argmax, CLIP EOS read-out. Every wrapper validates
  buffers/dtypes/sizes and fails closed. `gk_autosync`/`gk_sync` let an
  executor chain hundreds of launches with one device sync at the end.
  57 numpy-checked tests on CUDA **and** the CPU backend.
- **tensor 0.4.0 (M5)** — DTensor reaches full ndarray coverage: numpy
  broadcasting on the elementwise ops (one stride-broadcast launch, no
  materialised expansion), `dtensor_bmm` with numpy batch broadcast,
  `dtensor_gather`/`dtensor_scatter` (host indices validated before the
  device is touched), `dtensor_conv2d`/`dtensor_maxpool2d`. One
  broadcast implementation shared between host and device tensors.
  33 device checks vs numpy; f64 results bit-identical CUDA ↔ CPU.
- **tokenizer 0.3.0** — a third engine: Hugging Face `tokenizer.json`
  **Unigram** models (XLM-RoBERTa / BGE / multilingual-e5). The
  sentencepiece Precompiled charsmap normalizer (a darts-clone
  double-array trie decoded straight from the file), Metaspace with
  HF's exact prepend rule, true Viterbi segmentation over piece
  log-probabilities with fused unknowns, added tokens with
  lstrip/rstrip semantics, TemplateProcessing specials —
  token-for-token identical to HF `tokenizers` on a 27-line
  multilingual corpus (committed golden).
- **embed 0.1.0** — the embedding server, pure NURL. Loads an
  XLM-RoBERTa-family model directory (config.json + tokenizer.json +
  f32 model.safetensors) and serves embeddings over HTTP, drop-in
  compatible with the reference FastAPI/sentence-transformers service
  (`POST/GET /create_embedding`, `/health`, Bearer auth with a
  constant-time compare, JSON errors, hardened single-worker serving).
  The forward pass is wired entirely from gpukit's `gkd_*` kernels —
  the package ships no kernel sources. Verified at cosine 1.0000000
  against sentence-transformers per row, cosine 1.00000000 against the
  reference service container over HTTP, CPU ↔ CUDA cosine 1.0.
- **Documentation site** — a VitePress site under `web-docs/`, deployed
  to **docs.nurl-lang.org** by the "Publish Webdocs" workflow
  (assets-only Cloudflare Worker; deploys on pushes touching
  `web-docs/`).

### Changed

- **onnx 0.7.0 (M4b)** — `src/ops.nu` (24 private f32 kernels + an
  eagerly-compiled kernel struct) is **deleted**; the executor
  dispatches every node to gpukit's shared kernel library, compiles
  lazily through gpukit's in-process + on-disk caches, and chains the
  whole graph walk with a single device sync. Migration was gated on
  byte-identical model outputs at every step (yoloe det+seg, tinyyolov2,
  CLIP text encoder, promptable two-input) on both backends; wall-clock
  unchanged. The gkd validation layer also exposed a latent bug: the
  CLIP text-encoder export hardcodes `[1,77,-1]` reshapes, so token
  batches > 1 made the old executor read 3× past the out-proj weight —
  the new path fails closed with a diagnostic.
- **`hash_string`** (`stdlib/std/hashmap.nu`) — djb2 → FNV-1a with a
  murmur-style avalanche finisher. The map masks the hash with a power
  of two, so only the low bits pick a slot — and djb2's low bits carry
  so little of a real key that 250 002 multilingual tokenizer pieces
  probed ~7× slower on insert (and ~20× on miss-heavy lookups) than
  synthetic benchmark keys. Net effect with the utf8/base64 fixes:
  loading that vocabulary went 3.4 s → 0.24 s and a 7 000-token encode
  2.4 s → 0.13 s.

### Fixed

- **`b64_decode` was quadratic** — it read every input byte through
  `nurl_str_get`, which re-runs `strlen` per call; a 300 KB
  precompiled-charsmap blob took 2.1 s to decode. The loop reads
  through a raw pointer now: linear.
- **Windows golden corpus unstuck** — the `outputs-windows/` goldens
  had not followed the `__`→`_` rename wave (http_extras, http_proxy),
  the nurldoc multi-line-struct addition, or the `hash_string` change
  (hashmap_iter's arbitrary-order peek), leaving `windows-tests` red
  since before 0.19.0. Refreshed; only genuine platform differences
  remain.

## [0.19.0] — 2026-07-17

The **reachability** release: search that survives contact with a real
language-model caller (ranked boundaries, zero-hit widening, exact-name
footers, honest package descriptions), build artifacts addressed by
absolute URLs, one shared search engine for the playground and the local
nurl-mcp — and playground deploys that reach the live container
deterministically instead of waiting for an idle window.

### Added

- **`stdlib/ext/mcp_search.nu`** — the MCP search surface (module API
  view via nurldoc, declaration query with registry widening and
  exact-name footers, boundary-ranked grep, registry name+description
  search) extracted from nurlapi into a stdlib module with explicit
  path/registry parameters, so the playground API and the local
  `nurl-mcp` package share ONE implementation.
- **`nurl-mcp` 0.5.0** gains `nurl_api` and `nurl_grep` over the
  installed stdlib + the package registry — the declaration view and
  package discovery for local, MCP-only editors. (Publish requires the
  toolchain release that carries `ext/mcp_search.nu`.)

- Playground build endpoints return ABSOLUTE `download_url`s (native,
  windows, macos, cross-target and wasm — wasm keeps its base64 payload
  too): the base comes from `NURL_PUBLIC_URL` (or the already-deployed
  `NURL_API_URL`), so an MCP caller on another machine no longer has to
  guess which host a bare `/download/…` path belongs to. Unset env keeps
  the old relative form for same-host use.

- MCP `nurl_api` notes an exact package-name hit in one footer line
  regardless of stdlib match count — `query='http'` returns hundreds of
  declarations AND "Note: the registry has a package named 'http' — the
  unified HTTP server interface…", so the package's existence never
  drowns.
- Registry: a package whose manifest omits `description` gets the
  README's first paragraph as its searchable pitch (both the Worker and
  `packages/registry`), instead of an empty search row.

### Fixed

- `http` 0.3.1: the manifest description had a 0.3.0 release note
  prepended before the actual pitch — and the registry's 500-byte cap
  kept the note and dropped the pitch. The description is now the stable
  value proposition ("the unified HTTP server interface … anything that
  needs to SERVE HTTP"), which also lets a model correctly reject it
  for client-fetch tasks.

- MCP `nurl_api` widens a zero-hit query automatically: when no stdlib
  declaration matches, the same AND-terms are matched against example
  programs (file granularity, with each file's header blurb) and the
  package registry (per-term name/description search, de-duplicated) —
  in the same reply, so "is there anything about X" never needs a second
  call.

- MCP `nurl_grep` ranks word-boundary matches first, by default and with
  no flags: lines where the pattern's neighbors are not letters (digits,
  underscore, punctuation and line edges all count as boundaries — `mcp`
  is clean in `mcp_call`, `/mcp` and `mcp2`, not in `memcpy` or `-mcpu`)
  come first, and in-word substring hits follow under a clearly-labeled
  tail with its own small byte budget. Plain-grep substring semantics
  are preserved — nothing matching is hidden, only ordered. `word=true`
  drops the in-word tail entirely (the filtered count is still
  reported).

## [0.17.0] — 2026-07-17

The **findability** release: the MCP server answers "what's in this
module", "when did this change" and "does a package for X exist" in
kilobytes instead of context-flooding dumps — and the registry learns
what its packages are about.

### Added

- **MCP: `nurl_api` — a stdlib module's API surface, or a search across
  all of them.** `module='ext/csv.nu'` returns signatures, doc comments
  and full type definitions with no function bodies (11 KB where the
  source is 63 KB); `query='csv quote'` returns just the declarations
  whose signature/doc/module-path contain every term. Backed by nurldoc,
  which now omits `__`-private (file-scoped, uncallable) functions and
  renders a multi-line type declaration's full field list in a fenced
  code block — the /stdlib-docs pages get both fixes too.
- **MCP: `nurl_grep`** — case-insensitive substring search across stdlib
  sources, examples and compiler tests (`path:line: text`, per-file and
  total caps), plus the package registry by name AND description — "does
  a package for X exist" is one cheap call.
- **Registry: package descriptions are stored, served and searchable.**
  `[package].description` is extracted server-side from the published
  tarball on every publish (latest wins; never a client header), shown
  in the catalog, returned by `/api/v1/search`, and matched by it — in
  both the Cloudflare Worker (D1 migration 0003 +
  `/api/v1/admin/desc-backfill` for pre-existing packages) and
  `packages/registry` 0.3.0. `nurlpkg search` prints them.

### Changed

- **MCP: `nurl_changelog` results are ranked, and every match stays
  visible.** Entries whose TITLE carries the search terms outrank
  passing mentions; the top `limit` matches return in full and every
  further match appears as a one-line provenance+title (previously the
  newest N matches consumed the byte cap and the rest were an opaque
  "77 omitted" count). `compact=true` gives a titles-only overview.

## [0.16.0] — 2026-07-16

The **provenance** release: the registry shows what a package contains and
when every version shipped, nurlpkg learns to move requirements forward
instead of making you hand-edit manifests, and one bad token inside a
match arm no longer buries the real diagnostic under phantom errors.

### Added

- **`nurlpkg update` — move dependency requirements to the newest
  versions.** Walks `[dependencies]` and offers each requirement the
  newest available version: registry deps follow the newest non-yanked
  published version, path deps the version in the dep's own local
  `nurl.toml` (that is the code you build against, and the publish gate
  requires the requirement to cover it — the registry may not carry that
  version yet). Each change is confirmed on stdin (`y/N`, default No —
  and piped/EOF stdin never mutates); `--all` (aliases `-y`/`--yes`)
  accepts everything, `nurlpkg update <name>…` limits the walk. A
  requirement the newest version already satisfies is left untouched,
  and edits are surgical: only the version value on the dep's line
  changes, so `path =` keys, formatting and comments survive.
- **Registry package pages show publish dates and a per-version file
  listing.** Each version row on `/packages/<name>` carries its publish
  date — read from the authoritative server-side `published_at` recorded
  at publish since the registry's first day, never from client-controlled
  tar/gzip timestamps — and links to a new
  `/packages/<name>/<version>/files` page listing every file in the
  published tarball with its size (USTAR-prefix and GNU-longname paths
  reconstructed; immutable-cacheable, since versions are immutable). In
  both registries: the live Cloudflare Worker and `packages/registry`
  0.2.0.

### Fixed

- **A diagnostic inside a `?`/`??` arm no longer poisons the rest of a
  multi-error compile.** `die`'s recovery panic unwinds out of the open
  function/arm symbol-table scopes; the per-declaration recovery frame now
  pops those leaked scopes before continuing. Previously gen_match's
  synthetic `__matchtmp<n>__res_nurl_T` payload keys survived, and — the
  label counter that numbers them resetting per function — a later
  same-numbered option match typed its payload with the dead declaration's
  struct, drowning the one real error under phantom cross-file type errors
  in modules compiled much later (`diag_match_arm_recover` pins the fix).
- **`: i pub …` explains itself.** Naming a let binding `pub` now says the
  word is a reserved keyword (the visibility prefix on top-level
  declarations) instead of the bare "expected variable name in let".
- nurlpkg `add`/`remove` leaked one trimmed String per manifest line
  walked (the shared dep-line matchers returned through early exits),
  plus the initial empty buffer when reading `nurl.toml`. All
  line-machinery commands (`add`, `remove`, `update`) are now
  LeakSanitizer-clean.

## [0.15.0] — 2026-07-14

The **joins and guards** release: one new language behaviour, three classes
of silent failure turned into diagnostics that explain themselves, and a
release pipeline that tells the truth about its own version.

### Added

- **Integer arms of different widths unify losslessly at `?`/`??` joins.**
  `?? m { T x → x F → 0 }` over a `( Vec u )` — "the byte, or zero" — used
  to be impossible: the `u` arm and the `i` literal could not share a phi.
  Every integer arm now carries a 64-bit shadow extended by its OWN
  signedness (zext for unsigned and bool, sext for signed), so `u` 200
  arrives as 200 — never −56 — and `i` −1 arrives as −1: the same number in
  a wider register, not a conversion. Same-width arms emit bit-for-bit the
  IR they always did. This is the join catching up with the stores and call
  sites, which have always bridged integer widths; the join refusing to was
  the language disagreeing with itself. Float↔int and pointer↔int stay
  errors — those WOULD change values, and NURL converts nothing implicitly.
- **Duplicate definitions die in the front end, with both locations.** A
  NURL compilation unit is one flat namespace — `__` is a convention, not a
  scope — and a second `@ fn` / `: Type { … }` / `: ~ global` from another
  file used to die inside LLVM ("invalid redefinition"), location-free in a
  50k-line generated .ll, or worse: two generic functions sharing a name
  silently replaced each other's SOURCE, and two files sharing one mutable
  global by accident is the bug found a week later. All three now report
  `duplicate <kind> '<name>' — already defined at <file>:<line>`. A file
  imported by several importers stays legal (same-position re-registration
  is idempotent), and a generic beside a non-generic of the same name stays
  legal — the corpus relies on it.
- **A valueless expression is an error, not a pointer.** When `?`/`??` arms
  are genuinely incompatible (float beside int), the construct degrades to
  a statement and produces no value — and a cast or binding consuming it
  used to receive `undef`: the program printed whatever was in the register.
  Found live: a WebSocket PCM16 decoder decoded every audio sample to
  pointer garbage and the failure surfaced three layers away as a timeout.
  The degrade site now RECORDS why (the two arm types), and the consumer's
  error carries the reason and the fix.

### Fixed

- **Released binaries no longer report `-dirty`.** Three test goldens were
  committed with CRLF in the blob while `.gitattributes` demands LF, so
  every fresh CI clone was "modified" before the build began, and
  `git describe --dirty` stamped every release accordingly. The blobs are
  renormalised, and the posix test runner now honours the \r-normalisation
  contract the attributes always claimed (previously only the Windows
  runner did).

### Ecosystem

- **whisper 0.6.0 / audio 0.6.0 on the registry**: `whisper serve` holds
  the model open (0.33 s per warm request where the CLI pays 1.15 s per
  invocation, distil-large-v3) behind whisper.cpp's own HTTP surface — and
  the SAME port speaks WebSocket: stream raw PCM16, get utterances back as
  `{"text","t0","t1"}` on the stream's clock, segmented by an
  adaptive-floor streaming VAD whose noise floor is the 10th percentile of
  the trailing minute. One port and a floor that tunes itself, where the
  whisper.cpp fork needs two ports, a fixed dB threshold and a pile of
  auto-settings heuristics.

## [0.14.1] — 2026-07-13

A patch for the speech release's own hot path: the FFT that computes every
whisper spectrogram frame.

### Changed

- **`stdlib/std/fft.nu` — "not a power of two" is not one case.** 0.14.0
  sent every such length through Bluestein; but `400 = 2^4·5^2` is
  perfectly factorable, and Bluestein pays for TWO radix-2 transforms of
  length 1024 to produce one transform of length 400 — the fallback for
  hard lengths, applied to an easy one, 3000 times per 30 seconds of
  audio. Three paths now, picked by what N actually is: powers of two
  keep the radix-2 core, **smooth lengths (factors 2/3/5/7) get a direct
  mixed-radix Cooley-Tukey** with per-level twiddle tables built once in
  the plan, and Bluestein does only the job it is for — lengths with a
  large prime factor, where a "radix" would degenerate toward the O(n²)
  DFT it exists to avoid (997 stays on it, and stays exact).
- **`fft_rfft` folds a real signal of even length in half**: 400 real
  samples become a 200-point complex transform (`z[t] = x[2t] +
  i·x[2t+1]`) plus an O(n) untangle — the even samples' spectrum is
  conjugate-symmetric where the odd ones' is anti-symmetric, so they
  separate. Half the transform is half the work, whichever path the
  half-length takes.
- Together: whisper's 30-second mel spectrogram **0.52 s → 0.14 s**
  (the STFT itself 288 → 99 ms). With the packages already on the
  registry riding this stdlib, distil-large-v3 transcribes a 292-second
  recording in 3.9 s — 1.3 s with `--vad`.

### Fixed

- The FFT identity suite now pins **every radix the factoriser can hand
  out** (3, 5, 7, alone and mixed: 105 = 3·5·7, 343 = 7³) with δ[1]
  cases — the check that catches a conjugated combine step, which
  round-trips perfectly while transforming wrongly. Forward transforms of
  pseudo-random signals at N = 400, 360, 105, 343 were verified against
  `numpy.fft` directly.

## [0.14.0] — 2026-07-13

The **speech** release: NURL now transcribes real audio with real models,
and the ecosystem grew the four packages that took it there.

### Added

- **`stdlib/std/fft.nu`** — the discrete Fourier transform, for **any**
  length. A radix-2 FFT covers powers of two; whisper's spectrogram wants
  `n_fft = 400`, which is not one, and padding to 512 computes a
  *different* transform rather than a rounder one. So arbitrary N is
  handled properly, by **Bluestein's algorithm**: relative error 1.9e-14
  at N=400 and 7.3e-15 at the prime 997, against numpy — the
  arbitrary-length path is as accurate as the easy one. A plan
  precomputes the twiddles and the transformed chirp, so an STFT does not
  pay the setup per frame: whisper's whole 30-second mel spectrogram
  (3000 frames) takes 0.30 s.
  - The test suite pins the transform with **identities**, because its
    round trip passed while the forward transform was wrong: the inverse
    was wrong in the compensating way. `δ[1] → e^(−2πik/N)` pins the sign;
    `ifft(fft(x)) == x` pins nothing on its own.

- **`nurlpkg publish` refuses a package the installed toolchain cannot
  build.** A package's `$ \`stdlib/…\`` imports are resolved by whatever
  toolchain the USER has — so a package importing a stdlib file added
  since the last release publishes cleanly and then fails to install for
  everyone. It happened (packages/audio against this release's
  `stdlib/std/fft.nu`), and the gate now names the missing files and the
  toolchain that lacks them.

### Ecosystem (published to the registry)

- **`safetensor` 0.1.0** — the container Hugging Face ships every model
  in, parsed as hostile input: the header length is checked against the
  real file size before the JSON is looked at, every tensor's extent must
  land inside the data region and be exactly what its dtype and shape
  need, and element counts accumulate with an overflow check. Proven by a
  whole forward pass: gemma-3-270m from its checkpoint reproduces HF's
  own logits at **r = 1.00000000**.
- **`tokenizer` 0.1.0** — nurllama's SentencePiece and byte-level BPE
  engines, lifted out and made loader-agnostic: a vocabulary can arrive
  from a GGUF's metadata or from HF's `tokenizer.json`. The HF oracle
  found a **years-old bug**: GPT-2's `\s+(?!\S)` gives the last space of
  a run *back* to the next token, and the default pre-tokenizer was
  swallowing it.
- **`audio` 0.1.0** — WAV (untrusted input), windowed-sinc resampling
  (linear interpolation aliases the speech band), and whisper's log-mel
  to the constant — matching HF's `WhisperFeatureExtractor` at
  **r = 1.00000000** on both 80 and 128 bands.
- **`whisper` 0.1.0** — speech recognition in pure NURL, from a
  safetensors checkpoint, on the GPU or the CPU. **Word for word what HF
  transformers produces**, on whisper-tiny *and* distil-large-v3.
  LayerNorm rather than RMSNorm, error-function GELU rather than tanh,
  two conv1d layers, cross-attention, and the ecosystem's first
  **non-causal** attention — a speech encoder hears the whole clip at
  once.
- **`nurllama` 0.8.0** — the tokenizer engine now comes from the package;
  its loader is the 128 lines that read `tokenizer.ggml.*`. Weights can
  also come from a safetensors file (`--weights`), which is how the
  safetensor reader is proven.

### Fixed

- **A quadratic vocabulary load.** `whisper transcribe` cost 14.2 s on an
  11-second clip — and the same 13.7 s whether it generated 1 token or
  20. A flat cost is never the model: `tokenizer.json` was being read with
  `json_obj_get` per key, which scans linearly, so a 50 258-entry
  vocabulary was 2.5 billion string comparisons. 12.88 s → **0.05 s**.


## [0.13.0] — 2026-07-12

The **local-LLM release**. NURL now runs language models end to end — a
hostile-input GGUF parser, a tokenizer read from the model's own
metadata, a llama forward pass on GPU kernels that also run on the CPU,
a content-addressed model store with resumable downloads, and an
ollama-compatible API — all in pure NURL, all verified against
independent references. The compiler, the stdlib and three packages
each grew what that work proved they were missing.

### Added

- **`stdlib/std/progress.nu`** (new module) — a throttled, width-fitted
  transfer bar on stderr that stays **completely silent when stderr is
  not a tty**, so CI logs never fill with carriage returns.
  `progress_human` is a pure, unit-testable byte formatter.
- **`stdlib/std/fs.nu`: handle-based writes and seeking** —
  `file_create` / `file_append` / `file_write_chunk` (binary-safe; a
  short write is an error, never silent truncation) / `file_flush`,
  plus `file_seek` / `file_tell` / `file_read_at` with
  `FS_SEEK_SET/CUR/END`. An output far larger than RAM can now be
  emitted, and a broken transfer resumed.
- **Incremental hashing** — `sha256_init/update/final` and
  `blake3_init/update/final`. BLAKE3 grows the real chunk tree as bytes
  arrive (a buffered chunk is only compressed once a later byte proves
  it non-final), so any update pattern reproduces the one-shot's tree.
  **Both one-shots are rebuilt as init/update/final compositions**, so
  the streaming and whole-buffer paths cannot drift.
- **`stdlib/std/floatbits.nu`: f16 / bf16 ↔ f32**, both directions —
  widening is exact (subnormals, ±inf, NaN payloads, −0), narrowing
  rounds to nearest-even. Proven by an **exhaustive 65 536-pattern
  round-trip identity** for both formats.
- **`stdlib/std/term.nu`: `term_width` / `term_height`** — TIOCGWINSZ
  (new `nurl_native_constant` entry) with a `$COLUMNS`/`$LINES` → 80×24
  fallback.
- **HTTP streaming-response hook** — `server_set_stream`, exposed on the
  `http` package facade as `http_app_stream`: the write-side sibling of
  the WebSocket upgrade hook, for chunked / SSE / NDJSON bodies. The
  chunked writers existed at the low level, but `HttpApp`'s
  request→`HttpResponse` handler type had no seam for a token-by-token
  body.

### Fixed

- **Arm-local owned slices are dropped at fall-through** (memory-model
  rule 5). A slice literal `:`-bound inside a `?` / `??` / `~` / foreach
  arm leaked: `__owned_slices__` is name-keyed and scope-shadowed, so
  the arm's delta died unseen at `nurl_sym_pop`. Phase 2D now has a
  slice counterpart driven by a `__slice_decls__` sideband (only
  bindings *declared* in the arm — freeing an `= outer [ … ]` target
  would be a use-after-free), and the same family's rule-3 gap is closed:
  `= xs [ … ]` now frees the old backing buffer.
- **The sanitized CI job no longer runs at the memory ceiling.** The
  bootstrap snapshot predated the 0.12.0 self-compile work, so stage 1
  still ran the 13.6 GB-era compiler under ASan — right against the
  16 GB runner, where it died as a silent `Terminated`. Refreshing
  `nurlc_lastgood` takes the sanitized build's peak from **17.2 GB to
  0.47 GB**; the build-stage `ASAN_OPTIONS` were tuned as well.

### Packages

- **`gguf` 0.2.0** (new) — read, verify, write and dequantise the GGUF
  container. mmap-lazy and hostile-input-safe: every count, length and
  offset is validated against the real file size *before* anything is
  allocated. Dequantisation covers F32/F64/F16/BF16, Q4_0/Q4_1/Q5_0/Q5_1/
  Q8_0 and the K-quants **Q4_K/Q5_K/Q6_K** — verified **bit-identical**
  against an independent Python decoder on real llama.cpp models — and
  `gguf_dequant_range` reads one row of a multi-gigabyte tensor without
  expanding it.
- **`nurllama` 0.1.0** (new) — run language models locally:
  `pull` (resumable, content-addressed store) · `run` · `chat` ·
  `serve` (ollama-compatible NDJSON API). Weights stay **quantised on
  the device** — the matvec kernels decode GGUF blocks inside the matmul
  (a Q4_K_M model needs ~3× less device memory than its f32 expansion) —
  and the same kernel sources run on the CPU backend byte-identically.
  Token IDs are checked against an independent SentencePiece
  implementation, logits and greedy text against an independent numpy
  forward pass.
- **`gpu` 0.5.0** — **compiled kernels are cached on disk**, keyed by the
  BLAKE3 hash of the source, so a process start costs a file read
  instead of an NVRTC / C++ compile (a dozen-kernel package starts ~3×
  faster; `NURL_GPU_CACHE=off` disables it). Two CPU-backend bugs that
  banned `__device__` helper functions are fixed: `__device__` is an
  execution-space qualifier, not a storage class, and the parameter
  scanner now finds the entry kernel by name instead of taking the
  source's first parenthesised list.

## [0.12.0] — 2026-07-11

The release that finishes the clean-room self-critique started in 0.11.3.
It closes the compiler's existential scaling wall (**self-compile 13.6 GB
→ 366 MB**), the ecosystem's account-takeover surface (**registry token
expiry + scoped tokens + typosquat guard**), the playground's abuse
surface (**non-root, timeouts, rate limits**), a real `--debug` compiler
crash, and a documentation-accuracy sweep that made every user-facing
claim verifiable — plus the two remaining structural critique items (the
fused-compiler map, the safe-code safety-hole statement) and a first real
Windows CI corpus.

### Changed

- **Self-compiling the compiler takes 366 MB instead of 13.6 GB** (and
  3.0 s instead of 10.1 s). Instrumented per-site allocation counters
  attributed 11.9 GB of the peak to one function — the borrow checker's
  per-binding state lookup, which re-sliced the remainder of its state
  string per token (O(n²) bytes, 14.8 M calls per self-compile). The
  state-map operations now walk by index and build their output in one
  exact-size buffer; the state format and every diagnostic are unchanged
  (old and new compiler emit byte-identical IR). CI gates the number with
  `tools/memgate.sh` (600 MB budget) so it cannot silently regress.
- **`std/random.nu` draws fail closed.** `rand_u64` / `rand_hex_str` now
  check `nurl_rand_fill`'s return and panic when every OS entropy source
  failed (the runtime would otherwise degrade to a non-cryptographic LCG)
  — the same contract the tls/rsa/x509 draws already enforced.
- **Documentation accuracy sweep.** Every user-facing doc was verified
  against the source, workflows, installers, and release assets: a
  platform-support **tier model** replaces contradictory "fully supported"
  claims (tiers defined by what CI actually verifies), `docs/ASYNC.md` was
  rewritten from a stale design plan to the shipped runtime, and roughly
  95 stale references, wrong numbers, and marketing/past-version notes
  were corrected across the tree.

### Added

- **Registry account hardening (M9).** Tokens expire after 90 days;
  `POST /api/v1/token/new` mints per-package **scoped CI tokens**; new
  package names pass **reserved-name** and **typosquat** checks
  (normalised lookalikes and edit-distance ≤ 1 of someone else's package
  are rejected); publish / token-mint / search are **rate-limited**.
- **Playground hardening (M11).** The `nurlapi` container runs as a
  non-root user; every build-tool invocation runs under `timeout(1)`;
  build routes are rate-limited per client IP with an explicit body cap;
  the build-output directory is TTL-swept and count-capped.
- **`nurlpkg install <library>` works in a plain folder — no `nurl.toml`
  required.** A library package (no `src/main.nu`) now lands under
  `./deps/<name>` with its transitive registry deps, instead of erroring;
  when a `nurl.toml` is present the dependency is recorded there too.
  Program packages still build + install onto `$PATH` unchanged.
- **`--strict-borrowck` closes the conditional double-free hole.** A value
  freed on one arm of a `?` and freed again unconditionally — a real
  double-free on the path where the first free ran — is now an error under
  the strict checker (its third opt-in check). The default checker still
  deliberately allows it to keep the no-false-positive property;
  `docs/MEMORY.md` §2.9/§6.5 state the trade both ways.
- **`std/net.nu` gains `tcp_connect`** — the plain-TCP client connect,
  returning `!TcpConn NetErr` like its TLS siblings. The MQTT module's
  private duplicate (which returned `MqttErr`) is gone.
- **`docs/dev/COMPILER_INTERNALS.md`** — the map of the fused walk:
  pipeline order, every process-global table with its writers (appendix
  generated from source by `tools/gen_globals_map.py`), the invariants
  that bite, and the safe-change checklist.
- `docs/MEMORY.md` §6.5 now states every way safe-looking code can still
  fail, together, with the accurate one-line safety claim to quote instead
  of "memory-safe like Rust".

### Fixed

- **`nurl.sh --debug` no longer crashes clang at `-O2`.** A larger
  multi-file program built with debug info crashed clang in
  `DwarfDebug::finalizeModuleInfo`: three kinds of inlinable call (the
  indirect closure call, the `__jdrop_*` thunk's drop call, and the C-ABI
  `main` wrapper's call) were emitted without a `!dbg` location, so the
  optimizer reparented a debug-info callee into the wrong subprogram. All
  synthetic functions now carry a subprogram and their inlinable calls
  carry `!dbg`; non-debug IR is byte-identical.
- **`url_parse` rejects out-of-range ports** instead of wrapping — a port
  past 65535 silently wrapped into a plausible small number and parsed as
  a valid URL pointing at the wrong port.
- Registry signing keyid is configurable (`REG_SIGN_KEYID`) — signing with
  a non-default key (self-hosted registry, local tests) used to embed the
  production keyid and produce signatures every client rejects.

### CI

- **The Windows golden corpus now runs on a real `windows-latest` runner**
  (the `windows-tests` workflow), on every push to `main` — the 447
  Windows goldens were previously exercised only locally. `build.bat` now
  exits non-zero when it skips the test suite (a missing PowerShell 7 used
  to print success), so an untested build can't masquerade as a tested one.
- **DWARF debug-info gate** — the plain corpus never builds with
  `--debug`, so `tools/dwarf_test.sh` (the `-O2` closure/Drop regression
  plus gdb source-level checks) is now wired into CI.

## [0.11.3] — 2026-07-10

A **hardening & supply-chain** release. A clean-room self-critique of the whole
project — compiler, language, libraries, toolchain, ecosystem — was turned into
fixes, one focused change at a time. The headline is **end-to-end package
signing**: the registry now signs every published tarball with a project
Ed25519 key and `nurlpkg` verifies the detached signature with a *pure-NURL*
minisign implementation before unpacking, so a compromised CDN can no longer
substitute bytes. Around it: fail-closed installers, integer/type safety fixes
in the compiler, a diagnostics overhaul (multi-error reporting, "did you mean",
unified borrow-checker rendering), a resolver correctness fix, and new CI safety
gates (leak surface, symbol collisions, a second fuzzer).

### Security

- **End-to-end package signing — mandatory and fail-closed.** The registry
  signs every published tarball with a project Ed25519 key (minisign legacy
  `Ed` format — a raw signature over the `.tar.gz` bytes); `nurlpkg` pins the
  matching public key and verifies the detached `.minisig` before unpacking. No
  signature, no install (`PkgBadSig`). The SHA-256 checksum still runs first,
  but it defended integrity given an authentic index — it no longer stands
  alone. A `$NURL_REGISTRY_PUBKEY` trust-anchor override supports self-hosted
  registries. New stdlib primitives make this possible without any C
  dependency: **pure-NURL BLAKE2b-512** (RFC 7693, `std/hash_blake2b`) and a
  **pure-NURL minisign verifier** (`std/minisign`) on the existing Ed25519. The
  registry gained an idempotent backfill so packages published before signing
  existed are signed without stranding older clients.
- **Toolchain archives are signed.** `release.yml` signs each release archive
  with minisign, and `install.sh` / `install.ps1` verify the detached signature
  against a pinned key. This layer is opportunistic — the toolchain can't assume
  minisign is present at first-run, so HTTPS + a fail-closed checksum stay the
  root of trust there; the pure-NURL verifier covers the package layer, where
  `nurl` is already installed.
- **`curl | sh` installer no longer fails open.** Both installers verify
  **fail-closed**: a missing, empty, or malformed checksum — or any mismatch —
  aborts; `--insecure` / `NURL_INSTALL_INSECURE=1` is the explicit opt-out. The
  `rm -rf "$PREFIX"` step is guarded so it refuses `$HOME` / `/` / `%USERPROFILE%`
  and any non-empty directory that isn't a prior NURL install.
- **Integer division / remainder by zero now panics** with a clear message
  instead of executing undefined behaviour (previously a raw `sdiv` / `srem`).
- **Recursion-depth caps in the XML and YAML-flow parsers** — deeply nested
  hostile input can no longer exhaust the stack.

### Added

- **Compiler diagnostics overhaul (`nurlc`).** Reports **multiple errors per
  run** instead of aborting on the first; prints **"did you mean …?"**
  suggestions for unknown functions and identifiers; routes internal invariant
  violations through a labelled **internal-compiler-error** path instead of a
  bare crash; renders borrow-checker diagnostics through the same source-caret
  renderer as front-end errors; and adds `--help` / `-h`.
- **Leaf-site error-handling combinators** in the stdlib — `expect`, `unwrap`,
  `unwrap_or`, `or_else`, and Option↔Result bridges for terminal error handling.
- **A mutational parser fuzzer** (`tools/fuzz`) over the DER/X.509 and
  format parsers, plus a weekly CI workflow running it alongside the existing
  differential fuzzer.

### Changed

- **Resolver intersects all version requirements per package**, rather than
  taking the first requirement seen — a dependency constrained as both `^0.2`
  and `^0.2.3` now resolves against the intersection.
- **`nurlc` rejects pointer↔scalar call-argument mismatches** — passing a `*T`
  where a value `T` is expected (or vice versa) is now a call-site error.
- **bind / assign type-mismatch diagnostics point at the offending statement**,
  not the line after it.
- Removed stray `DEBUG:` prints from `nurlc`.
- Docs: corrected inaccurate claims and broken commands across the README and
  guides, and documented the pre-commit `nurlfmt` hook accurately.
- Packages `anomaly` 0.3.7 and `yoloe-demo` 0.2.3 depend on `http ^0.2` (the
  `^0.1` caret-lock never picked up the 0.2.0 leak fixes).

### Fixed

- **Loop-carried `% Drop` leak** — a value with a `Drop` impl created inside a
  `while`-loop body was never dropped at the end of each iteration (surfaced by
  the new leak gate). The compiler now reclaims it at the loop-scope boundary.

### CI

- **Release publishing is gated on the tagged commit's CI status** — a release
  can no longer ship from a SHA whose `ci.yml` did not pass.
- **Leak-freedom gate** over a pinned surface plus an HTTP per-request leak
  check, and a **symbol-collision gate** that fails the build when two stdlib
  helpers mangle to the same symbol (two real collisions were found and fixed).

## [0.11.2] — 2026-07-08

An **infrastructure-dogfood** release. The package registry itself is now a
NURL program — `packages/registry` re-implements reg.nurl-lang.org in pure
NURL on three of its own registry packages and is proven end-to-end against
the real `nurlpkg` client. Around it: the installed-tools story hardened
(embedded assets, an `[install] assets` mechanism, dependency-range and
installer fixes — a registry install of a tool now *just works*), the
WebGPU backend got 2–4× faster, the generation-accuracy study measured the
repair loop (one diagnostic round → exact Python/Rust parity), and the
LSan pass over the new registry found a long-standing compiler leak.

### Added

- **`packages/registry` 0.1.0 — the NURL package registry, served by NURL
  itself (critic C8).** A self-hostable registry speaking exactly the wire
  protocol `nurlpkg` drives: `/index/<name>.json` + content-addressed
  tarballs on the read side; bearer-authenticated `POST /api/v1/publish`
  (server-side SHA-256, first-publisher name ownership, version
  immutability), yank/unyank/revoke on the write side; search/stats JSON;
  and a server-rendered catalog UI whose package pages render the README
  straight out of the published tarball (relative image links rewritten
  onto a version-pinned, CSP-sandboxed `/files/` asset route). SQLite is
  the single source of truth — the index JSON is rendered from it on
  demand, removing the dual-write consistency hazard of the Cloudflare
  Worker it replaces. Tokens are peppered-SHA-256 hashes at rest, minted
  locally (`registry token new`) or via the config-gated GitHub OAuth
  flow. Built on the `http`, `template` and `md2html` packages. Proven by
  34 socketless router-level wire tests (ASan/LSan-clean) and an
  end-to-end script that drives the real `nurlpkg publish → search →
  install → yank` against it, dependency resolution included.
- **`nurlpkg`: `[install] assets` — runtime data files for installed
  tools.** A registry install used to ship only the compiled binary, so a
  tool with data files (anomaly's dashboard HTML) silently lost them. The
  manifest gains an optional `[install] assets = [...]` array; `nurlpkg
  install` stages each entry into `<prefix>/share/<name>/` (the
  relocatable `<exe-dir>/../share/<name>` convention tools already probe),
  clearing it first so upgrades leave no stale files. Asset paths are
  validated (no absolute, no `..`) — registry manifests are untrusted
  input. `anomaly` 0.3.6 declares `assets = ["static"]`, so a
  registry-installed `anomaly serve` now serves its dashboard with no
  `--webroot` flag.
- **`bench/genacc`: the repair loop, measured** — the v3 report's missing
  half. `repair.py` gives a failing generated program ONE round of
  compiler-stderr feedback (the model sees only its own code and the
  diagnostic, never the expected output): **Sonnet 80→100/100 and Opus
  70→100/100 — exact Python/Rust parity**; Haiku reaches 100% compile; the
  mercury-2 diffusion model quadruples its score. Auditing every v3
  failure also closed two frontend holes, now hard errors with fix hints:
  `!` on a non-`b` operand (used to emit invalid `xor` IR and surface a
  raw LLVM error) and an `&` FFI declaration written inside a function
  body (used to die with a misleading type-mismatch message).
- **`stdlib/ext/sqlite.nu`: `sqlite_changes`** — rows changed by the most
  recent INSERT/UPDATE/DELETE on the connection; previously unreachable
  for statements run through prepare/step (only `sqlite_exec` returned it).
- **Docs: getting a real WebGPU adapter on Linux Chrome** — the flag
  combinations that turn SwiftShader into the actual GPU.

### Performance

- **`gpu` WebGPU backend: 2–4× faster WGSL inference.** Four per-launch /
  per-element taxes removed: kernel launches now accumulate into a single
  command encoder submitted only when results must be observed (a browser
  pays an IPC round-trip per `queue.submit`; a YOLOE frame paid it ~380×);
  `conv2d` computes 4×2 outputs per invocation with constant-unrolled
  k3s1/k3s2/k1s1 fast lanes (66 → 269 GFLOPS on the yolov8s shape mix);
  the mask-proto `convtranspose2d` decodes its single contributing tap
  from output parity instead of scanning the kernel window; bind groups
  are cached.

### Fixed

- **Compiler: `^ ( f … x … )` no longer cancels the argument's auto-drop.**
  gen_ret derived the escaping binding from the last-identifier channel,
  which for a direct-call return holds the call's last *argument* — so
  returning a call that takes an owned string / `% Drop` value / owned-field
  struct as an argument leaked it on every such return (the callee never
  takes ownership of its arguments). The skip now keys on whether the
  returned value can alias the binding: bare-identifier returns keep the
  ownership transfer, call returns drop their arguments unless the callee
  is summarised ret-borrow (then the skip stays — dropping the source would
  dangle the returned alias). The `→ v` fall-off path gets the same guard:
  nothing escapes a void return, so a stale last-ident can no longer cancel
  a Drop-value's drop there. Lock: `compiler/tests/ret_call_arg_drop.nu`;
  bootstrap refreshed (the fix reclaims buffers inside the compiler itself).
- **Compiler: string literals are no longer size-capped by the C stack.**
  `encode_str` — the LLVM-IR `c"…"` encoder — recursed once per character,
  so a literal past ~124 KB (≈48 KB under a `zig -O2 -flto` release build)
  was a stack overflow, plus two heap allocations per character. Rewritten
  iteratively with a single worst-case output buffer; literal size is now
  bounded by memory only (verified through 2 MB). Lock:
  `big_string_literal.nu` (160 KB literal, position-weighted checksum).
- **`net`: a large response no longer aborts because the client reads it
  slowly.** `nurl_tcp_set_timeout` programs both `SO_RCVTIMEO` and
  `SO_SNDTIMEO`; during a big write to a slow-but-alive client one blocking
  `send()` window can pass with the socket buffer still full, and that
  `EAGAIN` was treated as fatal — a phone fetching a 54 MB model over LAN
  TLS died mid-body while the server logged a 200. A send timeout is only a
  dead peer when there is NO progress across consecutive windows:
  zero-progress send timeouts now retry up to twice (blocking sockets
  only — the fiber reactor's park-on-EAGAIN contract is untouched), and
  any successful write resets the allowance. A failed response write is
  also now logged with its `NetErr` name instead of vanishing.
- **`packages/http` 0.2.0** — the `HttpApp` facade now exposes the full
  server knob set (`http_app_body_max` / `head_max` / `max_keepalive` /
  `request_timeout` over `server_new_complete`), and two per-request leaks
  are gone: the pre-allocated panic-500 placeholder response now freed on
  the success path, and the dispatch/middleware closure envs released after
  the server returns. The same placeholder leak is fixed in the playground
  server (`nurlapi/main.nu`).
- **Installed tools now carry their assets embedded.** `nurlpkg install`
  ships only the built binary, so relative asset paths can never resolve
  on the host: `yoloe` 0.6.2/0.6.3 compile the 512 KB CLIP BPE merge table
  into the binary (`tokenizer_load_builtin`; emitted as ~32 KB chunks so
  the RELEASED v0.11.1 compiler — which still has the recursive string
  encoder — can build the package too), and `yoloe-demo` 0.2.2 embeds its
  page template the same way. `--merges FILE` remains as an override.
- **Installers no longer wipe registry credentials on reinstall.**
  `get-nurl.sh` / `get-nurl.ps1` deleted the whole prefix before unpacking
  — including `$NURL_HOME/credentials`, silently logging the user out of
  the registry on every toolchain upgrade. User data now survives.
- **Package dependency ranges un-broke registry installs.** Several
  manifests had drifted behind their published dependencies (caret on
  `0.x` locks the minor, so e.g. `onnx ^0.4.2` resolved a version missing
  the ops the code was built against, and `anomaly` 0.3.4's
  `gpu ^0.4` + `gpukit ^0.2` pair was unsatisfiable) — local path-deps hid
  all of it. Versions bumped and ranges synced (`anomaly` 0.3.5).

## [0.11.1] — 2026-07-07

A **neural-nets-in-the-browser** release. Real object detection and
open-vocabulary segmentation now run **entirely in a web page** — pure NURL
compiled to WebAssembly, with the ONNX runtime executing either on the CPU
(precompiled kernels) or on the visitor's GPU via a new **WebGPU backend**
(the CUDA-C kernels translated to WGSL compute shaders). No server inference,
no Python, no OpenCV, no inference engine. This is carried by two new demo
packages (`yoloe-demo`, and the playground's `objdet` page), two new `gpu`
backends (static + WebGPU), and the toolchain work that made in-browser GPU
compute possible — plus a template engine, TLS hardening, and a CI fix.

### Added

- **`packages/gpu` 0.4.0 — two new backends: static kernels and WebGPU.**
  Beyond CUDA (NVRTC) and the runtime-compiled CPU backend, `gpu` gains a
  **static-kernel backend** (backend 2): a generated `kernels_static.c`
  precompiles every kernel and registers them under
  `nurl_static_kernel(name)` (a weak NULL stub in the core runtime keeps
  every other link working), so a model runs with **no NVRTC, no system
  C++ compiler, no dlopen** — the backend a wasm module or a sealed native
  binary needs. Select with `NURL_GPU=static` or `( gpu_force_static )`.
  And a **WebGPU backend** (backend 3): the ONNX kernels, pre-translated to
  WGSL (`web/kernels_wgsl.js`), run through `navigator.gpu` (browser or
  Deno) driven by host imports the JS embedder implements (`web/webgpu.js`).
  Device memory is a `GPUBuffer`; the one async op — the `mapAsync` grid
  readback — is bridged with Asyncify so the synchronous NURL `gpu_download`
  returns data in wasm memory. Every WGSL kernel is verified on a real GPU
  against a JS reference of the CUDA-C (25/25 via Deno's headless WebGPU);
  the full YOLOE detector forward matches onnxruntime within tolerance
  (max abs err 0.02).
- **`packages/yoloe-demo` 0.1.0 — live YOLOE in the browser, served by pure
  NURL.** Open a page, start the webcam, and watch open-vocabulary detection
  + instance segmentation stream back. Three compute engines: the server GPU
  (frames posted to a pure-NURL HTTP/TLS server), **this browser · wasm
  (CPU)**, and **this browser · WebGPU** — one wasm module picks the backend
  at runtime. **Free-text prompting**: type any class (`coffee mug`,
  `a person waving`), the CLIP BPE tokenizer + MobileCLIP text encoder run on
  the GPU (all pure NURL), and the next frame detects it. The page template
  is rendered by `packages/template`; `--tls` mints a self-signed P-256 cert
  with `std/x509_gen`.
- **`packages/template` 0.1.0 — an HTML template engine over stdlib `Json`.**
  Jinja-flavoured `{{ vars }}` (HTML-escaped by default) with
  `raw`/`upper`/`lower`/`length`/`json` filters, `{% if/elif/else %}`,
  `{% for %}` with `loop.index`/`first`/`last`/`length`, `{% include %}`
  partials from a named `TplSet`, and `{# comments #}`. Missing keys render
  empty and are falsy (mustache-lenient); malformed tags are hard errors
  with line/col positions. Ships the fs-free engine, a directory loader, and
  a CLI. ASan/LSan-clean.
- **`packages/onnx` 0.6.0 — static-kernel generator + graph-executor
  completeness.** `tools/gen_static_kernels.nu` emits the precompiled kernel
  set for the gpu static/WebGPU backends. The graph executor grows the ops a
  browser-shaped ONNX graph (torch 2.12 / onnxsim) needs: `Slice` (single
  axis), a real `ArgMax` (with an int64 kernel for token inputs), the pb
  parser reads `TensorProto.int64_data` (packed varints), optional-input
  `Clip` no longer clamps everything to zero, and `Concat`/`Gather`
  normalise negative axes.
- **Playground objdet WebGPU demo (`/objdetdemo`).** Tiny-YOLOv2 object
  detection running on the visitor's GPU as WGSL compute shaders — the
  lighter demo (single image input, no prompting/masks, one model fetched
  once from the ONNX model zoo). Runs on the main thread (no worker, no
  SharedArrayBuffer) via a generic `asyncImport()` so `host_frame` awaits the
  next camera frame through the same Asyncify path as the GPU readback.

### Changed

- **`packages/wasmbuilder` 0.1.2 — WebGPU-ready wasm builds.** `--obj`
  accepts several space-separated objects (a module can link both the static
  kernels and the asyncify stack); `--cflags` passes extra flags (e.g.
  `-msimd128`); `--asyncify-imports` names the async host imports (asyncify
  was canvas-only); and the asyncify pass **strips DWARF first** — `wasm-opt
  --asyncify` aborts on the debug line-tables wasi-sdk/zig objects carry.
- **`packages/image` 0.4.1** — internal JPEG helpers renamed `__jp_*` →
  `__jpg_*`, resolving a cross-package symbol collision with `ext/json.nu`'s
  parser (one flat fn namespace) that surfaced the first time both were
  imported together.
- **Installers offer a permanent PATH entry** and set the current shell
  session where possible; the registry renders the `[package].repository`
  link and `nurlpkg` gained `[hints].postinstall`.
- Published to `reg.nurl-lang.org`: `gpu` 0.4.0, `onnx` 0.6.0, `wasmbuilder`
  0.1.2, `image` 0.4.1, `template` 0.1.0.

### Fixed

- **Compiler: call-argument integer-width coercion.** A sized-int parameter
  (`u`/`u16`/`i32`, …) called with an i64 value — any bare literal or a plain
  `i` variable — emitted `call @f(i64 …)` against `define @f(i8 …)`. The
  native ABI masks the mismatch, but on wasm32 the exact-signature rule makes
  `wasm-ld` emit a **trapping `_bitcast_invalid` stub** — YOLOE-in-the-browser
  died in `image_new`'s `( vec_push [u] d 0 )`. `gen_call` now trunc/extends
  fixed-position arguments against the declared parameter (generics substitute
  the call's type args first). Lock `callarg_width.nu`.
- **`packages/wasmbuilder`: working env imports.** The `#99` attribute group
  carried only `wasm-import-module`, which `wasm-ld` still rejects as
  undefined; the per-symbol `wasm-import-name` attribute is what marks an
  explicit import — so undefined `& c` symbols never actually linked through
  the local zig path (the container pipeline had masked this with
  `-Wl,--allow-undefined`).
- **Pure TLS: 16 KB record splitting + server-keyed close_notify.** A TLS
  record caps its plaintext at 2^14 bytes (and past 65535 the u16 length
  wraps), so responses over ~16 KB (fatally, over 64 KB) failed OpenSSL
  clients with "bad record mac" — found live by the demo's ~90 KB HTTPS
  responses. `tls_write`/`tls_server_write` now split into ≤16384-byte
  records, and `tls_close`'s close_notify is sent under the server keys
  (it was encrypting with the client-direction keys). A failed TLS handshake
  no longer takes the whole HTTP server down (it is a per-connection event).
- **FreeBSD CI out-of-memory.** The bootstrap self-compile peak had grown to
  ~13.2 GB and crossed the guest's 13.3 GB budget (OOM → SSH drop → exit
  255). The width-coercion emitter is now factored into one shared helper
  (dropping the peak) and the VM memory was raised to track the real peak.

## [0.11.0] — 2026-07-06

A **types-and-ecosystem** release. In the compiler, signedness now lives in
the type representation itself — the flag side-channel behind a whole class
of silent miscompiles is gone (critic A1, the last 1.0-lock compiler item) —
and diamond package dependencies compile once. Around the compiler, the
package ecosystem takes a leap: pure-NURL image codecs (`image`), an
n-dimensional tensor package over the GPU stack (`tensor` + `gpukit`, with a
zero-copy bridge into `onnx`), a declarative command-line framework (`cli`)
and a unified HTTP server facade (`http`) — plus npm-identical dependency
requirements, MCP session completeness, and a sweep of backlog fixes.

### Changed

- **Compiler (critic A1): signedness lives in the type representation.**
  The internal type language now keeps `u`/`u16`/`u32`/`u64` distinct
  from `i8`..`i64` end to end (as internal types `u8`/`u16`/`u32`/`u64`)
  — through the last-type channel, binding/param/field/payload/return
  metadata, `?`/`??` join types, and generic monomorph mangles —
  lowering to the LLVM i-types only at the IR-emission boundary
  (`nurl_llty`). The `__last_unsigned__` flag machinery (the
  side-channel behind 11 fuzzer-found silent miscompiles, later tamed by
  the last-type coupling) is deleted entirely: no
  `g_last_unsigned_p`, no `__unsigned`/`__ret_unsigned` syms keys, no
  `__last_nurl_type__` parse side-channel — a value's signedness can no
  longer go stale or be forgotten at a producing site. Fixes that fell
  out of the repr: struct→int casts zero-extend an unsigned field 0
  (was always `sext`), FFI fixed-position argument widening
  zero-extends unsigned args (was always `sext`), pointer-to-unsigned
  generic arguments (`[ *u64 ]` vs `[ *i ]`) monomorphise separately,
  and DWARF renders `u`/`u16`/`u32`/`u64` as `DW_ATE_unsigned` while
  signed `i8` is no longer mislabeled `u8`. New regression
  `signedness_in_types.nu`; validated by the bootstrap fixed point, the
  full suite, the examples gate, and a clean differential-fuzzer run.
- **`packages/gpu` 0.3.0 — shared primary CUDA context, modern `_v2`
  driver ABI, `gpu_dtod`.** `gpu_open` now retains the device's PRIMARY
  context (`cuDevicePrimaryCtxRetain` + `cuCtxSetCurrent`) instead of
  creating a private one — every consumer in the process shares one
  context and one device address space, so device pointers flow between
  packages (a gpukit buffer straight into an onnx graph); `gpu_close`
  releases the retain. All memory/copy/context entry points now bind
  the 64-bit `_v2` driver symbols — the unversioned names are the
  legacy pre-CUDA-3.2 ABI with 32-bit device addresses, which only
  happened to work inside a legacy `cuCtxCreate` context and silently
  break with 64-bit primary-context addresses (a live 4 GB landmine
  either way). New `gpu_dtod`: device→device copy from a raw device
  pointer (`cuMemcpyDtoD_v2`; plain memcpy on the CPU backend) — the
  primitive the tensor↔onnx bridge builds on. gpu/gpukit/tensor suites
  green on both backends; yoloe's 267-node segmentation forward stays
  byte-identical.
- **objdet 0.3.0 + yoloe 0.5.0 decode PNG/JPEG natively via
  `packages/image`.** Both packages delete their private PPM/resize/
  draw code and keep only a thin adapter (yoloe's ultralytics-matching
  letterbox and NCHW packing stay local), so they take photos and write
  annotated/mask-overlay PNGs and JPEGs directly — no ImageMagick
  shell-out. Equivalence proven: old-vs-new preprocessing tensors are
  bit-identical on real photos (objdet's 3×416×416 NCHW; yoloe's
  letterbox(640), 0 float mismatches), and a live GPU seg run on a real
  JPEG matches the previously verified result. Also fixed along the
  way: objdet's `voc_class` returned a borrow into a per-call Vec (real
  leak; suite is now ASan-clean), and yoloe cam's v4l2 YUYV group mask
  tripped the newer `&`-type check (widened before masking).
- **Dependency version requirements are npm-identical (node-semver).**
  `stdlib/ext/semver.nu`'s requirement engine rewritten as an OR of
  half-open intervals: a bare fully-specified version is now EXACT (was
  Cargo-style caret), and X-ranges (`*`/`1`/`1.2`), `^`, `~`,
  comparators, space-separated AND, hyphen ranges and `||` OR all match
  npm — verified against a table of npm cases, ASan-clean. The
  resolver/registry-index API (`semver_req_parse`/`matches`/`free`,
  `semver_req_max_satisfying`) is unchanged, so `nurlpkg` keeps
  building; every inter-package dependency in `packages/*/nurl.toml`
  switched to `^` to preserve the previous newest-compatible intent,
  and `packages/README.md` documents the full syntax table plus the
  convention (depend with `^`, bump minor on a 0.x breaking change).
- **nurl-mcp 0.4.0: `serve --http` mounts the stdlib Streamable-HTTP
  facade.** The hand-rolled single-POST handler (manual CORS, no
  batches, 405 on GET, no session-id echo) is deleted; nurl-mcp's own
  layer shrinks to bearer-token auth wrapped around `ext/mcp_http.nu`
  — the same plumbing swarm-mcp serves through (OPTIONS preflight
  bypasses auth, as browsers send no headers on preflight). Free from
  the facade: JSON-RPC batches, `GET /mcp` SSE probe, `Mcp-Session-Id`
  echo, `DELETE /mcp`, spec CORS. Verified live (401 without bearer,
  preflight, initialize, batch, SSE content-type, session-id
  round-trip); read-only tool gating holds and stdio is untouched.

### Fixed

- **Compiler: canonical import-dedup key — diamond dependencies compile
  once.** The import seen-tables keyed on the resolved path STRING, so
  the same file reached through two different-but-equivalent paths
  compiled twice and every symbol in it collided (`invalid
  redefinition`). Packages hit this through symlinked `deps/` chains —
  onnx importing tensor (whose dev.nu imports `deps/gpukit` →
  `deps/gpu`) alongside its own `deps/gpu` is a diamond.
  `__canon_import_key` (`realpath(3)`) now canonicalises the dedup key
  at all four seen-table sites; the as-written path stays in use for
  reading and diagnostics, so error messages and goldens are unchanged.
  New regression `import_diamond.nu`; two-step bootstrap, fixed point
  re-established.
- **nurlfmt: a match-arm `→` is no longer type context.** The formatter
  glued an operator starting a braceless arm body to its operand
  (`? flag x 0` → `?flag x 0`, `* n 2` → `*n 2`, `? != …` → `?!=`),
  making ternary/multiply/not/modulo read as type sigils in canonical
  output. Declaration headers (`@`/`\` … `{`) are now the only type
  context for arrows; return-type gluing (`→ ?i`) is unchanged. The 14
  covered files carrying the old glued spelling were reformatted; lock
  `fmt_arm_arrow_ops.nu`; both fmt gates green (777 files canonical,
  idempotence + IR-equivalence).
- **DWARF (critic A8): per-source-file `!DIFile`.** Imported functions
  and monomorphised stdlib generics debug-attributed to the top-level
  file (right line, wrong file). Subprograms now carry the !DIFile of
  their defining source — generics map through the template's recorded
  path. `vec_push__u8` renders as `./stdlib/core/vec.nu:203` in
  llvm-dwarfdump; non-debug IR is byte-identical and the bootstrap
  fixed point holds.
- **swarm-mcp:** `serverInfo.version` no longer hardcoded (was 0.7.0).

### Added

- **`packages/tensor` 0.1.0→0.3.0 — the reusable n-dimensional array
  the ML ecosystem lacked, over gpukit (M1–M3).** `Tensor` (row-major,
  f64 compute; an F32 dtype keeps values on the float32 grid): creation
  / reshape / transpose / permute, numpy-rule broadcasting elementwise
  and scalar ops, unary maps, 2-D matmul (GPU via gpukit for large
  problems, identical results), and axis/global reductions (M1);
  N-D batched matmul with batch-dim broadcasting, numerically stable
  softmax, per-dimension half-open slicing, concat, argmax/argmin (M2);
  and `DTensor` (M3) — tensor data lives in GPU memory and ops chain on
  the device with no host roundtrips (upload weights once, stream
  activations), residency explicit via `tensor_to_device` /
  `dtensor_to_host`, with TE_F32 DTensors computing IN float32
  (accumulation included) to match numpy-float32/onnxruntime
  semantics. Verified against numpy on CUDA (RTX 4090) and the gpu
  package's CPU backend — 17/17 + 25/25 + 12/12 per dtype, ASan-clean.
- **`packages/gpukit` 0.1.0→0.3.1 — diamond GPU-compute toolkit over
  the gpu package.** Kills the ~35-line marshalling dance every
  GPU-using package re-invents: typed `GkArg` bindings and one `gk_run`
  (per-name kernel cache; alloc, upload, marshal, launch, sync,
  download, free) plus ready-made f64 kernels — adding no numerics of
  its own, so a kernel runs bit-for-bit the same as through
  hand-written `gpu_*` calls. 0.2.0 (shaken out by the anomaly
  dogfood): `gk_open` returns a heap `*GpuKit` for singleton use, plus
  `gk_compile` to warm the cache at setup. 0.3.0: the device-resident
  layer — element-typed `GkBuf` allocations (`GK_F32`|`GK_F64`) with
  staging upload/download conversion, `gk_run_dev` (cached-compile
  launch over raw device args, zero marshalling), and dtype-generic
  `gkd_*` kernels with true-float32 GK_F32 semantics; 12/12 vs numpy
  per dtype. 0.3.1 republishes the manifest with `gpu ^0.3` (the
  published `^0.2` was disjoint from onnx 0.5.0's range, letting a
  resolver install two gpu versions side by side).
- **`packages/onnx` 0.5.0 — tensor↔onnx zero-copy bridge (M4a) + engine
  memory ownership.** `src/tensor_bridge.nu` is the seam between
  tensor's `DTensor` and the graph runtime, both living in the shared
  primary context: `rt_run_dtensor` runs a graph with a device-resident
  input — no host staging, no upload; the input is borrowed, never
  freed — and `dtensor_from_output` wraps a run's output as an OWNED
  `DTensor` via a device-to-device copy (outputs may alias an owned
  base at an offset — Reshape/Split — so ownership transfer would
  corrupt the heap). Device-input output is bit-identical to the host
  path and matches the onnxruntime reference; ASan-clean. ASan-gating
  the bridge also fixed a family of pre-existing engine leaks:
  `rt_reset` freed device buffers with `cuda_free` directly (every
  activation leaked on the CPU backend; now `gpu_free`), RTensor shapes
  were never freed and 9 op sites shared the input's shape vector,
  `graph_free` gives the parse layer a teardown at last, parser
  placeholder-String overwrite leaks (one per attr/node/tensor name —
  scales with model size), and `rt_open`/`rt_close` engine cleanup.
  yoloe's 267-node seg graph (exercising the reshape/split alias paths)
  stays byte-identical.
- **`packages/image` 0.1.0→0.4.0 — pure-NURL image codecs, raster ops
  and an `img` CLI.** Decode/encode images with no native library and
  no `convert` shell-out, over the stdlib DEFLATE: PPM (P5/P6); a
  complete PNG codec (decode of bit depths 1/2/4/8/16, Adam7
  interlacing, palette + tRNS colour keys → alpha; lossless 8-bit
  encode); baseline AND progressive (SOF2, the format most web JPEGs
  use) JPEG decode with any common subsampling and restart intervals;
  baseline JPEG encode (quality 1–100, 4:4:4/4:2:2/4:2:0, Annex K
  tables, loss profile matching Pillow's encoder); and libjpeg-exact
  "fancy" triangular chroma upsampling (bit-matching jdsample.c
  including its rounding biases), dropping 4:2:0 decode to
  IDCT-rounding distance from Pillow (max diff 3, tolerance tightened
  12→4). Plus `ops.nu` (resize nearest/bilinear/area, crop, flips,
  rotations, convert, fill/rect/line, alpha blit, packed `0xRRGGBBAA`
  colours), stb-style `image_error` failure reasons, and the `img` CLI
  (`info`/`convert`/`resize` with keep-aspect specs). Verified
  pixel-exact against Pillow where lossless, and hardened by a
  deterministic fuzz harness (10k+ mutants per seed, 6 formats,
  ASan+LSan, no hangs) that found a real infinite loop — baseline block
  decode never checked the Huffman decoder's corrupt-table return —
  alongside new dimension caps and inflated-size preflights.
- **`packages/cli` 0.1.0 + 0.2.0 — diamond command-line framework.** A
  single dependency-importable facade over std/args + std/term +
  ext/env that collapses the 100–500-line hand-written `main()` every
  package carries into a declarative `Cli`: git-style subcommand
  routing, typed flag accessors (str/int/bool/float) with env fallbacks
  and defaults, auto colour-aware `--help`/`--version` (TTY-gated,
  respects `$NO_COLOR`), error→exit-code conventions, and interactive
  prompts (`cli_confirm`/`cli_prompt`/`cli_password`). 0.2.0 adds
  `cli_default` — a default command for programs that ARE the command
  (psql/redis-cli shape): a bare invocation runs it, and a first
  positional matching no subcommand (e.g. a `redis://` URL) routes to
  it — and automatic help-short yield when a user flag claims `-h`.
  Migrated onto it: anomaly 0.3.2, yoloe 0.6.0, redis 0.2.0 and psql
  0.3.0 — three hand-rolled argv parsers deleted, clients live-verified
  against real servers (redis:7, postgres:16), and several pre-existing
  leaks fixed along the way (TCP handle leaked on connect failure,
  `__parse_url` String overwrites), flushed out by ASan-gating the new
  paths.
- **`packages/http` — unified HTTP server interface package.** The
  stdlib already ships the complete toolkit (sockets + TLS, parser,
  response builder, keep-alive server with pools + DoS limits, router,
  static files, auth/jwt/multipart/middleware/websocket); what every
  server re-invents is the glue. `HttpApp` collapses bind → router →
  shutdown signal → logging/CORS/panic-recovery → keep-alive loop into
  a few `http_app_*` calls (`http_app_get`/`_static_dir`/`_listen` or
  `_listen_tls`), reusing the battle-tested stdlib implementation with
  no duplication. First consumer: anomaly 0.3.0–0.3.3 — a
  self-contained web dashboard (model manager, trainer, feature
  visualiser, anomaly scanner served from `anomaly serve --webroot`;
  plain HTML/JS, no CDN, no build step), serving migrated onto HttpApp
  (~35 lines of hand-wired glue → 6, gaining graceful SIGINT/SIGTERM
  shutdown and handler panic→500 for free) and GPU scoring onto gpukit
  (bit-identical output preserved).
- **`nurl.sh --coverage` (critic C9):** line coverage for `.nu`
  sources — gcov-style `-fprofile-arcs -ftest-coverage` as IR passes
  over the DWARF metadata `--debug` emits; `llvm-cov gcov` reports
  per-line hit counts against the original source.
- **`std/fswatch.nu` (critic B8):** file watching via Linux inotify,
  pure libc FFI — blocking `fswatch_next`, `FSW_*` masks, multiple
  packed events cursored out one per call. Lock `fswatch_basic.nu`.
- **`std/process.nu` (critic B11):** raw streaming on a live child —
  `proc_read_chunk` (poll-gated incremental read, empty Vec = EOF) +
  `proc_write_bytes`, interleaving safely with `proc_read_line`. Lock
  `process_pipes.nu` (live cat round-trips + sort-after-EOF).
- **LSP `textDocument/rename` (critic C7):** references sweep + decl
  index mapped to a WorkspaceEdit, -32602 on invalid targets/names,
  `renameProvider` advertised. Lock `lsp_rename_smoke.sh`.
- **MCP session completeness (critic B22, all three):**
  `Last-Event-ID` SSE resumption (monotonic event ids + bounded
  64-event per-session backlog, best-effort replay), JSON-RPC batch
  arrays through `mcp_http_handler_session` (validated once, ordered
  responses, 202 for pure notifications), and `resources/subscribe` +
  `notifications/resources/updated` delivered over the session SSE
  stream (the session transport advertises `resources.subscribe:true`
  on initialize). Locks extended in `mcp_session_basic.nu` +
  `mcp_http_session.nu`.
- **packages/swarm-mcp 0.9.0:** `--mcp` now mints its self-signed TLS
  certificate in pure NURL (`std/x509_gen`) — the `openssl` CLI
  dependency is gone; minted pair verified with openssl and a live
  curl MCP handshake.
- **Registry + web.** Package pages now show the verified owner (first
  publisher) and the GitHub login that published each version, sourced
  from the D1 identity tables — the authenticated publishing identity,
  crates.io/npm style; `nurl.toml` gains no self-declared author field.
  New `GET /api/v1/stats` (packages/versions counts, CORS-open, 5-min
  cached) feeds a live registry-package count on nurl-lang.org (fetched
  at deploy time, best-effort). Brand imagery lands: hero logo mark,
  og:image/twitter social card, brand-showcase band, and a branded
  registry header + favicon on every page.
- **Pre-commit `nurlfmt` hook.** `.githooks/pre-commit` runs `nurlfmt
  --write` on fully-staged `.nu` files and re-stages them (a
  partially-staged file is only `--check`ed and blocks the commit, so
  unstaged edits are never silently staged); `build.sh` wires
  `core.hooksPath = .githooks` on build, so a normal build activates
  it. Prevents commits that would trip the CI `nurlfmt --check` gate.

### Docs

- Backlog synced to reality: A8/B8/B11/B22/C7/C9 checked off with
  locks; B20 (HTTP/2 client interleave) and C6 (`nurlfmt --check` CI
  gate) were found already shipped and are annotated as such; C8 notes
  the live registry.
- `ROADMAP.md` reviewed for 0.11.0: signedness-in-the-type-repr wording,
  the registry package-ecosystem summary, and removal of stale pointers
  to untracked scratch files (also scrubbed from `docs/CRYPTO.md`).

## [0.10.12] — 2026-07-03

A patch release: **GPU-dependent packages are installable from release
archives again.** v0.10.11 archives were assembled on a GPU-less CI runner
and shipped without the `runtime.cuda` / `runtime.nvrtc` sentinels, so the
installed compiler refused to build anything depending on `packages/gpu`
(`nurlpkg install anomaly` failed on every machine — GPU or not).

### Fixed

- **cuda/nvrtc build sentinels are unconditional — stub-backed libs always
  link.** The sentinels (nurlc's compile-time FFI-lib gate) were probed
  from the *build* machine, but they answer a question about the *link*:
  cuda and nvrtc are the two FFI libraries with fallback stub objects
  (`stdlib/{cuda,nvrtc}_stubs.o`) — `nurl.sh` links the real library when
  the host has one and the stubs when it doesn't, stubbed calls return
  errors, and `packages/gpu` falls back to its CPU backend. The gate could
  only ever produce false negatives, and baked into a release archive it
  blocked gpu-dependent packages everywhere. Stub-backed libraries now get
  their sentinels unconditionally (the host probe remains for the build
  log); libraries without stubs (opus, asound, X11, sqlite3, …) keep the
  conditional probe, and Windows (`build.bat`, no cuda stubs) is
  unchanged. Verified end to end: with the sentinels in the installed
  stdlib, `nurlpkg install anomaly` resolves `iforest` + `gpu` from the
  registry, compiles, links the real `libcuda`/`libnvrtc`, and the
  installed binary scores a 5001-row batch through the CUDA path in
  0.29 s.

## [0.10.11] — 2026-07-03

A **streaming anomaly detection** release. The new `anomaly` package is a
complete self-training anomaly-detection service in pure NURL: named models
are created on first use, ingest one JSON point at a time over CLI or HTTP,
and train themselves once enough history accumulates — Isolation Forests
under the hood (the `iforest` package), scikit-learn's exact decision
conventions on top, and GPU-accelerated bulk scoring that is bit-identical
across CUDA, the gpu package's CPU backend, and the pure-NURL loop, so a
GPU-less machine gets the same verdicts. Also in this release: the `cas`
content-addressed store and pure-NURL self-signed X.509 certificates, plus
two ecosystem-wide leak fixes the new package's sanitized suite flushed out
(every CLI's argv parse; every gpu-package consumer's device allocations).

### Added

- **`packages/anomaly` v0.2.0 — streaming anomaly-detection service:
  dynamically created, automatically trainable models.** Where `iforest`
  is the kernel (matrix in, scores out), `anomaly` is the service around
  it. Heterogeneous features encode automatically (numeric passthrough,
  categorical → deterministic sorted one-hot, ISO-8601 → calendar
  features) with a frozen feature-order projection so one-hot columns
  never scramble across retrains; a persisted StandardScaler analogue
  standardises them. Each model keeps a bounded ring of raw points
  (data.jsonl — raw, so retrains learn new categories), warms up to 50
  points, then retrains every enabled time-window version (`short_term`
  180 min / `daily` / `weekly` / `seasonal` 90 d / `timevector` last 100
  points) on schedule; a point is anomalous if any version flags it.
  Decision maths match scikit-learn exactly — `decision_function =
  -iforest_score − offset_`, `offset_ = −0.5` for `contamination='auto'`,
  else the 100·c training percentile; validated against sklearn on
  identical deterministic data (agreement within ~0.01). Margins are read
  from live metadata so `finetune` (95 % of the worst observed score) and
  config changes apply without retraining. Persistence is atomic with
  fully-validated binary forest blobs — corrupt, truncated, or renamed
  files load as errors, never UB. Ships as a library (`model_open` /
  `model_ingest` / `model_detect_only` / …, injectable clock via `_at`
  variants), a CLI (`anomaly detect/score/batch/train/reset/rm/ls/info/
  serve`), and an HTTP/JSON service mirroring the reference Flask API
  route for route (202 while warming, `^[a-zA-Z0-9_]+$` name validation,
  same error shapes). **GPU path (M7):** bulk scoring (batch CSVs, the
  contamination percentile, the fine-tune sweep) routes through
  `packages/gpu` at ≥ 128 rows — CUDA when present, the gpu package's CPU
  backend (host C++ + OpenMP) without one, pure NURL with neither — and
  all three engines are **bit-identical by construction** (the kernel only
  sums f64 path lengths in the pure walker's order over host-precomputed
  per-leaf constants; the nonlinear finish stays in NURL), asserted
  element-for-element `==` in the tests. Measured on 200 000 rows × 300
  trees: pure 9.6 s → host C++ 1.1 s (~9×) → RTX 4090 213 ms (~45×).
  Suite: seven unit suites (165 checks), a CLI end-to-end pass, a live
  served-over-curl smoke, and the GPU parity test on both engines —
  ASan/UBSan/LSan-clean throughout, deterministic (seed 42 ⇒
  byte-identical forests and scores everywhere).

### Added

- **`packages/cas` v0.1.0 — content-addressed store over BLAKE3 + minimal
  manifest.** The keystone of a verifiable build → hash → dedup →
  distribution chain: bytes are stored under their own BLAKE3-256 hex
  (git/OCI-shaped two-level fan-out of plain files, atomic tmp+rename
  writes, dedup by existence — no index, no database, no locks), and every
  read **re-hashes what it found**, refusing to return bytes that don't
  match their name — a store you can rsync, mirror, or fetch from an
  untrusted cache without losing integrity. A snapshot is a canonical text
  manifest (`cas-manifest v1` + sorted `hash size path` lines) stored in
  the CAS like any blob, so one 64-hex string names an entire tree
  Merkle-style and the same tree always snapshots to the same hash.
  CLI (`cas put/hash/get/snapshot/ls/checkout/verify`, store at
  `$CAS_STORE` or `~/.cas`) + embeddable library (`cas_put` / `cas_get` /
  `cas_snapshot` / `cas_checkout` / `cas_verify`). Tests cover round-trip,
  in-store dedup (N identical files → one object), snapshot determinism,
  and the point of it all: a flipped byte inside the store turns `get`,
  `verify`, and `checkout` into errors — never silent corruption.
  Path-traversal-safe checkout (manifest paths may not escape the
  destination). ASan/UBSan/LSan-clean including the error paths.

- **`std/x509_gen.nu` — self-signed X.509 certificates in pure NURL.** The
  write-side sibling of the parse-only `std/x509.nu`: a minimal DER encoder
  plus TBSCertificate assembly, self-signed with the ECDSA-P256/SHA-256 and
  P-256-keygen machinery the stdlib already had. `x509_selfsigned_p256 cn
  days` returns a certificate PEM (X.509 v3: random serial, CN + dNSName
  SAN, basicConstraints critical CA:TRUE, ecdsa-with-SHA256) and a SEC1 /
  RFC 5915 `EC PRIVATE KEY` PEM — exactly the pair `openssl ecparam` +
  `openssl req -x509` used to produce, so the pure TLS server consumes the
  files unchanged and servers like swarm-mcp `--mcp` can drop their OpenSSL
  subprocess. The `_pinned` variant takes an explicit scalar/serial/validity
  and — because the stdlib's ECDSA is deterministic RFC 6979 — produces a
  byte-reproducible certificate, which is what makes the golden test
  (`compiler/tests/x509_selfsigned.nu`) possible. Verified externally:
  `openssl verify` accepts the cert, the key↔cert pair matches, and `curl
  --cacert` completes a fully-verified TLS handshake against the pure-NURL
  TLS server serving it. New playground example
  `examples/selfsigned_cert.nu` prints a freshly minted pair and re-verifies
  it with the stdlib's own X.509 parser.

### Fixed

- **`args_parse_argv` leaked every argv token** (`std/args`) — every CLI
  built on it (cas, nq, anomaly, …) leaked argc strdups per process:
  `nurl_argv_get` returns a heap copy by contract, but the parser treated
  it as borrowed and copied it again. The copy is now adopted with
  `string_from_take`. Found by the anomaly package's sanitized CLI suite.

- **`packages/gpu` v0.2.1 — every out-slot and compile-path leak
  plugged.** `cuda.nu` leaked its 8-byte out-param slot on every wrapper
  call — `cuda_malloc` leaked per device allocation, for every consumer of
  the package (onnx, objdet, yoloe) — and `cpu_compile` leaked every
  working String it built (cast list, generated source, tmp paths,
  compiler command lines) on success and error paths alike. All freed at
  last use; `cuda_device_name`'s contract documented (returns a fresh
  buffer the caller owns). gpu's own tests pass on both backends.

## [0.10.10] — 2026-07-03

A **local wasm builds** release. The new `wasmbuilder` package turns a bare
toolchain install into a complete NURL → wasm32-wasi compiler — no wasi-sdk,
no Docker, no build service: the bundled `zig cc` (wasi-libc + wasm-ld
built in) links what nurlc emits, and the wasm runtime object is compiled
from the installed stdlib on first use. swarm-mcp compiles compute kernels
locally on the strength of it, nurl-mcp grows a fully local
`nurl_build_wasm` tool, and the Windows release now bundles zig like the
Linux archives. The compiler fix underneath: enum payload slots are `i64`
now, so f64 / >2³² payloads survive wasm32 bit-exactly — general-enum
programs produce byte-identical output native vs wasm. Also in this
release: swarm-mcp's GPU engine matured through v0.6.0 (runtime kernel
params, GPU map + histogram) and v0.7.0 (distributed GPU compute over real
uploaded datasets).

### Fixed

- **Enum payload slots are now `i64`, not `ptr` — 64-bit payloads survive
  wasm32.** General-enum payload slots were pointer-typed and every payload
  transited them via `inttoptr`/`ptrtoint`. Lossless on 64-bit targets, but
  a wasm32 pointer is 32 bits wide, so an `f` payload's bit-pattern or an
  integer ≥ 2³² silently lost its upper half on the wasm target (the
  chaotic-showcase autodiff computed garbage under wasm while passing
  natively). Payload slots are now uniformly `i64` on every target —
  floats bitcast in and out, narrow ints widen/trunc, and pointers are the
  ones that convert (`ptrtoint`/`inttoptr`, lossless everywhere, wasm32
  pointers zero-extend). Construction, match destructuring (slots 0–N,
  literal payload patterns), and the auto-generated enum `Drop` all moved
  together, so the layout change is invisible on 64-bit native — proven by
  the full corpus and the held bootstrap fixed point. New regression:
  `compiler/tests/enum_payload_64bit_slots.nu` pins the 64-bit-exact
  round-trip for f64 / >2³² / negative i64 / mixed-slot / pointer payloads
  (and runs identically as wasm via the wasmbuilder corpus).

### Added

- **`packages/wasmbuilder` v0.1.0 — local NURL → wasm32-wasi builds, no
  wasi-sdk, no build service.** `nurlpkg install wasmbuilder` is all a blank
  machine needs: the CLI (`wasmbuilder file.nu` → `file.wasm`, plus
  `--doctor`) and library (`wb_build_file` / `wb_build_source`) drive the
  installed toolchain end to end — nurlc emits IR, the production IR
  rewriter (extracted from nurlapi's `/build_wasm`) retargets it for
  wasm32-wasi, and the toolchain's **bundled `zig cc`** links it (zig
  carries wasi-libc + wasm-ld, which is what makes wasi-sdk unnecessary).
  `runtime.wasm.o` is compiled from the installed stdlib's `runtime.c` on
  first use and cached by content hash, so it always matches the toolchain;
  a machine with no zig at all downloads the pinned 0.13.0 release once,
  sha256-verified against ziglang.org's index (`NURL_WASM_NO_DOWNLOAD=1`
  opts out). zig's driver rejects `-Wl,--allow-undefined`, so the rewriter
  instead marks every remaining `declare` with a
  `"wasm-import-module"="env"` attribute — same semantics (undefined
  symbols become host-resolved wasm imports; defined symbols win), now
  expressed in the IR. A `@main` alias keeps zig's debug-mode wasi-libc
  linking at `-O0`. Corpus-tested: 13 repo examples byte-identical to their
  native builds under both the reference wasmtime and the pure-NURL `wt`;
  the compiler itself (65k lines) built through wasmbuilder compiles
  programs byte-identically to its native twin.

- **`packages/swarm-mcp` v0.8.0 — kernels compile locally.**
  `compute_submit_kernel` / `compute_submit_cuda` now build wasm in-process
  via the new wasmbuilder dependency (local toolchain, no network); the
  NURL build API (`$NURL_BUILD_API`) remains as a fallback for hosts whose
  toolchain can't build wasm. A local `nurlc failed` (a genuine kernel
  error) is returned directly instead of being retried remotely.

- **`packages/nurl-mcp` v0.3.0 — `nurl_build_wasm` tool.** Compile inline
  `source` or a `path` to a wasm32-wasi module fully locally via
  wasmbuilder: optional `out` path; a `path` input defaults to
  `<input>.wasm` next to it; inline source without `out` returns JSON with
  `wasm_base64`. Gated with `nurl_build` (off under `--read-only`).

- **Windows release bundles zig** (`release.yml` + `install-toolchain.bat`
  staging + uninstall): the Windows toolchain zip now carries the same
  self-contained zig backend as the Linux archives, so wasmbuilder works
  offline there too; older Windows installs fall back to wasmbuilder's
  one-time zig download.

- **`packages/swarm-mcp` v0.7.0 — datasets: distributed GPU compute over real
  data.** `compute_upload_data` uploads a flat f64 array (base64 raw LE, or a
  file on the MCP host; ≤ 256 MiB) and returns a `dataset_id` + stats; the
  three CUDA tools take `dataset: id` and the device functions receive each
  element as a second argument — `f(long long x, double v)`, `bin/val(x, v)`,
  with runtime params as a trailing `const double* p`. Without `lo`/`hi` the
  whole dataset is processed. Sharding follows the map-reduce split rule: each
  chunk's payload (v3) carries exactly its own data slice (≤ 12 MB per chunk
  under the relay's 16 MB frame cap), HMAC-tagged like everything else; the
  worker hands it to the module through a sandbox-preopened file and the
  generated program uploads it to the GPU. Verified live against Python
  references: sum / max / variance-with-param over 100k gaussians exact,
  pointwise normalisation exact, 10-bin `floor(v)` distribution exact.
  `compute_list_data` lists uploads.

- **`packages/swarm-mcp` v0.6.0 — dynamic, versatile GPU compute.** Three
  upgrades to the distributed GPU engine:
  - **Runtime kernel params, no recompiles.** `params: [numbers]` reach the
    CUDA device functions as `const double* p` via each chunk's argv — the
    generated source (and so the module hash) never changes. Together with a
    new coordinator-side compiled-module cache (keyed by generated source) and
    the existing worker-side content-hash cache, a parameter scan pays the
    build API once and then resubmits in seconds.
  - **`compute_sample_cuda`** — a GPU map that returns *every* value: `f(x)`
    for each `x` in order (curves, fields, tables). Inline as JSON (≤ 1024) or
    base64 f64 LE (≤ 65536), or written to `out_file` (≤ 1M values);
    min/max/mean always included.
  - **`compute_histogram_cuda`** — binned aggregation in one pass: `bin(x)`
    picks one of K buckets, `val(x)` (default 1.0) is accumulated with a
    portable CAS-based double `atomicAdd`; chunks combine elementwise. K rides
    argv, so one module serves any bin count.

  GPU chunks now use payload v2 (`[ver][mode][lo][hi][K][params][wasm]`);
  vector modes return results through a sandbox-preopened binary file (one
  `fwrite`) instead of stdout, and the result frame `[ok][count][f64…]` keeps
  chunk failures visible. All-in-one nodes with `--gpu` require a same-version
  cluster for GPU tasks (CPU task wires are unchanged).
- **`packages/wasmtime` v0.6.1**: `nvrtcCompileProgram`'s options array is now
  marshalled correctly — each guest `char*` entry is translated to a host
  pointer (bounded, NULL for out-of-range), mirroring `cuLaunchKernel`'s
  void** handling. Previously any nonzero option count handed libnvrtc guest
  offsets as host pointers.

- **`stdlib/dist/job.nu`: per-kind routing rings (capability domains).**
  `job_set_ring(node, kind, ring)` scopes a task kind to its own consistent-hash
  ring — submit, ownership, and mid-flight forwarding for that kind all resolve
  against the scoped ring, so a task can never land on (or re-home to) a node
  outside its capability domain. Kinds without a scoped ring use the main ring,
  unchanged. New golden coverage in `compiler/tests/dist_job.nu`.
- **`packages/swarm-mcp` v0.5.0 — distributed GPU compute over MCP.**
  Workers started with `--gpu` advertise a capability bit in the HELLO gossip
  (a trailing byte older nodes ignore); every node folds GPU workers into a
  GPU-only ring and the GPU wasm task kind routes on it, so mixed CPU/GPU
  clusters just work. GPU chunks run under the pure-NURL wasmtime with
  `--allow-gpu`, executing CUDA/NVRTC host imports on the worker's real GPU.
  New MCP tool **`compute_submit_cuda`**: the model writes only a CUDA-C
  `__device__ double f(long long x)`; the server generates the complete kernel
  program (NVRTC JIT, grid-stride map, on-device block reduction, host fold),
  compiles it to wasm, and shards it across the GPU workers — verified live on
  an RTX 4090 (π·10⁹ integral; a 250M-element chunk in ~0.3 s including the
  JIT). `compute_submit_kernel` gains `kind:"chunk"` (one kernel call per
  sub-range) and `gpu:true`; `compute_run_wasm` gains `gpu:true`.

### Changed

- **swarm-mcp wasm results are failure-visible.** The wasm result frame is now
  `[ok:1][partial:8]`; a chunk that fails (module trap, missing runtime, GPU
  error) is counted and the task finishes as `status:"error"` with
  `failed_chunks` — never silently folded into the reduce as a zero. Legacy
  8-byte frames are still accepted.

## [0.10.9] — 2026-07-02

A **wasm toolchain** release. The pure-NURL `packages/wasmtime` runtime grows
from a proof-of-concept into a spec-faithful, hostile-input-hardened WebAssembly
engine — real traps and multi-value blocks, bulk memory + reference types, a
bounded explicit frame stack with fuel metering and name-section backtraces, a
much larger WASI surface (positioned I/O, directories, real clocks/entropy/env),
and a CUDA/NVRTC host-import bridge that runs GPU wasm modules on real hardware.
Two compiler FFI argument-coercion fixes make GPU-using NURL compile to wasm at
all, and the runtime now aborts loudly on OOM instead of silently corrupting
wasm32 linear memory. Organisationally, `stdlib/runtime.c` is split into a
bootstrap core and the stdlib FFI shims.

### Added

- **Compile GPU-using NURL to WebAssembly — `nurlc --ffi-host-imports`.** With
  the new flag, external `` `&`-FFI `` libraries are satisfied by the run-time
  embedder as wasm imports (module `env`) instead of a native link line, and the
  build-time `stdlib/runtime.<lib>` sentinel gate is skipped (native path
  unchanged, flag off by default). `nurlapi`'s wasm build passes it through and
  links with `-Wl,--allow-undefined`, so undefined FFI symbols become wasm
  imports; a genuinely missing symbol traps at run time with its name. This is
  what lets a GPU package (objdet → onnx → gpu) compile to a wasm module the host
  resolves against real libcuda/libnvrtc.
- **`packages/wasmtime` — WASI expansion.** `environ_get`/`_sizes_get` from
  repeatable `--env NAME=VALUE` (capability-style; the host environment is never
  inherited implicitly); real `clock_time_get` (wall + monotonic, ns) and
  `random_get` from the OS CSPRNG (both previously returned zeros); a `path_open`
  overhaul (directory fds, `O_CREAT`/`O_EXCL`/`O_APPEND`/`O_TRUNC` semantics),
  positioned `fd_pread`/`fd_pwrite`/`fd_tell`/`fd_sync`, offset-correct
  `fd_write`, a directory surface (`fd_readdir`, `path_create_directory`,
  `path_remove_directory`, `path_unlink_file`, `path_rename`,
  `path_filestat_get`), and multiple preopens via repeatable `--dir`.
- **`packages/wasmtime` — bulk memory + reference types.** Passive data/element
  segments (`memory.init`/`data.drop`, `table.init`/`elem.drop`), a runtime
  funcref table mutable via `table.get`/`set`/`grow`/`size`/`fill`/`copy`,
  `ref.null`/`ref.is_null`/`ref.func` and typed `select`, and up-front
  bounds-checked `memory.copy`/`fill`/`init` (no partial writes before a trap).
- **`packages/wasmtime` — explicit frame stack, fuel metering, backtraces.**
  `exec_func` drives an explicit frame stack, so guest calls no longer recurse on
  the host native stack — deep guest recursion is bounded by `max_depth` (65536
  frames, trap `call stack exhausted`) instead of a host stack overflow (verified
  1M-deep). Optional `--fuel N` traps a runaway guest after N instructions; the
  custom `name` section is decoded and traps append a wasm backtrace.
- **`packages/wasmtime` — CUDA/NVRTC GPU host-import bridge.** Resolves a GPU wasm
  module's `cuda`/`nvrtc` imports to real libcuda/libnvrtc, marshalling guest
  linear memory ↔ host (every `*u` param is a guest offset → host address;
  opaque handles and `CUdeviceptr` travel as raw `i64`; `cuLaunchKernel`'s guest
  `void**` is reconstructed host-side). `nurl.sh` auto-links libcuda/libnvrtc
  when those symbols appear and stubs them on a GPU-less host. Verified on an
  RTX 4090 (`vadd`, `cuInit`+`cuDeviceGetCount`).
- **`nurlapi` — `/build_wasm` accepts pre-compiled IR (`ir` field).** The only
  way to wasm-build a multi-file package: a host `nurlc` resolves the `$`-imports
  the container lacks and the container just does the wasm rewrite + wasi-clang
  link.

### Changed

- **Runtime source split (A9) — `stdlib/runtime.c` → bootstrap core + FFI
  shims.** The 5.2k-line runtime is separated into
  `stdlib/runtime_core.c` (bootstrap core: OOM policy, version, Win32
  shims, basic stdio I/O, string ops, file/dir, the allocator +
  panic-unwind journal, IEEE-754/math, and panic/recover) and
  `stdlib/runtime_ffi.c` (stdlib FFI shims: HTTP, process, TCP/TLS + UDP
  sockets, DNS, thread trampolines, signals, and the async fiber runtime +
  I/O reactor). `stdlib/runtime.c` becomes a thin aggregator that
  `#include`s both into one translation unit, so the default build still
  emits a single `stdlib/runtime.o` with a byte-identical symbol set and
  link surface — no build-script or bootstrap changes. `runtime_core.c`
  has zero references into the FFI half and compiles standalone, so it
  now *defines the core symbol set* a bootstrap/`no_std` target must
  provide (unblocks ROADMAP D2). Organisational only: no behavioural
  change, self-host fixed point held, full corpus + sanitizer suite green.
- **`packages/wasmtime` — core semantics: multi-value, real traps, checked
  `call_indirect`.** Block types decode as signed-LEB `s33` (multi-value
  blocks/loops/ifs), `call_indirect` performs the runtime structural signature
  check, the `start` section runs at instantiation, integer divide-by-zero and
  `INT_MIN/-1` overflow trap, float→int truncation traps on NaN / out-of-range
  (with saturating `0xfc` forms), and float min/max/compare are NaN-correct.
- **`packages/wasmtime` — import layer strictness.** Imports record their module
  name and dispatch verifies `wasi_snapshot_preview1`; a table/memory/global
  import (or `global.get` in a const expression) is now a hard decode error
  instead of being silently skipped.
- **`packages/wasmtime` — hardened against hostile input (v0.6.0).** Audited
  against malformed/adversarial wasm (ASan-fuzz + exhaustive prefix sweep): every
  vector count is validated against the bytes physically remaining before
  allocating (`__chk_count`), negative/over-long section and name-subsection
  sizes are rejected, truncated init/element expressions are clean decode errors,
  and `mem.min`/`table.min`/per-function locals are capped. Every input is now
  memory-safe and terminating; valid modules still run byte-identically to
  reference wasmtime.

### Fixed

- **`nurlc` — FFI argument coercion to the declared parameter width, plus
  int↔pointer.** An integer argument whose width differs from an FFI function's
  declared parameter (NURL literals are `i64` → an `i32` param) was emitted
  verbatim; native LLVM tolerates it but `wasm-ld` replaces the whole function
  with an `unreachable` stub that traps at run time. `gen_ffi_decl` now records
  each symbol's LLVM parameter types (`__ffi_params`) and `gen_call` coerces via
  `trunc`/`sext` (and `inttoptr` for a bare `0`/handle passed to a pointer
  param). `__ffi_params` is also registered in the `scan_fn_sigs` pre-pass so
  forward-referenced FFI symbols coerce correctly. Fixes the long-standing
  `fread`/`cuLaunchKernel` "unreachable stub" on wasm.
- **runtime — abort loudly on OOM, on every allocation.** `nurl_alloc`/`_zalloc`/
  `_realloc` and the 81 other `malloc`/`calloc`/`realloc`/`strdup` sites in the
  runtime returned raw NULL on OOM. On native that faults on first write, but on
  wasm32 address 0 is ordinary writable linear memory, so a NULL-backed
  string/vec silently corrupts state (observed as the `nurlc.wasm` self-host
  "hang": once `memory.grow` failed past the 4 GiB ceiling the analysis spun on
  NULL-backed state). File-wide checked wrappers now abort with
  `nurl: out of memory (requested N bytes)`; the panic-journal grow keeps its
  deliberate degrade-to-a-leak.
- **FFI decls — `nurl_peek_i32`/`nurl_poke_i32` are 32-bit, not `i64`.** Every
  package declared these 32-bit runtime accessors with NURL's `i` (`i64`); on
  LP64 native the register hid the high bits, but on wasm the type differs from
  `runtime.wasm.o` and `wasm-ld` emits an `unreachable` stub. Fixed to `i32` in
  gpu (`cuda.nu`/`cpu.nu`), onnx (`pb.nu`) and yoloe.
- **`nurlapi` — libc `off_t`/`size_t` wasm width shims.** Correct the FFI shim
  widths that produced `unreachable` stubs on `fs.nu`'s `fopen`/`fread` file path
  (`lseek` removed from the shim list — its `off_t` is already 64-bit on wasm32;
  a new `w` param-char for an `i32` parameter `nurlc` already emits as `i32`).

## [0.10.8] — 2026-07-02

A **dynamic trait objects** release. NURL's trait system gains a second,
opt-in dispatch path alongside the existing static one: `%Trait` boxes a
concrete implementer behind a vtable fat pointer, so heterogeneous
collections and plugin-style APIs can dispatch on the trait rather than the
concrete type — no GC, and the existing monomorphised `impl` dispatch is
unchanged. Diamond supertraits upcast through the same object, object safety
is checked at compile time, and the box's `Drop` is synthesized so the
single-owner memory model holds. A real leak in the (unrelated) static
impl-method dispatch path, found while adding the feature, is fixed
alongside it.

### Added

- **Dynamic trait objects — `%Trait` (docs/spec.md §4.9).** A trait can now be
  used as a runtime-dispatched *object* so values of different concrete types are
  handled uniformly, layered *beside* the existing static path (a concrete
  `( fmt p )` still lowers to `fmt__Point`; concrete values carry no trait
  identity). `%Trait` is a fat pointer `%dyn.<Trait> = { i8* data, i8* vtable }`:
  a heap-boxed copy of the value plus a per-impl vtable (slot 0 = destructor,
  slots 1..K = one uniform-ABI thunk per method). `( dyn Trait value )` boxes a
  value that implements `Trait`; a bare-name call `( method obj )` on a `%Trait`
  receiver loads the vtable slot and dispatches indirectly. **Diamond upcasting**:
  the vtable flattens the transitive supertrait method set, so a `%Pet` object
  (`Pet : Animal`) dispatches Animal's methods too — including inherited
  **default** methods, which call back through the object's own dynamic dispatch.
  **Object safety** is enforced with a precise diagnostic: a trait is usable as
  `%Trait` only if every method (and every supertrait's) is dispatchable from an
  `i8*` self plus its signature (has a `[T]` Self parameter; no method lacks a
  Self receiver, names Self beyond the receiver, consumes self by value, or
  mentions an associated type). **Memory safety**: a `%Trait` binding is an owned
  value with a synthesized `Drop` that runs the vtable's slot-0 destructor on the
  boxed value (freeing its owned resources transitively) then frees the box — no
  leak, no double-free, verified under AddressSanitizer. Tests: `dyn_dispatch`,
  `dyn_diamond`, `should_fail_dyn_not_object_safe`.
- **`nurlfmt` understands `%Trait` type sigils.** The formatter now distinguishes
  the three uses of `%` — trait/impl declaration sigil, `%Trait` object type, and
  the modulo operator — using prefix-notation context (an operand never precedes
  an operator). A `%Trait` in a signature, binding, or return type glues to the
  trait name (`%Pet`) and no longer opens a spurious top-level declaration that
  split the signature across lines.
- **`nurl_free_count()` runtime primitive.** A symmetric companion to
  `nurl_alloc_count()` (counts every `nurl_free` of a non-NULL pointer), so a
  program can bracket a scope and assert leak-freedom deterministically without a
  sanitizer. Used by the new `trait_owned_ret_no_leak` regression test.

### Fixed

- **Owned-string temporaries from trait-method calls leaked.** A trait method
  returning an owned `s` (e.g. via `nurl_str_cat`) whose result was passed
  straight to another call — `( nurl_print ( label d ) )` — leaked the temporary;
  plain-function composition already freed it. The impl-method dispatch path
  (Group F in `gen_call`) emitted its call and returned **without publishing any
  of the `__last_call_*` return side-channels** the caller reads, so the callee's
  owned-string / borrow / signedness / `??`-propagation markers were all lost —
  not just a leak but a latent borrow double-free and a `u`/`!T E` mis-handling.
  Fixed by factoring the marker propagation into one helper
  (`mem_propagate_call_ret_markers`) shared by both the impl-method and
  regular-call paths, so no dispatch path can silently omit a marker.

## [0.10.7] — 2026-07-01

A **CPU inference + GUI** release. The GPU/ML stack from 0.10.6 gains two big
things: models now run **with no GPU at all** (a CPU backend in `packages/gpu`
that runs the same CUDA-C kernels on the host), and the `yoloe` webcam demo can
draw its live segmentation into a **real X11 window** — or the terminal.

### Added

- **CPU backend for `packages/gpu` (0.1.0 → 0.2.0).** `gpu_open` uses CUDA when
  a device is present and otherwise falls back to a CPU backend that runs the
  *same* CUDA-C kernels on the host: each kernel is wrapped in a small
  CUDA-compatibility shim (`blockIdx`/`threadIdx`/`blockDim`/`gridDim` as
  thread-locals, `__global__` etc. as no-op macros) plus a generated grid-loop,
  compiled by the system C++ compiler, `dlopen`'d, and run with **OpenMP**
  across cores. `gpu_launch`'s `void**` argument array is byte-for-byte what
  CUDA passes, so the neutral surface is unchanged and every caller (`onnx`,
  `objdet`, `yoloe`) gets the fallback for free. `NURL_GPU=cpu` forces it.
  Verified identical CPU vs GPU on the onnx MLP and the full 267-node YOLOE-seg
  forward.
- **Driverless linking.** A program that references `packages/gpu` no longer
  hard-requires libcuda/libnvrtc to load: `nurl.sh` links small stub objects
  (`stdlib/{cuda,nvrtc}_stubs.o`, built by `build.sh`) in place of `-lcuda` /
  `-lnvrtc` when those libraries are absent — the binary links, loads, and
  auto-falls-back to the CPU backend. `NURL_GPU_STUBS=1` forces the stubs to
  build a portable CPU-only binary on a GPU host. `runtime.c` gains one tiny
  generic thunk, `nurl_cpu_launch`, so the backend can call the `dlsym`'d
  kernel entry.
- **X11 GUI-window support.** `build.sh` writes a `runtime.X11` sentinel when
  libX11 is present and `nurl.sh` auto-links `-lX11` only when `@XOpenDisplay`
  appears — the same opt-in-by-symbol pattern as libcuda/libopus, so headless
  programs are unaffected. Used by `packages/yoloe`'s new window preview.
- **`yoloe` — a real webcam segmentation tool.** The `yoloe` command is now a
  flag-driven, self-documenting CLI with three sub-commands — `detect`, `seg`,
  and `cam` — and `cam` shows the **live** segmented feed either in a **real
  X11 window** (full webcam resolution, pure NURL via libX11) or in the
  terminal (area-averaged 24-bit half-blocks, works over SSH). `--boxes` /
  `--mask` pick what to draw, `--frames` bounds the run (omit ⇒ until Ctrl-C),
  `--out` saves frames, `--device` / `--gpu` select the camera / CUDA device.

### Fixed

- **`nurlpkg` `{ path, version }` hybrid dependencies** are published + resolved
  correctly end-to-end (carried over from 0.10.6); the `gpu`/`onnx`/`yoloe`
  packages were republished with the correct dependency edges so a registry
  install resolves the whole chain.

## [0.10.6] — 2026-06-30

A **GPU compute + ML inference** release. NURL gains the ability to run real
neural networks — CNNs, vision-language transformers, and end-to-end object
detection *and instance segmentation* — entirely in pure NURL on the GPU,
through a new stack of registry packages (`gpu` → `onnx` → `objdet` /
`yoloe`). The crown jewel is `yoloe`: promptable open-vocabulary detection
with per-object masks, **live off a webcam**, captured in pure NURL via
Video4Linux2 — no ffmpeg, no OpenCV, no external inference engine. The
toolchain changes here are the thin layer that makes that possible plus a
`nurlpkg` dependency-resolution fix; the heavy lifting lives in the packages.

### Added

- **Typed 4-byte buffer accessors in the runtime.** `stdlib/runtime.c` gains
  `nurl_peek_i32` / `nurl_poke_i32` / `nurl_peek_f32` / `nurl_poke_f32` —
  natural-stride reads/writes for the packed `float32` / `int32` arrays that
  GPU kernels, image data, and binary wire formats use (the 8-byte
  `nurl_peek`/`poke` can't address a 4-byte array at its stride). Pure and
  dependency-free; they ship to every target, no GPU required.
- **Automatic GPU linking, opt-in by symbol.** `nurl.sh` and `build.sh` now
  link `-lcuda` / `-lnvrtc` **only** when a program references `cu*` / `nvrtc*`
  symbols (detected via sentinels). A GPU-less host — or any program that
  never touches the `gpu` package — is completely unaffected; the CUDA
  dependency lives entirely in `packages/gpu`.
- **New registry packages — a pure-NURL GPU/ML stack:**
  - **`gpu` 0.1.0** — backend-neutral GPU compute (`Gpu` / `GpuKernel` /
    `GpuBuffer`: open, compile, alloc, upload/download, launch, sync). One
    backend: CUDA, with kernels written in CUDA-C and compiled to PTX at
    runtime via NVRTC, run over the CUDA Driver API — all bound from pure
    NURL with no `runtime.c` bridge.
  - **`onnx` 0.1.0 → 0.4.0** — run ONNX models on the GPU: a pure-NURL
    protobuf decoder (no protoc) builds an in-memory graph, and a
    GPU-resident executor dispatches each operator to a CUDA-C kernel. Grew
    from MLPs (`Gemm`/`Relu`) to CNNs (`Conv`/`MaxPool`/`BatchNormalization`/
    `LeakyRelu`/N-D tensors) to the transformer set (`LayerNormalization`/
    `Erf`/`Gather`/batched `MatMul`/N-D `Transpose`/`Softmax`) to the
    **segmentation mask-prototype branch** — a new `ConvTranspose` op plus a
    model's second graph output reachable via `rt_output1`. Verified
    end-to-end against onnxruntime at every step.
  - **`objdet` 0.1.0 / 0.2.0** — object detection (tiny-yolov2) from pure
    NURL on the GPU: image I/O, YOLO decode, NMS; matches onnxruntime
    pixel-for-pixel and supports a frame-sequence video mode.
  - **`yoloe` 0.1.0 / 0.2.0** — promptable open-vocabulary detection **and
    instance segmentation**, a NURL port of YOLOE (ICCV 2025). Names the
    classes you want at runtime; the whole YOLOv8/YOLOE network (backbone,
    neck, DFL head, region-text contrastive head) runs on the GPU. The
    MobileCLIP text path is pure NURL too — a 12-layer CLIP text transformer
    (bit-exact vs onnxruntime) and a CLIP byte-level BPE tokenizer
    (byte-identical to open_clip). 0.2.0 adds **per-object masks** and a
    pure-NURL **Video4Linux2** capture path (`open`/`ioctl`/`mmap`, YUYV→RGB)
    for **live segmentation off a webcam** — no ffmpeg, no OpenCV.
  - **`swarm-mcp` 0.3.0 / 0.4.0** — a unified node with composable,
    non-exclusive roles (`--relay` / `--worker` / `--mcp`), `--token`
    cluster security (group-id + HMAC), MCP served over HTTPS JSON-RPC, and
    floating-point (`f64`) distributed compute kernels.
- **Registry renders package READMEs.** The registry Worker now turns a
  published package's README into HTML (Markdown → HTML in TypeScript,
  XSS-safe), including images served straight from the package tarball.

### Fixed

- **`nurlpkg` resolves `{ path, version }` hybrid dependencies correctly.** A
  Cargo-style hybrid dep (a local `path` override that also carries a
  registry `version`) is now (a) **published** with its `version` in the
  registry index — so a downstream consumer can resolve it — and (b)
  **installed** by falling back to the registry version when the local path
  is absent, resolved transitively across the whole dependency tree. Before
  this, publishing such a package dropped the dependency from the index and a
  registry `install` of it silently skipped the dep. This is what lets the
  layered `gpu` ← `onnx` ← `yoloe` packages install from the registry.
- **`onnx` text-encoder forward correctness.** Three real runtime bugs —
  `Softmax` with a negative axis, `Add` mask broadcasting, and an `Engine`
  value-map that wasn't reset between runs — were producing all-`NaN`
  outputs hidden by a NaN-blind comparison. Fixed; the MobileCLIP text
  encoder now matches PyTorch to ~5e-6.
- **Registry README links.** Links that wrap across source lines, and
  monorepo sibling-package references, now render correctly.

## [0.10.5] — 2026-06-29

A **compiler correctness** release: a single codegen fix that stops the
toolchain from overflowing the stack on hot loops.

### Fixed

- **`nurlc` now emits every `alloca` in the function entry block.**
  Previously each `:` binding's stack slot was allocated at its lexical
  position, so a binding inside a loop re-allocated a fresh slot on every
  iteration (LLVM only reclaims allocas at `ret`) — a loop over N items
  leaked N stack slots and eventually overflowed the stack. clang's
  `mem2reg` promoted those slots away and hid the leak, but the released
  toolchain (relinked with the bundled `zig cc -O2 -flto` for
  portability) kept the per-iteration stack growth and crashed. The most
  visible symptom was `nurlpkg publish` segfaulting inside the pure-NURL
  gzip/deflate path while packing a multi-kilobyte tarball. All NURL
  allocas are static-size, so hoisting them to the entry block is the
  canonical LLVM idiom and semantically identical — the slot lifetime is
  already function-wide; the compiler just stops re-issuing it per
  iteration. The bootstrap snapshot (`nurlc_lastgood.{nu,ll}`) was
  refreshed accordingly.

## [0.10.4] — 2026-06-29

A **WebAssembly + self-hosting** release. NURL gains a from-scratch WebAssembly
runtime written entirely in NURL, the compiler now **self-hosts on wasm** — the
compiler compiled to `wasm32-wasi` recompiles its own source to byte-identical
IR — and the `swarm-mcp` engine can compile arbitrary NURL kernels to wasm and
run them across the cluster.

### Added

- **`packages/wasmtime` — a WebAssembly runtime written in pure NURL.** No
  libwasm, no embedded interpreter, no external `wasmtime` binary: it decodes a
  wasm binary (LEB128, every standard section) and interprets the full integer +
  float instruction set — structured control flow (`block`/`loop`/`if`/`else`/
  `br`/`br_if`/`br_table`/`return`), `i32`/`i64` arithmetic / comparison /
  bitwise ops (signed **and** unsigned, rotates, `clz`/`ctz`/`popcnt`,
  sign-extension), `f32`/`f64` ops and every int↔float conversion, linear memory
  (load/store, `memory.size`/`grow`, bulk `memory.copy`/`fill`, the data
  section), globals, tables + `call_indirect`, and the element section. It hosts
  real `wasm32-wasi` command modules via the WASI snapshot-preview1 surface
  (`proc_exit`, `fd_write`, `args_*`/`environ_*`, `clock_time_get`,
  `random_get`) plus a file-descriptor table with **`--dir` preopen** and file
  ops (`path_open`/`fd_read`/`fd_seek`/`fd_write`/`fd_close`/`fd_filestat_get`),
  so a module can read host files. Cross-checked byte-for-byte against the
  reference `wasmtime` and ASan-clean; floats held as IEEE-754 bits via
  `std/floatbits`.
- **NURL self-hosts on WebAssembly.** The compiler compiled to `wasm32-wasi`
  (`nurlc.wasm`) compiles NURL source — up to and including the full compiler
  `nurlc.nu` itself — to IR **byte-identical to the native `nurlc`**, under both
  the reference `wasmtime` and the pure-NURL `packages/wasmtime` runtime above
  (the 2.4 MB / 65530-line self-compile is md5-verified). The borrow-checker
  analysis is skipped for the wasm self-compile (`--no-borrowck`); it emits no
  IR, so the output is identical. Reaching this required the three `wasm32` ABI
  fixes listed under *Fixed*.
- **`packages/swarm-mcp` — an MCP-driven distributed compute engine.** A model
  sets a workload over MCP and the cluster map-reduces it. Two kernel forms:
  `compute_submit` takes a small integer-expression kernel (in `x`, over a
  range, with a `sum`/`product`/`min`/`max`/`count` reduce); `compute_submit_kernel`
  takes an arbitrary **per-element NURL kernel** (`@ kernel i x → i { … }` plus
  any imports/helpers — no `main` needed), which the server wraps into a full
  program, compiles to wasm via the build service, and shards across the live
  workers. `compute_run_wasm` runs an already-compiled `wasm32-wasi` module.
  Tools: `compute_submit` / `compute_submit_kernel` / `compute_run_wasm` /
  `compute_list` / `compute_result`.
- **`packages/swarm` 0.2.0 — real distributed compute workloads.** The
  install-to-join cluster now runs genuine sharded workloads (e.g. prime
  counting and sum-of-squares) across the ring via `dist/job` — `π(10⁶)=78498`
  computed across four workers — not just a membership demo.
- **`std/floatbits` — IEEE-754 bit reinterpretation + binary float I/O.** NURL's
  `#` cast converts a float's *value*; this new module reinterprets its *bit
  pattern* — the operation binary formats need, and previously impossible in the
  stdlib (`bytes_push_float` only writes `%g` text). Backed by a zero-allocation
  runtime bitcast (`memcpy`, correct for NaN/±Inf/subnormals): `f64_to_bits` /
  `bits_to_f64`, `f32_to_bits` / `bits_to_f32`, and explicit-endian binary
  helpers `bytes_push_f64_le/_be` · `bytes_read_f64_le/_be → ?f` (and `f32`
  variants). For serialization (msgpack/protobuf/wasm/audio), float hashing,
  random→float, and the pure-NURL wasm runtime. KAT-tested (`floatbits`).

### Changed

- **`net/relay` frame limit raised from 128 KiB to 16 MiB.** A relayed message
  may now be up to 16 MiB, large enough to forward a compiled wasm compute
  kernel (a NURL→wasm module bundles the runtime, ~250 KB–1 MB) in one frame.
  It is only an upper bound, so small gossip / audio / unicast frames are
  unaffected.

### Fixed

- **Field store into a struct pointer silently miscompiled when the value name
  was a non-parameter local shadowing the field.** `= . t lo lo`, where `lo` is
  an in-scope local that also names a field of `t`'s struct, compiled to a
  value-as-index array store (`t[lo] = lo`, `getelementptr %T, %T* t, i64 %lo`)
  — an out-of-bounds, struct-corrupting write with no diagnostic. The read path
  already let a concrete struct field always win over a same-named variable;
  the store path only did so when the name was a *parameter*. The two are now
  symmetric: a name that is a field of the (non-generic) struct stores into that
  field whether it is a parameter or a local. The value-as-index array store is
  still taken when the name is not a field of the struct — raw pointers, and the
  tparam element types `stdlib/core/vec.nu` writes through (unaffected;
  full bootstrap + corpus green). Regression test `field_store_shadow`.
- **`nurlc.wasm` trapped on the first token compiled — `int`-returning libc
  shim ABI.** The `wasm32` build's shim layer widened every non-pointer libc
  return to `i64`, correct for `size_t` (which `nurlc` declares `i64`) but wrong
  for `int` (`strcmp`/`memcmp`/`atoi`/…, which `nurlc` declares `i32`): a
  `call i32 @__nurl_<fn>_shim` against a `define i64` shim is a wasm
  signature mismatch, so `wasm-ld` replaced the call with a trap stub and the
  compiled `nurlc` trapped on its first `strcmp` (the first lexed token). The
  shim now returns `i32` for `int`-returning functions.
- **`__tok_write` passed a token pointer as `i64` to an `i8*` parameter.** The
  lexer cast each strdup'd token spelling to `# i` (i64) for `__tok_write`'s
  `s` (i8\*) `val` parameter — a no-op on 64-bit, but on `wasm32` (4-byte
  pointers) an `i64`-for-`i8*` signature mismatch that trapped on the first
  token. The spurious cast is removed (the value is a string; `__tok_write`
  already narrows it internally).
- **`wasm32` link dropped functions referenced only through the call-table.**
  NURL closures take function addresses, which become wasm function-table
  indices; `wasm-ld`'s default `--gc-sections` pruned/renumbered the table so a
  stored `call_indirect` index no longer mapped to its function — fine for small
  programs, but `nurlc.wasm` compiling a >150-function program trapped
  (`call_indirect: index out of range`). The wasm link now passes
  `-Wl,--no-gc-sections` to keep the table stable.

## [0.10.3] — 2026-06-28

A **portability + distributed-stack** release. The runtime drops its last
glibc-version-specific symbols so the toolchain builds and links on older-glibc
targets again (notably **Raspberry Pi OS aarch64**), a silent `net/relay`
group-multicast bug is fixed, and the new **`packages/swarm`** package turns the
distributed stack into a compute cluster you join by installing it.

### Fixed

- **Runtime failed to link on older-glibc targets (e.g. Raspberry Pi OS
  aarch64): `undefined symbol: __isoc23_strtoul` / `__isoc23_strtol`.** When the
  runtime is compiled with glibc ≥ 2.38 headers in C23 mode, `strtoul` /
  `strtol` / `atoi` / `scanf` resolve to the versioned symbols
  `__isoc23_strtoul` etc., which are baked into the shipped LTO runtime bitcode
  and then undefined when linked against a target with an older glibc. The
  runtime no longer calls any of them: a hand-rolled decimal parser
  (`nurl__parse_ul`) replaces `strtoul`/`atoi`, and `nurl_read_int` is rebuilt
  on `getchar`/`ungetc` instead of `scanf`. The runtime bitcode now references
  none of the `__isoc23_*` symbols, so it links cleanly across every glibc/musl
  version and target (verified by cross-linking for aarch64 against glibc 2.28).
- **`net/relay` group multicast silently dropped any non-32-byte group id.**
  `GJOIN`/`GLEAVE` carried the group id as a raw, variable-length body, but
  `GSEND` reused the fixed 32-byte pubkey split — so a group id that was not
  exactly 32 bytes was mis-parsed on the server (aliasing the payload) and the
  fanout was silently skipped. Group sends are now length-delimited
  (`[gidlen:2][gid][payload]`) via `relay_gsend_gid` / `relay_gsend_payload`, so
  a group id of any length round-trips. Regression test added in
  `relay_codec` (a 5-byte gid). Existing 32-byte users (`replicated_counter`,
  `pttvoice`) are unaffected.

### Added

- **`net/relay` server verbose mode.** `relay_server_set_verbose(rs, 1)` (and a
  new `RelayServer.verbose` field) logs each peer connect/disconnect as
  `relay: + peer <id>` / `relay: - peer <id>`. `packages/swarm`'s relay exposes
  it as `swarm relay <host> <port> --v` / `--verbose`, so cluster membership is
  visible as workers come and go.
- **`packages/swarm` — a distributed compute cluster you join by installing it.**
  `nurlpkg install swarm` then `swarm worker <relay> <port>` makes a machine a
  live compute node: it announces itself over the relay group (HELLO census),
  every node folds it into the consistent-hash ring, and it takes its share of
  work. `swarm submit … primes <lo> <hi>` / `sumsq <lo> <hi>` shards a real
  numeric workload across the live workers (by key, via `dist/ring` + `dist/job`)
  and sums the partial results — verified live (π(10⁶) = 78498) and by an
  ASan-clean offline suite that pins exact sharding.

## [0.10.2] — 2026-06-28

A **language-maturity** release. The static trait system reaches v1.0
(coherence, supertraits, associated types, a dyn-dispatch seam); `Result` gains
a by-value representation; the toolchain gains first-class **FreeBSD** support
(now a CI gate) and a local **MCP server** that exposes the compiler to LLM
agents. The standard library absorbs argument parsing, letting the registry
shed its `argz` and `tls` packages.

### Added

- **Trait system v1.0.** Sound bare-name method dispatch (coherence:
  `method##type` registered once, position-idempotent re-scan, `i`/`i64`
  collisions resolved); **supertraits** (`% Sub : Super`, whole-program-enforced
  and transitive); **associated types** (`type Item` in a trait, bound per impl
  and substituted into defaults); and a recorded **dyn-dispatch vtable seam**.
  Documented in spec §4.9 and the EBNF.
- **`std/utf8` — a validating UTF-8 codepoint layer** over NURL's byte strings
  (rejects overlong / surrogate / out-of-range encodings, with U+FFFD recovery):
  `utf8_valid` / `utf8_len` / `utf8_nth` / `codepoints` / `encode_cp` /
  `utf8_substr` / … The byte-level `core/string` stays the fast default; the
  codepoint layer is opt-in.
- **Send check.** Capturing a non-atomic `Rc` in a `thread_spawn` closure is now
  a **compile error** (use `Arc`), catching that data race at compile time.
- **`nurl-mcp` — a local MCP server for the toolchain** (registry package:
  `nurlpkg install nurl-mcp`). Exposes the *locally installed* compiler to an
  LLM agent over the Model Context Protocol so it can build / run / type-check /
  format NURL against the host's real files and read the installed stdlib. Stdio
  by default; an optional **token-authenticated HTTP** transport gates code
  execution behind `--allow-run` and refuses a non-loopback bind without
  `--token`. The LLM-facing counterpart of `nurl-lsp`.
- **FreeBSD support.** Documented as a first-class **host platform** (the
  toolchain binaries are libc-only and the wrappers POSIX `sh`); CI now builds,
  bootstraps, and runs the full test corpus on a real **FreeBSD 14 VM** as a
  hard gate. `docs/PLATFORMS.md` is split into codegen targets vs. host
  platforms, and `docs/BUILDING.md` documents every CI gate.

### Changed

- **`Result` `!T E` now lowers to `{ i1, T, E }`.** The Ok payload rides field 1
  and the Err payload field 2, both **by value**, mirroring `?T` → `{ i1, T }`.
  A multi-field-struct success payload is no longer heap-boxed — the Ok path
  emits no `nurl_alloc`. Note: direct numeric access to the *error* payload
  moves from `. r 1` to `. r 2` (`??` / `\` matching constructs are unaffected).
- **Argument parsing is now a stdlib facility, `std/args`** (flags, value
  options, clustered shorts, `--`, positionals, an auto-generated `--help`); the
  registry CLIs (`nq`, `md2html`, `chart`, `iforest`) migrated onto it.
- **`install-toolchain` now installs `nurlfmt`**, and its sourceable `env` file
  is POSIX-`sh`-safe — the old `${BASH_SOURCE[0]}` form aborted FreeBSD / Alpine
  `/bin/sh` with "Bad substitution". The release relinks `nurlfmt` against the
  old-glibc floor like the other shipped binaries.

### Removed

- The **`tls`** registry package — pure-NURL TLS now lives in the stdlib, and
  `psql` / `redis` depend on it directly.
- The **`argz`** and **`argz-demo`** packages — argument parsing is now
  `std/args`.

## [0.10.1] — 2026-06-27

A **security-hardening** release for the pure-NURL cryptography and TLS stack
introduced in 0.10.0. A full adversarial audit of the OpenSSL-replacement code
(documented in the new `docs/CRYPTO.md`) drove fixes across certificate-chain
validation, the TLS 1.3 protocol guards, and the side-channel posture of every
asymmetric and symmetric primitive. The elliptic-curve secret path is now
**constant-time including operand timing** via a dedicated fixed-limb P-256
field, and the certificate chain now enforces Basic Constraints — closing an
"any leaf certificate can sign for any host" authentication bypass.

### Security

- **Certificate-chain policy hardened (X.509).** The chain now enforces
  BasicConstraints `cA:TRUE` on every signing certificate — closing a complete
  authentication bypass where any leaf certificate could mint a forged cert for
  any host (the classic Moxie Marlinspike break; `is_ca` was parsed but never
  read, and was in fact written to a by-value copy and discarded). Adds
  keyUsage `keyCertSign` / EKU `serverAuth` enforcement, `pathLenConstraint`,
  embedded-NUL dNSName rejection, tightened wildcard matching (`*.com` /
  `*foo.com` now rejected), iPAddress-SAN matching, a ≥2048-bit RSA-key floor,
  a presented-chain length cap, and issuer/subject DN name-chaining.
- **TLS 1.3 protocol guards.** Reject an all-zero X25519 / P-256 ECDHE shared
  secret (RFC 8446 §7.4.2) on both client and server; check the §4.1.3
  downgrade sentinel when a 1.3-capable client negotiates 1.2; fail closed on a
  CSPRNG failure; constant-time TLS 1.2 server-Finished comparison.
- **Constant-time symmetric primitives.** AES computes its S-box in constant
  time (`Affine(x⁻¹ in GF(2⁸))`, no secret-indexed table — closing the
  cache-timing key-recovery leak); GHASH is branchless; the GCM and
  ChaCha20-Poly1305 entry points validate key/nonce lengths and enforce
  plaintext caps. Tag comparisons were already constant-time.
- **Constant-time asymmetric primitives.** `bigint_modpow` is now a Montgomery
  powering ladder with a uniform square-multiply trace independent of the
  secret exponent. The P-256 secret scalar multiply (ECDSA nonce, ECDHE) runs
  on a new dedicated **fixed-limb constant-time GF(p256) field**
  (`std/p256_field`), so it is constant-time *including operand timing*. RSA
  private-key signing adds base blinding (plus a signature range check and the
  PSS maskedDB check). Ed25519 verify rejects non-canonical encodings and
  `S ≥ L` (malleability); ECDSA verify and P-256 ECDH validate that peer
  points are on-curve (invalid-curve guard).
- **Side-channel scope, stated honestly** (`docs/CRYPTO.md`): on the
  timing/cache axis the EC and symmetric primitives are constant-time including
  operand timing, and RSA's residual operand timing is covered by base
  blinding. Physical **power/EM (DPA/template) side-channels are out of scope**
  for any pure-software stack. Revocation (OCSP/CRL) and X.509 name constraints
  are not checked.

### Added

- **`std/p256_field.nu`** — a dedicated fixed-16-limb constant-time GF(p256)
  field (Montgomery CIOS multiply, conditional-±p add/sub, Fermat inverse) and
  constant-time P-256 point arithmetic via the Renes–Costello–Batina complete
  addition formula. Cross-checked against the bigint reference (2000 cases) and
  Python `cryptography` (500/300 cases); new corpus test `p256_ct_field`.
- **`docs/CRYPTO.md`** — documents the pure-NURL crypto/TLS stack: implemented
  primitives, the side-channel taxonomy, TLS 1.3 controls, X.509 verification,
  and the soundness contract. Linked from the README.
- `bigint_modinv` (modular inverse) and `bigint_cselect` (constant-time select)
  in `std/bigint.nu`.

### Changed

- `tls_accept_rsa` now takes the RSA public exponent (argument order `n e d`)
  so the server's CertificateVerify signature can be base-blinded; `net.nu`'s
  TLS listener threads the exponent through. Other public TLS APIs are
  unchanged.

### Fixed

- The CHANGELOG's DEFLATE interop claim is now "round-trip / KAT verified"
  rather than "byte-for-byte" — a greedy LZ77 encoder produces a valid but not
  bit-identical stream versus zlib.

## [0.10.0] — 2026-06-26

The **self-sufficiency** release. NURL no longer depends on any third-party
C library at its core: the entire external-library surface — `libcurl`,
`libssl`/`libcrypto`, `libpq`, and `libz` — has been removed from the
runtime and replaced with pure-NURL implementations in the standard library.
A default `./build.sh` now links **`libc` only** (plus `libm`). The same
self-contained stdlib provides TLS 1.3 (client *and* server), cryptography,
HTTP/1.1, and DEFLATE/gzip/zlib — written in NURL, verified against the
libraries they replace by known-answer vectors and round-trip interop (our
DEFLATE output is a valid, if not byte-identical, stream — a greedy LZ77
encoder compresses differently from zlib), and clean under AddressSanitizer.

Alongside the dependency purge: a new pure-NURL `redis` client, a compiler
type-checking sweep that converts several silent miscompiles into clear
compile-time errors, and an `O(n²) → O(1)` symbol-table speedup that keeps
whole-program compilation fast now that HTTP pulls in the full TLS+crypto
closure.

**Toolchain requirement:** the minimum supported compiler is now
**clang / LLVM 15+** (was 14+). LLVM 15 emits opaque-pointer IR by default,
so the build no longer needs the `-opaque-pointers` shim for older clangs.

### Added

- **Pure-NURL TLS 1.3 client in the stdlib** (`std/tls.nu`,
  `std/tls_verify.nu`) — promoted from the `tls` package so stdlib HTTP/TLS
  consumers (`anthropic`, `mcp_http`/`mcp_client`, `cluster`, `http_json`,
  `http2_client`) can build on it. The `tls` package is now a thin
  re-export facade for backward compatibility. (§8 P0)
- **Pure-NURL TLS 1.3 server** (`std/tls_server.nu`) — full
  ServerHello / EncryptedExtensions / Certificate /
  CertificateVerify (ECDSA P-256) / Finished handshake over `tcp_accept`,
  EC P-256 private-key PEM loading, ALPN (`h2`) negotiation, and an
  in-place STARTTLS upgrade. `net.nu`'s `TcpConn` is now polymorphic
  (plain / TLS-client / TLS-server) so `http_server` gets clean HTTPS.
  (§8 P4)
- **RSA leaf-certificate support for the pure TLS server** — RSA-PSS
  signing (`rsa_pss_sign_sha256`), PKCS#1/#8 key parsing
  (`rsa_priv_from_pem`), cert-chain transmission, and `tls_accept_rsa`;
  `net.nu` auto-detects EC vs RSA and frames `fullchain.pem`. (PR #289)
- **Pure-NURL crypto** filling the gaps left by the OpenSSL removal:
  AES-256-GCM (`std/aes_gcm.nu`), **Ed25519** sign/verify
  (`std/ed25519.nu`, a TweetNaCl port reusing the x25519 field
  arithmetic), **scrypt** (`std/scrypt.nu`, RFC 7914), PBKDF2-HMAC-SHA512,
  and ECDSA P-256 signing (RFC 6979). All KAT-verified, ASan/LSan-clean.
  (§8 P1/P2/P4)
- **Pure-NURL HTTP/1.1 client** (`ext/http_pure.nu`) over the stdlib TLS —
  one transport+parser driving both the buffered `http_request`/`http_get`
  family and the pull-based `http_stream_*` API: incremental chunked
  decoder (live SSE streaming), Content-Length, redirects (301/302/303/
  307/308), all methods, binary bodies. (§8 P3)
- **Pure-NURL DEFLATE/inflate/gzip/zlib** (`std/deflate.nu`) — RFC 1951
  inflate (puff.c port) + greedy-LZ77 deflate, `crc32`/`adler32`, and
  streaming `inflate_stream` / `deflate_block_dict` for permessage-deflate
  context takeover. `ext/compress.nu` is rewritten over it
  (`zlib_*`/`gzip_*`/`raw_deflate_*`). (§8 P6)
- **`redis` package** — a pure-NURL Redis client speaking RESP2 over a
  libc TCP socket, with optional TLS (`rediss://`) via the pure `tls`
  package, so the binary links `libc` only. Flat-arena RESP2 codec
  (`src/resp.nu`), a typed surface (strings/lists/hashes/sets, `INCR`/
  `EXPIRE`/`TTL`/`KEYS`, full pub/sub), and a `redis-cli`-style CLI with a
  REPL and `SUBSCRIBE`/`PSUBSCRIBE` streaming. Validated live against
  redis:7 (20/20, ASan-clean).

### Changed

- **`ext/crypto.nu` is now a thin facade** over the pure crypto modules —
  the OpenSSL EVP FFI layer (~35 bindings) is gone; the public API and
  `CryptoErr`/`CryptoKeypair` types are unchanged, so `noise`/`session`/
  `jwt`/`http_jwt` consumers compile untouched. (§8 P2)
- **All client-TLS consumers** (`mqtt`, `websocket`, `http2`, `smtp`) now
  route through `net.nu`'s pure `tcp_connect_tls[_alpn]` / `tcp_starttls`
  instead of the OpenSSL-backed runtime helpers. (§8 P4)
- **Compiler: the symbol table is hash-indexed** (FNV-1a buckets) —
  `nurl_sym_get` was a backward linear scan over an append-only table, so
  whole-program compilation was `O(n²)`. Now `O(1)` average lookups with
  identical semantics (byte-identical IR, bootstrap fixed point holds).
  Effect: compiling `examples/http_basic.nu` 11.0s → 0.59s, the examples
  sweep 8m11s → 25s, the corpus stage 7m13s → 1m11s.
- **Minimum toolchain is clang / LLVM 15+** (was 14+). The build scripts
  reject older clangs with install guidance; the `-opaque-pointers` shim
  for clang 13/14 is removed.

### Removed

- **`libcurl`** — the entire C HTTP-client backend (libcurl bridge +
  WinHTTP + stubs, ~850 lines) is deleted from `runtime.c`; `-lcurl` and
  its detection are gone from the build. (§8 P3)
- **`libssl` / `libcrypto`** — all SSL code (the dlopen vtable + ~250
  `SSL_*` call sites, −801 lines) is deleted from `runtime.c`; `-lssl
  -lcrypto` and `NURL_HAVE_OPENSSL` are gone from the build. (§8 P4)
- **`libpq`** — `ext/postgres.nu` (47 FFI bindings) and its examples/test
  are removed; the pure-NURL `psql` package is the replacement. (§8 P5)
- **`libz`** — `nurl_z_*` + the `z_stream` ABI are deleted from
  `runtime.c`; `-lz` and `NURL_HAVE_ZLIB` are gone from the build. (§8 P6)
- Net effect: the default `./build.sh` produces binaries whose `NEEDED` is
  `libc.so.6` only (plus `libm`). `libzstd` and `libsqlite3` remain
  **optional**, behind runtime sentinels and `-Wl,--as-needed`, so a
  program that does not use them still links `libc` only. (§8 P7)

### Fixed

- **Compiler type-check sweep** — a focused pass that turns a class of
  "`nurlc` accepts → `clang` rejects late (or silently miscompiles)" gaps
  into clear compile-time errors. Diagnostic-only: IR for valid programs is
  byte-identical and the bootstrap fixed point holds.
  - **`String` vs `s` (`i8*`) argument mismatch** — passing a raw C-string
    where a `String` parameter is declared (or vice versa) was silent
    wild-pointer UB (it surfaced as a SEGV in `net.nu`'s cert-chain code).
    Now rejected at the call site with a fix-it (`string_data` / `string_from`).
  - **Wrong named struct by value** — passing a `B` where an `A` is
    declared by value type-checked clean and let the callee read the
    foreign struct's leading fields. Now rejected at the call site, in
    return position (`^ b` from a `→ A` fn), and in struct literals (bad
    field type or too many fields).
  - **`^ value` from a `→ v` (void) function** — silently lowered to
    `ret i64 …` out of a `void` LLVM function. Now a clear error, and a
    **bare `^`** is supported as an early return in void functions.
  - **Reassignment and field stores** (`= name v`, `= . obj field v`) — a
    float-into-`i`, wrong-struct, or `String`-vs-`s` store emitted a
    type-mismatched `store` that only clang caught. Now rejected (integer
    width / signedness / pointer-stash coercions stay legal).
  - **`!b` / `?b` bool payloads** in result/option matches were extracted
    as `i64` but used as `i1` (`clang` rejected the IR); a `b` branch now
    truncates the payload back to `i1`.
- **WASM build of the runtime.** `nurl_read_password` (added in 0.9.19)
  included `<termios.h>` on every non-Windows target, which broke the
  `wasm32-wasi` compile (no termios) used by the playground / API image. It
  now uses a WASI fallback branch (echoed read) alongside the POSIX termios
  and Windows console paths; native behaviour is unchanged.

## [0.9.19] — 2026-06-25

A usability pass on the pure-NURL `psql` client: it gains a real psql-style
front end — aligned result tables, a multi-line REPL, and backslash
meta-commands — and now **prompts for a password** when the server requires
one, so it connects to password-protected servers out of the box instead of
failing with an opaque error. The cross-platform hidden password entry is
provided by a new runtime helper, `nurl_read_password`.

### Added

- **Runtime: `nurl_read_password`** — prompt on stderr and read a line from
  the terminal with echo disabled (termios on POSIX, `SetConsoleMode` on
  Windows), restoring the prior console state. The cross-platform home for
  password entry, so packages need not declare platform-specific console
  symbols themselves.

### Changed

- **`psql`: prompt for a password when the server requires one.** Like the
  real `psql`, it now reads the password interactively (echo disabled) when
  the server requests authentication and neither `$PGPASSWORD` nor a URL
  password was supplied — instead of sending an empty password and failing
  with `PgServerError`. Trust-authenticated servers are still connected
  without a prompt.
- **`psql`: a `--help` / `-?` flag.** Bare `psql` again attempts a default
  (localhost) connection like other psql clients; only an explicit `--help`
  prints usage.
- **`psql` package — a proper psql-style front end.** The command now
  renders results as aligned tables (numeric columns right-justified, NULLs
  blank, an `(N rows)` footer), runs a multi-line REPL that accumulates a
  statement until its `;` terminator, shows prompts and a banner only on a
  terminal, and supports backslash meta-commands (`\dt`, `\d TABLE`, `\dn`,
  `\l`, `\du`, `\conninfo`, `\?`, `\q`). It captures the server version and
  the connection identity for the banner and `\conninfo` (which reports
  whether the link is TLS-encrypted). All of this stays pure-NURL — the
  binary still links `libc` only.

### Fixed

- **`psql`: a per-query memory leak.** Each `pg_query` overwrote the
  result's command-tag string without freeing the previous one, leaking one
  allocation per statement over a long session. The REPL is now free of
  per-operation leaks.
- **`psql`: a connection leak on authentication failure.** `pg_connect`
  returned the error without closing the socket or freeing the connection;
  it now closes on the failure path (which the password-retry flow relies
  on).

## [0.9.18] — 2026-06-24

Portability fixes surfaced by real-world installs of the v0.9.17 toolchain:
a program built on a non-x86_64 release could fail to link against OpenSSL,
and the pure-NURL TLS client could not reach TLS-1.2-over-P-256 servers.

### Fixed

- **Every binary now links `libc`-only on every platform — OpenSSL is
  loaded at runtime via `dlopen`.** The shipped `runtime.o` is built with
  OpenSSL, so it referenced `SSL_*` / `X509_*` / `CRYPTO_*`. A program that
  doesn't use runtime TLS only linked `libc`-only if the linker dead-stripped
  those references — which clang/lld LTO does on x86_64 but the bundled-zig
  portable builds do not, so `nurlpkg install` of any `net.nu`-importing
  package (e.g. `tls`) failed on `linux-arm64-glibc` with dozens of
  `undefined symbol: SSL_new / TLS_server_method / …`. OpenSSL is now
  resolved entirely through `dlopen`/`dlsym`, so `runtime.o` carries **zero**
  link-time references to libssl/libcrypto: every program links `libc`-only
  regardless of dead-code elimination, and libssl is loaded lazily the first
  time a TLS connection is created (its absence becomes a clean
  `TLS_CTX_INIT` error rather than a link failure). On Linux the link adds
  `-ldl` (`dlopen` lives in `libdl` below glibc 2.34; `--as-needed` drops it
  where unused); FreeBSD/macOS keep `dlopen` in libc, and Windows is
  unaffected (it uses WinHTTP, not OpenSSL).
- **Pure-NURL TLS reaches TLS-1.2 servers that use P-256 key exchange.** The
  TLS 1.2 fallback only did X25519 ECDHE, so a TLS-1.2 server negotiating
  ECDHE over `prime256v1` (the OpenSSL default `ssl_ecdh_curve`) failed with
  `TlsHandshake`. The 1.2 handshake now reads the `named_curve` from the
  `ServerKeyExchange` and does P-256 ECDHE as well, matching the TLS 1.3
  path. (`tls` package republished as 0.1.1.)

## [0.9.17] — 2026-06-24

A complete **pure-NURL cryptography and TLS stack**, and on top of it a
**TLS client** and a **PostgreSQL client** that need nothing installed on
the target — no OpenSSL, no libpq. Every primitive is implemented from
scratch in NURL and validated against its RFC/NIST known-answer vectors;
the resulting clients link `libc` only. Also ships the `chart`
data-visualisation package and makes the runtime's `libssl` an optional
dependency.

### Added

- **`chart` package** — terminal data-visualisation (sparklines, bar
  charts, histograms, line plots) as both a CLI and a reusable library.
- **Pure-NURL cryptography** in `stdlib/std/`, each validated against its
  RFC/NIST known-answer vectors and ASan-clean:
  - **X25519** key exchange (RFC 7748) — `x25519.nu`.
  - **ChaCha20-Poly1305** AEAD (RFC 8439) — `chacha20poly1305.nu`.
  - **HKDF** + TLS 1.3 key-schedule helpers (RFC 5869 / RFC 8446 §7.1) —
    `hkdf.nu`.
  - **RSA** signature verification — PKCS#1 v1.5 and PSS — plus bigint
    `modpow` / `from_bytes_be` / `to_bytes_be` — `rsa.nu`, `bigint.nu`.
  - **ECDSA** verification on NIST **P-256** and **P-384** — `ecdsa_p256.nu`.
  - **AES-128-GCM** AEAD (NIST SP 800-38D) — `aes_gcm.nu`.
  - **X.509 / DER** certificate parser (TBS, signature algorithm, SPKI,
    validity, SAN, CA flag) with RFC 6125 hostname matching — `x509.nu`.
  - **PBKDF2-HMAC-SHA-256** (RFC 8018) — `pbkdf2.nu`.
  - **P-256 ECDH** (`p256_ecdh_keygen` / `p256_ecdh_shared`) — `ecdsa_p256.nu`.
- **`tls` package — a pure-NURL TLS 1.3 client (RFC 8446) with TLS 1.2
  fallback.** No OpenSSL and no FFI beyond the libc TCP socket. Negotiates
  ChaCha20-Poly1305 and AES-128-GCM over **X25519 and NIST P-256** key
  exchange. **`verify-full` by default**: the CertificateVerify signature,
  the certificate chain up to the system trust store, the validity window
  and the hostname are all checked (`TlsBadCert` otherwise). `tls_attach`
  runs the handshake over an already-connected socket for STARTTLS-style
  upgrades. Ships a `tlsget` HTTPS CLI. Verified live against example.com,
  google.com and cloudflare.com.
- **`psql` package — a pure-NURL PostgreSQL client.** The version-3 wire
  protocol, authentication (trust / cleartext / MD5 / **SCRAM-SHA-256**)
  and an optional **TLS** transport over the pure-NURL stack — **no libpq,
  no OpenSSL**. A secure, authenticated connection works on a host with
  nothing installed; the produced binary's `NEEDED` is `libc` only.
  Installable with `nurlpkg install psql`; usable as a library
  (`pg_connect` / `pg_query`). Verified against a live PostgreSQL 16.

### Changed

- **Importer-relative import resolution.** A `$`-import now resolves
  relative to the importing file first (then the working directory, then
  `$NURL_STDLIB`), so a multi-file package can reference its own modules by
  bare name and build identically standalone, from the monorepo, and as a
  `deps/<name>` dependency. Purely additive — the self-host bootstrap is
  byte-identical.
- **`libssl` is now an optional runtime dependency.** The OpenSSL hot-path
  symbols (`SSL_read` / `SSL_write` / …) are routed through a
  lazily-installed, `volatile` function-pointer vtable, so a program that
  never opens a runtime OpenSSL connection — a pure-NURL-TLS client or a
  plaintext-TCP program — links `libc` only. (`volatile` is required:
  without it, full LTO constant-folds the addresses back into the live
  readers and re-pins `libssl`.) A program that does use runtime TLS
  re-links `libssl` correctly.
- **The compiler dedupes FFI `declare`s by symbol name.** Two imported
  modules may legitimately declare the same libc/runtime extern (e.g.
  `nurl_rand_fill` in both `std/random.nu` and the `tls` package); the
  duplicate IR line is now suppressed instead of failing the build with
  LLVM's "invalid redefinition of function". Generalises the existing
  prelude-symbol skip; purely additive — only fires when a duplicate would
  otherwise error, so the bootstrap is byte-identical.

### Fixed

- **Fiber-scheduler use-after-free on yield.** `nurl_fiber_yield` pushed
  the fiber onto the run queue *before* `swapcontext` returned, so another
  worker could steal, run and free it while the worker loop still read
  `f->state`. The push moved out of `nurl_fiber_yield` into the worker
  loop's runnable branch, after the context is saved. Surfaced
  intermittently by the sanitized test suite (`async_chan`); 0 failures
  under stress after the fix.

## [0.9.16] — 2026-06-23

Makes the Windows toolchain actually usable. v0.9.15 shipped a Windows
archive that installed but couldn't build anything; this release makes it
self-contained and fixes the toolchain bugs that surfaced behind it.

### Fixed

- **Windows toolchain is now self-contained.** The shipped `runtime.o` is
  built with `-DNURL_HAVE_ZLIB`, so it references zlib and EVERY program link
  needs it — but `runtime.winlibs` recorded the CI build machine's absolute
  vcpkg path (`C:\vcpkg\…\zs.lib`), so on a user's box every
  `nurlpkg install`/build died with `lld-link: could not open 'zs.lib'`.
  `build.bat` now copies the resolved static libs into `stdlib\winlib\` and
  records a relocatable fragment that `nurl.bat` resolves against the install
  prefix — the toolchain links against its own bundled zlib/zstd with no
  vcpkg on the box.
- **`nurlpkg install` on Windows.** nurlpkg copied the built binary from
  `pkgdir/.nurl-bin`, but the Windows driver emits `.nurl-bin.exe`, so the
  copy silently failed with `failed to install binary`. Fixed by appending
  `.exe` on Windows.
- **FFI build-time sentinel resolves like a `$`-import.** `__ffi_lib_check`
  looked for `stdlib/runtime.<lib>` relative to the current directory, so a
  program importing `stdlib/ext/compress.nu` failed to compile from any
  directory other than the stdlib tree with a bogus "no build-time sentinel"
  error. It now resolves CWD-first then `$NURL_STDLIB`, matching how
  `$`-imports resolve — so an installed toolchain finds its shipped sentinel
  from anywhere. (Control-flow only; the self-host bootstrap is unaffected.)
- **`nurlc --version` / `nurlpkg --version` on Windows** reported `unknown`:
  `build.bat` never generated `stdlib/nurl_version_gen.h`. Added
  `tools/version.bat` (Windows counterpart of `tools/version.sh`) and wired
  it into `build.bat`, so the real version is baked into `runtime.o`.

### Added

- **Windows PowerShell one-line install** on the website install card
  (`irm https://nurl-lang.org/install.ps1 | iex`), alongside the Linux /
  FreeBSD `curl | sh` command.

## [0.9.15] — 2026-06-23

### Added

- **Prebuilt Windows toolchain.** The release pipeline now publishes
  `nurl-<tag>-windows-x86_64.zip`, built natively on `windows-latest` in CI, so
  the one-line installer works on Windows out of the box
  (`irm https://nurl-lang.org/install.ps1 | iex`). The website install card
  gains a labelled Windows PowerShell one-liner next to the Linux / FreeBSD
  `curl | sh` command. The Windows release job is no longer best-effort — with
  the build fixed below it drops `continue-on-error`, so a future Windows break
  fails the run instead of being silently swallowed.

### Fixed

- **Windows release build (issue #229).** `build.bat` wrote the `-lzlib` link
  fragment whenever `zlib.h` was present, without checking that a matching
  `.lib` actually existed — so `nurlpkg` failed to link with
  `LNK1181: cannot open input file 'zlib.lib'`. The vcpkg zlib static-lib name
  is version-dependent (1.3.1 → `zlib.lib`, but 1.3.2 adopted zlib's new CMake
  and ships `zs.lib`, whose `zlib.pc` is rewritten `-lz` → `-lzs`), which is why
  the build passed on local boxes yet only broke in CI. `build.bat` now probes
  the lib directory for the actual file, derives the `-l<name>` from it, and
  enables zlib only when a linkable lib is present (same name probe for zstd).

## [0.9.14] — 2026-06-23

### Added

- **Prebuilt FreeBSD toolchain.** The release pipeline now publishes
  `nurl-<tag>-freebsd-x86_64.tar.gz`, built on FreeBSD 14 in CI, so the
  one-line installer works on FreeBSD out of the box
  (`curl -fsSL https://nurl-lang.org/install.sh | sh`). The shipped binaries
  depend on `libc.so.7` only; FreeBSD's base clang drives `nurlpkg install`,
  so no compiler is bundled. `get-nurl.sh` detects FreeBSD via `uname -s`.
  Validated end-to-end on real hardware: `nurlpkg install argz-demo &&
  argz-demo --shout hi`.
- **FreeBSD CI.** A FreeBSD VM job builds the compiler, checks the
  self-hosting fixed point, and runs the test corpus on genuine FreeBSD — the
  gate that caught the two FreeBSD bugs fixed below.
- **`nurlc --version` / `nurlpkg --version` / `nurl --version`.** The version
  is derived at build time by `tools/version.sh` (`git describe` → `v0.9.14`
  on a release tag, `v0.9.13-2-gabc-dirty` on a dev checkout; falls back to
  the top `CHANGELOG.md` entry for a git-less source tree) and baked into
  `runtime.o` via a generated, git-ignored header (`stdlib/nurl_version_gen.h`).
  Nothing is hardcoded, and it flows in automatically both in releases and
  local builds. Because the string lives in `runtime.o` and not in
  `nurlc.nu`'s IR, the self-hosting fixed point and the committed bootstrap
  snapshot are unaffected by a version bump.

### Fixed

- **The installed toolchain no longer requires bash.** The shipped wrapper
  scripts (`nurl.sh` and the `nurl` / `nurlc` / `nurlpkg` shims) were
  `#!/usr/bin/env bash`, so on a stock FreeBSD / Alpine / busybox box — where
  the binaries are libc-only but bash is absent — the first build died with
  `env: bash: No such file or directory`. They are now POSIX `sh`, validated
  under dash on Linux and end-to-end on a bash-less FreeBSD 14.3 box.
- **Async fibers run on FreeBSD.** The M:N stackful-fiber runtime was gated to
  glibc/macOS, so on FreeBSD (which has full `ucontext`) it silently fell back
  to a no-op stub and fibers never ran. Now enabled on
  FreeBSD / NetBSD / DragonFly.
- **Empty URL is `HttpInvalidUrl` on a no-libcurl build** (was `HttpOther`),
  matching the libcurl and WinHTTP backends — input validation that no longer
  depends on which HTTP backend is compiled in.
- **`z_stream` ABI helpers decoupled from the zlib build flag**, so a runtime
  linked against libz without `zlib.h` at compile time still reports the
  correct struct size (an ABI replica pinned by `_Static_assert`).
- **Test/example harness portability.** `run_tests.sh` no longer uses GNU
  `sed -i` (mis-parsed by BSD sed); FFI-dependent tests and examples now
  self-skip when their optional library (sqlite3 / libpq / …) is absent
  instead of failing the suite.

### Changed

- **Setup no longer needs `source ~/.nurl/env`.** The shims self-locate the
  stdlib, so `export PATH="$HOME/.nurl/bin:$PATH"` is the whole setup and works
  in any shell. The website one-line install is updated to match and gains a
  Copy button.

## [0.9.13] — 2026-06-23

A one-line follow-up to v0.9.12 that makes the bundled-zig build actually
work on a fresh box.

### Fixed

- **A failed feature-library probe no longer aborts the build.** v0.9.12
  installed and ran on a Raspberry Pi 4 / ODROID, but any build — including
  `nurlpkg install <tool>` — died with a bare `compile failed:`. The
  feature-lib availability probe ended each check with
  `probe && EXTRA_LIBS+=(…)`, so a *failed* probe made the helper return
  non-zero and the build's `set -e` aborted at the first unavailable
  library. A fresh box typically has the runtime `libcurl.so.4` but not the
  `-dev` `libcurl.so` linker symlink, so `-lcurl` (and openssl/sqlite/pq/
  zstd) won't link and every probe failed — killing the build before the
  link step. The probe now uses an explicit `if` and is total, so an
  unavailable library is simply skipped. Verified on a real Raspberry Pi 4
  (glibc 2.31) and ODROID: `nurlpkg install argz-demo && argz-demo --shout
  hi` → `HELLO, HI!`.

## [0.9.12] — 2026-06-23

The "bombproof install" release: the toolchain now installs **and builds**
on old or minimal Linux boxes — a fresh Raspberry Pi / ODROID can run the
`curl … | sh` one-liner and `nurlpkg install <tool>` straight through,
with no system compiler and no surprise library requirements.

### Added

- **Bundled `zig` build backend.** The archive ships a self-contained
  `zig`; `nurl.sh` uses `zig cc` to lower nurlc's LLVM IR to a native
  binary. zig carries its own modern LLVM (so the opaque-pointer IR just
  parses), its own `lld` linker, and libc headers — so **building a program
  (and `nurlpkg install`) needs no system clang at all** and is immune to
  the box's LLVM version. Falls back to a system clang (with
  `-opaque-pointers` on clang 13/14) when no bundled zig is present.

### Fixed

- **The shipped binaries run on old distros.** `nurlc`/`nurlpkg` were built
  on a glibc-2.39 runner and failed to start on e.g. Raspberry Pi OS
  bullseye (glibc 2.31) with `version 'GLIBC_2.34' not found`. They are now
  relinked with the bundled zig against an old glibc floor
  (`tools/relink-toolchain-portable.sh`), landing at **GLIBC_2.25** — which
  covers the Pi and essentially every Linux since ~2017.
- **Feature libraries are linked only when available.** `nurl.sh` probes
  each back-end library (libcurl / OpenSSL / sqlite3 / libpq / zlib / zstd)
  and links it only if it is present on the box; under LTO + `--as-needed`
  an unused one is dropped anyway. A feature-free program — the common
  registry tool — links against **libc only** and never demands a library
  the box lacks (an unconditional `-lpq` previously broke a hello-world
  where the Postgres client was absent).
- **Actionable errors instead of cryptic failures.** A missing compiler
  prints install guidance rather than `clang: command not found`; the
  installer smoke-tests the unpacked binaries and, on a missing shared
  library, names the `.so` with a package-manager hint.

## [0.9.11] — 2026-06-22

The "dependency-free toolchain + registry programs" release: the installed
`nurlc` and `nurlpkg` now link **libc only** (no inherited `libpq` /
`libcurl` / `libsqlite3` / …), several real programs landed on the package
registry, and the whole source tree is now held to canonical `nurlfmt` form
by CI.

### Added

- **WebSocket `permessage-deflate` (RFC 7692), server and client.** Per-message
  compression negotiated over `Sec-WebSocket-Extensions`, with both context-
  takeover directions and peer-imposed window bounds honoured. New surface in
  `stdlib/ext/websocket.nu`: extension negotiation (`ws_deflate_parse_extensions`,
  `ws_deflate_offer_header`, `ws_deflate_response_header`), a `WsDeflate` context
  (`ws_deflate_make` / `ws_deflate_free`), deflate-aware messaging
  (`ws_send_text_deflate` / `ws_send_binary_deflate` / `ws_read_message_deflate`
  / `ws_serve_messages_deflate` and their `ws_client_*` mirrors), and one-shot
  handshake helpers (`ws_perform_handshake_deflate`, `ws_connect_deflate`). The
  frame reader now surfaces the RSV1 compressed bit (`WsFrame.rsv1`,
  `WsMessage.compressed`) — still rejected on the non-deflate readers, so the
  change is fully backward-compatible. Decompression is capped against
  `WsLimits.max_message_bytes` (a decompression-bomb guard) and text payloads
  are UTF-8-validated *after* inflation.
- **Raw-DEFLATE streaming codec in `stdlib/ext/compress.nu`** (the engine the
  above rides on): `raw_deflate_*` / `raw_inflate_*` drive a *persistent*
  `z_stream` with raw (header-less) DEFLATE via negative `windowBits`,
  `Z_SYNC_FLUSH`, sliding-window context takeover, and `*_reset`. Four new
  layout-absorbing `nurl_z_*` accessors in `runtime.c` let the NURL-side loop
  rebind input/output across the persistent stream. Regression tests
  `compress_rawdeflate.nu` and `ws_permessage_deflate.nu`.
- **Real programs on the package registry.** Three CLI/library packages were
  written in NURL and published to `reg.nurl-lang.org`: **`nq`** (a jq-lite
  JSON query tool), **`md2html`** (a Markdown → HTML converter, CLI + library),
  and **`iforest`** (Isolation Forest anomaly detection, CLI + library).
  `argz` / `argz-demo` gained READMEs and published `0.1.1`.
- **Registry renders each package's README.** A package's detail page now
  renders the README from its tarball (Markdown → HTML done in TypeScript,
  XSS-safe).
- **`nurlweb` auto-generates release-coupled facts and serves the installer.**
  Site facts (version, line/test/module counts) are generated from the repo
  state instead of being hand-maintained, and `nurl-lang.org` serves the
  installer scripts so the `curl … | sh` one-liner works.

### Fixed

- **Bombproof toolchain install — `nurlc` and `nurlpkg` link libc only.** A
  fresh install could die immediately with
  `error while loading shared libraries: libpq.so.5`, even though `nurlpkg`
  never touches Postgres: the monolithic `runtime.o` carries every FFI
  back-end, and the link lines named them all unconditionally with no
  `--as-needed`, so each binary inherited whatever the build machine had as a
  hard `DT_NEEDED`. Every native link line now passes `-Wl,--as-needed`
  (a binary keeps a dependency only for a library it actually references;
  LTO drops the dead back-end code first), and `nurlpkg` reaches the registry
  through the system `curl` **binary** (new `stdlib/ext/http_cli.nu`) with
  zlib + zstd linked statically — so both `nurlc` and `nurlpkg` now depend on
  `libc` only. The installer (`get-nurl.sh`) also smoke-tests the unpacked
  binaries and reports any missing shared library with a package-manager hint.
- **Windows build.** Build breakage on the Windows target was fixed.
- **`nurlc`: `Vec[T]` indexing when `T` has a field named like the index
  variable.** A struct-pointer field access could be mis-resolved as an array
  index (and vice-versa) when a local index variable shared a name with a
  struct field; the field/element disambiguation is now correct.
- **Playground self-heals a wedged container Worker.** When the backing
  server hangs-but-keeps-running, the Cloudflare container Worker now detects
  the "not listening" wedge and restarts it instead of serving sticky 500s.

### Changed

- **Canonical-form gate.** The whole tree was canonicalised with `nurlfmt`
  and a `nurlfmt --check` CI gate now rejects any non-canonical first-party
  `.nu` file (the formatter is IR-transparent, so this changed no behaviour).

### Docs

- Roadmap: the two LLM-native evidence studies are marked as shipped.

## [0.9.10] — 2026-06-20

The "NURL becomes an ecosystem" release: the toolchain is now installable,
the package registry can host and install real programs, and tagged
releases ship install packages for Linux and Windows.

### Added

- **`$NURL_STDLIB` import root (the compiler is relocatable).** `nurlc`
  resolved every `$ `…`` import path relative to the current working
  directory with no notion of an installed stdlib, so a package could not
  reference `stdlib/…` outside the monorepo. `__norm_import_path` now falls
  back to `$NURL_STDLIB/<path>` (via libc `getenv`) when a cwd-relative hit
  misses; the cwd hit always wins, keeping the bootstrap byte-identical.
  This is what lets an installed compiler — and registry-installed packages
  — find the shipped stdlib from any directory.

- **`nurlpkg install <name>` — install a program from the registry.** The
  `cargo install`-shaped sibling of bare `install`: fetch a published
  package, resolve its dependencies, compile its `src/main.nu` against the
  installed stdlib, and drop the binary in `$NURL_HOME/bin` (default
  `~/.nurl/bin`). A package with `src/main.nu` is an installable program
  (binary = package name); without it, a library. Shell-free and
  cross-platform: staging via the language's own filesystem primitives
  under the platform temp dir, in-process dependency resolution, and a
  build-driver spawn that wraps `.bat` with `cmd /c` on Windows.

- **Installable toolchain — `tools/install-toolchain.sh` / `.bat`.** Install
  `nurlc`, `nurlpkg`, and the stdlib into a self-contained prefix (default
  `~/.nurl`) and wire up `NURL_STDLIB` + `PATH` so the whole toolchain works
  from any directory. The shims and `env` are relocatable (they resolve the
  prefix from their own location), so a downloaded archive works wherever it
  is unpacked.

- **Release pipeline — `.github/workflows/release.yml`.** On a `v*` tag,
  build the toolchain natively for `linux-x86_64-glibc` (ubuntu-latest),
  `linux-arm64-glibc` (ubuntu-24.04-arm), and `windows-x86_64`
  (windows-latest), package each as a relocatable archive + `.sha256`, and
  attach them to the GitHub Release. `workflow_dispatch` gives a
  publish-free dry run.

- **One-line installer — `tools/get-nurl.sh` / `get-nurl.ps1`.** The
  `curl -fsSL https://nurl-lang.org/install.sh | sh` front door: detect
  OS/arch, resolve the latest (or pinned) release, download the matching
  archive, verify its SHA-256, and unpack the toolchain into `$NURL_HOME`.
  `$NURL_INSTALL_BASE` overrides the download base for internal mirrors.

- **First registry packages — `packages/argz` + `packages/argz-demo`.**
  `argz` is a tiny, dependency-free command-line argument parser (boolean
  flags, value options, short aliases, `--` separator, positional arguments,
  auto-generated `--help`), leak-clean under AddressSanitizer/LeakSanitizer.
  `argz-demo` is an installable greeter that depends on `argz = "^0.1"`.
  Both are published to `reg.nurl-lang.org`.
  `tools/nurlpkg/test-install-tool.sh` drives the full fetch → build →
  install → run loop against a local static registry.

### Fixed

- **The language server no longer crashes on an unresolvable import.** The
  LSP's workspace indexer read imported files with the compiler's
  `nurl_read_file`, which calls `exit(1)` on a missing file (a missing
  import is fatal to a *compile*, but must never be fatal to the *server*).
  Opening a file whose imports don't resolve — e.g. a package whose registry
  dependencies aren't installed yet — killed the whole language server. It
  now probes with `file_exists` first (`__read_if_exists`).

- **Duplicate `getenv` declaration removed from `env.nu`.** Now that the
  compiler globally declares `getenv` (for import-path resolution), `env.nu`
  re-declaring it via the `&` FFI form emitted two `declare @getenv` lines
  and failed to link; `env.nu` relies on the compiler-provided declaration,
  matching how `fopen`/`access` are handled.

### Documentation

- **`RELEASING.md`** — the distribution model (GitHub Releases + a `curl|sh`
  front door served from nurl-lang.org; the registry stays the *package*
  registry), how to cut a release, runtime dependencies, and the
  Windows/macOS caveats.

- **`packages/README.md`** — the two registry packages and the full
  install-and-run loop on POSIX and Windows.

## [0.9.9] — 2026-06-18

### Fixed

- **Signedness-aware generic monomorphisation (distinct instantiations for `i` and `u64`).** Generic code using signedness-sensitive operations (like `/`, `%`, `>>`, or comparison operators) now monomorphises correctly based on the concrete type argument's signedness. Previously, types with the same LLVM width (e.g. `i` and `u64`) shared the same mangled slug, causing the compiler to reuse the first generated monomorphisation (e.g., executing `udiv` instead of `sdiv`). Mangles generic type arguments from their source word (`u8`/`u16`/`u32`/`u64` vs `i64`) to force distinct instantiations.
  Regression: `compiler/tests/generic_signedness_mono.nu`.

- **Correct zero-extension for unsigned-returning generic calls.** Widening casts (`# i ( f … )`) of generic call results now zero-extend (instead of sign-extend) the result when the function's declared return type is unsigned. The return signedness of the monomorphised instantiation is now tracked and resolved at the call site.
  Regression: `compiler/tests/unsigned_call_result_widen.nu`.

- **Integer literals above `i64` max parsed correctly in `u64` range.** The decimal lexer now accumulates digits using wrapping 64-bit arithmetic instead of `atoll` (which silently saturated at `LLONG_MAX` for literals in `[2^63, 2^64)`).
  Regression: `compiler/tests/u64_literal_parsing.nu`.

- **Foreach elements inherit container's unsigned element type.** Element variables in `~ x container { … }` loops now correctly inherit the container's unsigned type (recovered from the vector/slice metadata), ensuring signedness-sensitive operations and widening casts inside the loop execute with unsigned semantics.
  Regression: `compiler/tests/foreach_unsigned_element.nu`.

- **IEEE 754 NaN semantics for float inequality (`!=`).** Float `!=` comparisons now emit `fcmp une` (unordered-or-not-equal) instead of `fcmp one` (ordered, not-equal), correctly returning `true` when either or both operands are NaN.
  Regression: `compiler/tests/float_ne_nan.nu`.

- **Result Ok-arm payload inherits type's unsigned flag.** Pattern matching over a Result `! T E` now correctly propagates T's unsigned flag to the Ok-arm (`T v`) binding inside the match block, correcting signedness-sensitive operations on the payload.
  Regression: `compiler/tests/result_payload_unsigned.nu`.

- **Result Err-arm payload inherits type's unsigned flag.** Dual to the Ok-arm fix, the Err-arm (`F e`) binding now correctly inherits E's unsigned flag from a Result `! T E` type.
  Regression: `compiler/tests/result_err_arm_unsigned.nu`.

- **Monomorphised generic struct fields retain unsigned signedness.** Field type substitutions in `ensure_struct_instantiated` now propagate the unsigned flag, preventing unsigned fields of generic struct instances from being treated as signed on field access (e.g. `. p field`).
  Regression: `compiler/tests/generic_struct_field_unsigned.nu`.

- **Coercion of float literals to `f32` struct fields.** Float literals (always parsed as `double`) are now correctly truncated to `float` (via `fptrunc`) when initializing `f32` fields of structs/aggregates, resolving "insertvalue operand and field disagree in type" compilation errors.
  Regression: `compiler/tests/f32_struct_field_literal.nu`.

- **Enum `f32` payload construction support.** Float payloads constructed for `f32` enum variants now correctly perform float narrowing (`fptrunc`) from double literals or values before insertion, allowing float-payload enums to round-trip.
  Regression: `compiler/tests/enum_f32_payload.nu`.

- **Two more fuzzer BAD_IR shapes diagnosed (bool/int mix, match on a scalar).**
  - **A binary operator mixing a bool (i1) and a non-bool operand**, both
    non-constant (`< flag n` with `n : i`), emitted a width-mismatched
    `icmp i1 %flag, %n` that only clang/llvm-as rejected. `gen_binary` now
    rejects it. A constant operand is still fine — it reinterprets to the other
    side's width — so `== flag 0` (int literal fits i1) and `== v T` (bool
    literal fits i64) keep compiling; only two disagreeing registers are
    flagged.
  - **Binding a payload while matching a non-aggregate scalar** (`?? n { T a →
    … }` with `n : i`) emitted an `extractvalue` on the scalar. `gen_match` now
    rejects payload binding unless the scrutinee is an enum / option / result;
    integer-literal arms and bare tag matches are unaffected.
  Locks `should_fail_binop_bool_int`, `should_fail_match_payload_scalar`. (One
  deeply-contrived fuzz holdout remains: a mutation that makes a match
  scrutinee's *declared* type claim an option/result while its actual SSA value
  is a scalar — an inconsistency no real program produces.)

- **Option / Result `??` arm payload arity is enforced (fuzz follow-up #3).** An
  Option (`? T`) or Result (`! T E`) match arm binds at most one payload — the
  T-arm value / Ok payload, or the F-arm error. Binding more (`?? o { T a b → …
  }`) used to emit an out-of-range `extractvalue { i1, T } v, 2` that nurlc
  accepted (rc 0) and only clang/llvm-as rejected. `gen_match` now reports
  *"match arm binds N payloads but an option/result 'T' arm binds at most
  one …"*. (Enum variants already validated per-variant payload arity; this
  closes the opt/res case, completing the in-`??` out-of-range-extractvalue
  class.) Locks `should_fail_match_opt_overbind`.

- **More front-end checks for type/field misuse (fuzz follow-up #2).** The
  mutation fuzzer's remaining `BAD_IR` shapes (nurlc rc 0, only clang/llvm-as
  rejecting) were turned into source diagnostics — and one of the new checks
  caught a genuine latent bug in the corpus:
  - **A function / FFI symbol name used where a type is expected** now reports
    *"unknown type 'X'"*. The earlier unknown-type check accepted any name in
    scope; it now requires a `%`-type, so `@ f rand x → i` (using the FFI symbol
    `rand` as a parameter type) is rejected too.
  - **`.` field/element access on a non-aggregate scalar** (`. n x` with `n : i`)
    is rejected — it used to emit `extractvalue i64 …`.
  - **An out-of-range integer index into an aggregate** (`. p 9` on a 2-field
    struct) is rejected — it used to emit an invalid `extractvalue …, 9`.
  - **Accessing a field a struct does not have** (`. p nope`) now reports
    *"type 'P' has no field 'nope'"* instead of silently reading field 0 (a
    miscompile) — this exposed and fixed a real `. pho req` typo in
    `compiler/tests/websocket_client.nu` that had been reading the right field
    (`head`, index 0) only by luck.
  - **An FFI declaration whose `@` is not followed by an identifier**
    (`& "lib" @ @ foo`) is rejected with *"expected the C function name …"*.
  Locks `should_fail_{type_is_fn_name, member_on_scalar, member_index_oob,
  unknown_field, ffi_no_name}`. (Remaining, deferred: a `??` arm that binds more
  payloads than its variant/option has still emits an out-of-range
  `extractvalue` — a `gen_match` concern for a future round.)

- **Unknown type names are diagnosed at the source (fuzz follow-up).** An
  undeclared type identifier in a type position — an FFI parameter/return type,
  a function parameter/return type, or a struct field type — used to leak into
  the IR as an undefined `%Name` that `nurlc` emitted with status 0 and only
  `clang` / `llvm-as` rejected ("use of undefined type named 'X'", or the
  cryptic "cannot allocate unsized type"). A typo'd type name or a missing `$`
  import now produces *"unknown type 'X' … (a typo, or a missing '$' import?)"*
  pointing at the use. The new `check_type_known` scans the emitted LLVM type
  for `%Name` references and verifies each against the pre-scan type registry;
  generic type variables (tparam-like, substituted at monomorphisation) and
  compiler-mangled names (containing `__`, e.g. a `%Vec__i64` instantiation or
  an aliased import) are accepted unchanged, so generics and imports are
  unaffected. Locks `should_fail_unknown_type_{ffi,param,return,field}`.

- **Compiler no longer hangs on an unterminated declaration body (fuzz sweep).**
  A corpus-seeded mutation fuzzer (36k + 15k mutants over `build/nurlc`; oracle:
  never crash, never hang, and rc 0 ⇒ the IR assembles) found **zero crashes**
  but a class of infinite loops: several body-parsing loops checked only for
  their closing token (`}` / `)` / `]`) and not for end-of-input, so an
  unterminated construct spun forever on a no-op `nurl_lex_advance` at EOF
  instead of erroring. A playground user mid-keystroke (or any truncated file)
  could wedge the compiler. Fixed by adding an EOF guard to every such loop and
  letting the trailing `expect` report a clean "expected '}' / ')' / ']' but
  found end of input":
  - enum-variant loop (`: | E { A`),
  - trait/impl scan + gen loops and the method-signature skip
    (`% Shape { @ area i s → i`, `% Shape i { …`),
  - the `[T]` type-param skip, and
  - `parse_type_paren`'s generic-application and closure-type argument loops
    (`( Vec i`, reachable in any type position).
  Struct / match / block / call-argument bodies already terminated (their inner
  sub-parsers hit EOF first) and were left unchanged. 15k post-fix mutants
  produce no hangs and no crashes. Locks `should_fail_unterminated_enum`,
  `_trait`, `_impl`, `_type_paren`.

- **Front-end type checking for the common static-error class (adversarial
  sweep #3).** A sharper probing pass found that a whole family of trivial type
  errors was accepted by `nurlc` (rc 0, no diagnostic) and emitted IR that only
  `clang` rejected — the "where is the type checker?" optics. All are now caught
  at the source, with no implicit conversions introduced (NURL stays explicit):
  - **Binary-operator operand mismatch** — mixing a float and a non-float in any
    operator (`+ 1 1.0`, `* 2.0 3`, `== 1 1.0`), or a pointer/string and an
    integer in an arithmetic op (`+ `a` 1`). `gen_binary` enforces the
    "operands share a type" invariant it already documented. Pointer
    comparisons (`== ptr 0`, ptr↔ptr) stay exempt via the existing ptrtoint
    coercion. Locks `should_fail_binop_int_float`, `should_fail_binop_ptr_int`.
  - **Binding initialiser / assignment mismatch** — `: i x 1.5`, `: i x `hi``,
    `= n 1.5`. `coerce_store_val` now rejects the never-valid float/non-float
    and pointer-into-non-pointer store clashes after its real coercions
    (i1-widen, enum-wrap, single-handle, int-width) have had their say; the
    null-as-`0` idiom (`: *T p 0`) stays valid. Locks
    `should_fail_let_type_mismatch`, `should_fail_assign_type_mismatch`.
  - **Return-value type mismatch** — `^ `hi`` / `^ 1.5` from a `→ i` function.
    `gen_ret` checks the returned value's type against the declared return type
    (same narrow never-valid directions). Locks
    `should_fail_return_type_mismatch`.
  - **Void/unit value (`v`) stored or bound** — `: i y v`, `= x v` (the bare
    type keyword leaking into a value position). Locks `should_fail_store_void`;
    the operator/complement/not sinks were already guarded.
  - **Recursive struct of infinite size** — `: Node { i v  Node next }` (a
    by-value self-reference, the classic missing-pointer mistake) is diagnosed
    at the declaration with the "box it as `* Node`" cure, instead of a cryptic
    `insertvalue operand and field disagree` IR error at first construction.
    Locks `should_fail_recursive_struct`.
  - **Closure return-type context** — `gen_ret` inside a closure body now sees
    the *closure's* declared return type (the body scope shadows
    `__fn_ret_ty__`), not the enclosing function's; this both enables the
    return check above inside closures and corrects the pre-existing
    void-return diagnostic there.

### Decided (toward 1.0 grammar lock)

- **No grouping/closing delimiter — locked.** Fixed prefix arity with no
  closing token stays the canonical, permanent surface form (CRITIC A3, the
  last open grammar decision). The call was made on data: a ~77 000-line
  first-party corpus sweep (the self-hosted compiler, the HTTP/1.1+2 +
  WebSocket stack, a regex engine, crypto, and the Game Boy / C64 emulators)
  measured the longest consecutive prefix-operator run per line — ~96 % of
  operator-bearing lines nest only 1–2 deep, and just **19 lines in the entire
  corpus** reach depth ≥5, clustered in two idioms (n-ary boolean membership
  and big-endian byte assembly) that already have ordinary library answers (a
  predicate helper such as `is_alpha`, or an intermediate `:` binding). The
  foot-gun shape is caught by the existing dead-value / prefix-arity-cascade
  diagnostics. Rationale and the depth table are recorded in `docs/spec.md`
  §6. The decision is safe to revisit additively — an *optional* grouping form
  could be added post-1.0 without breaking any program; 1.0 locks only the
  negative.

### Changed

- **Clearer diagnostics for two call-site papercuts** (surfaced by the
  v1.0-lock language sweep):
  - A **generic function called without `[T …]` type arguments** now reports
    *"generic function 'pick' needs explicit type argument(s): write
    ( pick [T] … ) — NURL does not infer generic type arguments from value
    arguments"* instead of the misleading *"call to unknown function 'pick'"*
    (the same message a genuine typo gets). A truly-unknown name still gets the
    unknown-function message. Lock `compiler/tests/should_fail_generic_no_typeargs.nu`.
  - A **pure-NURL stdlib helper used without importing its module** —
    `nurl_str_cat` / `_cat3` / `_cat4` / `_slice`, which are pre-registered for
    cross-module typing but have no C body (unlike `nurl_str_int` / `_float` /
    `read_*`) — now reports *"'nurl_str_cat' is defined in
    stdlib/core/string.nu … add a '$' import of that file"* at the call site,
    instead of leaking clang's *"use of undefined value '@nurl_str_cat'"* at
    link. Safe because `scan_fn_sigs` is a complete whole-program pre-pass, so a
    real definition anywhere sets `__arity` before any call is generated (no
    false positive for cross-module callers). Lock
    `compiler/tests/should_fail_stdlib_helper_no_import.nu`. Both are
    diagnostic-only — the bootstrap fixed point holds.

### Fixed

- **Adversarial language-probing sweep #2 (`examples/chaotic-aggressor.nu`) —
  four edges hardened before the v1.0 lock.** A hostile valid-NURL stress demo
  (a concatenative stack VM exercising generics, traits, multi-payload `??`,
  a slice-of-closures jump table, closures-returning-closures and dense prefix
  float math) flushed out:
  - **Slice element access by a parameter index emitted malformed IR.**
    `. slice idx` where `idx` was a bare function parameter lowered the index
    as a load from a `<name>__ptr` alloca a parameter never has, leaving the
    `load i64, i64*` pointer operand blank — IR nurlc accepted (rc 0) and only
    clang rejected (*"expected instruction opcode"*). `gen_member` now resolves
    the index exactly like `gen_ident` (parameter → `%name`, local → load
    `__ptr`, const / enum → load `@name`). Regression
    `compiler/tests/slice_index_by_param.nu`.
  - **A bare type keyword used as a value emitted `add void void, …`.** The
    void/unit literal `v` (produced only by a bare type keyword in value
    position) reaching an operator / complement / logical-not lowered to a
    void-typed SSA operand — again rc 0, clang-only rejection. New
    `die_if_void` guard rejects it at the source (covers `: i x + v 100` and
    the `~ v xs { … }` foreach-binding trap). Lock
    `compiler/tests/should_fail_void_operand.nu`.
  - **Closure capture-by-value assignment is no longer silent.** Assigning to a
    binding a closure captured by value (the counter footgun: `1,1,1` instead
    of `1,2,3`) now warns at the assignment, pointing at the supported
    shared-mutation shape (a `: ~` multi-field struct captured by reference,
    which cannot escape its frame). Baseline
    `compiler/tests/should_warn_byval_capture_assign.nu`.

### Changed

- **`generic_inst` grammar widened to match the implementation (compound type
  arguments).** The compiler has always accepted compound generic arguments —
  a nested application `( Pair ( Box i ) i )`, a pointer `*T`, an option
  `?T` / `??T`, or a closure `( @ R P* )` — at both the type-position
  `( Name … )` form and the call-site `[ … ]` form, but `spec/grammar.ebnf`
  still said *"base identifiers only; `*T` is not accepted."* The grammar and
  `docs/spec.md` now define a shared `generic_arg` covering those forms, so
  spec and implementation agree ahead of the 1.0 lock. The one excluded shape —
  a bare anonymous slice (`[ T`) as an argument — used to emit garbage IR that
  only clang rejected and now gets a clean source diagnostic with the
  wrap-in-a-struct cure. Lock `compiler/tests/should_fail_slice_generic_arg.nu`.

- **Mutable string globals (`: ~ s g …`) can now be reassigned.** The
  declaration was accepted and emitted as writable `global i8*` storage, but
  `gen_const_decl`'s string branch never recorded the `__mutable` flag (the
  `i` / `u` / `f` / `b` branches all did), so a later `= g …` was wrongly
  rejected with *"cannot assign to immutable global"* — even though the
  grammar lists `s` as an updatable mutable-global type. The string branch now
  sets the flag like the other scalar branches. Reassignment to a constant or
  a heap-allocated (`nurl_str_cat`) string both work. The bootstrap fixed
  point holds (no in-tree code could use a mutable string global, since the
  bug rejected them, so emitted IR is unchanged). Regression
  `compiler/tests/mutable_string_global.nu`. Surfaced by an adversarial
  language-probing sweep for grammar/spec-vs-compiler gaps before the v1.0
  lock.

### Changed

- **Pattern matching now binds N payloads per arm (was capped at 3).** The
  enum type and construction already supported any number of payload slots;
  only the match side was limited — the parser stored just three binding
  names and the emitter had three hand-unrolled slot blocks, so a 4th+ payload
  was silently dropped (`use of undefined identifier`), forcing a post-match
  `.` extraction. The parser now collects overflow payload names/literals and
  the emitter binds slots 1..N-1 through one `emit_enum_payload_bind` helper in
  a loop (slot 0 keeps its option/result-aware reconstruction); literal
  constraints on slots 3+ loop the same way. Verified for 4- and 5-payload
  variants across mixed payload types (int / float / string / pointer /
  struct), a literal constraint on slot 3, and a guard reading a slot-3
  binding. The bootstrap fixed point holds without a refresh. Regression
  `compiler/tests/match_payload_n.nu`. Removes the `docs/LIMITATIONS.md` Enums
  limitation (CRITIC A6).

### Fixed

- **Float (`f` / `f32`) enum payloads now compile.** An enum's payload slot
  is uniformly pointer-typed; construction coerced `i1` / integer / string /
  struct payloads into it, but had no branch for `double` / `float`, so a
  float payload emitted `insertvalue %E …, double X, 1` into a `ptr` field
  and clang rejected it (`operand and field disagree in type`). The match
  side had the symmetric gap. Any sum type with a floating-point payload —
  a numeric AST, a real-valued JSON, a geometry variant — was uncompilable,
  although the grammar permits it. Fixed in `gen_agg_lit` (bitcast the float
  to a same-width int, f32 widens i32→i64, then `inttoptr` into the slot) and
  `emit_enum_float_extract` (the inverse on the match arm). Verified across
  payload slots 0/1/2, a mixed float+pointer recursive enum, and a genuine
  `f32` value; the bootstrap fixed point holds (no existing code used float
  enum payloads, so emitted IR is unchanged). Regression
  `compiler/tests/enum_float_payload.nu`; surfaced by the
  `examples/chaotic-showcase.nu` grammar stress test (recursive symbolic
  autodiff). An *implicit* double-literal → `f32` narrowing in an enum
  literal still needs an explicit `# f32` cast, exactly as struct
  construction requires.

## [0.9.8] — 2026-06-15

### Added

- **NAT- and mobile-traversing distributed transport (§7.4).** A complete
  pubkey-addressed overlay where a peer is a **public key, not an address** —
  it reaches that key over a direct peer-to-peer path when it can and a relay
  when it must, and never drops to zero reachability. Built bottom-up:
  `net/securedgram.nu` (WireGuard-style encrypted UDP over Noise + a session
  AEAD with a sliding replay window, plus endpoint **roaming** so a peer survives
  a network change), `net/stun.nu` (RFC 8489 server-reflexive discovery),
  `net/nat.nu` (candidate gathering, NAT-type classification, UDP hole punch),
  `net/relay.nu` (DERP-style opaque forwarding **plus group multicast** —
  broadcast to your own group), `net/rendezvous.nu` (signaling-only directory),
  `net/transport.nu` (the flat seam: `transport_send`/`broadcast`/`recv`,
  direct-when-possible/relay-when-forced with promote/demote), and SWIM
  membership (`net/membership.nu`) hardened by **Lifeguard**
  (`std/lifeguard.nu`) with a failure-detector control loop
  (`net/failuredetector.nu`). On top sit the sharding + replicated-state
  layers: a consistent-hash ring (`dist/ring.nu`), state-based CRDTs
  (`dist/crdt.nu` — PN-Counter, LWW-Register, OR-Set) and their gossip wiring
  (`dist/replicator.nu`, anti-entropy scoped to a key's replica set). Documented
  end to end in [`docs/DISTRIBUTED.md`](docs/DISTRIBUTED.md).

- **The Crown — distributed computation (§7.5).** Turns the distributed *state*
  above into distributed *work*. `dist/identity.nu` gives each peer a replica
  id; `dist/job.nu` is the keystone — submit a task keyed by `k`, the ring owner
  executes it via a registered handler, the result is recorded idempotently, and
  a key that re-homes mid-flight is **forwarded** to the new owner so the job
  still completes. `dist/lease.nu` adds fencing tokens (epoch monotonicity +
  idempotency keys) so a *side-effecting* task fires **at most once** across a
  split-ownership window. Liveness under load is handled by SWIM
  **self-refutation** plus a **heartbeat on a dedicated OS thread**
  (`dist/heartbeat.nu`), so a 100%-CPU node is not falsely evicted. The whole
  story is verified by a **deterministic chaos-simulation harness**
  (`dist/sim.nu`): a virtual clock + in-process message bus with seeded fault
  injection (drop, latency/jitter→reorder, partition/heal) drives the *real*
  stdlib logic, with scenarios for converge-under-loss, keystone-across-
  partition, at-most-once-side-effect, and CPU-pinned-not-evicted — all
  byte-reproducible goldens, ASan-clean.

- **Push-To-Talk voice app — `pttvoice/`.** A distributed PTT voice app on the
  overlay: captures the microphone, **Opus**-encodes it (48 kHz mono, 20 ms
  frames via a libopus FFI binding), and pushes a talkspurt either to one peer
  (unicast — p2p when punchable, relayed otherwise) or to the whole group
  (multicast); a receiver decodes and plays it. ALSA capture/playback
  (`audio.nu`), the codec (`opus.nu`), the voice wire frame (`proto.nu`), and
  the app (`ptt.nu`) live in a self-contained folder. Verified live over a
  loopback relay (group broadcast and peer unicast). `build.sh` now detects
  **libopus** and **ALSA** (dropping `stdlib/runtime.{opus,asound}` sentinels)
  and `nurl.sh` auto-links `-lopus`/`-lasound` when those FFI symbols appear.

- **Playground “🎙️ PTT Chat” demo with channels.** A new `/pptchat` tab: a
  page with a microphone button and an **embedded NURL→WebAssembly module**
  (`nurlapi/static/pptchat.nu` → `pptchat.wasm`) that reads the mic through the
  `audio` FFI and paints a live VU meter + frequency spectrum, framing the
  distributed voice tech. **Channels**: no id → the shared `public` channel;
  **+ Create channel** mints a random id and navigates to `/pptchat/<id>`;
  opening that URL joins the same channel (the URL is the invite, the future
  shared-secret/QR), with a Copy-link button.

- **Parallel sanitizer test suite.** `compiler/tests/run_san_tests.sh` now runs
  AddressSanitizer/UBSan checks in parallel (`NURL_SAN_JOBS`, default = cores),
  cutting the sanitized CI leg from minutes to under one — matching the already-
  parallel functional runner.

- **HTTP client cookie jar — `stdlib/ext/cookies.nu`** (critic B23). The
  server side writes `Set-Cookie` (ext/http_auth.nu); this is the missing
  client half. `cookie_jar_set` parses one `Set-Cookie` value (Domain,
  Path, Expires, Max-Age, Secure — Max-Age wins over Expires, an
  already-expired cookie deletes its stored match) defaulting Domain/Path
  from the request host/path; `cookie_jar_header` returns the `Cookie:`
  value for a request, applying RFC 6265 domain matching (§5.1.3,
  host-only vs subdomain), path matching (§5.1.4), Secure gating, and
  expiry, longest-path-first. Pure string-in/string-out — decoupled from
  the HTTP client types, so it round-trips a session over HTTP/1.1, h2,
  or any header source. `now` (unix seconds) is passed explicitly for
  deterministic expiry. Lock: `compiler/tests/cookies_basic.nu`
  (host-only vs Domain, path ordering, Secure, Max-Age/Expires expiry,
  replacement, Max-Age=0 deletion, malformed rejection); ASan+UBSan+LSan
  clean.

- **Benchmark harness — `stdlib/std/bench.nu` + `nurlpkg bench`** (critic
  C4). `std/bench.nu` times a no-arg closure over many iterations and
  reports **ns/op** (via the monotonic clock) and **allocations/op**.
  `bench_run name iters body` runs a short untimed warmup then a timed
  loop; `bench_auto name body` auto-scales the iteration count until a
  pass clears ~50 ms, for stable numbers on sub-microsecond operations.
  `bench_report` prints one line; `bench_result_*` accessors expose the
  raw numbers. The allocation metric is backed by a new runtime hook,
  `nurl_alloc_count` (a relaxed-atomic counter on every
  `nurl_alloc`/`nurl_zalloc` — which is what stdlib vec/string/struct
  blocks route through), snapshotted around the timed loop so warmup is
  excluded. `nurlpkg bench` discovers `benches/*.nu`, compiles each at
  `-O2`, runs it, and streams its report (no goldens — wall time is
  machine-dependent; a bench fails only on a compile error or nonzero
  exit). Ships `bench/stdlib_hotpath.nu` (string build / vec push / sort
  micro-benches). Locks: `compiler/tests/bench_basic.nu` (deterministic
  surface — report formatting, the alloc counter on a vec cycle vs a
  no-op body, iteration bookkeeping) and
  `compiler/tests/nurlpkg_bench_smoke.sh` (runner discovery / streaming /
  summary / exit codes).

- **`nurlpkg test` — user-facing test runner** (critic C3). Ships the
  compiler suite's per-test pattern as a tool: `nurlpkg test` discovers
  `tests/*.nu`, compiles and runs each, and reports `PASS`/`FAIL` with a
  summary (exit 0 iff every test passes). A test passes on exit 0; if a
  `tests/outputs/<name>.txt` golden exists, the program's stdout must
  match it byte-for-byte instead. Tests run in sorted order for
  determinism. The build driver is `./nurl.sh` by default, overridable
  via `$NURL_CC` (a command taking `<flags> <src> <outbin>`) for an
  installed toolchain. Smoke-tested by
  `compiler/tests/nurlpkg_test_smoke.sh` (all four verdict paths +
  all-pass/any-fail exit codes + the empty-tree message).

- **REPL — `tools/repl` (`nurl repl`)** (critic C1). An interactive
  read-eval-print loop on a process-per-eval model: top-level definitions
  (`@` functions, `&` FFI, `$` imports, and `:` types / enums / globals)
  accumulate into a persistent session, while every other line is spliced
  into a fresh `main`, compiled with `./nurl.sh -O0`, and run — its stdout
  is echoed back. A new definition is validated by a fast `build/nurlc`
  frontend pass before it joins the session, so a typo never poisons later
  evaluations. Line editing + history come from `std/term.nu` (the B10
  work); on a non-tty (pipe / script) it falls back to plain buffered
  reads. All REPL chrome — prompts, acks, errors, `:help` — goes to
  stderr, so stdout carries only the evaluated program's output. Meta-
  commands: `:help`/`:h`, `:quit`/`:q`, `:defs`, `:reset`, `:save FILE`.
  Multi-line definitions are read until brackets balance. Build with
  `./tools/repl/build.sh`; smoke-tested by `compiler/tests/repl_smoke.sh`
  (definitions + globals persist across lines, a bad definition is
  isolated, stdout stays clean). Note: process-per-eval re-initialises a
  `:` global on every evaluation — definitions and pure functions persist,
  but mutation does not accumulate across lines.

- **Bitset — `stdlib/std/bitset.nu`** (critic B18, collections round-out).
  A fixed-size bit array over 64-bit limbs: `bitset_set` / `bitset_clear`
  / `bitset_flip` / `bitset_test` (all bounds-checked, so the unused high
  bits of the last limb stay clear), `bitset_set_all` / `bitset_clear_all`,
  a popcount-backed `bitset_count`, `bitset_any` / `bitset_all` /
  `bitset_none`, the in-place combiners `bitset_and_with` / `bitset_or_with`
  / `bitset_xor_with`, `bitset_clone`, and an ascending `bitset_each_set`.
  Storage is a flat `nurl_zalloc` word buffer peeked/poked by limb. NURL
  has no native XOR or NOT operator, so the module uses the exact,
  carry-free identities `a ^ b = (a|b) - (a&b)` and `~m = -1 - m`. Lock:
  `compiler/tests/bitset_basic.nu` — cross-limb set/clear/flip, out-of-
  range no-ops, popcount, `all()` on a full set, the three combiners with
  an XOR-identity bit check, and clone independence; ASan+UBSan+LSan clean.

- **LRU cache — `stdlib/std/lru.nu`** (critic B18, collections round-out).
  A fixed-capacity `LruCache [V]` over string keys, backed by a HashMap
  (key → slot) plus an intrusive doubly-linked recency list over
  preallocated slot arrays with a free list — so `lru_get` / `lru_put` /
  `lru_contains` / `lru_remove` are all O(1) and a cache at capacity does
  no further allocation. `lru_get` moves the key to MRU; `lru_peek` does
  not; `lru_put` returns the displaced value (replaced or evicted), owned;
  `lru_each` walks MRU→LRU; `lru_free_with` drops each value on teardown
  (the owned-element discipline the deque/heap work established). The map's
  hash/eq closures are non-capturing, so they allocate nothing per call.
  Lock: `compiler/tests/lru_basic.nu` — eviction order, get-as-touch
  survival, peek-without-reorder, replace-returns-old, remove, the MRU→LRU
  walk, and the owned-String `free_with` path; ASan+UBSan+LSan clean. With
  the B-tree and bitset, this **closes critic B18**.

- **B-tree ordered map — `stdlib/std/btree.nu`** (critic B18). A
  `BTree [K V]` with O(log n) insert / lookup / delete, replacing the
  array-shift backing for large ordered maps. Classic CLRS proactive
  split-on-descent and borrow/merge-on-descent (minimum degree 8, so up
  to 15 keys per node) keep the tree balanced; each node also caches its
  subtree size, which makes `btree_key_at` / `btree_val_at` order-
  statistic queries (the *i*-th smallest key) O(log n) too. API:
  `btree_new` / `btree_len` / `btree_is_empty` / `btree_get` /
  `btree_contains` / `btree_set` / `btree_remove` / `btree_min_key` /
  `btree_max_key` / `btree_key_at` / `btree_val_at` / `btree_each` /
  `btree_free` / `btree_free_with`. Nodes are raw 6-slot blocks with
  typed-pointer access (the same generic-container pattern as
  `std/set.nu`). Lock: `compiler/tests/btree_basic.nu` — a 2000-key
  scrambled fill with replace, remove-every-third churn, order-statistic
  and ascending-iteration checks, and full drain; ASan+UBSan+LSan clean.

- **Terminal control — `stdlib/std/term.nu`** (critic B10). The
  prerequisite for a REPL and TUI examples: POSIX termios raw mode
  (`term_raw_enable` / `term_raw_disable`, with `struct termios` sized
  via `nurl_native_sizeof` so the platform layout never leaks into NURL),
  `term_is_tty`, a full set of byte-exact ANSI builders (`ansi_reset` /
  `ansi_sgr` / `ansi_fg` / `ansi_bg` / `ansi_clear` / `ansi_clear_line` /
  `ansi_cursor_to` / `ansi_cursor_up`/`down`/`right`/`left`), and a
  minimal raw-mode line editor (`term_read_line`) with printable insert,
  backspace, ←/→, ↑/↓ history, Ctrl-A/E/K, and a clean not-a-tty None
  fallback. Adds `TCSANOW` / `TCSAFLUSH` to the runtime's
  `nurl_native_constant` table (POSIX-only; Win32/WASI return None from
  raw mode while the ANSI builders still work — Windows Terminal speaks
  VT). Lock: `compiler/tests/term_basic.nu` — the tty-independent surface
  (None on a file fd, byte-exact ANSI hex); ASan+UBSan+LSan clean.

- **ZIP archives — `stdlib/ext/zip.nu`** (critic B15). A reader and
  writer for the ZIP format over the existing zlib FFI. Writer: `zip_new`
  / `zip_add` (raw-deflate, windowBits −15, falling back to *store* when
  deflate would not shrink the entry) / `zip_add_stored` / `zip_finish`,
  emitting local headers, the central directory, and the EOCD with a
  fixed DOS timestamp so archives are byte-deterministic. Reader:
  `zip_open` (backward EOCD scan over the comment window, with zip64
  rejected as unsupported) / `zip_count` / `zip_name_at` / `zip_size_at`
  / `zip_extract` / `zip_extract_name` / `zip_close`, every extraction
  CRC-32-validated. Lock: `compiler/tests/zip_basic.nu` — build (deflate
  + store + a compressible 5000-byte entry), re-open, CRC-checked extract
  of each entry, by-name extraction, missing-name and junk-archive
  rejection; cross-checked against system `unzip -t`; ASan+UBSan+LSan
  clean.

- **SMTP client — `stdlib/ext/smtp.nu`** (critic B17). A mail-submission
  client over the runtime's client-side TCP/TLS connect: `smtp_connect` /
  `smtp_connect_tls`, EHLO capability discovery (`smtp_ehlo` /
  `smtp_has_cap`), `smtp_starttls` (RFC 3207 — upgrades the live
  plaintext fd to TLS and re-EHLOs), `smtp_auth_plain` / `smtp_auth_login`
  (RFC 4954), the `smtp_mail_from` / `smtp_rcpt_to` / `smtp_data`
  envelope (DATA dot-stuffs and terminates per RFC 5321 §4.5.2),
  `smtp_quit` / `smtp_close`, plus a minimal RFC 5322 MIME builder
  (`mime_build`), `smtp_dotstuff`, and `smtp_date_now`. STARTTLS needs to
  upgrade an already-open fd, which the existing connect primitives could
  not do, so this adds `nurl_tcp_starttls` to the runtime — the
  client-handshake half of `nurl_tcp_connect_tls` applied in place. Lock:
  `compiler/tests/smtp_basic.nu` — the offline surface (multiline reply
  scanner/parser, AUTH PLAIN/LOGIN base64 tokens, dot-stuffing, MIME),
  ASan+UBSan+LSan clean; `examples/smtp_send.nu` demonstrates the live
  STARTTLS submission flow.

- **Unix domain sockets — `stdlib/std/unixsock.nu`** (critic B9). The
  local-IPC sibling of `std/net.nu`'s TCP, same API shape but a
  filesystem path instead of host:port — for Postgres-over-socket,
  systemd-style services, container control planes. `unix_listen` /
  `unix_accept` / `unix_connect` / `unix_socketpair` / `unix_read_chunk`
  / `unix_write_all` / `unix_write_str` / `unix_close_conn` /
  `unix_close_listener` (which unlinks the socket file). Pure libc FFI
  (blocking SOCK_STREAM); `unix_listen` unlinks any stale path before
  binding. Adds `AF_UNIX` / `SOCK_STREAM` / `EADDRINUSE` to the runtime's
  `nurl_native_constant` table (POSIX-only; the module degrades to a
  clean `UnixSocket` error on Win32/WASI). Lock:
  `compiler/tests/unixsock.nu` — a deterministic `socketpair` round-trip
  (both directions + EOF-after-close) plus a thread-driven
  listen/accept/connect echo gated on `NURL_NET_TESTS`; ASan+UBSan+LSan
  clean on both paths.

- **CBOR (RFC 8949) — `stdlib/ext/cbor.nu`** (critic B16). The
  IETF-standard binary serialization (COSE / WebAuthn / CTAP), sibling of
  MessagePack, over the shared `Json` value: `cbor_encode Json →
  !( Vec u ) CborErr` and `cbor_decode ( Vec u ) → !Json CborErr`. Encode
  is canonical-ish — integers and lengths use the shortest head, floats
  are float64 — so equal documents serialize to equal bytes. Decode is
  liberal: every definite-length head, signed/unsigned integers at all
  widths, and **float16 / float32 / float64** (the half-float decoder
  handles zero / subnormal / normal / inf / NaN). Byte strings, tags,
  indefinite-length items, and exotic simple values are rejected as
  `CborUnsupported`; `undefined` (0xf7) → `JNull`. Lock:
  `compiler/tests/cbor.nu` — Json round-trip with canonical-byte check,
  the RFC 8949 Appendix A decode vectors (integer boundaries, negatives,
  nested array/map, all three float widths), and every documented
  rejection; ASan+UBSan+LSan clean (error paths free the partial tree).

- **Arbitrary-precision fixed-point decimal — `stdlib/std/decimal.nu`**
  (critic B14, the last ROADMAP numeric gap). A `Decimal` is a `BigInt`
  coefficient × 10^-scale, so it is *exact* — `0.1 + 0.2` is `0.3`, not
  the binary-float `0.30000000000000004` — and never overflows. Exact
  `dec_add` / `dec_sub` / `dec_mul`; `dec_div a b scale` with an explicit
  result scale and **banker's rounding** (round half-to-even, the
  financial default); scale-agnostic `dec_cmp`; `dec_round` / `dec_rescale`
  / `dec_normalize`; `dec_from_string` (`"-12.340"`, `".5"`, `"42"`) and
  `dec_to_string`. Builds on the `bigint` div/rem from PR #100. Lock:
  `compiler/tests/decimal.nu` (exact `0.1+0.2==0.3`, the full
  half-to-even rounding table incl. negatives, division + div-by-zero,
  normalize, cross-scale compare; ASan+UBSan+LSan clean — every
  intermediate `BigInt` freed).

- **Playground: rendered stdlib API reference at `/stdlib-docs`**
  (`nurlapi`). The `nurldoc` library is now wired into the playground
  server: `/stdlib-docs` is an auto-generated index of every stdlib
  module (grouped by `core`/`std`/`ext`/`hal`), and `/stdlib-docs/<path>`
  renders one module's signatures + doc comments through
  `nurldoc_render` → the existing `md_to_html` + dark-theme doc chrome
  (the same presentation as the README/spec pages). Append `.md` for the
  raw Markdown. Closes the loop the C2 nurldoc PR opened — the "broad
  stdlib" is now browsable, not just greppable. Listed in the OpenAPI
  spec; live-verified end-to-end (index + module HTML + raw `.md`,
  ASan-clean).

- **`nurldoc` — Markdown API-doc generator** (critic C2). The stdlib's
  `//`-header + doc-comment discipline (90+ modules) was unrenderable;
  `nurldoc` extracts each module's header block, top-level declaration
  signatures (functions trimmed at their `{` body; types/enums/consts
  keep their full definition), and the doc comment above each, into
  Markdown. The render logic is an importable library
  (`stdlib/ext/nurldoc.nu`, `nurldoc_render content title → String`,
  brace-depth-aware so `:` locals inside bodies are never picked up);
  `tools/nurldoc/main.nu` is a thin CLI — `nurldoc <file.nu>` to stdout,
  or `nurldoc <src-dir> <out-dir>` to walk the tree with `fs_glob` and
  write one `.md` per module. Lock: `compiler/tests/nurldoc.nu`.

- **HTTP-date / RFC 2822 date parsing — `stdlib/std/time.nu`** (critic
  B13). The server formatted HTTP dates (`time_format_http`) but could
  not parse them; `http_date_parse` now accepts all three forms RFC 7231
  §7.1.1.1 requires — IMF-fixdate (`Sun, 06 Nov 1994 08:49:37 GMT`),
  obsolete RFC 850 (`Sunday, 06-Nov-94 08:49:37 GMT`, 2-digit year via
  the POSIX <70 pivot), and asctime (`Sun Nov  6 08:49:37 1994`) — for
  `If-Modified-Since` / `If-Unmodified-Since` / cookie `Expires`.
  `rfc2822_parse` handles the email `Date:` form with numeric `±HHMM`
  zones (`Mon, 02 Jan 2006 15:04:05 -0700`). Both return UTC seconds in
  the `!i ParseErr` shape (pair with `time_from_unix`), matching
  `time_parse_iso`. Lock: `compiler/tests/http_date.nu` — the three
  RFC 7231 spellings agree on the spec's own example (784111777), the
  RFC 2822 `-0700` case equals Go's canonical reference instant, plus
  round-trip and rejects.

- **JWT bearer-auth middleware — `stdlib/ext/http_jwt.nu`** (B5
  follow-through). `with_jwt_hs256 secret inner` / `with_jwt_eddsa
  pubkey inner` wrap a claims-aware handler
  (`( @ HttpResponse HttpRequest Json )`) and return the standard
  `( @ HttpResponse HttpRequest )` middleware shape, so they compose
  with `with_access_log` / `with_cors_default` / `router_handle`. A
  request runs the handler only with a valid `Authorization: Bearer`
  token; the verified payload claims are passed straight in (no
  re-parse, no header injection / spoofing surface, borrowed + freed by
  the middleware). Missing / invalid / expired / not-yet-valid tokens
  get a 401 with an RFC 6750 `WWW-Authenticate: Bearer` challenge whose
  `error=` / `error_description=` names the failure. Kept in its own
  module so the base `ext/http_auth.nu` stays free of the OpenSSL
  dependency `ext/jwt.nu` pulls in. Lock: `compiler/tests/http_jwt.nu`
  (valid/expired/tampered/wrong-key/missing × HS256 + EdDSA;
  ASan+UBSan+LSan clean).

- **Filesystem niceties + glob — `stdlib/std/fs.nu`** (critic B6 + B7).
  `fs_rename` (libc `rename`), `fs_copy_file` (64 KiB-chunk streaming, so
  large files copy in bounded memory), `fs_tempfile` (libc `mkstemp` →
  unique 0600 file, returns the path). `fs_glob` expands shell patterns
  against the tree: `*` / `?` / `[...]` (with `[a-z]` ranges and
  `[!...]`/`[^...]` negation) within a segment, `**` as a whole segment
  for recursive descent, the leading-dot rule (`*` never matches a
  dotfile; an explicit `.` does), absolute or relative patterns. Pure
  NURL over `dir_list`. Lock: `compiler/tests/fs_glob.nu` (every pattern
  class + rename/copy/tempfile against a built temp tree).

- **One URL parser — `stdlib/std/url.nu`** (critic B12). RFC 3986
  `scheme://[userinfo@]host[:port][/path][?query][#fragment]` into an
  owned `Url`, with bracketed-IPv6 hosts, `url_default_port` /
  `url_port_or_default` (http/https/ws/wss/ftp/redis/postgres),
  `url_request_target` (path?query for the request line), a percent
  codec (`url_percent_encode`/`_decode`), and `url_query_decode` →
  `Vec[UrlParam]` (form-urlencoded `+`→space, `%xx`). Lives in `std/`
  with core-only deps so `ext/` layers on it without a cycle. Locked
  against RFC 3986 component-split vectors in
  `compiler/tests/url_parse.nu`.

- **JSON Web Tokens — `stdlib/ext/jwt.nu`** (critic B5). HS256 (HMAC-
  SHA256) and EdDSA (Ed25519) sign + verify over the existing crypto
  block and base64url. `jwt_hs256_sign/verify`, `jwt_eddsa_sign/verify`,
  a `…_verify_at` core taking an explicit epoch `now` (deterministic;
  the wrapper uses the system clock), and `jwt_decode_unverified`.
  Validates `exp`/`nbf` time claims; the HS256 signature comparison is
  constant-time (`std/subtle.nu`). The HS256 path reproduces the
  canonical jwt.io reference token exactly and EdDSA is goldened against
  the RFC 8032 test key (Ed25519 signatures are deterministic) in
  `compiler/tests/jwt_basic.nu`. Adds `b64_url_encode_vec` /
  `b64_url_decode_vec` to `std/encode.nu` for binary, unpadded
  base64url (the signature segment).

### Changed

- **`ext/websocket.nu` and `ext/http2_client.nu` delegate URL parsing to
  `std/url.nu`** (critic B12 consolidation). Both hand-rolled
  scheme/host/port/path splitting; their `__ws_parse_url` /
  `__h2_parse_url` are now thin wrappers over `url_parse` that enforce
  the ws/wss and http/https schemes and map to the existing `WsUrl` /
  `H2Url` types — same public API, one parser underneath. The new parser
  also correctly stops the authority at `?`/`#` (the old scanners folded
  a query into the host when no path was present) and keeps the query in
  the request target.

### Fixed

- **CRDT replica ids must be globally stable** (`dist/crdt.nu`,
  `dist/replicator.nu`, `dist/identity.nu`). The chaos-simulation harness
  exposed silent state corruption: `PNCounter` stored increments in a dense
  vector merged **by position**, while `identity_of` handed out ids in local
  first-seen order, so every node called itself replica 0 — two distinct
  replicas collided into one slot and the merge took `max(1,1)=1` instead of
  summing to 2, converging to the *wrong value with no error*. Fixed deeply:
  `identity_stable_id(pubkey)` derives a globally consistent id from the pubkey
  (FNV-1a/64, no coordination); `PNCounter` is now sparse and **keyed by
  replica id** (merge aligns by identity, not position); the wire carries the
  id per slot and `pncounter_encode` emits slots in canonical ascending-id
  order so equal states encode identically (required by the digest anti-entropy).

- **Struct-pointer field access mis-resolved when the field name shadows a
  variable** (`compiler/nurlc.nu`, `gen_field`). `. p field` on a struct
  *pointer* resolved `field` as a same-named local integer and emitted a pointer
  array-index instead of a field load — a silent miscompile only `clang` caught.
  A struct field now always wins over a same-named variable on the field-load
  path (the field-*store* `= . p name val` array-index form is unchanged and
  intentional). Lock: `compiler/tests/ptr_field_name_shadow.nu`.

- **Closure literals rejected parenthesised compound param/return types**
  (`compiler/nurlc.nu`, `gen_backslash_expr`). `\ ( Vec u ) p → ( Vec u ) { … }`
  failed with “undefined identifier 'u'” because `\ (` was only treated as a
  closure when the next token was `@`; a compound type head fell through to the
  try-expression path. `\ (` is now a closure whenever the next token introduces
  a type (incl. the builtin `Vec`). Lock: `compiler/tests/closure_compound_param.nu`.

- **`@ ?Enum { T Variant }` emitted invalid IR** (`compiler/nurlc.nu`,
  `gen_agg_lit`). Constructing `Some(variant)` of an option whose
  payload is a no-payload (C-style) enum inserted the variant's bare
  i64 tag into the option's `%Enum` aggregate slot, which clang
  rejected (`insertvalue operand and field disagree in type`). The
  Result form `! T E` always worked because its payload slot is i64;
  only the option payload field carries the full `%Enum` type. The
  coercion now wraps the tag with `insertvalue %Enum zeroinitializer,
  i64 tag, 0`. Found while writing `ext/jwt.nu`. Lock:
  `compiler/tests/option_enum_payload.nu`.

- **Cryptography block — AEAD, signatures, key exchange, KDFs**
  (`stdlib/ext/crypto.nu`, critic B1–B3). Binds libcrypto's EVP layer
  through pure-NURL `` & `openssl` @ `` FFI (no C bridge, same sentinel
  pattern as TLS/libpq → "install libssl-dev" at compile time):
  AES-256-GCM and ChaCha20-Poly1305 one-shot AEAD (tag appended;
  `CryptoVerify` on tampered input); Ed25519 keygen/sign/verify and
  X25519 keygen/derive via the EVP_PKEY raw-key API; HKDF-SHA256,
  PBKDF2-SHA256/512, and scrypt. Every primitive is locked against its
  published vector (NIST GCM, RFC 8439, RFC 8032 §7.1, RFC 7748 §6.1,
  RFC 5869 A.1, RFC 7914 §12) in `compiler/tests/crypto_evp.nu`.
- **`std/subtle.nu` — constant-time comparisons** (critic B4).
  `constant_time_eq` / `_eq_n` / `_eq_vec` for secret material,
  promoted from the private bearer-token loop in `ext/mcp_registry.nu`
  (which now calls it). Length-leaking but content-timing-invariant,
  matching `hmac.compare_digest` / Go `crypto/subtle`.

### Fixed

- **`ext/crypto.nu` HKDF: binary salt was silently zeroed** before the
  module shipped — `nurl_str_get` is a NUL-bounded C-string read, so
  hex-encoding a `Vec u` salt through a `# s` cast truncated at the
  first `0x00` byte. Switched the binary→hex helper to the `*u` + `. p k`
  indexed load (the idiom `encode.nu`'s `__b64_emit` already uses). The
  RFC 5869 test vector caught it; documented as a reuse hazard in
  `critic.md` B3.

- **`nurlc --lint` detects unused imports** (`compiler/nurlc.nu`). A
  top-file `$` import none of whose defined symbols (functions, FFI
  externs, types, constants — generic templates included) is referenced
  by the top file itself now warns `unused import: no symbol from
  '<path>' is referenced in this file`. References count from calls,
  identifier reads, and type positions; uses recorded while re-parsing
  generic template bodies during the instantiation flush are attributed
  to the template's defining file, so stdlib internals never mask a top
  file's dead import. Pure aggregator files (only `$` directives, no
  decls of their own — e.g. `stdlib/ext/http_full.nu`) are exempt both
  as importer and as import target: re-exporting is their purpose. The
  LSP server (v0.6.0) now surfaces these straight from `nurlc --lint`
  and drops its former text-heuristic duplicate (~190 LOC removed) —
  one source of truth for the diagnostic.

- **Unknown callees are compile errors now** (`compiler/nurlc.nu`). A
  call to a name with no registered return type — not an `@`-fn, FFI
  extern, builtin, impl method, or local closure — previously fell
  through as an assumed-`i64` call to an undeclared symbol: invalid IR
  that clang rejected far from the source, or worse, code that linked
  by accident when the defining file happened to be imported later in
  the unit *and* the return type happened to be i64. Now dies at the
  call site: `call to unknown function 'X' — … add the missing '$'
  import … or check the spelling.` Same treatment for a generic call
  whose template is nowhere in the import closure (was: opaque
  `expected '->' but found end of input` inside the synthetic
  `<generic …>` source). En route this surfaced — and forced fixing —
  nine runtime builtins that were header-declared but missing from the
  compiler's symbol table (`nurl_peek`, `nurl_init`, `nurl_memset`,
  `nurl_vec_drop`, `nurl_argc`, `nurl_argv_count`, `nurl_read_int`,
  `puts`, `printf`), all silently riding the i64 default.

### Fixed

- **180 stale `$` imports removed tree-wide** (88 stdlib, 92
  tests/examples/tools). Several masked real latent bugs, now fixed
  with explicit imports: `stdlib/ext/csv.nu` used `opt_unwrap_or`
  without importing `stdlib/core/option.nu` (rode on `sort.nu`'s own
  stale import), `stdlib/ext/http2_hpack.nu` called
  `h2_default_header_table_size` without importing
  `stdlib/ext/http2_frame.nu`, and `stdlib/std/bufio.nu` called
  `nurl_file_open`/`nurl_file_close` without importing
  `stdlib/std/fs.nu` — each compiled only when every consumer
  happened to import the missing file first. `stdlib/std/set.nu` no
  longer imports `hashmap.nu` for its callers' convenience; import it
  alongside (the stock `hash_*`/`eq_*` helpers live there).

## [0.9.7] — 2026-06-11

### Added

- **Enum payload residuals diagnosed — ghost variants and unsized
  generics are hard errors now** (`compiler/nurlc.nu`, critic A7).
  An unknown/unimported type name in an enum variant's payload position
  parses as a SEPARATE variant (same-file forward references already
  resolve via the pre-scan, so this fires only for typos and missing
  imports) — the intended payload silently vanished and downstream
  code emitted out-of-bounds `extractvalue` / broken `store` IR, or
  silently read a sibling variant's slot. Three new hard errors:
  payload-arity checks at the match arm ("match arm binds 1 payload(s)
  but variant 'V' declares only 0 …") and at the enum literal, both
  naming the unknown-type-parses-as-variant cause; and an
  unknown-generic check in `parse_type_paren` — `( Vec i )` with no
  generic-struct template in scope and no materialised instantiation
  dies at the use site naming the missing `$` import, instead of
  clang's "loading unsized types is not allowed" far from the cause
  (zero-type-arg `( Type )` trait-impl targets are exempt). Locks:
  `should_fail_ghost_variant_match.nu`,
  `should_fail_ghost_variant_construct.nu`,
  `should_fail_unknown_generic_type.nu`. False-positive sweep: full
  suite 339 PASS + nurlapi + examples clean.

- **"Statement has no effect" warning — the last silent prefix-arity
  cascade is now diagnosed** (`compiler/nurlc.nu`, critic A2). A
  statement that produces a value without being a call or control flow
  (bare local identifier, operator expression like `+ a 1`, a `#` cast,
  a `.` field read) discards that value silently — under prefix
  notation with fixed arity and no closing token, this is exactly the
  residue left when an operator short an argument swallows the next
  statement's leading token. The bare-literal flavor was already a
  hard error (dangling operand); these shapes name real bindings, so
  they warn. Value-block tail expressions (the block result), calls,
  and `?`/`??` statements (their arms may be effectful) are exempt.
  The diagnostic embeds the dead statement's own line — by the time
  the block iterator sees the flag, the lexer already points at the
  next statement. Tree-wide false-positive check: nurlc.nu
  self-compile, the full stdlib, nurlapi, and examples produce ZERO
  warnings. Locks: `should_warn_dead_value.nu` (four dead shapes warn;
  tail/call/return stay silent), and `should_warn_caret_xor.nu` now
  also catches the previously silent dead `b` in `: i x ^ a b`. This
  closes the last undiagnosed half of the prefix-arity cascade family
  (critic §4); the A3 closing-delimiter decision can cite it as the
  mitigation.

- **`std/bigint`: arbitrary-precision division and modulo** —
  `bigint_div` / `bigint_rem` (`stdlib/std/bigint.nu`), closing the last
  gap in the bigint arithmetic surface. The magnitude core is Knuth
  Algorithm D (TAOCP vol. 2, §4.3.1) over the base-2¹⁶ limbs: D1
  normalization reuses the existing small-multiply helper (top divisor
  limb ≥ base/2, so every trial digit is off by at most one), the
  multiply-and-subtract step uses a per-limb {0,1} borrow (no negative
  shifts), and the rare add-back step is exercised by both classic
  Hacker's Delight `divmnu` trigger vectors. A single-limb divisor
  short-circuits through `__mag_divmod_small_inplace`. Semantics are
  truncated division exactly like the native `/` and `%`: the quotient
  rounds toward zero, the remainder takes the dividend's sign, and
  `x == (x/y)*y + x%y` holds for every `y ≠ 0`. Division by zero panics
  (recoverable via `recover`) — a defect, not a data error, so it is not
  threaded through `!`. Regression `compiler/tests/bigint_div.nu`: all
  four sign combinations, zero/`a<b`/exact edges, both add-back vectors,
  a 39-digit ÷ 21-digit case, a 60-round deterministic invariant sweep
  (reconstruction, `|r| < |y|`, remainder sign) over growing multi-limb
  operands, and the recovered divide-by-zero panic; ASan+UBSan clean,
  leak-free. Additionally verified against Python on 300 random cases
  (mixed limb counts/signs, near-power-of-2¹⁶ divisors).

### Fixed

- **Auto-drop: fn-returned by-value structs with owned fields now
  transfer ownership to the caller** (`compiler/nurlc.nu`, critic A4c).
  Two bugs closed. `^ @ T { ( nurl_str_cat … ) }` (direct construction
  return) leaked the field — the callee never bound it so never
  registered a drop, and the caller never registered one either.
  `^ v` where `v` is a bound struct was worse: a **use-after-free** —
  the callee's scope-exit drop freed v's owned field while the
  returned-by-value copy still aliased it, so the caller read freed
  memory. The fix mirrors the existing owned-string return flag: the
  callee skip-drops the escaping struct binding and publishes its exact
  owned-field list (`<fname>__ret_owned_fields`), which the caller's
  `: T x ( f )` re-registers through the same
  `mem_register_agg_owned_fields` path — exactly one drop, at the
  caller's scope exit. Ownership composes through `^ ( mk )` call chains
  and reaches nested struct fields. Safe against double-free with
  stdlib's manual `*_free` conventions: only raw-`s`/slice fields filled
  by a fresh allocation in a *direct* agg-literal return register for
  transfer — stdlib's struct returns use `String`/`Vec` handle fields
  (untracked) and build incrementally before `^ binding` (which never
  registers agg fields), so their manual frees stay correct. Verified:
  full san suite 0 SAN_FAIL, `tools/leakcheck` zero, suite 340 PASS,
  and a targeted incremental-build manual-free probe stays single-drop.
  Regression `ret_struct_owned_transfer.nu` (direct / bound / chain /
  nested shapes, ASan+LSan zero). No nurlc IR change — fixed point holds
  without a bootstrap refresh.


- **Auto-drop: arm-local trailing declarations leaked; `^ ( call )`
  string ownership now propagates; aliasing escapes transfer ownership**
  (`compiler/nurlc.nu`, critic A4). Three coupled fixes: (1) a `:`
  declaration as an arm's LAST statement made the arm look
  value-producing (gen_let_or_struct left the RHS type in last_type),
  which suppressed the Phase 2D fall-through drop — leaking the binding
  on every `?`/`??`/loop arm ending in a decl — and emitted a bogus phi
  over the discarded value; declaration statements now publish `void`.
  (2) `__fn_ret_str_owned__` was only set for identifier returns, so
  `@ helper → s { ^ ( nurl_str_cat … ) }` was never marked
  `__ret_owned=str` and `: s x ( helper )` leaked one buffer per call;
  gen_ret now consults the outermost call's `__last_call_ret_owned__`
  for direct parenthesised-call returns, making ownership compose
  through helper chains. (3) The widened tracking exposed missing
  ownership TRANSFER on aliasing escapes: `= outer x` and ternary/match
  arms whose value is a bare load of an owned binding now cancel that
  binding's scheduled drop (`mem_remove_owned_str`; the arm delta-drop
  protocol switched from prefix-length to word-membership to stay
  consistent under mid-list deletion). Conservative direction
  throughout: worst case a leak, never a use-after-free — the
  pre-transfer behavior freed buffers that had escaped through phis,
  which miscompiled the compiler itself (gen_cast's
  `: s norm ? … xv ( nurl_cg_reg cg )` returned a freed register
  name). Bootstrap snapshot refreshed (`--refresh-bootstrap`).
  Regressions: `arm_local_trailing_drop.nu` +
  `ret_owned_propagation.nu`, both ASan+LSan zero, with manual-free
  double-free locks on the transfer paths. Known residual filed as
  critic A4c: fn-returned structs with owned fields still transfer
  nothing (needs an ownership-model decision against the stdlib's
  manual `*_free` handle conventions).

- **`server_stop` from another thread freed the listener under blocked
  pool workers** (`stdlib/ext/http_server.nu`). `server_run_pool`'s
  documented shutdown — call `server_stop s` from another thread while
  workers block in accept — was a heap-use-after-free: workers hold no
  reference on the listener, so the stop's `nurl_tcp_close` dropped the
  last ref and freed the struct while every worker was still polling
  its `shutting_down` flag and wake-pipe fd (3/3 reproducible under
  ASan; single-threaded `server_run` raced identically). `server_run`
  and `server_run_pool` now retain the listener for the whole
  run→join window and release it only after no worker can touch the
  handle — the same contract `server_run_async` already followed for
  its accept fiber. The two-phase `tcp_shutdown_listener` → join →
  `server_stop` pattern remains valid; it is simply no longer the only
  safe shutdown. Regression `compiler/tests/http_server_stop_direct.nu`
  drives both fixed paths with a direct cross-thread stop (ASan-clean
  10/10 under `NURL_NET_TESTS=1`). Closes critic.md B19 together with
  the earlier accept-wake fix (f470571).

- **`recover` leaked the closure's captured environment**
  (`stdlib/std/panic.nu`). `recover` decomposes its closure into
  `(fn_ptr, env_ptr)` and hands them to the C trampoline; passing the
  raw env pointer onward suppresses the parameter's auto-drop (the
  compiler must assume the env escapes — and in `thread_spawn`, whose
  shape this mirrors, it really does). But `nurl_recover` is
  synchronous: once it returns, the closure can never run again, so the
  env was simply leaked — one allocation per `recover` call with a
  capturing closure, panic or not. `recover` now frees the env right
  after `nurl_recover` returns (NULL-safe for capture-less closures),
  on both the normal and the unwind path. Found via ASan on the new
  `bigint_div` divide-by-zero regression; the existing
  `recover_basic` / `http_server_panic` goldens are unaffected (output
  is unchanged — only the leak is gone).

- **HTTP/1.1 server hardening — four root-cause bug fixes from a focused
  security bughunt** (`stdlib/ext/http_request.nu`, `http_server.nu`,
  `http_response.nu`):
  - **Chunked request bodies were silently dropped on keep-alive
    connections.** `__finish_body` only handled `Content-Length`, so a
    `Transfer-Encoding: chunked` body was left undrained in the connection
    carry buffer — the handler saw an *empty* body and the leftover bytes
    were mis-parsed as the next request (a desync / request-smuggling
    vector). `__finish_body` now decodes chunked bodies carry-aware
    (draining from the buffer + socket, leaving any pipelined successor).
  - **Chunk-size integer overflow → smuggling/DoS.** `__parse_hex_size`
    accumulated an unbounded hex value; `0x10000000000000000` wrapped i64
    to `0` (read as the terminating chunk, ending the body early) or to a
    small positive (wrong boundary) — both smuggling vectors, and a huge
    positive could drive an enormous allocation. Now rejects any value
    past a sane ceiling, well clear of i64 overflow.
  - **Content-Length + Transfer-Encoding smuggling.** A request carrying
    both framing headers (RFC 7230 §3.3.3) is now rejected at head parse
    (and in `read_body_to`) instead of silently letting `Transfer-Encoding`
    win — the classic CL.TE desync.
  - **HTTP response splitting (CWE-113).** Response header names/values
    were serialised verbatim, so a value reflected from untrusted input
    (a redirect `Location`, an echoed header) could inject
    `\r\n<header>` and split the response. The serialiser (and the chunked
    `response_begin_chunked` path) now strips CR/LF from every emitted
    header name and value.

  Regressions: `compiler/tests/http_request_parser.nu` (CL+TE rejection,
  chunk-size overflow rejection), `http_response_builder.nu` (header
  CR/LF stripping), and a new live `http_server_chunked.nu` (chunked body
  decoded + keep-alive survives a chunked request, gated on
  `NURL_NET_TESTS=1`).

- **HTTP/2 client: request bodies larger than 256 bytes now work, and a
  large body no longer deadlocks the driver.** Three related fixes:
  - **SETTINGS parameter-ID mismap (critical).** The client's SETTINGS
    parser handled id `3` (`MAX_CONCURRENT_STREAMS`) as
    `INITIAL_WINDOW_SIZE` and ignored id `4` (the real
    `INITIAL_WINDOW_SIZE`), so every stream's send window was seeded with
    the peer's max-concurrent-streams value (typically 256) instead of its
    advertised window (65535). Any POST/PUT body over ~256 bytes stalled
    forever waiting for a WINDOW_UPDATE that never needed to come. IDs are
    now mapped correctly.
  - **Driver read/write interleave.** Each pump step now drains every
    inbound frame already available (readiness-probed via
    `nurl_reactor_wait_read`) *before* flushing pending DATA, keeping the
    peer's send buffer to us empty so it never blocks writing and keeps
    reading our DATA — removing the documented single-socket deadlock on a
    large request body.
  - **Server per-stream WINDOW_UPDATE** (`stdlib/ext/http2_conn.nu`). The
    h2 server replenished only the connection window, so it could not
    receive a request body larger than the 64 KB initial *stream* window;
    it now also replenishes each stream's window as it consumes DATA.

  Regression: `compiler/tests/http2_client.nu` gains a live 200 KB POST
  (spanning many DATA frames and several flow-control windows) over the
  in-repo h2 server, gated on `NURL_NET_TESTS=1`.

- **`inout` / `sink` parameter conventions now work on trait impl
  methods** (grammar-v2 borrow checker). An `inout` (or `sink`) parameter
  on an impl method silently miscompiled: the convention was recorded
  under the mangled method name (`bump__Counter`) while the call site
  dispatches by the bare name (`( bump c )`), so the receiver was passed
  **by value** into a `%T*` parameter — memory corruption / segfault.
  Fixing that surfaced a second bug (applying `inout` pointerised the
  first argument to `%T*`, which missed the `method##%T` impl-dispatch key
  and emitted an undefined bare `@method`). Both are fixed: the bare-name
  convention is mirrored at emission, and the impl-dispatch lookup retries
  with the receiver pointer stripped. Regression
  `compiler/tests/impl_inout_sink.nu` (struct `inout`, `inout` + by-value,
  a second implementing type, and a `sink` impl method; ASan + leak
  clean).

### Fixed (examples)

- **Game Boy emulator: deterministic ~90 s crash on Tobu Tobu Girl's
  title screen** (`examples/gameboy/core.nu`). Root cause was a
  halt-bug emulation error, found by stack forensics on an
  instruction trace: `EI` + `HALT` with a timer IRQ landing inside
  HALT's own 4-cycle window set `g_halt_bug`, the EI delay then raised
  IME and the interrupt dispatched immediately — and the stale
  halt-bug flag replayed the HANDLER's first instruction (PC failed to
  advance once inside the handler). Tobu's handler starts with
  `PUSH HL`, so SP skewed by 2 and `RETI` returned into WRAM data —
  the screen froze and execution fell into a RST 38 loop (the gray
  bars + hang seen on the playground). Two-part fix per Pan Docs:
  (1) `EI` immediately before `HALT` with a pending interrupt is NOT
  the halt bug — the interrupt is serviced with the HALT's own address
  as the return address; (2) invariant: an interrupt dispatch always
  clears the halt-bug replay (it applies to the next sequential fetch
  only, never the handler's). Verified: Blargg `cpu_instrs` 11/11 +
  `02-interrupts` + `instr_timing` still pass, dmg-acid2 renders, and
  a 40 000-frame idle soak (vs the ~2 918-frame crash) runs ASan-clean
  with a live framebuffer. Also: migrated `examples/gameboy` to the
  enforced `:` immutability (97 declarations — it sits outside the
  test suite, so the tree-wide migration missed it; all gameboy
  targets compile again, playground build regenerated), and fixed
  `gbtrace.nu --trace` to drive the real `cpu_advance` path (its
  hand-rolled step loop was a stale copy that never woke from HALT).

### Documentation

- **The `sink`-of-auto-dropped-value boundary is documented as an
  intentional, locked limitation** (`docs/MEMORY.md` §1,
  `docs/LIMITATIONS.md`). Passing a compiler-auto-dropped value (owned
  string / slice / `Drop` value / owned-field struct) to a `sink`
  parameter is rejected by design: the auto-drop obligation is tracked in
  per-scope owned-sets that are snapshotted/restored across `?` / `??` /
  loop boundaries, so transferring it to the callee would be silently
  undone by an enclosing arm's restore — reintroducing a double-free.
  Reframed from "a future step" to a sound, conscious 1.0 decision with
  the rationale and workaround; pinned by
  `compiler/tests/should_fail_sink_autodrop.nu`.

- **The `pub` visibility contract is now stated exactly and locked by
  tests** (`docs/spec.md` §3.3). Cross-file enforcement covers
  `@`-functions, structs, enums, top-level consts, and enum variants; `pub`
  on **traits, impl methods, and FFI** is accepted but has no cross-file
  effect *by design* — trait dispatch resolves by type-mangled method name
  (no trait-name identity to gate) and FFI symbols are linker-level ABI
  globals. New `compiler/tests/pub_trait_ffi_visibility.nu` pins the
  unenforced surface (a non-`pub` trait method + FFI stays callable across
  files) so it can't silently regress into enforcement; the existing
  `should_fail_pub_*` tests pin the enforced surface. (Corrects the stale
  "only `@`-function calls observe the check" wording.)

## [0.9.6] — 2026-06-08

### Added

- **HTTP/2 client — native, multiplexed (`stdlib/ext/http2_client.nu`).**
  Completes the HTTP/2 stack (server + client). Reuses the direction-neutral
  framing/HPACK: `h2_client_connect_tls` (TLS + ALPN `h2`) /
  `h2_client_connect_h2c` / `h2_client_attach` → `h2_client_submit` (N
  concurrent streams) → `h2_client_run_until_complete` →
  `h2_client_take_response`, plus one-shot `h2_get` / `h2_request`. Full HPACK
  (connection-global decoder), per-stream + connection flow control,
  WINDOW_UPDATE / SETTINGS / PING / GOAWAY / RST_STREAM. Added runtime
  `nurl_tcp_connect_tls_alpn`. Example `examples/h2_client.nu`.

- **MCP server: stateful sessions, SSE stream, and `sampling/createMessage`
  reverse RPC (`stdlib/ext/mcp_session.nu`).** The pure, socket-free stateful
  core: an `McpSessionStore` keyed by a CSPRNG `Mcp-Session-Id`, a per-session
  outbound notification queue, and server→client reverse-RPC correlation.
  `mcp_http.nu` gains `mcp_http_handler_session` (mints/validates session ids,
  drains the queue to SSE on GET, settles reverse-RPC responses, tears down on
  DELETE) plus chunked `mcp_sse_*` helpers for a long-lived stream.

- **MCP server: `completion/complete` argument autocompletion.**
  `mcp_registry_add_completion r ref_type ref_id handler` registers a
  completion provider for a prompt argument (`ref/prompt`) or resource template
  (`ref/resource`); `completion/complete` resolves it and returns the
  spec-shaped `{completion: {values, total, hasMore}}`. Unknown refs yield an
  empty list (per spec). Works over both stdio and HTTP transports.

- **MCP server: `resources/subscribe` + `notifications/resources/updated`.**
  Per-session resource subscriptions: `mcp_session_subscribe` /
  `_unsubscribe` / `_is_subscribed`, and `mcp_session_notify_resource_updated`
  which fans an update notification out to every subscribed session over the
  SSE queue. The session HTTP handler services subscribe/unsubscribe against
  the request's `Mcp-Session-Id`.

- **XML parser + serializer — `stdlib/ext/xml.nu`.** Parses the common subset
  (elements, attributes, nesting, self-closing, text, comments, CDATA,
  declarations, the 5 predefined entities + numeric refs) into an `Xml` tree;
  `xml_stringify` round-trips with entity encoding. Accessors + builders. Out
  of scope: DTD/DOCTYPE, namespace resolution.

- **YAML parser + serializer — `stdlib/ext/yaml.nu`.** Parses a pragmatic
  subset into the shared `Json` value (so every `json_*` accessor works on a
  parsed doc): block mappings/sequences, the seq-under-a-key idiom, plain and
  quoted scalars resolved per the YAML 1.2 core schema, flow collections,
  comments, `---`/`...` markers. `yaml_stringify` emits block style with
  round-trip-safe quoting. Out of scope: block scalars, anchors/aliases/tags,
  multi-doc streams.

- **Timezone / DST support in `stdlib/std/time.nu`.** Local-time conversion +
  DST driven by a POSIX TZ string (`EST5EDT,M3.2.0,M11.1.0`, `IST-5:30`, …) —
  the format IANA tzdata compiles each zone's current ruleset into (covers
  US/EU/AU). `tz_utc` / `tz_fixed` / `tz_parse` / `tz_offset_at` / `tz_is_dst`
  / `time_from_unix_tz` / `time_now_tz` / `time_to_unix_tz` /
  `time_format_iso_tz`. Not in scope: IANA region-name lookup.

- **Growing arena + typed allocation — `stdlib/std/arena.nu`.**
  `arena_growing chunk_sz` returns a chained-chunk arena: when the current
  chunk fills, a fresh chunk is linked in and old ones are never moved, so
  every pointer handed out before a grow stays valid (the canonical
  pointer-stable arena model). `arena_alloc_n [T] a count → *T` allocates
  `count` contiguous items of `T`. `arena_new` / `arena_with_cap` remain fixed
  (NULL on overflow) — byte-identical behaviour for existing callers.

- **Counting semaphore — `stdlib/std/thread.nu`.** `sem_new` / `sem_acquire`
  / `sem_try_acquire` / `sem_release` / `sem_avail` / `sem_free`, built on the
  existing `Mutex` + `Cond`. The permit count lives in a heap cell, so a
  by-value copy (e.g. a worker-closure capture) shares state across threads —
  the classic tool for bounding concurrency (see the nurlapi compile gate
  below).

- **`readlink(2)` FFI — `stdlib/std/fs.nu`.** `fs_readlink` reads a symlink's
  target as an owned `String` via a direct `& \`c\`` binding (no runtime
  change). `nurlpkg` now reads and verifies an existing `deps/<name>` link
  target, catching transitive name collisions.

- **Seedable, deterministic PRNG — `stdlib/std/rng.nu` (xoshiro256\*\*).**
  Companion to `std/random.nu`'s OS CSPRNG, which draws from the kernel
  entropy pool and *cannot be seeded*. `rng.nu` gives a reproducible stream:
  `( rng_seed s )` expands any i64 seed into a 256-bit xoshiro256\*\* state
  via SplitMix64 (so even `0`/`1` produce well-distributed, uncorrelated
  streams), and the same seed yields a **byte-identical sequence on every
  platform and build** — the determinism guarantee extends here because the
  generator is integer-only (no float state, `>>` lowers to a logical
  `lshr` on the `u64`-typed words). Surface: `rng_next` (raw 64-bit),
  `rng_below` (unbiased, rejection-sampled `[0,n)`), `rng_range`, `rng_u01`
  (uniform double in `[0,1)`, 53-bit), `rng_bool`, `rng_free`. Opaque-handle
  lifecycle (same shape as `Arena`/`Channel`/`String`); state mutates in
  place. **Not** a CSPRNG — predictable, so never for security; use
  `std/random.nu` there. Regression `compiler/tests/rng_seedable.nu` pins
  the exact stream for seeds `0` and `0x1234` against an independent
  reference implementation, and checks determinism, `rng_below` bounds, and
  the inverted-range guard.

### Changed

- **nurlapi: bound concurrent compiles to stop OOM crashes.** The container
  runs a 16-worker pool, so up to 16 requests run at once; each compile spawns
  `clang -O2 -flto` (hundreds of MB), and 16 simultaneously could exceed the
  container memory cap and get the whole process OOM-killed ("container is not
  listening"). The accept pool stays wide (light requests keep flowing) but the
  heavy compile step is now bounded by a counting semaphore: `POST /build*` and
  `POST /mcp` take a permit before dispatch and release after (panic-safe),
  default 4, tunable via `NURL_COMPILE_SLOTS`.

- **Reverse proxy: binary-safe streaming response bodies.** Streaming
  responses were forwarded via a NUL-terminated carrier and truncated at the
  first embedded NUL (only SSE/JSON/text survived). The proxy now reads the
  stream's true byte length and copies exactly that many bytes. New
  `bytes_extend_raw` + `http_stream_next_bytes` (→ `( Vec u )`).

- **ROADMAP.md rewritten** as a concise, forward-looking document (status →
  toward-1.0 → planned), with the per-feature history delegated to this
  changelog. Bootstrap snapshot refreshed.

### Fixed

- **Compiler: struct payloads in enum match slots 1 and 2.** A multi-field
  struct value carried as an enum payload anywhere but the first slot
  (`: | E { Nil  V  i Pt }`) emitted invalid IR (`store %Pt <ptr>`) and was
  rejected by clang — construction heap-boxed it for every slot but the
  match/unbox path only reconstructed slot 0. Slots 1/2 now mirror slot 0.

- **Compiler: recursive auto-`Drop` for boxed-payload enum trees.** A
  `% Drop`-free enum whose variants box struct/enum payloads now gets a
  compiler-generated recursive drop, so nested owned payloads are freed at
  scope exit instead of leaking.

- **Compiler: borrow provenance for auto-`Drop` enum bindings off a
  borrow-returning accessor.** A binding taken from an accessor that returns a
  *view* into its parent is no longer treated as owned, fixing a double-free.

- **Compiler: drop the scrutinee of `^ ?? owned { … }` that returns a
  scalar.** The owned match scrutinee in a returning `??` whose arms yield a
  scalar was leaked; it is now dropped before the return.

- **Compiler: reject unbalanced braces / stray top-level tokens.** Malformed
  brace nesting and stray tokens at top level are now hard errors with source
  locations instead of reaching the backend.

- **C64 emulator** correctness fix (`examples/`).

## [0.9.5] — 2026-06-04

### Added

- **Playground shows its deployed version, and the API auto-deploys on
  release tags.** The playground header now carries a version pill — a
  `__NURL_VERSION__` placeholder in `index.html` is stamped at image-build
  time from the `NURL_VERSION` build-arg (`dev` for local builds). A new
  `.github/workflows/api-deploy.yml` builds the API image on a `v*` tag (or
  manual dispatch), pushes it to Docker Hub under the exact semver
  (`nurllang/nurl:vX.Y.Z` — no `:latest`), pins `cloudflare/Dockerfile`'s
  `FROM` to that tag and runs `wrangler deploy`, so a git tag is now a
  reproducible playground release. The Docker image was renamed
  `hindurable/nurl` → `nurllang/nurl`; `registry-deploy.yml` is now
  manual-only (the registry changes rarely).

- **MQTT-over-WebSocket transport — `mqtt_connect_ws`.** Adds a WebSocket
  transport alongside the raw TCP/TLS path so a client can reach a broker's
  MQTT-over-WS endpoint (e.g. `wss://host:8084/mqtt`) — handy when a firewall
  only permits the WS port inbound. `wss://` enables TLS with certificate
  verification and negotiates the `mqtt` subprotocol automatically; the codec
  and framed packet reader stay transport-blind behind two chokepoints. New
  entrypoints `mqtt_connect_ws` / `mqtt_connect_ws_cfg`; `mqtt_disconnect`
  also sends a WS Close frame, and `mqtt_reconnect` rejects WS clients (no URL
  to redo the upgrade). `stdlib/ext/mqtt.nu`.

- **Package manager → MLP: login/search/info, yank, token-revoke, catalog UI
  (ROADMAP §4).** Rounds the registry out into a minimum *lovable* product.
  - **CLI ergonomics.** `nurlpkg login` stores a per-registry publish token
    in `~/.nurl/credentials` (chmod 600) — `publish`/`yank` resolve the token
    `$NURL_TOKEN` → credentials, so it no longer has to live in the
    environment. `nurlpkg logout [--revoke]` forgets it (and optionally
    revokes it server-side). `nurlpkg search <q>` and `nurlpkg info <name>`
    query the registry (`info` with no arg still prints the local manifest).
    New `stdlib/ext/credentials.nu`.
  - **Registry hygiene.** `nurlpkg yank|unyank <name> <version>` flips a
    version's yanked flag (owner-only, via `POST /api/v1/{yank,unyank}`); the
    resolver already skips yanked versions, so a yanked release disappears
    from resolution. `nurlpkg logout --revoke` (`POST /api/v1/revoke`) deletes
    the presented token from D1.
  - **Catalog UI.** The Worker's `/` is now a searchable package list and
    `/packages/<name>` a detail page (versions with yank state, latest
    dependencies, an install snippet); `GET /api/v1/search?q=` backs the CLI.
  - Client helpers: `pkg_search` (`pkg_fetch.nu`), `pkg_yank` / `pkg_revoke`
    (`pkg_publish.nu`). Regression `compiler/tests/credentials_basic.nu`
    (set/get/upsert/multi-registry/remove; gated `NURL_CREDS_TESTS=1`, clean
    under ASan/UBSan). Whole feature set verified end-to-end against the
    Worker under `wrangler dev`: login → creds-based publish → search → info
    → yank (install then fails ResolveNoMatch) → unyank → catalog → logout
    --revoke → publish rejected (PubAuth).

- **Transitive registry dependencies — `nurlpkg publish` sends `X-Nurl-Deps`.**
  Publishing now includes the manifest's registry dependencies (a JSON
  `[{name, req}]` built by `__deps_json`) as the `X-Nurl-Deps` header, which
  the registry records in the package index. `pkg_publish` gained a
  `deps_json` parameter. With the deps in the index, `resolve_registry`
  pulls **sub-dependencies transitively** — previously the index always
  recorded `deps: []`, so only leaf registry packages installed correctly.
  Verified end-to-end against the local Cloudflare Worker: publish `tdep-b`,
  publish `tdep-a` (depends on `tdep-b ^1.0`), then `install` a consumer of
  only `tdep-a` → both land in `deps/` and the lock. Registry now supports
  real dependency graphs. `stdlib/ext/pkg_publish.nu`, `tools/nurlpkg/main.nu`.

- **Package registry service — Cloudflare Worker + R2 + D1 (`registry/`,
  ROADMAP §4 phase 6).** The deployable server side of the ecosystem, in
  TypeScript. The read path serves the static `index/<name>.json` +
  content-addressed `pkgs/<name>/<name>-<v>.tar.gz` from R2 (cacheable, no
  compute); the write path `POST /api/v1/publish` authenticates a Bearer
  token (peppered SHA-256 looked up in D1), enforces **first-publisher name
  ownership** + **version immutability**, **recomputes the tarball SHA-256
  server-side** (never trusts a client digest), and writes the tarball +
  updated index to R2. Identity bootstraps via **GitHub OAuth** (`/login` →
  `/auth/callback` mints a one-time CLI token). D1 schema in
  `migrations/0001_init.sql` (users / tokens / packages / versions).
  Implements exactly the wire contract the NURL client already drives.
  **Validated end-to-end locally** (no Cloudflare account): under
  `wrangler dev` (miniflare R2 + D1), the real `nurlpkg` binary completes a
  full publish → install round-trip plus immutability (409) and bad-token
  (401) rejections — `registry/test-local.sh`. Ships with
  `registry/DEPLOY.md`, a `registry-deploy.yml` GitHub Actions workflow
  (guarded so a placeholder token can't trigger a broken deploy), and
  secrets kept out of the repo (`wrangler secret put` for
  `GITHUB_CLIENT_SECRET` / `TOKEN_PEPPER`; GH Actions secrets for the
  Cloudflare deploy token). This completes the registry-backed package
  manager: `nurlpkg publish` + `nurlpkg install` against a deployable
  registry, all pure-NURL on the client and standing up locally today.

- **Package publishing — `stdlib/ext/pkg_publish.nu` + `nurlpkg publish`
  (ROADMAP §4 phase 5).** The write side. `pkg_pack` walks a project tree
  into a `.tar.gz` (excluding `deps`, `.git`/dotfiles, `nurl.lock`,
  `target`, `build`); `pkg_publish` uploads it with `POST
  <registry>/api/v1/publish`, `Authorization: Bearer <token>`, and
  `X-Nurl-Package` / `X-Nurl-Version` headers (binary body via
  `http_request_bytes`), mapping status to PubAuth (401/403) / PubConflict
  (409, version immutability) / PubRejected. `nurlpkg publish` packs the
  current project, prints its size + SHA-256, and uploads using the token
  from `$NURL_TOKEN` and the registry from `$NURL_REGISTRY` →
  `[package].registry` → default; a missing token or any non-2xx exits
  non-zero. The registry recomputes the checksum server-side — no
  client-supplied digest is trusted. Regression
  `compiler/tests/pkg_pack_basic.nu` (offline pack + gunzip + tar_parse
  membership: nested source included, deps/ + dotfiles excluded), clean
  under ASan/UBSan + leak-free. Verified end-to-end against a static
  `python` registry: a full **publish → install round-trip** (a library
  packed, uploaded with a Bearer token, then resolved + installed into a
  consumer's `deps/`), plus immutability (409), bad-token (401), and
  no-token rejections. This is the exact contract the Cloudflare
  Worker + R2 write endpoint (phase 6) will implement.

- **Verified registry install — `stdlib/ext/pkg_fetch.nu` (ROADMAP §4
  phase 4b).** The I/O side that turns a resolved `LockPkg` into files on
  disk against a static-HTTP registry (R2 + CDN shape). `pkg_fetch_index`
  GETs `<registry>/index/<name>.json`; `pkg_install_one` downloads
  `<registry>/pkgs/<name>/<name>-<v>.tar.gz`, **verifies its SHA-256
  against the recorded checksum**, gunzips, and path-safe `tar_unpack`s it
  into `<dest>/<name>` — composing the whole pure-NURL package stack (http
  binary body + sha256 + gzip + tar). Capstone regression
  `compiler/tests/pkg_install_e2e.nu` stands up a **loopback NURL registry
  server** (serves a real `tar_create`+`gzip` tarball + an index carrying
  its true checksum) and drives the full pipeline resolve → download →
  verify → unpack end-to-end, plus a wrong-checksum rejection
  (PkgChecksumMismatch); `NURL_NET_TESTS=1`. Clean under ASan/UBSan.

  **`nurlpkg install` is now registry-aware.** It resolves the manifest's
  registry deps (`foo = "^1.2"` or `{ version, registry }`), downloads +
  verifies + unpacks each into `deps/<name>`, and writes a `nurl.lock`
  whose registry entries carry `source = "registry+<url>"` + the tarball
  `checksum` (path deps keep their local source). The registry URL comes
  from `$NURL_REGISTRY` → `[package].registry` → a built-in default. A
  failed download or checksum mismatch makes `install` exit non-zero.
  Verified end-to-end against a static `python -m http.server` registry
  serving a GNU-`tar --format=ustar | gzip` package (differential interop):
  the happy path installs + locks with the `sha256sum`-computed checksum,
  and a tampered index checksum is rejected with the package left
  uninstalled.

- **Binary-safe HTTP response body — `http_body_bytes` / `http_body_len`.**
  `http_body_str` reads the response body through a NUL-terminated carrier
  (truncates at the first embedded NUL). The new `http_body_bytes` returns
  an owned, length-accurate `( Vec u )` copy, and `http_body_len` exposes
  the byte count — required for binary downloads (package tarballs, images,
  compressed payloads). Completes the binary HTTP story alongside the
  earlier binary-safe request body. Regression:
  `compiler/tests/http_response_binary.nu` (loopback server replies a
  5-byte `A B \0 C D` body; client confirms full length + the NUL via
  `http_body_bytes`; `NURL_NET_TESTS=1`). Clean under ASan/UBSan.
  `stdlib/ext/http.nu`.

- **Registry resolution core — `stdlib/ext/registry_index.nu` +
  `stdlib/ext/resolver.nu` (ROADMAP §4 phase 4).** The read side of the
  package registry. A registry serves a static JSON index per package at
  `<registry>/index/<name>.json` (versions, each with a tarball SHA-256
  `checksum`, `yanked` flag, and `deps`); tarballs live at the
  content-addressed `<registry>/pkgs/<name>/<name>-<ver>.tar.gz`, so the
  whole read path is a cacheable CDN with no compute.
  `registry_index.nu` parses an index and `regindex_select` picks the
  highest non-yanked version satisfying a semver requirement.
  `resolver.nu`'s `resolve_registry` walks the transitive dependency graph
  (BFS) and emits a `Vec[LockPkg]` ready for `lock_serialize` — the index
  fetcher is injected as a closure (`name → index-JSON`), so resolution is
  pure and offline-testable; nurlpkg will wire it to an HTTP GET. v1 policy:
  one version per name (first requirement wins; a later one must share that
  version or it's ResolveConflict), sub-deps from the parent's registry,
  path deps left to the existing symlink installer. Regressions:
  `compiler/tests/registry_index_basic.nu` (parse + select + yanked
  exclusion + tarball URL) and `compiler/tests/resolver_basic.nu`
  (transitive resolve with a mock index, ResolveNoMatch, ResolveNotFound).
  Both clean under ASan/UBSan and leak-free.

### Changed

- **Signedness is now coupled to the value's type instead of a free-floating
  side-channel — the structural fix for the whole `u`-vs-signed-`i8` bug
  class.** The LLVM type (`i8`/`i16`/`i32`) can't distinguish NURL's unsigned
  `u`/`u16`/`u32` from the signed types, so signedness travelled in a
  separate `__last_unsigned__` syms entry that each of ~83 value-producing
  sites had to remember to update — and ~67 didn't, leaving a stale flag
  that silently sign- or zero-extended the next widen (the source of a long
  run of miscompiles). Now signedness lives in `g_last_unsigned_p` right
  next to `g_last_type_ptr`, and **`nurl_set_last_type` always resets it**
  (signed default): every value-producing site already calls the type-setter
  (IR needs the type), so a stale "unsigned" can no longer leak. The handful
  of unsigned-PRODUCING sites assert it atomically with the type via
  `nurl_set_last_type_u` / `nurl_mark_unsigned`, and widen/op-selection
  readers consult `nurl_last_unsigned`. This eliminated the stale-leak
  subclass structurally; the migration also surfaced and fixed a latent gap
  the old leaky channel had masked by accident — bitwise `&`/`|`
  (`gen_bitwise_binary`) never set its result's signedness, relying on the
  last operand's flag happening to survive. Net: fewer, simpler, faster
  (a global vs a string-keyed map) and no longer forgettable. Bootstrap
  fixed point holds; full suite + ASan/UBSan green; 500 fuzzer seeds clean
  across every dimension.

### Fixed

- **Two more silent unsigned-widening miscompiles** (same `__last_unsigned__`
  side-channel hazard; fixed in `compiler/nurlc.nu`). Regression
  `compiler/tests/const_ternary_signedness.nu` (7 known-answer checks).
  1. **An unsigned global const load sign-extended.** `# i GU` over
     `: u GU 200` gave −56. `gen_const_decl` now records `<const>__unsigned`
     (which `gen_ident` already turns into `__last_unsigned__` on load).
  2. **A `?` (ternary) result didn't carry its arms' signedness.**
     `# i ? c (# u 200) (# u 100)` sign-extended the selected value.
     `gen_cond` now snapshots each arm's `__last_unsigned__` and sets the
     result flag (the arms share a type, so either suffices).

- **A call to an unsigned-returning function sign-extended at the call
  site.** `# i ( f )` where `f → u` returns 200 gave −56 (and likewise for
  `u16`/`u32`): the call site never carried the callee's return signedness
  onto the `__last_unsigned__` side-channel the enclosing widening cast
  reads (the LLVM return type i8/i16/i32 can't distinguish `u` from `i8`).
  `scan_fn_sigs` now records `<fn>__ret_unsigned` in the persistent pre-pass
  symbol table (the per-function `gen_fn_decl` scope doesn't reach call
  sites), and `gen_call` re-asserts it on `__last_unsigned__` after the
  call. Regression `compiler/tests/fn_return_signedness.nu` (5 known-answer
  checks). Bootstrap fixed point holds; full suite + ASan/UBSan green.

- **Narrow sized-int enum payloads now compile and round-trip correctly.**
  An enum variant carrying a `u`/`i8`/`u16`/`i16`/`u32`/`i32` payload (e.g.
  `: | E { None Val u }`) was accepted by the front-end but emitted invalid
  IR: `gen_agg_lit` only converted i64/i32 payloads into the enum's pointer
  slot (so an i8 payload hit `insertvalue …, i8 …` against a `ptr` field —
  clang reject), and `gen_match` only un-converted i1/i64 (storing a `ptr`
  into an `i8` binding). Now construction widens a narrow payload to i64
  (zext for an unsigned payload, sext for signed — from the payload
  signedness `gen_enum_decl` now records) before `inttoptr`, and the match
  `ptrtoint`s back and truncs to the payload width, carrying the payload's
  signedness onto the binding so a later widen zero-extends an unsigned
  payload. Found by hand-probing the fuzzer's struct dimension outward.
  Bootstrap fixed point holds; full suite + ASan/UBSan green. Regression
  `compiler/tests/enum_payload_signedness.nu` (5 known-answer checks).

- **Two silent struct-field signedness miscompiles** (same fuzzer, extended
  with a struct dimension; same root cause — the LLVM field type can't carry
  NURL's signedness). Both fixed in `compiler/nurlc.nu`; regression
  `compiler/tests/struct_field_signedness.nu` (8 known-answer checks);
  validated by 600 fuzzer seeds with the struct dimension.
  1. **Reading an unsigned field sign-extended.** `# i . rec u8field` over a
     `u`/`u16`/`u32` field holding e.g. 200 read back −56: `gen_member` never
     surfaced the field's declared signedness onto `__last_unsigned__`.
     `gen_struct_decl` now records `<S>__<field>__unsigned`, and both the
     value (extractvalue) and pointer (GEP+load) field-load paths set the
     flag from it.
  2. **Constructing a wider field from a narrower unsigned value
     sign-extended.** `@ Wide { # u 130 }` into an `i64` field stored −126
     instead of 130 — `gen_agg_lit`'s field-store widening hardcoded `sext`.
     It now picks `zext` when the field value is unsigned (the
     `__last_unsigned__` snapshot it already takes), `sext` otherwise.

- **Two silent integer miscompiles, found by a new differential fuzzer
  (`tools/fuzz`) and fixed at the root in `compiler/nurlc.nu`.** Both
  produced wrong values with no error — the worst class of bug.
  1. **Unsigned-byte cast widening sign-extended.** `# i64 # u 217` gave
     −39 instead of 217: a nested cast-to-unsigned never set the
     `__last_unsigned__` side-channel the enclosing widening cast consults,
     so it defaulted to `sext`. `gen_cast` now records the cast target's
     signedness for an enclosing widen / binop / shift. (Previously only
     casts whose subject was a typed *binding* — where `gen_ident` sets the
     flag — widened correctly.)
  2. **Signed `i8` arithmetic treated as unsigned.** `gen_binary` inferred
     unsignedness from the LLVM type `i8`, but both the unsigned NURL `u`
     and the *signed* `i8` lower to LLVM i8 — so signed i8 `/ % >> <`
     selected `udiv`/`urem`/`lshr`/`icmp u*` and the result was marked
     unsigned, silently zero-extending a negative value at the next widen.
     Signedness now comes solely from the `__last_unsigned__` flag (set by
     `gen_ident` from a binding's `__unsigned` and by `gen_cast` from an
     unsigned cast target), never from the ambiguous LLVM type.
  Bootstrap fixed point holds; full suite + ASan/UBSan green. Regression
  `compiler/tests/cast_signedness.nu` (12 known-answer checks). Validated
  by 340 fuzzer seeds (0 divergences).

- **Three silent int↔float conversion miscompiles** (same fuzzer, extended
  with float round-trip + comparison + store-coercion probes; fixed in
  `gen_cast`). Same root cause — the LLVM integer type can't carry
  signedness, so it must ride the `__last_unsigned__` side-channel.
  1. **Unsigned int → float used `sitofp`.** `# f # u32 0x80000001` became a
     *negative* float (≈ −2.1e9 instead of +2.1e9); `# f # u 200` became
     −56. Now `uitofp` when the source is unsigned.
  2. **Float → int ignored target signedness.** Now `fptoui` for an unsigned
     target (a value above the signed max no longer becomes poison), else
     `fptosi`.
  3. **A float result leaked its source int's stale unsigned flag.** After
     `# i64 # f # u …`, the still-set `__last_unsigned__` made a surrounding
     `*`/`/` pick `udiv` on a negative product (e.g. `−65 / 7` computed as
     an unsigned divide → garbage). Float-producing casts now clear the
     flag; float→int casts set it from the target. Regression
     `compiler/tests/cast_int_float.nu` (9 known-answer checks). Validated by
     600 fuzzer seeds with the new float dimension (0 divergences).

### Added

- **Differential fuzzer for `nurlc` integer codegen (`tools/fuzz`).**
  `gen.py` generates random sized-integer expression trees and, from the
  same tree, both a self-checking NURL program (prints each result's exact
  64-bit pattern) and a Python reference oracle with explicit
  two's-complement / width / signedness semantics. `fuzz.sh` compiles each
  at `-O0` and `-O2` and requires `stdout(-O0) == stdout(-O2) == oracle`,
  catching miscompiles that are wrong at every optimisation level. Biased
  toward the historically fragile surface (width coercions, unsigned
  arithmetic, mixed signed/unsigned); generates no UB. Found and fixed two
  silent miscompiles on its first run (see Fixed, above). See
  `tools/fuzz/README.md`. Subsequently extended with `let`-binding store
  coercion, variable reuse, comparison operators, and int→float→int
  round-trips — which surfaced three more (see Fixed).

- **USTAR tar reader + writer — `stdlib/ext/tar.nu`.** Pure-NURL POSIX.1-1988
  tar: `tar_create` (entries → archive bytes), `tar_parse` (bytes → entries,
  in-memory), and `tar_unpack` (path-safe extract to disk). Composes with
  `gzip_compress`/`_decompress` to make the `.tar.gz` package format the
  registry will use. The reader treats archives as untrusted input:
  `tar_unpack` rejects absolute paths and `..` components (TarUnsafePath) and
  refuses symlink/hardlink/device members (TarUnsupported) so nothing can
  escape the destination; every header checksum is verified (TarBadChecksum)
  and an over-long declared size is TarTruncated. v1 supports the 100-byte
  `name` field on write (TarPathTooLong otherwise) and honours the `prefix`
  field on read. Bidirectionally interop-tested against GNU tar (NURL→`tar
  xf` and `tar cf`→NURL both round-trip). Regression:
  `compiler/tests/tar_basic.nu` (round-trip incl. embedded NUL in file data,
  gzip composition, checksum tamper, `../` rejection, unpack + binary
  read-back); verified clean under ASan/UBSan. First building block of the
  registry-backed package manager (ROADMAP §4).

- **Semantic Versioning 2.0.0 — `stdlib/ext/semver.nu`.** Pure-NURL semver
  parse / compare / render with full precedence ordering, including the
  prerelease rules (§11: numeric < alphanumeric identifiers, fewer < more
  identifiers, prerelease < release; build metadata ignored). Plus
  **version requirements**: `semver_req_parse` turns a constraint (`^1.2.3`,
  `~1.2`, `>=1.0`, `<2.0.0`, `=1.2.3`, `1.*`, `*`, or a bare `1.2.3`) into a
  half-open range, `semver_req_matches` tests a version, and
  `semver_req_max_satisfying` picks the highest matching version — the
  resolution primitive the registry-backed package manager needs (ROADMAP
  §4). Constraint dialect is **Cargo-shaped**: a bare `1.2.3` means `^1.2.3`,
  use `=1.2.3` to pin. v1 matches prereleases by pure range containment (no
  Cargo-style prerelease comparator special-casing yet). Regression:
  `compiler/tests/semver_basic.nu` (round-trip, the canonical §11 precedence
  chain, every constraint operator, `max_satisfying`, parse errors); clean
  under ASan/UBSan and leak-free.

- **Registry-ready manifest + typed lockfile.** `stdlib/ext/manifest.nu`'s
  `Dep` gained a `registry` field and `Manifest` gained a default
  `[package].registry`, so a dependency can now be expressed as a path dep
  (`{ path = "…" }`), a bare registry dep (`foo = "^1.2"`, default
  registry), or an explicit registry dep
  (`{ version = "1.0", registry = "…" }`); `dep_is_path` / `dep_is_registry`
  discriminate. New `stdlib/ext/lockfile.nu` is a typed view over
  `nurl.lock`: a `LockPkg { name, version, source, checksum }` with
  `lock_serialize` (deterministic, name-sorted, Cargo-shaped `[[package]]`
  blocks; `source`/`checksum` omitted for path/local packages) and
  `lock_parse` / `lock_load` (round-trips through `toml.nu`'s
  array-of-tables). `checksum` is the hex SHA-256 of the package tarball —
  the integrity pin a registry install verifies. Regressions:
  `compiler/tests/manifest_registry.nu`, `compiler/tests/lockfile_basic.nu`;
  clean under ASan/UBSan, leak-free. ROADMAP §4 phase 3 (data model for
  registry deps). `nurlpkg`'s two `Dep` construction sites updated for the
  new field.

- **WebSocket client (RFC 6455 §4.1 + §5.3).** `stdlib/ext/websocket.nu`
  gained the full client side to match the existing server. `ws_connect`
  / `ws_connect_with` parse a `ws://…` / `wss://…` URL, dial out (plain or
  TLS-with-cert-verification via the runtime client-connect primitives),
  send the HTTP Upgrade request with a fresh random `Sec-WebSocket-Key`,
  and validate the `101` response's `Sec-WebSocket-Accept`. Outbound frames
  are masked with a CSPRNG-drawn 4-byte key (`ws_client_send_text` /
  `_binary` / `_ping` / `_pong` / `_close`, `ws_client_write_frame`,
  `ws_serialize_frame_masked`); inbound server frames are read and required
  to be unmasked (`ws_client_read_frame` / `_read_message` /
  `_serve_messages`, which auto-pong masked). The frame reader/assembler is
  now shared between both directions via an internal `__ws_read_frame_ex` /
  `__ws_read_message_ex` parameterised on direction — no duplicated framing
  logic. Regression: `compiler/tests/websocket_client.nu` (RFC 6455 §5.7
  masked-frame byte vector, URL parsing, and a live `NURL_NET_TESTS=1`
  client↔server echo round-trip proving interop with the server stack).
  Example: `examples/ws_client.nu` (pairs with `examples/ws_echo.nu`).

- **Binary-safe HTTP request bodies — `http_*_bytes` family.** The s-body
  `http_request` / `http_post` / `http_put` family recovers the body length
  via `strlen`, so a request body with embedded NUL bytes (binary file
  uploads, MessagePack, protobuf) truncated at the first NUL. New
  length-carrying variants take the body as a `( Vec u )` and ship it via
  `CURLOPT_COPYPOSTFIELDS` + an explicit `POSTFIELDSIZE`, so the exact byte
  count is sent: `http_request_bytes` / `http_request_bytes_to`,
  `http_post_bytes`, `http_put_bytes`, and the streaming
  `http_stream_open_bytes_to`. The `body` argument is borrowed (the caller
  still owns it). Binary fidelity requires the libcurl backend; the
  WinHTTP/stub fallback round-trips through a NUL-terminated `s` and
  degrades to the old truncation. `stdlib/ext/http.nu`.

### Fixed

- **Reverse-proxy request body is now binary-safe + a latent use-after-free
  is closed.** `proxy_stream_to_conn_with` forwarded the upstream request
  body by converting the request's `( Vec u )` body to a NUL-terminated `s`
  and shipping it through `CURLOPT_POSTFIELDS` (strlen-sized), truncating
  binary uploads at the first NUL. Worse, the streaming opener set
  non-copying `CURLOPT_POSTFIELDS` and the proxy freed the body buffer
  *before* the first `multi_perform` read it — a dangling-pointer read that
  only escaped notice on small JSON bodies. Both are fixed by routing the
  length-tracked body through `http_stream_open_bytes_to`, which uses
  `CURLOPT_COPYPOSTFIELDS` (libcurl snapshots the bytes at open time, so the
  caller may free immediately and embedded NULs survive). Regression:
  `compiler/tests/http_binary_body.nu` (NURL client `http_post_bytes` of a
  5-byte `A B \0 C D` body to a loopback NURL server, asserting the server
  parsed all 5 bytes; `NURL_NET_TESTS=1`). Verified clean under ASan/UBSan.
  `stdlib/ext/http.nu`, `stdlib/ext/http_proxy.nu`.


## [0.9.4] — 2026-06-02

### Added

- **Keyword arguments — default parameter values + named call arguments.**
  A trailing parameter may carry a default: `@ f s a s b = `x` i n = 3 → R`
  (the default is a single source token — literal / const / atom). A call
  may then omit defaulted trailing arguments — `( f val )` — and/or pass
  arguments by name in any order, mixed with leading positional ones:
  `( f a: 1 b: 2 )`, `( f val n: 5 )`, `( greet greeting: `Hi` name: `Bob` )`.
  Implemented as a call-site desugaring to an ordinary positional call:
  `scan_fn_sigs` records each function's parameter names + default sources;
  `gen_call` fills omitted trailing defaults inline, and routes a call that
  uses `name:` labels through `gen_call_kwargs`, which evaluates arguments
  in source order and assembles them in parameter order. Existing positional
  calls take the unchanged path (byte-identical IR — bootstrap fixed point
  holds). Regression: `compiler/tests/kwargs.nu`. Current limits (documented
  in the grammar): not on generic functions, FFI/variadic, or parameters
  with the `inout`/`sink` convention; `**kwargs`-style collection is not
  provided (pass a `Json`/struct).

- **BLAKE3 hash (pure NURL) — completes the hash family.** New
  `stdlib/std/hash_blake3.nu` implements full BLAKE3 (the ChaCha-derived
  compression function, 1024-byte chunks split into 64-byte blocks with
  CHUNK_START/CHUNK_END flags, the binary Merkle tree of chaining values,
  and the ROOT-flagged final node), exposed via `blake3_bytes` /
  `blake3_hex` in `stdlib/std/hash.nu` (unkeyed, 32-byte output). All-NURL
  u32 wrapping arithmetic, little-endian, binary-clean over `( Vec u )` —
  **no C at all** (compiler and runtime untouched). Verified
  digest-for-digest against the official BLAKE3 reference across every
  structural path (empty, sub-block, the 1024-byte single chunk, the
  1025-byte two-chunk boundary, balanced multi-chunk trees up to 5000
  bytes); regression `compiler/tests/blake3.nu`; clean under ASan/UBSan/LSan.
  Closes the ROADMAP "Extended Hash Family" item — SHA-1/256/512, MD5,
  HMAC, and BLAKE3 are all shipped.

- **`volatile_load` / `volatile_store` compiler intrinsics for MMIO.** Emit
  `load volatile` / `store volatile` as pure IR (no runtime call, so they
  work on a freestanding target). The optimizer can no longer hoist an MMIO
  read out of a polling loop (LICM), reorder accesses, or coalesce repeated
  reads/writes — the missing piece for spinning on a device status register
  at `-O2`. The access width comes from the typed pointer argument (`*T`),
  so one pair covers i8/i16/i32/i64. `stdlib/hal/mmio.nu`
  (`mmio_read32`/`write32`/`set32`/`clear32`) now uses them, so the ESP32
  UART/GPIO drivers no longer need the `-O0` workaround. Regression:
  `compiler/tests/volatile_mmio.nu`; verified at `-O2` the volatile load
  stays inside the loop body.

- **ESP32 bare-metal register HAL (`stdlib/hal/esp32.nu`).** Pure-NURL GPIO
  and UART0 over the chip's memory-mapped registers (built on
  `stdlib/hal/mmio.nu`) — no ESP-IDF, no FFI. GPIO output enable / set /
  clear, and a blocking UART console (`esp32_uart_putc` / `getc` / `puts`
  with FIFO-count helpers), with register addresses taken from the ESP32 TRM
  and cross-checked against ESP-IDF's `soc/*_reg.h`. Demonstrated by the new
  fully-NURL UART echo example (`examples/esp32/idf-uart`).

- **C64 emulator example (`examples/c64`).** A MOS 6510 / Commodore 64
  emulator in pure NURL — a single `core.nu` engine shared by a native CLI
  and a WebAssembly browser front-end. The CPU core passes Klaus Dormann's
  `6502_functional_test` (the canonical 6502 correctness oracle, validated
  headlessly), and with stock KERNAL/BASIC/CHARGEN ROMs the machine boots
  through the full power-on sequence — PLA banking, CIA1 jiffy IRQ — to the
  BASIC `READY.` prompt.

### Fixed

- **nurlfmt split hex/binary/octal integer literals.** The tokenizer's
  numeric scanner stopped at the first non-decimal digit, so `0x3FF44008`
  became two tokens (`0` + identifier `x3FF44008`) and the reformatted
  source miscompiled — silently, because `--check` is idempotent on its own
  broken output. `tools/nurlfmt/tokenize.nu` now scans a `0x`/`0b`/`0o`
  prefix and its body as one token. Verified by the
  `nurlfmt_idempotent.sh` gate (450 files, IR-transparent) and by restoring
  the hex literals in the `examples/esp32/*` register maps that had been
  worked around with decimal constants.

- **SQLite production hardening (Tier 1 + Tier 2).** `stdlib/ext/sqlite.nu`
  is now binary-safe and resource-safe:
  - **NUL-safe text I/O.** `sqlite_column_text` reads the column's exact
    byte length via `sqlite3_column_bytes` (was `strlen`, which truncated
    at the first embedded NUL), and `sqlite_bind_text` now takes a `String`
    and passes an explicit byte length to `sqlite3_bind_text` instead of
    `-1` — strings with embedded NULs round-trip intact.
  - **BLOB support.** New `sqlite_bind_blob` (`Vec u` → `sqlite3_bind_blob`
    + `SQLITE_TRANSIENT`) and `sqlite_column_blob` (`sqlite3_column_blob` +
    `_bytes` → owned `Vec u`) — the binary-safe write/read path.
  - **`sqlite_open_v2` with open flags.** `SQLITE_OPEN_READONLY` /
    `READWRITE` / `CREATE` / `URI` / `NOMUTEX` / `FULLMUTEX` / `NOFOLLOW`
    constants exposed; `sqlite_open` is now `READWRITE|CREATE` over
    `open_v2`. A read-only connection refuses writes (new `SqliteReadOnly`
    error variant) instead of silently creating a file.
  - **`sqlite_busy_timeout`** wraps `sqlite3_busy_timeout` so `SQLITE_BUSY`
    blocks-and-retries under concurrent access rather than failing
    immediately.
  - **`% Drop` auto-close.** `Database` and `Statement` implement the Drop
    trait; a scope-local handle — including one unwrapped from a
    `! Database E` / `! Statement E` result in a match arm — closes itself
    on every path (Ok, Err, early return) with no manual
    `sqlite_close`/`sqlite_finalize`. Teardown zeroes the handle slot after
    closing, so a stale internal re-entry is a no-op. Verified leak-free
    and double-free-free under ASan + UBSan (`compiler/tests/sqlite_hardening.nu`).
  - **Tier 3 — datatypes & transactions.** `sqlite_bind_double` /
    `sqlite_column_double` (REAL columns), `sqlite_column_is_null`,
    `sqlite_begin` / `commit` / `rollback`, and a closure-based
    `with_transaction` that COMMITs on `Ok` and ROLLBACKs on `Err`
    (propagating the original error).
  - **Tier 4 — hardening for untrusted SQL/DB.** Extended result codes are
    enabled on every open, so constraint failures now map to distinct
    variants (`SqliteConstraintUnique` / `…ForeignKey` / `…NotNull` /
    `…PrimaryKey` / `…Check`). Added `sqlite_last_insert_rowid`;
    `sqlite_set_defensive` / `sqlite_enable_load_extension` /
    `sqlite_harden` (DEFENSIVE on + extension-loading off — blocks
    corruption/RCE from a hostile DB); `sqlite_limit` (bound query
    complexity); a closure-based `sqlite_set_authorizer` /
    `sqlite_clear_authorizer` that installs a sandbox callback with the
    exact C ABI libsqlite expects (the closure's compiled function +
    captured env are passed as `xAuth` + `pUserData`, the same mechanism
    `thread_spawn` uses for `pthread_create` — no C bridge); and PRAGMA
    helpers `sqlite_journal_wal` / `sqlite_foreign_keys` /
    `sqlite_synchronous`. Verified under ASan + UBSan
    (`compiler/tests/sqlite_tier34.nu`).

### Changed

- **Match-arm payload bindings now participate in auto-drop.** A `% Drop`
  type bound as a `??` match-arm payload (e.g. `?? r { T db → … }`) — or a
  `:` let inside a match arm — is now dropped at arm scope exit, on the same
  void-arm-only rule used for owned strings/structs. Previously such
  bindings were never dropped (a latent leak); this is what lets the SQLite
  handles above close automatically in the idiomatic result-unwrap flow.

### Documentation

- **ROADMAP brought up to date.** The Status header now reads **Grammar v2.1**
  (was v2.0) and points at `spec/grammar.ebnf`. Items that were marked pending
  but are in fact shipped are now `[x]`: the **async runtime** (stackful M:N
  fibers — the Coroutines-vs-async/await decision is settled), **HTTP server
  Phase 8** (production hardening) and **Phase 9** server-side (TLS+SNI+ALPN+
  mTLS+reload, HTTP/2, WebSocket — client-side remains), the **optional
  `-lcurl`** sentinel-gated linking, and the **`nurlc_lastgood.nu` refresh**
  lifecycle (documented via `--refresh-bootstrap`). Added an explicit
  "What's actually left" summary to the Status section (HTTP/2+WebSocket
  client-side; mobile/`no_std` targets; SQLite BLOB/double; reverse-proxy
  binary bodies; blake3; MCP SSE/sessions/auth; the `runtime.c` file-split;
  a compiler-embedded LLM; bench peers). Stale build-size figures left only
  in dated historical "shipped" entries (records, not current claims).

- **Removed hard-coded build-artifact sizes from the reference docs.** The
  `~480 KB nurlc.wasm` (`docs/PLAYGROUND.md`) and `~1.6 MB`
  `nurlc_lastgood.ll` (`docs/BUILDING.md`) figures drift every build and
  mislead when the real artifact differs. Build sizes belong in the
  changelog/release notes (tied to a specific version), not in
  instructional docs.

- **Cleaned stale `GOTCHAS.md item N` / `§N` references out of code comments.**
  After `docs/GOTCHAS.md` lost its numbered list, ~44 source comments (in
  `compiler/nurlc.nu`, the `nurlc_lastgood.nu` snapshot mirror, nine
  `compiler/tests/*.nu`, and `stdlib/ext/{http_middleware}.nu`) still pointed
  at item/section numbers that no longer exist. Each now points at the real
  home (escape/lifetime → `docs/MEMORY.md` §2.3, grammar → `docs/LIMITATIONS.md`)
  or simply describes the behaviour inline. The `nurlc_lastgood.nu` edits are
  comment-only — verified to produce byte-identical IR, so the committed
  bootstrap `nurlc_lastgood.ll` is unchanged; the build still reaches its
  fixed point and the full test suite passes.

- **`docs/GOTCHAS.md` reduced to "Currently no known gotchas."** Every
  source-level trap is now a compiler diagnostic (`error:`/`warning:` with a
  caret + cure), so the page no longer lists a museum of resolved issues.
  The real content that lived there was relocated to its proper home: the
  fiber-runtime operational caveats (non-blocking handle flipping,
  `runtime_run` blocking, stack-borrow capture, plus runtime-maintainer
  notes on TLS-under-LTO and the reactor park/unpark ordering) moved to
  [`docs/ASYNC.md`](docs/ASYNC.md) → Operational caveats, and the
  `: ~`-capture lifetime rule now points at [`docs/MEMORY.md`](docs/MEMORY.md)
  §2.3. Updated every back-reference (`docs/spec.md`, `docs/LIMITATIONS.md`,
  `ROADMAP.md`'s "5 active quirks" status line, the VS Code extension
  README, and stale `GOTCHAS.md item N` comments in `stdlib/ext/toml.nu`,
  `mcp_http.nu`, `http_multipart.nu`). All internal links verified.
- **`docs/LIMITATIONS.md` scoped to actual language/compiler limitations.**
  Removed the standard-library capability tables (PostgreSQL, SQLite,
  panic/recover) that were never language limitations — that information
  lives with each module (stdlib headers, `ROADMAP.md`). Moved
  the HTTPS/TLS table to [`docs/NETWORKING.md`](docs/NETWORKING.md) where it
  belongs. Removed two entries that were **stale** (the behaviour already
  works, verified empirically): "no tail-call optimisation" (self-recursive
  tail calls emit `tail call` → LLVM sibcall-opt; 50M-deep tail recursion
  runs without overflow) and "enum forward references unsupported"
  (`scan_type_names` registers type names before codegen, so a struct
  payload can be declared after its enum). The page now lists only
  language/compiler constraints (Type system, Functions/calls, Enums,
  Imports, Grammar).
- **Playground now renders linked docs instead of 404ing.** Clicking a
  relative link inside a rendered doc (e.g. `docs/LIMITATIONS.md` from the
  README, or `../spec/grammar.ebnf` from a `docs/` page) used to hit "not
  found". `nurlapi` now serves the repo doc tree by its natural path —
  `/docs/*`, `/spec/*`, `/bench/*`, and the capitalised top-level
  `/README.md` · `/ROADMAP.md` · `/CHANGELOG.md` · `/CONTRIBUTING.md` —
  rendering `.md` to HTML (`__serve_repo_doc`, path-traversal-guarded) and
  serving other files as text; `examples/*.md` renders too (`.nu` stays
  JSON for the editor). Because the route hierarchy mirrors the repo, the
  browser's own relative-link resolution chains correctly between docs. The
  container image now copies the **whole `docs/` tree** (was only
  `GOTCHAS.md`) plus `CHANGELOG.md`, `CONTRIBUTING.md`, and `bench/`.
- **README refactored into a slim overview + topic docs.** The 991-line
  kitchen-sink README is now a ~230-line overview (why/principles,
  architecture, quick start, syntax-at-a-glance, a documentation index, and
  project layout) that links out to focused pages under `docs/`. New:
  `docs/BUILDING.md`, `docs/TOOLING.md`, `docs/PLATFORMS.md`,
  `docs/PLAYGROUND.md` (HTTP API + playground + MCP), `docs/NETWORKING.md`
  (sockets + MQTT), `docs/LIMITATIONS.md`. Syntax/type/memory sections now
  point to the existing authoritative homes (`spec/grammar.ebnf`,
  `docs/spec.md`, `docs/MEMORY.md`) instead of duplicating them.
- **Removed stale / frequently-changing content.** The README no longer
  hard-codes a grammar version, benchmark tables (point to `bench/`), the
  example file list, the MCP tool count, or the `.vsix` version. The
  PostgreSQL "Known Limitations" (claimed no binary protocol / async /
  LISTEN-NOTIFY / COPY — all shipped) and the MQTT section (TLS-only +
  verify-on-by-default + exactly-once QoS 2 + `subscribe_many`) are now
  accurate. Dropped references to non-existent `spec/types.md` / `ir.md` /
  `bootstrapping.md`, fixed `CONTRIBUTING.md`'s `api/` → `nurlapi/`, a dead
  `HTTP_SERVER_PLAN.md` link in `ROADMAP.md`, the compiler's prefix-arity
  diagnostic (pointed at the moved README section → `docs/LIMITATIONS.md`),
  and `docs/GOTCHAS.md`'s cross-reference. All internal doc links verified.

### Added

- **MQTT: multi-topic SUBSCRIBE** (`mqtt_subscribe_many`) sends one
  SUBSCRIBE for N filters at a shared max QoS and validates every
  per-filter SUBACK reason code (a new `__mqtt_check_suback` that parses
  the property block instead of assuming a single trailing byte —
  `mqtt_subscribe_qos` now uses it too).
- **PostgreSQL advanced protocol features — binary, async, LISTEN/NOTIFY,
  COPY** (`stdlib/ext/postgres.nu`). Closes the last Tier-5 Postgres gap;
  all four are pure-NURL libpq FFI (no `runtime.c` bridge) and are
  exercised end to end by the new `examples/pg_advanced.nu`, live-verified
  against PostgreSQL 16.14.
  - *Binary result protocol*: `pg_exec_params_binary` requests
    `resultFormat = 1`; `pg_get_i16_bin` / `_i32_bin` / `_i64_bin` /
    `_bool_bin` / `_f64_bin` decode network-byte-order cells (`float8`
    reinterpreted from its IEEE-754 bit pattern, not a numeric cast), with
    `pg_get_length` / `pg_field_format` / `pg_binary_tuples`.
  - *Asynchronous queries*: `pg_send` / `pg_send_params` dispatch without
    blocking; `pg_get_result` (→ `?PgResult`, `None` when finished) and the
    blocking convenience `pg_await` collect results; `pg_consume_input` /
    `pg_is_busy` / `pg_socket` / `pg_flush` / `pg_set_nonblocking` hook into
    an event loop.
  - *LISTEN/NOTIFY*: `pg_listen`, `pg_notify_send`, `pg_notifies`
    (→ `?PgNotify { relname, be_pid, extra }`, read after
    `pg_consume_input`) and `pg_notify_free`.
  - *COPY*: `pg_copy_start` (accepts the `PGRES_COPY_IN` / `COPY_OUT`
    handshake that plain `pg_exec` rejects), `pg_put_copy_data` /
    `pg_put_copy_str` / `pg_put_copy_end` for `COPY … FROM STDIN`, and
    `pg_get_copy_data` (→ `?String`) for `COPY … TO STDOUT`.

### Fixed

- **Compiler: `??`-match on a result/option-typed *parameter* dropped its
  payload.** `@ f !S E r → S { ?? r { T x → ^ x } }` emitted `ret i64`
  against the `%S` return type (an LLVM "value doesn't match function
  result type" error), and the same gap mishandled a `( Vec u )` handle
  payload and dropped the unsigned flag on a `?u` parameter (sign-extending
  a byte ≥ `0x80`). `gen_fn_param` now records the
  `<param>__res_nurl_T` / `__res_t_llvm` / `__res_e_llvm` / `__opt_nurl_T`
  metadata that `gen_let_or_struct` already records for let-bound result
  vars, so `gen_match` reconstructs struct / pointer / unsigned payloads
  for a parameter scrutinee exactly as it does for a let binding. Bootstrap
  fixed point held; regression `compiler/tests/match_param_payload.nu`.
- **Compiler: an empty block `{}` returned from a void function emitted
  invalid IR.** An empty block is the unit/void value, but `gen_block` left
  the "last type" at whatever preceded it (i64 by default, i1 inside a
  conditional), so `^ {}` in a void function produced `ret i64 undef` —
  rejected by LLVM. The block now types as `void` when it has no trailing
  statement.
- **Compiler: undefined identifier in value position no longer emits an
  undefined SSA value with exit status 0** (PR #25 / `Fixes`). `gen_ident`'s
  bare `%<name>` fallback fired for *any* name lacking a `__ptr` / `__global`
  binding — so `: i x ^ a b c` emitted `ret i64 %a` that nurlc accepted and
  only clang rejected. The fallback now requires a by-value parameter and
  otherwise dies with "use of undefined identifier". This was critic.md §4's
  headline contradiction of "every trap is a compiler diagnostic".
  Regression `compiler/tests/should_fail_undef_ident.nu`.
- **Compiler: a within-statement prefix-arity cascade that swallowed the
  next `^` silently returned early** (PR #25 / `Fixes`). `: i x + 1` /
  `^ a` parsed as `+ 1 (^ a)` → `ret %a` plus a dead `add`, exiting 0. A new
  `g_ret_forbidden` flag (armed by a `gen_operand` wrapper around every
  value-operand parse, reset by `gen_stmt` and the `?` / `??` arm bodies)
  makes `gen_ret` refuse to emit a `ret` in operand position. Regression
  `compiler/tests/should_fail_cascade_caret.nu`.
- **Compiler: `??`-match on a direct-call scrutinee dropped pointer/handle
  payloads and option signedness** (PR #25 / `Fixes`). `: ( Vec u ) x ?? ( f
  … ) { … }` / `: s x ?? ( f … ) { … }` left the binding `undef` (no T-arm
  reconstruction, no result phi) for handle/pointer payloads, and `?? (
  vec_get [u] … ) { T b → # i b }` sign-extended an unsigned byte. The
  callee's Ok/Err-payload LLVM types and option-inner token are now recorded
  per function and surfaced to `gen_match`'s direct-call synthesis (with a
  bare-`i8*` inttoptr path for both arms). Regressions
  `compiler/tests/match_bind_call_handle.nu`, `match_call_opt_unsigned.nu`.
- **Compiler: option/result construction from a sized-int literal didn't
  truncate** (PR #25 / `Fixes`). `@ ?u { T 0x86 }` emitted `insertvalue {
  i1, i8 } …, i64 134, 1`, which clang rejected. `gen_agg_lit`'s opt/res
  payload coercion now truncs/sexts/zexts the literal to the payload width
  (option = T's real width, result = i64). Regression
  `compiler/tests/opt_lit_payload_width.nu`.
- **MQTT inbound QoS 2 is now exactly-once.** A retransmitted (DUP)
  QoS 2 PUBLISH was acknowledged but re-delivered to the application. The
  client now tracks inbound packet ids across their PUBREC…PUBCOMP window
  (`MqttClient.qos2_rx`, bounded, oldest evicted past 256), acknowledges a
  duplicate but delivers it only once. `__mqtt_parse_publish` returns
  `?MqttMessage` (None on a de-duplicated retransmit) and the dedup policy
  is unit-tested in `compiler/tests/mqtt_qos2_dedup.nu`. The doc-drift
  comment on `__mqtt_do_publish` (claimed a fixed packet id) was corrected.

### Security

- **MQTT TLS certificate verification is now configurable and on by
  default.** `mqtt_connect_cfg` / `mqtt_reconnect` previously hard-coded
  `verify = F`, so every TLS connection was effectively `--insecure`
  (MITM-able). `MqttConfig` gained a `tls_verify` field, threaded through to
  `tcp_connect_tls`; `mqtt_config` defaults it to T (peer-cert chain + host
  name verified against the system trust store). Set it F only for a
  self-signed broker in a trusted environment.
- **`pg_listen` SQL injection (critical) — fixed.** A channel name is a SQL
  *identifier* and cannot be a bound parameter, so it now goes through
  `pg_escape_identifier` (PQescapeIdentifier) before interpolation; raw
  concatenation previously let `pg_listen c "x; DROP TABLE …; --"` execute
  the injected statement. (`pg_notify_send` was already safe — it binds the
  channel as a value to `pg_notify($1, $2)`.)
- **Out-of-bounds read in the binary accessors (medium) — fixed.** A new
  `PQgetlength`-checked `__pg_bin_ptr` guards every `pg_get_*_bin`:
  reading an `int4` cell with the 8-byte `pg_get_i64_bin`, or any accessor
  on a binary SQL `NULL` (0 bytes), now returns `0` instead of reading past
  the cell into adjacent libpq buffer memory.
- **TLS is not verified by default — documented.** `pg_connect` and the
  file header now carry a prominent warning that libpq's default
  `sslmode=prefer` neither prevents a silent plaintext fallback nor
  verifies the server certificate (MITM-able), recommending
  `sslmode=verify-full sslrootcert=…` for non-local connections. Not
  force-defaulted, as that would break legitimate unix-socket / trusted-LAN
  connections. Minor: `pg_get_bool` gained a NULL-pointer guard, and the
  empty-on-NULL behaviour of `pg_escape_literal` / `pg_escape_identifier`
  is now documented.

## [0.9.3] — 2026-05-31

### Summary

A full **Game Boy (DMG) emulator written in NURL** now plays commercial
games with sound. `examples/gameboy/` passes Blargg `cpu_instrs` 11/11,
`instr_timing` and `02-interrupts`, is 100 %/pixel-perfect on dmg-acid2,
and runs *Tobu Tobu Girl* end to end — full gameplay plus a complete
4-channel APU mixed to stereo — in the browser at `/gameboydemo` via the
WebAssembly target. Building it drove three new language/compiler
features (**hex/binary integer literals**, pointer/aggregate global
initialisers, hex literals in `match`) and turned one
silently-accepted bare-literal statement into a hard compile error.

**Generics now range over option and pointer element types** — `Vec ?T`,
`vec_get [?T] → ??T`, `??T` parameters/returns and nested `??` matching
all compile (five front-end root-cause fixes). The PostgreSQL client is
**production-grade** (`stdlib/ext/postgres.nu` + `examples/psql.nu`),
including option-typed nullable params and getters
(`pg_exec_params_opt`, `pg_get_opt`), verified live against
PostgreSQL 16 under AddressSanitizer.

HTTP/2 + HPACK + WebSocket conformance suites remain green: h2spec 2.6.0
reports 146/146 cases against `examples/h2c_server.nu`; the
autobahn-testsuite fuzzing client reports 294 OK / 4 NON-STRICT /
3 INFORMATIONAL / 0 FAILED across all 301 RFC 6455 cases against
`examples/ws_echo.nu`. Both binaries run under ASan + UBSan
without findings.

Bootstrap fixed point at 1 772 342 B (stage1 ≡ stage2 byte-identical
IR).

### Added

- **Game Boy (DMG) emulator — `examples/gameboy/`.** A cycle-aware Sharp
  LR35902 core (every opcode + CB-prefix, exact Z/N/H/C flags + DAA,
  EI/DI IME enable-delay, HALT + HALT-bug, DIV/TIMA timer, interrupt
  dispatch) passing **Blargg `cpu_instrs` 11/11, `instr_timing` and
  `02-interrupts`**; a BG/window/sprite PPU that is **100 %/pixel-perfect
  on dmg-acid2** (0/23040 diff — LYC raster + window internal line
  counter); MBC1/3/5 mappers, joypad and OAM DMA; and a complete
  **4-channel APU** (2 square w/ sweep, 4-bit wave RAM, 15-bit-LFSR
  noise, 512 Hz frame sequencer, NR50/51 mix, DMG high-pass) mixed to
  stereo. The engine is split into a shared `core.nu` with `gb.nu` (CLI)
  and `gb_wasm*.nu` (wasm32-wasi → canvas) front-ends; the browser demo
  at **`/gameboydemo`** auto-starts *Tobu Tobu Girl* and plays it with
  sound through the playground audio shim. Two sub-instruction timing
  fixes (TIMA increments on the DIV falling edge; the fetch M-cycle is
  clocked before the instruction body) took it from a title-screen crash
  to full gameplay. Build the wasm at `-O2` (lower `-O` leaks the C
  shadow-stack pointer on the interrupt-dispatch path).
- **Generics over option / pointer element types.** Option (and pointer)
  element types are now first-class generic type arguments:
  `vec_get [?String] → ??String`, `Vec ?T` / `vec_push` / `vec_set` /
  `vec_free_with`, `??T` as a parameter and return type, and nested
  `?? o { T inner → ?? inner { … } }` matching all compile — every one of
  these previously failed at compile time. Five front-end root-cause
  fixes, each verified by a full bootstrap + test-suite run and an
  ASan-clean probe: (1) `parse_type_optopt` for the fused `??T` token;
  (2) `capture_type_arg_src` + `nurl_src_to_llvm` + an `opt_`
  mangle/demangle round-trip so compound type args like `[?String]` are
  one substitutable word; (3) `;`-separated closure parameter types so an
  aggregate type (`{ i1, %String }`) no longer truncates at its first
  space; (4) slice-vs-pointer store discrimination; (5) `int → aggregate`
  zeroinit. Test corpus on branch `feature/generic-option-types` (PR #21).
- **Hex / binary integer literals — `0xFF`, `0b1010`.** Added to the
  number lexer; the token carries the parsed value and keeps its spelling
  for diagnostics. Two companion compiler fixes: pointer- and
  aggregate-typed global initialisers (`: s g 0` → `global i8* null`,
  `: String g 0` → `zeroinitializer`, `inttoptr` for a nonzero address),
  and hex-literal normalisation in `match` (int-patterns `?? op { 0xCB →
  … }` and enum field-constraints `Code 0xFF → …` are rewritten to
  decimal before the `icmp`, since LLVM reads `0x…` as a hex float).
  Regression test `compiler/tests/hex_literals.nu`.
- **Production-grade PostgreSQL client + `psql` CLI.**
  `stdlib/ext/postgres.nu` reaches production grade: a `PgParams` builder
  (`pg_bind_text/str/int/bool/null`) for typed + NULL parameter binds the
  libpq/pgx way, `pg_prepare` / `pg_exec_prepared`, `pg_run`,
  `pg_begin/commit/rollback`, typed getters (`pg_get_int/f64/bool`),
  `pg_reset` / `pg_err_msg` / `pg_server_version` / `pg_escape_literal` /
  `pg_escape_identifier`, and — now that generics range over option types
  — option-typed nullable params/getters `pg_exec_params_opt
  ( Vec ?String )`, `pg_get_opt → ?String`, `pg_get_opt_int → ?i`. New
  `examples/psql.nu` (aligned-table renderer, command tags, multi-line
  `;` accumulation, `\dt \d \l \du \conninfo` meta-commands, `-c "SQL"`
  one-shot) and `examples/pg_optional.nu`. Verified live against
  PostgreSQL 16 under ASan (PRs #20 / #22).
- **Audio output in the WASM playground.** An `env.audio_out_push` host
  shim streams packed-stereo `i64` samples to 48 kHz Web Audio, letting
  WASM programs emit sound; demonstrated by `examples/audio_tone.nu` and
  used by the Game Boy demo's APU output.
- **Trait bounds on generic functions — `[A: Trait]`.** A generic type
  parameter may now carry one or more trait bounds: `@ my_max [A: Ord] A
  x A y → A { … }`. Trait-method dispatch inside a generic body already
  resolved to the concrete `impl` through monomorphisation (dispatch is
  keyed on the first argument's LLVM type, which becomes concrete at
  instantiation); the bound adds the up-front guarantee. `scan_impl_decl`
  now registers each `% Trait Type {}` as `Trait##<llvm>` in
  `g_trait_syms`; `gen_generic_fn_store` records per-tparam bounds; and
  `check_generic_bounds` (called from `gen_call` at every generic call
  site) verifies each bounded tparam's concrete type has the impl —
  turning a missing impl from a cryptic unresolved-call link error into a
  clear "type 'X' does not implement trait 'Y' required by bound A: Y"
  diagnostic. Generic detection in `gen_fn_decl` extended to recognise a
  colon anywhere in the `[…]` (a slice param's type never contains one).
  This removes the need to pass `Ord`/`Hash`/`eq` closures into generic
  helpers when an `impl` exists. Tests `compiler/tests/trait_bounds.nu`
  (positive, i + String) and `should_fail_trait_bound.nu` (bound
  violation → COMPILE FAIL). Bootstrap fixed point holds (stage1 ≡ stage2
  byte-identical at 1 730 148 B).
- **`??` match guards + or-patterns.** Two additions to `gen_match`:
  - **Guards** — `Pattern payloads ? <cond> → body`. The guard is
    evaluated *after* payload binding (so it can read the bound
    payloads); a false guard falls through to the next arm. Implemented
    by recording the guard's source span during arm parse and replaying
    it via `nurl_lex_set_pos` at the arm body, branching to the body or
    the next arm. A guarded arm does NOT satisfy exhaustiveness for its
    variant — a catch-all (unguarded or `_`) is still required. Not
    allowed on a `_` wildcard arm or combined with an or-pattern.
  - **Or-patterns** — `A | B | C → body`: several tag-only named
    variants share one body (`emit_or_chain` lowers the alternatives to
    a tag-compare chain). No payload binding or literal constraints; all
    listed variants count toward exhaustiveness.

  Test `compiler/tests/match_guards_or.nu`. Bootstrap fixed point holds
  (stage1 ≡ stage2 byte-identical at 1 720 428 B).
- **Compile-time const folding for integer globals.** A top-level
  integer const (`: i NAME …`, or u / sized ints — not `b`) may now take
  a prefix expression over integer literals instead of a single literal:
  `+ - * / << >> & | ^^` (not `%`, which collides with the trait/impl
  decl sigil at scan time). `const_eval_int` in `gen_const_decl` folds it
  to one value. Fixes the long-standing wart where e.g. the
  two's-complement minimum needed a niladic helper — `stdlib/std/int.nu`
  now exposes `: i INT_MIN - -9223372036854775807 1` directly
  (`int_min_val` retained, delegating to it). Transparent (computes a
  value, hides no control flow); fits the parse-directed architecture.
  Test `compiler/tests/const_eval.nu`. Bootstrap fixed point holds.
- **`select` over channels — `?? { … }`** — Go-style select. A `??`
  whose scrutinee is immediately `{` (no value to match) is a channel
  select; each arm `[T] ch → bind { body }` receives from one channel
  and the construct proceeds with the first ready arm. With no `_`
  default it BLOCKS until some channel is ready (value sent or channel
  closed); a `_ → { … }` default makes it non-blocking. `bind` is the
  `?T` the receive yields (None ⇒ closed). Arms are heterogeneous (each
  channel may carry a different element type) and tried in source order.
  Implemented in `gen_select` (compiler/nurlc.nu) as a desugaring that
  synthesises NURL source from the verbatim user channel-exprs + bodies
  and compiles it through a sub-lexer — no raw IR, no new lexer token.
  The blocking rendezvous (a shared `SelectWaiter` armed on every
  channel, fired by senders/closers under the channel mutex) lives in
  `stdlib/std/channel.nu` via the type-erased `chan_raw_poll` /
  `chan_raw_arm` / `chan_raw_disarm` / `select_waiter_*` helpers — the
  element type drops out of the orchestration, so one non-generic code
  path serves channels of any type. Test
  `compiler/tests/select_basic.nu` (deterministic default / value /
  closed / priority cases always-on; concurrent blocking path gated on
  `NURL_NET_TESTS=1`). Bootstrap fixed point holds (stage1 ≡ stage2
  byte-identical at 1 691 603 B).
- **Stdlib numeric + text utility round-out** — four pure-NURL
  additions (no compiler changes, each with an offline test):
  - `stdlib/std/int.nu`: `int_gcd`, `int_lcm`, `int_isqrt` (Newton-method
    exact floor sqrt). Test `compiler/tests/int_extra.nu`.
  - `stdlib/std/float.nu`: `float_trunc`, `float_cbrt`, `float_hypot`,
    `float_log2`, `float_log10` (direct libm FFI) + pure-NURL
    `float_sign`. Test `compiler/tests/float_extra.nu`.
  - `stdlib/core/string.nu`: `string_join` (complement of `string_split`)
    and `string_count` (non-overlapping occurrence count). Test
    `compiler/tests/string_join_count.nu`.
  - `stdlib/core/char.nu`: `is_upper`, `is_lower`, `is_hexdigit`,
    `to_upper_ascii`, `to_lower_ascii`, `hex_val`. Predicates use the
    same `# i <bool-expr>` shape as the existing `is_alpha` / `is_digit`
    family — now returning a canonical 1/0 thanks to the cast fix below.
    Test `compiler/tests/char_extra.nu`.

### Fixed

- **Pointer-vs-integer comparison emitted invalid IR.** `gen_binary`
  produced `icmp eq i8* %p, 0`; comparison operators now `ptrtoint` any
  pointer operand to `i64` and compare in `i64`, so `== raw 0`
  null-checks compile. Found bringing `postgres.nu` to production grade.
- **`^ <void-call>` (returning a `→ v` call) emitted a value return.**
  Returning the result of a void function now lowers to `ret void`
  instead of attempting to return a non-existent value. Found in the
  postgres work.
- **A bare numeric/string literal as a statement is now a hard compile
  error.** Previously `& m 255 0x40` (single `&`) silently discarded the
  trailing `0x40` — a bare-literal discard statement the compiler
  accepted — which masked a real masking bug in the Game Boy PPU's
  STAT-bit-6 handling. `gen_block_stmts` / `gen_block_ret` now reject a
  bare literal whose value is unused. (The no-workarounds dividend from
  debugging dmg-acid2.)
- **`# i <bool>` now zero-extends (was -1 for true).** Casting a boolean
  (an `i1` from a comparison / `&` / `|` / `!`) to a wider integer
  emitted `sext i1`, so `# i true` was -1 instead of 1. Harmless for the
  ubiquitous `!= 0` callers, but it silently broke every predicate
  documented as "→ 1": `is_alpha` / `is_digit` / `is_space` /
  `is_alnum_us` all returned -1 for true. NURL has no signed 1-bit type,
  so a boolean true is canonically 1 — `gen_cast` now forces `zext` for
  any `i1` source (comparisons never set the `__last_unsigned__`
  side-channel that the unsigned-widen path relies on, hence the explicit
  guard). Latent fix across the whole stdlib; no existing test output
  changed (nothing depended on the -1). Regression
  `compiler/tests/cast_bool_int.nu`. Bootstrap fixed point holds
  (stage1 ≡ stage2 byte-identical at 1 660 838 B).
- **`HttpOptions` struct (HTTP client)** — `stdlib/ext/http.nu` gained
  `HttpOptions { i timeout_ms, i connect_timeout_ms, i follow_redirects,
  i max_redirects, i verify_tls, s user_agent }` bundling the per-request
  transport overrides that were previously hardcoded in the libcurl
  orchestrator. New entry points: `http_options_default → HttpOptions`,
  `http_request_with_opts`, and `http_get_opts` / `http_post_opts`
  conveniences. The orchestrator body moved into
  `__libcurl_perform_full_opts` (wires `CURLOPT_FOLLOWLOCATION` /
  `MAXREDIRS` / `SSL_VERIFYPEER` / `SSL_VERIFYHOST` / `USERAGENT` from the
  struct); the legacy timeout-only `__libcurl_perform_full_to` is now a
  thin shim over it, so `http_request` / `http_request_to` are
  behaviour-preserving. `user_agent` is borrowed `s` so HttpOptions owns
  nothing (no free fn, safe by-value). WinHTTP / stub backends honour
  only the two timeouts (redirect / TLS / UA ignored — documented).
  Stdlib-only; compiler IR unperturbed. Tests: offline
  `compiler/tests/http_options.nu` (always-on) + a live `GET_OPTS` case
  in `compiler/tests/http_basic.nu`.
- **`examples/h2c_server.nu`** — minimal cleartext-HTTP/2 ("h2c,
  prior-knowledge") echo server (~135 LOC). Async accept loop via
  `stdlib/std/async.nu` so h2spec's probe + test connections can be
  served concurrently; per-conn read timeout of 1 s keeps the
  sequential accept queue draining when a test deliberately leaves
  a connection half-open; response body sized ≥ 5 bytes so the
  `dataLen >= 5` gate in h2spec §6.9.2/2 runs the test instead of
  skipping. Verified green under both `./nurl.sh` and
  `NURL_SAN=1 ./nurl.sh`.
- **`examples/ws_echo.nu`** — minimal WebSocket echo server (~110
  LOC). Uses the stdlib `ws_perform_handshake` + `ws_serve_messages`
  pair against the same TCP accept loop. Per-server `WsLimits`
  raises `fragment_max_count` to 131 072 so autobahn §9.x's 4-MiB
  message split into 65 536 frames assembles successfully; per-
  frame and per-message byte caps stay at the stdlib defaults.
- **`NURL_SAN=1` support in `nurl.sh`** — drops `-flto`, adds
  `-fsanitize=address,undefined -fsanitize-address-use-after-scope
   -fno-omit-frame-pointer -fno-sanitize-recover=all` at the link,
  and builds a side-by-side `stdlib/runtime_san.o` (non-LTO,
  matching flags) if `stdlib/runtime.c` is newer than the cached
  artefact. Matches the toolchain `./build.sh --san` already uses
  for its own corpus.
- **HPACK lowercase-header-name encoder** (`stdlib/ext/http2_hpack.nu`
  `__hpack_lower_name_dup`) — RFC 9113 §8.2.2 mandates lowercase
  header field names on the wire; `hpack_encode_headers` now
  lowercases every name before encoding. Previously curl's HTTP/2
  parser rejected our `Content-Type` response header.
- **Inline WINDOW_UPDATE pump in `__h2_send_response`** — when the
  stream OR connection send-window is exhausted mid-response, the
  writer reads frames off the peer and applies WINDOW_UPDATE /
  SETTINGS / PRIORITY semantics in place (RFC 9113 §5.2.1, §6.9.1).
  HEADERS for a new stream during the pump is refused with
  RST_STREAM(REFUSED_STREAM) per §5.1.2. Empty `DATA(END_STREAM)`
  fallback (§6.9.1 permits zero-length DATA + END_STREAM regardless
  of window state) closes the stream cleanly when the pump bails.
- **HTTP/2 request HEADERS validation pass** (`__h2_validate_request_
  headers` in `stdlib/ext/http2_conn.nu`) — RFC 9113 §8.3 / §8.2.1 /
  §8.2.2: lowercase names, pseudo-headers precede regular ones,
  exactly one `:method` / `:scheme` / `:path` (non-empty), no
  duplicate or response-only or unknown pseudo-headers, no
  connection-specific headers (`Connection`, `Proxy-Connection`,
  `Keep-Alive`, `Transfer-Encoding`), and `TE` — if present — holds
  exactly `"trailers"`. Runs immediately after HPACK decode succeeds
  on both the HEADERS+END_HEADERS and HEADERS+CONTINUATION+
  END_HEADERS paths.
- **HTTP/2 frame-validation pass** — SETTINGS / GOAWAY / RST_STREAM
  / PRIORITY / DATA stream-ID + length + ACK rules per §6.5 / §6.4
  / §6.3 / §6.1 / §6.8.
- **HEADERS-on-existing-open-stream = trailers** (§8.1) — accepting
  a HEADERS frame on a stream already in `open` / `half-closed-
  local` state as the trailers section. Trailers MUST carry
  END_STREAM; decoded fields are discarded but `end_stream_received`
  is marked and the handler is dispatched.
- **PUSH_PROMISE rejection** (§6.6) — client→server PUSH_PROMISE is
  now PROTOCOL_ERROR (we advertise SETTINGS_ENABLE_PUSH=0).
- **§5.3.1 self-dependency check** for PRIORITY and HEADERS-with-
  PRIORITY-flag — a stream MUST NOT depend on itself; rejected as
  PROTOCOL_ERROR.
- **§6.9.1 flow-control overflow detection** — WINDOW_UPDATE that
  carries a stream's or connection's send-window above 2^31-1 is
  now FLOW_CONTROL_ERROR (stream-level → RST_STREAM, conn-level →
  GOAWAY).
- **§5.1 idle-stream WINDOW_UPDATE** — WINDOW_UPDATE on a stream
  with sid > last_peer_stream_id (never opened) is PROTOCOL_ERROR;
  on a closed stream silently no-ops.
- **HPACK §4.2 dynamic-table-size-update placement check** — size
  updates after any indexed/literal field in the block are
  COMPRESSION_ERROR (new `seen_field` flag in `hpack_decode_block`),
  and the new size is bounded by `h2_default_header_table_size`
  (4 096) — our advertised SETTINGS_HEADER_TABLE_SIZE — rather than
  the table's current `max_size`, which may have been lowered by a
  previous update in the same connection.
- **§8.1.1 content-length consistency check** (`__h2_content_length
  _mismatch`) — when a request carries `content-length`, the sum of
  DATA-payload lengths MUST equal that value. Mismatched (or
  unparseable, or duplicated and disagreeing) content-length becomes
  PROTOCOL_ERROR before handler dispatch.
- **RFC 6455 §5.5.1 / §7.4.2 WebSocket close-frame validation** —
  payload length 1 → `WsInvalidCloseCode` (close code 1002, not
  1000); status code outside 1000–2999 OR 1004 / 1005 / 1006 /
  1015 / 1016+ → close 1002; close-reason bytes validated as UTF-8.
  Previously a close frame's payload was discarded outright and the
  server replied with `WsClosedByPeer` → 1000 regardless of what the
  peer sent.
- **TCP_NODELAY on accepted sockets** (`stdlib/runtime.c`,
  `nurl_tcp_accept`) — disables Nagle's algorithm on every accepted
  TCP connection. Small framing-level ACKs (SETTINGS-ACK, PING-ACK,
  WINDOW_UPDATE) were otherwise pinned behind the previous write
  for up to 40 ms, which is exactly the window h2spec's per-test
  short timeouts can't tolerate.
- **`h2_default_header_table_size` constant** in
  `stdlib/ext/http2_frame.nu` — value `4 096`, used as the upper
  bound for HPACK dynamic-table-size updates and matches the
  RFC 9113 §6.5.2 default for SETTINGS_HEADER_TABLE_SIZE.

### Changed

- **`scan_fn_sigs` is now brace-depth-tracked** — only TT_AT / TT_AMP
  / TT_DOLLAR / TT_PERCENT openers at depth 0 trigger their
  respective dispatch branches; everything inside `{ ... }` advances
  silently. Matches the pattern `scan_type_names` already used (see
  the docstring there). Closes the family of param-walk-desync bugs.
- **HTTP/2 GOAWAY-receive no longer triggers immediate shutdown** —
  per RFC 9113 §6.8 the receiver of GOAWAY MUST keep processing in-
  flight frames (PING, RST_STREAM, in-progress streams) until the
  peer closes the socket; only NEW stream creation is forbidden.
  Previously we hard-exited the serve loop on the first GOAWAY,
  which broke the h2spec GOAWAY-then-PING sequence.
- **HTTP/2 invalid-preface error path** sends GOAWAY only when the
  preface was structurally invalid (`H2FrameBadPreface`); on a read
  error (timeout / EOF / IO) we tear down silently. GOAWAY-on-
  every-preface-error was being seen by h2spec's per-test probe
  connections and counted as the test response.

### Fixed

- **`scan_fn_sigs` brace-depth desync** — the `@` inside a closure-
  shaped struct field type (`( @ HttpResponse HttpRequest ) handler`)
  was treated as the start of a function declaration; the param
  walker then read `HttpResponse` as the phantom `fname` and the
  NEXT type-name-shaped token (in `stdlib/ext/http_server.nu`,
  `DosLimits`, declared 5 lines later) as that phantom function's
  `ret_ty`, silently writing `syms["HttpResponse"] = "%DosLimits"`.
  `gen_match`'s wide-payload reconstruction for a
  `: ! HttpResponse WsErr rr (...)` binding then looked up
  `syms["HttpResponse"]` to size the heap-box load and emitted
  `inttoptr i64 ... to %DosLimits*` + `load %DosLimits` + `bitcast
   %DosLimits* ... to i8*` against the real HttpResponse pointer.
  Under -O1+ this manifested as a runtime nurl_peek of a misaligned
  sub-page address (the HttpResponse i64 status field read as a Vec
  ctl). Under -O0 the extra reload of the alloca round-tripped the
  bits exactly so the struct's field accesses happened to land at
  the right offsets, hiding the bug.
- **`__h2_stream_to_request` double-freed `req.query`** when the
  request had no `?` in the path — the field was freed
  unconditionally but only reassigned inside the `qi >= 0` branch.
  `request_free` then freed the dangling pointer again. Clear ASan
  use-after-free on the very first h2c request through h2spec.
- **`__h2_decode_stream_headers` freed the old `cur.dec_dyn` before
  assigning the new `dd.dyn`** — but `HpackDynTable.entries` is
  aliased through the by-value pass into `hpack_decode_block`, so
  the two wrappers shared one Vec ctl. The free turned the new
  assignment into a dangling pointer; subsequent reads on
  connection close tripped nurl_peek.
- **`hpack_decode_block` failure path freed `cur`** — but `cur` was
  initialised from the input `dyn` (struct copy, entries Vec
  pointer-aliased), so freeing in the error path left the caller's
  `dec_dyn` pointing at a freed Vec entries pointer. The next
  h2_conn_free vec_free_with double-freed.
- **`__h2_frame_err_to_conn` returned bare enum tags from `??`-arm
  bodies** when the function return type wrapped them as a struct;
  follow the established `__net_err_of` convention with explicit
  `# H2ConnErr Tag` casts so the IR's `ret %H2ConnErr` matches the
  function signature.
- **`nurl_str_slice_unsafe` did pointer-load instead of pointer
  arithmetic** — `. rp from` lowers to "load the byte at rp+from",
  not "compute address rp+from". The code intended an unsafe
  substring view (rp + from interpreted as a string pointer); now
  spelled `# s + # i raw from` (cast-add-cast).
- **Two latent parenthesised-operator compile errors** in
  `stdlib/ext/http2_conn.nu` — `( % n 6 )` and `( . rp from )`. The
  diagnostic that rejects these landed 2026-05-22 but
  `http2_conn.nu` was never on the build/test path, so they sat
  silently until `examples/h2c_server.nu` pulled the file in.
- **`__pow2` defined in two translation units** — once in
  `stdlib/ext/http_response.nu` (used for hex-format expansion) and
  once in `stdlib/ext/http2_hpack.nu` (used for HPACK integer
  width). Linker rejected the redefinition the first time both
  modules were used together; the HPACK helper is now
  `__hpack_pow2`.
- **`__h2_apply_settings` sign-extension** — byte-shift-and-OR
  assembly of the 24-bit length / 32-bit value fields used `# i u`
  to widen each payload byte without masking, so any byte ≥ 0x80
  propagated as a negative i64 into the next shift, corrupting
  `value`. Fixed with explicit `& 255` masks at every byte read; the
  same fix applied to the WINDOW_UPDATE increment decode in the
  main serve loop and in `__h2_pump_one_frame`.
- **`autobahn-testsuite §6.4.1-4` UTF-8 fail-fast** — accepted as
  NON-STRICT (the spec permits either streaming UTF-8 rejection or
  whole-message validation; we do the latter). Documented for
  follow-up work.

### Tooling / dev experience

- **`./build.sh --san` ASan/UBSan corpus runs WebSocket close
  validation** end-to-end through autobahn-testsuite's first seven
  case sections (92/92 OK; 0 sanitizer findings).
- **`docs/GOTCHAS.md` remains empty** — every gotcha surfaced
  during the interop push (parenthesised-operator calls, sign-
  extension, `__pow2` collision, enum-tag-cast-on-return) is
  diagnosed by the compiler at compile time.
- **`.github/workflows/bench.yml`** — reproducible CI bench runner.
  Triggers on push-to-main (paths-filtered to bench/, compiler/,
  stdlib/, bench.yml itself), `workflow_dispatch`, and a weekly
  Monday 06:00 UTC cron. Installs clang + rustup stable + the FFI
  libs the regular `ci.yml` uses, bootstraps nurlc, runs
  `bench/run.sh 5` on a fixed `ubuntu-latest` 2-vCPU runner, and
  uploads the results as a workflow artifact. Manual / scheduled
  runs additionally commit a refreshed `bench/RESULTS_CI.md` back
  to main. The README's headline numbers (captured on a 12-core Intel
  @ 3.5 GHz) stay in `RESULTS.md` as the hand-captured figures;
  `RESULTS_CI.md` is the reproducible baseline.

### Tokeniser-aware token-efficiency baseline

- **`bench/token_efficiency.py` + `bench/TOKEN_EFFICIENCY.md`** —
  BPE-aware token counts using `tiktoken`'s `cl100k_base`
  (GPT-3.5 / GPT-4 / Claude legacy), `o200k_base` (GPT-4o /
  o-series), and `gpt2` (proxy for Llama-3, which is HF-gated)
  against every cross-language benchmark in `bench/`. NURL/Python
  BPE-aware token-count ratios on these three benchmarks are
  0.82–0.95× (LCG, all encoders) / 1.88–2.06× (sieve) /
  1.60–1.77× (json_parse).
- **`bench/{lcg,sieve,json_parse}.nu` cleanup** — dropped the
  redundant `$ "stdlib/core/io.nu"` import (the `puts` and
  `nurl_str_int` calls resolve through the compiler's libc/runtime
  prelude) and switched the trailing print from
  `( puts ( nurl_str_int x ) )` to the one-call
  `( nurl_print_int x )`. `sieve.nu` also drops the redundant FFI
  decls for `malloc` and `free` (both pre-registered by
  `init_syms`). Net result: −29 to −80 source bytes per file, NURL
  token counts down ~6–10 % across every encoder, and `@main` LLVM
  IR is byte-identical for both compute benchmarks.

### Borrow checker

- **`--strict-borrowck` (off by default)** — opt-in mode that
  extends two existing on-by-default checks:
    - **Aliased mutation through `. obj field` arguments.** The
      default N-readers-XOR-1-writer check fires only when both
      aliasing arguments at a call site are bare identifiers.
      Strict mode also recognises `. obj field` as an access of the
      root binding `obj`, so `( swap c . c n )` is now flagged when
      one of the arguments is `inout`. The iterator-invalidation
      check is widened in the same shape.
    - **`# *T <owned-binding>` raw-pointer escape.** When a `*T`
      cast's source binding sits on any of the auto-drop
      side-tables (`__owned_strings__` / `__owned_slices__` /
      `__owned_struct_fields__`) OR is a non-parameter heap binding
      (%Struct / enum / aggregate, mirroring the move-tracker's
      `bck_let_alias` heuristic), strict mode flags the cast: the
      binding's auto-drop at scope exit invalidates the pointer.
- Regression tests `compiler/tests/borrow_strict_field_alias.nu`
  and `compiler/tests/borrow_strict_raw_ptr_escape.nu` — both
  compile cleanly under the default checker and error out under
  `--strict-borrowck`. `compiler/tests/run_tests.sh` recognises any
  `borrow_strict_*` filename and adds the flag automatically.
- Bootstrap fixed point unchanged: strict mode is purely a
  diagnostic-only analysis pass.



## [0.9.2] — 2026-05-28

### Summary

`play.nurl-lang.org` no longer runs Python at runtime. `nurlapi/` is
a 3 000+-LOC NURL HTTP server with a full Model Context Protocol
server over `/mcp` (15 tools, 7 resources, 1 prompt), serving five
cross-compile build targets (native ELF, wasm32-wasi, mingw-w64
PE32+, macOS Intel, macOS Apple Silicon + the rest of the
`/build_target` registry). One static NURL binary is PID 1 inside
the runtime image.

A `nurl_poke` / `nurl_peek` byte-vs-slot index overrun in
`server_run_pool` (and three other call sites) that scribbled 7×N
bytes past a worker-handles buffer is fixed. The overrun had
manifested as random route / closure corruption under thread load.

Full test corpus + sanitiser corpus (ASan + UBSan + LSan, 281 tests)
green. Bootstrap fixed point at 1 620 300 B (stage1 ≡ stage2
byte-identical IR).

### Added — pure-NURL playground server (`nurlapi/`)

Replaces the Python FastAPI playground end-to-end. One static NURL
binary as PID 1; the runtime image is a slim Debian-bookworm stage
that only needs clang-16 + the cross-compile toolchains baked in.

**Route surface** (POST unless noted):

- `/build` → native Linux x86_64 ELF
- `/build_wasm` → wasm32-wasi (uses `prepare_ir_for_wasi` IR shim;
  wasm32 ABI rename + libc shims for `malloc` / `puts` / `write` etc.)
- `/build_windows` → mingw-w64 PE32+ via two-stage `clang -c` then
  `x86_64-w64-mingw32-gcc` link (static libcurl chain when the
  `runtime.win.curl` marker is present)
- `/build_macos` → Mach-O via zig cc
- `/build_target` → multi-target dispatch (linux-x64-musl,
  linux-arm64-musl/-gnu, linux-riscv64-musl, macos-x64, macos-arm64,
  windows-x64) over a single shared `_build_zig_cross` helper
- `GET /examples`, `GET /examples/*name` — bundled example listing +
  individual source
- `GET /stdlib`, `GET /stdlib/*path` — recursive .nu listing (84
  entries) + per-file `{name, source, bytes}` JSON
- `GET /tests`, `GET /tests/*path` — same shape for the compiler
  test corpus (281 entries)
- `GET /targets` — target registry (the dropdown the UI builds from)
- `GET /readme` / `/readme.md`, `/roadmap` / `/roadmap.md`,
  `/gotchas` / `/gotchas.md`, `/grammar.ebnf` — doc passthroughs +
  HTML-rendered alternates (pure-NURL Markdown→HTML renderer:
  headings, fenced code, bold/em, code spans, links, autolinks,
  images, ul/ol, blockquote, hr; tables + nested lists deferred)
- `GET /LICENSE-MIT`, `/LICENSE-APACHE`, `/NOTICE`, `/license`,
  `/license/{mit,apache}` — license endpoints (raw + HTML-wrapped)
- `GET /openapi.json` — minimal but valid OpenAPI 3.1 doc enumerating
  every public route
- `GET /health` → toolchain status (60+ stdlib modules + per-tool
  liveness)
- `GET /mcp-info` → MCP server probe (tools / resources / prompts
  catalogue + a `client_config_example` built from the request's
  Host header or `NURL_PUBLIC_URL`)
- `GET /download/:id/:file` → built artifact download
- OAuth 2.0 / OIDC rubber-stamp stubs so Claude-Desktop-class MCP
  clients that probe `.well-known/*` succeed: `oauth-protected-
  resource` (+`/mcp`), `oauth-authorization-server`, `openid-
  configuration`, `POST /register`, `GET /authorize` (instant 302),
  `POST /token`
- Static UI at `/`, `/favicon.{ico,svg}`, `/static/*`, `/*path`

**Build response shape** mirrors `api/` (Python) exactly: combined
`stdout` / `stderr`, parsed `nurlc_errors[]` (`{file, line, col,
message}`), `ll_artifact` + `binary_artifact` with `{name, bytes,
download_url, token}`, `nurlc_returncode` / `clang_returncode`,
`uses_canvas` / `uses_audio`. New shared helpers:
`parse_nurlc_diagnostics`, `combine_stderr`, `make_artifact_json`,
`stamp_build_response`, `nurlc_failure_response`,
`push_native_runtime_libs`.

`nurlapi/Dockerfile` — two-stage Debian bookworm image. Stage 1
bootstraps nurlc, downloads WASI SDK 24 + Zig 0.13, builds a static
libcurl-mingw for the Windows target, pre-builds the six zig-target
runtime objects + warms the zig per-target libc cache so the first
`/build_target` per target is a fast cache hit rather than a cold
multi-second libc compile, compiles the nurlapi binary itself.
Stage 2 is a slim runtime image (clang-16 + cross-compile toolchains
only, no Python).

`nurlapi.sh` — bring-up wrapper. `./nurlapi.sh` builds + runs on
port 8000; `./nurlapi.sh bind` skips the Docker rebuild and bind-
mounts the freshly-built local binary + stdlib + examples + tests
+ root docs into the running container (inner dev loop: edit `.nu`
→ `./nurlapi.sh bind` → hit endpoint, ~30 s vs ~10 min). Flags:
`--no-cache` / `--port=N` / `--rm` / `--detach` / `--build-only` /
`--name=NAME` / `--help`.

`nurlapi/e2e_test.{py,sh}` — end-to-end test driver covering every
endpoint.

### Added — full MCP server over `/mcp`

`stdlib/ext/mcp_http.nu` + `nurlapi/main.nu`. Streamable HTTP
transport (POST /mcp), FastMCP handshake parity:

- `initialize` (protocolVersion `2025-03-26`, FastMCP capabilities
  shape, `instructions` blurb verbatim, serverInfo `nurl-playground
  0.9.2`)
- `ping`, `tools/list` (15 tools), `tools/call` (dispatch by name)
- `resources/list` (7 `nurl://` URIs), `resources/read`
- `prompts/list` (1 prompt: `nurl_coding_assistant`), `prompts/get`
- `notifications/*` (no reply, 202 Accepted)
- JSON-RPC 2.0 batches (top-level array → array reply,
  notifications dropped per spec)

**Tools (full Python parity):**

- Build (5) — `nurl_build_native`, `nurl_build_wasm`,
  `nurl_build_windows`, `nurl_build_macos`, `nurl_build_target`
  (enum-typed target id)
- Browse (3) — `nurl_list_examples`, `nurl_list_stdlib`,
  `nurl_list_tests`
- Read (7) — `nurl_read_example`, `nurl_read_stdlib`,
  `nurl_read_test`, `nurl_read_grammar`, `nurl_read_readme`,
  `nurl_read_roadmap`, `nurl_read_gotchas`

Build tools dispatch via loopback HTTP to the server's own `/build`
endpoints (`NURL_MCP_LOOPBACK_URL`, default `http://127.0.0.1:8000`):
zero duplication of the canonical handler logic.

**Reliability fixes vs Python reference:**

1. **Session persistence across container restarts.** Python
   validated `Mcp-Session-Id` against a per-process in-memory
   whitelist — fresh pod = fresh whitelist = previously-issued sids
   rejected. NURL approach: session ID is opaque to the server.
   First request (no sid) → server generates 16-hex-char sid, echoed
   in `Mcp-Session-Id` response header; subsequent requests with sid
   → echoed verbatim, no validation. Pod restart → client sid still
   accepted, no reconnect required.
2. **Burst handling.** Python's asyncio event loop serialised
   request handling. NURL piggybacks on `server_run_pool`'s
   16-pthread worker pool — every POST /mcp gets its own worker
   thread, no serialisation. Measured: 50 concurrent `tools/list`
   in 65 ms wall on a single host (~770 req/s peak).

**Streamable HTTP content-negotiation** in `stdlib/ext/mcp_http.nu`:
when the client sends `Accept: text/event-stream` (every official
SDK does), the JSON-RPC reply is wrapped as `event: message\r\ndata:
<json>\r\n\r\n` with `Content-Type: text/event-stream` +
`Cache-Control: no-cache`. Legacy clients without the Accept header
still get plain `application/json`.

### Added — `http_router` HEAD + OPTIONS

`router_handle` now answers HEAD and OPTIONS requests without each
handler having to know about them — same shape FastAPI / Express /
most modern HTTP frameworks ship by default.

- **HEAD** (RFC 7231 §4.3.2): treated as a GET for the purpose of
  route matching — falls through to the GET handler, then pins
  `Content-Length` to the GET body's would-have-been length and
  clears the body Vec so the wire-level serialisation emits headers
  + blank line + zero bytes.
- **OPTIONS** (RFC 7231 §4.3.7): the router answers directly, no
  handler involved. Walks every registered route, collects distinct
  methods whose pattern matches the request path, auto-adds HEAD
  (when GET is among them) and OPTIONS (always), returns 204 No
  Content with the assembled `Allow:` header. Root-level catch-alls
  (patterns starting with `/*`) are excluded from OPTIONS
  enumeration so they don't pollute the advertised method list.

Two new helpers: `__strip_body_for_head`, `__router_options`.

Verified live against nurlapi: `OPTIONS /health` → 204 `GET, HEAD,
OPTIONS`; `OPTIONS /build` → 204 `POST, OPTIONS`; `OPTIONS
/nonexistent` → 404 (catch-all filter working); `HEAD /health` →
200 `Content-Length: 1570`, body 0 bytes.

### Fixed — `nurl_poke` / `nurl_peek` byte-vs-slot heap overrun (critical)

`server_run_pool` in `stdlib/ext/http_server.nu` allocated an N×8-byte
buffer for N worker thread handles and then wrote into it with
`nurl_poke thandles (* j 8) traw` — passing a **byte offset** where
`nurl_poke` expects a **slot index**. `nurl_poke` scales by 8
internally, so each "write at byte offset j*8" actually landed at
byte offset j*64 — scribbling 7×N bytes past the buffer end.

The overrun survived for years because it consistently hit the
malloc arena's slack-padding zone, which on glibc was unallocated
"redzone-shaped" space between the worker-handles block and the
next live allocation. The behaviour only collapsed once enough other
heap traffic crowded the arena and a real load-bearing allocation
landed in the spillover window — at which point one of the routes,
or its `RouteImpl` pointer, or its closure environment, would get
clobbered and the next request through that route would crash.

This was previously misdiagnosed as a `Vec[Route]` multi-field-struct
stride hazard under pthread + clang -O2 (the boxed-handle pattern in
`stdlib/ext/http_router.nu` was added as a workaround for the
symptom). Route storage was always sound; routes just happened to
share the arena page that got smashed. The `http_router.nu` comment
block has been rewritten to credit the real cause.

ASan caught the real root cause when `nurlapi/main.nu` grew from 14
to 22 routes — the bigger router-build allocation budget shifted
what landed in the spillover. Same anti-pattern was present in three
other call sites, fixed atomically:

- `stdlib/ext/http_server.nu` `server_run_pool` (3 sites: 2 poke + 1 peek)
- `stdlib/ext/postgres.nu` `pg_exec_params` (2 sites)
- `compiler/tests/thread_basic.nu` (2 sites — masked by malloc slack)

Each: `(nurl_poke buf (* j 8) v)` → `(nurl_poke buf j v)`.

Regression test `compiler/tests/nurl_poke_slot_index.nu` allocates
an N×8 buffer (N=32, well past any malloc-slack forgiveness zone),
writes N distinct markers, reads them back, verifies bit-for-bit.
Under ASan in `run_san_tests.sh` it fails-fast as
`heap-buffer-overflow` on the first overrun if anyone reintroduces
the byte-as-slot mistake.

### Fixed — playground init no longer blocks on a CDN

`<script type="module">` in `api/static/index.html` and
`nurlapi/static/index.html` started with a top-level
`import { … } from "https://esm.sh/@bjorn3/browser_wasi_shim@0.3.0"`.
ES-module top-level imports are awaited before any statement in the
module body runs — if esm.sh is slow, blocked, or rejected by the
browser (ad-blocker, CSP, offline cache, transient DNS), the module
never reached its first statement, so `refreshHealth()`,
`loadExamples()` and `loadTargets()` never fired. The health pill
stayed "checking…", dropdowns stayed empty, and the page looked
like the server's `/health` was down even though the server was fine.

Fix: replace the static import with a lazy `import(WASI_SHIM_URL)`
inside a `loadWasiShim()` helper, called only from inside `run()` —
the one place that actually needs the shim. The module body now has
zero top-level awaitable imports and initialises synchronously. A
CDN failure surfaces in `run()`'s `logLine` path and aborts only
that one Run-click, not the whole page.

### Changed — `/build_windows` two-step compile (clang) + link (mingw-gcc)

Mirrors Python `api/`'s approach: `clang --target=x86_64-w64-mingw32`
is great at parsing IR but its mingw linker driver can't resolve
mingw-w64's installed support libraries (`-lgcc`, `-lwinpthread`,
`crtbeginS.o`, etc.). Single-step `clang ... runtime.win.o -o
out.exe` therefore fails with `/usr/bin/x86_64-w64-mingw32-ld:
cannot find -lgcc`. Two steps fix it:

1. `clang --target=x86_64-w64-mingw32 -c file.ll -o file.o` — clang
   compiles IR to a mingw-flavoured object.
2. `x86_64-w64-mingw32-gcc file.o runtime.win.o -lpthread …
   [optional libcurl] -o file.exe` — mingw's own gcc owns its
   libgcc / libwinpthread / CRT search paths and finishes the link
   cleanly.

The optional libcurl chain (`-L<curl-mingw>/lib -lcurl -lws2_32
-lcrypt32 -lbcrypt -lncrypt -lsecur32 -ladvapi32`) is added only
when the `stdlib/runtime.win.curl` marker is present — same gate
Python uses. Combined stderr now layers all three stages
(`nurlc` → `clang -c` → mingw-gcc link) so the playground's "BUILD
FAILED" panel surfaces whichever stage actually errored;
`final_rc` prefers the compile return code over the link return
code (a failing compile produces the more actionable diagnostic).

Five compile targets now produce real binaries end-to-end:

- `/build` → 78 KB Linux ELF
- `/build_wasm` → 232 KB wasm32-wasi
- `/build_windows` → 1.18 MB PE32+ EXE
- `/build_macos` → 19 KB Mach-O (Intel)
- `/build_target macos-arm64` → 52 KB Mach-O (Apple Silicon)

### Changed — small fixes & perf polish

- `stdlib/std/bytes.nu` — speed-up to the byte-walk helpers used on
  parser hot paths (direct `*u` pointer reads where the bounds check
  is already proven by the loop invariant).
- `stdlib/ext/http_response.nu` — minor allocation-count reduction
  on the response-build path.
- `bench/http_server.nu`, `bench/run.sh`, `bench/run_http.sh` —
  small harness tweaks for the local bench host.
- `README.md` — updated headline benchmark numbers;
  `nurlapi/README.md` added (96-line operator manual for the
  pure-NURL playground + inner-loop dev workflow).
- `examples/{enigma,fizzbuzz,msgpack_demo,wordcount}.nu` — minor
  polish picked up while testing playground rendering.
- `nurlapi/static/viewer.html` — new stdlib / tests source viewer
  (linked from the playground UI).
- `cloudflare/Dockerfile`, `dockerpush.sh`, `startdev.sh` — incidental
  updates so the prod image build & local dev port (8001 vs api/'s
  8000) coexist cleanly.

## [0.9.1] — 2026-05-26

### Summary

- Borrow checker promoted to hard errors by default. Five bug
  classes are compile errors: use-after-move, alias double-free,
  closure escape, aliased mutable-borrow at call sites, iterator
  invalidation. `--no-borrowck` is the escape hatch.
- UDP datagrams (dual-stack IPv4/IPv6 with multicast) + standalone
  DNS resolver (`getaddrinfo` / `getnameinfo`).
- JSON parser ~34× faster — pure-NURL `stdlib/ext/json.nu` rewritten
  around a single-pass scanner; 479 ms → 14 ms on the
  `bench/json_parse` micro-benchmark.
- Peer benchmarks in `bench/` compare NURL with Python / Rust / Node
  on three reproducible micro-benches plus an HTTP-server-vs-Rust-
  hyper / Node-http sweep.
- GitHub Actions workflow with parallel build-test + sanitizer
  (ASan + UBSan) jobs.
- `docs/spec.md` (~1 000 lines) covers the semantic side the grammar
  EBNF does not.
- Generic signal handling, structured logging, silent-miscompile
  diagnostics.

Bootstrap fixed point: stage1 ≡ stage2 byte-identical IR at
1 620 300 B. Full test corpus + sanitizers green.

### Added — UDP datagram sockets + full DNS resolver

Three new public surfaces:

1. **`stdlib/std/udp.nu`** — pure-NURL wrapper over runtime §18b. Dual-
   stack IPv4/IPv6 by default (wildcard `udp_bind("", 0)` creates an
   `AF_INET6` socket with `IPV6_V6ONLY=0` so a single fd serves both
   v4 and v6 peers; literal `udp_bind("127.0.0.1", 0)` stays IPv4-only
   on purpose). Sync + fiber-aware async on every send/recv: inside a
   fiber, `udp_recv_from` / `udp_send_to` park on the reactor on
   EAGAIN; outside any fiber, they fall back to blocking I/O
   transparently. Exposed surface:
   - lifecycle: `udp_bind`, `udp_bind_any`, `udp_connect`, `udp_close`
   - send/recv: `udp_send_to`, `udp_send_str_to`, `udp_recv_from`,
     `udp_send`, `udp_recv` (last two for connected-mode UDP)
   - address: `udp_peer_addr` (borrowed), `udp_local_addr` (owned
     String — how the caller discovers the kernel-assigned ephemeral
     port after `udp_bind("", 0)`)
   - options: `udp_set_timeout`, `udp_set_nonblock`, `udp_set_broadcast`
   - multicast: `udp_join_group`, `udp_leave_group`,
     `udp_set_multicast_ttl`, `udp_set_multicast_loop`. `iface` arg is
     intentionally minimal (IPv4 IP literal or numeric ifindex; no
     `if_nametoindex` so Win32 doesn't need `-liphlpapi`).

2. **`stdlib/std/dns.nu`** — pure-NURL wrapper over runtime §18c.
   System-resolver-based (`getaddrinfo` / `getnameinfo`), no c-ares
   dep. Three entry points:
   - `dns_resolve host` → `! ( Vec String ) NetErr` of A/AAAA literals
     in the kernel's preferred order, dedup'd.
   - `dns_resolve_port host port` → same, but each entry is formatted
     as `"ip:port"` (IPv4) or `"[ip]:port"` (IPv6, RFC 3986 §3.2.2)
     ready for direct `tcp_connect` / `udp_connect`.
   - `dns_reverse ip` → `? String` (Some only when there's a real PTR
     record — `NI_NAMEREQD`).

3. **Runtime §18b / §18c (`stdlib/runtime.c`)** — implementation:
   - `NurlUdp { fd, err_kind, family, peer }` opaque handle (~16 % the
     size of `NurlTcp` — UDP has no TLS state to track).
   - 22 new `nurl_udp_*` and 3 new `nurl_dns_*` exports; WASI stub
     row at the bottom degrades every call to `NetOther` /
     `strdup("")` so `wasm32-wasi` builds still link.
   - Reuses §18's `NURL_NET_ERR_*` error space + `nurl__net_map_errno
     / _wsa` mapping helpers; multicast group-family branching uses a
     new `nurl__parse_numeric_addr` (`AI_NUMERICHOST`) so callers
     don't have to thread family flags through the NURL API.
   - DNS results come back as newline-separated heap strings; NURL
     splits and dedupes are deferred to the wrapper (`__dns_split_lines`).

Acceptance:

- `compiler/tests/udp_basic.nu` — always-on (loopback only, no live
  network). Covers send_to/recv_from roundtrip, peer-addr capture,
  connected-mode send/recv on a separate pair, zero-length datagram,
  wildcard dual-stack bind, broadcast + multicast TTL / loop
  setsockopt smoke. Exit 0, output matches `correct.txt` baseline.
- `compiler/tests/dns_basic.nu` — always-on (uses literals + the
  `/etc/hosts` `localhost` mapping that every Linux/macOS/Win box
  has, no external DNS). Covers resolve + resolve_port for both IPv4
  and IPv6, IPv6 bracketed-port formatting, reverse lookup, empty-
  input → `Err NetOther`.

Runtime LOC delta: `stdlib/runtime.c` 4 790 → 5 606 (+816, +17 %)
including the WASI stub row. Bootstrap fixed point unchanged at
**1 620 300 B** (stage1 ≡ stage2 byte-identical IR) — the runtime
extension is pure stdlib, no compiler IR perturbation.

### Added — HTTP peer-bench (Tier D #3, 2026-05-25)

`bench/run_http.sh` + `bench/http_server.{nu,js}` +
`bench/rust_http_server/` (Cargo + hyper 1.9 + tokio multi-thread)
close the long-standing "no Rust hyper / Node http peer comparison"
gap that critic v0.9.0 §10 flagged. Drives `oha` 1.8.0 against three
hello-world servers at four concurrency levels (1, 10, 50, 200),
median of 3 × 10 s per cell. Captured numbers + commentary in
`bench/HTTP_RESULTS.md`:

| Server  | C = 1    | C = 10   | C = 50   | C = 200  |
|---------|---------:|---------:|---------:|---------:|
| NURL    | 14 451   | **68 960** |  60 897  |  59 044  |
| Rust    | 14 507   |  47 703  | **86 699** | **114 694** |
| Node    |  8 708   |  16 726  |  17 108  |  15 555  |

(req/s, higher is better, best in bold per column.)

Highlights:

- NURL is parity with Rust hyper at C=1 (within < 1 %), and is **1.45× ahead**
  of hyper at C=10 — NURL's 8-worker pool fits the workload while tokio's
  12-worker default is over-provisioned at that concurrency.
- Rust hyper pulls ahead at C ≥ 50, peaking at 115 k/s vs NURL's 59 k/s
  (1.94×) at C=200.
- NURL has **the lowest tail latency across the whole sweep**: p99 0.62 ms
  at C=200 vs Rust's 6.19 ms and Node's 20.95 ms.
- Node http plateaus at ~16 k/s — textbook single-event-loop signature.

The Go `net/http` half of the originally-asked-for comparison is
deferred: Go was not installed on the bench host at capture time.
`bench/run_http.sh` has the lane reserved and `bench/README.md`
documents the gap — a PR adding `bench/http_server.go` would re-publish
a four-column table.

### Added — More examples + refreshed catalogue (Tier D #4, 2026-05-25)

Two-part deliverable closing ROADMAP §6 "More Examples":

1. **`examples/find_clone.nu`** — grep-style recursive search over
   files / directories with three modes:

   ```
   find_clone PATTERN [PATH ...]                  # literal substring
   find_clone --list PAT[,PAT...] [PATH ...]      # comma-separated alternatives
   find_clone --regex PAT [PATH ...]              # POSIX-extended regex
   ```

   PATH is one or more files or directories — directories recurse,
   dotfiles are skipped, and with no PATH the tool reads stdin. Output
   is `path:line:contents` per match; exit 0 on any match, 1 on no
   match, 2 on usage / I/O error. Closure-shaped matchers
   (`make_literal_test`, `make_list_test`, `make_regex_test`) so
   `scan_lines` is mode-agnostic; `walk_dir` returns -1 on
   not-a-directory so the dispatcher falls back to the file scanner
   cleanly. Built on top of `stdlib/std/fs.nu` (`read_file`,
   `dir_list`), `stdlib/ext/regex.nu` (`regex_compile` / `_test`), and
   the existing `nurl_str_*` helpers. Pure CLI I/O — runs on the
   public playground.

2. **`examples/README.md` refresh** — from a 3-of-36 catalogue to all
   36 rows, organised by category (CLI tools / Algorithms / Data
   formats / Language showcase / HTTP & RPC / LLM API / SDL canvas).
   Each row carries a one-line description plus a **playground** or
   **local** tag describing where it can run. *playground* = pure
   compute + stdin / argv / file I/O (runs on `play.nurl-lang.org`
   as-is); *local* = needs network, a server listening port, an
   `ANTHROPIC_API_KEY`, SDL2, or microphone access.

The critic-suggested agent-loop variants and MCP-client demo were
deliberately omitted: `examples/claude_agent.nu` already covers the
agent shape, and an MCP-client-from-the-public-playground would need
either secret injection (API keys) or WASM outbound sockets,
neither of which the playground exposes today.

### Added — GitHub Actions CI (critic v0.9.0 Tier D #2, 2026-05-25)

`.github/workflows/ci.yml` lifts the previously-local build + test +
sanitiser gate to PR-level. Two parallel jobs on `ubuntu-latest`:

- **`build-test`** — installs clang + optional FFI dev libs
  (`libcurl4-openssl-dev`, `libssl-dev`, `libsqlite3-dev`,
  `libpq-dev`, `zlib1g-dev`, `libzstd-dev`) so every
  `stdlib/runtime.<lib>` sentinel lights up, then runs `./build.sh`
  (bootstrap stage1 ≡ stage2 fixed point + the full `run_tests.sh`
  corpus). 15-min timeout.
- **`sanitizers`** — same setup, runs `./build.sh --san --no-tests`
  to build an ASan + UBSan-instrumented stack, then
  `compiler/tests/run_san_tests.sh` over the corpus. 25-min timeout.

Triggers on push to `main` / `Improvements`, PR-to-`main`, and
`workflow_dispatch` (manual rerun). `concurrency.cancel-in-progress`
cancels older runs when a new commit lands on the same ref so the
queue can't fill up on a fast-typing day.

`nurlfmt --check` is deliberately NOT yet wired up — ~100 .nu files
in the current stdlib / tests / examples corpus (and
`compiler/nurlc.nu` itself) are not in canonical form, so adding the
check today would fail every PR with an unrelated 100-line diff.
The follow-up path is documented inline in the workflow comments:
either a single repo-wide `nurlfmt --write` pass first, or grow the
check scope file-by-file as canonicalisation lands.

### Added — Structured logging (critic v0.9.0 Tier D #1, 2026-05-25)

`stdlib/std/log.nu` gains two structured-logging features that the
critic flagged as missing-for-v1.0 (ROADMAP §2):

1. **Key/value variants** — `log_debug_kv1` / `_kv2` / `_kv3`,
   `log_info_kv1..3`, `log_warn_kv1..3`, `log_error_kv1..3`. Twelve
   fixed-arity helpers that accept 1..3 `s` key / `s` value pairs
   alongside a message. Same below-threshold suppression as the raw
   and `fN` variants.

2. **JSON output mode** — `log_set_json T` / `log_set_json F`,
   `log_get_json`. When JSON is on, every `log_*` call emits a single
   `{"level":"info","msg":"…","key":"value",…}` line instead of the
   `[INFO]  msg key=value` text form. Compatible with `jq`, Logstash,
   Loki, CloudWatch, etc. — values are RFC 8259-compliant (named
   escapes for `"` `\` `\n` `\r` `\t`; remaining control bytes
   0x00..0x1F emit `\u00XX`).

The existing raw `log_<level>` and `log_<level>fN` calls route
through the new shared `__log_dispatch` so JSON mode applies
uniformly to every call site. The per-byte JSON-escape walker uses
a `*u` pointer instead of `nurl_str_get` to avoid the O(strlen)
per-character cost. Compiler / bootstrap untouched; regression
`compiler/tests/log_structured.nu` exercises text mode, JSON mode,
escape coverage and below-threshold suppression. `jq -c .`
round-trips every JSON line emitted by the test.

### Added — Tier A diagnostics for the v0.9.0 critic (2026-05-25)

Closes the four "grammar-legal but semantically dead" cases the
external review flagged as silent compiles. Each is a small, local
compiler change; bootstrap fixed point holds (stage1 ≡ stage2
byte-identical IR at **1 620 300 B**); full test corpus green.

1. **`^` vs `^^` XOR confusion `warning:`** — `gen_ret` peeks the
   token after the returned expression. If it is on the same source
   line as the `^` AND is value-producing (not `:` / `=` / `;` / `}`
   / `)` / `]` / `{` / EOF), the user almost certainly wrote `^ X Y`
   intending XOR. Emits a soft `warning:` naming `^^` (two adjacent
   carets, no space) as the cure. Test: `should_warn_caret_xor.nu`.
2. **Bare-callable-as-statement `error:`** — `gen_stmt` checks for
   `name args` (no parens) at statement position. If `name` is a
   known callable (registered in syms with no `__ptr` / `__global`
   / `__param`), dies with `( name args )`-cure pointer. The
   companion `gen_ffi_decl` now stamps `<name>__ffi = 1` so FFI
   builtins like `nurl_print` are detected alongside @-fns. Test:
   `should_fail_bare_ident_stmt.nu` (PoC: `nurl_print \`oops\``).
3. **Use-after-`_free` via wrapper `error:`** — auto-infer `sink`
   convention on parameters that a function passes to a destructor
   (`*_free`) or to another fn's existing `sink` slot. New helper
   `bck_record_inferred_sink` accumulates into
   `__fn_inferred_sink__` per fn body; `gen_fn_decl_concrete`
   merges into `g_fn_sink[fname]` after body parses, deduping
   against the explicit `sink` marker. Closes the indirect
   `( take s ) ( read s )` use-after-free the critic exhibited.
   Test: `should_fail_uaf_indirect.nu`. Also added
   `str_word_index` helper next to `str_contains_word`.
4. **Per-instantiation source line for generics** — replaces the
   opaque `<generic>:1:21:` synthetic filename with
   `<generic vec_as_slice__i64 from user.nu:42>:1:21:` so a parse
   error during the substituted-body re-parse names the call site
   in the user's own code. `defer_instantiation` now captures the
   call-site file + line; `flush_deferred_instantiations` passes
   them to `emit_one_instantiation`, which builds the synthetic
   filename. (Diagnostic-only — IR unchanged.)

### Changed — `stdlib/ext/json.nu` parser ~34× faster (2026-05-25)

`json_parse` of the `bench/json_parse` payload (5 × 64 KB) dropped
from **479 ms** to **14 ms** — now faster than Python's C-extension
`json` (~34 ms) and within ~3× of a hand-written zero-copy Rust
parser (~5 ms). Two landed changes:

1. **Direct `*u` pointer reads instead of `nurl_str_get`.** Every
   `__jp_peek` was paying a full `strlen` of the whole input (the
   `core/string.nu` helper does an `strlen` for the bounds check) —
   a 64 KB parse spent gigabytes of memory bandwidth in `strlen`
   alone, classic O(n²). Replaced with a cached `*u`-based byte read
   against `. p src`, plus a `memchr`-driven fast path in
   `__jp_parse_string` that slices the literal byte range when the
   string contains no `\` escape (the common case).

2. **Packed-layout `String` constructor.** New
   `core/string.nu::string_from_bytes_packed` allocates the 24-byte
   `Vec` control block and the data buffer in a single
   `nurl_alloc(24 + n + 1)`. `vec_free` / `vec_free_with` /
   `__vec_grow` in `core/vec.nu` detect the layout by `data ==
   ctl + 24`; the lifecycle is byte-identical to a normal String
   (it can still grow — the first growth pays for an unpacking copy
   out into a separate buffer). For JSON parsing every `JNum` /
   `JStr` is read-only after construction, so this exact case halves
   the per-string allocation count.

Bench runner (`bench/run.sh`) also stopped forking `date` twice per
measurement by switching to `$EPOCHREALTIME` arithmetic (bash 5+),
shaving ~3 ms of measurement overhead per cell.

`bench/RESULTS.md` and `README.md` updated with the new headline
numbers. Bootstrap fixed point holds; full test corpus green;
no API or grammar changes.

### Added — `bench/` peer-comparison benchmark suite (2026-05-25)

Three reproducible micro-benchmarks with one source file per language
(NURL, Python 3, Rust, Node.js):

* `bench/lcg.{nu,py,rs,js}` — 100M-step MMIX linear congruential
  generator. Tight i64 multiply + add with a single-stream data
  dependency that defeats LLVM's closed-form folding.
* `bench/sieve.{nu,py,rs,js}` — Sieve of Eratosthenes computing
  π(10 000 000) = 664 579. Memory bandwidth + branch prediction.
* `bench/json_parse.{nu,py,rs,js}` — 5 parses of a deterministic
  ~64 KB JSON file. Each language uses **what ships in its standard
  distribution** (Python `json`, Node `JSON.parse`, NURL
  `stdlib/ext/json.nu`; Rust links a small hand-written
  recursive-descent parser since it has no JSON in stdlib).

`bench/run.sh` compiles each NURL + Rust target, runs every present
language N times (default 5) with a per-run `timeout`, and prints a
median-wall-clock-ms table. Missing tools render as `n/a`; a cell that
hits the timeout renders as `>30s` instead of hanging the suite.

`bench/RESULTS.md` captures the numbers from one specific machine:

* On `lcg` and `sieve` NURL lands within measurement noise of Rust —
  same LLVM `-O2 -flto` codegen on both sides.
* On `json_parse` NURL's pure-NURL parser is ~12× slower than Python's
  C `json` and ~50× slower than a hand-written Rust parser. The
  module's allocator-and-Vec-growth path through recursive descent is
  the explanation, and a zero-copy slice-based rewrite would close
  most of the gap — tracked as a follow-up.

An HTTP-server-vs-`net/http` peer benchmark is not included; that
would need a Go install and a `wrk`-shaped harness.

### Changed — borrow-checker diagnostics are now hard errors

* `bck_diag` (use-after-move) and `bck_esc_warn` (escape analysis +
  aliased-mut + iterator invalidation) emit `: error: ` instead of
  `: warning: ` and bump a new `g_bck_errors` counter. `main()` exits
  non-zero after `parse_program` if any violation was recorded —
  every error surfaces in one run (same shape as a C compiler).
* The test harness now treats `borrow_*` tests as expected compile
  failures with an `ERRORS` baseline blob rather than "compile OK +
  WARNINGS". The exact error text remains regression-protected.
* `--no-borrowck` remains the escape hatch; the abort message points
  at it so a user hitting a false positive is never wedged.
* Bootstrap fixed point holds (the checker is diagnostic-only — IR is
  byte-identical with or without `--no-borrowck`): stage1 ≡ stage2 at
  **1 602 394 B**.

Five bug classes are now compile errors by default: use-after-move,
alias double-free, closure escape, call-site aliased mutation, and
iterator invalidation. `*T` raw pointers and aliased mutation through
nested-argument reads remain unchecked; see
[`docs/MEMORY.md`](docs/MEMORY.md).

## [0.9.0] — 2026-05-24

### Changed — `refactor/nurlify` branch

Picks up where `refactor/pure-nurl` left off and drives `stdlib/runtime.c`
the rest of the way down:

* **`stdlib/runtime.c`: 6 265 → 4 540 LOC (−1 725, −27.5 %).** Combined
  with the prior branch the total reduction since v0.8.0 is **8 879 →
  4 540 LOC (−4 339, −48.9 %)** — over half of the C runtime is gone.
  Bootstrap fixed point held on every shipped phase; full test corpus
  green.
* **PURIFY §17 random.** `rand_u64` / `rand_hex_str` ported to pure
  NURL in `stdlib/std/random.nu`. Only `nurl_rand_fill` stays C —
  the `getrandom` / `arc4random_buf` / `BCryptGenRandom` platform
  branching is genuinely syscall-shaped FFI.
* **PURIFY §4 file ops batch.** `nurl_read_file_bytes` /
  `_write_file_bytes` / `_file_read_chunk` / `_read_n_bytes` /
  `_errno_kind` moved to pure NURL. The `g_last_bytes_len` sideband is
  gone — `fread` / `fwrite` write directly into the `Vec[u]` data
  buffer and `vec_set_len` records the count. `EACCES` / `EPERM` /
  `EEXIST` added to `nurl_native_constant`; `errno_kind` now lives in
  `stdlib/core/posix.nu`.
* **PURIFY §22 gzip.** `nurl_gzip_compress` / `_decompress` moved to
  pure-NURL FFI in `stdlib/ext/compress.nu` over `deflateInit2_` /
  `deflate` / `deflateEnd` + `inflateInit2_` / `inflate` /
  `inflateEnd`. Two tiny C accessors (`nurl_z_setup` /
  `nurl_z_total_out`) bridge the platform-varying `z_stream` field
  layout (LP64 vs LLP64 `uLong` width).
* **PURIFY §14 HTTP response accessors.** The 7 accessor C functions
  (`status` / `err_kind` / `body` / `body_len` / `header_count` /
  `header_name` / `header_value`) deleted from `runtime.c`. Pure-NURL
  equivalents in `stdlib/ext/http.nu` read the `NurlHttpResponse`
  heap struct via `nurl_peek(p, slot)` over its 6-i64 slot layout.
  Static asserts in `runtime.c` pin the layout at compile time so a
  future field reorder breaks the native build instead of silently
  miscompiling NURL reads. `nurl_http_response_free` stays C because
  it walks `headers[]` deallocating each name / value pair plus the
  body.
* **PURIFY §14b HTTP libcurl backend** + multi-stream orchestration
  driven from pure NURL. Sync `nurl_http_perform_full_to` and
  multi-stream `_open_to` / `_next` / `_pump_headers` plus the 5
  stream accessors live in `stdlib/ext/http.nu`; 22 monomorphic
  trampolines stay C (`nurl_curl_*` `setopt` / `multi` /
  stream-state) because libcurl's variadic `curl_easy_setopt` and the
  raw-fn-pointer callbacks (`nurl__http_write_body` /
  `_write_header`) can't cross the FFI directly. `NurlHttpStream`'s
  three historical `int` fields widened to `long long` for a clean
  14×i64 slot layout; `static_assert` pins it. Live verified
  against httpbin.
* **PURIFY §2 SIMD CSV scanner** ported to pure NURL
  (`stdlib/ext/csv.nu`, −508 C). The vectorised newline / delimiter
  scanner is now NURL @-fns over `nurl_peek` of a heap-side byte
  window.
* **`runtime.c` prose cleanup** (commits `d558844`, `f88d7bb`):
  trimmed verbose multi-paragraph explanations, phase-by-phase
  migration history and prose that just restated what the code does
  — kept one-line function-purpose intros and the non-obvious "why"
  notes (TLS / SNI race discipline, fiber park-unlock ordering,
  wasm32 layout caveats, libz LP64 / LLP64 differences). Net −913
  comment-only LOC.

### Changed — `JSON-to-production` branch

* **`json` ext goes production-ready.** `stdlib/ext/json.nu`:
  - **Typed `JsonError`** replaces the bare `ParseErr` — carries
    `kind` (`BadFormat` / `Empty` / `TrailingGarbage` / `Overflow`),
    `pos` (0-based byte offset), `line` (1-based) and `col`
    (1-based). Location is computed once per failure and travels
    with the error value — no global state, so nested
    `json_parse` calls and multi-threaded use are both safe.
    `json_format_error` renders the standard message; build your
    own from the fields if you need a custom shape.
  - **RFC 8259 strict mode.** Non-conforming numbers (leading zeros
    like `01`, `+5`, lone `.5`, `1.`) are now `BadFormat` instead of
    parsing to the prefix — `json_stringify ∘ json_parse` is
    guaranteed-valid JSON.
  - **New constructors** — `json_int n` / `json_float x` from
    primitives (no `i8*` roundtrip), `json_arr_new` / `json_obj_new`
    for empty containers.
  - **Duplicate-key behavior documented.** Parser preserves
    duplicate keys as-is; `json_obj_get` returns the first match in
    source order; `json_obj_set` replaces the first match in source
    order.
  - Call sites updated across `stdlib/ext/anthropic.nu`,
    `stdlib/ext/mcp{,_client,_http,_stdio}.nu`, `nurlapi/main.nu`,
    `examples/serde_demo.nu`, `tools/nurl-lsp/jsonrpc.nu`.

### Changed — `refactor/pure-nurl` branch

The `refactor/pure-nurl` branch took the bulk of `stdlib/runtime.c`
out of C and into pure NURL — either as pure-NURL @-fns or as direct
`& \`c\`` / `& \`pthread\`` / `& \`sqlite3\`` FFI declarations.

* **`stdlib/runtime.c`: 8 879 → 6 265 LOC (−2 614, −29.4 %).** The
  bootstrap fixed point held on every shipped phase and the full
  test corpus stayed green.
* **Python removed from the bootstrap.** `compiler/nurlc.py` and
  `compiler/src/*.py` are gone. Stage 0 now links the committed
  `compiler/nurlc_lastgood.ll` snapshot directly via clang. The
  only build-time dependency is clang/LLVM 14+. Refresh the
  snapshot with `./build.sh --refresh-bootstrap` when a
  grammar/runtime-ABI change leaves the current snapshot unable
  to compile current `nurlc.nu`.
* **`Box[T]` / `Cell[T]` / `Rc[T]` / `Arc[T]`** heap-stable
  allocator surface — `stdlib/core/box.nu`, `stdlib/core/cell.nu`,
  `stdlib/std/rc.nu`, `stdlib/std/arc.nu`. `% Drop` auto-fires;
  `nurl_native_sizeof` + `nurl_atomic_i64_*` runtime primitives
  added. This unblocked Phases 6 / 8 / 11 / 12 of the purification.
* **Per-phase migration:**
  - Phase 1 §3 char classification (`stdlib/core/char.nu`, −11 C)
  - Phase 2 §15 logging level (`stdlib/std/log.nu`, −7 C)
  - Phase 3 §11 libm + integer helpers (`& \`m\`` / `& \`c\`` FFI, −17 C)
  - Phase 4 §17 crypto MD5/SHA-1/256/512 + HMAC
    (`stdlib/std/hash_*.nu`, **−541 C**)
  - Phase 5 §2 string ops over libc (strlen/strcmp/strncmp/strstr/
    memcmp/memmem/atoll/atof/memcpy/strdup via preamble, **−682 C**)
  - Phase 6 §19 threads / mutex / cond (pthread `& \`pthread\``
    FFI in `stdlib/std/thread.nu`, −162 C; mingw-w64 winpthreads
    linked via `-lpthread`)
  - Phase 7 §4 + §13 file & dir syscalls — incremental over many
    batches (realpath / write_file_safe / file_size / mmap / fread
    fallback / dir_list POSIX, −158 C combined)
  - Phase 8 §16 + §16b process spawn (fork/exec/poll, `||` and
    `&&` added as language tokens for the spawn-error sideband,
    **−245 C**)
  - Phase 9a §7 + §8 codegen counters + last-type sideband
    (pure-NURL @-fns in `nurlc.nu`, −71 C)
  - Phase 9b §6b symbol table (3 parallel grow-by-2× arrays,
    inner loops via direct `*s` / `*i` pointer arithmetic, −72 C;
    ~0.95× of C runtime — LTO inlines everything and the parallel
    layout is cache-friendlier than the C interleaved struct)
  - Phase 9c §5 HashMap deleted entirely (the canonical
    `stdlib/std/hashmap.nu` HashMap[s i] is the one-true map for
    every consumer; the migration also fixed `hash_string` from
    O(n²) → O(n) by switching from per-byte `nurl_str_get` to a
    direct `*u` byte walk, −101 C)
  - **Phase 10 §6a Lexer (the big one, −592 C).** Full state
    machine + 4-deep lookahead ported to pure-NURL @-fns over a
    280-byte heap handle. Uncovered + fixed a subtle escape-handling
    bug: only `\n \t \r \\` are real escapes; any other `\X`
    (including `` \` ``) writes the lone `\` and advances one byte.
  - Phase 11 §23 DoS protection (`stdlib/std/dos.nu`, −180 C)
  - Phase 12 §21 SQLite bridge — pure-NURL FFI over 18 libsqlite3
    symbols (`stdlib/ext/sqlite.nu`, **−330 C**)
  - §12 Time — `clock_gettime` + `nanosleep` FFI (`stdlib/std/time.nu`,
    −38 C; macOS uses `CLOCK_MONOTONIC = 6` vs `1` elsewhere, read
    at runtime via `nurl_native_constant`)
  - §13 batch 2/3 — stdin + dir_list POSIX FFI (−80 C)
  - §11 strtod sideband eliminated with an endptr buffer (−20 C)
* **`||` and `&&` operators** added as language tokens — strict
  binary, bool-only short-circuit. Alternative to the chainable
  `|` / `&` for cases that are more readable as a `||` / `&&`
  chain. Grammar v2.0 documents them. Same LLVM IR as `|` / `&`
  on i1 left operands.
* **`./check.sh <file.nu>`** — per-file syntax/type check tool;
  runs `nurlc` against a single source file in ~0.2 s vs build.sh
  ~60 s. Use in iterate-fix loops before kicking the full build.
* **Test runner output split** into `success.txt` + `failures.txt`
  so a failed test is greppable without scrolling through the
  green output.
* **Parenthesised-operator diagnostic.** A `(` begins a call, so
  `( . obj field )` / `( | a b )` / `( + x y )` etc. now produce
  a precise call-site `error:` instead of a far-away LLVM-verifier
  complaint. (Listed earlier in this section under the original
  feature work; reiterated here as it landed in this branch.)
* **Call-arity diagnostics.** Every call's argument count is
  checked against the callee's declared parameter count; a
  mismatch points at the call site (same listing remark).
* **Prefix arity-cascade diagnostic.** Short-an-argument prefix
  operator over-reads now name the offending token and point back
  at the line where the cascade started.
* **`mcp_response_get_result`** — `mcp_client`'s 1-arg result
  extractor renamed for consistency with the rest of the surface.

### Fixed — `refactor/pure-nurl` branch

* **WASM FFI width mismatches** uncovered by uuidgen wasm build
  (2026-05-24). `nurl_errno_get` / `nurl_errno_set` /
  `nurl_wait_is_exited` / `_exit_status` / `_is_signaled` /
  `_term_sig` paluut + parametrit widened `int` → `long long`
  in `stdlib/runtime.c`. On x86_64 SysV the `int` return's upper
  32 bits were undefined and accidentally zero; wasm-ld validates
  signatures strictly and refused to link until the C side
  agreed with the NURL FFI's `→ i` (i64) declaration. `memmem`
  added to `api/app/main.py:LIBC_WASM32_ABI` (the playground's
  wasm-build IR rewriter), since wasm32 `size_t` is i32 but
  `nurlc.nu`'s preamble emits `memmem(i8*, i64, i8*, i64)`.
* **macOS `WIFEXITED` lvalue requirement.** The widened
  `nurl_wait_*` functions originally passed `(int)status` as an
  rvalue to the W*-macros; macOS's `<sys/wait.h>` expands them
  to `*(int*)&(x)` which needs an lvalue. Fixed by binding
  `int s = (int)status;` first inside each wrapper. Restores the
  zig macOS-arm64 / macOS-x64 cross-build.

### Added

* **MsgPack serde.** `stdlib/ext/serde.nu` gained `from_msgpack_i` /
  `from_msgpack_f` / `from_msgpack_b` / `from_msgpack_string` —
  decoding MessagePack bytes straight to a built-in value. There is no
  `% MsgpackSerialize` trait: MessagePack and JSON share a data model,
  so a value is encoded by composing the existing `to_json` with
  `msgpack_encode`. The decoders return `!T MsgpackErr` (not
  `ParseErr` — `MsgpackErr` is the richer error type and represents
  every failure losslessly); `MsgpackErr` gained a
  `MsgpackTypeMismatch` variant for a value that decoded cleanly but
  is the wrong shape. Demo `examples/msgpack_demo.nu`; regression
  `compiler/tests/msgpack_serde.nu`. With this the serde story covers
  JSON, TOML and MessagePack — all reusing one `JsonSerialize` impl
  per type.

* **TOML serde.** `stdlib/ext/serde.nu` gained its TOML side: a
  `% TomlSerialize [T] { @ to_toml T x → TomlValue }` trait with impls
  for `i` / `b` / `s` / `String`, and `from_toml_i` / `from_toml_b` /
  `from_toml_string` decoders returning `!T ParseErr` — the same shape
  and error type as the JSON helpers. There is no `f` impl: the
  `TomlValue` AST has no float variant. `stdlib/ext/toml.nu` gained
  `toml_stringify`, the inverse of `toml_parse`: a `TomlValue` is
  rendered as TOML text — top-level `key = value` lines, nested tables
  and arrays inline, strings escaped with the `\\ \" \n \r \t` set the
  parser accepts, so `toml_parse ∘ toml_stringify` round-trips.
  Regression `compiler/tests/toml_serde.nu`; verified leak-free under
  ASan/UBSan/LSan.

* **MessagePack codec.** `stdlib/ext/msgpack.nu` is a faithful binary
  codec between the `Json` value and the MessagePack wire format:
  `msgpack_encode Json → ! ( Vec u ) MsgpackErr` and `msgpack_decode
  ( Vec u ) → ! Json MsgpackErr`. The encoder emits the smallest
  signed integer format, float64 for reals, and length-appropriate
  str / array / map headers; the decoder accepts every integer and
  float format plus all str / array / map sizes. `bin` / `ext` and
  non-string map keys are reported as `MsgpackUnsupported`; truncation
  and malformed input have their own `MsgpackErr` variants; a
  recursion cap guards both directions. Three runtime helpers —
  `nurl_f64_bits`, `nurl_f64_from_bits`, `nurl_f32_from_bits` — provide
  the IEEE-754 bit access needed for the float wire format. Regression
  `compiler/tests/msgpack_basic.nu` (37 assertions: round-trips,
  msgpack.org encode vectors, non-canonical-format decoding, malformed
  inputs); verified leak-free under ASan/UBSan/LSan. First of the
  three Serde-completion ships (codec, then TOML serde, then MsgPack
  serde).
* **Runtime float-bits helpers** — `nurl_f64_bits`,
  `nurl_f64_from_bits`, `nurl_f32_from_bits` in `stdlib/runtime.c`.
* **Parenthesised-operator diagnostic.** A `(` begins a function call,
  so the token after it must be a function name. An operator token
  there — `( . obj field )`, `( | a b )`, `( + x y )` — meant an
  operator expression was wrongly wrapped in parentheses. nurlc used
  to take the operator's lexeme as the callee, emit a call to a
  function literally named `.` / `|` / `+`, and let the build fail far
  from the source at link time with `use of undefined value`.
  `gen_call` now rejects a binary operator, member access `.`, the
  cast `#` or the caret `^` immediately after `(` with a precise
  `error:` at the call site — `operator '.' cannot be a call target:
  '(' begins a function call, but operator expressions are written
  without parentheses` — and a caret on the operator. Regression
  `compiler/tests/should_fail_paren_operator.nu`.

* **Typed Path.** `stdlib/std/path.nu` gained a `Path { String inner }`
  typed, owning wrapper over a path string, with a concise
  Rust-PathBuf-style verb API — `path_new`, `path_str` (borrow the
  inner buffer), `path_len`, `path_is_empty`, `path_clone`,
  `path_free`, `path_eq`, `path_push` (join one component),
  `path_parent`, `path_name`, `path_is_abs` — and the two operations
  the existing string-level layer lacked: `path_canonical` (realpath:
  absolute, symbolic links resolved) and `path_relative_to` (a purely
  lexical relative path between two paths). Both return `? Path` —
  None for a missing / inaccessible path or a not-comparable pair. The
  string-`s`-based `path_*` functions stay the raw layer underneath;
  the typed functions never consume their arguments. One runtime
  helper, `nurl_realpath`, is reached through the pure-NURL `& \`c\``
  FFI model, so the compiler is unchanged and the bootstrap fixed
  point is byte-identical. Regression `compiler/tests/path_typed.nu`;
  verified leak-free under ASan/UBSan/LSan.
* **Runtime helper** — `nurl_realpath` (realpath on POSIX, `_fullpath`
  on Windows) in `stdlib/runtime.c`.
* **Extended hash family — SHA-512, MD5, HMAC-SHA-512.**
  `stdlib/std/hash.nu` gained `sha512_bytes` / `sha512_hex` (FIPS 180-4
  SHA-512, 64-byte digest), `md5_bytes` / `md5_hex` (RFC 1321 MD5,
  16-byte digest) and `hmac_sha512_bytes` / `hmac_sha512_hex` (RFC 2104
  HMAC over SHA-512). All are binary-clean — they take `( Vec u )` and
  are length-aware, so NUL bytes are preserved — mirroring the existing
  `sha1_bytes`. The three algorithms are self-contained in
  `runtime.c` §17 (no libsodium / OpenSSL dependency) and are reached
  through the pure-NURL `& \`c\`` FFI model, so the compiler is
  unchanged and the bootstrap fixed point is byte-identical. MD5 and
  SHA-1 are documented as compatibility-only — both are collision-broken
  and must not authenticate data or hash secrets. Regression
  `compiler/tests/hash_extended.nu` checks every algorithm against
  published vectors (RFC 1321 §A.5, FIPS 180-4, RFC 4231 HMAC cases
  1/2/6); verified leak-free under ASan/UBSan/LSan.
* **Runtime hash primitives** — `nurl_md5_bytes`, `nurl_sha512_bytes`,
  `nurl_hmac_sha512_bytes` in `stdlib/runtime.c`.
* **Advanced filesystem operations.** `stdlib/std/fs.nu` gained
  recursive directory operations and a streaming file reader:
  `dir_create_all` is mkdir -p — it creates every missing parent
  directory and treats an already-existing directory as success;
  `dir_remove_all` is recursive rm -rf — it walks the tree removing
  every entry before removing the directory itself, and unlinks a
  symlink rather than descending through it. `file_open` /
  `file_read_chunk` / `file_eof` / `file_close` read a file in
  fixed-size byte chunks over a new `File` handle, so a binary input
  far larger than RAM can be processed without ever being fully
  resident (line-oriented streaming stays with `stdlib/std/bufio.nu`).
  Three new `runtime.c` filesystem helpers back this — `nurl_path_type`
  (an lstat-based entry classifier), `nurl_file_read_chunk` and
  `nurl_file_eof` — all reached through the pure-NURL `& \`c\`` FFI
  model, so the compiler is unchanged and the bootstrap fixed point is
  byte-identical. Regression `compiler/tests/fs_advanced.nu`; the new
  paths are verified leak-free under ASan/UBSan/LSan.
* **Runtime filesystem helpers** — `nurl_path_type`,
  `nurl_file_read_chunk`, `nurl_file_eof` in `stdlib/runtime.c`.
* **Call-arity diagnostics.** `gen_call` now checks every call against
  the callee's declared parameter count and rejects a mismatch with a
  precise `error:` at the call site — e.g. `call to 'add' has the
  wrong number of arguments: expected 2, got 1`. Previously a
  wrong-arity call to a known function either miscompiled silently
  (too few arguments) or emitted a malformed `call` the LLVM verifier
  complained about far from the source (too many). `scan_fn_sigs`
  records each non-generic `@`-function's parameter count through a
  new pure-lexical type skipper (`scan_skip_type` — no `parse_type`
  call, which would desync the scan); a name carrying two definitions
  of differing arity is marked ambiguous and skipped rather than
  mis-blamed. Generic and variadic-FFI callees are out of scope for
  v1.
* **Prefix arity-cascade diagnostic.** When a prefix operator runs out
  of operands and over-reads into the following statement — the
  classic NURL cascade, since operators have fixed arity and no
  closing bracket — the resulting "unexpected token" error now names
  the offending token and points back at the line where the
  short-an-argument statement began, instead of blaming the innocent
  next line.
* **Compiler regressions** — `compiler/tests/{call_arity_ok,`
  `should_fail_call_arity_few,should_fail_call_arity_many,`
  `should_fail_prefix_cascade}.nu`.
* **MQTT client — topic-filter wildcard matching.** `mqtt_topic_matches`
  in `stdlib/ext/mqtt.nu` implements the MQTT 5.0 §4.7 `+` / `#`
  wildcard rules — `+` matches one topic level, `#` matches the
  remainder (zero levels included, so `sport/#` also matches the parent
  `sport`) — including the §4.7.2 guard that a filter beginning with a
  wildcard never matches a `$SYS/...` topic. The intended use is
  client-side dispatch when one connection carries several
  subscriptions.
* **MQTT offline codec regression** — `compiler/tests/mqtt_codec.nu`
  exercises the Variable Byte Integer round-trip, the unsigned byte
  reader, MQTT UTF-8 string framing, the CONNECT byte layout, CONNACK
  reason extraction, MQTT 5 user-property parsing, the typed `MqttErr`
  names, and topic matching — no network, CI-safe.

## [0.8.1] — 2026-05-21

### Added

* **Playground multi-target cross-compilation.** The `api/` browser
  playground replaces its four fixed build buttons (WASM / native /
  Windows / macOS) with a grouped **Target** dropdown + one **Build**
  button. New compile targets, all driven by the `zig cc` pipeline
  already shipped for macOS:

  * `linux-x64-musl`, `linux-arm64-musl`, `linux-riscv64-musl` —
    fully-static ELF (runs on any Linux of that arch, no libc pin).
  * `linux-arm64-gnu` — dynamic glibc 2.31+ ELF.
  * `macos-x64`, `macos-arm64` — Mach-O; Apple Silicon was previously
    unreachable (the only macOS target was Intel).

  Backed by `POST /build_target` (target id in the body) and
  `GET /targets` (the registry the UI builds its dropdown from); the
  three near-duplicate build endpoints now share one `_build_zig_cross`
  helper. `POST /build_macos` is kept as a thin wrapper for MCP / older
  clients. The MCP server (both `/mcp` and the REST companion) gains a
  `nurl_build_target` tool — valid target ids are inlined as a schema
  enum so clients need no separate lookup; the existing per-OS build
  tools are unchanged. canvas/audio FFI is rejected on the cross
  targets and HTTP falls back to the runtime's no-op stubs — same
  contract macOS had.

  Image cost is ~negligible: zig already bundles musl / glibc /
  libSystem for every arch, so each target adds only one ≈125 KB
  `runtime.<id>.o`. The Dockerfile cross-compiles those at build time
  and **pre-warms** each target's libc/compiler-rt into a baked
  `ZIG_GLOBAL_CACHE_DIR`, so the first build per target is a fast
  cache hit rather than a cold multi-second libc compile; the warm
  link doubles as a build-time smoke test. No `riscv64` glibc target —
  zig 0.13's bundled glibc for RISC-V is incomplete; `riscv64-musl`
  covers RISC-V until the image moves to zig ≥ 0.14.

* **`stdlib/std/time.nu` calendar completion.** On top of the existing
  `Time` struct and Hinnant `civil_from_days` conversions:

  * `is_leap_year`, `days_in_month` (leap-aware), `time_yday` (1..366).
  * `time_make Y Mo D H Mi S` — range-checked civil-time constructor
    (rejects e.g. 2023-02-29 and month 13).
  * `time_cmp` / `time_eq` / `time_before` / `time_after` — order
    timestamps (by Unix-second value).
  * `time_add_seconds` / `time_add_days` (negative subtracts; rolls
    month/year/leap-day over) / `time_diff_seconds`.
  * `time_format t fmt` — strftime subset (`%Y %y %m %d %H %M %S %j
    %a %A %b %B %%`), alongside the fixed `time_format_iso` /
    `time_format_http`.

  Regression `compiler/tests/time_calendar.nu`; `calendar_time.nu`
  updated. All pure NURL arithmetic, ASan/UBSan/leak-clean.

* **Buffered streaming reader — `stdlib/std/bufio.nu`.** `BufReader` pulls
  a file (or stdin) through a 64 KiB buffer one `fread` at a time, so an
  input far larger than RAM is processed without ever being fully
  resident — the streaming counterpart to `read_file` / `csv_reader_new`,
  which load the whole file first. Built for fast ETL over logs / CSV /
  JSONL:

  * `bufreader_open path → ! BufReader IoErr`, `bufreader_stdin → BufReader`.
  * `bufreader_read_line br → ? String` — a fresh owned line each call,
    `\n` / `\r\n` stripped; `None` at EOF.
  * `bufreader_read_line_into br dst → b` — refills the *caller's* String
    with the next line, so a steady-state read loop allocates nothing
    after warm-up (one `memcpy` per line, no `malloc`). The recommended
    ETL hot path.
  * `bufreader_eof`, `bufreader_close`.

  Line terminators are found with `memchr` (glibc SIMD), not a byte loop.
  Lines longer than the buffer grow it; lines straddling a refill
  boundary are compacted with `memmove`. Neither read entry point hands
  back a pointer into the internal buffer, so there is no
  invalidated-view foot-gun. Implemented as pure-NURL `& \`c\`` FFI
  (`fread` / `memchr` / `memmove` / `fdopen`) — no `runtime.c` change.
  New supporting primitive `string_push_bytes` (`stdlib/core/string.nu`)
  appends a known-length raw byte range to a String. Regressions
  `compiler/tests/bufio_basic.nu` (mixed terminators, empty + trailing
  unterminated line, missing-file error) and `bufio_stream.nu` (50 001
  lines across ~17 refills + a 200 000-byte line forcing buffer growth);
  both ASan + UBSan + leak-detection clean.

* **Standard-library Clone story.** Owned containers can now be deep-copied
  without hand-rolling a per-type clone. NURL has no type-class dispatch,
  so — exactly like the existing `vec_free` / `vec_free_with` split — the
  clone is delivered as a per-call closure rather than a language-level
  `Clone` trait:

  * `string_clone String → String` (`stdlib/core/string.nu`) — independent
    deep copy of an owned String; embedded NUL bytes preserved verbatim.
    The stock element-clone for owned-String containers.
  * `vec_clone [A] v → ( Vec A )` — bitwise shallow copy, trivial element
    types only. `vec_clone_with [A] v ( @ A A ) clone → ( Vec A )` — deep
    copy that runs `clone` per element; use for `Vec[String]`, nested
    `Vec`, `Vec[HashMap]`.
  * `vec_filter_with [A] v ( @ b A ) pred ( @ A A ) clone → ( Vec A )` —
    owned-safe filter: kept elements are *cloned* into the result instead
    of bitwise-aliased, so source and result can both be freed with
    `vec_free_with` without a double-free. Plain `vec_filter` stays the
    fast path for trivial elements.
  * `map_clone [K V] m → ( HashMap K V )` — bitwise, trivial K/V.
    `map_clone_with [K V] m ( @ K K ) clone_k ( @ V V ) clone_v` — deep
    copy. Both preserve the source slot layout verbatim (same cap, probe
    positions, tombstones), so the clone needs no rehash.

  Before this, `vec_filter` / `vec_extend` / `map_keys` / `map_values`
  bitwise-copied elements — silent UB / double-free for any owned element
  type (`Vec[String]`, `HashMap[String _]`, nested containers), an unsafe
  copy the borrow checker cannot see because it happens inside a
  monomorphised generic. The `_with` variants close that hole. Regression
  `compiler/tests/clone_basic.nu` — verified independence (mutate source →
  clone unaffected) and ASan + UBSan + leak-detection clean.

* **`inout` field targets.** An argument of the form `. obj field` at
  an `inout` parameter now passes the *address of that struct field*,
  so the callee mutates exactly that field of the caller's struct in
  place — finer-grained than passing the whole struct `inout`:

  ```
  @ add100 inout i x → v { = x + x 100 }
  : ~ Game g @ Game { @ Counter { 1 99 } 0 }
  ( add100 . g turns )    // g.turns is mutated in place
  ```

  `obj` must be a mutable (`: ~`) struct binding — or an `inout`
  struct parameter, which carries the same backing-pointer shape. The
  field's address is a `getelementptr` resolved through the
  `<sname>__<field>__idx` roster, so plain and generic structs both
  work; the field may itself be a struct (`( bump . g score )`).
  Single-level access (`. obj field`) only. Regression test
  `compiler/tests/inout_field.nu` (+ `should_fail_inout_field_immut.nu`).

* **`inout` / `sink` parameter conventions on generic functions.**
  A generic function may now mark a parameter `inout` (exclusive
  mutable borrow) or `sink` (the callee consumes it), exactly like an
  ordinary function:

  ```
  @ store_g [A] inout i slot  A item → v { = slot + slot 1 }
  ( store_g [i] n 7 )    // n is mutated in place
  ```

  A parameter convention is a property of parameter *position*, not of
  the type arguments, so the `inout` / `sink` index sets are computed
  once from the generic template (the new `compute_generic_inout_sink`,
  keyed by the generic name) and a call site resolves them by that
  name — the mangled-instantiation entry only appears once the
  deferred monomorphisation is compiled, which is too late for the
  call that triggered it. Previously a generic `inout` argument was
  passed by value into a `<T>*` parameter (an LLVM type mismatch). A
  forward call to a generic `inout` function is rejected with the same
  define-before-call diagnostic as the non-generic case. Regression
  tests `compiler/tests/inout_generic.nu` and
  `should_fail_inout_generic_forward.nu`.

* **Forward references for enum-variant payload types.** An enum
  variant whose payload is a struct or enum declared *later* in the
  same file now parses correctly:

  ```
  : | Shape { Dot  Box Geom }   // Geom used before it is declared
  : Geom { i w  i h }
  ```

  Previously the compiler only recognised a payload type already
  registered in the symbol table, so a forward-referenced payload was
  misread as a phantom extra variant — and any `??` match over the
  enum then failed with a bogus non-exhaustive-match error. A new
  linear pre-pass (`scan_type_names`) registers every top-level
  struct / enum / generic-struct name before the main compile pass,
  following `$`-imports. Regression test
  `compiler/tests/forward_enum_payload.nu`.

### Changed

* **`time_parse_iso` now returns `! i ParseErr`** (Unix seconds), not
  `! Time ParseErr`. A Unix timestamp is the more composable parse
  result — directly sortable, comparable and storable — and
  `time_from_unix` reconstructs the broken-down `Time` when its fields
  are needed. The new `time_make` constructor uses the same
  `! i ParseErr` shape for consistency.

### Fixed

* **A side-effecting `~` while-loop condition no longer drops an
  iteration.** `gen_loop` speculatively parsed the condition (to tell a
  while loop from a complement expression used as a statement) and left
  that speculative IR in the output — so the condition was evaluated
  one extra time up front. For a pure condition this was harmless dead
  code; for a side-effecting condition (`~ ( read_next x ) { … }`) the
  first evaluation's side effects happened with no matching body run,
  silently dropping one iteration's work. `gen_loop` now emits the
  condition straight into the loop-check block and only then looks for
  the `{` — the condition is parsed exactly once and evaluated exactly
  (bodies + 1) times; no speculative IR. Regression
  `compiler/tests/loop_cond_sideeffect.nu`.

* **`?? ( call )` on a wide-payload `! T E` result no longer truncates.**
  Matching directly on a function-call expression whose Result payload
  is a wide value struct (a multi-field `Time`-like type) silently
  produced garbage fields: `gen_match`'s heap-box-unboxing
  reconstruction was keyed on `<name>__res_nurl_T`, which only exists
  when the scrutinee is a named binding — so `?? ( f … )` skipped it and
  the `T`-arm binding received the raw heap-box pointer reinterpreted as
  the struct. `gen_match` now synthesises the binding metadata from the
  callee's NURL return type (`__last_nurl_call__`, cleared before the
  scrutinee is evaluated), so the direct-call form reconstructs exactly
  like `?? r`. Narrow payloads (`i`, pointers, handle structs) were
  always fine. Regression `compiler/tests/match_call_wide.nu`.

* **Enum variant with a struct or enum payload now constructs and
  pattern-matches correctly.** Building `@ E { Variant structValue }`
  used to store the struct value straight into the variant's pointer
  slot (an LLVM type error: a multi-field struct is not a pointer),
  and the matching `??` arm mis-unboxed it. Both sites are fixed:
  construction heap-boxes the `%Name` payload (`nurl_alloc` + `store`)
  and the match arm `load`s it back through the slot pointer. Pointer
  payloads (`*Ast`) and single-pointer-handle structs (`String`,
  `Vec`) keep their existing direct-store path. This bug was
  independent of forward references — it affected backward-declared
  payload types too — but went unnoticed because no test constructed
  such a value.

* **`#`-cast from a named aggregate (enum or struct) to an integer
  now works.** `# i someEnumOrStruct` (or any sized integer
  destination) recovers field 0 — an enum's variant tag, or a
  struct's first field. Previously the cast emitted no instruction,
  so the i64-typed use site (a return, `nurl_print_int`, arithmetic)
  failed the LLVM verifier. `gen_cast` now has one unified branch:
  `extractvalue` field 0, normalise it to i64 (`sext` a narrow
  integer field, `ptrtoint` a pointer field, `fptosi` a float
  field), then `trunc` to a narrower destination. A struct whose
  field 0 is itself an aggregate is a hard error. Regression tests
  `compiler/tests/enum_to_int_cast.nu` and
  `compiler/tests/struct_to_int_cast.nu`.

* **Struct construction coerces narrow integer fields.** `@ S { v }`
  where `S`'s field is `i8` / `i16` / `i32` and `v` is a wider value
  (e.g. an i64 literal) used to emit `insertvalue ... i64 …` into the
  narrow field — an LLVM verifier error — forcing an explicit
  `# i8` / `# i16`-cast at every construction site. `gen_agg_lit`
  now coerces each named-struct field value to its declared field
  type: `trunc` into a narrower field, `sext` into a wider one.
  Regression test `compiler/tests/struct_narrow_field.nu`.

### Fixed

* **`mcp_stdio_call` write-failure classification was racy.** Pinging a
  server that had already exited surfaced either `McpStdioEof` or
  `McpStdioIo` depending on whether the write hit `EPIPE` before the
  child's exit was observed — a non-deterministic result (and a flaky
  `mcp_stdio_basic` test). On a failed write `mcp_stdio_call` now
  consults `proc_eof`: if the child's stdout is also at EOF the server
  is simply gone (`McpStdioEof`, matching the write-lands-then-reads-EOF
  path), otherwise it is a genuine transient pipe fault (`McpStdioIo`).
  The dead-server outcome is now deterministic.

## [0.8.0] — 2026-05-20

### Added

* **Native `^^` XOR operator.** Two adjacent carets lex as a single
  `^^` token (the lexer pairs them only when adjacent — `^ ^` with a
  space is still two return tokens). `^^` is a strictly-binary
  operator lowered to LLVM `xor`: bitwise XOR on integer operands,
  logical XOR on `b` operands. Float operands are a compile error
  (LLVM has no float `xor`). Replaces the old `(a | b) - (a & b)`
  identity workaround. `^` alone remains the return operator.
  Grammar (`spec/grammar.ebnf`) and `nurlfmt` updated; regression
  tests `xor_op.nu` + `should_fail_xor_float.nu`.

* **`inout` and `sink` parameter conventions.** `in` / `inout` /
  `sink` are contextual keywords recognised only as a parameter's
  leading token (no lexer change); `in` is the default.
  A parameter marked **`inout`** is an exclusive mutable borrow: the
  callee mutates the caller's binding in place. `inout T` lowers to a
  by-address `<T>*` parameter — the body reads/writes the caller's
  storage with no local copy — replacing the `*T`-parameter and
  return-the-struct mutation idioms. The argument must be a mutable
  (`: ~`) binding; an `inout` function must be defined before it is
  called. Exclusive-access check: a binding passed `inout` must be
  the only argument path to its value at that call — passing it
  again, as a second `inout` or a plain by-value argument, is a
  `warning:`.
  A parameter marked **`sink`** consumes (takes ownership of) its
  argument: it lowers to an ordinary by-value parameter, and the
  borrow checker records the argument binding as moved so a later
  use is a use-after-move. `sink` v1 applies to `Vec` and other
  manually-managed handles; passing a compiler-auto-dropped value
  (owned string / slice / `Drop` value / struct with owned fields)
  to a `sink` parameter is rejected pending drop-ownership transfer.

* **Static borrow checker, on by default.** A diagnostic analysis
  pass (disable with `--no-borrowck`) that never changes generated
  code — a
  borrow-clean program compiles to byte-identical IR. Closes four
  bug classes with `warning:` diagnostics: use-after-move (a binding
  read after its ownership moved), alias double-free (`: T b a` of an
  owned heap value moves `a`), stack-reference escape (a closure
  capturing a `: ~`-mutable struct by pointer that is returned,
  pushed into a container, spawned onto a thread, or assigned into a
  longer-lived binding — a region-based check), and iterator
  invalidation (mutating a container — `vec_push`/`vec_free`/… — from
  inside a `~`-foreach that iterates it). Ownership + borrow rules
  documented in the new [`docs/MEMORY.md`](docs/MEMORY.md).

* **Tail-call optimisation in the @-fn dispatch path.** `gen_ret`
  now flags the upcoming return-value expression as
  tail-position; `gen_call` snapshots + clears the flag on entry,
  so only the outermost call in the return expression is treated
  as tail (argument-evaluation recursions stay non-tail). In the
  regular @-fn dispatch path the LLVM `call` becomes `tail call`
  when (a) the flag was set, (b) `rlt == fn_ret_ty` so LLVM
  accepts the marker, (c) the callee is not variadic, and (d)
  `gen_ret` saw no pending owned-string / owned-slice / owned-
  struct-field / user-drop / defer in scope at flag-set time
  (any of those would emit drop calls between the tail call and
  `ret`, which LLVM would silently demote).

  Deliberately chose `tail` over `musttail`: `tail` is a hint
  LLVM may drop when its safety analysis can't confirm the
  rewrite (alloca-escape through an arg, etc.), so a
  misclassification only costs an optimisation. `musttail` is
  verifier-enforced and would fail on NURL's owning ABI where
  the same source-level signature lowers to different LLVM
  types across call sites.

  Effect: tail-recursive functions no longer blow the stack —
  `compiler/tests/tco_deep_recursion.nu` runs a 5_000_000-deep
  countdown in O(1) stack (~7 ms wall-clock). Trait/impl,
  closure-loaded var, and fn-pointer-parameter dispatch paths
  intentionally still emit a plain `call` (different shapes; not
  the deep-recursion targets TCO exists for).

  Coexists with `--g` DWARF emission: `tools/dwarf_test.sh` still
  passes all five phases.

* **DWARF Phase 6 composite-type rendering.** User structs and
  generic-instantiation handles (`%Vec__u8`, `%String`, `%FmtTok`,
  user `% Point`, …) now resolve under `nurlc --g` to a
  `!DICompositeType(tag: DW_TAG_structure_type, …)` carrying one
  `!DIDerivedType(tag: DW_TAG_member, …)` per field — instead of
  the previous i64 placeholder. `gdb ptype Point` lists the fields
  with their NURL names + base types; `print p` renders the value
  as `{x = 3, y = 7}`; `print p.x` evaluates a single field.

  Field roster lives in the existing symbol table next to the
  per-field `__idx_N__type` entries — `gen_struct_decl` and the
  generic-instantiation emitter now also record
  `<sname>__field_count` and `<sname>__idx_N__name`. New helpers
  `dbg_size_bits` / `dbg_align_bits` / `dbg_align_up` compute
  LLVM-natural cumulative field offsets so the emitted
  `!DIDerivedType` member offsets match the actual layout
  clang/LLVM uses. Self-referential structs (a cell holding a
  pointer to itself, etc.) are safe — the composite id is interned
  in `g_dbg_type_syms` before the per-field recursion descends
  through `dbg_type_id_for`, so a back-edge returns the cached id
  instead of looping.

  Regression: `compiler/tests/dwarf_struct.nu` exercises the
  codegen path in the standard test corpus; `tools/dwarf_test.sh`
  picks up a fifth phase that drives gdb in batch mode to assert
  `ptype` + `print` + field-access over the new test. Bootstrap
  fixed point holds — non-debug IR is byte-identical.

  Per-instantiation source-line precision for generics remains
  deferred.

## [0.7.2] — 2026-05-19

### Added

* **Serde-style `JsonSerialize` trait + decoder helpers
  (`stdlib/ext/serde.nu`).** A NURL trait `JsonSerialize [T] { @ to_json
  T x → Json }` with first-arg dispatch and impls for `i` / `b` /
  `f` / `s` / `String`, paired with per-type `from_json_<T>` helpers
  (`from_json_i` / `_b` / `_f` / `_string` / `_str_borrow`) that
  return `!T ParseErr`. User types add their own `% JsonSerialize
  MyStruct { @ to_json MyStruct x → Json { ... } }` impl and a
  hand-written `mystruct_from_json`. The shape mirrors Serde:
  format-specific traits (JsonSerialize stands alone today; TOML /
  MsgPack get their own trait when those formats land) and a
  Deserialize-by-naming-convention because NURL's first-arg-dispatch
  cannot carry a trait whose receiver is `Json` — every impl would
  collide. Demo: `examples/serde_demo.nu` round-trips a `Point`
  through JSON text. Regression: `compiler/tests/serde_basic.nu`.

* **docs/GOTCHAS.md folded back into the compiler + grammar +
  README — empty stub now.** The historical "gotchas" list existed
  to compensate for compile errors that lacked enough context to
  fix the source. As of v0.7.1+ that gap is closed: every old item
  now surfaces as a `file:line:col:` `error:` / `warning:` with a
  pointing caret + concrete cure inline (see "Source-level compiler
  diagnostics" below for the seven new emit sites + the four shipped
  prior). The residual edges — prefix-arity strictness, `^` not
  being XOR — are grammar properties, not surprises; they live in
  README's Known Limitations → Grammar table next to the existing
  imports / FFI limitations, and grammar.ebnf's `bin_expr` /
  `ret_expr` productions now carry explanatory comments. The
  GOTCHAS.md file is preserved as a redirect stub so external
  links (and the MCP `nurl_read_gotchas` resource) keep working,
  but new code should not add items there — extend the compiler
  diagnostics or the grammar comments instead.

* **Two more compiler diagnostics on top of the prior five.**
  Bare `@-fn` used as a closure value (`error:` at the use site
  with the `\ args → R { ( fn args ) }` wrap), and the
  `? cond bare-then bare-else { … } { … }` shape (`warning:` —
  the n-ary `&`/`|` foot-gun where `&` only consumed 2 of the
  operands and the `{ … }` blocks became side-effect statements).
  Both ride on the same `die`/`warn` infrastructure; verified via
  the `bare '@-fn'` / `?-with-{` smoke programs.

* **Source-level compiler diagnostics for five language gotchas.**
  Previously each surfaced as either silent UB or a cryptic LLVM /
  arity error far from the source. Each now emits a
  `file:line:col` diagnostic with a caret + the concrete cure, and
  is mirrored in `docs/GOTCHAS.md` items 6-10 (the Quick-reference
  table gained an "Auto-diagnosed?" column).
    * `^ ?? value { ... }` with `^`-arms — `error:` augments the
      existing `return expression has no value` message with the
      `: ~ T rc init / ?? { … = rc v } / ^ rc` refactor (item 6).
    * `nurl_str_len` (libc, expects `s`) called on a `%String`,
      and `string_len` (stdlib, expects `%String`) called on a
      raw `i8*` — both `error:` at the call site (item 7).
    * Parameter named `entry` — `error:` at the param parse,
      naming the LLVM `entry:` block-label collision (item 8).
    * `# T { ... }` where T is a registered struct/enum — `error:`
      at the cast site suggesting `@ T { ... }` (item 9).
    * `: ~ *T` mutable pointer bindings — `warning:` at the decl
      pointing at the long-loop miscompile (item 10). Warn rather
      than die because trivial isolated cases work; the advisory
      catches the hoist patterns that crash deterministically
      ~tens of thousands of iterations in.

* **One-command developer install (`./install.sh`).** Bootstraps the
  compiler (skipped if `build/nurlc` already exists), builds
  `nurl-lsp`, symlinks it into `~/.local/bin/nurl-lsp` so VS Code /
  Cursor / Windsurf find it without any settings tweak, packages
  the VS Code extension (`vsce package`) and installs it via the
  editor's CLI when one is on PATH. Idempotent: re-run any time to
  pick up a newer checkout. Flags: `--no-vscode`, `--no-path`,
  `--force`, `--uninstall`, `--help`.

### Changed

* **`tooling/vscode-nurl` bumped 0.3.0 → 0.4.4** (matches the
  `nurl-lsp` server version it pairs with). README rewritten to
  document the actual feature set — go-to-definition (single +
  cross-file via `$ `path`` imports), hover, document outline,
  workspace-wide IDENT completion, `Ctrl-T` symbol search, folding
  ranges, and `nurlfmt`-backed formatting — replacing the stale
  "coming in later iterations" line that misrepresented an
  already-shipped server. New packaged extension:
  `tooling/vscode-nurl/nurl-0.4.4.vsix`.

## [0.7.1] — 2026-05-19

### Changed

* **MCP `protocolVersion` bumped from `2024-11-05` to `2025-11-25`
  (current stable revision)** + centralized + drift-check tooling.
  All seven hardcoded pinnings across `stdlib/ext/mcp.nu`,
  `mcp_registry.nu`, `mcp_client.nu`, `mcp_stdio.nu` now route
  through a single `mcp_protocol_version → s` helper. A companion
  `mcp_protocol_version_legacy → s` returns `2024-11-05` for
  callers that need to explicitly negotiate the older shape
  (server MAY agree to whatever the client requests as long as
  it's a revision the server supports).

  MCP revisions only bump on backwards-incompatible changes per
  the spec's versioning page, so a server advertising the latest
  revision serves earlier clients fine — pinning to an old date
  pushes negotiation the wrong way.

  New helper: `tools/mcp_spec_drift_check.sh` fetches the spec
  site's versioning page, parses the current revision, compares
  to NURL's pinned value, exits 1 on drift with a pointer at the
  changelog URL. Drop-in for CI or a weekly cron.

### Added

* **DWARF debug-info support (compiler + driver).** `nurlc --g
  foo.nu` now emits LLVM `!DICompileUnit` /
  `!DIFile` / per-fn `!DISubprogram` / per-stmt `!DILocation` /
  per-`:`-binding `!DILocalVariable` + `llvm.dbg.declare` metadata.
  `nurl.sh --debug foo.nu` forwards `--g`, drops `-flto` (which
  silently strips DWARF in the current LLVM/gcc-ld pipeline), and
  side-by-side rebuilds `stdlib/runtime_debug.o` with `-g` so the
  link preserves `.debug_info` end-to-end. `gdb` then resolves
  `break fizzbuzz`, `break foo.nu:42`, `print x`, `whatis x` (with
  NURL type names — `i`/`u8`/`b`/`f`/`s`/...), and `backtrace` with
  source file + line for every NURL frame. Closures and generic
  monomorphisations get their own subprograms with mangled names.
  `nurl_panic` now dumps a stack trace via libc's `backtrace_*` API
  before aborting; pipe each frame's offset through `addr2line -e
  <binary>` to recover `.nu:LINE`. End-to-end regression:
  `./tools/dwarf_test.sh` (gracefully skipped if `gdb` is absent).
  Composite-type rendering (`!DICompositeType` for `%Vec` /
  user structs) and per-instantiation source-line precision for
  generics are not currently implemented.

* **Compiler: closure-escape warnings for `vec_push` / `vec_insert` /
  `vec_set` / `thread_spawn`.** Extends the existing 2026-05-15
  `^`-return escape check (`gen_ret` reading `__last_closure_byref__`
  + `<name>__captures_byref`) to four more sites where a closure
  takes ownership across a scope boundary. `gen_call` snapshots
  `__last_ident_name__` per-argument; when the callee's `fname` is
  one of the four AND the argument names a binding tagged
  `__captures_byref = 1`, emits a soft `warning:` line consistent
  with the existing escape diagnostic. By-name only — struct-wrapping
  (`@ Slot { cb }` then push the slot) passes through silently, which
  is acceptable: we catch the obvious one-line foot-gun rather than
  every conceivable indirection. Closes gotcha #8 to the same scope
  as #5. Regression: `compiler/tests/should_warn_closure_escape_vec.nu`
  (positive `thread_spawn` + 2 negative controls).

  `docs/GOTCHAS.md` §5 updated to document the extended coverage;
  the `vec_push [(@ v)]` form remains untested because anonymous
  closure types aren't yet accepted as generic-arg type names — a
  separate `parse_type_paren` extension would unlock it.

* **MCP server framework with closure-based registry.**
  `stdlib/ext/mcp_registry.nu` (~550 LOC) replaces the previous
  "write your own JSON-RPC dispatch loop" workflow with a uniform
  `register-tool-with-handler` API. The Channel[A] generic-propagation
  fix (2026-05-17) unlocked closure-in-Vec storage, which is what
  makes this possible.

  Three first-class entity types:
    - `McpTool { name, description, input_schema, ( @ Json Json ) handler }`
    - `McpPrompt { name, description, arguments_schema, ( @ Json Json ) handler }`
    - `McpResource { uri, name, mime_type, description, ( @ Json ) handler }`

  Surface:
    - `mcp_registry_new name version → McpRegistry`
    - `mcp_registry_add_tool / _add_prompt / _add_resource` —
      register entities with closure handlers.
    - `mcp_registry_dispatch r method ?params → Json` — single entry
      point routing JSON-RPC method names through the per-method
      dispatchers. Covers `initialize`, `tools/list`, `tools/call`,
      `prompts/list`, `prompts/get`, `resources/list`,
      `resources/read`, `ping`. Unknown methods return an
      `{__error__: "method not found"}` envelope.
    - `mcp_registry_envelope r req → ?Json` — transport-agnostic
      single-request adapter. Notifications (no `id`) return None.

  Transports:
    - **stdio server** — `mcp_serve_stdio r → ! v McpServeErr`
      reads JSON-RPC frames off stdin (line-delimited per spec),
      dispatches via the registry, writes responses to stdout. NURL
      is now a complete bidirectional MCP party (server-side stdio
      pairs with the existing client-side stdio from `mcp_stdio.nu`).
    - **HTTP adapter** —
      `mcp_http_dispatch_for_registry r → ( @ ? Json Json )` returns
      a closure that plugs straight into the existing
      `mcp_http_handler` from `stdlib/ext/mcp_http.nu` (batch
      requests + CORS + session-id echo + SSE stub already covered
      there).
    - **Bearer-auth middleware** —
      `mcp_http_with_bearer_auth handler expected_token` decorates
      any HTTP handler with `Authorization: Bearer <token>`
      enforcement. Missing or mismatched → 401 with
      `WWW-Authenticate: Bearer realm="mcp"`.

  Spec out-of-scope for v1 (tracked):
    * `resources/subscribe` + change notifications (needs an SSE
      push channel from a custom accept loop).
    * `completion/complete` (rarely-used spec feature).
    * `sampling/createMessage` (server→client reverse RPC).

  Regression: `compiler/tests/mcp_registry.nu` exercises every
  dispatch path including 2 tool invocations (echo + add(17,25)=42),
  prompt rendering with arguments, resource read, unknown-method
  error envelope, and ping.

* **`json_as_str` / `json_as_int` / `json_as_bool` accessors** in
  `stdlib/ext/json.nu`. Convenience extractors for the leaf-typed
  variants of `Json`, returning the unwrapped value (or empty/zero
  for the wrong variant). `json_as_str` returns a BORROWED view
  into the underlying JStr's String backing buffer — copy via
  `string_from` for longer-lived references.

* **DoS connection caps for the HTTP server.** Two-axis protection
  against connection-exhaustion attacks:
    - `DosLimits { max_concurrent_conns, max_conns_per_ip }` declares
      the caps. `dos_default_limits → DosLimits { 1024 16 }` covers
      the typical single-VM-public-HTTPS shape; CG-NAT'd clients
      (10s of users behind one public IP) stay under 16 in real usage.
    - `server_new_with_dos listener handler limits` constructs an
      HttpServer with a runtime-side `NurlDosState` (mutex-protected
      counter + linear per-IP table, up to 256 distinct active IPs).
    - At accept time, `server_run_once` calls
      `nurl_dos_state_try_acquire`. Over-cap conns are closed
      immediately at the TCP layer (no canned 503 response — cheapest
      possible rejection, keeps the server's per-cap cost low).
    - Per-connection cleanup releases the counter on conn end;
      multi-worker pools (`server_run_pool`) share the same state via
      the shared HttpServer handle.
    - `server_active_conn_count` exposes the live counter for
      `/metrics`-style observability endpoints.

  Runtime additions in `runtime.c` §23: `NurlDosState` struct + four
  public entry points (`nurl_dos_state_new` / `_try_acquire` /
  `_release` / `_free`) + `_active` accessor. Cross-platform mutex
  (`pthread_mutex_t` POSIX, `CRITICAL_SECTION` Win32). Linear scan
  with O(1) last-element-swap eviction on count→0 keeps the IP
  table compact under steady churn.

  Verified live (NURL_NET_TESTS=1):
  `compiler/tests/http_server_dos.nu` opens 4 concurrent TCP conns
  from 127.0.0.1 against a server with `max_per_ip=2`; the first
  two complete the handshake + handler, the last two are rejected
  pre-handshake → 2 accepted + 2 rejected.

* **TLS extras: SNI + live cert reload + mTLS.** Three additions
  that close the critical-path tuotantopuutteet in the TLS stack
  built on top of the existing `tcp_listen_tls` listener — the new
  operations attach to an
  already-created listener and take effect on subsequent handshakes.

    - `tcp_tls_add_sni listener hostname cert_path key_path → !v NetErr`
      Registers a per-virtual-host cert/key against the listener
      using OpenSSL's `SSL_CTX_set_tlsext_servername_callback`.
      Clients that offer no SNI extension OR offer an unknown
      hostname fall through to the default cert (set at listen
      time) — matches RFC 6066 §3 server semantics. Idempotent
      on re-add (replaces the stored pair for an existing host).
      Required for multi-tenant HTTPS where one listener serves
      multiple virtual hosts.

    - `tcp_tls_reload listener ?hostname cert_path key_path → !v NetErr`
      Atomically swaps the listener's default SSL_CTX (empty
      hostname) OR a matching SNI entry's SSL_CTX with one built
      from the new cert/key files. Per-listener mutex serialises
      the swap against the concurrent accept loop; OpenSSL refcounts
      the old SSL_CTX so in-flight conns that already wrapped an
      SSL handle from it stay valid until they close. Natural
      shape for Let's Encrypt cert rotation triggered from SIGHUP
      or a control endpoint.

    - `tcp_tls_require_client_cert listener ca_bundle_path b strict → !v NetErr`
      Sets `SSL_VERIFY_PEER` on the listener; when `strict` is true,
      adds `SSL_VERIFY_FAIL_IF_NO_PEER_CERT` so the handshake fails
      outright for unauthenticated clients (mTLS-mandatory).
      `tcp_peer_cert_subject TcpConn → String` reads the peer's
      X509 DN in OpenSSL one-line format (e.g.
      "/CN=test-client/O=NURL/C=FI") for the application's
      authorisation decisions.

  Verified live (NURL_NET_TESTS=1):
  `compiler/tests/http_server_tls_extras.nu` runs three sections —
  SNI hostname dispatch (api.example.com → CN=api cert,
  www.example.com → CN=www cert, unknown.example.com → fallback to
  CN=localhost default), live reload (CN=localhost → swap →
  CN=reloaded.example.com), and mTLS (no client cert → rejected,
  valid client cert → 200 OK). All probes driven via `openssl
  s_client` shell-outs.

  Runtime additions in `runtime.c` §18: `NurlTcp` grew
  `sni_entries` + `sni_count` + `sni_cap` + a per-listener
  cross-platform mutex (`pthread_mutex_t` on POSIX,
  `CRITICAL_SECTION` on Windows). Four new C entry points
  (`nurl_tcp_tls_add_sni`, `nurl_tcp_tls_reload`,
  `nurl_tcp_tls_require_client_cert`, `nurl_tcp_peer_cert_subject`).
  `tcp_close` extended to free the SNI registry + destroy the
  mutex; in-flight SSL_CTX refs are released via SSL_CTX_free's
  refcount decrement, so cleanup is safe under concurrent shutdown.

## [0.7.0] — 2026-05-18

Full HTTP/2 server stack (RFC 9113 + RFC 7541) alongside WebSocket
(RFC 6455), gzip wire format (RFC 1952), and an AddressSanitizer +
UndefinedBehaviorSanitizer quality gate.
Three compiler fixes (single-pointer-handle Result coercion, `?u`
match-arm unsigned propagation, `gen_assign` last-type publishing) +
one new language feature (integer-literal match arms) round out the
release. Bootstrap fixed point holds; 0 SAN_FAIL across the 208-test
sanitized corpus.

### Added

* **HTTP/2 server-side (RFC 9113 + RFC 7541).** Four pure-NURL modules
  plus one runtime extension for ALPN. Same `( @ HttpResponse HttpRequest )`
  handler contract as HTTP/1.1 — application code unchanged.

  Modules:
    - `stdlib/ext/http2_frame.nu` (~360 LOC) — binary framing: 9-byte
      header + all 10 frame types + connection preface validation +
      pure round-trip helpers + socket I/O + one-shot senders for
      SETTINGS / PING / GOAWAY / WINDOW_UPDATE / RST_STREAM.
    - `stdlib/ext/http2_hpack.nu` (~900 LOC) — RFC 7541 header
      compression: 61-entry static table + dynamic table with FIFO +
      size-based eviction + N-bit prefix integer codec + string codec
      (literal or Huffman) + all 6 header-field representations +
      complete Huffman decoder covering all 257 Appendix B codes
      across 21 length buckets (5..30 bits).
    - `stdlib/ext/http2_conn.nu` (~770 LOC) — connection + stream
      state machine: SETTINGS exchange + apply, stream state diagram
      per RFC 9113 §5.1 (idle → open → half-closed → closed),
      HEADERS+CONTINUATION assembly with §6.10 interleaving check,
      DATA flow control with connection-level WINDOW_UPDATE
      replenishment, PING/GOAWAY/RST_STREAM dispatch, request
      assembly from HTTP/2 pseudo-headers (:method/:path/:scheme/:authority)
      to the existing HttpRequest shape, response emission with §8.2.2
      hop-by-hop header stripping.
    - `stdlib/ext/http2_server.nu` (~100 LOC) — `http2_serve` +
      `server_run_h2_capable`. The latter accepts a connection,
      checks ALPN selection via `tcp_alpn_protocol`, and routes to
      h2 OR the existing HTTP/1.1 keep-alive loop transparently.

  Runtime extension:
    - `nurl_tcp_listen_tls_alpn(host, port, backlog, cert, key,
      "h2 http/1.1")` — wraps `SSL_CTX_set_alpn_select_cb` over the
      existing TLS listener. Wire-format packing of the server's
      preference list happens C-side. NurlTcp handle gained
      `alpn_wire` + `alpn_wire_len` fields.
    - `nurl_tcp_alpn_selected(handle)` — reads
      `SSL_get0_alpn_selected` post-handshake, returns heap-owned
      NUL-terminated string ("h2" / "http/1.1" / "").
    - NURL surface: `tcp_listen_tls_with_alpn` + `tcp_alpn_protocol`
      in `std/net.nu`.

  v1 scope intentionally excludes:
    * Client-side h2 (symmetric to server; ship when a consumer asks).
    * h2c (HTTP/1.1 → h2 cleartext upgrade — TLS+ALPN is the
      universal modern shape).
    * PUSH_PROMISE / server push (deprecated by RFC 9113 §8.4).
    * PRIORITY frames (obsoleted by RFC 9218 — default ordering OK).

  Verified offline against RFC 9113 §4 framing vectors and
  RFC 7541 Appendix C / C.4.1 HPACK + Huffman vectors via
  `compiler/tests/http2_basic.nu`. Bootstrap fixed point holds.
  ASan + UBSan: 0 SAN_FAIL across the 208-test corpus.

  Usage:
  ```
  : !TcpListener NetErr ll
    ( tcp_listen_tls_with_alpn `127.0.0.1` 8443 16
                               `cert.pem` `key.pem`
                               `h2 http/1.1` )
  ?? ll {
      T listener → {
          : HttpServer s ( server_new listener my_handler )
          ( server_run_h2_capable s )
      }
      ...
  }
  ```

* **Compiler: integer-literal match arms.** `?? value { 1 → ... 42 → ... -1 → ... _ → ... }`
  is now valid wherever `value` has an integer LLVM type (i / i8/16/32/64,
  u/u16/u32/u64). Each arm emits a single `icmp eq <match_type>` and
  branches; the wildcard `_` arm catches the residual (required —
  exhaustiveness is not statically checked across the full integer
  domain). Skips the enum-variant lookup, payload-binding, and
  duplicate-arm tracking paths that named-variant arms exercise.
  `stdlib/ext/http2_hpack.nu`'s 280+ line `? == x N { ^ Y } {}`
  cascade for the HPACK static table + Huffman per-length lookup
  tables was rewritten on top of this and is significantly more
  readable. Regression: `compiler/tests/match_int_literal.nu`.

* **AddressSanitizer + UndefinedBehaviorSanitizer quality gate.** Two
  manual entry points:
    - `./build.sh --san` rebuilds the runtime + every bootstrap stage
      with `-fsanitize=address,undefined -fsanitize-address-use-after-scope
      -fno-omit-frame-pointer -fno-sanitize-recover=all`. LTO is
      dropped because clang's LTO+sanitizer combo produces opaque
      link-time errors on NURL's cross-module function pointers (the
      runtime/user-code inline win isn't the point of a san run).
      LeakSanitizer is disabled during the bootstrap itself
      (`ASAN_OPTIONS=detect_leaks=0`) because nurlc_py/nurlc_self
      intentionally don't free their process-lifetime str-pool /
      sym-arena globals at exit.
    - `compiler/tests/run_san_tests.sh` runs the full .nu corpus
      under the sanitized runtime, captures stdout / stderr per-test
      separately, scans stderr for ASan/UBSan/LeakSanitizer markers,
      and reports `PASS` / `SAN_FAIL` / `COMPILE_FAIL` / `LINK_FAIL`.
      Non-zero exit codes without sanitizer markers count as PASS
      (several tests in the corpus deliberately return computed values
      as exit codes — `native_sum` returns 55, `test_immutable_assign_error`
      aborts to prove the runtime check fires, etc.). Skips
      `should_fail_*` compile-negatives and helper modules without
      `main()`. Leak detection is opt-in via `LSAN_DETECT_LEAKS=1`.

  First sweep result: 188 PASS, 0 SAN_FAIL across 206 tests. The
  infrastructure stays manual — invoke when validating a release
  candidate or triaging a memory-shape bug, not on every build.

* **WebSocket server-side (RFC 6455).** `stdlib/ext/websocket.nu`
  (~570 LOC pure NURL). Composes on the HTTP/1.1 stack: client sends
  `Upgrade: websocket` + `Sec-WebSocket-Key` + `Sec-WebSocket-Version: 13`,
  server validates via `ws_perform_handshake[_with]` and writes the
  `101 Switching Protocols` response, both sides switch to the binary
  frame protocol over the SAME `TcpConn`. TLS works transparently —
  `wss://` routes through `tcp_listen_tls` + the polymorphic `TcpConn`
  SSL dispatch with zero additional code in this module.

  **Surface:**
    - Handshake: `ws_is_upgrade`, `ws_accept_key`,
      `ws_handshake_response_for`, `ws_perform_handshake[_with]`
      (`_with` accepts an optional subprotocol echo).
    - Low-level frame I/O: `ws_serialize_frame` (pure, testable builder),
      `ws_read_frame`, `ws_write_frame`.
    - Convenience writers (server-side, never masked per RFC §5.1):
      `ws_send_text`, `ws_send_binary`, `ws_send_ping`, `ws_send_pong`,
      `ws_send_close i code s reason`.
    - Message reader: `ws_read_message` assembles continuation frames
      per RFC §5.4, auto-pongs incoming pings, surfaces peer close as
      `WsClosedByPeer`. Text payloads validated UTF-8 before return.
    - Serve loop: `ws_serve_messages` reads messages, dispatches to a
      `( @ ! v WsErr WsMessage )` handler, performs the full close
      handshake on exit (mapping errors to RFC §7.4 close codes:
      `WsInvalidUtf8 → 1007`, `WsProtocol*  → 1002`, `WsMessageTooLarge → 1009`,
      everything else `→ 1011`).
    - `WsLimits { max_frame_bytes, max_message_bytes, read_timeout_ms,
      fragment_max_count }`; defaults are 16 MiB / 64 MiB / 60 s / 128.
    - `ws_validate_utf8` (RFC 3629 strict) is exposed publicly — useful
      outside the WebSocket context too.

  **Validation rigour:** RSV1–3 bits must be 0 → `WsProtocolReservedBit`;
  opcode must be in {0,1,2,8,9,10} → `WsProtocolBadOpcode`; control frames
  MUST have FIN=1 (`WsProtocolControlFragmented`) and payload ≤125 B
  (`WsProtocolControlTooLarge`); client→server frames MUST be masked
  (`WsProtocolUnmasked`); text payloads MUST be valid UTF-8 — overlongs,
  UTF-16 surrogates (U+D800-U+DFFF), and codepoints above U+10FFFF all
  rejected; close codes constrained to 1000–4999; the fragment-count
  cap defends against a ping-flood interleaved with continuation frames.

  **Verified against RFC 6455 vectors:**
    - §1.3 accept-key worked example
      (`dGhlIHNhbXBsZSBub25jZQ==` → `s3pPLMBiTxaQ9kYGzzhZRbK+xOo=`).
    - §5.7 unmasked text frame `"Hello"` round-trips to
      `81 05 48 65 6c 6c 6f`.
    - Length-encoding transitions: 126-byte payload triggers the 16-bit
      extended-length header; 65536-byte triggers the 64-bit form
      (with the spec-required MSB-clear check on the top byte).

  Regression: `compiler/tests/websocket_basic.nu` (6 sections, 30
  assertions). v1 scope is server-side only — a symmetric client-side
  API is tracked for follow-on work if a real consumer asks. No
  `permessage-deflate` extension; subprotocol header echo is the only
  negotiation surface.

* **SHA-1 in runtime §17** (RFC 3174 self-contained, ~80 LOC). Added to
  enable the WebSocket handshake's `Sec-WebSocket-Accept` derivation;
  exposed via new `sha1_bytes` (length-aware, binary-safe → 20 raw
  bytes) and `sha1_hex` (→ 40-char lowercase) in `stdlib/std/hash.nu`.
  SHA-1 is documented as protocol-compatibility-only — not recommended
  for new security-sensitive code; use `sha256_hex` for that.

* **`stdlib/ext/http_full.nu`** now imports `ext/websocket.nu` so one
  `$`-include brings the full HTTP stack including WebSockets in scope.

### Fixed

* **`signal_basic.nu` — F-arm pattern no longer binds the undef
  Option payload.** The previous `F e → { ( string_free e ) ... }`
  shape passed the F-tag's undef String handle to `string_free`,
  which deep-dispatched into `nurl_peek(NULL, 0)` and tripped UBSan's
  "applying zero offset to null pointer". Replaced with bare `F → ...`
  (Option's None arm carries no data). Surfaced by the first sanitized
  run of the corpus and was a silent crash even outside of ASan
  (`EXIT 139` / `dumped core` in the baseline — now `EXIT 0` cleanly).

* **`stdlib/runtime.c` `nurl_peek` / `nurl_poke` defensively handle
  NULL base.** `nurl_peek` returns 0 instead of dereferencing;
  `nurl_poke` silently no-ops. Safety net for the same caller-side
  mistake the `signal_basic` fix patched at source — a future stdlib
  binding that hands an Option-F-arm payload to a vec-style API will
  log a soft warning under ASan/UBSan but not crash the process.

* **Compiler: `?u → T b →` match-arm now propagates the unsigned flag
  to the payload binding.** `parse_type_opt` stashes the inner-T NURL
  token in `__last_opt_nurl_t__`; `gen_let_or_struct` copies it to
  `<name>__opt_nurl_T`; `gen_match`'s T-arm payload binding tags
  `<pv0>__unsigned = 1` when the inner T is `u` / `u16` / `u32` / `u64`.
  Without this fix the alloca dropped the unsigned-ness and a
  downstream `# i b` cast in the arm body emitted `sext` instead of
  `zext` for high-bit-set bytes, surfacing as wrong hex nibbles in
  `bytes_to_hex` over SHA-1 / SHA-256 digests. `bytes_to_hex` reverted
  from its temporary direct-pointer workaround back to the natural
  `vec_get [u]` + match-arm path.

* **Compiler: `! (Vec u) E` Ok-arm now coerces the i64 payload to the
  `{ ptr }`-shaped single-handle struct.** Two-part fix:
  `parse_type_res` stashes `__last_res_t_llvm__` (LLVM type of T) so
  `gen_let_or_struct` can store `<name>__res_t_llvm` for paren-compound
  T like `( Vec u )` whose NURL-source name is just `(`;
  `gen_match`'s reconstruction path uses it as a fallback after the
  NURL-name lookup fails. Additionally, `coerce_store_val` gained an
  `i64 → single-pointer-handle-struct` case (one-field struct whose
  field 0 is a pointer — covers `Vec[A]`, `String`, `Channel[A]`,
  `Thread`, `Arena`) that wraps via `inttoptr` + `insertvalue` at
  field 0. Without these, `?? r { T pb → @ Frame { … pb } }` over
  `! ( Vec u ) E` generated invalid IR (`insertvalue %Frame, i64`)
  forcing callers into `vec_with_cap + vec_extend` copy workarounds.
  `ws_read_frame` reverted from the copy workaround back to the
  direct payload pass-through.

* **Compiler: `gen_assign` now publishes the LHS type via
  `nurl_set_last_type`.** Without this, an `=`-assignment as the last
  expression of a match arm (`F e → { = err e }`) reported the
  RHS-expression's pre-coerce type to the surrounding `gen_match`,
  causing the phi to be typed for the RHS while the actual stored
  register held the coerced LHS type. LLVM verifier rejected the
  mismatch. Surfaced in `ws_read_frame`'s `?? hdr_r { T … F e → { = err e } }`
  which previously needed a trailing `( nurl_print `` )` to push the
  arm's last-expression type back to void; that workaround removed.

* **Gzip wire format (RFC 1952).** `stdlib/ext/compress.nu` gains
  `gzip_compress` / `gzip_compress_at level` / `gzip_decompress` —
  byte-identical interop with the `gzip` / `gunzip` CLI tools and HTTP
  `Content-Encoding: gzip`. Magic + 10-byte header, raw deflate body,
  CRC-32 + ISIZE trailer, all per RFC 1952. Decompress auto-detects
  gzip OR zlib wire format on the input side (libz's
  `inflateInit2_(windowBits=15+32)`), so a single helper handles both
  shapes coming back from heterogeneous peers. Decompress also reads
  the ISIZE trailer to pre-size the output buffer, avoiding the
  grow-and-retry loop on the common path (sub-4 GB inputs).
  Errors map to the existing `CompressErr` enum
  (`CompressData` / `CompressMemory` / `CompressBufTooSmall` /
  `CompressOther`). Empty input passes through to an empty `Vec[u]`
  with no magic-byte production, matching the zlib/zstd shape.
  Regression: `compiler/tests/compress_gzip.nu` (round-trip + magic
  bytes 0x1f 0x8b 0x08 + level-0 store-only + empty + auto-detect
  zlib + garbage rejection).

* **`runtime.c` §22 — gzip bridge.** `nurl_gzip_compress` /
  `nurl_gzip_decompress` wrap libz's streaming
  `deflateInit2_(windowBits=15+16)` / `inflateInit2_(windowBits=15+32)`
  + `deflate(Z_FINISH)` / `inflate(Z_FINISH)` + matching `End`. ABI
  mirrors `compress2` / `uncompress` (in/out `dst_len`, return 0 on
  success or libz error code on failure; sentinel `-98` when the build
  lacked zlib). The C-side bridge stays because `z_stream`'s sizeof
  and field layout are platform-specific (88 B on Win64 LLP64, 112 B
  on Linux/macOS x64 LP64), and `deflateInit2_` checks an exact-sizeof
  match — mirroring the struct from NURL would be brittle across
  toolchains. Same architectural pattern as the sqlite3 borrowed-view
  bridge: thin, ABI-faithful, no state caching beyond what libz needs.

### Changed

* **`stdlib/ext/compress.nu` header comment** updated: the
  zlib-vs-gzip wire-format gap section now documents the gzip helpers
  shipped alongside, with a pointer to `runtime.c` §22 for the bridge
  rationale.

* **`build.sh`** zlib detection now sets
  `ZLIB_CFLAGS="-DNURL_HAVE_ZLIB ..."` and threads it into the runtime
  compile step so the §22 bridge compiles in when zlib1g-dev is
  present. Without zlib, `nurl_gzip_*` short-circuit to the
  `NURL_GZIP_ERR_UNSUPPORTED` sentinel which the NURL surface maps to
  `CompressOther` — graceful runtime degradation rather than a link
  error.

### Fixed

* **Stale "Quoted CSV Support" roadmap entry closed.** `stdlib/ext/csv.nu`
  has implemented RFC 4180 quoting via the `CSVDialect { delimiter,
  crlf, quote_char }` struct (and the matching `CSVTable` arena's
  `escape_buf`) since the v2 arena rewrite. The roadmap line was a
  leftover from the pre-arena CSV prototype; surfaced and removed
  during the critic-cleanup sweep.

## [0.6.1] - 2026-05-17

### Added

* **Generic propagation through nested structs.** Two generic structs
  side-by-side compose freely: a generic function that returns
  `( Outer A )` while internally allocating `*( Inner A )` and writing
  its fields now compiles, and a generic struct whose field types
  reference another generic (e.g. `Wrap[A] { ( Vec A ) items, … }`)
  emits its inner instantiation before the outer typedef. Fix is in
  `compiler/nurlc.nu` — `emit_one_instantiation` re-scans the
  substituted generic-function body so concrete inner refs trigger
  `ensure_struct_instantiated`, and `ensure_struct_instantiated`
  itself re-scans the substituted generic-struct body for the same
  reason. Bootstrap fixed point holds (stage1 ≡ stage2 byte-identical
  IR at 1 187 843 B). Regression: `compiler/tests/generic_nested_struct.nu`
  (Inner/Outer + Wrap/Vec, both `[i]` and `[s]` instantiations).

* **`Channel[A]` — generic over the element type.** `stdlib/std/channel.nu`
  rewritten on top of the nested-generic fix. `Channel[A] { s ctl }`
  wraps `ChannelImpl[A] { Mutex m, Cond c, ( Vec A ) q, i closed }`;
  every call site supplies the element type via `[A]`
  (`chan_new [i]`, `chan_send [s] ch "hello"`, `chan_recv [i] ch → ?i`,
  etc.). Closes the long-standing v0.3.0 roadmap item that previously
  forced i64-only channels with `# i ptr` for handle payloads.
  `compiler/tests/channel_basic.nu` migrated to the new API (still
  exercises `[i]` so behaviour-equivalent); the regression test above
  exercises both `[i]` and `[s]`. Naming: uses `[A]` (the existing
  stdlib tparam convention) — `T` is the boolean true literal in NURL
  so cannot be a tparam name.

* **Bytes endianness primitives.** `stdlib/std/bytes.nu` gained six
  read helpers and six write helpers covering u16 / u32 / u64 in
  both big-endian (network) and little-endian byte orders:
  `bytes_read_uN_be/_le → ?T` (None when offset is negative or runs
  off the end of the buffer), and `bytes_push_uN_be/_le → v` for the
  symmetric appends. Unblocks binary protocol work (gzip CRC-32 +
  ISIZE trailers, MessagePack header bytes, BSON length prefixes,
  raw network packet headers). Regression:
  `compiler/tests/bytes_endian.nu` (round-trip + boundary values +
  byte-layout sanity + OOB + negative-offset rejection).

### Fixed

* **Nested `??` on a bare-enum value from an `F` arm of `! T E` now
  compiles.** `gen_match` was always emitting `extractvalue` to recover
  the discriminant tag, even when the matched value was already a bare
  scalar (e.g. an `IoErr` bound by `?? r { F e → ?? e { … } }`, where
  `e` is just i64). The pre-existing i1 short-circuit is generalised
  to cover both `i1` AND `i64` match types — `extractvalue` is only
  emitted on aggregate types now. Closes gotcha #6. Regression:
  `compiler/tests/nested_match_enum.nu` (direct `??` on Color, nested
  `??` per-variant on DbErr-from-`! i DbErr`, plus the wildcard arm).

* **Param name shadowing struct field name no longer miscompiles.**
  `gen_field_store`'s struct-pointer branch now routes `= . obj field
  val` to the field-store path when the IDENT after `.` is a
  function parameter AND a registered field of the destination
  struct. Pre-fix the int-width check ran first and treated the
  param as an array index, emitting `getelementptr %S, %S* %obj, i64
  %field` (value-as-index, no field offset). Local non-param int
  variables that coincide with field names — like vec.nu's
  `len`/`idx`/`i` array-store kernels — still route through the
  array path. Closes gotcha #10. Regression:
  `compiler/tests/param_field_shadow.nu` (Box param-shadow positive +
  Pt array-store negative control).

* **`i64` recognised as a type keyword.** The C and Python lexers'
  multi-char TYPE_KW whitelists already covered
  `i8`/`i16`/`i32`/`u16`/`u32`/`u64`/`f32` but not `i64`, so any
  source line writing `: i64 name …` silently took the inferred-type
  branch (`i64` as the binding name, the rest as the value) and
  produced IR with undefined SSA names. `llvm_type` was missing the
  `i64 → i64` row symmetrically — even after the lexer fix, the chain
  fell through to the `%i64` named-type fallback and LLVM rejected the
  resulting `alloca %i64` as unsized. Both ends fixed; closes gotcha
  #7. Regression: `compiler/tests/sized_int_binding.nu` covers
  literal + FFI-call RHS for every sized integer width.

* **Sign-extension when loading bytes from `*u` pointers.**
  `gen_member` now snapshots `__last_unsigned__` before parsing the
  index expression and restores it after the load, so a subsequent
  `# i ( . p k )` cast emits `zext i8 → i64` instead of `sext`. Prior
  to this, a byte with the high bit set (`0x89`, `0xFF`, …) would
  sign-extend to `0xFFFFFFFFFFFFFF89` and silently corrupt
  shift-and-add accumulators in the byte-decoding code that triggered
  the discovery. Covers both the literal-index and variable-index
  load paths; struct-field loads not affected.

### Changed

* **`Channel` is no longer a type alias for the i64 channel.** All
  callers must specify the element type at use site. The single
  in-tree caller (`compiler/tests/channel_basic.nu`) was updated.

## [0.6.0] — 2026-05-16

CSV stdlib consolidates around the arena layout, runtime link-time
optimization lands across the toolchain, and a couple of long-running
infrastructure papercuts get resolved.

### Added

* **`build.sh --no-tests` flag.** Bootstraps the compiler (with the
  byte-identical-IR fixed-point gate still enforced) and exits before
  the test suite. Replaces the older `verbosebuild.sh` script that
  Docker images relied on. `api/Dockerfile` and `nurlapi/Dockerfile`
  both updated to `./build.sh --no-tests`.

* **`nurl.sh` link line — full runtime-feature parity.** The user-
  facing wrapper now auto-links `-lssl -lcrypto` (when
  `stdlib/runtime.openssl` sentinel present), `-lsqlite3`
  (`stdlib/runtime.sqlite3`), and `-lpq` (`stdlib/runtime.pq`) in
  addition to the existing `-lcurl` auto-detection. Mirrors the
  central `build.sh` link line; closes the v0.4.3 follow-up to
  centralise the link-flag set across multiple build scripts.

### Changed

* **Runtime LTO** — `stdlib/runtime.o` is now compiled with `-O2
  -flto`, and every clang invocation that consumes it (`build.sh`,
  `nurl.sh`, `compiler/tests/run_tests.sh`,
  `tools/{nurlfmt,nurl-lsp,nurlpkg}/build.sh`) carries the matching
  `-flto` flag. The LTO link pipeline inlines Vec / String / IO FFI
  calls (`vec_push`, `vec_data`, `vec_reserve`, `nurl_peek/poke`,
  `nurl_parse_int_range`, `cmp_int`, …) across the runtime ↔ user-
  code boundary. Measured on the 1 M-row × 8-col CSV bench (Linux
  i7-5930K, 5 runs median):

  | Stage  | no LTO | LTO    | Δ       |
  |--------|-------:|-------:|--------:|
  | load   | 315 ms | 272 ms | **-14 %** |
  | filter | 146 ms | 139 ms |  -5 %   |
  | sort   |  65 ms |  40 ms | **-38 %** |
  | total  | 529 ms | 451 ms | **-15 %** |

  Sort wins the most because the indexed-permutation comparator was
  bottlenecked on un-inlinable `nurl_parse_int_range` / `cmp_int` /
  `vec_data`. Native binary size dropped 172 888 → 25 408 B (-85 %)
  as LTO drops unused runtime symbols. Bootstrap fixed-point IR
  unchanged (LTO runs at link time only — `nurlc`'s LLVM IR
  generation is invariant) — stage1 ≡ stage2 still at 1 185 386 B.

* **`stdlib/ext/csv.nu` API consolidation.** The legacy v1
  `CSVTable` / `CSVRow` per-cell-malloc layout is gone. The arena-
  backed `CSVTableA` is now THE `CSVTable` — every `csv_table_*`
  call reaches the (offset, length) arena parser directly, and
  RFC 4180 quoting is the default for every load/write. New
  accessor surface:

  - `csv_table_view t row col → s` — zero-copy borrowed pointer
    into the content / escape buffer. NOT NUL-terminated; pair with
    `csv_table_view_len`.
  - `csv_table_view_by_name`, `csv_table_view_len`.
  - `csv_table_get t row col → ?String` — owned-String fallback for
    callers that want an independent lifetime.
  - `csv_table_get_by_name`.

  All sort / filter / truncate / find / select_cols paths wired
  through the arena. Predicate signature for `csv_table_filter` is
  now `( @ b *CSVTable i ) → b` (table + row index) instead of the
  old CSVRow-based shape — match the closure-cached-pointer pattern
  used by `compare/nurl_analysis.nu`. `csv_table_a_*` functions and
  `CSVTableA` deleted outright (no deprecation cycle — NURL is not
  yet in wide enough use). Removed files:
  `stdlib/ext/csv_hoist_test.nu`, `compare/nurl_analysis_arena.nu`,
  `compiler/tests/csv_sort_indexed.nu`, `compare/csv_demo.nu`
  (latter two were duplicates of `csv_arena` / `examples/csv_demo.nu`).
  Callers updated: `examples/csv_demo.nu`, `compare/nurl_analysis.nu`,
  `compare/test_quoting.nu`, `compiler/tests/{csv_arena,
  repro_csv_table_quotes}.nu`. CSV bench at 451 ms (post-LTO) vs
  Polars 95 ms (~4.7×). RFC 4180 quoting verified across read +
  write round-trips.

* **Test framework: skip helper modules.** `compiler/tests/run_tests.sh`
  now skips files matching `*_mod.nu`, `*_helper.nu`, `*_lib.nu` —
  they are imported by other tests and have no `main` function, so
  the old framework recorded them as `COMPILE OK / LINK FAIL` in
  the baseline. Five stale entries removed from `correct.txt`:
  `alias_rewrite_types_mod`, `should_fail_alias_import_mod`,
  `should_fail_group_d_lib`, `should_fail_pub_helper`,
  `should_fail_pub_type_helper`.

### Removed

* **`verbosebuild.sh`** — duplicated `build.sh`'s logic without
  test execution. Folded into `build.sh --no-tests`.

* **`CSVTableA` + every `csv_table_a_*` function** in
  `stdlib/ext/csv.nu` (see "API consolidation" above).

* **`stdlib/ext/csv_hoist_test.nu`** — stranded Phase 2c hoist
  experiment, never imported by any caller.

## [0.5.0] — 2026-05-16

The package manager lands. `nurlpkg` is a Cargo-shaped CLI that
covers the full dependency lifecycle: scaffold a manifest, declare
dependencies, resolve them transitively, lock the resolution, and
verify the lockfile hasn't drifted. This release also ships the
TOML and Manifest stdlib modules that back the package manager,
plus a new `fs_symlink` primitive in `stdlib/std/fs.nu`.

### Added

* **`tools/nurlpkg/` — NURL package manager.** Single-binary CLI
  with ten subcommands:

  - `nurlpkg init <name>` — write a `nurl.toml` skeleton (refuses
    to overwrite an existing one).
  - `nurlpkg info` — pretty-print the typed manifest fields.
  - `nurlpkg deps` — list each `[dependencies]` entry, one per
    tab-separated line (pipe-friendly).
  - `nurlpkg add <name> [--path P] [--version V]` — append a
    dependency to `[dependencies]` via surgical text edit
    (preserves user comments and formatting; refuses duplicates).
  - `nurlpkg remove <name>` — delete a dependency entry the same
    way (errors if the name isn't declared).
  - `nurlpkg install` — BFS-resolve every path-based dependency
    transitively, create `deps/<name>` symlinks via libc's
    `symlink(2)`, regenerate `nurl.lock` as a side effect.
    Idempotent: rerunning on a fully-installed tree returns 0
    silently. Diamond dependencies dedupe.
  - `nurlpkg lock` — regenerate `nurl.lock` from the on-disk
    `deps/` tree without reinstalling.
  - `nurlpkg verify` — compare `deps/` against `nurl.lock` and
    exit 1 on any drift (missing entries OR unexpected entries).
    Intended for CI / pre-build gates.
  - `nurlpkg version` / `--version` — print the nurlpkg version.
  - `nurlpkg help` — usage.

* **`stdlib/ext/toml.nu` — TOML parser.** Recursive-descent parser
  producing a `TomlValue` tagged-union tree (`TStr` / `TInt` /
  `TBool` / `TArr` / `TTable`). Handles both `[section]` headers
  and `[[array.of.tables]]`, inline tables, dotted keys, and
  comments. Used internally by the package manager but also
  available to any stdlib consumer.

* **`stdlib/ext/manifest.nu` — typed manifest view.** Pulls the
  well-known `[package]` and `[dependencies]` fields out of a
  TomlValue tree into a typed `Manifest { name, version,
  description, license, Vec[Dep] dependencies }`. Single-table
  inline-table dep form and bare-string version form both
  supported. Returns `! Manifest ManifestErr` with a small set of
  named error variants (ReadFailed / ParseFailed / MissingName /
  MissingVersion / BadShape).

* **`fs_symlink s target s linkpath → !v IoErr` (stdlib/std/fs.nu).**
  Thin wrapper over libc's `symlink(2)` exposed via pure-NURL FFI
  (`& \`c\` @ symlink → i32`). POSIX-only; Windows callers should
  fall back to copying since `CreateSymbolicLinkW` needs a
  privilege most accounts lack.

* **Regression tests.** `compiler/tests/toml_basic.nu` covers the
  parser; `compiler/tests/manifest_basic.nu` covers the typed
  manifest extraction (well-formed + missing-required-field
  cases).

### Compiler quirks documented (workarounds in place)

Two codegen issues surfaced while writing the package manager and
remain as quirks until separately addressed:

* **Nested `??` on an enum value extracted from `! T E`** emits
  `extractvalue` on an `i64`, which is invalid LLVM. Workaround:
  flatten with `?` + `==`, or restructure to avoid needing the
  inner match (`__cmd_install` checks `file_exists` before
  `dir_create` to skip the `AlreadyExists` arm entirely).

* **Width-suffixed FFI return bindings** (`: i64 n ( ffi_call … )`)
  emit `store i64 %n, …` before the call defines `%n`, producing
  "use of undefined value." Workaround: bind FFI integer returns
  to `: i n (…)` (the default 64-bit type).

## [0.4.4] — 2026-05-16

LSP server gains the last three "quick win" features and the
Language Server protocol surface is now feature-complete enough
for daily editor use without falling back to other tooling.

### Added

* **`textDocument/formatting`** — pipes the active buffer through
  `build/nurlfmt --stdin` and returns a single TextEdit covering
  the entire document. `Shift+Alt+F` in VS Code triggers it. Uses
  `process_run`'s stdin_str parameter — no temp file needed.

* **`workspace/symbol`** — fuzzy-search across every indexed
  top-level symbol (functions, struct/enum types, enum variants,
  global constants, FFI symbols). Case-insensitive substring
  match, empty query returns the full set. `Ctrl+T` / `Cmd+T` in
  VS Code. Reuses the `g_all_names :list` TSV index built by the
  decl scanner.

* **`textDocument/foldingRange`** — emits FoldingRange for every
  multi-line `{ … }` block. Backtick strings and `//` comments are
  skipped so braces inside them don't confuse the matcher.
  Single-line blocks (e.g. `{ ^ 0 }`) are filtered out. Nested
  blocks each get their own range so the editor can fold any
  level independently.

## [0.4.3] — 2026-05-16

Tier D ecosystem advances on two axes: a working **Language Server**
(`nurl-lsp`) with the five most-used IDE features wired end-to-end,
and a small but generally-useful binary-stdin primitive in core/io.

### Added

* **NURL Language Server (`tools/nurl-lsp/`).** Stdio JSON-RPC server
  written in NURL itself, wired to VS Code / Windsurf through the
  refreshed `tooling/vscode-nurl` extension (v0.3.0). Features:
  - Live compile-driven **diagnostics** on `didOpen` / `didChange`
    (errors + warnings stream from `nurlc` stderr into LSP
    `publishDiagnostics`).
  - **Go-to-definition** across files. Transitive `$`-import index
    populated per workspace; jump works for `@`-functions,
    struct/enum types, enum variants, global `:` constants, and
    `& \`lib\`` FFI symbols.
  - **Document outline** (`textDocument/documentSymbol`) with the
    right `SymbolKind` per decl shape — visible in VS Code's
    Outline panel and via `Ctrl+Shift+O`.
  - **Hover** popups (`textDocument/hover`) showing the symbol's
    kind label, signature line (Markdown-formatted code block),
    and source location.
  - **Completion** (`textDocument/completion`) filtered by the
    IDENT-prefix immediately left of the cursor. `CompletionItemKind`
    mapping covers the same five decl shapes.

  Build: `./tools/nurl-lsp/build.sh` produces `build/nurl-lsp`.

* **`stdlib/core/io.nu read_n_bytes i n → ( Vec u )`.** Owned-Vec
  binary stdin reader. Used by the LSP server's `Content-Length`
  framing; useful for any framed-protocol consumer (DAP, raw
  JSON-RPC, length-prefixed RPC). Backed by `nurl_read_n_bytes` in
  `runtime.c §1` — single `fread` + side-channel byte count via
  the existing `nurl_last_bytes_len`.

* **`tooling/vscode-nurl` extension v0.3.0.** Spawns `nurl-lsp` over
  stdio via `vscode-languageclient`. Server-path fallback order:
  `nurl.server.path` setting → `<workspaceFolder>/build/nurl-lsp` →
  PATH lookup for `nurl-lsp`. Graceful syntax-only fallback when no
  binary resolves. New configuration knobs `nurl.server.path` and
  `nurl.server.trace`. Packaged as `nurl-0.3.0.vsix`.

### Fixed

* **`tools/nurlfmt/build.sh` linker line.** The formatter's build
  script was matching only the libcurl sentinel; missing
  openssl / sqlite3 / libpq linker flags led to `undefined reference
  to TLS_server_method` once OpenSSL was wired into the runtime.
  Now mirrors `tools/nurl-lsp/build.sh` and the central `build.sh`
  by checking all four runtime sentinels (`stdlib/runtime.{curl,
  openssl,sqlite3,pq}`) and appending the corresponding `pkg-config
  --libs` to the link line. Same pattern that breaks when a new
  runtime dependency is added across multiple build scripts —
  centralising into `tools/_link_flags.sh` is a follow-up.

## [0.4.1] — 2026-05-15

### Fixed

* **WASI build: gate setjmp/longjmp + clock() that wasi-sdk rejects.**
  The v0.4.0 panic model `#include <setjmp.h>` made `runtime.c`
  unbuildable under `--target=wasm32-wasi` (wasi-sdk's setjmp.h
  errors out unless `-mllvm -wasm-enable-sjlj` is set against the
  unfinalised Wasm Exception Handling proposal). Same for `clock()`,
  which is deprecated on wasi-sdk without `_WASI_EMULATED_PROCESS_CLOCKS`.
  Both are now `#ifndef __wasi__`-guarded. On WASI, `nurl_recover`
  degrades to "run-the-closure-inline, return 0"; `nurl_panic` prints
  the message and aborts (same shape as the no-frame path on native
  targets); `nurl_panic_last_msg` returns `""`. The degraded recover
  semantics line up with WASI's other single-threaded fallbacks
  (signals, processes, threads). Native builds unchanged — bootstrap
  fixed point still at 1 184 466 B.

## [0.4.0] — 2026-05-15

Tier A correctness/safety holes from the v0.3.0 external review all
closed; Tier B HTTP production-hardening complete end-to-end (TLS
1.2+, per-request timeout, configurable parser limits, handler panic
recovery); Tier C module-system extended (`pub` for types/enums/
consts, alias rewrite for everything); Tier D ecosystem advanced
(SQLite + PostgreSQL FFI, compile-time FFI library check).

The full per-feature breakdown follows.

### Added

* **PostgreSQL FFI in `stdlib/ext/postgres.nu` (pure-NURL).** First
  example of the **runtime-less FFI model**: every libpq symbol is
  declared directly via `& `pq` @ ... → ...` — no `runtime.c` bridge.
  Surface: `pg_connect / _close / _err_msg / _exec / _exec_params /
  _result_status / _result_is_ok / _ntuples / _nfields / _get_value /
  _get_is_null / _field_name / _clear`. `pg_exec_params` accepts a
  `Vec[String]` and builds the parallel `char **` pointer array for
  libpq. v1 scope: text format only, no async, no LISTEN/NOTIFY, no
  COPY streaming. Build-time dep detected via `pkg-config --exists
  libpq`; missing → clear compile-time error from the new lib-check
  (below). Regression: `compiler/tests/postgres_basic.nu`
  (NURL_PG_TESTS=1 + PG_CONNINFO=... to enable).

* **Compile-time FFI library presence check
  (`__ffi_lib_check`).** Every `&`-FFI library name is normalised
  (strip `lib`-prefix, whitelist always-linked system libs `c` / `m` /
  `pthread` / `dl`) and checked against `stdlib/runtime.<lib>`
  sentinels written by `build.sh`. Missing sentinel → die at the
  `&`-decl site with `FFI library '<name>' is required but no
  build-time sentinel '...' found - install lib<name>-dev (or
  equivalent) and run build.sh again`. Replaces cryptic linker errors
  like `undefined reference to PQconnectdb`. Smoke-validated by moving
  `stdlib/runtime.pq` aside and recompiling a postgres-using program.

* **SQLite FFI in `stdlib/ext/sqlite.nu`.** Thin wrapper over
  libsqlite3 with idiomatic `! T SqliteErr` returns. Surface:
  `sqlite_open / _close / _exec / _prepare / _bind_int / _bind_text /
  _bind_null / _step / _column_count / _column_type / _column_int /
  _column_text / _reset / _finalize`. `: Database` / `: Statement`
  value handles, `: | SqliteErr` with 9 variants. `sqlite_step`
  returns `!b SqliteErr` (T=Row, F=Done). v1 scope: int64 + text
  binds/columns only (no BLOB / double), no transaction helpers, no
  statement cache, no ATTACH — those compose with raw SQL. Build-
  time dep detected via `pkg-config --exists sqlite3`; without it,
  every entry returns `SqliteUnsupported`. Runtime side at
  `stdlib/runtime.c §21`. Regression: `compiler/tests/sqlite_basic.nu`
  (in-memory CRUD round-trip with prepared statement reuse).

* **Import alias rewriting extended to types, enum variants, and
  global constants.** `$ `path` alias` now renames every top-level
  decl in the imported file to `alias__name`, not just `@`-functions.
  Use sites reach them with `alias::Name`, which the lexer merges into
  the single IDENT `alias__Name`. FFI declarations and trait/impl
  methods are NOT renamed — FFI is linker-level ABI, trait dispatch is
  type-mangled. `collect_alias_targets` grew handling for `:` /
  `: |` / `: TYPE_KW` / `pub` prefixes. Regression:
  `compiler/tests/alias_rewrite_types.nu` + helper module.

* **`pub` visibility for structs, enums, and global constants.**
  Extends the v2.0 `pub @ greet` rule that already covered `@`-fns to
  cover `pub :`, `pub : |`, and `pub : i FOO 7` declarations. Enum
  variants inherit the parent enum's visibility (no per-variant
  syntax). Enforcement at parse_type_base (cross-file `%Name`
  resolutions) and gen_ident (cross-file `__global` loads). FFI and
  trait/impl decls accept `pub` forward-compat but don't enforce
  (FFI is an ABI contract; trait dispatch is type-mangled, not name-
  routed). Diagnostic: `private type 'X' is not visible across files;
  defined in 'Y'` (and the `global` / `function` variants on the same
  template). Regressions: `pub_type_visibility.nu` (positive) +
  `should_fail_pub_type_neg` / `_const_neg` / `_variant_neg` +
  `should_fail_pub_type_helper.nu` (shared helper).

  **Strategic value:** package management now has the public API
  surface it requires.

### Changed

* **`parse_request_head` now returns `! ParsedHeadOk HttpReqErr`**
  (was `ParsedHead { head, consumed, ok, err }`). The v0.3.0-era
  tagged-struct workaround for the multi-field-Result-Ok-arm hole is
  gone — heap-boxing of multi-field Ok payloads shipped 2026-05-14
  unblocked the idiomatic shape. Callers in `stdlib/ext/http_server.nu`
  (`__read_request_head` + keep-alive loop), `stdlib/ext/http_proxy.nu`
  (`proxy_serve_run_with`), and `compiler/tests/http_request_parser.nu`
  migrated from `? . ph ok / .ph err` branching to `?? ph { T pho → ...
  F e → ... }`. `parsed_head_free` and `__parsed_head_err` removed —
  the new shape needs neither. Bundled cleanup: stale `vec_get [Header]`
  miscompile comments in `header_get` / `__parse_headers` updated to
  reflect current reality (the miscompile shipped a fix May 14;
  direct-pointer iteration is retained where it's still the right
  shape, not as a workaround).

### Added

* **Panic model + HTTP handler panic recovery.** New
  `stdlib/std/panic.nu` module: `panic s msg → v` for explicit aborts,
  `recover ( @ v ) closure → ! v PanicInfo` for setjmp/longjmp-based
  catch. Built on `nurl_recover` / `nurl_panic` / `nurl_panic_last_msg`
  runtime primitives (`stdlib/runtime.c` §20, thread-local jmp_buf
  stack). NOT Rust-style stack unwinding — owned allocations inside a
  recover scope that don't run their auto-drop **leak**. Signal faults
  (SIGSEGV / SIGFPE / SIGBUS) are NOT caught. Recover is crash-
  mitigation, not a routine error path. HttpServer's
  `__serve_keepalive_loop` wraps the handler call in `recover`: panic
  in the handler → server logs the message to stderr + substitutes
  a stock 500 response + keeps serving. Compiler fix bundled:
  `simple_capture_analysis` now captures assignment targets as well
  as read references — the recover-with-byref-capture pattern depended
  on it (pre-fix the closure body referenced the outer's alloca
  register directly, producing invalid IR). Regressions:
  `compiler/tests/recover_basic.nu` (offline; Ok / panic / typed-byref
  round-trip cases) and `compiler/tests/http_server_panic.nu`
  (NURL_NET_TESTS=1).

* **TLS (server-side) via libssl/OpenSSL.** `tcp_listen_tls host port
  cert_path key_path → !TcpListener NetErr` in `stdlib/std/net.nu` is a
  drop-in replacement for `tcp_listen`; `NurlTcp` runtime struct made
  polymorphic via `SSL *ssl` + `SSL_CTX *ssl_ctx` fields, so
  `nurl_tcp_read` / `_write` / `_close` dispatch via libssl when the
  handle was wrapped at listen time. **HttpServer integration is zero
  code changes** — callers just swap the listener constructor. TLS
  1.2 minimum. Build-time dependency detected via `pkg-config --exists
  openssl`; without it, calls return `NetTlsCtxInit`. v1 scope: no
  SNI, no ALPN, no client-cert auth, no live cert reload. New `NetErr`
  variants: `NetTlsCtxInit` / `NetTlsCertLoad` / `NetTlsKeyLoad` /
  `NetTlsHandshake`. Regression:
  `compiler/tests/http_server_tls.nu` (NURL_NET_TESTS=1; generates a
  self-signed cert at setup time).

* **HTTP server Phase 8 closed out.** Two production-hardening items
  shipped:
  - *Configurable parser limits* via new `HttpLimits { i head_max_bytes,
    i header_max_count, i body_default_max }` struct + `http_default_limits`
    ctor in `stdlib/ext/http_request.nu`. `parse_request_head_with` /
    `__parse_headers` / `__finish_body` plumbed; `HttpServer` extended
    with an `HttpLimits limits` field; new `server_new_complete`
    constructor exposes every knob. Existing `server_new` / `_with_timeout`
    / `_full` keep v0.3.0 defaults so every existing call site builds
    unchanged.
  - *Per-request total timeout* via new `HttpServer.request_total_timeout_ms`
    field (0 = disabled). `__serve_keepalive_loop` snapshots `now_ms`
    after each head parse; if the handler runs over budget, its response
    is dropped and a stock 504 sent instead with forced `Connection:
    close`. Enforcement is post-handler only (NURL has no thread-
    cancellation primitives) — per-conn idle timeout still covers slow
    reads.

  Acceptance: `compiler/tests/http_server_limits.nu` (NURL_NET_TESTS=1).
  Mirror call site in `stdlib/ext/http_proxy.nu` uses
  `http_default_limits`.

* **Compiler warnings for `docs/GOTCHAS.md` items 3 + 8.** Two
  non-fatal `warning:` diagnostics now surface the two soundness-
  adjacent foot-guns flagged by the v0.3.0 external review:
  - *Same-line parameter shadowing* (`: i z + z 7` where `z` is a
    function parameter): per-fn `__fn_param_names__` roster shadowed
    inside closure bodies so the check stays scoped. Zero false
    positives across the entire stdlib + compiler + test corpus.
  - *Closure-byref escape on `^`-return*: closures that take a
    `: ~`-mutable multi-field capture by pointer (via the existing
    `__is_capture_byref` predicate) get tagged with
    `__last_closure_byref__` at the closure-literal site; the tag is
    propagated onto the binding (`<name>__captures_byref`) by
    `gen_let_or_struct`; `gen_ret` reads either form and emits the
    warning. `vec_push` / `thread_spawn` escape sites are NOT yet
    checked (documented as follow-up).

  New `should_warn_*` test category in `compiler/tests/run_tests.sh`:
  compile stderr is captured into a `WARNINGS` block (absolute paths
  stripped via `sed $ROOT_DIR/`). Regressions:
  `compiler/tests/should_warn_param_shadow.nu` and
  `compiler/tests/should_warn_closure_escape.nu`. `docs/GOTCHAS.md`
  items 3 + 8 marked "Compiler-warned 2026-05-15" in the quick-ref
  table.

### Fixed

* **`$`-import dedup keys are now canonicalised.** Pre-existing dedup
  tables in three compiler passes (`scan_generic_structs`,
  `scan_fn_sigs`, `gen_import_decl`) keyed on the raw path string, so
  `$ \`stdlib/x.nu\`` and `$ \`./stdlib/x.nu\`` (same physical file,
  different strings) defeated the dedup and produced `redefinition of
  type` errors at link. New `__norm_import_path` helper strips leading
  `./` segments at every `$`-path read site. Symlink-equivalent paths
  still collide as separate imports (no realpath FFI yet —
  intentionally deferred). Acceptance:
  `compiler/tests/import_dedup.nu`. README "Known Limitations" updated
  to drop the stale "no duplicate-include guard" / "alias parsed but
  ignored" claims (alias DOES rewrite top-level `@`-fns; dedup HAS
  worked for exact-string matches since the original `$`-import
  implementation).

* **HTTP server pipelining correctness.** The keep-alive request loop
  previously copied all bytes past a parsed head wholesale into
  `req.body`, which silently corrupted req1 and dropped req2 entirely
  when a peer pipelined two requests in one `send()`. The fix
  introduces a connection-level `Vec[u] carry` buffer that survives
  across keep-alive iterations: `__read_request_head` drops only the
  `.consumed` bytes off the front after a successful parse;
  `__finish_body` drains exactly Content-Length bytes off carry's
  front before topping up from the socket; any remaining bytes feed
  the next iteration. Mirror call site in `stdlib/ext/http_proxy.nu`
  also updated. Acceptance:
  `compiler/tests/http_server_pipelined.nu` (NURL_NET_TESTS=1).

## [0.3.0] — 2026-05-15

Grammar moved from v1.9 → **v2.0**: visibility control with `pub` is
the headline feature. `printf`-family direct-call (variadic FFI)
shipped in the same window. `nurlfmt` learned the canonical layout
and ships as `build/nurlfmt`. Bootstrap fixed point holds with
byte-identical LLVM IR across stages 1 and 2.

### Added

* **Visibility control with `pub`** (grammar v2.0). A top-level decl
  may carry a leading `pub` keyword to mark it public:

  ```nurl
  pub @ greet → v { ( nurl_print `hello\n` ) }
  @ __priv   → v { ( nurl_print `internal\n` ) }
  ```

  Per-file strict-vis mode is OPT-IN: a source file enters strict
  mode the first time any of its decls carries `pub`. In strict
  mode, every unmarked `@`-function is private to that file; calls
  from another file are rejected with
  `private function 'X' is not visible across files; defined in 'Y'`.
  Files without any `pub` decl stay in legacy mode — the entire
  existing stdlib + test corpus continues to build unchanged.

  Implementation: `LTT_PUB = 44` in `stdlib/runtime.c` (the lexer
  recognises the bare identifier `pub`); `compiler/nurlc.nu` tracks
  per-fn origin + per-file strict-mode in a new `g_vis_syms` map,
  the current source file is saved/restored across nested
  `$`-imports, and `gen_call` enforces the rule at @-fn dispatch
  sites. Forward-compat parse paths for `pub` on `:` / `&` / `%`
  decls accept the prefix but do not yet enforce — wider
  enforcement is on the roadmap. `nurlfmt` learned to glue `pub`
  onto the following decl-starter so `pub @ greet` stays on one
  line through the formatter. Regression tests:
  `compiler/tests/pub_visibility.nu` (positive, runs `hello from pub`
  + `hello from priv`) and `compiler/tests/should_fail_pub_visibility_neg.nu`
  (negative, expected `COMPILE FAIL`). Bootstrap fixed point holds
  with byte-identical IR across stages 1 and 2.

* **Variadic FFI + automatic argument promotion** (grammar v1.9).
  FFI declarations may end the param list with the literal `...`
  token to mark the C function variadic. New `LTT_ELLIPSIS = 43`
  in `stdlib/runtime.c`; `gen_ffi_decl` records `<fname>__variadic`
  + `<fname>__variadic_fixed` side-channels; `gen_call` applies the
  C default argument promotions (ISO C §6.5.2.2) to every argument
  beyond the fixed count — `float → double` via `fpext`, narrow
  ints (`i1` / `i8` / `i16`, signedness from the binding's
  `__unsigned` flag) → `i32` via `sext` / `zext`. `i32` / `i64`
  / `double` / pointers pass through unchanged. Unlocks direct
  `printf` / `snprintf` / `fprintf` / `scanf` from NURL without
  per-call hand-widening. Closes `docs/GOTCHAS.md` §9 — every
  remaining §1-10 entry is now an intentional design choice rather
  than a real bug. Canonical example:

  ```nurl
  & `libc` @ printf s fmt ... → i32

  : i32 a 42
  : f32 c # f32 3.5
  ( printf `i32=%d f32=%g\n` a c )   // both args auto-promoted
  ```

  Regression: `compiler/tests/variadic_ffi.nu` (every promotion
  rule in one exit-0 program). Bootstrap fixed point holds at
  1 125 285 B (stage1 ≡ stage2 byte-identical, +11 426 B vs Phase
  1B). `nurlfmt` round-trips `...` as a single OP token (added
  6b branch in `tools/nurlfmt/tokenize.nu`). Snapshot:
  [`spec/grammar_v1.9.ebnf`](spec/grammar_v1.9.ebnf).
* **`nurlfmt` — canonical source formatter.** First-class tooling
  for deterministic NURL source layout. Written in NURL itself
  (eats its own dogfood) and built automatically by `./build.sh`
  to `build/nurlfmt`. Specification lives in
  [`docs/FORMAT.md`](docs/FORMAT.md). CLI mirrors gofmt/rustfmt:
  `nurlfmt` (stdin→stdout), `--stdin` (explicit), `--check`
  (CI-friendly idempotence gate), `--write` (in-place), plus
  multi-file fan-out and the conventional 0/1/2 exit-code
  semantics.

  Architecture: token-stream walker — `tools/nurlfmt/tokenize.nu`
  rebuilds a comment-and-newline-preserving token vector from
  source, `tools/nurlfmt/pretty.nu` emits the canonical layout by
  tracking brace depth, top-level decl boundaries, and type-
  prefix sigil tightness (`*Expr`, `?i`, `[T]`). No CST is
  built; NURL's regular prefix grammar lets a token walker do
  the work that `gofmt` needs an AST for.

  Acceptance:
  `compiler/tests/nurlfmt_idempotent.sh` enforces two invariants
  on every `.nu` file under `stdlib/`, `examples/`,
  `compiler/tests/`, `tools/nurlfmt/`, and `compiler/nurlc.nu`:
  `fmt(fmt(x)) == fmt(x)` (formatter is a fixed point on its own
  output) AND `nurlc(fmt(x)) == nurlc(x)` byte-for-byte (the
  reformat changes zero bytes of emitted LLVM IR). 263 files
  pass idempotence; 251 are IR-equivalence covered (12 are
  include fragments that don't compile standalone and are
  skipped for the IR pass).

  v1 deliberate scope: no automatic line wrapping, no
  cascading-construct extra-indent (a user-written newline
  inside a ternary cascade gets re-indented to the surrounding
  block, not bumped by one level — see FORMAT.md §7), no comment
  reflow, no range formatting.

## [0.2.0] — 2026-05-14

First post-bootstrap release. The grammar moved from v1.7 → **v1.8**,
adding fixed-size integer and float types. Six long-standing compiler
quirks closed; the standard library no longer carries workarounds for
them. Bootstrap fixed point holds at 1 113 859 B (stage1 ≡ stage2
byte-identical LLVM IR).

### Added

* **Fixed-size integer and float types** (grammar v1.8). New TYPE_KW
  tokens `i8`, `i16`, `i32`, `u16`, `u32`, `u64`, `f32` recognised by
  the lexer. LLVM mappings: `i8` / `i16` / `i32` → `iN`; `u16` / `u32`
  → `i16` / `i32` with signedness carried in a per-binding side-
  channel (LLVM IR has no unsigned types); `u64` → `i64`; `f32` →
  `float`. Cast (`#`), let-binding store, and function-parameter
  store all consult the binding's signedness to pick `sext` (signed)
  vs `zext` (unsigned) on widening, `trunc` on narrowing. Float ↔
  double conversions use `fpext` / `fptrunc`; mixed integer/float
  paths use `fptosi` / `sitofp`.
* **Unsigned arithmetic for sized u-types.** `gen_binary` now picks
  `udiv` / `urem` / `lshr` / `icmp u*` when either operand is
  declared `u16` / `u32` / `u64` (matching the existing 8-bit `u`
  behaviour). Bitwise `&` / `|` are sign-agnostic at the LLVM level
  and previously rejected `i8` / `i16` operands; that gate was
  broadened to all integer widths.
* `CONTRIBUTING.md` with contribution guidelines and the byte-
  identical-IR bootstrap acceptance criterion.
* Google Colab notebook badge in `README.md` for one-click try-out.
* Regression tests: `compiler/tests/fixed_size_types.nu`,
  `compiler/tests/unsigned_arith.nu`,
  `compiler/tests/result_multifield.nu`,
  `compiler/tests/result_multifield_try.nu`,
  `compiler/tests/option_multifield.nu`,
  `compiler/tests/option_multifield_try.nu`,
  `compiler/tests/mutable_enum_binding.nu`,
  `compiler/tests/multifield_struct_mut.nu`,
  `compiler/tests/function_param_mut.nu`.

### Changed

* **Grammar v1.7 → v1.8.** Multi-char TYPE_KW tokens added (see
  Added). Per-binding `__nurl_type` + `__unsigned` side-channels
  drive cast / store / binop selection. No breaking changes to
  existing v1.7 programs.
* `stdlib/ext/http_server.nu` `server_run` rewritten to carry the
  failing `NetErr` variant directly through a `: ~ NetErr last_err`
  mutable binding. The previous `had_err: b` sentinel-flag dance
  plus cheap-re-issue trick is gone.
* `docs/GOTCHAS.md` rewritten for the v0.2.0 surface: historical
  bug-fix entries removed, current quirks and design notes only.

### Fixed

* **Multi-field structs on the `! T E` Ok arm.** Previously
  multi-field T couldn't fit through the i64 payload slot, forcing
  callers to wrap state in a single-pointer-handle struct or carry a
  parallel tagged-struct. The compiler now heap-boxes multi-field T
  transparently at construction (`gen_agg_lit`), unboxes at `??`
  match destructure (`gen_match`), and unboxes at `\` try-propagate
  (`gen_try_expr`). Single-pointer-handle T continues to use the
  cheaper `ptrtoint` path — no allocation.
* **Multi-field structs in `? T` Option Some arm.** Option's natural
  `{ i1, %T }` layout already handles multi-field T inline, but the
  standard `@ ? T { F # T 0 }` None-payload idiom in `vec_get` /
  `hashmap_get` / iter combinators emitted invalid IR when T's first
  field was a non-pointer named type (e.g. `%String` inside
  `Header`). `gen_cast`'s `i64 → struct` branch now returns
  `zeroinitializer` for that shape, so the None idiom works
  uniformly across stdlib.
* **Mutable enum bindings.** `: ~ NetErr e NetOther` and the
  symmetric immutable case `: NetErr e NetOther` no longer produce
  type-mismatched IR. `coerce_store_val` wraps `i64 → %Enum` with an
  `insertvalue` before the store, detected via the
  `<name>__variants` side-table. Bare-variant reassignment
  (`= last_err NetTimeout`) works for narrow and wide enums.
* **Multi-field struct mutation through closures.** When a `: ~`-bound
  multi-field struct is captured by a closure, the closure's env
  block now stores the caller's alloca *pointer* instead of
  snapshotting the value. Writes through the closure reach the
  caller's memory; immutable captures still snapshot. Lifetime
  caveat: captures are borrows — the closure must not outlive the
  binding's scope.
* **Function-parameter struct field mutation.** `= . p field val`
  on a struct parameter previously emitted invalid IR (empty GEP
  base). `gen_fn_decl_concrete` now calls `__alloca_struct_params`
  right after the function's `entry:` label; it backs each multi-
  field-struct parameter with an `alloca + store` and registers the
  pointer as the binding's `__ptr`. Value semantics are preserved
  — the function mutates a local copy; callers thread mutation
  back through the return value.

### Removed

* Obsolete test fixture removed from `compiler/tests/`.

---

## [0.1.0] — 2026-05-12

Initial public commit. Self-hosted NURL compiler targeting LLVM,
grammar v1.7. Establishes the baseline against which subsequent
releases are measured.

* Self-hosted compiler (`compiler/nurlc.nu`) with Python bootstrap
  (`compiler/nurlc.py`) and byte-identical-IR fixed-point bootstrap
  acceptance.
* Native cross-compilation targets: Linux x86_64, Windows x86_64
  (mingw-w64 + libcurl + Schannel TLS), macOS x86_64 (`zig cc` +
  libSystem only), wasm32-wasi.
* Self-hosted compiler compiles to ~390 KB of wasm and runs in a
  browser via `@bjorn3/browser_wasi_shim`.
* Single-owner memory model with compiler-inserted auto-drop
  (phases 1, 2A, 2B, 2C, 2D), user `Drop` trait, foreach-borrow
  semantics, scope-exit cleanup.
* **Standard library** under `stdlib/`:
  * `core/`: `option`, `result`, `vec`, `pair`, `string`, `errors`,
    `mem`, `io`.
  * `std/`: `fmt`, `fs`, `path`, `time` (Howard Hinnant civil-time
    algorithms, ISO-8601 + RFC 7231), `random`, `sort`, `iter`,
    `hash`, `hashmap`, `set`, `cmp`, `encode`, `channel`, `thread`,
    `signal`, `process`, `log`, `net`, `bytes`, `int`, `float`.
  * `ext/`: JSON, CSV, regex, UUID v4 + v7 (RFC 9562), env, the
    full HTTP server stack (`http`, `http_json`, `http_request`,
    `http_response`, `http_server`, `http_router`, `http_static`,
    `http_auth`, `http_middleware`, `http_multipart`, `http_proxy`,
    `http_full` aggregator), Anthropic Claude client (streaming
    SSE, prompt caching, extended thinking, tool-use loops), MCP
    client over HTTP and stdio transports.
* HTTP server: Phases 1–6 + 5.3 thread pool + 5.4 HTTP/1.1
  keep-alive (~38× speedup) + 7 (static / auth / cookies / form)
  + 8 mostly (access log, Prometheus metrics, idle timeout,
  graceful shutdown) + 9 partial (multipart/form-data, reverse-
  proxy streaming pass-through).
* 80+ snapshot tests with `compiler/tests/run_tests.sh` runner.
* Documentation: `README.md` (project overview),
  `docs/GOTCHAS.md` (compiler quirks),
  `spec/grammar.ebnf` (v1.7 grammar).
* Tooling: VS Code extension (`tooling/vscode-nurl/`), Dockerised
  compile-server (`api/`), browser playground (`nurlweb/`).
* Dual license: MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE).

[Unreleased]: https://github.com/nurl-lang/nurl/compare/v0.44.2...HEAD
[0.44.2]: https://github.com/nurl-lang/nurl/compare/v0.44.1...v0.44.2
[0.44.1]: https://github.com/nurl-lang/nurl/compare/v0.44.0...v0.44.1
[0.44.0]: https://github.com/nurl-lang/nurl/compare/v0.43.0...v0.44.0
[0.43.0]: https://github.com/nurl-lang/nurl/compare/v0.42.0...v0.43.0
[0.42.0]: https://github.com/nurl-lang/nurl/compare/v0.41.0...v0.42.0
[0.41.0]: https://github.com/nurl-lang/nurl/compare/v0.40.0...v0.41.0
[0.40.0]: https://github.com/nurl-lang/nurl/compare/v0.39.0...v0.40.0
[0.39.0]: https://github.com/nurl-lang/nurl/compare/v0.38.0...v0.39.0
[0.38.0]: https://github.com/nurl-lang/nurl/compare/v0.37.1...v0.38.0
[0.37.1]: https://github.com/nurl-lang/nurl/compare/v0.37.0...v0.37.1
[0.37.0]: https://github.com/nurl-lang/nurl/compare/v0.36.0...v0.37.0
[0.36.0]: https://github.com/nurl-lang/nurl/compare/v0.35.1...v0.36.0
[0.35.1]: https://github.com/nurl-lang/nurl/compare/v0.35.0...v0.35.1
[0.35.0]: https://github.com/nurl-lang/nurl/compare/v0.34.0...v0.35.0
[0.34.0]: https://github.com/nurl-lang/nurl/compare/v0.33.0...v0.34.0
[0.33.0]: https://github.com/nurl-lang/nurl/compare/v0.32.0...v0.33.0
[0.32.0]: https://github.com/nurl-lang/nurl/compare/v0.31.1...v0.32.0
[0.31.1]: https://github.com/nurl-lang/nurl/compare/v0.31.0...v0.31.1
[0.31.0]: https://github.com/nurl-lang/nurl/compare/v0.30.0...v0.31.0
[0.30.0]: https://github.com/nurl-lang/nurl/compare/v0.29.0...v0.30.0
[0.29.0]: https://github.com/nurl-lang/nurl/compare/v0.28.0...v0.29.0
[0.28.0]: https://github.com/nurl-lang/nurl/compare/v0.27.0...v0.28.0
[0.27.0]: https://github.com/nurl-lang/nurl/compare/v0.26.0...v0.27.0
[0.26.0]: https://github.com/nurl-lang/nurl/compare/v0.25.1...v0.26.0
[0.25.1]: https://github.com/nurl-lang/nurl/compare/v0.25.0...v0.25.1
[0.25.0]: https://github.com/nurl-lang/nurl/compare/v0.24.1...v0.25.0
[0.24.1]: https://github.com/nurl-lang/nurl/compare/v0.24.0...v0.24.1
[0.24.0]: https://github.com/nurl-lang/nurl/compare/v0.23.0...v0.24.0
[0.23.0]: https://github.com/nurl-lang/nurl/compare/v0.22.0...v0.23.0
[0.22.0]: https://github.com/nurl-lang/nurl/compare/v0.21.0...v0.22.0
[0.13.0]: https://github.com/nurl-lang/nurl/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/nurl-lang/nurl/compare/v0.11.3...v0.12.0
[0.10.12]: https://github.com/nurl-lang/nurl/compare/v0.10.11...v0.10.12
[0.10.11]: https://github.com/nurl-lang/nurl/compare/v0.10.10...v0.10.11
[0.10.10]: https://github.com/nurl-lang/nurl/compare/v0.10.9...v0.10.10
[0.10.9]: https://github.com/nurl-lang/nurl/compare/v0.10.8...v0.10.9
[0.10.8]: https://github.com/nurl-lang/nurl/compare/v0.10.7...v0.10.8
[0.10.7]: https://github.com/nurl-lang/nurl/compare/v0.10.6...v0.10.7
[0.10.6]: https://github.com/nurl-lang/nurl/compare/v0.10.5...v0.10.6
[0.10.5]: https://github.com/nurl-lang/nurl/compare/v0.10.4...v0.10.5
[0.10.4]: https://github.com/nurl-lang/nurl/compare/v0.10.3...v0.10.4
[0.10.3]: https://github.com/nurl-lang/nurl/compare/v0.10.2...v0.10.3
[0.10.2]: https://github.com/nurl-lang/nurl/compare/v0.10.1...v0.10.2
[0.10.1]: https://github.com/nurl-lang/nurl/compare/v0.10.0...v0.10.1
[0.10.0]: https://github.com/nurl-lang/nurl/compare/v0.9.19...v0.10.0
[0.9.14]: https://github.com/nurl-lang/nurl/compare/v0.9.13...v0.9.14
[0.9.13]: https://github.com/nurl-lang/nurl/compare/v0.9.12...v0.9.13
[0.9.12]: https://github.com/nurl-lang/nurl/compare/v0.9.11...v0.9.12
[0.9.11]: https://github.com/nurl-lang/nurl/compare/v0.9.10...v0.9.11
[0.9.10]: https://github.com/nurl-lang/nurl/compare/v0.9.9...v0.9.10
[0.9.9]: https://github.com/nurl-lang/nurl/compare/v0.9.8...v0.9.9
[0.9.8]: https://github.com/nurl-lang/nurl/compare/v0.9.7...v0.9.8
[0.9.7]: https://github.com/nurl-lang/nurl/compare/v0.9.6...v0.9.7
[0.9.6]: https://github.com/nurl-lang/nurl/compare/v0.9.5...v0.9.6
[0.9.5]: https://github.com/nurl-lang/nurl/compare/v0.9.4...v0.9.5
[0.9.4]: https://github.com/nurl-lang/nurl/compare/v0.9.3...v0.9.4
[0.9.3]: https://github.com/nurl-lang/nurl/compare/v0.9.2...v0.9.3
[0.9.2]: https://github.com/nurl-lang/nurl/compare/v0.9.1...v0.9.2
[0.9.1]: https://github.com/nurl-lang/nurl/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/nurl-lang/nurl/compare/v0.8.1...v0.9.0
[0.8.1]: https://github.com/nurl-lang/nurl/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/nurl-lang/nurl/compare/v0.7.3...v0.8.0
[0.2.0]: https://github.com/nurl-lang/nurl/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/nurl-lang/nurl/releases/tag/v0.1.0
