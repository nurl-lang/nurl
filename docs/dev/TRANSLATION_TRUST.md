# Taking the translation out of the trusted path

Status: **design** (AGORA-1020 part 2). Part 1, the translator in NURL
(`packages/nurl-cert/src/tolean.nu`, byte-identical to tolean.py over
4300 core IRs), is what certificates are made with. This note decides how the step from nurlc's core IR to the
Lean term stops being trusted.

## The problem

A certificate (docs/dev/CERTIFICATE.md) proves `M.safe` and `M.leak` about a
term `P` of formal/A2. Something makes `P` from the core IR text that nurlc
prints (`--emit-core`). Today that is a program outside the kernel: first
`tools/ncore/tolean.py`, now its NURL port. It is the bundle's `translation`
ledger row, and `verify` can re-run it (`--rebuild`), but nothing checks that
it is right. If it mistranslates, the theorem is true of a program nobody
runs.

The translator also chooses encodings that carry meaning, and each one could
let a must-reject program through if it were done wrongly (AGORA-994's
closing notes). The list is below.

## The two routes, measured

Both routes move the encodings into Lean definitions, which the kernel
evaluates. They differ in what the untrusted side hands to Lean.

**(a) `parseCore : String → Option Prog`.** The certificate holds the `.core`
text as a Lean string literal, and the kernel parses it.

- Measured on `vec_push_len.nu`'s core IR (9523 bytes, 17 functions;
  `tools/ncore/trust/measure.sh` reproduces it).
- `String.splitOn` and the rest of `String`'s library do not reduce in the
  kernel: `decide +kernel` gets stuck at the first split.
- A parser by structural recursion over `String.toList` reduces, but the
  kernel's recursion depth is fixed. One line split over 9.5 K characters
  fails with "(kernel) deep recursion detected", which `maxRecDepth` does
  not change.
- A tail-recursive scan in chunks would avoid that. It would still walk
  every character of every function the program imports: the core IR of a
  one-line program is 9.5 KB, because the library's functions come with it.

Verdict: not viable as the per-certificate path.

**(b) `elab : CoreIR → Option (Prog × Stmt)`.** The untrusted side prints the
core IR as plain Lean data, one entry per line, each line its list of words
(`List (List String)`). A Lean function builds the calculus term from it.

- Measured on the same program: the 1400-line data literal elaborates, and a
  kernel `decide` over it (a filter that compares words) checks, in 1.1 s
  wall in all, against 0.3 s for an empty file.
- Word comparison is `String` decidable equality on literals, which the
  kernel reduces.
- Reading a number out of a word (`v42`, `123`) has to use `elab`'s own
  structural functions over `String.toList`, which reduce. Lean's
  `String.toNat?` gets stuck in the kernel, as `splitOn` does.
- The only untrusted step left is printing the literal: splitting each line
  at tabs (header lines) or spaces (statements). `nurl verify` checks that by
  splitting the bundle's `Program.core` again and comparing with the
  literal. That step is a dozen lines, the same in the NURL printer and the
  verifier, and it makes no choices.

Verdict: **route (b)**.

| | (a) parseCore | (b) elab over words |
|---|---|---|
| trusted code left | none beyond the kernel, if it could run | the line/word split (≈ 12 lines), checked by verify |
| kernel time, `vec_push_len` | does not finish (stuck / depth) | ≈ 0.8 s over the empty-file baseline for the data, plus `elab` itself |
| where an encoding is reviewed | a Lean definition | a Lean definition |
| what phase D links to | the `.core` text | the same text, split into words (one-to-one) |

`elab`'s own kernel cost is not measured yet: it does what the NURL
translator does, on words. The NURL translator's output is a term of about
the same size as the data, and `certOK2B` over it already costs 0.39–1.05 s
per certify program. So `elab` is expected to stay in that range. It is to
be measured on the corpus when `elab` exists (AGORA-1020 part 2b).

## The certificate under route (b)

```lean
def ir : List (List String) := [...]        -- Program.lean: the core IR, as words
theorem verdict : C.certOK2B' ir 1 = true := by decide +kernel
-- certOK2B' ir nv := match elab ir with
--   | some (P, s) => certOK2B P s nv | none => false
theorem m_safe : ∀ P s, elab ir = some (P, s) → ∀ m' s', Steps P (emptyMem 1) s (.ok m' s') → ¬ Stuck P m' s'
```

The claims then say "the program `elab` makes of this core IR". The
`translation` row is replaced by two rows:
- `core-ir-words`: the printing, checked by `verify`;
- `elab-encodings`: the encodings below, as Lean definitions with design
  notes, until the core IR has a semantics.

## The encodings, and where each is argued

The core IR has no semantics of its own. `CORE_IR.md` calls it formal/A2's
statement language, extended where NURL has more. Giving the extensions a
semantics, and proving each encoding against it, is the full answer: it is
also what phase D needs to link the LLVM validators to A2. Until then, each
encoding is a ledger row with a design note. The decisions:

| encoding (tolean.py / tolean.nu) | what it says | argued by |
|---|---|---|
| scalars → `.int`; an untracked number (`c`) → `Expr.any`; a computation over tracked operands `e` → `(.add .any (.lt e (.lit 0)))`, any number with `e` still read | a number's value is no part of the memory model, and the model's runs must include the program's whatever its numbers (AGORA-1030: `.lit 0` made the model take every if's else arm) | design note, A2's `Ty.int` and `Eval.any`; `C.ite_any_both` shows both arms are runs |
| a raw string bound from a literal or a fresh string → `(.vec .int)`; held in a value → `(.slice .int)` | owned text vs a view (MEMORY.md §1, §2.13) | ledger row; needs the IR's own provenance flag to be proved |
| options → `sum int t`; structs → nested `prod`, one field = the field | layout-free shapes | design note (shapes only, no ownership choice) |
| destructor types → `.dtor f u`, a one-field struct padded with an int | `% Drop` runs `f` at the end of every value | design note + A2-drop's theorems |
| closures → `.fn [σ] .any`; captures by name vs in the environment (`CORE_VF_ENVOWN`), mode `inp` / `(.inout .drop)` | a capture by name is a dependency on the binding (MEMORY.md §2.11) | ledger row (the mode choice is precision, the code is checked against it, but by-name vs by-value is meaning) |
| a spawned closure → an interface of class `.send`; the spawn → A3's spawn-only `letcall` of a wrapper `[(.sink, .fn [m] .send)] → .int` that calls it; the join → a read; `Thread` / `ThreadErr` → `.int`; `!T E` → `sum E T` | a spawn moves the closure to a new thread; its captures are held by value (no view, no name, no destructor value); `thread_spawn_owned` always succeeds | ledger row: the spawn's failure path is outside the model; the closure is moved, where nurlc copies its environment (a reuse after the spawn is unsupported, not refused) |
| channels → `lk (prod (vec A) int)`; `Channel_share` → `lockClone`; a channel bound from another binding → a move | A3.4's channel; one owner per handle (nurlc) | design note, `Ty.ChanOf` |
| `sink=` / `keeps=` summaries → `sink` | the callee owns what nurlc's caller does not drop (AGORA-994) | ledger row: it reads the walk's summary, which is nurlc's |
| a borrowed result (`rviews`) → `(.slice .int)` + `lends` | the result views its parameters | ledger row: it reads the walk's summary |
| a mutable cursor → a borrow; a loop element → `.view` / `.sat` | AGORA-994's families | ledger row; AGORA-1009 changes these |
| library calls → A2 primitives (`push`, `len`, `new`, …) | phase B's models | the `library-summaries` row (AGORA-1014) |

The rows that read nurlc's own summaries are the weakest. In them the
certificate trusts the compiler's walk, which it is meant not to need. The
engine computing those summaries itself (AGORA-877) is what removes them.

## Reproducing the measurements

```sh
tools/ncore/trust/measure.sh [prog.nu]   # default: tools/ncore/certify/vec_push_len.nu
```

The script writes the scratch files of both routes from the program's core
IR into a temporary directory and times each with `lake env lean` in
`formal/`:
- `E`, an empty file: the baseline;
- `A`, the text with `String.splitOn`;
- `A2`, the text with a structural scan;
- `B`, the IR as words.

It needs `build/nurlc`, `python3` (to write the scratch files only) and
`lake`, with `formal/` built. Measured here:

```
core IR: 9523 bytes, 17 functions
E:  0.28 s, 466 MB
A:  stuck: "(countFn irText).beq 17"                 0.32 s
A2: (kernel) deep recursion detected                2.43 s, 798 MB
B:  checks                                          1.10 s, 527 MB
```

## Threads (done, AGORA-1020)

A program that calls `thread_spawn_owned` is translated for A3 and gets
`M.race` with `M.safe` and `M.leak` (CERTIFICATE.md §1).
- The checker's closure literal now takes the class the literal's
  interface declares, where it fits (`C.packClass`, C8p). A spawned
  closure's interface is of class `send`; every other closure keeps
  `any`, so no verdict changed (all 4505 probes compared).
- One encoding was caught being wrong while this was built: a channel
  bound from another binding (`: ( Channel i ) tx ch`) had been read as a
  new share. nurlc moves it (one owner), and with the share reading a
  program nurlc rejects certified. It is a move again. The program is now
  a refused certify program (`thread_channel_read_after_an_alias_took_it_refused`).
  This is the class of error the per-encoding rows above exist for.

## Route (b), step 1 (AGORA-1029)

- `nurl-cert words prog.core` prints the core IR as `def ir : C.Elab.IR`:
  one list of words per line, header lines (`fn`, `v`, `ty`, `sum`) split
  at tabs, statements at spaces and tabs.
  `packages/nurl-cert/tests/translate_test.sh` checks that its output is
  exactly the lines' split for every certify program.
- `formal/C/Elab.lean` reads those words in the kernel. `natOf` and
  `varOf` work by structural recursion over the characters; `fnsOf` gives
  the functions, their variables and their statements, and fails closed on
  a function left open or an `endfn` with none open.
- Measured: `vec_push_len`'s whole IR (17 functions with the library's,
  588 lines of data) is read and checked by `decide +kernel` in 1.2 s.
- Next: the translator's rules as Lean definitions over `CoreFn` (step 2,
  the scalar subset first), then the claims stated about `elab ir`.

## Route (b), step 2: the scalar subset (AGORA-1029)

- `C.Elab.elabIR : IR → Option (Prog × Stmt)` (formal/C/Elab.lean; `elab`
  is a keyword of Lean) builds the term and the entry statement for the
  **scalar subset**: every function of the program (its file is not the
  standard library's, as tolean.nu selects them) has only number-typed
  variables, parameters and result (`__int_ty`: `i64` … `u8`, `void`,
  the floats), and statements among `scope` / `if` / `else` / `loop` /
  `loopcond` / `end`, `line`, `drop`, `break`, `continue`, `let k
  use|none|scalar …`, `eval scalar|use|none …`, `assign vK
  use|none|scalar …`, `ret c|-|vK`, and `let` / `eval` of `call f …` where
  `f` is a function of the program. Anything else is `none`.
- It is tolean.nu's rules for that subset, in tolean.nu's order: a `let`
  or an `eval` translates the rest of its list before its own right-hand
  side, a loop its body before its condition, so the fresh temporaries are
  numbered as tolean.nu numbers them. The statements are first read into a
  tree (blocks closed, fail closed otherwise); the translation is
  structural recursion over a fuel of 4 × the body's lines + 4 (the `ret`
  at a list's end rebuilds the list, as tolean.nu does).
- Stricter than tolean.nu, never laxer: a count or an id that is not plain
  digits, two program functions of one name, a program function named as
  a library call tolean.nu makes a construct of (`vec_push__…`,
  `nurl_println_int`, …), and any destructor type (a `ty` line whose drops
  say `d`, a `drop__` function) are refused. The `ty`, `virt` and `sum`
  lines are read only for that `d` and for the summary keys the subset
  needs (`sink`, `keeps`, `retdyn`, `ret_owned`, `ret_unowned`, `rviews`).
- `C.Elab.elabIs ir P e` compares the result with a term (A2's `Stmt`
  has no decidable equality: its run-time forms hold a store);
  `elabIs_sound` makes a `true` the equation `elabIR ir = some (P, e)`.
  `elab_while` is one, by `decide +kernel`, against the term tolean.nu
  prints for `while_loop_summing`, written out.
- `tools/ncore/elab_parity.sh` compares `elabIR` with `nurl-cert
  translate` over every certify program, every hole probe and the 18
  scalar programs of `tools/ncore/elab_scalar/` (written for it: calls,
  `inout` and `sink` parameters, `void` functions, nested loops, `break`,
  `continue`, returns from inside loops and arms). A parity test, not a
  proof. Of 4527 programs nurlc makes a core IR of 4322; tolean.nu
  translates 247; `elabIR` answers a term for 21 (the 3 scalar certify
  programs, `while_loop_summing`, `int_recursion_early_return`,
  `loop_with_continue_and_break`, and the 18), every one exactly
  tolean.nu's term, each also checked by `decide +kernel`; it answers
  `none` for the other 4301, and a term for no program tolean.nu
  refuses. 90 s in all with 12 jobs (`elabIR` itself runs over every IR
  in one Lean process, from JSON: Lean takes ~10 s to elaborate an
  8000-line words literal).
- Kernel time, `decide +kernel` of `elabIs ir P entry` over the file that
  only defines the data and the translator's term (best of 5):
  `while_loop_summing` 0.19 s, `int_recursion_early_return` 0.27 s,
  `loop_with_continue_and_break` 0.31 s. Outside the subset `none` costs
  0.15 s for `vec_push_len` (588 lines) and 2.7 s for an 8087-line IR
  (`chacha20poly1305_open_in_offset_wraps_its_range_check`, mostly the
  library's functions, which step 1 reads too).
- What the kernel spends its time on is turning words into characters: a
  string literal's `toList` decodes its UTF-8 bytes at ~4 ms a character.
  The words are therefore read as bytes (`bytesOf`, a third of the cost;
  `natOf` and `varOf` of step 1 too), and the texts they are compared
  with are written as lists of byte values, each checked against its
  text. Before that the three programs took 0.47, 1.07 and 0.65 s, and
  the 8087-line IR 16 s. Printing the words as numbers rather than
  strings would take the rest of that cost away.
- Next: the subset widened rule by rule (strings and `Vec`s of numbers,
  options, structs, the library calls, closures), each with its rows of
  the table above; then the certificate's claims stated about `elabIR ir`.

## Route (b), step 3: the bundle's term checked by the kernel (AGORA-1029)

- For a program in the scalar subset, a certificate bundle no longer
  trusts the translator (`tolean.nu`). One more bundle file
  (docs/dev/CERTIFICATE.md §2), `Elab.lean`: Program.core as words
  (`nurl-cert words`, `noncomputable def Cert.ir`) and
  `theorem Cert.elab : C.Elab.elabIR ir = some (P, entry)`, by
  `elabIs_sound` and `decide +kernel`. It is a pure function of
  Program.core.
- The claims stay about `P` and `entry`, Program.lean's term. With
  `Cert.elab` that term is `elabIR`'s of the words: the claims are about
  "the program `elabIR` makes of this core IR", as the design above has
  it, without a second form of the claims.
- **What is out of the trusted path**, for those programs: the
  translator, and with it every encoding the subset uses (scalars as
  `.int`, untracked numbers as `.any`, calls, loops, `break`, `continue`,
  returns). They are now `C.Elab.elabIR`'s definitions, which the kernel
  runs.
- **What is still trusted**, the `translation` ledger row, reworded for
  such a bundle:
  - `nurlc --emit-core`: that the core IR is the source's;
  - the split into words (`words.nu`). `verify` makes Elab.lean again
    from the hashed Program.core and compares it byte for byte. Every word
    is a string literal (`"` and `\` escaped, bytes below 32 as `\x..`).
    A core IR that is not well-formed UTF-8 has no words, since Lean reads
    such a byte as U+FFFD;
  - that `elabIR`'s rules give a core IR its meaning. They are
    definitions in formal/, reviewed, not proved against a semantics of
    the core IR, which does not exist yet.
- **Which programs.** Lean decides. certify asks it for every program
  whose translated term can be `elabIR`'s at all: a term holding a
  constructor `elabIR` never builds, or `true`, cannot equal its term
  (`elabIs` compares constructor by constructor), so for it Lean is not
  asked. That skip is exact: it is read off `elabIR`'s codomain
  (`ELAB_CTORS` in packages/nurl-cert/src/claims.nu; formal/C/Elab.lean
  says above `elabIR` that a new constructor goes into that list too), not
  off its rules. The bundle keeps Elab.lean when the checker accepts the
  program and Lean proves `Cert.elab` on the standard axioms; otherwise
  it is deleted, and the bundle is as before. Of the 62 certify programs,
  3 get Elab.lean: `while_loop_summing`, `int_recursion_early_return` and
  `loop_with_continue_and_break`. The selftest's sweep requires exactly
  these 3, so a stale constructor list fails CI rather than silently
  dropping the stronger bundle.
- The manifest records the case by `hashes.elab_lean`, and the
  `translation` row's text follows it. The schema stays `nurl-cert/1`: a
  bundle without it, an older one included, verifies with the
  translator's row. A bundle downgraded honestly (Elab.lean removed, its
  hash dropped, the row the translator's again) verifies too. That is
  expected: it claims less, and its ledger says so.
- **Tested** (`packages/nurl-cert/tests/nurl-cert_test.sh`, part 2b):
  another scalar program's Program.lean swapped into a subset bundle,
  with its hash updated, now fails a plain `verify`, on `Cert.elab` alone.
  Before, only `verify --rebuild` caught it. So do Elab.lean deleted with
  the manifest kept, and its words or its theorem edited. Part 2c holds
  the words to string literals: quotes, backslashes, `-/`, `/-`, a
  would-be `axiom`, control characters and non-ASCII read back as their
  bytes, and five byte sequences that are not UTF-8 have no words.
- **Cost.** Measured over the 62 certify programs, one at a time, best of 3,
  before and after run in turn on the same x86-64 host: certify takes
  79.2 s against 78.6 s before (+0.8 %, within the runs' spread of
  ±1.2 s). Three things keep it there:
  - the skip above: the 33 accepted programs outside the subset and every
    refused one get no Elab.lean and no Lean run of it;
  - one file, one Lean process: the words and the theorem are elaborated
    together (a separate words module cost another start-up, ≈ 0.25 s,
    and an olean written and read);
  - Elab.lean is checked by a second Lean process beside Claims.lean,
    against the same Program.olean, so the two overlap.
  For the 3 programs in the subset the check costs 0.6 s of Lean, most of
  it hidden behind the claims' check. Elaborating the words costs ≈ 1 ms
  per core IR line (the list literal itself: other spellings are no
  faster; `noncomputable` saves the code generator's 0.25 s on 600
  lines). Without the skip, certify took 72 % longer: most programs'
  core IR carries hundreds of lines of the library's functions.

## Next

**`elab` in Lean (route b)**, in formal/C/Elab.lean: the translator's
rules over words. Done: the claims rest on `elabIR` for the scalar
subset, and `verify` checks the words against `Program.core` (step 3).
Then:
- the subset widened rule by rule;
- the per-encoding rows above replace `translation`;
- kernel time is measured on the corpus;
- `elab`'s parity with the NURL translator is shown over the sweep.
