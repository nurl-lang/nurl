// view_pushed_through_the_payload_of_a_field_of_a_join_of_structs_outlives_its_source: agora #414 — as …_payload_of_a_join_of_enums, the enum a struct's field: `: H j ? == c 1 { o } { o2 }`, `?? . j en { A w → … }`; `. o en` read after the block
// Closed: a value kept in a container whose handle is a copy of an owner's, or a part of one, without being its borrow — a binding of a `?` / `??` join of names, a `~` loop's element, a `??` payload read in place, a value a call lends (`( id ( vec_at vv 0 ) )`), or such a value handed to the call as the container itself — lands in that owner too, which holds the view (`hr_`, __bck_store_owners; agora #414).
// main: heap-use-after-free (base 22fd0184 too).
// map: PushArg | A1 | rejected | - | agora #414: a view pushed through the payload of a field of a binding of a join of structs, read through an owner
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | E { A ( Vec s ) B }
: H { E en i n }

@ main → i {
    : H o @ H { @ E { A ( vec_new [s] ) } 1 }
    : H o2 @ H { @ E { A ( vec_new [s] ) } 2 }
    : i c 1
    {
        : String loc ( string_from `a block local string long enough for the heap, surely` )
        : H j ? == c 1 { o } { o2 }
        ?? . j en { A w → { ( vec_push [s] w ( string_data loc ) ) } B → {} }
    }
    ?? . o en { A w → { ( nurl_println ( vec_at [s] w 0 ) ) } B → {} }
    ^ 0
}
