// OPEN in v0.78.0 — an `inout` argument whose binding does not own its value, handed to a callee that gives that parameter a new value (agora #135). `cur` is a cursor over `root` (`: ~` of a binding: a borrow, root stays the owner); `reset` assigns its `inout` parameter, which releases the old value — root's buffer — and stores the new one in cur's slot. root then reads freed memory, and drops it again. The rule refusing this shape (h295, resolve_replaces) covers only a `: ~` copy of a parameter; a cursor, a field read (`: ~ H h . o h`) and a lend (`: ~ H h ( arc_get [H] a )`) pass, with a field replaced as with the whole value.
// ASan: heap-use-after-free in vec_len.
$ `stdlib/core/vec.nu`

@ reset inout ( Vec i ) v → v { = v ( vec_new [i] ) }

@ main → i {
    : ( Vec i ) root ( vec_new [i] )
    ( vec_push [i] root 5 )
    : ~ ( Vec i ) cur root
    ( reset cur )
    ^ ( vec_len [i] root )
}
