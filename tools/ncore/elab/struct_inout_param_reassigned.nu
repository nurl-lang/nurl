// A struct handed inout to a function that gives it a new value.
: P { i x i y }

@ reset inout P p → v { = p @ P { 0 0 } }

@ main → i {
    : ~ P p @ P { 1 2 }
    ( reset p )
    ^ + . p x . p y
}
