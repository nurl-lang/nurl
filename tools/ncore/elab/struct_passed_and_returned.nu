// A struct made by a function and handed back (owned), then read by another.
: P { i x i y }

@ make i a → P { ^ @ P { a 2 } }

@ total P p → i { ^ + . p x . p y }

@ main → i {
    : P p ( make 1 )
    ^ ( total p )
}
