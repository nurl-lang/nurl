// OPEN in 0.72.0 — mem_forget in a trait method's body (a `% Show` impl, called as ( show b )): the String leaks.
// The impl method builds a String and forgets it; an impl method is safe code like any other function.
// mem_forget is `unsafe`-only (§3.3d), but no check rejects it in 0.72.0 (mem_forget_owned_vec); this is
// the trait-method context a fix must cover too.
// LSan: detected memory leaks — the String (24-byte control block from string_from, and its buffer).
$ `stdlib/core/string.nu`

: Bag { i n }

% Show Bag { @ show Bag b → v { : String s ( string_from `x` ) ( mem_forget s ) } }

@ main → i {
    : Bag b @ Bag { 1 }
    ( show b )
    ( nurl_println `ran` )
    ^ 0
}
