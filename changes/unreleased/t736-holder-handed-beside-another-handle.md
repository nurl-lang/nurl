### Fixed

- **A value holding closures, handed to a function that runs them beside
  another handle on what they change, is refused** (Agora #736). A struct,
  an option or a Vec holding a closure that replaces an Rc's payload,
  handed to a function together with another handle on that Rc, let the
  function view the payload through the handle and then run the closure;
  the view read freed memory. It is refused now, naming the value and the
  closure's change ("a closure the value at argument 1 holds"). The
  function is asked whether it runs what that parameter holds, through any
  helper it hands it to, so registering one more closure into a holder
  beside such a handle, as a server's tool registration does, still
  compiles.
