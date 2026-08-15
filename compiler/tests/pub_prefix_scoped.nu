// pub_prefix_scoped.nu — a `pub` prefix belongs to ONE declaration.
//
// Importing a module that ends in a `pub` non-function declaration used
// to make this file's `greet` public — and, worse, flip this file into
// strict mode, at which point `Local` (unmarked, and only ever used
// here) stopped being visible even to itself as far as any importer was
// concerned. The failure surfaced as "private type 'Local' is not
// visible across files" pointing at a declaration nowhere near the
// `pub` that caused it.
//
// Nothing in this file is marked `pub`, so nothing in it is strict and
// `Local` stays freely usable. Compiling and running at all is the
// assertion.

$ `compiler/tests/pub_prefix_scoped_mod.nu`

: Local { i n }

@ greet Local l → i { ^ . l n }

@ main → i {
    : Local l @ Local { 7 }
    ( nurl_print `local=` ) ( nurl_print ( nurl_str_int ( greet l ) ) ) ( nurl_print `\n` )
    ^ 0
}
