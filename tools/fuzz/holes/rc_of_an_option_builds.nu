// rc_of_an_option_builds: agora #463 — `( rc_new [?String] @ ?String { T … } )`
// Closed: an Rc's drop table asks for its value's drop graph when it is requested, walked with every other at module end (an option's drop was undefined) (agora #463).
// main: failed to build (use of an undefined value in the IR) (base 8a2afbc3).
// map: §7.5 | A2 | runs-clean | - | agora #463: `( rc_new [?String] @ ?String { T … } )`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

@ main → i {
    : ( Rc ? String ) r ( rc_new [? String] @ ?String { T ( string_from `an rc option long enough for the heap` ) } )
    : ( Rc ? String ) q ( mem_dup r )
    ?? ( rc_get [? String] q ) { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
