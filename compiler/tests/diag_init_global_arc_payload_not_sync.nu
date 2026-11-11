// diag_init_global_arc_payload_not_sync.nu — every thread reads a global
// set at start; an Arc's payload is read by all of them at once, so it must
// be Sync, as the payload of an Arc that crosses to a thread must. A struct
// holding an Rc is not (agora #639).
$ `stdlib/std/rc.nu`
$ `stdlib/std/arc.nu`

: Holder { ( Rc i ) r }

@ make → ( Arc Holder ) { ^ ( arc_new [Holder] @ Holder { ( rc_new [i] 5 ) } ) }

: ( Arc Holder ) g_one ( make )

@ main → i {
    : Holder h ( arc_get [Holder] g_one )
    ^ - ( rc_strong [i] . h r ) 1
}
