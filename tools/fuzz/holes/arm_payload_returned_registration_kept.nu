// arm_payload_returned_registration_kept: a `??` arm that hands its payload out as the match's value (`T t → t`) — a library handle registered with the panic journal under its drop flag — cleared the flag but left the registration: once the function had returned, a panic later in the same recover extent read the flag from a frame that no longer existed (stack-use-after-return) and could drop the handle again.
// Closed: an arm exit whose value is consumed and that drops nothing still ends its locals' journal registrations (mem_arm_exits_emit).
// main (before this PR): AddressSanitizer reported stack-use-after-return in the journal drain.
// map: §7.2 | A2 | runs-clean | h296 | a ?? arm handing its handle payload out as the match value left its journal registration: a later panic read a dead frame's flag
$ `stdlib/std/arc.nu`
$ `stdlib/std/panic.nu`

: Meta { i id }
: Info { ( Arc Meta ) a }

@ Info_share Info t → Info { ^ @ Info { ( arc_clone [Meta] . t a ) } }

@ Info_drop sink Info t → v {}

@ find i k → ?Info { ? > k 0 { ^ @ ?Info { T @ Info { ( arc_new [Meta] @ Meta { k } ) } } } {} ^ @ ?Info { F } }

@ get i k → Info {
    ^ ?? ( find k ) {
        T t → t
        F → { ( panic `none` ) ^ ( get 1 ) }
    }
}

@ main → i {
    : ~ i got 0
    : !v PanicInfo r ( recover \ → v {
        : Info x ( get 5 )
        = got . ( arc_get [Meta] . x a ) id
        ( panic `later` )
    } )
    ( nurl_println_int got )
    ^ 0
}
