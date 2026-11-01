// string_field_taken_by_a_sink_then_pushed: agora #280 — a String field handed to a `sink`, then pushed to: the field was a null handle and string_push_str faulted.
// main: accepted; the push dereferenced a null handle (SIGSEGV).
// map: §2.1 | A2 | rejected | - | agora #280: a String field handed to a `sink`, then pushed to: the field was a null handle and string_push_str faulted
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`

: Holder { String s }

@ eat sink String v → i { ^ ( string_len v ) }

@ main → i {
    : Holder h @ Holder { ( string_from `abc` ) }
    : i n ( eat . h s )
    ( string_push_str . h s `x` )
    ^ 0
}
