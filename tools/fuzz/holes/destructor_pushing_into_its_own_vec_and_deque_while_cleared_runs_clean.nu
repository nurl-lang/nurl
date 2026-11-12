// destructor_pushing_into_its_own_vec_and_deque_while_cleared_runs_clean: nodes held in an Rc'd Vec and an Rc'd Deque push two nodes into their own container from their destructors while vec_clear, vec_truncate, vec_retain and deque_clear drop them; the containers are used and cleared again afterwards.
// Guard for agora #709: the elements a release drops leave the container's storage first (__vec_release_from, __dq_release_moved → mem_drop_moved): a push from a destructor lands in slots the release does not walk.
// main 70f7232: accepted, heap-use-after-free (a pushed node dropped twice, the old buffer freed under the release by a growth) and the elements written over leaked.
// map: §7.2 | A2 | runs-clean | - | agora #709 guard: a destructor that pushes into the Vec / Deque it is being cleared or truncated out of — every element dropped once, the pushed ones kept
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/deque.nu`

: ~ i g_budget 0
: Node { String tag ( Rc ( Vec Node ) ) home }

% Drop Node {
    @ drop Node n → v {
        ? > g_budget 0 {
            = g_budget - g_budget 1
            ( node . n home `pushed, long enough for the heap` )
            ( node . n home `pushed again, long enough for the heap` )
        } {}
    }
}

@ node ( Rc ( Vec Node ) ) home s tag → v { ( vec_push [Node] ( rc_get [( Vec Node )] home ) @ Node { ( string_from tag ) ( rc_clone [( Vec Node )] home ) } ) }

: DNode { String tag ( Rc ( Deque DNode ) ) home }

% Drop DNode {
    @ drop DNode n → v {
        ? > g_budget 0 {
            = g_budget - g_budget 1
            ( dnode . n home `pushed, long enough for the heap` )
            ( dnode . n home `pushed again, long enough for the heap` )
        } {}
    }
}

@ dnode ( Rc ( Deque DNode ) ) home s tag → v { ( deque_push_back [DNode] ( rc_get [( Deque DNode )] home ) @ DNode { ( string_from tag ) ( rc_clone [( Deque DNode )] home ) } ) }

@ keep_none Node n → b { ^ F }

@ main → i {
    : ( Rc ( Vec Node ) ) home ( rc_new [( Vec Node )] ( vec_new [Node] ) )
    ( node home `a, long enough for the heap` ) ( node home `b, long enough for the heap` ) ( node home `c, long enough for the heap` )
    = g_budget 3
    ( vec_clear [Node] ( rc_get [( Vec Node )] home ) )
    = g_budget 2
    : b t ( vec_truncate [Node] ( rc_get [( Vec Node )] home ) 1 )
    = g_budget 2
    ( vec_retain [Node] ( rc_get [( Vec Node )] home ) \ Node n → b { ^ ( keep_none n ) } )
    = g_budget 0
    ( nurl_println ( nurl_str_int ( vec_len [Node] ( rc_get [( Vec Node )] home ) ) ) )
    ( vec_clear [Node] ( rc_get [( Vec Node )] home ) )
    : ( Rc ( Deque DNode ) ) dh ( rc_new [( Deque DNode )] ( deque_new [DNode] ) )
    ( dnode dh `d0, long enough for the heap` ) ( dnode dh `d1, long enough for the heap` ) ( dnode dh `d2, long enough for the heap` )
    = g_budget 3
    ( deque_clear [DNode] ( rc_get [( Deque DNode )] dh ) )
    = g_budget 0
    ( nurl_println ( nurl_str_int ( deque_len [DNode] ( rc_get [( Deque DNode )] dh ) ) ) )
    ( deque_clear [DNode] ( rc_get [( Deque DNode )] dh ) )
    ^ 0
}
