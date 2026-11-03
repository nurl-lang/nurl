### Fixed

- **What a function makes of its parameters' views reaches its callers**
  (Agora #422, #341, #370, #380, #404, #442, #454, #369; probes
  holder_viewing_a_string_param_*, view_param_*,
  enum_literal_viewing_a_param_returned and others). A function that
  handed back a value holding views of its parameters' storage gave its
  caller a result that depended on nothing. That covered a local Vec
  filled with views of a String parameter, by itself or by a named, `dyn`
  or recursive callee, in a loop or a join; views of a parameter's
  elements; and a struct or enum literal of a view beside an owned field.
  Kept past the argument, the result read freed memory. The function's own
  borrow walk now records which parameters the value it hands back views,
  and the caller's result depends on those arguments. A view parameter
  (an `s` its caller owns) now counts as a source too. Stored into a local
  copy, into an `inout` holder that is not the first argument, or through
  a borrow, a field or an element of one, it ties that holder to what the
  caller passed. Before, it tied the first argument or nothing. The same
  holds for a view stored whole into an `inout` holder as part of a
  struct, and for one stored through a loop element, a join or an element
  binding of the function's own parameter. A closure
  may not hand back a value holding views of what it captured: a struct or
  an enum now follows the rule a bare view always did.
- **A cursor that may own its value is released when it moves on**
  (probes cursor_over_a_local_view_resliced_in_a_loop,
  cursor_given_its_own_slice_on_one_arm and others). A binding that
  borrowed on one path and held a value of its own on another was taken
  for a plain borrow where the paths met. Re-pointing it was thought to
  free nothing, so a copy taken from it before was read after the value
  it pointed into was released. That covered the split-on-delimiter loop
  whose last piece is the cursor itself, and a `?` or `??` arm that gave
  the cursor a slice of its own. Such a binding now may own its value:
  re-pointing it ends what was borrowed from it. nurlc's own unused-import
  lint had this shape and now reads each piece before moving on.
