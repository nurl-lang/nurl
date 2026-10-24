// A `??` arm whose value is a call's fresh handle made from the arm's
// payload — `T a → ( keep a )`, keep handing back an arc_clone — drops the
// payload at the arm's exit: the result is a second owner, not the
// payload. A callee that hands the payload itself back (`lend`) keeps it
// alive through the join, and one that consumes it takes it along.
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`

: E { i code }
: P { i x }
: H { ( Arc P ) a }

@ mk → !( Arc P ) E { ^ @ !( Arc P ) E { T ( arc_new [P] @ P { 5 } ) } }

@ keep ( Arc P ) a → ( Arc P ) { ^ ( arc_clone [P] a ) }

@ wrap ( Arc P ) a → H { ^ @ H { ( arc_clone [P] a ) } }

@ take sink ( Arc P ) a → ( Arc P ) { ^ a }

@ via_keep → ( Arc P ) { ^ ?? ( mk ) { T a → ( keep a ) F _ → ( arc_new [P] @ P { 0 } ) } }

@ via_wrap → H { ^ ?? ( mk ) { T a → ( wrap a ) F _ → @ H { ( arc_new [P] @ P { 0 } ) } } }

@ via_block → ( Arc P ) { ^ ?? ( mk ) { T a → { : i n . ( arc_get [P] a ) x ( keep a ) } F _ → ( arc_new [P] @ P { 0 } ) } }

@ via_take → ( Arc P ) { ^ ?? ( mk ) { T a → ( take a ) F _ → ( arc_new [P] @ P { 0 } ) } }

@ main → i {
    : ( Arc P ) k ( via_keep )
    ( nurl_print `keep  strong ` ) ( nurl_println_int ( arc_strong [P] k ) )
    : H w ( via_wrap )
    ( nurl_print `wrap  strong ` ) ( nurl_println_int ( arc_strong [P] . w a ) )
    : ( Arc P ) b ( via_block )
    ( nurl_print `block strong ` ) ( nurl_println_int ( arc_strong [P] b ) )
    : ( Arc P ) t ( via_take )
    ( nurl_print `take  strong ` ) ( nurl_println_int ( arc_strong [P] t ) )
    ^ 0
}
