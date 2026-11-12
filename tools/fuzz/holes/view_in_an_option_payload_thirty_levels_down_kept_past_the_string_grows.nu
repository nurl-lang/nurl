// view_in_an_option_payload_thirty_levels_down_kept_past_the_string_grows: a view of a String's bytes thirty levels down through structs and an option payload, read after the String grew
// Closed: as above: an option's payload counts as a level, and the walk has no budget (agora #721).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #721: a view thirty levels down through an option payload kept past the growth of what it views
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
: L18 { L17 a i pad }
: L19 { L18 a i pad }
: L20 { L19 a i pad }
: L21 { L20 a i pad }
: L22 { L21 a i pad }
: L23 { L22 a i pad }
: L24 { L23 a i pad }
: L25 { L24 a i pad }
: L26 { L25 a i pad }
: L27 { L26 a i pad }
: L28 { L27 a i pad }
: L29 { L28 a i pad }
: L30 { L29 a i pad }

@ mk String x → ?L30 { ^ @ ?L30 { T @ L30 { @ L29 { @ L28 { @ L27 { @ L26 { @ L25 { @ L24 { @ L23 { @ L22 { @ L21 { @ L20 { @ L19 { @ L18 { @ L17 { @ L16 { @ L15 { @ L14 { @ L13 { @ L12 { @ L11 { @ L10 { @ L9 { @ L8 { @ L7 { @ L6 { @ L5 { @ L4 { @ L3 { @ L2 { @ L1 { ( string_data x ) 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } 0 } } }

@ main → i {
    : ~ String x ( string_from `the first heap string, long enough to be on the heap for sure` )
    : ?L30 o ( mk x )
    ?? o { T h → { ( string_push_str x `and a long tail that makes the buffer move to a new place in memory for sure, really really for sure` ) ( nurl_println . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . h a a a a a a a a a a a a a a a a a a a a a a a a a a a a a v ) } F _ → {} }
    ^ 0
}
