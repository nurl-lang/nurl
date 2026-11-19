// map: §2.10 | A2 | rejected | - | AGORA-557: a borrow through `?? ev { A p → ? == c 1 . p a . p b … }` not ended by a clear of `. p a` in a later `??`
// AGORA-557 (this shape, closed): refused (main: accepted, heap-use-after-free)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { ( Vec String ) a ( Vec String ) b }
: | Ev { A S B S }

@ run i c → i {
    : ( Vec String ) va ( vec_new [String] )
    ( vec_push [String] va ( string_from `a heap string long enough to own a buffer on the heap, surely` ) )
    : ( Vec String ) vb ( vec_new [String] )
    ( vec_push [String] vb ( string_from `a heap string long enough to own a buffer on the heap, surely` ) )
    : Ev ev @ Ev { A @ S { va vb } }
    : ( Vec String ) k ?? ev { A p → ? == c 1 . p a . p b B q → . q a }
    : String e ( vec_at [String] k 0 )
    ?? ev { A p → { ( vec_clear [String] . p a ) } B q → {} }
    ( nurl_println ( string_data e ) )
    ^ 0
}

@ main → i { ^ ( run 1 ) }
