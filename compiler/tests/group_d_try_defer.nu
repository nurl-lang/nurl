// group_d_try_defer.nu — try_expr fail path routes through defer chain
//
// Expected output:
//   cleanup
//   false

@ maybe_val i flag → ? i {
  ? == flag 0
    { ^ @ ? i { F 0 } }
    { ^ @ ? i { T 99 } }
}

// This function has a defer AND uses try_expr.
// When try_expr fails (None path), it must run the defer before returning.
@ try_with_defer i flag → ? i {
  ; { ( nurl_print_str `cleanup` ) }  // defer: should print even on None path
  : r ( maybe_val flag )
  : n \ r                              // if flag==0: None path → defer runs → return None
  ^ @ ? i { T n }
}

@ main → v {
  : result ( try_with_defer 0 )        // flag=0 → None path through defer
  ( nurl_print_bool . result 0 )       // false (None)
}
