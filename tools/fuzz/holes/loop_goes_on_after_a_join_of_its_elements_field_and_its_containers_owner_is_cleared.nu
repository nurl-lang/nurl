// loop_goes_on_after_a_join_of_its_elements_field_and_its_containers_owner_is_cleared: agora #482 — `~ x cc` over `cc = ( vec_at o 0 )`: `c = ? own xb ob`, a join of a cursor over `. x f` and one over `o`, cleared; the loop goes on
// Closed: a join may be either arm, so a change through it ends the element as a change through the container's owner does (agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: a loop goes on after a join of its element's field and its container's owner is cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: E { ( Vec ( Vec E ) ) f String name }

@ pick i n → b { ^ > n 0 }

@ main → i {
    : ( Vec ( Vec E ) ) o ( vec_new [( Vec E )] )
    : ~ ( Vec E ) c0 ( vec_new [E] )
    ( vec_push [E] c0 @ E { ( vec_new [( Vec E )] ) ( string_from `an element name long enough for a heap buffer` ) } )
    ( vec_push [E] c0 @ E { ( vec_new [( Vec E )] ) ( string_from `a second element name long enough for a heap buffer` ) } )
    ( vec_push [E] c0 @ E { ( vec_new [( Vec E )] ) ( string_from `a third element name long enough for a heap buffer` ) } )
    ( vec_push [( Vec E )] o c0 )
    : ( Vec E ) cc ( vec_at [( Vec E )] o 0 )
    : b own ( pick 0 )
    ~ x cc {
        ( nurl_println ( string_data . x name ) )
        : ~ ( Vec ( Vec E ) ) xb . x f
        : ~ ( Vec ( Vec E ) ) ob o
        : ~ ( Vec ( Vec E ) ) c ? own xb ob
        ( vec_clear [( Vec E )] c )
    }
    ^ 0
}
