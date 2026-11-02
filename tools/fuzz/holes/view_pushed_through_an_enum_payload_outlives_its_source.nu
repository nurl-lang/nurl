// view_pushed_through_an_enum_payload_outlives_its_source: agora #414 — `?? en { A w → { ( vec_push [s] w ( string_data loc ) ) } B → {} }`, `A` a program enum's `( Vec s )` payload; read through `en`
// Closed: a value kept in a container whose handle is a copy of an owner's, or a part of one, without being its borrow — a binding of a `?` / `??` join of names, a `~` loop's element, a `??` payload read in place, a value a call lends (`( id ( vec_at vv 0 ) )`), or such a value handed to the call as the container itself — lands in that owner too, which holds the view (`hr_`, __bck_store_owners; agora #414).
// main: heap-use-after-free (base 22fd0184 too).
// map: PushArg | A1 | rejected | - | agora #414: a view pushed through a program enum's payload, read through the enum
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | E { A ( Vec s ) B }

@ main → i {
    : E en @ E { A ( vec_new [s] ) }
    {
        : String loc ( string_from `a block local string long enough for the heap, surely` )
        ?? en { A w → { ( vec_push [s] w ( string_data loc ) ) } B → {} }
    }
    ?? en { A w → { ( nurl_println ( vec_at [s] w 0 ) ) } B → {} }
    ^ 0
}
