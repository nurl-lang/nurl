// return_cast_word_is_view.nu — a library handle rebuilt from a word and
// returned (`^ # H w`) is a view of whatever holds the word, as binding it
// (`: H m # H w`) is; the caller does not release it.
//
// A cast from an integer counted as a value made from a number (an enum
// tag, the empty `# ( Vec T ) 0`), so the function's result was the
// caller's to drop: every call released the table's handle, and the next
// read was a use-after-free (packages/anomaly's forecast model table).
// An owner is built with a literal — `@ H { # s w }` — or a share.

$ `stdlib/core/vec.nu`
$ `stdlib/core/rcbox.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: HImpl { i v }
: H { s ctl }

unsafe

@ H_share H h → H { ^ @ H { # s ( rcbox_share # i . h ctl ) } }

@ H_drop sink H h → v {
    ( mem_forget h )
    ( rcbox_release [HImpl] # i . h ctl )
}

unsafe

@ h_new i v → H { ^ @ H { # s ( rcbox_new [HImpl] @ HImpl { v } ) } }

unsafe

@ h_get H h → i {
    : *HImpl p ( rcbox_ptr [HImpl] # i . h ctl )
    ^ . p v
}

@ word_at ( Vec i ) tab i j → i { ^ ?? ( vec_get [i] tab j ) { T x → x F _ → 0 } }

// a view of the table's handle
@ at ( Vec i ) tab i j → H { ^ # H ( word_at tab j ) }

// an owner: a share of it
@ take ( Vec i ) tab i j → H { ^ ( H_share ( at tab j ) ) }

unsafe

@ main → i {
    : i l0 ( live )
    : ( Vec i ) tab ( vec_new [i] )
    : H h ( h_new 42 )
    ( vec_push [i] tab # i h )
    ( mem_forget h )  // the table's word owns it now
    : ~ i acc 0
    : ~ i k 0
    ~ < k 20 {
        = acc + acc ( h_get ( at tab 0 ) )
        : H mine ( take tab 0 )
        = acc + acc ( h_get mine )
        = k + k 1
    }
    ( nurl_print_int acc ) ( nurl_print `\n` )
    // the table gives its handle up: an owner made from the word
    : H last @ H { # s ( word_at tab 0 ) }
    ( H_drop last )
    ( nurl_print `live: ` ) ( nurl_print_int - ( live ) l0 ) ( nurl_print `\n` )
    ^ 0
}
