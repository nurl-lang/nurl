// diag_owning_store_into_a_by_value_param.nu — a field of a by-value (`in`)
// struct parameter given a value that owns memory (Agora #643). The store
// lands in the function's own copy of the caller's value: the caller never
// sees it, and nothing released the new String (a leak on every call).
// Refused, naming `inout` and `sink`.

$ `stdlib/core/string.nu`

: App { String name i n }

@ rename App a → v {
    = . a name ( string_from `a replacement name that is long enough to live on the heap` )
}

@ main → i {
    : App a @ App { ( string_from `the first name, also long enough to live on the heap` ) 1 }
    ( rename a )
    ^ 0
}
