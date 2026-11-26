# The certificate bundle

Status: **S1 and M4 of the certified-programs work** (AGORA-1019; M4,
the translator in NURL and threaded programs, AGORA-1020; the term checked
by the kernel for the subset of numbers, buffers of numbers and views,
AGORA-1029 steps 3 to 5; part of
AGORA-1010; spec in the agora notes `spec.program-cert`, `.2`, `.3`).
Schema **`nurl-cert/1`**, described here and in
[`certificate.schema.json`](certificate.schema.json).

A certificate states theorems about one program. It does not ask to be
trusted: `nurl verify` checks it again, and every assumption it rests on
is a row of its trust ledger.

```sh
nurl --certify prog.nu prog          # build prog, then write prog.cert/
nurl verify prog.cert --binary prog  # check it again: no compiler needed
```

`nurl --certify` builds the program as usual, then runs
`nurl-cert certify` (`packages/nurl-cert`, written in NURL). The build is
unchanged. The exit code is the certificate's: 0 when every claim is
proved, 2 when the translation does not cover the program, 3 when the
checker refuses it. `nurl verify` runs `nurl-cert verify`. Both find
`formal/` through `$NURL_FORMAL`, then next to `nurl.sh`. They need Lean's
`lake` on `PATH`, and `formal/` built (`lake build C.Cert C.Cert3 C.Elab`).

The flag's and the subcommand's names are working names. The owner
confirms them before 1.0.

## 1. What is proved

For a program `P` (its term in `formal/A2`'s calculus) run from its entry
`entry` over one slot, `Claims.lean` holds:

```lean
theorem Cert.verdict : C.certOK2B P entry 1 = true := by decide +kernel

theorem Cert.m_safe :        -- M.safe
    ∀ m' s', A2.Steps P (A2.emptyMem 1) entry (.ok m' s') → ¬ A2.Stuck P m' s'

theorem Cert.m_leak :        -- M.leak
    (∀ m', A2.Steps P (A2.emptyMem 1) entry (.ok m' .skip) → ∀ i, m'.alloc i = false) ∧
    (∀ m', A2.Steps P (A2.emptyMem 1) entry (.panic m') → ∀ i, m'.alloc i = false)
```

- `M.safe`: no run from the empty store ever gets stuck. A stuck state is
  a read or write of memory the program does not own: a use after free, a
  double free, a dangling view, an access out of bounds (`A2.Stuck`,
  `formal/CLAIM.md`).
- `M.leak`: a run that finishes has freed every allocation, and so has a
  run that ends in a panic nothing recovers.

The statements use A2's semantics only (`Steps`, `Stuck`, `emptyMem`,
`Mem.alloc`). `formal/CLAIM.md` is their review document.

**What "any run" means.** The core IR records what a program does with
memory, not the numbers it computes. The translation writes every number
the IR does not track (a condition, a loop condition, an index, a
computed value) as `Expr.any`, which evaluates to any number (AGORA-1030).
A model step on such a condition can take either arm (`C.ite_any_both`),
so the runs a claim quantifies over include every run the program can make,
whatever its numbers. Certificates made before this (nurl-cert 0.1.0, the
v0.95.0 release) wrote `.lit 0` there. Their model took only the else arm
of every `if`, so their claims covered that single run; the checker's
verdict, which types every arm, was the same. Certify such a bundle again.

The proofs are one line each. `formal/C/Cert.lean` (C13) gives
`cert_safe`, `cert_leak_end` and `cert_leak_panic`: A2's `memory_safe`,
`no_leak_end` and `no_leak_panic`, for any program whose checker verdict
`certOK2B` is `true`. That verdict is decided by the Lean kernel
(`decide +kernel`).

`certOK2B` is everything the verified checker decides about a program:
- `progOK2B`, every function;
- `checkA2` on the entry;
- `stmtCodesB`;
- `s.src`;
- the slot bound.

The kernel profile adds no axiom: `#print axioms` lists only `propext`,
`Classical.choice` and `Quot.sound`.

**A threaded program** (one that calls `thread_spawn_owned`) is certified
against A3, since A2 has no threads (AGORA-1020). Program.lean then ends
with `def spawns : List Nat := [...]`, the spawned functions, and
Claims.lean imports `C.Cert3` and proves three claims over every
interleaving of its threads, from `C.certOK3B P spawns entry 1`
(`formal/C/Cert3.lean`, C14):

```lean
theorem Cert.m_safe : ∀ C, A3.Reach P (fun f => decide (f ∈ spawns)) (A3.Cfg.init entry 1) C →
    ∀ (i : Nat) (t : A3.Thread), C.ths[i]? = some t → ¬ A2.Stuck P (C.view t) t.s
theorem Cert.m_leak : ∀ C, A3.Reach … C → (∀ t ∈ C.ths, t.s = .skip) → ∀ i, C.alloc i = false
theorem Cert.m_race : ∀ C, A3.Reach … C → ¬ A3.Race P C
```

- `M.race` rests on one more ledger row, `drf-sc`: the C11 / LLVM memory
  model's guarantee that a race-free program behaves sequentially
  consistently. It is cited, not mechanized.
- A spawn is A3's spawn-only call of a wrapper function. The wrapper takes
  the closure over (class `send`: its environment holds no view and no
  binding by name) and calls it.
- The join is a read. Modelling no join only adds interleavings, so the
  claims hold all the more with it.
- `thread_spawn_owned` gives the thread its own copy of the environment.
  The translation moves it instead, which is stricter: a program that uses
  the closure again after spawning it is refused. That is a precision gap,
  never a hole.
- Module globals are not translated yet: such a program is `unsupported`.
- **What the threaded claims cover.** The translation takes every
  `thread_spawn_owned` to succeed. A run in which `pthread_create` fails,
  and the code that handles `ThreadCreate`, is outside the claims: that
  code is type-checked with the rest, but no theorem speaks of its runs.
  Modelling a failing spawn would need a nondeterministic outcome in A3.
  The sentences say so ("on any run in which every thread it spawns
  starts").
- `M.leak` for a threaded program is A3's leak clause: once every thread
  has finished, nothing is allocated. Unlike the single-threaded claim, it
  says nothing of a run that a panic ends.
- A spawned closure that is used again after its spawn, or passed to a
  function that takes the ordinary closure type, is `unsupported`. Not
  refused: `thread_spawn_owned` copies the environment, and the copy is not
  translated yet.

## 2. The bundle

```
prog.cert/
  manifest.json   statuses, coverage, hashes, versions, the trust ledger
  Program.core    nurlc's core IR of the program (--emit-core), the translation's input
  Program.lean    the program as a term of formal/A2: fn0 … fnN, P, entry
  Claims.lean     the claims above, stated and proved; only when the checker accepts
  Elab.lean       Program.core as Lean data (C.Elab.IR) and the proof that Program.lean's
                  term is the one the kernel builds from it (Cert.elab); only for a
                  program in C.Elab's subset
```

- **Program.lean** is made from Program.core by nurl-cert's translator
  (`packages/nurl-cert/src/tolean.nu`, on the one reader of the core IR,
  `coreir.nu`), with no other program in between: `nurl-cert translate
  prog.core` prints the same term with the checker's `#eval` frame. It
  is the NURL port of the Python prototype `tools/ncore/tolean.py`, which
  stays its reference: `tools/ncore/tolean_parity.sh` runs both over
  every certify program and every hole probe and finds no byte of
  difference, and `packages/nurl-cert/tests/translate_test.sh` holds the
  fail-closed cases (a core IR the translation cannot render is
  `unsupported`, never a term).
- **Program.lean** is held to the translator's grammar:
  - the lines `import C.Cert` and `open A2 C`;
  - `def fn<k> : Fn := …`;
  - `def P : Prog := [fn0, …]`;
  - `def entry : Stmt := .letcall 0 <k> [] .skip`;
  - terms built from constructors (`.name`), numbers, `true`/`false`, the
    fields of `Fn` and the punctuation `( ) [ ] { } , :=`.

  Nothing else passes. There is no comment, string, other name or
  non-ASCII character. So the file cannot declare an axiom, a notation, a
  macro or an instance that would change what the claims say
  (`packages/nurl-cert/src/shape.nu`).
- **Claims.lean** is a pure function of the profile and the program's slot
  count (`packages/nurl-cert/src/claims.nu`). `verify` writes it again and
  compares the bundle's copy byte for byte. A statement weakened, a proof
  replaced by `sorry`, or an axiom added is a difference.
- **Elab.lean** takes the translator out of the trusted path, for the
  programs `C.Elab.elabIR` covers (numbers; buffers of numbers: raw
  text, `String`s and `Vec`s of numbers; views: slices of `Vec`s of
  numbers, raw text viewed by `string_data`, `Vec`s of raw strings; and
  `foreach` and the changes of a `Vec` through a borrow, `vec_clear`,
  `vec_truncate`, `vec_reserve`, `string_push_str`;
  `docs/dev/TRANSLATION_TRUST.md`, route (b), steps 2, 4 and 5). It is a
  pure function of
  Program.core (`cert_elab_lean`, `packages/nurl-cert/src/claims.nu`):

  ```lean
  import Program
  import C.Elab
  namespace Cert
  noncomputable def ir : C.Elab.IR := [ … ]   -- nurl-cert words of Program.core
  theorem «elab» : C.Elab.elabIR ir = some (P, entry) :=
    C.Elab.elabIs_sound _ _ _ (by decide +kernel)
  end Cert
  #print axioms Cert.«elab»
  ```

  (`elab` is a keyword of Lean, hence `«elab»`; Lean prints the name
  `Cert.elab`.)
  - The words are `nurl-cert words` (`packages/nurl-cert/src/words.nu`).
    Every word is a Lean string literal: `"` and `\` are escaped, a byte
    below 32 is `\x..`, a byte above 127 is written as it is. Lean reads
    well-formed UTF-8 back as the same bytes; a core IR that is not
    well-formed UTF-8 has no words, and its bundle no Elab.lean.
  - A library function (its file starts with `stdlib/`) is left out of
    the words whole, when Lean's reader (`C.Elab.readFns`) would accept
    its records: its `fn` line's parameter count and each of its `v`
    lines. When it would not, its `fn`, `v` and `endfn` lines are
    printed, and the reader refuses the words as it refuses the whole IR.
    The translator reads only the program's own functions' bodies, and
    `elabIR` drops the library's by the same test before it reads
    anything of them but those records, so it answers the same on the
    words as on every line (`tools/ncore/elab_parity.sh` compares the two
    over the corpus; the selftest over IRs the reader refuses).
    This came with nurl-cert 0.3.0: a 0.2.0 bundle with Elab.lean whose
    core IR has library functions does not verify with it (`verify`
    makes Elab.lean again, and it is another file now). Certify the
    program again.
  - certify writes it for a translated term that can be `elabIR`'s at
    all, and Lean checks it in the same run as Claims.lean (below).
    A term with a constructor `elabIR` never builds (the list
    `ELAB_CTORS` in claims.nu, read off formal/C/Elab.lean) cannot equal
    `elabIR`'s, so Lean is not asked: that skip is exact. For every other
    term Lean decides.
  - The bundle keeps Elab.lean when the checker accepts the program, Lean
    exits 0, and `Cert.elab` rests on the standard axioms only. Otherwise
    it is deleted, and the bundle is as before, its term the translator's.
  - With it, `M.safe` and `M.leak` are about the term the kernel built
    from Program.core's words. What is left of the `translation` row is
    nurlc's core IR and the split into words.
- **How Lean checks a bundle.** The bundle holds the three modules, which
  a person can check with lake the module way: Program.lean compiled to
  its olean, then Claims.lean and Elab.lean against it. certify and
  verify check them in one Lean process instead, one file made in the
  work directory (`cert_lean_check`, packages/nurl-cert/src/lean.nu):
  `import C.Cert` (and `import C.Cert3` for a threaded Claims.lean,
  `import C.Elab` with Elab.lean); `section`, `open A2 C`, Program.lean's
  definitions, `end`; Claims.lean without its imports; Elab.lean without
  its imports. The file means what the modules mean:
  - Program.lean's grammar (shape.nu) allows only its two first lines,
    `import C.Cert` and `open A2 C`, exactly, then definitions: no option,
    notation, instance, namespace or attribute. So its definitions read
    the same inline as imported, and the `section` ends its `open` before
    the claims, as the end of its module does;
  - Claims.lean and Elab.lean are the templates byte for byte (certify
    writes them, verify compares them before Lean runs);
  - only lines checked to be exactly the expected ones are left out
    (Program.lean's two lines; Claims.lean's `import Program`, and a
    threaded one's `import C.Cert3`; Elab.lean's `import Program` and
    `import C.Elab`, each after nothing but comments); any other shape is
    refused;
  - no `.olean` passes from one process to the next, so a planted
    `Program.olean` is no longer an attack surface.

  Lean runs it with `--json`, so every message, `#print axioms` output
  included, comes with its file and line. A message is placed by its own
  line, not by where it comes in the output. A message from the line
  where the Elab.lean part starts on is Elab.lean's; any other is
  Program.lean's or Claims.lean's. Output that cannot be placed (not one
  of Lean's messages, another file's, a message with no line, anything
  on stderr) counts as an error of the claims' part, so it fails closed.
  An error of the claims' part is an error or a refusal, as with the
  modules. An error of the Elab.lean part alone means only that
  `Cert.elab` is not proved (no Elab.lean; the translation row the
  translator's). `Cert.elab` still counts only on
  an exit 0 and `#print axioms` listing the standard axioms. A run that
  ends any other way (killed, out of memory) with no error of Lean's in
  the claims' part is run again once without the Elab.lean part: the
  claims count if that run passes, and `Cert.elab` is not proved, so
  certify writes no Elab.lean and verify of a bundle that holds one fails.
  certify prints why a candidate has no `Cert.elab`
  (`Cert.elab not proved: …`). The selftest
  checks three bundles both ways (verdict, each claim's axioms,
  Cert.elab), a candidate whose Elab.lean part fails (accepted, no
  Elab.lean), the refused programs of the subset (their claims refused
  beside an Elab.lean part the kernel proves), and a refused program's
  term in a bundle with Elab.lean (verify fails on the claims). A refused `Cert.elab` costs little: `C.Elab.elabIs` is
  irreducible to the elaborator (not to the kernel), so `decide +kernel`
  does not re-reduce it to explain the failure, which on a real core IR
  took tens of GB.
- **Refused and unsupported programs** get a bundle with no Claims.lean,
  and their `M.safe` and `M.leak` are `open`. A bundle is written whole:
  certify first deletes the old Claims.lean, Elab.lean and manifest.

## 3. Claims and statuses

| status | meaning |
|---|---|
| `proved` | a theorem about this program, kernel-checked, standard axioms only (profile `kernel`) |
| `validated` | decided by compiled code (profile `fast`: `native_decide`); its compiled-code axiom is listed |
| `assumed` | rests on a ledger row, not on a theorem (`M.unsafe`: nurlc's `--unsafe-report`) |
| `open` | not proved: the program is refused or unsupported, or Lean did not check it; NOT PROVED |

A claim's status is read off what Lean reports for it: the axioms
`#print axioms` lists. It is never written down from what was intended.
Under `kernel`, a claim is `proved` exactly when it rests on the three
standard axioms. Under `fast`, it is `validated` when the rest is the
axiom `native_decide` adds (`Cert.verdict._native.native_decide.ax_…`).
Anything else is `open`.

Each claim names its premises, which are ledger rows. A claim's effective
status is the weakest on that chain. `M.safe proved` reads: proved for the
program's term in the model; the term's link to the source rests on the
translation, and the link to the binary on LLVM and the linker.

## 4. manifest.json

```
schema      "nurl-cert/1"
tool        { name, version }
profile     "kernel" | "fast"
program     { source, verdict: accepted | refused | unsupported | error, reason, slots }
claims      [ { id, lean, status, sentence { en, fi }, reason, axioms [..], premises [ledger ids] } ]
            M.safe, M.leak, (a threaded program) M.race, then M.unsafe, in this order
coverage    { functions: [ { name, file, line, status, reason } ], <status>: count }
hashes      { sources: [ { path, sha256 } ], core_ir, llvm_ir?, program_lean?, claims_lean?,
              elab_lean?, binary?: { path, sha256 } }
versions    { nurlc, formal_tree, formal_commit, lean_toolchain }
ledger      [ { id, what, why, where, vouches, claims [..] } ]
```

- `hashes.sources`: every file the compile read, hashed as the bytes
  nurlc compiled. `nurlc --list-sources=TAG` prints each snapshot it
  reads on stderr: a line `source:TAG <length> <real path>`, then the
  bytes, then a newline. TAG is fresh and random per run, so no line a
  diagnostic quotes from a source can pass for a record. A path holding a
  newline stops the compile. certify hashes those bytes and requires each
  file on disk to hold them still; a file changed during the run
  certifies nothing. So the hashes are of exactly the bytes that made
  Program.core, and `verify`'s re-hash of the files checks those bytes.
- `hashes.llvm_ir` is the sha256 of nurlc's LLVM IR, with no flags, for
  the program. It is absent when nurlc refuses to compile the program.
- `hashes.binary` is present when `--binary` was given.
- `hashes.elab_lean` is present exactly when the bundle has Elab.lean,
  and records the case: with it, the `translation` row is the kernel's
  (below), and verify requires the file.
- **Schema.** The member is optional, so the schema stays
  `nurl-cert/1`. A bundle made before it (nurl-cert 0.1.x, against the
  same `formal/` tree) has none, and verifies as before with its
  translator's row. An older verify refuses a bundle that has it (an
  unknown member), which fails closed.
- `versions.formal_tree` is the sha256 of a listing with one line
  `<sha256>  <path>` per file of `formal/`, in byte order of the paths:
  every `.lean` file, plus `lakefile.toml`, `lean-toolchain` and
  `lake-manifest.json`, and not `.lake/`. `verify` refuses another tree.
  `formal_commit` is informational.
- `coverage.functions`: the program's own functions in the core IR (not
  the standard library's). All of them share the program's verdict,
  because the translation is all or nothing today. Per-function
  certificates are AGORA-1015.

### The trust ledger

One row per thing the claims rest on and do not prove:

| id | what |
|---|---|
| `lean-kernel` | the Lean 4 kernel and the pinned toolchain |
| `lean-compiler` | (profile `fast` only) the Lean compiler, which computes the verdict |
| `claim-definitions` | the claims' definitions, A2's semantics (`formal/CLAIM.md`) |
| `translation` | without Elab.lean: the step from source to term, `nurlc --emit-core`, then nurl-cert's translator (`packages/nurl-cert/src/tolean.nu`). With Elab.lean: only `nurlc --emit-core` and the split of Program.core into words (`words.nu`; verify makes Elab.lean again from Program.core), and `C.Elab.elabIR`'s rules as the meaning of a core IR; the term itself is the kernel's (`Cert.elab`) |
| `library-summaries` | the standard library as the term has it, A2 primitives and declared summaries; the models follow the library by inspection (AGORA-1014) |
| `llvm`, `linker`, `os`, `c-runtime` | the path from the IR to a running binary |
| `drf-sc` | (a threaded program) the C11 / LLVM memory model's DRF-SC guarantee, for `M.race` |
| `unsafe-report` | `M.unsafe` is what nurlc's `--unsafe-report` says |
| `unsafe-<n>` | one row per line of that report: each `unsafe` function, `unsafe % Send` / `% Sync` assertion and foreign-declaration claim of the program |

A bundle with no `unsafe-<n>` row and `M.unsafe` assumed has no
hand-vouched code of its own. Apart from the translation, it rests only on
the toolchain and the library.

## 5. verify

`nurl verify prog.cert [--binary prog] [--rebuild]` checks, and prints
`ok` or `FAIL` for, each of the following:

- the schema and the profile;
- the manifest's shape:
  - the schema's top-level members, and no others;
  - every required field;
  - the claims in the template's order, with its ids, theorems, sentences
    and premises;
  - the trust ledger exactly as certify writes it for this profile and
    these unsafe rows. A dropped or reworded row does not verify;
- the hash of every source file, of Program.core, Program.lean and
  Claims.lean, and of Elab.lean when the manifest records it;
- that the bundle has Elab.lean when the manifest records
  `hashes.elab_lean` (and the program is accepted), and none otherwise;
- that the `formal/` tree is the pinned one;
- the binary, when given;
- Program.lean's grammar and the slot count;
- Claims.lean against the template, byte for byte;
- with Elab.lean: Elab.lean against the one made from Program.core
  (its words and the template), byte for byte;
- that Lean checks Program.lean and Claims.lean again, and, with
  Elab.lean, that it proves `Cert.elab` again with the standard axioms
  only. Lean is run only when every check above passed: it runs code
  while it elaborates a file, so a file the grammar, the template or a
  hash refused is never handed to it. A run counts only when Lean exits
  0;
- for each claim, that the manifest's status and axioms are what Lean
  reports now;
- that `M.unsafe` is `assumed` (or `open` with no LLVM IR);
- that nothing is claimed beyond the template's claims.

For a refused or unsupported program it checks instead that there is no
Claims.lean and that no claim is above `open`. The exit code is 0 only
when every check passes.

`packages/nurl-cert/tests/nurl-cert_test.sh` is the selftest, and CI runs
it (`certify.yml`). A fresh bundle verifies, and `verify`
fails, naming the check, on each of these edits:
- one source byte changed;
- a claim's status edited in the manifest;
- a theorem's statement weakened in Claims.lean;
- `sorry` put in Claims.lean, or an axiom added to Program.lean;
- the wrong binary given;
- in a bundle with Elab.lean: another scalar program's Program.lean
  swapped in, with its hash updated (on `Cert.elab`); Elab.lean
  deleted with the manifest kept; its words or its theorem edited, its
  hash updated; code put in it (Lean never runs it).

A bundle downgraded honestly verifies: Elab.lean removed, its hash
dropped, and the `translation` row the translator's again.
That is expected. It is the weaker bundle, and its ledger says so. With
the kernel's row kept, it does not verify.

Without Elab.lean, a plain `verify` cannot tell whether Program.lean is
the source's term or a well-formed term of some other program with every
hash updated: the translation is a ledger row. With Elab.lean it can, for
the step from Program.core on: the kernel refuses any term but the one
`C.Elab.elabIR` builds from Program.core's words. `verify --rebuild` checks
the whole step where nurlc and the translator are at hand: it runs
`nurlc --emit-core` on the recorded sources and the translator on
Program.core again, and compares both byte for byte. The selftest swaps
another program's term into a bundle without Elab.lean: plain verify
passes it, and `--rebuild` refuses it. Signing a bundle (an in-toto statement) is out of
scope.

## 6. Cost

Measured over the 58 programs of `tools/ncore/certify/` (34 accepted, 24
refused), one at a time, on an x86-64 Linux host (AGORA-1019):

- `nurl --certify` against the plain build (`nurl.sh`, the cache off), for
  the 34 accepted programs:
  - time: median 2.0×, range 1.4× to 38.2×;
  - peak RSS: median 6.7×, at most 27.2×.
- A whole certify takes 0.84–1.4 s per program. Most of its memory is
  Lean holding formal/'s A2 and C environment (about 0.6 GB), whatever the
  program.
- The kernel decides the verdict in 0.39–1.05 s for 57 of the programs.
- The stress program `joins_each_freeing_a_different_vec` (22 joins)
  takes 18.5 s and 2.4 GB under the kernel, against 1.6 s under `fast`.
  Splitting it per function would not help: it is one function.
- Plain `decide` (elaborator first) runs out of recursion depth on it.
  That is why the kernel profile uses `decide +kernel`, which is also the
  fastest kernel route on every other program (0.41 s against 0.62 s on a
  typical one).

Elab.lean costs little. At step 3 (AGORA-1029), over the 62 certify
programs, one at a time, best of 3, certify took 79.2 s against 78.6 s
before (+0.8 %). With step 4's larger subset and its one Lean process a
program it takes 82.1 s against 83.9 s (−2.1 %). Step 5 covers 13 more
of them, which now each have an Elab.lean part (+0.3 to +0.8 s a
program; 8 of them are refused, and spend it too), and leaves the
library's functions out of the words whole, which makes the other 49
7.2 s faster: 81.3 s against 80.8 s (+0.6 %). Lean is asked only for a
term that can be `elabIR`'s; `docs/dev/TRANSLATION_TRUST.md` (steps 3 to
5) has the numbers, peak memory included.

Without `--certify`, nothing changes:
- `--list-sources=TAG` is off by default;
- 2120 programs compile byte-identical (compiler/tests, the certify
  programs, examples);
- the self-compile is neutral within codegen noise: +0.056 % instructions
  at -O2 (25.669 G → 25.683 G) and −0.07 % at -O0, where layout does not
  count (84.321 G → 84.261 G), with the same peak RSS (186 MB). Both
  compilers were built by the same compiler and link.
