// diag_arity_swallow_own_binding.nu — '+' one operand short swallows the
// next statement, which uses the very binding being initialised. That
// used to be reported at the use as "use of undefined identifier 'b'";
// the mistake is the binding's initialiser, so that is where it points.

@ main → i {
    : i a 3
    : i b + a
    ( nurl_println_int b )
    ^ 0
}
