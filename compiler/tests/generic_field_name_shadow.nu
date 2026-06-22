// generic_field_name_shadow.nu — regression: indexing a generic container
// over a struct whose FIELD name collides with the container's own generic
// loop/parameter identifier must do ARRAY indexing, not field access.
//
// stdlib/core/vec.nu reads/writes elements with `. data idx` / `= . data idx
// x` where `data : *A` (A is the generic type parameter) and `idx`/`len` are
// int parameters/locals. Monomorphisation substitutes A textually, so for a
// `Vec[Slot]` whose Slot has a field literally named `idx` (or `len`), the
// concrete body became `. data idx` on a `*Slot` — and the "struct field
// wins over a same-named variable" rule (correct for genuine field access,
// see ptr_field_name_shadow.nu) mis-routed it to FIELD access (offset 0),
// a silent miscompile that clang caught only because field 0's type differed
// from the element type. The fix suppresses field-name resolution for a
// pointer whose element type is a tparam-substituted type (its generic
// origin — an opaque type variable — has no source-accessible fields), so
// the access falls back to array indexing.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// BOTH field names (`idx`, `len`) collide with vec.nu's generic identifiers.
: Slot { i idx  i len }

@ main → i {
    : ( Vec Slot ) v ( vec_new [Slot] )
    ( vec_push [Slot] v @ Slot { 10 11 } )
    ( vec_push [Slot] v @ Slot { 20 21 } )
    ( vec_push [Slot] v @ Slot { 30 31 } )

    // READ: element 1 must be {20,21}, not field 0 of element 0.
    ?? ( vec_get [Slot] v 1 ) {
        T c → { ( nurl_print_int . c idx ) ( nurl_print_int . c len ) }   // 20 / 21
        F _ → { ( nurl_print `READ_BAD\n` ) }
    }

    // STORE: vec_set must overwrite element 2, leaving the others intact.
    ( vec_set [Slot] v 2 @ Slot { 99 98 } )
    ?? ( vec_get [Slot] v 2 ) {
        T c → { ( nurl_print_int . c idx ) ( nurl_print_int . c len ) }   // 99 / 98
        F _ → { ( nurl_print `STORE_BAD\n` ) }
    }

    // Element 0 untouched by the store above.
    ?? ( vec_get [Slot] v 0 ) {
        T c → { ( nurl_print_int . c idx ) }                              // 10
        F _ → {}
    }

    ( vec_free [Slot] v )
    ^ 0
}
