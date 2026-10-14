// closure_join_assign_arms.nu — a `?` / `??` whose arms end in assigning a
// closure binding (`= base ( wrap base )`) yields that binding's closure.
// A join nothing takes (a statement) owns nothing: an arm's own temporary
// (a call's result) is dropped in the arm. A join whose value is taken
// gets an owned copy from every arm (h259).

$ `stdlib/core/io.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

: Srv { ( @ i i ) h }

@ srv_new ( @ i i ) h → Srv { ^ @ Srv { h } }

@ wrap ( @ i i ) inner → ( @ i i ) {
    ^ \ i x → i { ^ + ( inner x ) 1 }
}

@ mk i k → ( @ i i ) { ^ \ i x → i { ^ + x k } }

@ run i k → i {
    : ~ ( @ i i ) base \ i x → i { ^ + x k }
    : Srv s ( srv_new base )
    ?? @ ?i { T 4 } { T t → { = base ( wrap base ) } F → {} }
    ? > k 0 { = base ( wrap base ) } { = base ( wrap base ) }
    // statement joins of call results: dropped in their arms
    ? > k 0 { ( mk k ) } { ( mk 1 ) }
    ?? @ ?i { T 1 } { T _ → { ( mk k ) } F → { ( mk 2 ) } }
    // a value-position join with an assigning arm: its own copy
    : ( @ i i ) g ? > k 0 { = base ( wrap base ) } { ( mk 3 ) }
    : ( @ i i ) h1 . s h
    ^ + + ( base 1 ) ( h1 1 ) ( g 1 )
}

unsafe @ main → i {
    ( nurl_println_int ( run 5 ) )
    : i before - ( nurl_alloc_count ) ( nurl_free_count )
    : ~ i n 0
    ~ < n 20 { : i r ( run n ) = n + n 1 }
    : i after - ( nurl_alloc_count ) ( nurl_free_count )
    ( nurl_print `live delta over 20 calls: ` ) ( nurl_print_int - after before ) ( nurl_print `\n` )
    ^ 0
}
