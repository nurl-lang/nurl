// diag_owning_store_into_a_closure_parameter.nu — a field of a closure
// literal's by-value struct parameter given a value that owns memory
// (AGORA-643). The store lands in the body's own copy of the caller's
// value, as a function's by-value parameter's does: the caller never sees
// it, and nothing released the new String (a leak on every call). A
// function's parameter was refused; a closure's was only warned, and
// leaked. Refused, naming the closure's `inout` parameter.

$ `stdlib/core/string.nu`

: App { String name i n }

@ main → i {
    : App a @ App { ( string_from `the first name, also long enough to live on the heap` ) 1 }
    : ( @ v App ) f \ App x → v { = . x name ( string_from `a replacement name that is long enough to live on the heap` ) }
    ( f a )
    ^ 0
}
