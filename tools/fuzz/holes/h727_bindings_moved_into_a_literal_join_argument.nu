// H727: as h725, the literals' fields bindings: placed in a literal they
// moved in (mem_note_kept), so the literal owned them — and was dropped
// by no one.
// Closed: the join's ownership bit is taken for the call before
// mem_lent_cond consumes it (arg_join_own), and mem_arg_temps drops the
// joined value by it unless the callee keeps, consumes or hands it back
// (agora #174).
// v0.80.0: HOLE (detected memory leaks).
$ `stdlib/core/string.nu`

: S { String s i pad }

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ use S h → i { ^ ( string_len . h s ) }

@ main → i {
    : ~ i n 0
    ~ < n 4 {
        : String a ( mk )
        : String b ( mk )
        ( nurl_println_int ( use ? == 0 % n 2 @ S { a 0 } @ S { b 1 } ) )
        = n + n 1
    }
    ^ 0
}
