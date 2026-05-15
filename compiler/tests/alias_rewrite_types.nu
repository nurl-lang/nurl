// alias_rewrite_types.nu — regression for grammar v2.1 alias-rewrite
// extension that covers types, enum variants, and global constants in
// addition to top-level `@`-functions (the original 2.0 coverage).
//
// Reaching every kind via the `m::` prefix exercises the renamed
// declarations end-to-end: the helper's `Point` struct is now
// `m__Point`, its `Shade` enum is `m__Shade` with variants
// `m__Light` / `m__Dark`, and `PI_FIXED` is `m__PI_FIXED`. A bare-call
// `m::make_point` confirms the original @-function rewrite still works
// alongside the new ones.
//
// Generic structs (`: Box [A] { ... }`) are intentionally NOT exercised
// here — the type-arg suffix in the monomorphised name (`Box__i`)
// interacts with whole-identifier rewriting in a way that needs
// follow-up handling (out of scope for this iteration).

$ `compiler/tests/alias_rewrite_types_mod.nu` m

@ main → i {
    : m::Point p ( m::make_point 3 4 )
    : m::Shade s # m::Shade m::Light
    ( nurl_print `x=` ) ( nurl_print ( nurl_str_int . p x ) ) ( nurl_print `\n` )
    ( nurl_print `y=` ) ( nurl_print ( nurl_str_int . p y ) ) ( nurl_print `\n` )
    ?? s {
        m::Light → ( nurl_print `shade=Light\n` )
        m::Dark → ( nurl_print `shade=Dark\n` )
    }
    ( nurl_print `pi=` ) ( nurl_print ( nurl_str_int m::PI_FIXED ) ) ( nurl_print `\n` )
    ^ 0
}
