// vec_get_noncopyable_payload_stored_leaves_a_null_slot: a payload of a `vec_get` result that cannot be copied and has no all-zero value (a struct holding a trait object), handed from its `??` arm to a callee that keeps it (`vec_push`): codegen took it out of its slot, leaving zero bytes in the Vec, and a later method call through that element called a null vtable.
// Closed: such a payload is taken out only where its type's all-zero value is one (__zero_invalid); otherwise its store is judged at module end, on the callee's final summary, as a store of what a call lends (resolve_nc_lent_stores), and refused where the callee keeps or releases it.
// main: accepted; AddressSanitizer reported SEGV on unknown address 0x8 (a call through the null vtable).
// map: §7.6 | A2 | rejected | - | a non-copyable vec_get payload stored by a callee left a zeroed trait object in the Vec
$ `stdlib/core/vec.nu`

% Speaker [T] { @ speak T self → i }

: Dog { i pitch }

% Speaker Dog { @ speak Dog d → i { ^ . d pitch } }

: Pet { % Speaker s }

@ mk i k → Pet { ^ @ Pet { ( dyn Speaker @ Dog { k } ) } }

@ sum ( Vec Pet ) vs → i {
    : ~ i t 0
    ~ x vs { = t + t ( speak . x s ) }
    ^ t
}

@ main → i {
    : ( Vec Pet ) vs ( vec_new [Pet] )
    ( vec_push [Pet] vs ( mk 4 ) )
    : ( Vec Pet ) ws ( vec_new [Pet] )
    ?? ( vec_get [Pet] vs 0 ) { T p → { ( vec_push [Pet] ws p ) } F → {} }
    ( nurl_println_int ( sum ws ) )
    ( nurl_println_int ( sum vs ) )
    ^ 0
}
