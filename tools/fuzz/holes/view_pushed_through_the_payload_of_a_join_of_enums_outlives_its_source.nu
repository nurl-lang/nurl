// view_pushed_through_the_payload_of_a_join_of_enums_outlives_its_source: agora #414 — `: E j ? == c 1 { en } { en2 }`, `E` a program enum with a `( Vec s )` payload, then `?? j { A w → { ( vec_push [s] w ( string_data loc ) ) } B → {} }`; `en` read after the block
// Closed: a value kept in a container whose handle is a copy of an owner's, or a part of one, without being its borrow — a binding of a `?` / `??` join of names, a `~` loop's element, a `??` payload read in place, a value a call lends (`( id ( vec_at vv 0 ) )`), or such a value handed to the call as the container itself — lands in that owner too, which holds the view (`hr_`, __bck_store_owners; agora #414).
// main: heap-use-after-free (base 22fd0184 too).
// map: PushArg | A1 | rejected | - | agora #414: a view pushed through the payload of a binding of a join of enums, read through an owner
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | E { A ( Vec s ) B }

@ main → i {
    : E en @ E { A ( vec_new [s] ) }
    : E en2 @ E { A ( vec_new [s] ) }
    : i c 1
    {
        : String loc ( string_from `a block local string long enough for the heap, surely` )
        : E j ? == c 1 { en } { en2 }
        ?? j { A w → { ( vec_push [s] w ( string_data loc ) ) } B → {} }
    }
    ?? en { A w → { ( nurl_println ( vec_at [s] w 0 ) ) } B → {} }
    ^ 0
}
