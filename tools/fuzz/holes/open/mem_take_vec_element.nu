// OPEN in 0.72.0 — mem_take on a vec_get payload claims an element the Vec still holds: it is released twice.
// The `T e` arm binds a view of element 0, and ( mem_take e ) makes `e` its owner, so the String is
// released when the arm ends; the Vec in `h` still holds it and releases it again at scope exit.
// mem_take is a primitive for container code, `unsafe`-only by §3.3d but callable here.
// ASan: heap-use-after-free in nurl_vec_drop (the Vec's element drop reading the released String).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Holder { ( Vec String ) items }

@ main → i {
    : Holder h @ Holder { ( vec_new [String] ) }
    ( vec_push [String] . h items ( string_from `element` ) )
    : String b ( string_from `x` )
    ?? ( vec_get [String] . h items 0 ) { T e → { ( mem_take e ) ( nurl_println ( string_data e ) ) } F → {} }
    ( nurl_println `ran` )
    ^ 0
}
