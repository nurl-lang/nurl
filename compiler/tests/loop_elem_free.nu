// Negative control for the loop-carried move check + the bck_join_state
// fix. Three legal "free inside a loop" shapes that must all COMPILE,
// LINK and RUN clean (no use-after-move false positive):
//
//   1. foreach freeing the loop ELEMENT      — fresh load each pass
//   2. while-loop freeing a LOOP-LOCAL binding — fresh alloc each pass
//   3. while-loop freeing an OUTER binding it RE-BINDS in the same pass
//
// Before the fix, (1) was wrongly rejected: bck_join_state copied a
// body-only binding's Moved state verbatim into the loop's fixpoint
// head instead of joining it to MaybeMoved, so the element looked
// definitely-moved on re-read.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

// 1. foreach element free.
@ free_elems → i {
    : ( Vec String ) ss ( vec_new [String] )
    ( vec_push [String] ss ( string_from `a` ) )
    ( vec_push [String] ss ( string_from `b` ) )
    : ~ i n 0
    ~ x ss {
        ( string_free x )
        = n + n 1
    }
    ( vec_free [String] ss )
    ^ n
}

// 2. loop-local free.
@ free_locals i times → i {
    : ~ i k 0
    ~ < k times {
        : ( Vec i ) tmp ( vec_new [i] )
        ( vec_push [i] tmp k )
        ( vec_free [i] tmp )
        = k + k 1
    }
    ^ times
}

// 3. free-then-rebind an outer binding each iteration.
@ free_rebind i times → i {
    : ~ ( Vec i ) buf ( vec_new [i] )
    : ~ i k 0
    ~ < k times {
        ( vec_free [i] buf )
        = buf ( vec_new [i] )
        ( vec_push [i] buf k )
        = k + k 1
    }
    : i last ( vec_len [i] buf )
    ( vec_free [i] buf )
    ^ last
}

@ main → i {
    : i a ( free_elems )
    : i b ( free_locals 4 )
    : i c ( free_rebind 3 )
    ( nurl_println_int + + a b c )
    ^ 0
}
