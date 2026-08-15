# tools/metamorph — does the checker answer the same question the same way?

The fuzzers in [`tools/fuzz`](../fuzz) ask **"does this program compute the
right value?"** — differential, against an oracle. This asks a different
question, on the axis where nurlc's diagnostics have actually been wrong:

> the same semantic situation, written N ways, must get the **same verdict**
> from the checker.

## Why this axis

Four consecutive fixes in August 2026 were all one shape. The checker asked
its question at one syntactic spelling and missed the others:

| PR | asked at | missed |
|---|---|---|
| #898 | a non-generic wrapper that frees its parameter | the same wrapper, generic |
| #899 | `: T b a` | `?` · `??` · `=` · a callee returning its argument |
| #901 | a box-shaped payload slot | a slot declared as a number |
| #902 | mutation inside the thread closure | mutation one call deep |
| #910 | a capture *spelled* `Rc` | the Rc one field / element / payload / Arc / closure / boundary away |

None of these was the analysis being *too weak in theory*. Each was coverage
across spellings that nobody had enumerated. That is mechanizable, so this
enumerates it.

It earned its keep on the first run: four gaps, one of which
(`arc-shared-mutation/helper-two-deep`) was a hole in #902 — shipped hours
earlier — where the summary stopped being transitive at depth two. The
"wrap it one level further" escape the summary exists to close was still
open, and no human had thought to try depth two.

## Running it

```bash
./build.sh                                   # needs build/nurlc
tools/metamorph/spellings.py                 # report; exit 1 on a NEW gap
tools/metamorph/spellings.py --verify        # + ASan-confirm every gap
tools/metamorph/spellings.py --class NAME    # one class
tools/metamorph/spellings.py --update-known  # re-baseline after fixing one
```

`--verify` wants a sanitized **runtime**, never a sanitized **compiler**.
Leaving `build/nurlc` sanitized turns each of the ~80 compiles into an
ASan+LSan run: the sweep goes from **1.5 seconds to ~50 minutes** and looks
hung when it is only crawling. The tool warns when it detects this. Keep a
sanitized runtime aside and point at it:

```bash
./build.sh --san --no-tests && cp stdlib/runtime.o /tmp/rt-san.o
./build.sh                                  # normal compiler back
NURL_SAN_RUNTIME=/tmp/rt-san.o tools/metamorph/spellings.py --verify
```

## How a finding is judged

A disagreement between spellings is **not** proof of a compiler bug — the
template may simply not express the same situation. So a spelling that is
accepted where its class says reject is escalated: rebuilt with
`--no-borrowck` and run under AddressSanitizer.

- **confirmed** — it crashed, leaked, or hung. The program really is broken
  and the checker really missed it.
- **UNCONFIRMED** — it ran clean. Look at the template first, not the
  compiler. A silent-wrong-*value* bug also lands here, because ASan has
  nothing to say about arithmetic on a boxed pointer; those need a value
  oracle, which is what `tools/fuzz` is for.

That escalation is the whole difference between a bug finder and a
generator of plausible-looking noise.

## The classes

Each carries a **severity**, and the worklist ranks by it. Not every
disagreement is a memory-safety bug, and pretending otherwise would make
the output useless for deciding what to fix first.

- **`handle-second-name`** *(memory-unsafety)* — a heap handle acquires a
  second name and both are freed.
- **`use-after-free`** *(memory-unsafety)* — a handle is READ after being
  freed. Nothing frees twice; the buffer is simply gone.
- **`loop-carried-free`** *(memory-unsafety)* — an outer binding freed
  inside a loop body (§2.6). Its documented exemptions are controls.
- **`arc-shared-mutation`** *(memory-unsafety)* — a thread closure mutating
  the contents of an `Arc` it did not create, unlocked.
- **`thread-nonsend`** *(memory-unsafety)* — an `Rc` reaching a worker.
- **`option-payload-type`** *(silent-wrong-value)* — a payload that is not
  the type the option was declared over. ASan has nothing to say about
  arithmetic on a boxed pointer, so these land in UNCONFIRMED by
  construction; a value oracle is `tools/fuzz`'s job.
- **`iterator-invalidation`** *(diagnostic-consistency)* — mutating a
  container under a `~ x xs` foreach (§2.5). Deliberately **not** ranked as
  unsafety: measured, a forced realloc mid-iteration does not dangle,
  because a `Vec` is a handle to a control block and the loop reads through
  it. The rule is a conservative guard, so a gap is an inconsistency in
  what gets *diagnosed* — the direct push warns, the same push one call
  deep does not.
- **`controls`** — correct programs, in a class of their own. A checker that
  rejects these is worse than one that misses a bug: every entry is code
  someone would reasonably write, and one of them (`mutex-guarded-mutation`)
  is the cure the Arc diagnostic itself recommends. An earlier draft of that
  check rejected it.

## The gate

`known_gaps.json` is the baseline. A **new** gap fails; a **control**
regressing fails loudly and separately, because a false positive is the
worse failure. Removing an entry is progress — fix the checker, then
`--update-known`.

Adding a spelling costs three lines and is the point: if you fix a checker
hole, add the spelling that was missing *and* the two neighbours nobody
tried.
