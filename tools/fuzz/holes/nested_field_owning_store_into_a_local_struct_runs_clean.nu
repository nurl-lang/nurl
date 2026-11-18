// nested_field_owning_store_into_a_local_struct_runs_clean: AGORA-851 guard — `= . . o inner name ( string_from … )` into a mutable local's nested field replaces it in place: accepted, the old name released
// map: §7.6 | A2 | runs-clean | - | AGORA-851 guard: a nested owning store into a local's own storage is the local's, not a copy
$ `stdlib/core/string.nu`

: In { String name i k }

: Out { In inner i n }

@ main → i {
    : ~ Out o @ Out { @ In { ( string_from `an original name long enough to live on the heap` ) 1 } 2 }
    = . . o inner name ( string_from `a replacement name long enough to live on the heap` )
    ( nurl_println ( string_data . . o inner name ) )
    ^ 0
}
