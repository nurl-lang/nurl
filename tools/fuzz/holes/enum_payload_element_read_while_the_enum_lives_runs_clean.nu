// enum_payload_element_read_while_the_enum_lives_runs_clean: as t842_enum_payload_element_kept_past_the_enum_moved, x read before b is moved
// AGORA-842 guard: accepted - the view's source b still holds it
// map: §2.10 | A2 | runs-clean | - | AGORA-842
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
    ( nurl_println ( string_data x ) )
    ( drop_bag b )
    ^ 0
}
