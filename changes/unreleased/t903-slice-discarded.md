### Fixed

- **A slice discarded as a statement is released** (AGORA-903, part). Examples: a call `( mk )`, a slice join `? c ( mk ) a`, and a bare literal `[i | 1 2]`, each written as a statement. The discard path released only handles, so the fresh slice leaked. It is now released by its own answer: a call's (always fresh, or per run), a slice join's bit, or always for a literal. A slice that is only lent, such as `( id a )`, is never released.
