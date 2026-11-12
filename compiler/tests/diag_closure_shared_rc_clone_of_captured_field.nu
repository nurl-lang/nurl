// diag_closure_shared_rc_clone_of_captured_field.nu — agora #684's
// boundary: an Rc field of a captured struct, cloned by a closure several
// threads run, changes a count no lock or atomic guards — still refused
// (closure_shared_arc_clone_of_captured_field.nu is the Arc twin).

$ `stdlib/std/rc.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`

: In { ( Rc i ) r }

: App { In inn i n }

: Holder { ( @ i i ) f i tag }

@ main → i {
    : App a @ App { @ In { ( rc_new [i] 3 ) } 1 }
    : ( @ i i ) work \ i k → i {
        : ( Rc i ) c ( rc_clone [i] . . a inn r )
        ^ k
    }
    : ( Arc Holder ) shared ( arc_new [Holder] @ Holder { work 7 } )
    ^ 0
}
