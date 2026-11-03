### Fixed

- **An enum that can hold a view is an owner of views** (Agora #338;
  probes enum_viewing_a_line_*, *_viewing_a_line_pushed_out). The borrow
  check asked whether a type can hold a view and answered no for every
  enum, so a token over a line (`Tok { Word s Num i Bad String }` holding
  `( string_data line )`) was an owner of nothing borrowed. Pushed into an
  outer Vec, stored into a field, copied into a literal, captured by a
  closure, passed through a generic, wrapped in an option, an outer enum or
  a struct, or made in a loop, it was kept past its String and read freed
  memory. An enum now holds a view when one of its variants' payloads can,
  as a struct does when one of its fields can, and the answer is exact for
  recursive and deeply nested types (it used to stop 16 levels down, so a
  view 17 struct levels down was missed too). A `??` payload read out of
  such an owner holds what the owner views, so it may outlive the token
  but not the String the token views.
