// sink_param_into_inout.nu — a `sink` parameter assigned to an `inout`
// parameter moves into the caller's slot.
//
// `@ put inout ( Vec u ) slot sink ( Vec u ) v → v { = slot v }`: the slot
// took `v`'s handle, but `v` — a parameter, so not "a local that owns its
// value outright" — was still dropped at put's exit, and the caller's slot
// read freed memory (stdlib/std/tls*.nu's "replace what a field behind a
// pointer holds" helper). The old slot value is dropped; `v` is not.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ put_v inout ( Vec u ) slot sink ( Vec u ) v → v { = slot v }

@ put [T] inout T slot sink T v → v { = slot v }

@ fresh i n → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u k ) = k + k 1 }
    ^ v
}

@ main → i {
    : i l0 ( live )
    : ~ ( Vec u ) b ( vec_new [u] )
    : ~ i k 0
    ~ < k 10 {
        : ( Vec u ) t ( fresh 5 )
        ( put_v b t )
        ( put [( Vec u )] b ( fresh 3 ) )
        ( put_v b ( fresh 4 ) )
        = k + k 1
    }
    ( nurl_print `len: ` ) ( nurl_print_int ( vec_len [u] b ) ) ( nurl_print `\n` )
    // b's own value remains: its Vec (ctl + buffer)
    ( nurl_print `live: ` ) ( nurl_print_int - ( live ) l0 ) ( nurl_print `\n` )
    ^ 0
}
