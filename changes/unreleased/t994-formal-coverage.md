### Fixed

- **`tools/ncore/tolean.py` changes a loop's element through the element
  itself** (AGORA-994). A change of a `foreach` element's elements, such as
  `string_push_str x …`, `vec_clear` or `vec_truncate`, went through a fresh
  borrow of the element. The element, reached `.inner` from the container,
  then ended with the change made through it, so the verified checker
  refused a program that grows a loop element and reads it again. The
  change now goes through the element binding, as the program's own call
  does. `loop_element_grown_through_itself_then_read_runs_clean` is
  accepted. No other verdict among the sweep's translated programs changes,
  and every one that must be rejected still is.
- **`tools/ncore/tolean.py` hands a string literal to a raw-string parameter
  as text** (AGORA-994). A literal argument was translated as an integer, so
  a call passing a literal to an `s` parameter failed to type and the
  program was refused. It is now a buffer of its own for the call, as a raw
  string bound from a literal already is. That is stricter than the
  program, where the literal never dies. `local_option_moved_into_inout`,
  `inout_option_replaced_leaks` and
  `struct_owners_rotated_by_assignment_in_a_loop_runs_clean` are accepted.
  No other translation changes.
- **`tools/ncore/tolean.py` takes a parameter nurlc infers consumed as
  `sink`** (AGORA-994). It read a parameter's mode only from the flag the
  IR's variable line carries, so a parameter that the walk infers consumed
  (handed on to a `sink`, recorded in the summary's `sink=`) was translated
  as lent. The caller was then charged with a drop nurlc never makes, and
  the move refused. `kwargs_forward_consuming_callee` is accepted; the two
  other programs whose translation changes must be rejected and still are.
- **`tools/ncore/tolean.py` captures a buffer that a closure literal moves
  in by value** (AGORA-994). A captured String or `Vec` was always
  translated as captured by name, a read of the creating binding. That is
  right for a closure that shares a handle with a binding that lives on,
  but not for one whose literal takes the binding over: the creating
  function never releases or reads it again, so the environment owns it.
  Such a closure handed back over its local was refused as escaping. A
  capture that every literal of the code moves in is now a capture by value
  in the environment. `string_captured_by_a_returned_closure_runs_clean` is
  accepted; all 11 must-reject programs whose translation changes are still
  refused.
