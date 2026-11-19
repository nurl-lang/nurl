// literal_of_an_owner_and_a_view_of_it_pushed_then_popped_and_grown: AGORA-926 — `( vec_push [S] vs @ S { sv b } )`, then `vec_pop`, `vec_reserve . t buf` and a read of `. t v`: the literal views its own field
// AGORA-926 (closed): refused (main 58ab3032: accepted, heap-use-after-free; claude-solver's adv294/h03)
// map: §2.10 | A2 | rejected | - | AGORA-926: a literal of an owner and a view of it handed to a keeping callee
$ `stdlib/core/slice.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/bytes.nu`

: S { ( Slice u ) v ( Vec u ) buf }

@ main → i {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push_word_u8 b 9 1 F )
    : ( Slice u ) sv ( slice_from_vec [u] b )
    : ( Vec S ) vs ( vec_new [S] )
    ( vec_push [S] vs @ S { sv b } )
    ?? ( vec_pop [S] vs ) {
        T s → { : ~ S t s ( vec_reserve [u] . t buf 4096 ) ( nurl_println_int # i ( slice_at [u] . t v 0 ) ) }
        F _ → {}
    }
    ^ 0
}
