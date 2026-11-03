### Fixed

- **A closure that reads its capture on some path before giving it a value
  is checked where it is made** (Agora #444; probes closure_made_assigns_*,
  closure_made_reads_its_capture_on_an_early_return_path). #358 skipped a
  capture assigned anywhere earlier in the body. An assignment in one
  branch, in a loop that may not run, in a nested or recover closure, or
  to another field, left a later read reading a dead capture. These are
  refused now. An assignment and read in the same block, or of the same
  field, stay accepted.
