// println_builtin.nu — nurl_println: nurl_print plus a trailing
// newline, available everywhere without an import (it lives in
// runtime_core.c next to nurl_print / nurl_eprintln).
//
// Determinism: pure stdout writes, no clock/socket/env. ASan-clean.

@ main → i {
    ( nurl_println `hello` )
    ( nurl_print `a` )
    ( nurl_println `b` )
    ( nurl_println `` )
    ( nurl_println `done` )
    ^ 0
}
