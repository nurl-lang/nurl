// rc_resource_cycle_now.nu — a cycle of Rc handles that can hold a
// `% Resource` (stdlib/core/marker.nu) is released the moment the last
// handle from outside goes, not when the collector next runs: its drops
// (here: printing, standing in for closing a file) happen before the next
// statement. The same cycle without the mark waits for the collector —
// here, the end of the program.
$ `stdlib/core/marker.nu`
$ `stdlib/std/rc.nu`

: Res { i id }

% Drop Res { @ drop Res r → v { ( nurl_print `closed ` ) ( nurl_print_int . r id ) ( nurl_print `\n` ) } }

% Resource Res {}

: Node { Res r ? ( Rc Node ) next }

: Plain { i id }

% Drop Plain { @ drop Plain p → v { ( nurl_print `plain dropped ` ) ( nurl_print_int . p id ) ( nurl_print `\n` ) } }

: PNode { Plain p ? ( Rc PNode ) next }

@ resource_pair → v {
    : ( Rc Node ) a ( rc_new [Node] @ Node { @ Res { 1 } @ ?( Rc Node ) { F } } )
    : ( Rc Node ) b ( rc_new [Node] @ Node { @ Res { 2 } @ ?( Rc Node ) { T ( rc_clone [Node] a ) } } )
    ( rc_set [Node] a @ Node { @ Res { 3 } @ ?( Rc Node ) { T ( rc_clone [Node] b ) } } )
}

@ plain_pair → v {
    : ( Rc PNode ) a ( rc_new [PNode] @ PNode { @ Plain { 1 } @ ?( Rc PNode ) { F } } )
    : ( Rc PNode ) b ( rc_new [PNode] @ PNode { @ Plain { 2 } @ ?( Rc PNode ) { T ( rc_clone [PNode] a ) } } )
    ( rc_set [PNode] a @ PNode { @ Plain { 3 } @ ?( Rc PNode ) { T ( rc_clone [PNode] b ) } } )
}

@ main → i {
    ( resource_pair )
    ( nurl_print `after resource_pair\n` )
    ( plain_pair )
    ( nurl_print `after plain_pair\n` )
    ^ 0
}
