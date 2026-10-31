// argument_temporary_leaked_by_a_panic: a String / Vec / struct made by a call right in an argument (`( boom ( mk k ) )`) is a temporary the caller drops after the call returns. While the callee runs it is the caller's, and the panic journal did not know it: a panic in the callee (or in a later argument) skipped the drop after the call, and nothing else held the value. A transaction retried after a serialization failure leaked the row it was about to write, every time.
// Closed: the temporary's slot is journaled for the call (mem_journal_push_temp), flagged by whether the caller owns it then (the callee neither sinks nor keeps it); the registration ends when the call returns, and is elided where no panic can reach.
// main (before this PR): LeakSanitizer reported each panicking call's Vec (control block and buffer).
// map: §7.2 | A2 | runs-clean | h292 | a String / Vec made in an argument, the callee panics: the drop after the call was skipped and the journal did not know the temporary — leak
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

@ mk i x → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v x )
    ^ v
}

@ boom ( Vec i ) v String s → i {
    ? > ( vec_at [i] v 0 ) 2 { ( panic `too big` ) } {}
    ^ + ( vec_len [i] v ) ( string_len s )
}

@ main → i {
    : ~ i caught 0
    : ~ i k 0
    ~ < k 10 {
        : !v PanicInfo r ( recover \ → v { : i _n ( boom ( mk k ) ( string_from `name` ) ) } )
        ?? r { T _ → {} F p → { = caught + caught 1 ( panic_info_free p ) } }
        = k + k 1
    }
    ( nurl_print `caught: ` ) ( nurl_println_int caught )
    ^ 0
}
