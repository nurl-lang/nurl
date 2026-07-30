// Test: reassignment into a TRACKED owned-string binding, for every
// RHS shape that is not a fresh owning call. The invariant under test:
// a tracked binding holds an allocator-owned pointer on EVERY
// control-flow path, because the scope-exit drop cannot be made
// path-sensitive (an untrack inside a `?` arm dies with the arm's
// symtab pop and the outer registration resurfaces).
//
//   - literal RHS:  `= x `lit`` used to store the .rodata pointer, so
//     the scope-exit drop freed a string constant — a SEGV, not a
//     leak. The compiler now frees the old value and stores a strdup.
//   - untracked-ident RHS (parameter/borrow): the drop would free the
//     caller's buffer (UAF). Now: free old + strdup.
//   - borrow-returning call RHS: same discipline as the ident case.
//   - tracked-ident RHS: a true move — old value freed, pointer kept,
//     source's drop cancelled.
//   - self-assign `= x x`: skipped whole; x stays tracked and its
//     buffer is freed exactly once at scope exit.
//
// A premature or wrong free shows as a crash / wrong sum here; the
// leak side of each shape is pinned by the LSan CI set.

$ `stdlib/core/string.nu`

// Borrow-returning helper: hands back its argument unchanged.
@ pick s a → s { ^ a }

@ take_param s p → i {
    : ~ s x ( nurl_str_cat `a` `b` )
    // untracked ident RHS — must not free p's buffer at scope exit
    = x p
    ^ ( nurl_str_len x )
}

@ main → i {
    : ~ i acc 0

    // literal RHS inside a branch (the SEGV shape)
    : ~ s d ( nurl_str_cat `u` `i` )
    ? > ( nurl_str_len d ) 1 { = d `three` } { = d `four!` }
    = acc + acc ( nurl_str_len d )
    // acc = 5

    // tracked ident RHS: move
    : ~ s a ( nurl_str_cat `q` `w` )
    : ~ s b ( nurl_str_cat3 `e` `r` `t` )
    = a b
    = acc + acc ( nurl_str_len a )
    // acc = 8

    // self-assign
    : ~ s c ( nurl_str_cat `t` `y` )
    = c c
    = acc + acc ( nurl_str_len c )
    // acc = 10

    // borrow-returning call RHS
    : s big ( nurl_str_cat `mm` `nn` )
    : ~ s e ( nurl_str_cat `o` `p` )
    = e ( pick big )
    = acc + acc ( nurl_str_len e )
    // acc = 14 — and big is still intact:
    = acc + acc ( nurl_str_len big )
    // acc = 18

    // parameter borrow through a helper
    = acc + acc ( take_param `hello` )
    // acc = 23

    ( nurl_print ( nurl_str_int acc ) )
    ( nurl_print `\n` )
    ^ 0
}
