### Changed

- **The formal proof's memory invariant says that a binding whose type holds no by-name closure holds no package that captures by name, in a live slot or a dead one** (AGORA-937, a B4 piece). Before, only a live binding's value was known to be of its type in this respect; a dead slot's leftover value was not. `MInv.noPkg` now carries it. Every step keeps it: a right-hand side's value is of its type whether owned or lent (`ValOK.no_pkg`), and the call setup and a spawned thread's frame give it to their parameters. Nothing changes in nurlc.
