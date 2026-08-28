// Negative control for return escape through an aggregate field
// (§2.8). Two legal shapes that must COMPILE, LINK and RUN clean:
//
//   1. an ordinary CONSTRUCTOR `@ mk … → Point { @ Point { a b } }` —
//      embedding non-reference (int) parameters in a returned struct is
//      the bread-and-butter pattern and must never be flagged;
//   2. `( wrap f )` — wrap embeds the stack-reference closure `f` in a
//      Slot, but the Slot is consumed WITHIN the frame (the closure is
//      extracted and invoked), never escaping, so it is fine.
: Counter { i n i max }
: Slot { ( @ v ) cb }
: Point { i x i y }

@ wrap ( @ v ) cb → Slot {
    ^ @ Slot { cb }
}

@ mk i a i b → Point {
    ^ @ Point { a b }
}

@ use_inscope → i {
    : ~ Counter c @ Counter { 0 7 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    : Slot s ( wrap f )
    : ( @ v ) g . s cb
    ( g )
    ( g )
    ^ . c n
}

@ main → i {
    : Point p ( mk 3 4 )
    ( nurl_println_int + ( use_inscope ) . p x )
    ^ 0
}
