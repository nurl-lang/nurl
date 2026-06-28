// field_store_shadow.nu — a store `= . p field val` whose value-name is a
// non-parameter LOCAL that shadows the field must compile to a FIELD store,
// not a value-as-index array store (`p[val] = val`, a struct-corrupting
// miscompile). Symmetric with the read path, where a struct field always wins
// over a same-named variable. Regression for the field-store/local-shadow
// footgun.

$ `stdlib/core/string.nu`

: Box { i lo i hi i mid }

@ pb s label b ok → v { ( nurl_print label ) ( nurl_print ? ok `OK\n` `BAD\n` ) }

@ main → i {
    : *Box t # *Box ( nurl_alloc Z Box )
    // Locals whose names exactly match the struct fields.
    : i lo 11
    : i hi 22
    : i mid 33
    // Each of these must store into the field, not `t[lo]` / `t[hi]` / `t[mid]`.
    = . t lo lo
    = . t hi hi
    = . t mid mid
    ( pb `lo:  ` == . t lo 11 )
    ( pb `hi:  ` == . t hi 22 )
    ( pb `mid: ` == . t mid 33 )
    // A non-field local index still array-stores (raw-pointer style) — here the
    // field names are set, so reading them back proves no aliasing happened.
    ( pb `sum: ` == + + . t lo . t hi . t mid 66 )
    ( nurl_free # s t )
    ^ 0
}
