// clone_of_a_field_viewing_its_sibling_field_after_a_move_kept_past: d.words views d.text, d moved into docs; vec_clone of docs[0].words kept past docs.
// Closed: a container whose elements view its own storage — an element viewing a sibling's String, a field viewing another field — holds views of itself (`vsv_`, recorded where its dependency on itself is dropped, and carried along when such a value is moved in whole): a copy of a part of it holds them, and outlives it no longer.
// main 836c0e9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | Family G review: d.words views d.text, d moved into docs; vec_clone of docs[0].words kept past docs
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Doc { String text ( Vec s ) words }

@ main → i {
    : ~ ( Vec s ) keep ( vec_new [s] )
    {
        : ( Vec Doc ) docs ( vec_new [Doc] )
        : Doc d @ Doc { ( string_from `hello world, long enough for a heap buffer` ) ( vec_new [s] ) }
        ( vec_push [s] . d words ( string_data . d text ) )
        ( vec_push [Doc] docs d )
        = keep ( vec_clone [s] . ( vec_at [Doc] docs 0 ) words )
    }
    ( nurl_println ( vec_at [s] keep 0 ) )
    ^ 0
}
