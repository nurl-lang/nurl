### Fixed

- **An option or result owner given what a call may lend out of itself
  or another argument is refused** (Agora #412, claude-formal's review of
  #342; probes *_may_lend_itself_or_*). Example: `= o ( pick o other 1 )`,
  where `pick` may lend either argument. Since #342, `o` kept its old
  ownership after storing `other`'s value, so both dropped it
  (heap-use-after-free). Before #342, the run that handed back `o` itself
  freed it under `o`. No answer per run is right on both runs, so the
  form is refused.
  - The other argument may be a lend rather than a bare name: `( id other
    )`, a field `. s y`, or a `?` join.
  - `o` may be a local or an `inout` parameter.
  - The message gives the fix: give `o` a copy, `= o ( mem_dup ( pick o
    other k ) )`, or bind the result to a new name.
  - Still accepted: `= o ( id o )`, and a fresh value as the other
    argument (`( pick o ( mk … ) k )`).
