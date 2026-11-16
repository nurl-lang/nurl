### Fixed

- **What a value block binds lives, to the borrow checker, as long as codegen keeps it: to the end of the enclosing scope** (Agora #846, #839, #847, #638's rest). MEMORY.md §1 already said so, but the checker ended those bindings at the block's `}`. From then on, nothing tied a view or a closure of one to its real life. These shapes read freed memory (heap-use-after-free) while their unblocked spellings were refused:
  - `: s d { : String t … ( string_data t ) }  ^ d`;
  - `= b ( id { : String t ( mk k ) t } )` in a loop, with `b` read after it;
  - `= keep f` inside a block whose value is `f`, then `= keep …` and a call of the block's value;
  - a `;` defer calling a closure that was assigned from a value block;
  - a view chained through a second binding of the block and handed back, `: s e { : s t ( nurl_str_cat … ) : s w t  w }  ^ e`, as a raw string, a slice or a Vec element.

  Each is now refused with the message of its unblocked spelling. A view of a block's binding read in the same scope stays accepted, and so does a block's owned tail handed back. The block's *names* still end at its `}`. No other program in the tree changes verdict. Eleven probes guard the fix: nine refused and two that run clean. They replace the engine's open probes for these holes.

### Changed

- **The borrow checker's scope scans read each row's kind from its cached code instead of copying the row** (`__bck_scope_lets`, `bck_scope_restore`). With the #846 fix, compiling nurlc itself takes 0.23 % fewer instructions (callgrind: 25.90 G → 25.84 G), with the same peak memory (243 MB). Every tracked program compiles to the same verdict and the same code as before (tree sweep: every tracked file but the new probes byte-identical).
