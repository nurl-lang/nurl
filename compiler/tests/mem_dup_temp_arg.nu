// A `( mem_dup x )` copy handed straight to a call is a temporary the
// caller owns and drops after the call, like any owned call result. It was
// not dropped: the copy is no call, so the argument path found no callee to
// ask whether it owned the value — every copy leaked its shares (packages/
// embed's forward leaked each weight chunk this way, per layer).
$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/mem.nu`
$ `stdlib/std/arc.nu`

: ~ i g_drops 0

: BlkImpl { i id }

% Drop BlkImpl { @ drop BlkImpl x → v { = g_drops + g_drops 1 } }

: Lay { ( Arc BlkImpl ) w ( Arc BlkImpl ) b }

@ use_lay Lay l i k → b { ^ > k 0 }

@ run → v {
    : ( Arc BlkImpl ) a ( arc_new [BlkImpl] @ BlkImpl { 1 } )
    : Lay lay @ Lay { ( arc_clone [BlkImpl] a ) ( arc_clone [BlkImpl] a ) }
    : ~ b ok T
    // a statement, an assignment and a binding, and in a match arm
    ( use_lay ( mem_dup lay ) 1 )
    = ok ( use_lay ( mem_dup lay ) 2 )
    : b r ( use_lay ( mem_dup lay ) 3 )
    : ~ ( Vec Lay ) ls ( vec_new [Lay] )
    ( vec_push [Lay] ls ( mem_dup lay ) )
    ?? ( vec_get [Lay] ls 0 ) {
        T x → { = ok ( use_lay ( mem_dup x ) 4 ) }
        F → {}
    }
}

@ main → i {
    ( run )
    ( nurl_print `block dropped: ` ) ( nurl_println_int g_drops )
    ^ 0
}
