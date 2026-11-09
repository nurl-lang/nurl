// field_taken_by_a_sink_in_a_loop_then_taken_again: a String field handed to a `sink` inside a loop: the next round pushed to the field the last one emptied, a null buffer
// main: accepted; the loop mask reset the field path, which had no state before the take, and string_push_str copied into a null buffer (UBSan: null pointer passed to memcpy).
// map: §2.1 | A2 | rejected | - | agora #351: a String field handed to a `sink` inside a loop: the next round pushed to the field the last one emptied, a null buffer
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`

: Holder { String buf }

@ take sink String v → i { ^ ( string_len v ) }

@ main → i {
    : ~ Holder h @ Holder { ( string_from `abc` ) }
    : ~ i k 0
    ~ < k 3 {
        ( string_push_str . h buf `x` )
        : i n ( take . h buf )
        ( nurl_println_int n )
        = k + k 1
    }
    ^ 0
}
