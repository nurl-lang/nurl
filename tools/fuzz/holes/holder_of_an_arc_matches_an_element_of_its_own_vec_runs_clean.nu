// holder_of_an_arc_matches_an_element_of_its_own_vec_runs_clean: two structs hold an Arc beside (or below) a plain Vec of their own: a cursor table whose cursors reach an Arc through an Rc (an LSM tree's iterator), and a server record with an Arc'd counter beside its Vec of entries. A function handed the struct matches an element of the struct's OWN Vec: the cursor is copied by its share function, the entry's String is grown in place.
// Neither payload can be a place inside an Arc's payload: its type (`Cur`, `Ent`) is no part of any Arc's payload the holder reaches (`Flt`, `Atomic`). Only a callee handed the Arc itself lends it one — a holder lent it its own. The control for the arc_payload_*_matched_out_of_a_holder_of_the_arc_* probes: taken for views of a frozen payload by the holder alone, both were refused (packages/lsmdb's iterator).
// map: ThruOK.noShare | A3 | runs-clean | - | the `??` payload of a function handed a struct that holds an Arc beside its own Vec — an element of that Vec, whose type sits in no Arc's payload — copied by a share function, and grown in place: no view of a frozen payload (agora #646)
$ `stdlib/std/arc.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Flt { ( Vec i ) bits i n }

: Impl { ( Arc Flt ) flt i pos }

: Cur { ( Rc Impl ) l }

: It { ( Vec Cur ) curs i src }

@ share Cur h → Cur { ^ @ Cur { ( rc_clone [Impl] . h l ) } }

@ cursor It it i k → Cur {
    ?? ( vec_get [Cur] . it curs k ) {
        T c → { ^ ( share c ) }
        F _ → { ( nurl_panic `no such cursor` ) }
    }
}

: Ent { String name s tag }

: Srv { ( Arc Atomic ) hits ( Vec Ent ) ents }

@ ent_of Srv s i k → ?Ent { ^ ( vec_get [Ent] . s ents k ) }

@ main → i {
    : ( Vec Cur ) cs ( vec_new [Cur] )
    ( vec_push [Cur] cs @ Cur { ( rc_new [Impl] @ Impl { ( arc_new [Flt] @ Flt { ( vec_new [i] ) 0 } ) 0 } ) } )
    ( vec_push [Cur] cs @ Cur { ( rc_new [Impl] @ Impl { ( arc_new [Flt] @ Flt { ( vec_new [i] ) 0 } ) 1 } ) } )
    : It it @ It { cs 0 }
    : Cur c ( cursor it 1 )
    : Impl im ( rc_get [Impl] . c l )
    : ( Vec Ent ) es ( vec_new [Ent] )
    ( vec_push [Ent] es @ Ent { ( string_from `a name long enough to sit on the heap, not in the handle` ) `t` } )
    : Srv srv @ Srv { ( arc_new [Atomic] ( atomic_new 0 ) ) es }
    ?? ( ent_of srv 0 ) { T e → { ( string_push_str . e name `, grown in place` ) } F → {} }
    ^ - . im pos 1
}
