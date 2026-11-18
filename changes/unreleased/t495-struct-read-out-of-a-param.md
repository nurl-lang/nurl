### Fixed

- **A struct read out of a parameter and handed to a callee that clears one of its fields now counts as a drop of that parameter** (AGORA-495, and the loop-element shapes of AGORA-811). Three forms were in no summary, so a caller's view into the cleared field dangled after the call:
  - an element bound first, `: H e ( vec_at [H] hs 0 )  ( wipe e )`;
  - a loop element, `~ w ws { ( wipe w ) }`;
  - a field of a parameter read whole, `: P e . q p  ( wipe . e h )`.

  These are refused now. The summary keeps the field path, so a view of a sibling field stays accepted.
