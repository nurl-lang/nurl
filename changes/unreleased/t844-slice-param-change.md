### Fixed

- **A change made through a slice of a parameter's Vec now counts as a change of that parameter** (AGORA-844). Take `@ ext ( Vec String ) v → v { : ( Slice String ) sl ( slice_from_vec [String] v ) ( string_push_str ( slice_at [String] sl 0 ) … ) }`. Clearing an element through `sl`, `slice_put`, a window, or a slice handed back by a helper was in no summary, so a caller's view into `v`'s element dangled after `( ext v )`. That view is now refused. A struct literal that holds the slice is still open.
