// OPEN in 0.72.0 — a view leaving through a helper's return value inside a Vec, via a local binding.
// `wrapv` returns a new ( Vec s ) holding its parameter `a`; `back` binds ( wrapv x ) for its own fresh
// string `x` to `w`, returns `w`, and releases `x`, so the Vec main receives holds a view of freed
// memory. view_through_return_vec is the same without the binding.
// ASan: heap-use-after-free in fputs <- nurl_println (main), reading element 0.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ wrapv s a → ( Vec s ) { : ( Vec s ) v ( vec_new [s] ) ( vec_push [s] v a ) ^ v }

@ back → ( Vec s ) { : s x ( nurl_str_cat `ab` `cd` ) : ( Vec s ) w ( wrapv x ) ^ w }

@ main → i {
    : ( Vec s ) v ( back )
    ?? ( vec_get [s] v 0 ) { T e → ( nurl_println e ) F → {} }
    ( nurl_println `P33D-MARK` )
    ^ 0
}
