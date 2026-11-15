// map: §2.10 | A2 | rejected | - | agora #557: a borrow through `?? ev { A p → { . p a } … }` not ended by a clear of `. p a` in a later `??`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { ( Vec String ) a }
: | Ev { A S B S }

@ main → i {
    : ( Vec String ) va ( vec_new [String] )
    ( vec_push [String] va ( string_from `a heap string long enough to own a buffer on the heap, surely` ) )
    : Ev ev @ Ev { A @ S { va } }
    : ( Vec String ) k ?? ev { A p → { . p a } B q → { . q a } }
    : String e ( vec_at [String] k 0 )
    ?? ev { A p → { ( vec_clear [String] . p a ) } B q → {} }
    ( nurl_println ( string_data e ) )
    ^ 0
}
