// inout_replaces_owned.nu — a value assigned through an `inout` parameter
// replaces the caller's, and the one it replaces is released.
//
// An `inout` parameter is the caller's binding, lent for the call to be
// written (docs/MEMORY.md §2.4). `= . h item it` and `= s ( string_from … )`
// through one left the caller's old value with no owner: every call leaked
// it. A field the callee first handed to a consumer (`( item_free . h item
// )`), or took with `mem_take`, is emptied in the caller's struct, so the
// store after it releases nothing twice — and a binding that took a field
// and was then given another value (inside a closure: `recover \ → v { =
// response ( f req ) }`) leaves the field where it is.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: Item { i id String name }

: Payload { ( Vec u ) bytes i tag }

: Holder { Item item ( Vec u ) body Payload pay }

@ item_free sink Item it → v {}

@ set_item inout Holder h i n → v {
    = . h item @ Item { n ( string_from `made` ) }
}

@ free_then_set inout Holder h i n → v {
    ( item_free . h item )
    = . h item @ Item { n ( string_from `again` ) }
}

@ rename inout Item it → v { = . it name ( string_from `renamed` ) }

@ reset_text inout String s → v { = s ( string_from `fresh` ) }

@ reset_vec inout ( Vec i ) v → v { = v ( vec_new [i] ) }

// A local's value moves over: the local no longer drops it (under the
// caller, which read freed memory).
@ set_from_local inout String s → v {
    : String t ( string_from `from a local` )
    = s t
}

// Takes the body out and puts an empty one in; the caller gets the body.
@ take_body inout Holder h → ( Vec u ) {
    : ( Vec u ) moved . h body
    ( mem_take moved )
    = . h body ( vec_new [u] )
    ^ moved
}

// Took the payload, then was handed another one inside a `recover` body
// (http2_conn's panic fallback): the payload stays in h.
@ take_then_replace inout Holder h → Payload {
    : ~ Payload got . h pay
    : !v PanicInfo r ( recover \ → v { = got @ Payload { ( vec_new [u] ) 0 } } )
    ( mem_take got )
    ^ got
}

@ round → i {
    : ~ Holder h @ Holder { @ Item { 0 ( string_from `init` ) } ( vec_new [u] ) @ Payload { ( vec_new [u] ) 0 } }
    ( vec_push [u] . h body # u 7 )
    ( vec_push [u] . . h pay bytes # u 9 )
    ( set_item h 1 ) ( set_item h 2 )
    ( free_then_set h 3 )
    ( rename . h item ) ( rename . h item )
    : ~ String s ( string_from `init` )
    ( reset_text s ) ( reset_text s )
    : ~ String m ( string_from `init` )
    ( set_from_local m ) ( set_from_local m )
    : ~ ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v 1 )
    ( reset_vec v ) ( reset_vec v )
    : Payload kept ( take_then_replace h )
    : ( Vec u ) body ( take_body h )
    ^ + + + + . . h item id ( string_len s ) ( string_len m ) ( vec_len [u] body ) + ( vec_len [u] . kept bytes ) * 10 ( vec_len [u] . . h pay bytes )
}

@ main → i {
    : i a ( round )
    : i l0 ( live )
    : ~ i k 0
    ~ < k 20 { : i x ( round ) = k + k 1 }
    ( nurl_println ( nurl_str_cat `result ` ( nurl_str_int a ) ) )
    ( nurl_println ? == l0 ( live ) `live allocations: steady` ( nurl_str_cat `live allocations grew by ` ( nurl_str_int - ( live ) l0 ) ) )
    ^ 0
}
