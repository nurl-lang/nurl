// container_destructor_reenters.nu — a destructor that reaches the Vec or
// Deque it is being dropped out of, and pushes into it (Agora #709).
//
// vec_clear, vec_truncate, vec_retain and deque_clear move the elements
// they drop out of the container's storage before the first destructor
// runs: a destructor that pushes into the container — grows it, clears it
// — writes into slots the release does not use. Every element is dropped
// once, in index order; what a destructor pushes stays in the container.
// Before, the elements were dropped out of the container's own buffer, its
// count already short: a push wrote over the next element to go (never
// dropped), the release then dropped the element pushed while the
// container held it too, and a push that grew the buffer freed the storage
// the release was walking (heap-use-after-free under ASan).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/deque.nu`

: ~ i g_budget 0

: Node { String tag ( Rc ( Vec Node ) ) home }

% Drop Node {
    @ drop Node n → v {
        ( nurl_println ( nurl_str_cat `drop ` ( string_data . n tag ) ) )
        ? > g_budget 0 {
            = g_budget - g_budget 1
            ( node . n home ( nurl_str_cat ( string_data . n tag ) `.1` ) )
            ( node . n home ( nurl_str_cat ( string_data . n tag ) `.2` ) )
        } {}
    }
}

@ node ( Rc ( Vec Node ) ) home s tag → v {
    ( vec_push [Node] ( rc_get [( Vec Node )] home ) @ Node { ( string_from tag ) ( rc_clone [( Vec Node )] home ) } )
}

: DNode { String tag ( Rc ( Deque DNode ) ) home }

% Drop DNode {
    @ drop DNode n → v {
        ( nurl_println ( nurl_str_cat `drop ` ( string_data . n tag ) ) )
        ? > g_budget 0 {
            = g_budget - g_budget 1
            ( dnode . n home ( nurl_str_cat ( string_data . n tag ) `.1` ) )
            ( dnode . n home ( nurl_str_cat ( string_data . n tag ) `.2` ) )
        } {}
    }
}

@ dnode ( Rc ( Deque DNode ) ) home s tag → v {
    ( deque_push_back [DNode] ( rc_get [( Deque DNode )] home ) @ DNode { ( string_from tag ) ( rc_clone [( Deque DNode )] home ) } )
}

@ vlen ( Rc ( Vec Node ) ) home s what → v {
    ( nurl_println ( nurl_str_cat3 what ` len ` ( nurl_str_int ( vec_len [Node] ( rc_get [( Vec Node )] home ) ) ) ) )
}

@ starts_k Node n → b { ^ == ( nurl_str_get ( string_data . n tag ) 0 ) 107 }

// A destructor that clears the Vec it is dropped out of.
: CNode { String tag ( Rc ( Vec CNode ) ) home }

% Drop CNode {
    @ drop CNode n → v {
        ( nurl_println ( nurl_str_cat `drop ` ( string_data . n tag ) ) )
        ? > g_budget 0 { = g_budget - g_budget 1 ( vec_clear [CNode] ( rc_get [( Vec CNode )] . n home ) ) } {}
    }
}

@ main → i {
    : ( Rc ( Vec Node ) ) home ( rc_new [( Vec Node )] ( vec_new [Node] ) )
    // vec_clear: a, b and c push two each; the six stay.
    ( node home `a` ) ( node home `b` ) ( node home `c` )
    = g_budget 3
    ( vec_clear [Node] ( rc_get [( Vec Node )] home ) )
    ( vlen home `clear:` )
    = g_budget 0
    ( vec_clear [Node] ( rc_get [( Vec Node )] home ) )
    // vec_truncate: the first to go pushes two; they stay after `keep`.
    ( node home `keep` ) ( node home `x` ) ( node home `y` )
    = g_budget 1
    : b t ( vec_truncate [Node] ( rc_get [( Vec Node )] home ) 1 )
    ( vlen home `truncate:` )
    // vec_retain: the ones not starting with `k` go; the first of them pushes two.
    ( node home `kept` )
    = g_budget 1
    ( vec_retain [Node] ( rc_get [( Vec Node )] home ) \ Node n → b { ^ ( starts_k n ) } )
    ( vlen home `retain:` )
    = g_budget 0
    ( vec_clear [Node] ( rc_get [( Vec Node )] home ) )
    // deque_clear, the ring wrapped: two pushed per element for three.
    : ( Rc ( Deque DNode ) ) dh ( rc_new [( Deque DNode )] ( deque_new [DNode] ) )
    ( dnode dh `d0` ) ( dnode dh `d1` ) ( dnode dh `d2` ) ( dnode dh `d3` )
    : ?DNode f0 ( deque_pop_front [DNode] ( rc_get [( Deque DNode )] dh ) )
    : ?DNode f1 ( deque_pop_front [DNode] ( rc_get [( Deque DNode )] dh ) )
    ( dnode dh `d4` ) ( dnode dh `d5` )
    = g_budget 3
    ( deque_clear [DNode] ( rc_get [( Deque DNode )] dh ) )
    ( nurl_println ( nurl_str_cat `deque clear: len ` ( nurl_str_int ( deque_len [DNode] ( rc_get [( Deque DNode )] dh ) ) ) ) )
    = g_budget 0
    ( deque_clear [DNode] ( rc_get [( Deque DNode )] dh ) )
    // A destructor that clears the Vec while vec_truncate drops out of it.
    : ( Rc ( Vec CNode ) ) ch ( rc_new [( Vec CNode )] ( vec_new [CNode] ) )
    ( vec_push [CNode] ( rc_get [( Vec CNode )] ch ) @ CNode { ( string_from `c0` ) ( rc_clone [( Vec CNode )] ch ) } )
    ( vec_push [CNode] ( rc_get [( Vec CNode )] ch ) @ CNode { ( string_from `c1` ) ( rc_clone [( Vec CNode )] ch ) } )
    ( vec_push [CNode] ( rc_get [( Vec CNode )] ch ) @ CNode { ( string_from `c2` ) ( rc_clone [( Vec CNode )] ch ) } )
    = g_budget 1
    : b t2 ( vec_truncate [CNode] ( rc_get [( Vec CNode )] ch ) 1 )
    ( nurl_println ( nurl_str_cat `clearing destructor: len ` ( nurl_str_int ( vec_len [CNode] ( rc_get [( Vec CNode )] ch ) ) ) ) )
    ^ 0
}
