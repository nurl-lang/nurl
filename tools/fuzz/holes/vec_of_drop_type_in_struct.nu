// vec_of_drop_type_in_struct: a struct holding a value with a `% Drop` of the program's own inside a container — `: Imp { ( Vec R ) xs }`, or a Box, an option, an enum payload, a Vec of Vecs — was never dropped: it could not be copied (so it was no handle), and the compiler wrote a field-by-field drop only for a struct whose own fields had the `% Drop`. The Vec and every R in it leaked, and R's drop never ran.
// Closed: a struct that holds such a value anywhere inside it — through a Vec's or a Box's elements, an option's or an enum's payloads, a field's fields — gets the field-by-field drop (__holds_user_drop).
// main (before this PR): LeakSanitizer reports the Vec and every String its elements own.
// map: §7.6 | A2 | runs-clean | h209 | struct holding Vec of user %Drop type never dropped: leak, drop not run
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String s }

% Drop R { @ drop R r → v { ( nurl_print `drop R\n` ) } }

: Imp { ( Vec R ) xs i k }

@ fill → v {
    : Imp m @ Imp { ( vec_new [R] ) 0 }
    ( vec_push [R] . m xs @ R { ( string_from `a heap string that is long enough` ) } )
}

@ main → i {
    : ~ i n 0
    ~ < n 3 { ( fill ) = n + n 1 }
    ^ 0
}
