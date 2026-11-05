### Fixed

- **A closure that hands a captured `~` loop element to a callee that
  keeps it compiles.** A `~` loop element handed to a consumer leaves its
  container: its slot is emptied. Inside a closure body the capture
  inherited that slot, which is the enclosing function's element pointer,
  a register the body does not have, and clang rejected the IR ("use of
  undefined value"). In the body the capture is its own snapshot, and the
  container keeps its element. nurldb's parallel aggregate (`ParAgg`) had
  this shape. `compiler/tests/closure_capture_loop_element_consumed.nu`
  reproduces it.

### Changed

- **CI lowers every package entry point to IR and has clang compile it**
  (`tools/check_package_entries.py --ir`). The gate used to stop at
  `nurlc --check`, before code generation, so a compiler change that wrote
  IR clang rejects for code outside the compiler's own tests went
  unnoticed. nurllama stopped compiling that way. The two code generation
  bugs this release fixes were both invisible to the old gate: a library
  handle that opens with a `Locked`, and the closure capture above. Each
  entry is lowered with `--no-dce`, so a library's functions are checked
  even when no `main` reaches them.
