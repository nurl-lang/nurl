### Removed

- **tools/ncore's own front end** (AGORA-1046). `syntax.py`, `load.py` and
  `lower.py` were a Python parser and lowering that mirrored nurlc's front
  end, so every change to how nurlc lowers a form had to be made twice.
  The reference checker now reads only the core IR nurlc itself prints
  (`nurlc --emit-core`, `fromnurlc.py`), which `run.py --nurlc` already did.
  `run.py` checks that way without the flag, and still accepts `--nurlc`.
  The IR's forms moved to `tools/ncore/ir.py`. It is development tooling
  only: no step of building, installing, compiling or certifying runs
  Python. That is the owner's rule (agora note python-dev-only): Python is
  for development where it genuinely helps, never on a path a NURL user
  runs, and never a mirror of a NURL component.
