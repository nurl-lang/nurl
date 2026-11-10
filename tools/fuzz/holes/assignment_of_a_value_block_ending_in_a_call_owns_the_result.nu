// assignment_of_a_value_block_ending_in_a_call_owns_the_result: `= e { ( string_concat a a ) }`, `= e { : i n 1 ( string_from … ) }`, `= e { : String s … ( string_concat s s ) }`, the last in a loop body too.
// Closed: an assignment's value block whose tail is a call is that call for what the target owns, as a `:` binding takes it (__blk_bind_tt). Read as a block, a String or Vec target took every result for a borrow: the old value was dropped, the new one stored with its drop flag off, and never released (agora #613).
// main 2498b4e: accepted; LeakSanitizer: each call's result.
// map: §7.6 | A2 | runs-clean | - | agora #613: an owned String assigned a value block that ends in a call returning a value of its own
$ `stdlib/core/string.nu`

@ main → i {
    : String a ( string_from `outer string long enough for a heap buffer aaaa` )
    : ~ String e ( string_from `first value long enough for a heap buffer` )
    = e { ( string_concat a a ) }
    : ~ i total ( string_len e )
    = e { : i n 1 ( string_from `second value long enough for a heap buffer` ) }
    = total + total ( string_len e )
    = e { : String s ( string_from `inner string long enough for a heap buffer aaaa` ) ( string_concat s s ) }
    = total + total ( string_len e )
    : ~ i k 0
    ~ < k 2 {
        = e { : String s ( string_from `loop inner string long enough for a heap buffer` ) ( string_concat s s ) }
        = total + total ( string_len e )
        = k + k 1
    }
    ( nurl_println_int total )
    ^ 0
}
