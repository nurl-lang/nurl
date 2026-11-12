// The Send derivation reads a type whole: an Rc twelve structs down is the
// same Rc it is one struct down. The walk used to give up after ten levels
// and answer for the rest that nothing was in the way (agora #711).
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`

: L1 { ( Rc i ) r }
: L2 { L1 a }
: L3 { L2 a }
: L4 { L3 a }
: L5 { L4 a }
: L6 { L5 a }
: L7 { L6 a }
: L8 { L7 a }
: L9 { L8 a }
: L10 { L9 a }
: L11 { L10 a }
: L12 { L11 a }

@ look L12 x → v {}

@ main → i {
    : ( Rc i ) r ( rc_new [i] 5 )
    : L12 deep @ L12 { @ L11 { @ L10 { @ L9 { @ L8 { @ L7 { @ L6 { @ L5 { @ L4 { @ L3 { @ L2 { @ L1 { r } } } } } } } } } } } }
    ?? ( thread_spawn \ → v { ( look deep ) } ) {
        T t → { ( thread_join t ) }
        F _ → {}
    }
    ^ 0
}
