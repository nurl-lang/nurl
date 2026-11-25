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
| scalars → `.int` | a number's value is no part of the memory model | design note, A2's `Ty.int`; nothing to prove beyond "the IR's `scalar` reads only numbers" |
| a raw string bound from a literal or a fresh string → `(.vec .int)`; held in a value → `(.slice .int)` | owned text vs a view (MEMORY.md §1, §2.13) | ledger row; needs the IR's own provenance flag to be proved |
| options → `sum int t`; structs → nested `prod`, one field = the field | layout-free shapes | design note (shapes only, no ownership choice) |
| destructor types → `.dtor f u`, a one-field struct padded with an int | `% Drop` runs `f` at the end of every value | design note + A2-drop's theorems |
| closures → `.fn [σ] .any`; captures by name vs in the environment (`CORE_VF_ENVOWN`), mode `inp` / `(.inout .drop)` | a capture by name is a dependency on the binding (MEMORY.md §2.11) | ledger row (the mode choice is precision, the code is checked against it, but by-name vs by-value is meaning) |
| channels → `lk (prod (vec A) int)` | A3.4's channel | design note, `Ty.ChanOf` |
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

## Next

Both remaining parts stay under AGORA-1020:
- **Threads and globals (part 1's rest).** nurlc lowers a spawn to a call
  of `thread_spawn` / `thread_spawn_owned` with a closure, returning a
  `!Thread ThreadErr` handle that is joined later. A3's spawn is a
  `letcall` of a function marked spawn-only (`TStep.spawn`). The
  translator is to map the closure's code to such a function, with its
  environment moved, the handle to an integer and the join to a read. That
  is sound because ignoring the join only adds interleavings. Globals
  become A3's declarations. certify then states `M.race` from
  `C.checked_claim_made_full`.
- **`elab` in Lean (route b)**, in formal/C/Elab.lean: the translator's
  rules over words. Then:
  - the certificate states its claims about `elab ir`;
  - `verify` checks the words against `Program.core`;
  - the per-encoding rows above replace `translation`;
  - kernel time is measured on the corpus;
  - `elab`'s parity with the NURL translator is shown over the sweep.
