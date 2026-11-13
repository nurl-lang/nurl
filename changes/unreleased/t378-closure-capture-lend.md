### Fixed

- **An owner given a lend out of a closure's capture no longer leaks its
  old value** (Agora #378). Inside a closure, `= o ( first vs )` kept o's
  old value back on every call, because nurlc cannot tell whether the
  captured `vs` holds o's own value. The assignment now checks by key at
  run time.
