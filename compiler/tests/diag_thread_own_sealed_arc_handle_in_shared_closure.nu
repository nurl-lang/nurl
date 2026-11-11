// A program's own sealed handle that keeps its state in an Arc its raw code
// writes is one unsynchronised state, like a handle held in an rcbox: a
// closure several threads run must not capture it. `Tally` carries no
// `% Sync`, so nothing says its functions take a lock.

$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

: TallyImpl { ( Vec i ) v }

: Tally { ( Arc TallyImpl ) a }

unsafe @ Tally_share Tally h → Tally { ^ @ Tally { ( arc_clone [TallyImpl] . h a ) } }

unsafe @ Tally_drop sink Tally h → v {}

unsafe @ tally_new → Tally { ^ @ Tally { ( arc_new [TallyImpl] @ TallyImpl { ( vec_new [i] ) } ) } }

unsafe @ tally_add Tally h i x → v {
    : *TallyImpl p ( arc_ptr [TallyImpl] . h a )
    ( vec_push [i] . p v x )
}

: Holder { ( @ v i ) f i tag }

@ hit ( Arc Holder ) a i n → v {
    : Holder h ( arc_get [Holder] a )
    : ( @ v i ) g . h f
    : ~ i j 0
    ~ < j n {
        ( g j )
        = j + j 1
    }
}

@ main → i {
    : Tally t ( tally_new )
    : ( @ v i ) work \ i k → v { ( tally_add t k ) }
    : ( Arc Holder ) shared ( arc_new [Holder] @ Holder { work 7 } )
    : ( Vec ( Thread ) ) ts ( vec_new [Thread] )
    : ~ i n 0
    ~ < n 8 {
        : ( Arc Holder ) mine ( arc_clone [Holder] shared )
        : ( @ v ) body \ → v { ( hit mine 3000 ) }
        ?? ( thread_spawn body ) {
            T th → { ( vec_push [Thread] ts th ) }
            F _ → {}
        }
        = n + n 1
    }
    ~ > ( vec_len [Thread] ts ) 0 { ?? ( vec_pop [Thread] ts ) { T th → { : i joined ( thread_join th ) } F → {} } }
    ^ 0
}
