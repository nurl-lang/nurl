// map: §2.10 | A2 | rejected | - | agora #842: a view out of a `??` arm bound by `:`, then the enum moved
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Bag { Full ( Vec String ) Hollow }

@ drop_bag sink Bag b → v {}

@ mkv → ( Vec String ) {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `first heap string long enough for the heap` ) )
    ^ v
}

@ main → i {
    : Bag b @ Bag { Full ( mkv ) }
    : String dflt ( string_from `a default string long enough for the heap, surely` )
    : String x ?? b { Full v → ( vec_at [String] v 0 ) Hollow → dflt }
    ( drop_bag b )
    ( nurl_println ( string_data x ) )
    ^ 0
}
