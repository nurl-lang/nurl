### Fixed

- **A borrow of a lent value now ends when a forwarder defined above its
  caller changes that value** (Agora #352). A value lent by a call, such
  as an element of a Vec of Vecs, handed to a function that clears or
  replaces it through another function, ended the borrows of its contents
  only when that function was compiled after the call. A function compiled
  earlier, and every standard library forwarder (`string_push_str`), had no
  final summary yet and looked as if it changed nothing. A String borrowed
  from the element then survived the change and was read after it was
  freed. The call now records the lent argument for any NURL callee, and
  the borrow checker decides from the callee's final summary, as it already
  did for a callee defined later.
