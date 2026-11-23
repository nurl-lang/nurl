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
