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
| `run.py` | runs probes and compares the verdict with each probe's `// map:` line |
| `openprobes/` | probes written from open hole tickets |

```
cd tools/ncore
PYTHONUTF8=1 python run.py --list subset.txt      # the probes with no closures, traits, threads, Rc or generic definitions
PYTHONUTF8=1 python run.py openprobes/*.nu        # the open holes
PYTHONUTF8=1 python run.py <probe>.nu             # one probe, with its errors
```

The checker does not decide drops and does not generate code. Probes that
use `defer`, closures, results, traits, globals or generic definitions are
reported as skipped, never guessed.
