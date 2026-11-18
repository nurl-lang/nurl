// nested_field_owning_store_into_an_inout_parameter_runs_clean: AGORA-851 guard — `= . . o inner name ( string_from … )` through an `inout` parameter writes the caller's value: accepted
// map: §7.6 | A2 | runs-clean | - | AGORA-851 guard: a nested owning store through an inout parameter is the caller's storage
$ `stdlib/core/string.nu`

: In { String name i k }

: Out { In inner i n }

@ rename inout Out o → v {
    = . . o inner name ( string_from `a replacement name long enough to live on the heap` )
}

@ main → i {
    : ~ Out o @ Out { @ In { ( string_from `an original name long enough to live on the heap` ) 1 } 2 }
    ( rename o )
    ( nurl_println ( string_data . . o inner name ) )
    ^ 0
}
