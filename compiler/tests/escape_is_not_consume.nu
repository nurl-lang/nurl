// Escaping is not consuming. Both directions are pinned here, because the
// compiler answers them from two different summaries and a single one of
// them is the whole difference between a live binding and a NULL read.
//
// NEGATIVE: a callee may store a borrowed pointer into a block it never
// frees — stdlib/std/process.nu __build_argv pokes `cmd` into the argv
// array it hands to execvp. That is an escape (the address outlives the
// call) but not a move, so the binding is still live below the call and
// this scope still frees it. Reading the escape summary as ownership
// stranded the buffer AND nulled the binding on the arms after the call.
//
// POSITIVE: string_from_take really does adopt its argument, says so with
// `sink`, and must still move — the caller must not free it twice.
$ `stdlib/core/string.nu`

& `c` @ nurl_free_count → i

// The __build_argv shape: the argument's address lands in a heap block the
// callee returns. Nothing in here ever frees that address.
@ borrow_into_block s text → s {
    : s block ( nurl_alloc 16 )
    : *u text_p # *u text
    ( nurl_poke block 0 # i text_p )
    ( nurl_poke block 1 0 )
    ^ block
}

// Escaping callee, reached through a forwarding wrapper: the whole-module
// summary is what a call site consults, so the indirection must not
// upgrade a borrow into a move either.
@ forward_into_block s text → s { ^ ( borrow_into_block text ) }

@ borrowed → v {
    : s owned ( nurl_str_cat `still` ` here` )
    : s direct ( borrow_into_block owned )
    ( nurl_free direct )
    // Live after the call: borrowed, not moved.
    ( nurl_print owned )
    : s forwarded ( forward_into_block owned )
    ( nurl_free forwarded )
    ( nurl_print `\n` )
}

@ consumed → v {
    : s raw ( nurl_str_cat `adopted` `` )
    : String owner ( string_from_take raw + ( nurl_str_len raw ) 1 )
    ( nurl_print ( string_data owner ) )
    ( nurl_print `\n` )
    ( string_free owner )
}

@ main → i {
    : i before ( nurl_free_count )
    ( borrowed )
    // Two scratch blocks freed by hand, plus the auto-dropped string that
    // neither callee ever owned.
    : i borrowed_drops - ( nurl_free_count ) before
    : i between ( nurl_free_count )
    ( consumed )
    // The adopted buffer plus the String control block — freed once each,
    // by the owner, never again by the moved-from binding.
    : i consumed_drops - ( nurl_free_count ) between
    ( nurl_print ? == borrowed_drops 3 `borrow_survives=T\n` `borrow_survives=F\n` )
    ( nurl_print ? == consumed_drops 2 `adoption_moves=T\n` `adoption_moves=F\n` )
    ^ ? & == borrowed_drops 3 == consumed_drops 2 0 1
}
