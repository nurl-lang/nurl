// arc_basic.nu — Arc[T] atomic refcount on a single thread.
// Threaded sharing is exercised in arc_threads.nu.

$ `stdlib/core/string.nu`
$ `stdlib/std/arc.nu`

@ main → i {
    : ( Arc i ) a ( arc_new [i] 333 )
    ( nurl_print `count=` ) ( nurl_print ( nurl_str_int ( arc_strong [i] a ) ) )
    ( nurl_print ` value=` ) ( nurl_print ( nurl_str_int ( arc_get [i] a ) ) )
    ( nurl_print `\n` )

    : ( Arc i ) a2 ( arc_clone [i] a )
    : ( Arc i ) a3 ( arc_clone [i] a )
    : ( Arc i ) a4 ( arc_clone [i] a )
    ( nurl_print `after 3 clones count=` ) ( nurl_print ( nurl_str_int ( arc_strong [i] a ) ) )
    ( nurl_print `\n` )

    // All clones share one storage slot.
    ( arc_set [i] a3 99 )
    ( nurl_print `a=` ) ( nurl_print ( nurl_str_int ( arc_get [i] a ) ) )
    ( nurl_print ` a4=` ) ( nurl_print ( nurl_str_int ( arc_get [i] a4 ) ) )
    ( nurl_print `\n` )

    // arc_ptr aliases the value field.
    : *i p ( arc_ptr [i] a )
    = . p 0 - 0 7
    ( nurl_print `via ptr a=` ) ( nurl_print ( nurl_str_int ( arc_get [i] a ) ) )
    ( nurl_print ` a3=` ) ( nurl_print ( nurl_str_int ( arc_get [i] a3 ) ) )
    ( nurl_print `\n` )

    // Drop three clones — count walks down.
    ( arc_free [i] a4 )
    ( arc_free [i] a3 )
    ( arc_free [i] a2 )
    ( nurl_print `after 3 frees count=` ) ( nurl_print ( nurl_str_int ( arc_strong [i] a ) ) )
    ( nurl_print `\n` )

    // Last free releases.
    ( arc_free [i] a )
    ( nurl_print `done\n` )
    ^ 0
}
