// nested_closure_decl.nu — guard against the IR-codegen regression
// fixed 2026-05-23: a `: ( @ v ) name \ → v { ... }` binding inside
// ANOTHER closure's body used to spill the outer closure's body
// bytes at module scope, producing `error: expected 'type' after
// name` at LLVM-link time. Root cause was the single-instance print
// buffer in `stdlib/runtime.c §1` — the inner gen_closure_expr's
// reset+start wiped the parent's buffered IR.
//
// Fix: the print buffer is now a 32-deep stack; `start` pushes a
// fresh empty frame, `stop` snapshots-and-pops. `reset` is a no-op
// when the stack is non-empty so it cannot reach across frames.
// See `nurl_print_buf_start` in runtime.c for the protocol.

@ leaf → v {
    ( puts `leaf` )
}

@ outer → v {
    : ( @ v ) outer_cb \ → v {
        // Nested :-binding inside outer_cb's body — the failing case.
        : ( @ v ) inner_cb \ → v {
            ( leaf )
        }
        ( inner_cb )
    }
    ( outer_cb )
}

// Three-level nesting exercises the stack to depth ≥3.
@ outer3 → v {
    : ( @ v ) lvl1 \ → v {
        : ( @ v ) lvl2 \ → v {
            : ( @ v ) lvl3 \ → v {
                ( puts `lvl3` )
            }
            ( lvl3 )
        }
        ( lvl2 )
    }
    ( lvl1 )
}

@ main → i {
    ( outer )
    ( outer3 )
    ^ 0
}
