// Borrow checker — return escape through a NESTED aggregate
// (docs/MEMORY.md §2.8). borrow_ret_escape_agg.nu pins the one-level
// form; this is the same program with one more pair of braces between
// `^` and `cb`. gen_agg_lit published only the parameters embedded as
// DIRECT fields, so an inner literal's parameters were invisible and
// the depth of the struct decided the verdict.
: Counter { i n i max }
: Inner { ( @ v ) cb }
: Outer { Inner it }

@ wrap2 ( @ v ) cb → Outer {
    ^ @ Outer { @ Inner { cb } }
}

@ caller → Outer {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    ^ ( wrap2 f )
}

@ main → i {
    : Outer o ( caller )
    : Inner n . o it
    : ( @ v ) g . n cb
    ( g )
    ^ 0
}
