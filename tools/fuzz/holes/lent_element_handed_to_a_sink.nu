// lent_element_handed_to_a_sink: a call's result that only lends — `( vec_at v 0 )`, an element the Vec still holds — handed straight to a `sink` parameter: the callee released the element while the Vec held it, and the Vec's next read (and its own drop) touched freed memory. A declared `sink` counted as an explicit release, so the lent value went over as is.
// Closed: a lent result that can be copied is handed to a `sink` as a copy; one that cannot is rejected.
// main (before this PR): ASan heap-use-after-free.
// map: CallT.sink | A1 | runs-clean | h228 | vec_at element borrow passed to sink param; Vec still holds freed elem
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ consume sink String s → v {
}

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `abc` ) )
    ( consume ( vec_at [String] v 0 ) )
    ( nurl_println ( string_data ( vec_at [String] v 0 ) ) )
    ^ 0
}
