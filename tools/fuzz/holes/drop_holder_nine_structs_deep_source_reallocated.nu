// drop_holder_nine_structs_deep_source_reallocated: agora #340 — a `% Drop` holder of a view, nine struct layers down, keeps viewing a String that a push then reallocates: the holder's destructor reads the freed buffer.
// Closed: the question "may this drop read a view?" walks every layer with a visited set instead of a depth cap, so the push that moves the source ends the holder's view (__drop_may_read_view, agora #340).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #340: a Drop holder nine struct layers deep whose source is reallocated
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

: S1 { W a }
: S2 { S1 a }
: S3 { S2 a }
: S4 { S3 a }
: S5 { S4 a }
: S6 { S5 a }
: S7 { S6 a }
: S8 { S7 a }
: S9 { S8 a }

@ mk9 s v → S9 { ^ @ S9 { @ S8 { @ S7 { @ S6 { @ S5 { @ S4 { @ S3 { @ S2 { @ S1 { @ W { v } } } } } } } } } } }

@ main → i {
    : String s ( string_from `short` )
    : S9 o ( mk9 ( string_data s ) )
    ( string_push_str s ` and now long enough that the buffer has to move to a bigger block` )
    ^ 0
}
