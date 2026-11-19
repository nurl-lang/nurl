// literal_nesting_an_owner_beside_a_view_of_it_pushed_then_popped_and_grown: AGORA-926 — `( vec_push [O] vs @ O { @ I { b } sv } )`, then `vec_pop`, `vec_reserve . t buf` and a read of `. t v`: the owner sits in a nested literal (github#2086's review)
// AGORA-926 (closed): refused (main 58ab3032: accepted)
// map: §2.10 | A2 | rejected | - | AGORA-926: a literal nesting an owner beside a view of it handed to a keeping callee
$ `stdlib/core/slice.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/bytes.nu`

: I { ( Vec u ) buf }
: O { I in ( Slice u ) v }

@ main → i {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push_word_u8 b 9 1 F )
    : ( Slice u ) sv ( slice_from_vec [u] b )
    : ( Vec O ) vs ( vec_new [O] )
    ( vec_push [O] vs @ O { @ I { b } sv } )
    ?? ( vec_pop [O] vs ) {
        T s → { : ~ O t s ( vec_reserve [u] . . t in buf 4096 ) ( nurl_println_int # i ( slice_at [u] . t v 0 ) ) }
        F _ → {}
    }
    ^ 0
}
