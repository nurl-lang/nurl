// tried_sink_taking_an_inout_field_then_failing: `: i x \ ( take . h buf k )`: the tried call is a sink that takes the inout parameter's field, then fails; the `\` hands h back with the field taken (PO f03).
// Closed: as the view form (agora #406).
// main b997834b: accepted (it runs clean there: the taken field reads as empty); the `^` spelling of the same exit is refused, "use of partly moved value 'h'" (agora #280).
// map: §2.10 | A2 | rejected | - | agora #406: `: i x \ ( take . h buf k )`: the tried call is a sink that takes the inout parameter's field, then fails; the `\` hands h back with the field taken (PO f03)
$ `stdlib/core/string.nu`

: H { String buf }
: | E { Bad i }

@ take sink String s i k → !i E {
    ? > k 0 { ^ @ !i E { F @ E { Bad k } } } {}
    ^ @ !i E { T k }
}

@ g inout H h i k → !i E {
    : i x \ ( take . h buf k )
    = . h buf ( string_from `a new buffer for the field, long enough for the heap` )
    ^ @ !i E { T x }
}

@ main → i {
    : ~ H h @ H { ( string_from `the caller's buffer, long enough for the heap` ) }
    ?? ( g h 1 ) { T _ → {} F _ → {} }
    ( nurl_println ( string_data . h buf ) )
    ^ 0
}
