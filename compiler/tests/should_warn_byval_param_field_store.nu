// should_warn_byval_param_field_store.nu — assigning to a FIELD of a
// by-value struct parameter is a silent lost write.
//
// The parameter-context sibling of should_warn_byval_capture_assign:
// the same violation ("this write goes nowhere"), one context over. A
// struct parameter arrives by value, so `= . p field v` lands in the
// callee's own copy and the caller never sees it. Value semantics are
// intentional (function_param_mut.nu pins them), but they are
// invisible: the store compiles, runs, and does nothing.
//
// What makes it a trap rather than a rule anyone remembers is that the
// SAME struct propagates mutations made through its handle-typed
// fields — `( vec_push . p items x )` is seen by the caller, because a
// Vec shares its control block. A scalar field sitting beside a Vec
// field therefore looks like it behaves the same way, and does not.
// Found in stdlib/ext/mqtt.nu, where `next_pid` never advanced past 1
// and the keep-alive deadline never moved.
//
// NOT warned: the modify-a-copy-and-return-it idiom, where the write
// reaches the caller through the return value. `bump_returning` below
// must stay silent, or the warning would fire on correct code often
// enough to be ignored.

$ `stdlib/core/vec.nu`

: Client { i seq ( Vec i ) log }

// Lost write: the caller's `seq` never advances.
@ bump Client c → i {
    = . c seq + . c seq 1
    ^ . c seq
}

// Not a lost write: the mutated copy IS the return value.
@ bump_returning Client c → Client {
    = . c seq + . c seq 1
    ^ c
}

// Not a lost write either: a Vec field shares its control block.
@ record Client c i v → v {
    ( vec_push [i] . c log v )
}

@ main → i {
    : ~ Client c @ Client { 0 ( vec_new [i] ) }
    ( bump c )
    ( bump c )
    ( record c 7 )
    = c ( bump_returning c )
    ( nurl_print `seq=` ) ( nurl_print ( nurl_str_int . c seq ) ) ( nurl_print `\n` )
    ( nurl_print `log=` ) ( nurl_print ( nurl_str_int ( vec_len [i] . c log ) ) ) ( nurl_print `\n` )
    ( vec_free [i] . c log )
    ^ 0
}
