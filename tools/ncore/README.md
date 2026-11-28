# ncore: a reference checker over a core IR (AGORA-441 prototype)

This is a prototype, not a part of the toolchain. It tests one claim from
[docs/dev/PROPOSAL_CORE_IR.md](../../docs/dev/PROPOSAL_CORE_IR.md): one
checker that reads only a core IR, with every producer form let-bound,
decides the hole probes without any code per surface spelling.

| file | what it does |
|---|---|
| `ir.py` | the core IR's forms (`FnIR`, `Var`, `Program`) and the type facts the checker asks (`Types`); `Unsupported` for a construct it does not model |
| `check.py` | the checker: places, loans, effects, formal/A2's `Eff.kills` lifted to places, summaries by a whole-program fixpoint |
| `prims.py` | declared summaries of the stdlib functions the probes call (the `unsafe` trust boundary) |
| `fromnurlc.py` | nurlc's core IR (`--emit-core`) read into the form `check.py` checks |
| `derive.py` | the summary of a library function whose body crosses the raw boundary, from what the walk believes of it (`sum` lines), where `prims.py` declares none |
| `RULES.md` | the rules `check.py` checks, each with where docs/MEMORY.md states it |
| `disagree.tsv` | the probes whose `// map:` verdict the rules do not give yet, and how (the work left) |
| `show.py` | one program: its verdict, errors and summaries; `--trace FN` the state after each statement |
| `diagcmp.py` | the engine's diagnostics against the walk's goldens (compiler/tests): the same line, another, none |
| `run.py` | runs probes and compares the verdict with each probe's `// map:` line |
| `openprobes/` | probes written from open hole tickets |
| `tolean.py` | nurlc's core IR as a program of formal/A2's calculus, for the verified checker of formal/C (AGORA-975). The reference of nurl-cert's translator (`packages/nurl-cert/src/tolean.nu`, AGORA-1020), which certificates are made with: a change to one is made to the other, and `tolean_parity.sh` holds them to the same bytes |
| `certify.sh` | one program through `--emit-core`, `tolean.py` and the verified checker (`C.progOK2B`, `C.checkA2`), by `#eval`: `accepted`, `refused` or `unsupported: …`. The prototype of `packages/nurl-cert` (AGORA-1019), which states the verdict's consequences as kernel-checked theorems in a certificate bundle (docs/dev/CERTIFICATE.md) and is what CI runs (`certify.yml`); kept for the sweeps that read its one-word answer |
| `certify/` | the certify programs: `*_refused.nu` must be refused, every other one certified (`packages/nurl-cert/tests/nurl-cert_test.sh`) |
| `tolean_selftest.sh` | edits of a certify program's core IR that `tolean.py` must report `unsupported` (fail-closed) |
| `tolean_parity.sh` | `nurl-cert translate` (the translator in NURL, `packages/nurl-cert/src/tolean.nu`) against `tolean.py`, its reference, over every certify program and every hole probe: stdout byte for byte, the exit's class and the `unsupported` message, with both timed (AGORA-1020) |

`fromnurlc.py` reads the core IR nurlc itself builds
(`nurlc --emit-core`, [docs/dev/CORE_IR.md](../../docs/dev/CORE_IR.md)):
the checker runs on what the compiler lowered, for every probe and every
construct. It has no front end of its own: the parser and lowering that
mirrored nurlc's went in AGORA-1046, by the owner's rule that Python is
development tooling only and mirrors no NURL component (agora note
python-dev-only). Nothing here is on a path a NURL user runs.

```
cd tools/ncore
PYTHONUTF8=1 python run.py --jobs 8 --all  # every probe, on nurlc's IR (NURLC=<binary>; NCORE_CACHE=<dir> keeps the IR between runs)
PYTHONUTF8=1 python run.py --clean --list files.txt  # programs nurlc accepts (examples, tests): every one refused is a rule too coarse
PYTHONUTF8=1 python show.py --trace main <probe>.nu          # why: the state after each statement
```

The same rules are in the compiler (`nurlc --engine`, docs/dev/CORE_IR.md
§7). `engcmp.py` holds the two together:

```
PYTHONUTF8=1 python engcmp.py --verdicts --jobs 8   # every probe of results_nurlc.tsv: the engine's verdict against the one recorded there
PYTHONUTF8=1 python engcmp.py --list files.txt      # the engine's reading of every type against this checker's
PYTHONUTF8=1 python diagcmp.py --jobs 8 --tsv out.tsv  # every refusal golden: is the engine's first finding on the walk's line?
```

A rule changed here is changed there, and the other way round: the
comparison is what says they are still one table.

`--all` ends by comparing with `disagree.tsv`: a probe that agrees
now is progress (`--write-list` takes it off the list), one that joined
the list is named and the run fails. A change to the rules is held to
that line, and to `--clean` over examples/ and the valid compiler tests.

```
PYTHONUTF8=1 python run.py --list subset.txt      # the probes with no closures, traits, threads, Rc or generic definitions
PYTHONUTF8=1 python run.py openprobes/*.nu        # the open holes
PYTHONUTF8=1 python run.py <probe>.nu             # one probe, with its errors
```

The checker does not decide drops and does not generate code. What it has
no rule or no declared summary for is reported as skipped, never guessed:
on its own parser that is `defer`, closures, results, traits, globals and
generic definitions; on nurlc's IR, a program nurlc itself stops with a
diagnostic that is no ownership rule (typing, the raw boundary).

On nurlc's IR the program's own functions are checked. A library function
is trusted: one whose body stays inside the raw boundary is walked for its
summary; one that crosses it is answered by `prims.py`, or by `derive.py`
from the walk's own summaries.
