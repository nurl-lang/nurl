# The certificate bundle

Status: **S1, S3 and M4 of the certified-programs work** (AGORA-1019; M4,
the translator in NURL and threaded programs, AGORA-1020; the term checked
by the kernel for the subset of numbers, buffers of numbers, views,
closures, options and structs, AGORA-1029 steps 3 to 7; S3, what a program
can do outside its memory, `N.cap`, AGORA-1013; part of AGORA-1010; spec in
the agora notes `spec.program-cert`, `.2`, `.3`).
Schema **`nurl-cert/2`**, described here and in
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
proved, validated or conditionally assumed, 2 when the translation does not
cover the program, 3 when the checker refuses it. `nurl verify` runs
`nurl-cert verify`. Both find
`formal/` through `$NURL_FORMAL`, then next to `nurl.sh`. They need `lean`
on `PATH` (elan's: run inside `formal/`, it picks `formal/`'s toolchain;
or `--lean PATH` / `$LEAN`), and `formal/` built (`lake build C.Cert
C.Cert3 C.Elab C.Complete C.Caps C.Caps3`).

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

## 1b. What it can do: N.cap

`N.cap` says what the program can do outside its own memory, and what it
never does (AGORA-1013). It has two halves, apart in the bundle as they
are in the proof.

**Which of its functions a run can enter: a theorem.** `Caps.lean`
states a list of the program's function indices, `Cert.runs`, and proves
two things. First, the kernel checks that the list is closed: the entry
and every function of the list name only functions of the list
(`C.capsOKB`, `formal/C/Caps.lean`, C16). A name is a call's callee, a
`recover`'s, a destructor frame's (`letd`, `scopeD`, the destructor of a
block's type), a call's result frame, or a closure literal's code. Second,
from that check:

```lean
theorem Cert.n_cap : ∀ (P' : A2.Prog), (∀ f ∈ runs, P'[f]? = P[f]?) →
    ∀ (nv : Nat) (r : A2.Res), A2.Steps P (A2.emptyMem nv) entry r ↔ A2.Steps P' (A2.emptyMem nv) entry r
```

Any program with the same functions at the list's indices, whatever it
has elsewhere, has exactly this program's runs. So a function outside the
list never runs: its code could be anything, and no run would change. A
threaded program's `Cert.n_cap` says the same of every interleaving
(`A3.Reach`, `C.caps3_runs`, `formal/C/Caps3.lean`). The proof is
`formal/A2/Reach.lean` and `formal/A3/Reach.lean`: every step keeps a
configuration naming only such a list, in what is left to run and in what
memory holds (its packages' code, its blocks' destructors), and a step
reads the program only at a name it holds. Both are layers over A2 and
A3; no rule or theorem changed.

certify makes the list by scanning Program.lean's term for those names
from the entry (`cert_runs`, `packages/nurl-cert/src/caps.nu`). The scan
is generous: every `.dtor f` counts. The kernel does not trust it. A list
that is not closed is no claim, and `C.caps_witness_open` shows the check
refusing one.

**What each of those functions may do: the core IR and a table.** The
term has no events. The library's calls are A2's constructs, and a write
to standard output is no step of the model. So the classes are read off
the core IR. For each function of the program, certify follows every call
it makes, through the library's bodies (and a `dyn` method's impls, from
the `virt` lines), down to the runtime's functions. Each runtime function
is classed by the capability table `stdlib/caps.tsv`, which the bundle
copies as `caps.tsv`. A function that may panic inline (`fn` flag bit 3)
has `panic`. The claim's classes are the union over the list.

The classes outside the process are `stdio.out`, `stdio.err`, `stdio.in`,
`fs.read`, `fs.write`, `fs.meta`, `net.connect`, `net.listen`, `net.dns`,
`net.io`, `fd`, `proc.exec`, `proc.signal`, `sys.info`, `env`, `args`,
`clock`, `random`, `thread`, `device`, `exit` and `panic`, plus
`ffi.unknown` for a runtime function the table has no row for. `compute`
and `mem` stay inside the process. The sentence lists what it can do and
what it never does, from fixed phrases:

> Outside its own memory it can only: write to standard output. It never:
> write to standard error; read standard input …; read files; …

A program that reaches an `ffi.unknown` function gets no "never" list:
that function could do anything, so its sentence lists what it can do and
ends "Its effects outside its own memory are not bounded."

Two halves mean two kinds of trust, and the premises name both. The list
is a theorem. The classes rest on the table (`caps-table`: the C runtime
and the OS do what the table says) and on the core IR's calls being what
each function does (`caps-attribution`). Their meaning for the binary rests
on `M.safe` (`caps-binary`: a run that broke memory could call anything),
and on every hand-vouched place (`unsafe-<n>`: an `unsafe` function may
call anything). Enforcing a proved absence by the platform (seccomp,
Landlock, a wasm import list) is AGORA-1025.

**A conditional bundle** (AGORA-1033) holds a stub at each assumed
function, which names the functions the real one calls. `Cert.n_cap` is
then about the program with its stubs, and N.cap is `assumed`, as its M
claims are, on each assumed function's row (`assumed-fn:<name>`). The
assumed function's own classes are read off its real calls in the core
IR, as any other's are, so a program with a call the translation does not
cover (a `nurl_print`, a file write) still gets the class of it.

For every class, `capabilities.classes` gives one shortest chain of calls
from a function of the list to the runtime function that has it, each
step `name (file:line)` of its call, so a reader sees why a class is
there.

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
  Caps.lean       N.cap: the functions a run can enter (Cert.runs), the kernel's check that
                  the list is closed, and Cert.n_cap; only when Lean proves it
  caps.tsv        the capability table the classes were read with (stdlib/caps.tsv);
                  beside Caps.lean
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
  - for a deep term only, a third line `set_option maxRecDepth <n>`, with
    `n` exactly the bound the term's own nesting depth asks for
    (`cert_rec_depth`: 2 × the deepest nesting of parentheses + 128, where
    that is above Lean's default of 512). A2 nests each statement over the
    rest of its list, so a long body is a deep term, and Lean's elaborator
    stops at its default bound (AGORA-1034). The line bounds only the
    elaborator's recursion. It is a function of the term, and any other
    value, any other option, or the line on a term that does not need it,
    is refused;
  - `def fn<k> : Fn := …`;
  - `def P : Prog := [fn0, …]`;
  - `def entry : Stmt := .letcall 0 <k> [] .skip`;
  - for a threaded program, `def spawns : List Nat := […]`;
  - for a conditional certificate (AGORA-1033, AGORA-1035), `def assumed : List Nat := […]`
    (the indices of the assumed functions, each holding a stub `.seq s .panic`
    whose signature, callees and `hasThru` come from the core IR; `Claims.lean`
    imports `C.Complete`, decides `C.certOK2BA P assumed entry 1` — or
    `C.certOK3BA P spawns assumed entry 1` for a threaded program — and states
    `M.safe` and `M.leak` (and `M.race` for a threaded program) over every
    completion `P'` satisfying `C.Completes` and `C.AssumedOK` / `C.AssumedOK3`;
    each assumed function has a trust-ledger row `assumed-fn:<name>` and the
    memory-safety claims take status `assumed`);
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
  `vec_truncate`, `vec_reserve`, `string_push_str`; closures over numbers
  and buffers of numbers, their literals and calls through them; options
  and structs of those types, their literals, a struct's fields read
  through its pairs, an option's match; and structs with a `% Drop` of
  the program's own whose fields are of those types (raw text in a field
  a view), each value bound by a destructor frame (`.letd`) in a
  function's body: not handed back, assigned, returned by a call, given to
  a `sink` or `inout` parameter or held in another value; channels of
  numbers, `String`s and `Vec`s of numbers; and threads, A3's programs:
  spawned closures holding those by value, their spawns, joins and
  results, `C.Elab.elabIR3`, which builds the spawn wrappers too;
  `docs/dev/TRANSLATION_TRUST.md`, route (b), steps 2 and 4 to 10). Every
  certify program is in it. It is a pure function of
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

  A threaded program's (its Program.lean names its `spawns`) is
  `theorem «elab» : C.Elab.elabIR3 ir = some (P, spawns, entry) :=
  C.Elab.elabIs3_sound _ _ _ _ (by decide +kernel)`.
  (`elab` is a keyword of Lean, hence `«elab»`; Lean prints the name
  `Cert.elab`.)
  - The words are `nurl-cert words` (`packages/nurl-cert/src/words.nu`).
    Every word is a number (nurl-cert 0.4.0): `nat_lit 0x1`, then the
    word's bytes from its last to its first, two hex digits each, so
    256^k + Σ bᵢ·256^i for its k bytes. `C.Elab.wordOf` reads it back into
    the bytes (`wordOf_encB`, for every list of bytes), whatever they are:
    there is no escaping, and the file is ASCII. A core IR with a NUL byte
    has no words (they are made from the text up to the first NUL), and
    its bundle no Elab.lean. Until 0.3.0 every word was a string literal,
    and a core IR that was not well-formed UTF-8 had none; the numbers
    cost the kernel far less (`docs/dev/TRANSLATION_TRUST.md`, "the words
    as numbers"). A 0.3.0 bundle with Elab.lean does not verify with
    0.4.0 (`verify` makes Elab.lean again, and it is another file now):
    certify the program again.
  - A `sum` line outside every function is left out of the words when its
    name is none of the words of the other lines kept (0.4.0): `elabIR`
    looks a summary up only by a function's name, a callee's name or the
    function a `let … call f` calls, all of them words of those lines. A
    `sum` line with no name is kept (the reader refuses it), and so is one
    inside a function (a statement of its body, which `elabIR` refuses).
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
    `elabIR`'s, so Lean is not asked: that skip is exact. Neither can a
    term that holds `.callc` or `.pack` (`ELAB_CLO_CTORS`) but no `.fn`:
    `elabIR` builds those only for a variable of a closure type, and every
    closure type has an interface whose first parameter is a `.fn`. (Until
    step 7 the list also held `.pair .fst .snd .prod`, which skipped a
    struct's term; a struct's term is now one `elabIR` builds.) For every
    other term Lean decides.
  - The bundle keeps Elab.lean when the checker accepts the program, Lean
    exits 0, and `Cert.elab` rests on the standard axioms only. Otherwise
    it is deleted, and the bundle is as before, its term the translator's.
  - With it, `M.safe` and `M.leak` are about the term the kernel built
    from Program.core's words. The `translation` row is replaced by what
    is left of it: `core-ir-words` (nurlc's core IR and the split into
    words) and one row per encoding the term uses (`enc-…`, below).
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
    `import C.Cert` and `open A2 C`, exactly, a deep term's
    `set_option maxRecDepth` with the one value its depth asks for, then
    definitions: no other option, notation, instance, namespace or
    attribute. So its definitions read
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
schema      "nurl-cert/2"
tool        { name, version }
profile     "kernel" | "fast"
program     { source, verdict: accepted | refused | unsupported | error, reason, slots }
claims      [ { id, lean, status, sentence { en, fi }, reason, axioms [..], premises [ledger ids] } ]
            M.safe, M.leak, (a threaded program) M.race, M.unsafe, then N.cap, in this order
coverage    { functions: [ { name, file, line, status, reason } ], <status>: count }
hashes      { sources: [ { path, sha256 } ], core_ir, llvm_ir?, program_lean?, claims_lean?,
              elab_lean?, caps_lean?, caps_tsv?, binary?: { path, sha256 } }
capabilities? { runs [..], functions: [ { index, name, classes [..] } ],
              classes: [ { class, chain [..] } ] }      (N.cap proved)
versions    { nurlc, formal_tree, formal_commit, lean_toolchain }
ledger      [ { id, what, why, where, vouches, claims [..] } ]
```

- `program.verdict` `refused`: the checker refuses the program. Lean says
  so when it explains a failed `decide +kernel` ("… is false"), by reducing
  the proposition again in the elaborator. Where that explanation fails
  too, on a term too deep for the elaborator, only the kernel's own
  mismatch is left, and it would also be what a reduction that got stuck
  leaves. So certify then proves the refusal in a Lean run of its own
  (`C.certOK2B P entry 1 = false`, or A3's, by `decide +kernel`). The
  reason then reads `… is false, proved by the kernel`, and without that
  proof the verdict is `error` (AGORA-1034).
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
  and records the case: with it, the ledger has `core-ir-words` and the
  encodings' rows in place of `translation` (below), and verify requires
  the file.
- **Schema.** `nurl-cert/2` (AGORA-1033) adds conditional certificates
  (`def assumed : List Nat := […]` in `Program.lean`, `C.certOK2BA` and
  `C.Completes`/`C.AssumedOK` claims in `Claims.lean`, `assumed-fn:<name>`
  trust-ledger rows, and `assumed` status on `M.safe`/`M.leak` when any
  function is assumed), and (AGORA-1013) `N.cap` after `M.unsafe`, with
  `capabilities`, `hashes.caps_lean` and `hashes.caps_tsv`. Bundles written
  under `nurl-cert/1` must be re-certified with `nurl-cert certify`.
- `capabilities`, `hashes.caps_lean` and `hashes.caps_tsv` are present
  exactly when N.cap is proved (or, in a conditional bundle, `assumed`).
  Otherwise N.cap is `open`, its sentence says it is not claimed, and it
  rests on `claim-definitions` alone. `capabilities.runs` is Caps.lean's
  list; `functions` gives each of the program's functions in it with the
  classes its calls reach; `classes` gives each class of the claim with
  its chain.
- `versions.formal_tree` is the sha256 of a listing with one line
  `<sha256>  <path>` per file of `formal/`, in byte order of the paths:
  every `.lean` file, plus `lakefile.toml`, `lean-toolchain` and
  `lake-manifest.json`, and not `.lake/`. `verify` refuses another tree.
  `formal_commit` is informational.
- `coverage.functions`: the program's own functions in the core IR (not
  the standard library's), each with its own status (AGORA-1015):
  - `unsupported`: the translation does not cover it, and `reason` says
    why. The translation goes on past such a function, so every one of
    them is listed, not only the first. The program is still refused with
    the first one's reason: the claims of a program with an unsupported
    function are `open`.
  - `error`: the translation stopped on an internal error in it, or did not
    reach it after one (`reason` names the function it stopped in).
  - `open`: the translation covers it, but not the whole program, so no
    claim is proved for it (`reason`: `translated; the program is not: …`).
  - otherwise the program's: `proved` or `validated` when it is accepted,
    `refused` when the checker refuses it.

  The counts beside `functions` are per status. `nurl-cert coverage DIR`
  sums the bundles `DIR/*.cert` into one Markdown table: the programs by
  verdict, the functions by status by count and by the source lines they
  span, and the reasons of the unsupported ones, most frequent first.

### The trust ledger

One row per thing the claims rest on and do not prove:

| id | what |
|---|---|
| `lean-kernel` | the Lean 4 kernel and the pinned toolchain |
| `lean-compiler` | (profile `fast` only) the Lean compiler, which computes the verdict |
| `claim-definitions` | the claims' definitions, A2's semantics (`formal/CLAIM.md`) |
| `translation` | (without Elab.lean) the step from source to term, `nurlc --emit-core`, then nurl-cert's translator (`packages/nurl-cert/src/tolean.nu`) |
| `core-ir-words` | (with Elab.lean, in place of `translation`) `nurlc --emit-core` and the split of Program.core into words (`words.nu`; verify makes Elab.lean again from Program.core); the term itself is the kernel's (`Cert.elab`) |
| `enc-…` | (with Elab.lean) one row per encoding of `C.Elab.elabIR`'s the term uses, how a part of the core IR is read as the calculus, each argued by its design note (`docs/dev/TRANSLATION_TRUST.md`, "The encodings"): `enc-numbers` (always), `enc-raw-text`, `enc-shapes`, `enc-destructors`, `enc-closures`, `enc-threads`, `enc-channels`, `enc-summaries` (the walk's summaries read into the term). Certify and verify read which off Program.lean's constructors (`cert_enc_ids`), generously: a row may be named where its encoding is not used, never left out where it is |
| `library-summaries` | the standard library as the term has it, A2 primitives and declared summaries; the models follow the library by inspection (AGORA-1014) |
| `llvm`, `linker`, `os`, `c-runtime` | the path from the IR to a running binary |
| `drf-sc` | (a threaded program) the C11 / LLVM memory model's DRF-SC guarantee, for `M.race` |
| `unsafe-report` | `M.unsafe` is what nurlc's `--unsafe-report` says |
| `unsafe-<n>` | one row per line of that report: each `unsafe` function, `unsafe % Send` / `% Sync` assertion and foreign-declaration claim of the program; with N.cap proved, each backs N.cap too |
| `caps-table` | (N.cap proved) the capability table, `stdlib/caps.tsv`: what each runtime function does |
| `caps-attribution` | (N.cap proved) the core IR's calls as what a function does, through the library's bodies |
| `caps-binary` | (N.cap proved) the binary does only what its model does, which rests on `M.safe` and the code generator |

A bundle with no `unsafe-<n>` row and `M.unsafe` assumed has no
hand-vouched code of its own. Apart from the translation (its core IR,
words and encodings, with Elab.lean), it rests only on the toolchain and
the library. Each claim's premises name the same rows.

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
- with N.cap proved: the hashes of Caps.lean and caps.tsv; the list, the
  classes and the chains made again from the bundle's own Program.lean,
  Program.core and caps.tsv, against `capabilities`; Caps.lean against
  the template over that list, byte for byte; N.cap's sentences against
  the classes made again. Without it: no Caps.lean and no `capabilities`,
  and N.cap open;
- that Lean checks Program.lean and Claims.lean again, and, with
  Elab.lean, that it proves `Cert.elab` again with the standard axioms
  only, and, with Caps.lean, that it proves `Cert.n_cap` again. Lean is run only when every check above passed: it runs code
  while it elaborates a file, so a file the grammar, the template or a
  hash refused is never handed to it. A run counts only when Lean exits
  0;
- for each claim, that the manifest's status and axioms are what Lean
  reports now;
- that `M.unsafe` is `assumed` (or `open` with no LLVM IR);
- that N.cap follows M.unsafe, and that nothing is claimed beyond it.

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
  hash updated; code put in it (Lean never runs it);
- in a bundle with N.cap: the list emptied in Caps.lean and the manifest;
  caps.tsv edited (a print called pure), its hash updated or not; a class
  dropped from `capabilities`; the sentence edited; Caps.lean removed
  with N.cap still proved; Caps.lean's check weakened. And, outside verify,
  the kernel itself refuses a list that leaves out a function the program
  calls (`Cert.runs_closed`).

Seeded programs get exactly the classes their reachable calls have: a
print in `main`, behind a closure, in a destructor and in a spawned
thread is claimed, and a print in a function nothing calls is not (the
function is not in the list).

A bundle downgraded honestly verifies: Elab.lean removed, its hash
dropped, and `core-ir-words` and the encodings' rows the translator's
`translation` row again, in the ledger and in each claim's premises.
That is expected. It is the weaker bundle, and its ledger says so. With
the kernel's rows kept, it does not verify.

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
7.2 s faster: 81.3 s against 80.8 s (+0.6 %). Step 6 covers the 13
closure programs, which now each have an Elab.lean part (+0.19 to +0.63 s
a program; 5 of them are refused, and spend it too), and prints the words
as numbers, not string literals (the kernel builds a string literal's
bytes one `push` at a time, quadratic in its length), and leaves out the
`sum` lines no other word names: the other 49 are 5.6 s faster, and in
all certify takes 77.1 s against 77.8 s (−0.9 %). Step 7 covers the 6
struct and option programs, which now each have an Elab.lean part (+0.11
to +0.39 s a program; 2 of them are refused, and spend it too), and makes
`elabIR` cheaper (a drop's check read as bits, a list's `ret` looked for
once): the other 56 are 1.55 s faster, and in all certify takes 80.0 s
against 80.2 s (−0.2 %). Lean is asked only for a term that can be
`elabIR`'s; `docs/dev/TRANSLATION_TRUST.md` (steps 3 to 7 and "the words as
numbers") has the numbers, peak memory included.

N.cap costs 2.9 % of certify's time and 0.4 % of its peak memory. Over the
62 certify programs, one at a time, best of 2 alternated runs against the
nurl-cert of main b44ed757, both against the same `formal/` tree, certify
takes 62.7 s against 61.0 s. The sum of the peak RSS is 41.57 GB against
41.38 GB, and the largest peak is 2.53 GB against 2.52 GB. The time is the
kernel's check of the list and Lean elaborating Caps.lean (about 20 ms a
program), and certify's reading of the core IR's calls (about 7 ms). A
single-threaded program's Caps.lean imports `C.Caps`, which loads no A3:
with the threaded theorem in the same module, the peak RSS sum was +5.4 %.

Without `--certify`, nothing changes:
- `--list-sources=TAG` is off by default;
- 2120 programs compile byte-identical (compiler/tests, the certify
  programs, examples);
- the self-compile is neutral within codegen noise: +0.056 % instructions
  at -O2 (25.669 G → 25.683 G) and −0.07 % at -O0, where layout does not
  count (84.321 G → 84.261 G), with the same peak RSS (186 MB). Both
  compilers were built by the same compiler and link.
