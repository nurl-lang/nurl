// view_of_a_string_seventeen_structs_down_kept_past_the_string_grows: `: L1 { s v i pad }` … `: L17 { L16 a i pad }` built by a call over a String's bytes, read after the String grew
// Closed: the walk that asks whether a type holds an address reads it whole: a struct of views seventeen levels down is a view, not a number (agora #721).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #721: a view seventeen structs down kept past the growth of what it views
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: L1 { s v i pad }
: L2 { L1 a i pad }
: L3 { L2 a i pad }
: L4 { L3 a i pad }
: L5 { L4 a i pad }
: L6 { L5 a i pad }
: L7 { L6 a i pad }
: L8 { L7 a i pad }
: L9 { L8 a i pad }
: L10 { L9 a i pad }
: L11 { L10 a i pad }
: L12 { L11 a i pad }
: L13 { L12 a i pad }
: L14 { L13 a i pad }
: L15 { L14 a i pad }
: L16 { L15 a i pad }
: L17 { L16 a i pad }

@ mk String x → L17 { ^ @ L17 { @ L16 { @ L15 { @ L14 { @ L13 { @ L12 { @ L11 { @ L10 { @ L9 { @ L8 { @ L7 { @ L6 { @ L5 { @ L4 { @ L3 { @ L2 { @ L1 { ( string_data x ) 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } }

@ main → i {
    : ~ String x ( string_from `the first heap string, long enough to be on the heap for sure` )
    : L17 h ( mk x )
    ( string_push_str x `and a long tail that makes the buffer move to a new place in memory for sure, really really for sure` )
    ( nurl_println . . . . . . . . . . . . . . . . . h a a a a a a a a a a a a a a a a v )
    ^ 0
}
