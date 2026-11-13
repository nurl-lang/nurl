// diag_owning_store_into_a_closure_capture.nu — a field of a struct a
// closure captured by value given a value that owns memory (Agora #643).
// The body works on its own copy, made at each call: the binding outside
// kept its old value and the new String was never released. Refused,
// naming the mutable binding the closure would capture by pointer.

$ `stdlib/core/string.nu`

: App { String name i n }

@ main → i {
    : App a @ App { ( string_from `the first name, also long enough to live on the heap` ) 1 }
    : ( @ v i ) f \ i k → v {
        = . a name ( string_from `a replacement name that is long enough to live on the heap` )
    }
    ( f 1 )
    ^ 0
}
