// pub_prefix_scoped_mod.nu — helper for pub_prefix_scoped.nu.
//
// The shape that mattered: a module whose LAST top-level declaration
// carries a `pub` prefix on something other than an `@`-function. The
// scan_fn_sigs pre-pass set its pending-pub flag before dispatching and
// only the `@` arm ever cleared it, so the flag survived this file's
// end and attached itself to the first `@` the scanner reached in the
// IMPORTING file.
pub %Ping [T] {}
