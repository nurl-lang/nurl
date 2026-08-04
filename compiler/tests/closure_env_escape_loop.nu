// closure_env_escape_loop.nu — an escaped closure env stays escaped,
// even when the escape happens inside a nested block.
//
// docs/MEMORY.md §7.4: a closure handed to a callee that does more than
// invoke it — stores it, detaches it, decomposes it — has escaped, and
// its heap env is the consumer's to release, never the creating frame's.
// The escape sites record that by untracking the binding.
//
// They recorded it into the block's symbol scope, so the matching pop
// threw it away and the function-exit drain freed an env its consumer
// was still holding. The same closure therefore behaved differently
// depending on whether the call sat inside a `~` / `?` body — and the
// failure is silent twice over: the runtime recycles small blocks
// through a freelist, so the free neither traps nor shows up under
// ASan, and the next allocation of that size simply takes the block.
// The closure then reads someone else's bytes as its captures. That is
// what this test measures: `hold` escapes its closure from inside a
// loop, `main` allocates in the same size class straight afterwards,
// and the closure must still see seed = 7.
//
// `spawn` is the shape that found this (it decomposes the closure into
// fn + env), but nothing here needs a scheduler — the bug is in the
// compiler's scope handling, so the test is a plain, deterministic
// program.

: Holder { ( @ v ) f }
: ~ i n 0

// An escaping callee: it does not invoke the closure, it hands it on in
// a value that outlives the call.
@ stash ( @ v ) f → Holder { ^ @ Holder { f } }

@ hold i seed → Holder {
    : ( @ v ) w \ → v { = n + n seed }
    : ~ Holder h @ Holder { \ → v {} }
    : ~ i k 0
    ~ < k 1 { = h ( stash w ) = k + k 1 }
    ^ h
}

@ main → i {
    : Holder h ( hold 7 )

    // Same size class as the env. If `hold` wrongly freed it, this
    // takes the block and overwrites the captured seed.
    : s junk ( nurl_alloc 24 )
    ( nurl_poke junk 0 999 )
    ( nurl_poke junk 1 999 )
    ( nurl_poke junk 2 999 )

    : ( @ v ) g . h f
    ( g )
    ( nurl_print `n=` )
    ( nurl_print ( nurl_str_int n ) )
    ( nurl_print `\n` )

    ( nurl_free junk )
    // The env is ours to release now — the closure escaped into `h`.
    ( nurl_free # s # *u g 1 )
    ^ 0
}
