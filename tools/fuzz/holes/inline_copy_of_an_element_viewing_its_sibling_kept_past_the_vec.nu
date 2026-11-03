// inline_copy_of_an_element_viewing_its_sibling_kept_past_the_vec: recs[1].view points into recs[0].own; `= keep ( mem_dup ( vec_at [Rec] recs 1 ) )` kept past recs.
// Closed: a container whose elements view its own storage — an element viewing a sibling's String, a field viewing another field — holds views of itself (`vsv_`, recorded where its dependency on itself is dropped, and carried along when such a value is moved in whole): a copy of a part of it holds them, and outlives it no longer.
// main 836c0e9: rejected (a guard: family G's review head accepted it, reading the part held without the container's self-views).
// map: §2.13 | A2 | rejected | - | Family G review: recs[1].view points into recs[0].own; `= keep ( mem_dup ( vec_at [Rec] recs 1 ) )` kept past recs
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Rec { String own s view }

@ main → i {
    : ~ Rec keep @ Rec { ( string_from `x` ) `y` }
    {
        : ( Vec Rec ) recs ( vec_new [Rec] )
        ( vec_push [Rec] recs @ Rec { ( string_from `an owned string inside the record vec itself` ) `z` } )
        ( vec_push [Rec] recs @ Rec { ( string_from `w` ) ( string_data . ( vec_at [Rec] recs 0 ) own ) } )
        = keep ( mem_dup ( vec_at [Rec] recs 1 ) )
    }
    ( nurl_println . keep view )
    ^ 0
}
