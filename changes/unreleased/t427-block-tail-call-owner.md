### Fixed

- **`= o { … ( f o … ) }`: a value block ending in a call is that call to
  the owner's rules** (Agora #427). When the tail call may hand back o's
  own value, o's value was released and stored back freed. The block now
  gets the same per-run key check as `= o ( f o … )`. An option owner
  given a block whose tail call may hand back o or another argument is
  now refused, as the direct form already is.
