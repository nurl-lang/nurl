### Fixed

- **A closure handed to a function that runs it on several threads is
  held to Sync** (Agora #713). `( par_map_index [i] 20000 8 f )` with `f`
  pushing to a captured `Vec` compiled, and eight threads pushed to one
  Vec at once (a double free). So did a helper of the program's own that
  spawns a thread per round of a loop running its closure parameter, one
  that spawns it twice, and one that hands it on to `par_map_index`. They
  are now refused: "'par_map_index' hands its parameter 3 to several
  threads or fibers, where several threads may run the closure at once,
  but the closure … changes 'seen' …". A helper that runs the closure on
  one thread still accepts one that changes its capture.
