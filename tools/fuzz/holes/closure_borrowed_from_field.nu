// closure_borrowed_from_field: a closure read out of a struct's field (`: ( @ i i ) g . s f`) does not own its env — the struct does — and the borrow walk tracked closure bindings by their captures only, so replacing the field (`= . s f …`, which drops the old env) left `g` calling freed memory. SEGV / heap-use-after-free.
// Closed: a closure binding that does not own its env (read out of a field, an option's payload, a container's element) is a borrow of what it read (row class `k`, __clo_bind_class / bck_note_clo_borrow): the owner dying, given a new value, a field of it replaced or its elements dropped ends it, and calling it then is rejected. A closure-typed field written is a field of its struct replaced (bck_stash_fieldset).
// main's compiler: compiled; the program crashed (SEGV).
// map: §2.11 | A2 | rejected | h283 | closure read out of a struct field, field replaced (old env dropped), closure called
$ `stdlib/core/string.nu`

: S { ( @ i i ) f }

@ main → i {
    : String a ( string_from `abcdefghijklmnopqrstuvwxyz` )
    : ( @ i i ) f0 \ i x → i { ^ + x ( string_len a ) }
    : ~ S s @ S { f0 }
    : ( @ i i ) g . s f
    = . s f \ i x → i { ^ x }
    ( nurl_println_int ( g 1 ) )
    ^ 0
}
