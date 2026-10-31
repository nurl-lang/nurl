// arc_payload_lent_through_a_struct: an Arc's payload is frozen once made, and a view of it handed to anything that changes it is rejected (h212, h213) — when the call that lent the view took the Arc itself. A helper that took a struct HOLDING the Arc (`: Holder { ( Arc Page ) a }`) and handed back a view of the payload lent the same memory, but the view was not traced to the Arc: the caller's write through it compiled, and with the payload shared it raced every thread reading it.
// Closed: a parameter whose type holds an Arc or a `% Frozen` handle — a struct's field, an enum's payload, an option, a generic argument; not through a handle that synchronises what it holds — lends frozen views like the Arc does (__ty_lend_frozen).
// main (before this PR): compiled; the writer and the readers raced on the page (ThreadSanitizer: data race), and readers saw torn pages.
// map: §6.5 | A3 | rejected | h288 | helper takes a struct holding an Arc and lends the payload; caller writes through the view while threads read
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`

: Page { ( Vec u ) data }
: Holder { ( Arc Page ) a i tag }

@ holder_bytes Holder h → ( Slice u ) { ^ ( slice_from_vec [u] . ( arc_get [Page] . h a ) data ) }

@ main → i {
    : ( Arc Page ) a ( arc_new [Page] @ Page { ( vec_zeroed [u] 64 ) } )
    : Holder h @ Holder { ( arc_clone [Page] a ) 1 }
    : !Thread ThreadErr r ( thread_spawn \ → v {
        : ~ i k 0
        ~ < k 100000 {
            : ( Slice u ) s ( slice_from_vec [u] . ( arc_get [Page] a ) data )
            : i b ( slice_byte s 3 )
            = k + k 1
        }
    } )
    : ( Slice u ) s ( holder_bytes h )
    : ~ i k 0
    ~ < k 100000 { ( slice_put [u] s 3 # u & k 255 ) = k + k 1 }
    ?? r { T t → { ( thread_join t ) } F _ → {} }
    ^ 0
}
