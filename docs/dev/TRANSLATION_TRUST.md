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
  scalar programs of `tools/ncore/elab/` (written for it: calls,
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

## Route (b), step 4: buffers of numbers (AGORA-1029)

- `elabIR` covers the **Vec family** too: a variable, parameter or result
  may be a buffer of numbers, A2's `.vec .int`. That is raw text (`i8*`,
  owned: bound from a literal or a fresh string), a `String`, or a `Vec`
  of a number type (`bufTy`). The constructors it builds, beyond step 2's,
  are `.push .free` (Stmt), `.new .var .borrow .at` (Rhs), `.len` (Expr),
  `.vec` (Ty), `.drop .realloc .dropIn` (a parameter's `inout` bound) and
  `resOwn := true`. They are tolean.nu's rules for what it does with
  buffers:
  - a `use` of a buffer moves it (`.var`), or is a cursor's borrow
    (`.borrow`: a `: ~` binding of a binding or a parameter). A literal
    bound to raw text is a copy of its own (`.new .int`). A borrowed
    parameter assigned to an `inout` one is copied (its length read into a
    fresh variable, then `.new`);
  - the library calls `vec_new`, `vec_push`, `vec_len`, `vec_at` (a number
    element, `.at`), `vec_free` and `string_free` (`.free`), `string_from`,
    `string_len`, `nurl_str_cat` and `nurl_str_len`, in the translator's
    order of fresh numbers (`intrS`). A raw-text literal handed to a
    program function's `i8*` parameter is a buffer of the call's own;
  - a buffer's `ret` moves it into the result slot. A buffer parameter
    that is neither `sink` nor `inout` is `inout` at the bound the walk's
    summary gives (`drops`, `reallocs`, `ireallocs`, `mutates`), as
    `__mode` has it;
  - a buffer's `drop` is the end of its scope, as in the translator,
    which takes that to be so only if no line after the drop names the
    buffer or a variable that views it (`__views_of`). `elabIR` makes the
    same check, over the same lines (every word of every later line of
    the body, cut at its `/`s, the lines the translation passes over
    included), with the same closure of views (`viewsOf`: an element read
    out of the Vec by a `let … call vec_at…`).
- **Fail closed.** Each check the translator makes on these constructs is
  made too, with a kernel witness of its refusal and of its well-formed
  neighbour (formal/C/Elab.lean, "step 4"): an owner given a borrowed
  parameter's value, raw text assigned from another binding, an owned
  result aliasing a parameter (`ret_alias`), a buffer or an element of it
  named after its `drop`. Where the translator reads more than the subset
  needs, `elabIR` refuses instead (stricter, never laxer):
  - a `Vec` of anything but numbers;
  - a `let` of a call whose result may be a view (its summary says
    `ret_unowned=1` or names `rviews`; `string_data…`, `slice_from_vec__…`,
    `slice_at__…`). So raw text in the subset is owned (`__view_vars` finds
    nothing), and the only views are `vec_at`'s number elements;
  - a field as an argument (`v3/a`), and a `let x` of a call the
    translator lowers by falling through to a call (`vec_push`,
    `vec_free`).
- **Which programs.** Over tools/ncore/certify, 19 programs are in the
  subset (3 at step 3): all 15 whose translated term uses, beyond step
  2's constructors, only `.new .push .len .vec`, and 4 more:
  `joins_each_freeing_a_different_vec` (`.free`), `cursor_over_a_vec`
  (`.borrow`), and the two that read an element (`.at`). All 19 match,
  each also by `decide +kernel`. 13 of them are accepted by the checker and get
  Elab.lean (the selftest requires exactly these 13); the 6 `*_refused`
  ones have no Claims.lean, so no Elab.lean.
- **Parity** (`tools/ncore/elab_parity.sh`, the fixtures now in
  `tools/ncore/elab/`: the 18 scalar ones and 13 new ones written for this
  step, among them a loop pushing to a Vec, a Vec lent read-only, `inout`,
  moved into a `sink`, returned, dropped on an early return, freed on a
  branch, two Vecs swapped, a Vec parameter changed through its handle, a
  borrowed Vec parameter copied into an `inout` one, strings made and
  measured, a literal handed to a raw-string parameter, elements read by
  index): of 4540 programs nurlc makes a core IR of 4335. tolean.nu
  translates 260 of those, and `elabIR` answers a term for 51 (the 19
  certify programs, the 31 fixtures, one hole probe), every one exactly
  tolean.nu's term (each also by `decide +kernel`). It answers `none` for
  the other 4284, and a term for no program tolean.nu refuses. 166 s in
  all with 12 jobs.
- **Kernel time**, `decide +kernel` of `elabIs ir P entry` (the file with
  the theorem minus the file without it, best of 5 each), on the 16
  certify programs new to the subset: 0.56–0.91 s for 15 of them
  (`use_after_move_refused` 0.56 s, `vec_push_len` 0.61 s, the raw-string
  ones 0.81–0.87 s, `owner_moved_in_a_loop_without_returning_refused`
  0.91 s), and 4.24 s for `joins_each_freeing_a_different_vec` (one
  function of 300 lines, 22 Vecs, 906 lines of IR).
- **The words leave out the library's statement lines** (step 5 leaves
  the whole function out, below). A function
  whose file starts with `stdlib/` keeps its `fn`, `v` and `endfn` lines
  in the words; its other lines are left out (`words.nu`). This is sound,
  read off both programs that read a core IR:
  - the translator's reader (coreir.nu, `core_read`) keeps a statement
    line inside a function as text (`body`, `words`, `wstart`) and checks
    nothing of it; its records are `fn`, `v`, `endfn` and, outside a
    function, `sum`, `ty` and `virt`;
  - the translator (tolean.nu) reads a function's lines only through
    `__cf m p`, a function of `prog` (`__nl`, `__nw`, `__wd` and every
    rule above them, `__wellformed`, `__moved_caps`, `__spawn_scan`,
    `__view_vars`, `__views_of`, `__changes`, `__lean`). `__flags` reads
    `prog`'s variables only, and `__emit`, the one loop over every
    function, reads each one's `name` and `file`. `prog` is the
    functions whose file does not start with `stdlib/` (`__emit`, "not
    bodies to check: their code is phase B's");
  - `elabIR` drops those functions by the same test (`startsB f.file
    stdlibB`, on the sixth word of the `fn` line, which is coreir.nu's
    column 5), and reads nothing of a function it drops but its
    variables' records, which the reader checks and the words keep. A line
    is left out by Lean's own reading of it (`readFns`: a first word `fn`
    opens a function, `endfn` closes it), so exactly the lines `readFns`
    would put in a library function's `body` go. A library function is
    never taken for an empty function of the program: its `fn` line,
    and so its file, stays.
  - Checked, not assumed. `tools/ncore/elab_parity.sh` runs `elabIR` on
    the words and on every line (`elab_parity_full.py`) for every
    program, and requires the two results equal (`progBeq`, `stmtBeq`):
    the same on all 4335 core IRs. translate_test 1c compares the words
    with an independent Python reading of the rule. 15 mutants (5
    programs, 3 library statement lines each, made ill-formed) leave the
    translator's term, the words and `elabIR`'s answer unchanged. The
    controls change them: a program statement edited changes the term
    and the words, and a library `v` line of kind 7 makes the translator
    stop and `elabIR` answer `none`.
  - `vec_push_len`'s words: 581 lines → 157. `raw_strings_literal_and_fresh`'s:
    1141 → 284.
- **One Lean process per program.** certify and verify check a bundle in
  one Lean file made in the work directory, one `lake env lean`: the
  imports (`C.Cert`, a threaded program's `C.Cert3`, `C.Elab` with an
  Elab.lean), then Program.lean's definitions inside `section` / `open A2
  C` / `end`, then Claims.lean's body and Elab.lean's body
  (`cert_lean_check`, packages/nurl-cert/src/lean.nu). The bundle keeps
  its three modules, which a person checks the module way.
  docs/dev/CERTIFICATE.md ("How Lean checks a bundle") says why the file
  means what they mean, and how each of Lean's messages is placed by its
  own line (`lean --json`). The selftest
  checks three bundles both ways (verdict, each claim's axioms,
  Cert.elab). Gone with it: the second, concurrent Lean process and the
  stop of it on a refusal, the `Program.olean` handed from one run to the
  next, and the environment dump of an earlier try (one `lake` a check
  is the point now).
- **A refused Cert.elab is cheap.** When the kernel refuses `elabIs ir P
  entry` (words whose term is not Program.lean's: a tampered bundle, or a
  bug of `elabIR`), `decide +kernel` explains the failure by reducing the
  instance again in the elaborator. On a real core IR that reduction took
  111 s and 28 GB before the OOM killer stopped it. That happened in the
  module way too: before this step, the selftest's swapped-term bundle
  was refused only because its Elab.lean process was killed. `elabIs` is
  now `@[irreducible]`. The kernel ignores that, so the proof is
  unchanged, and the elaborator stops at once: the same bundle is refused
  in 0.74 s, with a 460-byte message. (A `maxRecDepth` on the theorem was
  tried first. It also bounds the kernel's own recursion, so
  `joins_each_freeing_a_different_vec` needs more than 64, and a depth
  of 384 lets the explosion through.)
- **Certify time** over the 62 certify programs, one at a time, best of
  3, before and after run in turn on the same x86-64 host: 82.1 s
  against 83.9 s before (−2.1 %). Most programs take 0.3–0.4 s less: one
  Lean process, not a compile and then a check. The 9 accepted programs
  new to the subset take +0.4 to +0.8 s, and their refused neighbours
  about +0.5 s: their Elab.lean part now runs after the claims instead
  of beside them. `joins_each_freeing_a_different_vec` takes +4.6 s (16.6
  → 21.2 s): its 5 s Elab.lean part no longer hides behind its 16 s
  claims' check, and `-DElab.async=true` does not run the two side by
  side (20.9 s). Along the way: 101.5 s with the full words and a second
  process, 95.6 s with the stop on refusal, 88.5 s with the library's
  statement lines left out and one lake run.
- **Peak memory** (the summed RSS of certify's process tree, sampled
  every 5 ms), against the same baseline:
  - a program outside the subset: +7 MiB on average (44 programs within
    ±50 MiB);
  - a program in the subset: +78 to +110 MiB (`C.Elab` and the words in
    the one process);
  - the 3 scalar ones: 618–648 MiB less (they had two processes);
  - the largest peak: +18 MiB (`joins…`, 2566 → 2584 MiB);
  - the sum of the 62 peaks: −0.7 %.
- **Where the time goes now**, best of 5:

  | | vec_push_len | raw_strings… |
  |---|---|---|
  | words (lines) | 157 | 284 |
  | Lean's start and `import C.Elab` (an empty file) | 0.30 s | 0.30 s |
  | elaborating the words literal | 0.24 s | 0.41 s |
  | kernel: reading the functions (`fnsOf`) | 0.09 s | 0.14 s |
  | kernel: the top-level lines (`topLines`) | 0.05 s | 0.04 s |
  | kernel: one summary lookup by name | 0.08 s | 0.13 s |
  | kernel: `elabIs`, in all | 0.47 s | 0.58 s |

  (Before the elision: 0.56 / 1.13 s of literal, 0.55 / 0.81 s of kernel.)
  What is left in the kernel is mostly the summary lookups by name, two
  or three a program. Each compares the name with every `sum` line's, at
  the kernel's cost per character of a string literal.
- **Tried, not kept:**
  - names as numbers: each name's bytes as a `Nat` (base 257, a byte plus
    one a digit; injective, proved), every lookup a `Nat` comparison. No
    gain, because making the keys decodes every name once, which costs
    what the comparisons did: 0.63 / 0.90 s for `elabIs` against 0.61 /
    0.80 s. On 200 distinct 20-character strings the kernel spends ≈ 6 ms
    on a literal at first touch and ≈ 0.7 ms a character; repeated
    literals (`let`, `v1`) are decoded once;
  - the literal's syntax: a typed list per line, `::` chains,
    `@List.cons String …` with explicit types, the linters off. All
    0.39–0.49 s against 0.46 s on the 581 lines: the cost is the term
    elaborator's, ≈ 0.2 ms a list node, whatever the spelling (a flat list
    of the 2163 words, 0.42 s; `Nat` leaves, 1.01 s).

## Route (b), step 5: views, slices and changes through a borrow (AGORA-1029)

- `elabIR` covers the translator's **views** too. A variable, parameter or
  `Vec` element may now be a view (A2's `.slice .int`): a `Slice` of a
  number type, raw text bound from a view, or the element of a `Vec` of
  raw strings (`%Vec__str`, `.vec (.slice .int)`). The constructors it
  builds beyond step 4's are `.edit` (Stmt), `.view .sat` (Rhs), `.slen`
  (Expr), `.trunc` (Edit; `.push` was there) and `.slice` (Ty). They are
  tolean.nu's rules for:
  - `string_data` and `slice_from_vec` (`.view`), `slice_len` (`.slen`),
    and a read of raw text that holds a view (`__read`, `nurl_println`:
    `.slen`, an owner's `.len`);
  - **which raw text is a view** (`__view_vars`): bound from `string_data`
    or `vec_at__str`, or a `use` copy of such a binding. `viewVars` takes
    the same fixpoint over the whole body. The translator also counts a
    call whose summary says it lends its result (`__borrowed`); no other
    such call is in the subset (`letCallOk`), so that case is
    `string_data`'s, which both take by name;
  - raw text pushed into a `Vec` of raw strings: viewed first (`.view`,
    then `.push`), a view pushed as it is, a literal refused;
  - `foreach x v` over a `Vec` of numbers: a block holding a view of the
    `Vec` for the loop, each element lent through it (`.sat`), the index
    stepped before the body, `continue` and `break` leaving the blocks a
    loop's leave;
  - changes of a `Vec` through a borrow of it: `vec_clear` and
    `vec_truncate` (`.edit true b (.trunc i)`, a `let x` of it any
    number), `vec_reserve` and `vec_shrink_to_fit` (a push that may move
    the buffer and a cut back to its length read before it), and
    `string_push_str` (a push, then the read of the text it copies);
  - a drop's check (`__views_of`) follows views copied into a temporary
    (`let j use …` of a `j` that is a raw-text view), as the translator
    does, beside the calls that hand back a view.
- **Fail closed.** Each check the translator makes on these is made too,
  each with a kernel witness of the refusal and of its well-formed
  neighbour (formal/C/Elab.lean, "step 5"): a slice of a `Vec` of views, a
  `foreach` over a `Vec` of views or over a `String`, a literal pushed into
  a `Vec` of raw strings, `vec_reserve` of a `Vec` of views,
  `string_push_str` of a number, a borrowed slice parameter copied into an
  `inout` one, a view copied into a temporary and read after its source's
  drop. Where the translator takes more, `elabIR` refuses (stricter,
  never laxer):
  - a `let x` of `vec_reserve`, `vec_shrink_to_fit`, `string_push_str` or
    `nurl_println`. The translator lowers it by falling through to
    `__call`, which tries the library call again without `x` and drops
    `x`;
  - a `slice_from_vec` (or `vec_at`) whose summary says it lends its
    result: the translator takes it and counts its result a view;
  - a slice handed back (the translator takes it as an owned result);
  - a change in place of a `foreach`'s element (the translator changes
    it through itself, without a borrow, `__edit_through`);
  - a `Vec` or `Slice` of anything but numbers and raw text, a `Slice` of
    raw text, `vec_reserve`/`vec_shrink_to_fit`/`slice_from_vec` of a
    non-number element, a `foreach` over a `Vec` of anything but numbers.
- **Which programs.** Over tools/ncore/certify, 32 programs are in the
  subset (19 at step 4), every one of the 13 this step aimed at:
  `view_taken_after_the_pushes`, `vec_cleared_then_pushed`,
  `vec_reserved_then_pushed`, `foreach_summing_a_vec`,
  `raw_strings_held_in_a_vec`, and 8 `*_refused` ones (a view kept across
  a realloc, across pushes in a loop, across a clear, across a reserve; a
  String copied from a view of a freed String; a String pushed its own
  view; a Vec pushed while iterated; raw text held in a Vec past its
  source). The 5 accepted ones get Elab.lean: 18 bundles in all (13
  before; the selftest requires exactly these 18). The refused ones have
  no Claims.lean, so no Elab.lean.
- **Parity** (`tools/ncore/elab_parity.sh`, 14 new fixtures in
  `tools/ncore/elab/`: a String viewed and the view copied and measured, a
  slice taken in each round of a loop, a slice handed to a function, a Vec
  truncated, reserved and shrunk in a loop, a String grown from a literal,
  another String and a view, `foreach` with `break` and `continue`,
  nested, returning early from a Vec parameter, text printed, a Vec of
  raw strings filled and read, and three the checker refuses: a view kept
  across a truncate, a view read after its String moved, a Vec cleared in
  a foreach over it): of 4554 programs nurlc makes a core IR of 4345.
  tolean.nu translates 274 of those, and `elabIR` answers a term for 101
  (the 32 certify programs, the 45 fixtures, 24 hole probes), every one
  exactly tolean.nu's term (each also by `decide +kernel`). It answers
  `none` for the other 4244, and a term for no program tolean.nu refuses.
  `elabIR` answers the same on the words and on every line for all 4345.
- **Verdicts unchanged.** Every program of the parity list (4554)
  certified by main's nurl-cert and formal/ and by this step's, 10 jobs:
  the same exit status for all 4554 (111 accepted, 163 refused, 4071
  unsupported, 209 not compiled). 27 more get Elab.lean (68 against 41),
  none loses it.
- **A drop's check reads the lines that can add a view once.** At step 4
  every non-number `drop` ran `__views_of`'s passes over the whole body.
  Now the lines that can add a variable (`viewEdges`: a `let` of a call
  that hands back a view, a `let … use` of a raw-text view into a
  temporary) are collected once per function, each with the variables its
  words name, and every drop's passes run over those
  (`viewsStep`/`viewsOf`, the same set, as `__views_of`'s). That saves
  `joins_each_freeing_a_different_vec` 1 s of kernel (44 drops in a
  300-line function: 5.22 → 4.16 s for its Elab.lean part).
- **The words leave out a library function whole.** At step 4 a library
  function kept its `fn`, `v` and `endfn` lines. The programs new to
  the subset import `slice.nu` and `string.nu` beside `vec.nu`, so those
  lines were most of their words (`vec_cleared_then_pushed`: 43 `fn` and
  210 `v` lines of 407 entries), and Lean spent most of their Elab.lean
  part reading them (0.60 s of literal, ≈ 0.5 s of kernel). `elabIR`
  drops a library function before it reads anything of it, so the only
  thing those lines decide is whether `readFns` accepts the IR at all: a
  parameter count that is not a number, or a `v` line `readVar` does not
  read (an id, kind or flags that is not a number, a kind above 3, fewer
  than six words), makes it refuse the whole IR. So `words.nu` leaves a
  library function out whole exactly when `readFns` would accept its
  records (`__wd_nat`, `__wd_var_ok`, the same tests on the same words
  as printed), and prints its `fn`, `v` and `endfn` lines when it would
  not, so that `readFns` refuses the words as it refuses every line. A
  function opened inside another, or left open, keeps its records too.
  `elabIR` answers the same on the words as on every line:
  - over the corpus, `tools/ncore/elab_parity.sh` (all 4345 core IRs);
  - over IRs the reader refuses, the selftest (section 2d: 11 core IRs, a
    clean library function, a kind written `0003`, a statement whose
    first word is `v`, and 8 the reader refuses: kind 4, a statement `v`
    of kind 9, flags `x`, a short `v` line, an empty parameter count, a
    function opened inside the library's, a library function opened
    inside `main`, one left open). Each compares `fnsOf` on the words
    with `fnsOf` on every line;
  - translate_test 1c checks the words against an independent Python
    reading of the rule.
  `vec_cleared_then_pushed`'s words: 407 entries → 119 (its 70 `sum` and
  12 `ty` lines stay: `elabIR` looks summaries up by name and checks every
  `ty` line; the `sum` lines cost ≈ 0.05 s). `vec_push_len`'s: 157 → 55.
  The combined Lean file of `vec_cleared_then_pushed`: 1.95 → 1.25 s,
  747 → 703 MB.
- **Certify time** over the 62 certify programs, one at a time, best of
  3, base (main's nurl-cert and formal/, 58545492) and branch run in turn
  on the same x86-64 host: 81.3 s against 80.8 s (+0.6 %; the sums of the
  per-program bests 79.2 s against 79.0 s). Before the library functions
  were left out whole this step was 91.6 s against 79.7 s (+14.9 %).
  - the 13 programs new to the subset: +0.32 to +0.82 s each
    (`vec_cleared_then_pushed` 0.77 → 1.59 s), the cost of their new
    Elab.lean part. 8 of them the checker refuses: they spend the same,
    and the bundle keeps no Elab.lean, since the verdict comes from the
    same Lean run and certify cannot leave the part out beforehand;
  - the other 49: −7.2 s in all. `joins_each_freeing_a_different_vec`
    −1.35 s (a drop's check, above), and the step 4 programs that import
    the library's text functions −0.46 to −0.50 s each
    (`raw_strings_literal_and_fresh` 1.59 → 1.11 s), since their words
    shrink too.
- **Tried, not kept:**
  - a summary table (one pass keeping the `sum` lines of the names
    looked up, then lookups in it; proved equal to `sumOf`). Within one
    `decide` the kernel already shares the decoded names between lookups
    (three lookups cost 0.29 s against 0.24 s for one), so the extra pass
    cost more than it saved (the same three lookups through the table:
    0.40 s);
  - skipping the Elab.lean part when the claims' part already failed. A
    command placed between the two parts sees no earlier error: Lean
    resets the messages per command, and a failed `decide` leaves no
    `sorry` declaration behind. A command of one's own also needs `import
    Lean`, ≈ 0.9 s more for every Elab.lean check. Stopping Lean from
    nurl-cert when the refusal is printed would need a process API that
    reads Lean's output as it comes (`nc_run` waits for the process).
- **Peak memory** (the summed RSS of certify's process tree, sampled
  every 5 ms), against the same base: the largest peak 2586 → 2584 MiB
  (`joins…`); the 13 new programs +46 to +105 MiB each (`C.Elab` and the
  kernel's work in the one process); the other 49 within −33 to +4 MiB;
  the sum of the 62 peaks +1.5 %.

## Route (b), step 6: closures (AGORA-1029)

- `elabIR` covers the translator's **closures**. A variable, parameter or
  result may be of a closure type `{ R (i8*, A…)*, i8* }`, A2's `.fn [σ]
  .any`, whose interface `σ` is one function per closure type after the
  program's own, in the order the translator first meets the type
  (`__clo_index`: each function's variables, then its result, in the
  program's order; `cloScan`). The constructors it builds beyond step 5's
  are `.callc` (Stmt), `.pack .pair .fst .snd` (Rhs) and `.prod .fn` (Ty;
  the class `.any`). They are tolean.nu's rules for:
  - a closure's code (`__closure_…`): a function of its environment (lent),
    its parameters, then its captures by name, then the result slot, its
    other variables after it in id order (`__fn_init`'s numbering, one
    number left out); the captures by value read out of the environment at
    the top of the body, one the environment, more its pairs' fields
    (`__read_caps`);
  - which captures are by name (`__named_cap`): a buffer the environment
    does not own (`CORE_VF_ENVOWN`), unless every literal of the code moves
    it in, the binding a local or a temporary its function drops nowhere
    and names no more after the literal (`__moved_caps`, `isMovedQ`, read
    over every function of the program); and a capture by name's mode
    (`__cap_mode`): read only, or `inout` at `drop` when the code takes it
    by pointer or changes it in place (`__changes`);
  - a literal (`let k closure f n caps…`): its captures by value copied into
    one value (none: a number; more: pairs nested to the right) and packed
    with the code and the interface of its variable's type (`.pack`), the
    other captures by name;
  - a call through a closure value (`callind`): `.callc` of method 0 of its
    type's interface; the interfaces themselves: the closure (lent), then
    the type's arguments, a result made fresh (a number or an empty buffer);
  - `nurl_println_int`: the read of a number.
- **Fail closed.** Each check the translator makes on closures is made too,
  each with a kernel witness of the refusal and of its well-formed
  neighbour (formal/C/Elab.lean, "step 6"): a capture that is not a
  variable, a literal of fewer captures than its code has, a capture of a
  type other than a number or a buffer of numbers (a `Vec` of raw strings),
  a number capture taken by pointer, a closure parameter taken `inout`, a
  closure bound from another binding or given another value, a closure
  handed to a `sink` or `inout` parameter (nurlc copies it there, which the
  core IR does not show), a call through a number, a closure type whose
  result is a slice or that takes or hands back raw text, and a closure's
  code naming a variable it does not declare where the translation reads
  it. The checks run over the whole body and the whole program, as the
  translator's (`__wellformed`, `__moved_caps`, `__changes`, the captures'
  types and modes for every capture of every code, a literal or not).
  Where the translator takes more, `elabIR` refuses (stricter, never
  laxer):
  - a literal of a function not named as a closure's code (the translator
    packs any function of the program);
  - a closure's code that names a variable it does not declare anywhere,
    a `line` included (the translator stops only where it numbers one);
  - a program with closures whose variables are not in id order, each id
    once (the translator reads them by id; `elabIR` in the order of the `v`
    lines; nurlc prints them in id order: no program of the corpus differs);
  - a closure type's arguments spelled other than `, A` (the translator
    splits at each comma, trims, and skips an empty piece);
  - a closure copied from another binding where its value is handed back
    at once: the translator's check sits after that case. A move there is
    what the copy is modelled as anyway, so this is no hole of the
    translator's, only a case the subset leaves out;
  - a `let x` of `nurl_println_int` (the translator falls through to a call
    that drops `x`);
  - a closure's code in a program with no closure type. That makes a fact
    nurl-cert's skip can read: a term of `elabIR`'s that holds `.callc .pack
    .pair .fst .snd .prod` holds `.fn` too (`ELAB_CLO_CTORS`, below).
- **Which programs.** Over tools/ncore/certify, 45 programs are in the
  subset (32 at step 5): all 13 `clo_*` programs this step aimed at. 8 are
  accepted and get Elab.lean, 26 bundles in all (the selftest requires
  exactly these 26); the 5 `*_refused` ones (a closure called on, or with,
  a moved Vec; a closure that pushes onto a captured Vec under a slice of
  it; a closure over a parameter run after its argument is freed; a
  captured Vec given a new value, then the closure run) have no Claims.lean,
  so no Elab.lean. The four thread programs stay outside (A3, `C.Cert3`).
- **The skip before Lean.** The closures' constructors include `.prod
  .pair .fst`, which a struct's term holds too: with them in `ELAB_CTORS`
  alone, the 6 struct programs became candidates, and each paid an
  Elab.lean part `elabIR` refuses (+0.15 to +0.31 s). `cert_elab_candidate`
  now also skips a term that holds one of `ELAB_CLO_CTORS` (`callc pack
  pair fst snd prod`) but no `.fn`. That is exact: `elabIR` builds those
  only for a literal or a call (whose variable is of a closure type) or a
  closure's code (refused without a closure type), and every closure type
  has an interface whose first parameter is a `.fn`.
- **Parity** (`tools/ncore/elab_parity.sh`, 12 new fixtures in
  `tools/ncore/elab/`: three captures in nested pairs, a Vec moved into the
  environment, a Vec read by name, a closure taking a Vec, a closure
  parameter called in a loop, a closure with no result, a literal inside a
  closure's code, a closure handing back a String, and four the checker
  refuses: a Vec cleared by name, a captured Vec freed before the call, a
  captured String moved into a sink before the call, a push through a
  closure under a slice): of 4566 programs nurlc makes a core IR of 4357.
  tolean.nu translates 286 of those, and `elabIR` answers a term for 166
  (the 45 certify programs, the 57 fixtures, 64 hole probes; 101 at step
  5, none of them lost), every one exactly tolean.nu's term (each also by
  `decide +kernel`). It answers `none` for the other 4191, and a term for
  no program tolean.nu refuses. `elabIR` answers the same on the words and
  on every line for all 4357. Of the 52 translated programs with closures,
  the 4 thread programs and 3 hole probes over `Vec`s of `String`s stay
  outside. The new matches are the 13 certify programs, the 12 fixtures
  and 40 hole probes (8 of them without a closure, in the subset now for
  their `nurl_println_int`).
- **Verdicts unchanged.** Every program of step 5's parity list (4554)
  certified by main's nurl-cert and formal/ and by this step's, 10 jobs:
  the same exit status for all 4554 (111 accepted, 163 refused, 4071
  unsupported, 209 not compiled). 14 more get Elab.lean (82 against 68),
  none loses it. The 12 new fixtures, certified apart: the 8 accepted get
  Elab.lean, the 4 `*_refused` are refused.
- **Certify time, with the words still string literals**, over the 62
  certify programs, one at a time, best of 3, base (main's nurl-cert and
  formal/, 6e34f390) and branch run in turn on the same x86-64 host: 90.4 s
  against 82.3 s (+9.8 %; the sums of the
  per-program bests 88.2 s against 80.2 s). **A regression**, all of it the
  13 programs new to the subset: +0.45 to +0.87 s each (+8.4 s in all;
  `clo_number_capture_called` 0.59 → 1.06 s), the cost of their new
  Elab.lean part. 5 of them the checker refuses and spend it too (no
  Elab.lean is kept; the verdict comes from the same Lean run). The other
  49: −0.35 s in all, each within ±0.10 s. Before the skip of a struct's
  term (above), the 6 struct programs were +0.15 to +0.31 s each too.
- **Peak memory, with the words still string literals** (the summed RSS
  of certify's process tree, sampled every 5 ms), against the same base:
  the largest peak 2583 → 2584 MiB (`joins…`); the 13 new programs +35 to +109 MiB each (`C.Elab` and the
  kernel's work in the one process); the other 49 within −4 to +9 MiB; the
  sum of the 62 peaks +1.9 %.
- **Where the time went, with the words as string literals.** For a small program the Elab.lean part costs
  0.4 to 0.6 s (`clo_two_captures_passed_to_a_function`: Lean's start and
  `import C.Elab` +0.02 s over the claims alone, the words literal +0.04 s,
  `decide +kernel` of `elabIs` +0.5 s, of which `elabIR` 0.39 s and the
  comparison 0.11 s). No single pass of `elabIR` dominates: taking any one
  of the drop check, `__view_vars`, the `let` check, `opsOk`, the summary
  lookup or the variables' types out saves 0 to 0.08 s, since the next
  pass then decodes the same words. Decoding every word of the words to
  bytes, alone, costs 0.57 s (`clo_changes_a_captured_vec`, 92 lines) and
  0.81 s (`vec_cleared_then_pushed`, 133 lines), more than `elabIR` itself
  (0.53 and 0.63 s): most of the kernel's time is the first touch of a
  string literal. The 13 new programs paid that, and it made this step
  slower overall until the words became numbers (next section).
- **Won back by the next section**: the `sum` lines no other word names
  left out of the words, and the words printed as numbers. Both change
  `words.nu`, the trusted split. (Measured first by cutting the `sum` lines
  of the 26 bundles with Elab.lean: 28.2 s → 25.8 s over the 25 small
  ones.)

## Route (b): the words as numbers (AGORA-1029, with step 6)

- **The cause.** In Lean 4.35 `String` is a UTF-8 `ByteArray`, which the
  kernel builds from a literal by one `push` a byte: quadratic in the
  word's length. For 40 distinct words, `(bytesOf w).length` by `decide
  +kernel` costs 0.15 s at 8 bytes, 1.24 s at 32 and 17 s at 128;
  `toByteArray.size` and `utf8ByteSize` cost the same and `toList` more, so
  no decoder of a `String` avoids it. The long words are the file paths of
  the `fn` lines: every closure is a function, so a closure program holds
  several paths of ~70 bytes, ≈ 130 ms each.
- **The words.** `nurl-cert words` prints each word as a number:
  `nat_lit 0x1`, then the word's bytes from the last to the first, two hex
  digits each (256^k + Σ bᵢ·256^i; an empty word is `0x1`), in `def ir :
  C.Elab.IR := …` with `IR := List (List Nat)`. The split into lines and
  words is unchanged, and so are the blank lines, the library functions
  left out and the `sum` lines left out (below). The file is ASCII and
  needs no escaping. `C.Elab.wordOf` reads a number back into its bytes by
  `% 256` and `/ 256` (fuel: the number itself), and `wordOf_encB` proves
  that it inverts the printer's encoding for every list of bytes.
  `nat_lit` is a raw literal: Lean elaborates it without an `OfNat`
  instance, 0.39 s against 0.72 s for the 1544 words of
  `joins_each_freeing_a_different_vec` (the string literals took 0.49 s).
- **The UTF-8 rule goes.** Lean no longer reads the words' bytes as text,
  so a core IR that is not well-formed UTF-8 has words now, each read back
  as its bytes (selftest 2c: quotes, backslashes, comment openers, control
  bytes, CR, non-ASCII UTF-8 and five byte sequences that are not UTF-8).
  The NUL rule stays (`cert_words_ok`): the words are made from the text
  up to its first NUL, and the bundle hashes the whole file.
- **Keywords are compared as numbers.** `elabIR` keeps each word as its
  number and compares it with a keyword's number (`kLet`, `kCall`, …,
  `@[match_pattern]` constants, each checked against its text): one GMP
  comparison. It reads a word into its bytes (`wordOf`) only where its
  text is needed (a variable, a count, a type, a callee's name), and the
  kernel keeps what it reduced, so each distinct number is read once. The
  first try read every word into a byte list and matched the keywords as
  byte lists: on `joins_each_freeing_a_different_vec` that made `elabIR`'s
  kernel time 3.69 s against 2.95 s with the string literals, since a
  `match` on a byte-list keyword unfolds into a test a byte. Measured on
  one pass over that program's 470 lines (a count of the `let … call` and
  `eval call` lines): 191 ms with string literals, 314 ms with byte-list
  patterns (their reading included), 210 ms with byte lists compared by
  `==`, 86 ms with the numbers as patterns (one Lean run each, the host
  loaded by the verdict sweep). With the keywords as numbers `elabIR`
  takes 3.03 s there.
- **The `sum` lines no other word names are left out** (`words.nu`). A
  `sum` line outside every function (Lean's reader reads only those as
  summaries) whose name is none of the words of the kept lines but those
  `sum` lines is not printed; one inside a function is a statement of its
  body, which `elabIR` refuses, and is kept (selftest 2e). `elabIR` looks a summary up only by a
  function's own name, a callee's name, or the function a `let … call f`
  calls, each a word of a kept line, and a name's summary is its last
  `sum` line, which stays. A `sum` line with no name is kept (`topOk`
  refuses it). `tools/ncore/elab_parity.sh`'s full words keep every line,
  so its check that `elabIR` answers the same on both covers this rule too;
  translate_test 1c checks the words against a Python reading of both
  rules. ≈ 0.1 s on `clo_changes_a_captured_vec`.
- **Breaking:** Elab.lean's words are another text now, so a 0.3.0 bundle
  with Elab.lean does not verify with nurl-cert 0.4.0 (`verify` makes
  Elab.lean again from Program.core and compares it byte for byte).
  Migration: certify the program again. A bundle without Elab.lean
  verifies as before.
- **Parity** (`tools/ncore/elab_parity.sh`; its JSON handoff, its full
  words and its run now carry the numbers): the same as above, 166
  programs in the subset of 4357 core IRs, every one exactly tolean.nu's
  term (each also by `decide +kernel`), 0 DIFF, 0 LAX, 0 errors, and
  `elabIR` the same on the words as on every line for all 4357. Its
  kernel comparisons take 161 s with 12 jobs, against 221 s with the
  string literals.
- **Verdicts unchanged.** The 4554 programs of step 5's parity list,
  certified by main's nurl-cert and formal/ and by this one, 10 jobs: the
  same exit status for all 4554 (111 accepted, 163 refused, 4071
  unsupported, 209 not compiled); 82 get Elab.lean against 68, none loses
  it (the same as with the string literals).
- **Certify time** over the 62 certify programs, one at a time, best of
  3, base (main's nurl-cert and formal/) and branch run in turn on the
  same x86-64 host, measured again on the branch rebased onto f6e28704:
  **77.1 s against 77.8 s (−0.9 %)**; the sums of the per-program bests
  75.3 s against 75.9 s. (An earlier run on 6e34f390, on a less loaded
  host: 74.1 s against 77.7 s, −4.6 %; the per-program changes were the
  same, the totals' spread is the host's.) The 13 programs new to the
  subset: +0.19 to +0.63 s each, +4.9 s in all (+8.4 s with the string
  literals); the other 49: −5.6 s in all, each −0.40 to +0.13 s; of them
  the 18 with Elab.lean −3.3 s (`vec_cleared_then_pushed` 1.57 → 1.17 s;
  `joins_each_freeing_a_different_vec` 18.53 → 18.66 s, its time the
  checker's and `elabIR`'s drop checks, not its words). The same exit
  status for all 62 (36 accepted, 26 refused).
- **Peak memory** (the summed RSS of certify's process tree, sampled
  every 5 ms), against the same base: the largest peak 2581 → 2586 MiB
  (`joins…`); the 13 new programs +15 to +71 MiB each; the other 49
  within −51 to +5 MiB; the sum of the 62 peaks −1.1 %.

## Route (b), step 7: structs and options (AGORA-1029)

- `elabIR` covers the translator's **structs and options**. A variable,
  parameter or result may be of an option type `{ i1, T }` (A2's `.sum .int
  T`, `None` the first variant) or of a struct type `%S` whose `ty` line
  gives its fields (A2's `.prod`, the fields' types nested in pairs to the
  right; a struct of one field is its field's type), over any type of the
  subset, options and structs included (`tyR`, the translator's
  `__lean_ty` and `_struct_ty`). The constructors it builds beyond step
  6's are `.inl .inr .getr` (Rhs), `.isl` (Expr) and `.sum` (Ty); `.pair
  .fst .snd .prod` were step 6's. They are tolean.nu's rules for:
  - a struct's literal (`agg - n ops…`): its operands nested in pairs to the
    right, each inner pair bound first (one of one field: its operand's
    value, a number's or a moved buffer's); an option's (`agg F 0`: `.inl`
    of a temporary; `agg T 1 op`: `.inr .int` of its payload), into a
    variable of an option type, by `let` or `assign`;
  - a field read (`v3/f`, `__field_temp`): through the pairs into fresh
    temporaries (`.snd` as often as the field's place, then `.fst` unless it
    is the last), where a `scalar`'s operand, a `use` of a number field, an
    index or a length operand (`operandP`) or a library call's argument
    (`rdF`, `fpre`: its bindings around the call's construct, outside an
    operand's) names it; a field's A2 type where it is read (`__flean`) is
    its place in the struct's pairs (`fieldTy`);
  - an option's match (`match v` with arms `T` and `F`): `.ite (.isl v)`,
    the `None` arm first, and `payload v T 0`: the payload lent, `.getr`.
- **Fail closed.** Each check the translator makes on these is made too,
  each with a kernel witness of its refusal and of its well-formed
  neighbour (formal/C/Elab.lean, "step 7"): a struct holding raw text (a
  field `i8*`), a closure inside a struct or an option, a struct inside
  itself, a struct of no fields or with no `ty` line, an owning field's
  value moved or copied (`use v/items` of a Vec), a nested field path, a
  field the struct does not have, an option's literal into a variable of
  another type or given none (`eval agg …`), a struct's literal of no
  operand, a payload other than `T 0` (a result's error, which the
  translator reads only in a program that spawns), a match whose arm names
  repeat or are not `T` and `F`. The type checks run for every variable
  and result of every function, as the translator's `__fn_init`. Where the
  translator takes more, `elabIR` refuses (stricter, never laxer):
  - a struct whose fields' names repeat (the translator reads a field by
    its first name in `__field_temp` and by its last in `__field_ix`);
  - a field of a type that is no struct of the subset (the translator reads
    the `ty` line of any type, a `Vec`'s or a `String`'s handle `ctl`
    included: `v/ctl` of a `%String` would be the whole String), and a field
    of a struct of one field named other than its field (the translator does
    not read the name there);
  - a struct named like a number behind its `%` (`%i64`: the translator
    takes it for a number) or like a channel, and a type nested deeper than
    `tyFuel` (32 types, the innermost counted: a number inside 31 options is
    read, inside 32 refused, both witnessed);
  - a field root other than `v` and digits, and a `match` of more than two
    arms (the translator takes repeated names, the last block of each).
  A program that spawns is outside the subset as before: its spawn is a
  call `intrS` has no rule for, so the translator's threaded readings
  (results, `%Thread`) never meet `elabIR`'s.
- **Closure types over structs.** A closure type's argument may be a
  struct of the subset (`cloArgTy`: step 6's `tyOfB`, else `tyR` through
  the program's `ty` lines, as the translator's `__lean_ty` reads it), so a
  closure taking a struct is in the subset; its interface takes the struct
  lent (`.inp`), as the translator's. A struct holding raw text, or a name
  with no `ty` line, is refused there as everywhere.
- **A struct of one number field** is A2's `.int`. Where the translator
  asks the IR type (`__is_int`: a `use`, a `ret`) it is no number and
  moves; where it asks the A2 type (`__lean_ty`: a `drop`, a `none` slot)
  it is one. `Ctx.obj` and the drop's and the slot's tests now read it so
  (for every type before this step the two readings agree).
- **The skip before Lean.** `ELAB_CTORS` takes `.inl .inr .getr .isl
  .sum`. `ELAB_CLO_CTORS`, step 6's skip of a term with a closure's
  constructor but no `.fn`, now holds `.callc .pack` only: `elabIR` builds
  those only for a call through, or a literal of, a variable of a closure
  type (`sigmaOf` of its type), and every closure type has an interface
  whose first parameter is a `.fn`. With `.pair .fst .snd .prod` in it, it
  skipped every struct program, now a term `elabIR` builds. It is still
  exact, and over tools/ncore/certify it skips none.
- **Which programs.** Over tools/ncore/certify, 51 programs are in the
  subset (45 at step 6): all 6 this step aimed at
  (`struct_field_handed_to_a_reader`,
  `struct_field_read_after_the_struct_moved_refused`, `struct_fields_read`,
  `vec_moved_into_a_struct`, `vec_moved_into_a_struct_then_pushed_refused`,
  `option_built_and_matched`). The 4 the checker accepts get Elab.lean, 30
  bundles in all (the selftest requires exactly these 30); the 2
  `*_refused` ones have no Claims.lean, so no Elab.lean. Outside stay the
  destructor programs (`.dtor .letd`), the channel and thread programs (A3)
  and nothing else. The selftest's tamper bundle, a program outside the
  subset, is a destructor program now
  (`destructor_frame_left_by_an_early_return`), and its outside-the-subset
  check names that one.
- **Parity** (`tools/ncore/elab_parity.sh`, 17 new fixtures in
  `tools/ncore/elab/`: three fields read through nested pairs, a struct
  made by a function and handed back, a struct of one field, a struct
  holding a String measured, viewed and grown through its field, a Vec
  field indexed, sliced and cut back, a struct inside a struct, a struct
  given a new literal in a loop, a struct handed `inout`, an option matched
  `None` first, an option holding a Vec, an option of a literal given
  another value, options made and matched in a loop, a closure taking a
  struct, and two the checker refuses: a Vec moved into an option then
  pushed, a struct read after it was handed to a sink): of 4583 programs nurlc makes a core IR of 4378.
  tolean.nu translates 303 of those, and `elabIR` answers a term for 224
  (the 51 certify programs, the 74 fixtures, 99 hole probes; 166 at step
  6, none of them lost), every one exactly tolean.nu's term (each also by
  `decide +kernel`). It answers `none` for the other 4154, and a term for
  no program tolean.nu refuses; the same on the words as on every line for
  all 4378. The new matches are the 6 certify programs, the 17 fixtures and
  35 hole probes (options and their payloads, struct literals, cursors in
  literals). The baseline run on main 986339c9 found 166 matches of 4356
  core IRs; 5 hole probes that import `stdlib/ext/sqlite.nu` had no core
  IR there (the baseline tree was a `git archive` copy), none of them in
  the subset on the branch.
- **Verdicts unchanged.** Every program of step 5's parity list (4554)
  certified by main's nurl-cert and formal/ and by this step's, 10 jobs:
  the same exit status for all 4554 (111 accepted, 163 refused, 4075
  unsupported, 205 not compiled). 10 more get Elab.lean (92 against 82):
  the 4 certify programs and 6 hole probes; none loses it. The 16 new
  fixtures, certified apart: the 14 accepted get Elab.lean, the 2
  `*_refused` are refused.
- **Certify time** over the 62 certify programs, one at a time, best of
  3, base (main's nurl-cert and formal/, 986339c9) and branch alternated
  (A1 B1 A2 B2 A3 B3) on the same x86-64 host: **80.0 s against 80.2 s
  (−0.2 %)**; the sums of the per-program bests 77.7 s against 77.7 s.
  The same exit status for all 62 (36 accepted, 26 refused).
  - the 6 programs new to the subset: +0.11 to +0.39 s each, +1.63 s in
    all (`option_built_and_matched` 0.64 → 1.03 s), the cost of their new
    Elab.lean part; the 2 the checker refuses spend it too (no Elab.lean is
    kept; the verdict comes from the same Lean run);
  - the other 56: −1.55 s in all. `joins_each_freeing_a_different_vec`
    19.90 → 18.71 s; the other 25 with Elab.lean +0.19 s in all, each
    within −0.06 to +0.07 s; the 30 without −0.55 s.
  - Before the four changes below, the same run gave 78.4 s against 76.3 s
    (+2.8 %): the 6 new programs +1.43 s, the other 56 +0.37 s.
- **What won it back**, each found by timing `decide +kernel` of `elabIs`
  on the bundles' words (the file with the theorem minus the one without,
  best of 3), and checked to change no answer by the parity run (the same
  223 matches, 0 DIFF, 0 LAX, words and full words the same):
  - a drop's check read every mention of every variable in the body (one
    list, `mentionsFrom`) for each drop. It now reads the lines after the
    drop, as bits of one number (`maskAfter`: bit `i` set where a line names
    `i`; `lineMask` of each line, `maskAfter` of each suffix of a body one
    term, so one pass serves every drop) and the drop's set as another;
    they share a bit exactly when a later line names a variable of the
    set. A set with a variable past `maskB` (4096) is read line by line as
    before (kernel witnesses of both). On a synthetic body of 50 Vecs (400
    lines) `elabIR` took 8.3 s, 5.1 s with the lines read per drop, 3.6 s
    with the bits, 3.8 s with no drop check at all;
  - `retSplit` (does a list end in `ret`?) reversed the rest of a list at
    every statement, quadratic in its length; it now runs once a list
    (`go`'s `fr`: a suffix of a list that does not end in `ret` does not
    either);
  - the literals' temporaries were counted on entry to a statement and cut
    off by `take`/`drop` on its exit. The kernel keeps a state's fields as
    terms, so each `drop` was one more step every later read took again
    (65 000 unfoldings of `List.drop` on `joins…`); they are now set aside
    on entry and given back (`M.saveLits`);
  - a variable's last `v` line: the first from the end (`find?` on the
    reversed list, one term per function) instead of a fold over all.
  `joins…`'s Elab.lean part took 3.30 s of kernel (3.11 s at base), 2.53 s
  with the lines read per drop and the next two changes; the bits then took
  it from 2.26 to 1.83 s (both measured on a build without the witnesses).
  The 26 bundles that had Elab.lean at base: 10.31 s of kernel at base,
  9.27 s with the lines read per drop and the next two changes.
- **Peak memory** (the summed RSS of certify's process tree, sampled every
  5 ms), against the same base: the largest peak 2585 → 2585 MiB
  (`joins…`); the 6 new programs +22 to +36 MiB each (`C.Elab` and the
  kernel's work in the one process); the other 56 within −17 to +8 MiB;
  the sum of the 62 peaks +0.2 %.
- **Where the rest goes.** The kernel's time is spread: no pass of
  `elabIR` but the drop's check costs more than ≈ 0.05 s alone on a small
  program, and `perf` on Lean shows term instantiation and the kernel's
  caches (hash lookups, freeing) on top, not any one definition. Of
  nurl-cert's own time (≈ 60–110 ms a program, built `-O0` by the
  selftest), 86 % is sha256 of formal/'s tree (7 MB of Lean sources, the
  manifest's `formal_tree`), and `lake env` adds ≈ 50 ms a run before
  Lean starts; neither is this step's, and both are the same for base and
  branch.
- A translator limit seen on the way: tolean.nu crashes (exit 139, stack)
  on a synthetic body of 50 such Vecs, which `elabIR` reads; certify has
  no term for such a program, so no Elab.lean either.

## Next

**`elab` in Lean (route b)**, in formal/C/Elab.lean: the translator's
rules over words. Done: the claims rest on `elabIR` for the subset of
numbers (steps 2 and 3), buffers of numbers (step 4), views, slices,
`foreach` and changes through a borrow (step 5), closures (step 6) and
structs and options (step 7), and `verify` checks the words against
`Program.core`. Then:
- the subset widened rule by rule (destructors; threads);
- the per-encoding rows above replace `translation`;
- kernel time is measured on the corpus;
- `elab`'s parity with the NURL translator is shown over the sweep.
