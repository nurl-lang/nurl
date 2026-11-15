// map: §6.5 | A3 | rejected | - | agora #689 guard: a sealed handle over an `( Arc Impl )` written through `arc_ptr`, captured by a closure kept in an `( Arc Holder )` that eight threads run
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

: TallyImpl { ( Vec i ) v }
: Tally { ( Arc TallyImpl ) a }
: Holder { ( @ v i ) f }

unsafe @ Tally_share Tally h → Tally { ^ @ Tally { ( arc_clone [TallyImpl] . h a ) } }
unsafe @ Tally_drop sink Tally h → v {}
unsafe @ tally_new → Tally { ^ @ Tally { ( arc_new [TallyImpl] @ TallyImpl { ( vec_new [i] ) } ) } }
unsafe @ tally_add Tally h i x → v {
    : *TallyImpl p ( arc_ptr [TallyImpl] . h a )
    ( vec_push [i] . p v x )
}

@ main → i {
    : Tally t ( tally_new )
    : ( @ v i ) g \ i k → v { ( tally_add t k ) }
    : ( Arc Holder ) shared ( arc_new [Holder] @ Holder { g } )
    : ( Vec ( Thread ) ) ts ( vec_new [Thread] )
    : ~ i n 0
    ~ < n 8 {
        : ( Arc Holder ) mine ( arc_clone [Holder] shared )
        : ( @ v ) body \ → v {
            : ( @ v i ) f . ( arc_get [Holder] mine ) f
            : ~ i k 0
            ~ < k 20000 { ( f k ) = k + k 1 }
        }
        ?? ( thread_spawn body ) { T th → { ( vec_push [Thread] ts th ) } F _ → {} }
        = n + n 1
    }
    ~ > ( vec_len [Thread] ts ) 0 { ?? ( vec_pop [Thread] ts ) { T th → { : i joined ( thread_join th ) } F → {} } }
    ^ 0
}
