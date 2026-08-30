// borrow_closure_capture_use_after_free.nu — freeing a handle a closure
// captured, then using the closure, is a compile error.
//
// The dual of borrow_closure_body_double_free. That one taught the checker
// to walk the closure BODY; this one connects the body back to the frame
// that owns the handles it captured. A closure body is analysed as its own
// function, where a capture is never seeded and therefore unreportable, and
// the enclosing function's walk never saw the body's reads at all — so
// nothing tied `( vec_free v )` to a later `( f )`. Every spelling of that
// shape compiled clean and ran on freed memory: the Vec form segfaults, the
// String and HashMap forms silently read a released control block.
//
// The fix is one fact, carried across the boundary: a closure binding holds
// a COPY of every heap handle its body captured, so an invocation of the
// binding READS those handles. gen_closure_expr publishes the capture list,
// gen_let / gen_assign record it on the binding, and the invocation sites
// expand it into the statement's read set — after which the existing
// use-after-move machinery reports it with no new state at all.
//
// POSITIVEs below, one per spelling: read, mutate, free-then-capture,
// invoke through a helper that only calls its parameter, free through a
// `sink` parameter, a closure captured by another closure, and the `=`
// rebinding form.
//
// CONTROLs: the same programs with the free AFTER the last use; a container
// rebound to a fresh handle before the second call; an inline `vec_each`
// callback; and — the shape that decides the rule — reclaiming a closure's
// heap env with `nurl_free` after freeing what it captured. That last one is
// how async_mn / async_sleep end, and reading a mere VALUE load of a closure
// as a use of its captures rejected both. Invocation is the discriminator:
// the capture list is expanded at a call, and at an argument the callee is
// known to invoke (its invoke-only set), never at a plain load.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ apply ( @ i ) f → i { ^ ( f ) }

@ release sink ( Vec i ) v → v { ( vec_free [i] v ) }

@ control → i {
    // Freed after the last call — the closure is dead by then.
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a 1 )
    : ( @ i ) ca \ → i { ^ ( vec_len [i] a ) }
    : i n1 ( ca )
    ( vec_free [i] a )
    ( nurl_free # s # *u ca 1 )

    // Rebound to a fresh handle before the second call.
    : ~ ( Vec i ) b ( vec_new [i] )
    : ( @ i ) cb \ → i { ^ ( vec_len [i] b ) }
    : i n2 ( cb )
    ( vec_free [i] b )
    = b ( vec_new [i] )
    : i n3 ( cb )
    ( vec_free [i] b )
    ( nurl_free # s # *u cb 1 )

    // An inline callback over a container nobody frees underneath it.
    : ( Vec i ) c ( vec_new [i] )
    : ( Vec i ) d ( vec_new [i] )
    ( vec_push [i] c 7 )
    ( vec_each [i] c \ i x → v { ( vec_push [i] d x ) } )
    : i n4 ( vec_len [i] d )
    ( vec_free [i] c )
    ( vec_free [i] d )
    ^ + + + n1 n2 n3 n4
}

@ main → i {
    ( nurl_print ( nurl_str_int ( control ) ) )

    // POSITIVE — read a captured Vec after freeing it.
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 41 )
    : ( @ i ) rd \ → i { ^ ( vec_len [i] v ) }
    ( vec_free [i] v )
    ( nurl_print ( nurl_str_int ( rd ) ) )

    // POSITIVE — mutate a captured Vec after freeing it.
    : ( Vec i ) w ( vec_new [i] )
    : ( @ v ) mu \ → v { ( vec_push [i] w 7 ) }
    ( vec_free [i] w )
    ( mu )

    // POSITIVE — capture a String that is already freed.
    : String s ( string_from `hi` )
    ( string_free s )
    : ( @ i ) sl \ → i { ^ ( string_len s ) }
    ( nurl_print ( nurl_str_int ( sl ) ) )

    // POSITIVE — invoked one call deep, through an invoke-only parameter.
    : ( Vec i ) x ( vec_new [i] )
    : ( @ i ) ix \ → i { ^ ( vec_len [i] x ) }
    ( vec_free [i] x )
    ( nurl_print ( nurl_str_int ( apply ix ) ) )

    // POSITIVE — consumed by a `sink` parameter, not a `_free` call.
    : ( Vec i ) y ( vec_new [i] )
    : ( @ i ) iy \ → i { ^ ( vec_len [i] y ) }
    ( release y )
    ( nurl_print ( nurl_str_int ( iy ) ) )

    // POSITIVE — reached through a closure that captured the closure.
    : ( Vec i ) z ( vec_new [i] )
    : ( @ i ) inner \ → i { ^ ( vec_len [i] z ) }
    : ( @ i ) outer \ → i { ^ ( inner ) }
    ( vec_free [i] z )
    ( nurl_print ( nurl_str_int ( outer ) ) )

    // POSITIVE — the `=` rebinding form of the same binding.
    : ( Vec i ) q ( vec_new [i] )
    : ~ ( @ i ) qc \ → i { ^ 0 }
    = qc \ → i { ^ ( vec_len [i] q ) }
    ( vec_free [i] q )
    ( nurl_print ( nurl_str_int ( qc ) ) )
    ^ 0
}
