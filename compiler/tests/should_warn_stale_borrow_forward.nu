// should_warn_stale_borrow_forward.nu — §2.10 stops depending on
// definition order (docs/MEMORY.md §6.4).
//
// A pointer borrowed with `vec_data` goes stale when the container is
// grown through a HELPER, and that was already reported — but only when
// the helper sat ABOVE the borrow. Below it, its mutation summary was
// still empty at the call, and empty reads as "does not mutate" rather
// than "not compiled yet": the same program, two verdicts, decided by
// where the author happened to put the function.
//
// The call now kills the pointer PROVISIONALLY — carrying the callee it
// is conditional on inside the dead-set entry, so the arm snapshot /
// union machinery treats it exactly like a certain kill — and the use
// site parks its report. resolve_pending_stale() prints it after the
// module, when the summary is final.
//
// Two positives (forward helper, forward helper inside a `?` arm) and
// two controls (a forward helper that only READS, and a re-fetch after
// the forward call).

$ `stdlib/core/vec.nu`

// POSITIVE — `grow` is defined at the bottom of this file.
@ stale_via_forward_helper → i {
    : ~ ( Vec u ) v ( vec_new [u] )
    ( vec_push [u] v # u 1 )
    : *u p ( vec_data [u] v )
    ( grow v )
    : i x # i . p 0  // warns
    ( vec_free [u] v )
    ^ x
}

// POSITIVE — the mutation is inside a `?` arm. After the join either
// arm may have run, so the pointer is stale exactly as it is when the
// helper sits above.
@ stale_via_forward_helper_in_arm → i {
    : ~ ( Vec u ) v ( vec_new [u] )
    ( vec_push [u] v # u 1 )
    : *u p ( vec_data [u] v )
    ? > 1 2 { ( grow v ) } {}
    : i x # i . p 0  // warns
    ( vec_free [u] v )
    ^ x
}

// CONTROL — a forward-defined helper that only READS its container
// cannot reallocate anything. The provisional kill is a question, and
// the answer here is no.
@ no_warn_forward_reader → i {
    : ~ ( Vec u ) v ( vec_new [u] )
    ( vec_push [u] v # u 1 )
    : *u p ( vec_data [u] v )
    : i n ( peek v )
    : i x # i . p 0
    ( vec_free [u] v )
    ^ + x n
}

// CONTROL — re-fetching after the forward call clears the borrow, just
// as it does after an inline `vec_push`.
@ no_warn_refetch_after_forward → i {
    : ~ ( Vec u ) v ( vec_new [u] )
    ( vec_push [u] v # u 1 )
    : ~ * u p ( vec_data [u] v )
    ( grow v )
    = p ( vec_data [u] v )
    : i x # i . p 0
    ( vec_free [u] v )
    ^ x
}

@ main → i {
    : i a ( stale_via_forward_helper )
    : i b ( stale_via_forward_helper_in_arm )
    : i c ( no_warn_forward_reader )
    : i d ( no_warn_refetch_after_forward )
    ( nurl_print `done\n` )
    ^ 0
}

@ grow ( Vec u ) v → v { ( vec_push [u] v # u 2 ) }

@ peek ( Vec u ) v → i { ^ ( vec_len [u] v ) }
