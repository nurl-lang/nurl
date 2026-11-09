### Fixed

- **A closure that gives a captured string bound from a borrow a new value
  is refused with a diagnostic, not left to fail in clang** (Agora #465).
  `: ~ s cur ( string_data src )` and then `= cur …` inside a closure: cur
  is a guarded `s`, whose owner and the proof of it are two slots of the
  enclosing function. The closure's code updated those slots through the
  enclosing function's registers, and the build died in clang with "use of
  undefined value". nurlc now says why and what to write instead: bind a
  string the function owns (nurl_str_cat's or nurl_str_slice's result),
  keep the text in a String, or return the new string from the closure. A
  value that may view something keeps the walk's own refusal ("a closure
  cannot give 'cur' a view of …"). Nothing that compiled before is
  refused.
