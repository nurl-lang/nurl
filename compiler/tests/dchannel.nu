// dchannel.nu — offline tests for stdlib/ext/dchannel.nu.
//
// No sockets: drives the server-side channel store through rpc_dispatch
// in-process (the same path the HTTP handler would take), so the full
// send/recv/full/closed/len state machine is exercised deterministically.
// The networked client path is covered by examples/dchannel.nu.
//
// Channel "q" has capacity 2:
//   send 10 → ok, send 20 → ok, send 30 → full (cap reached)
//   len → 2
//   recv → 10, recv → 20, recv → empty (FIFO drained)
//   close, then recv → closed, send → closed

$ `stdlib/ext/dchannel.nu`

// Dispatch one RPC against the registry; returns the owned response env.
@ disp Registry r s fn Json args → Json {
    : Json req ( json_obj_new )
    ( json_obj_set req `fn` ( json_str_lit fn ) )
    ( json_obj_set req `args` args )
    : Json env ( rpc_dispatch r req )
    ( json_free req )
    ^ env
}

@ result_field_str Json env s key → s {
    : ?Json rj ( json_obj_get env `result` )
    ^ ?? rj {
        T r → {
            : ?Json fj ( json_obj_get r key )
            ?? fj { T x → ( json_as_str x ) F → `` }
        }
        F → `?`
    }
}

@ result_field_int Json env s key → i {
    : ?Json rj ( json_obj_get env `result` )
    ^ ?? rj {
        T r → {
            : ?Json fj ( json_obj_get r key )
            ?? fj { T x → ( json_as_int x ) F → - 0 1 }
        }
        F → - 0 1
    }
}

// Build {ch:"q", v:n}
@ send_args i n → Json {
    : Json a ( json_obj_new )
    ( json_obj_set a `ch` ( json_str_lit `q` ) )
    ( json_obj_set a `v` ( json_int n ) )
    ^ a
}

@ name_args → Json {
    : Json a ( json_obj_new )
    ( json_obj_set a `ch` ( json_str_lit `q` ) )
    ^ a
}

@ pstatus s label Json env → v {
    ( nurl_print label )
    ( nurl_print ( result_field_str env `status` ) )
    ( nurl_print `\n` )
}

@ main → i {
    : DStore store ( dstore_new 8 )
    ( dstore_declare store `q` 2 )  // capacity 2
    : Registry reg ( registry_new )
    ( dchan_register store reg )

    // ── fill to capacity ─────────────────────────────────────────
    : Json e1 ( disp reg `dchan/send` ( send_args 10 ) )
    ( pstatus `send 10: ` e1 ) ( json_free e1 )
    : Json e2 ( disp reg `dchan/send` ( send_args 20 ) )
    ( pstatus `send 20: ` e2 ) ( json_free e2 )
    : Json e3 ( disp reg `dchan/send` ( send_args 30 ) )
    ( pstatus `send 30: ` e3 ) ( json_free e3 )  // full

    // ── depth ────────────────────────────────────────────────────
    : Json el ( disp reg `dchan/len` ( name_args ) )
    ( nurl_print `len: ` ) ( nurl_print_int ( result_field_int el `len` ) )
    ( json_free el )

    // ── drain (FIFO) ─────────────────────────────────────────────
    : Json r1 ( disp reg `dchan/recv` ( name_args ) )
    ( nurl_print `recv: ` ) ( nurl_print ( result_field_str r1 `status` ) )
    ( nurl_print ` v=` ) ( nurl_print_int ( result_field_int r1 `v` ) )
    ( json_free r1 )
    : Json r2 ( disp reg `dchan/recv` ( name_args ) )
    ( nurl_print `recv: ` ) ( nurl_print ( result_field_str r2 `status` ) )
    ( nurl_print ` v=` ) ( nurl_print_int ( result_field_int r2 `v` ) )
    ( json_free r2 )
    : Json r3 ( disp reg `dchan/recv` ( name_args ) )
    ( pstatus `recv: ` r3 ) ( json_free r3 )  // empty

    // ── close + post-close behaviour ─────────────────────────────
    : Json ec ( disp reg `dchan/close` ( name_args ) )
    ( pstatus `close: ` ec ) ( json_free ec )
    : Json r4 ( disp reg `dchan/recv` ( name_args ) )
    ( pstatus `recv after close: ` r4 ) ( json_free r4 )  // closed
    : Json e4 ( disp reg `dchan/send` ( send_args 40 ) )
    ( pstatus `send after close: ` e4 ) ( json_free e4 )  // closed

    // ── DSend variant names ──────────────────────────────────────
    ( nurl_print_str ( dsend_name # DSend DSendOk ) )
    ( nurl_print_str ( dsend_name # DSend DSendFull ) )
    ( nurl_print_str ( dsend_name # DSend DSendClosed ) )
    ( nurl_print_str ( dsend_name # DSend DSendErr ) )

    ( registry_free reg )
    ( dstore_free store )
    ^ 0
}
