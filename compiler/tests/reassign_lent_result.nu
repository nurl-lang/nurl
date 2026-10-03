// reassign_lent_result.nu — a call result assigned over an owned binding
// (`= x ( at p 0 )`) is the binding's only when the call says so.
//
// `at` lends a table element on one path and makes a fresh String on the
// other: it answers per call. Bound (`: String y ( at p 0 )`) that answer
// was honoured; assigned over a binding that held an owned value, the
// binding kept its old "owned" flag and dropped the table's element at its
// exit — freed under the table (packages/yoloe-demo: every second /detect
// crashed in onnx rt_reset). A call that may hand back the binding's own
// value (`= c ( bump c )`) keeps its gated form.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/rcbox.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: TbImpl { ( Vec String ) vals }

@ at * TbImpl t i k → String {
    ?? ( vec_get [String] . t vals k ) { T s → ^ s F _ → ^ ( string_new ) }
}

@ bound * TbImpl p → i {
    : String y ( at p 0 )
    ^ ( string_len y )
}

@ assigned * TbImpl p → i {
    : ~ String x ( string_new )
    = x ( at p 0 )
    ^ ( string_len x )
}

@ main → i {
    : i box ( rcbox_new [TbImpl] @ TbImpl { ( vec_new [String] ) } )
    : *TbImpl p ( rcbox_ptr [TbImpl] box )
    ( vec_push [String] . p vals ( string_from `hello` ) )
    : i l0 ( live )
    : ~ i acc 0
    : ~ i k 0
    ~ < k 3 { = acc + acc ( bound p ) = k + k 1 }
    ( nurl_print `bound ok ` ) ( nurl_print ( nurl_str_int acc ) ) ( nurl_print `\n` )
    = k 0
    ~ < k 3 { = acc + acc ( assigned p ) = k + k 1 }
    ( nurl_print `assigned ` ) ( nurl_print ( nurl_str_int acc ) ) ( nurl_print `\n` )
    ( nurl_print `live: ` ) ( nurl_print ( nurl_str_int - ( live ) l0 ) ) ( nurl_print `\n` )
    ( rcbox_release [TbImpl] box )
    ^ 0
}
