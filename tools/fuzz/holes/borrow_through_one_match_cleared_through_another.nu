// map: §2.10 | A2 | rejected | - | AGORA-557: a borrow through one `??` not ended by a change of that payload field in a later `??`
// AGORA-557 (this shape, closed): refused - a `??` join of payload projections borrows the matched binding, and a change through another match's payload sweeps it (main 54e5c459: accepted)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { ( Vec String ) a }
: | Ev { A S B S }

@ main → i {
    : ( Vec String ) va ( vec_new [String] )
    ( vec_push [String] va ( string_from `a heap string long enough for the heap, surely` ) )
    : Ev ev @ Ev { A @ S { va } }
    : ( Vec String ) k ?? ev { A p → . p a B q → . q a }
    : String e ( vec_at [String] k 0 )
    ?? ev { A p → { ( vec_clear [String] . p a ) } B q → {} }
    ( nurl_println ( string_data e ) )
    ^ 0
}
