// map: §2.10 | A2 | rejected | - | AGORA-842: a view out of a `??` arm bound by `:`, then `( eat_bag b e )` sinks the enum beside the view
// AGORA-842 part 2: refused (main 5c4740fa: accepted, heap-use-after-free)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Bag { Full ( Vec String ) Hollow }

@ eat_bag sink Bag b String e → v {
    ?? b { Full v → { ( vec_clear [String] v ) } Hollow → {} }
    ( nurl_println ( string_data e ) )
}

@ mkv → ( Vec String ) {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `first heap string long enough for the heap` ) )
    ^ v
}

@ main → i {
    : Bag b @ Bag { Full ( mkv ) }
    : String dflt ( string_from `a default string long enough for the heap, surely` )
    : String x ?? b { Full v → ( vec_at [String] v 0 ) Hollow → dflt }
    ( eat_bag b x )
    ^ 0
}
