// private_type_argument.nu — a private type passed as a type argument is
// judged where it is written, not inside the instance.
//
// private_type_argument_mod.nu keeps `Impl` private and writes
// `rcbox_new [Impl]` itself, where `Impl` is visible. The instance's body
// (`RcBox__Impl`, parsed in a pseudo-file) was checked as if it named
// `Impl` from outside the module and rejected it, so every strict module
// that kept its state in an rcbox had to make the state struct `pub`.
$ `compiler/tests/private_type_argument_mod.nu`

@ main → i {
    : H h ( h_new )
    ( nurl_println_int ( h_x h ) )
    ^ 0
}
