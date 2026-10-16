// A local copy of a parameter's element, read in a loop body, is no
// storage of the caller's once the loop is done: storing into another
// field of the parameter afterwards is fine. (The borrow checker used to
// take the ended binding for a live alias of the caller's storage.)
$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`

: Blk { i id }
: Buf { i n ? ( Arc Blk ) mem }
: Node { i n ( Vec i ) dims Buf val }
: Prog { ( Vec Node ) nodes ( Vec i ) rec }

@ none → Buf { ^ @ Buf { 0 @ ?( Arc Blk ) { F } } }

@ node inout Prog pg i id → Node {
    ^ ?? ( vec_get [Node] . pg nodes id ) {
        T x → x
        F → @ Node { 0 ( vec_new [i] ) ( none ) }
    }
}

@ run inout Prog pg → b {
    : ~ ( Vec i ) zs ( vec_new [i] )
    : ~ i k 0
    ~ < k 2 {
        : Node nd ( node pg k )
        ( vec_push [i] zs . nd n )
        = k + k 1
    }
    = . pg rec zs
    ^ T
}

@ main → i {
    : ~ Prog p @ Prog { ( vec_new [Node] ) ( vec_new [i] ) }
    ( vec_push [Node] . p nodes @ Node { 3 ( vec_new [i] ) ( none ) } )
    ( vec_push [Node] . p nodes @ Node { 4 ( vec_new [i] ) ( none ) } )
    : b _r ( run p )
    ( nurl_println_int ( vec_len [i] . p rec ) )
    ^ 0
}
