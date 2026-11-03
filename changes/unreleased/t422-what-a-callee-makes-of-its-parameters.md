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
