// escape_inside_block_detached: agora #214 — a callee's `thread_spawn cb` inside `? go { … }`: the escape was never summarised, and a closure capturing the caller's local by pointer ran on a detached thread after the frame was gone (escape_inside_block_detached).
// Closed: bck_record_inferred_escape (and the other function-level summary writers: __fn_ret_struct_owned__, __fn_builds_view__, __fn_param_valueread__) write the function's own record (set_deep), so a write from inside a block survives the block's pop (agora #214).
// main: accepted; AddressSanitizer reported stack-use-after-scope.
// map: §2.7 | A2 | rejected | h969 | agora #214: an escape recorded inside a block was popped with it: a by-pointer closure ran on a detached thread after its frame
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`

: Counter { i n i max }

@ detach b go ( @ v ) cb → v {
    ? go {
        : !Thread ThreadErr t ( thread_spawn cb )
        ?? t { T th → ( thread_detach th ) F _ → {} }
    } {}
}

@ leaky → v {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v {
        ( sleep_ms 50 )
        = . c n + . c n 1
        ( nurl_println_int . c n )
    }
    ( detach T f )
}

@ main → i {
    ( leaky )
    ( sleep_ms 200 )
    ^ 0
}
