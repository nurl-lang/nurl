// handle_field_read_after_its_viewer_was_consumed: a binding read out of a library handle field (`: PNCounter x . h c`) handed to a `sink` takes the field over, emptying it where it lives — and the field was read after (`. h c`): an emptied handle field holds no handle, so the counter's operations ran on a null block.
// Closed: a field viewer of a library handle (a String or a Vec left empty is still one) takes the struct with it: reading the struct after is rejected, as a moved value, until it is given a fresh value.
// v0.78.0: accepted; segfault.
// map: §7.6 | A2 | rejected | h348 | a binding read out of a library handle field, handed to a sink, emptied the field (a null handle) and the struct was read after: the viewer takes its struct along
$ `stdlib/dist/crdt.nu`

: Holder { PNCounter c }

@ eat sink PNCounter x → v { ( pncounter_inc x 1 1 ) }

@ main → i {
    : Holder h @ Holder { ( pncounter_new ) }
    : PNCounter x . h c
    ( eat x )
    ( pncounter_inc . h c 2 1 )
    ^ % ( pncounter_value . h c ) 256
}
