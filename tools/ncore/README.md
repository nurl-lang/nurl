# ncore: a reference checker over a core IR (AGORA-441 prototype)

This is a prototype, not a part of the toolchain. It tests one claim from
[docs/dev/PROPOSAL_CORE_IR.md](../../docs/dev/PROPOSAL_CORE_IR.md): one
checker that reads only a core IR, with every producer form let-bound,
decides the hole probes without any code per surface spelling.

| file | what it does |
|---|---|
| `syntax.py` | lexer and parser for the subset the probes use; `Unsupported` for the rest |
| `load.py` | a probe and the headers of the core stdlib files it imports |
| `lower.py` | surface AST → core IR: every call, join, match and value block becomes a temporary, in evaluation order |
| `check.py` | the checker: places, loans, effects, formal/A2's `Eff.kills` lifted to places, summaries by a whole-program fixpoint |
| `prims.py` | declared summaries of the stdlib functions the probes call (the `unsafe` trust boundary) |
| `fromnurlc.py` | nurlc's core IR (`--emit-core`) read into the form `check.py` checks |
| `derive.py` | the summary of a library function whose body crosses the raw boundary, from what the walk believes of it (`sum` lines), where `prims.py` declares none |
| `RULES.md` | the rules `check.py` checks, each with where docs/MEMORY.md states it |
| `run.py` | runs probes and compares the verdict with each probe's `// map:` line |
| `openprobes/` | probes written from open hole tickets |

`fromnurlc.py` reads the core IR nurlc itself builds
(`nurlc --emit-core`, [docs/dev/CORE_IR.md](../../docs/dev/CORE_IR.md)):
with `--nurlc` the checker runs on what the compiler lowered, for every
probe and every construct, and `syntax.py` / `lower.py` are not used.

```
cd tools/ncore
PYTHONUTF8=1 python run.py --nurlc --jobs 8 --all  # every probe, on nurlc's IR (NURLC=<binary>; NCORE_CACHE=<dir> keeps the IR between runs)
PYTHONUTF8=1 python run.py --nurlc --clean --list files.txt  # programs nurlc accepts (examples, tests): every one refused is a rule too coarse
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
