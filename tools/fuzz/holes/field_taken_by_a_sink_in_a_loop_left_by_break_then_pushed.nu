// field_taken_by_a_sink_in_a_loop_left_by_break_then_pushed: a String field handed to a `sink` inside a loop left by `break`: the push after the loop copied into the emptied field
// main: accepted; the loop's way out by `break` reset the taken field path as a binding the body declared (UBSan: null pointer passed to memcpy).
// map: §2.1 | A2 | rejected | - | agora #351: a String field handed to a `sink` inside a loop left by `break`: the push after the loop copied into the emptied field
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`

: Holder { String buf }

@ take sink String v → i { ^ ( string_len v ) }

@ main → i {
    : ~ Holder h @ Holder { ( string_from `abc` ) }
    ~ T {
        : i n ( take . h buf )
        ? > n 0 { break } {}
    }
    ( string_push_str . h buf `x` )
    ( nurl_println ( string_data . h buf ) )
    ^ 0
}
