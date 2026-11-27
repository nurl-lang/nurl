// A closure with no captures that takes a struct and reads both its fields.
: P { i x i y }

@ main → i {
    : ( @ i P ) sum \ P p → i { ^ + . p x . p y }
    : P q @ P { 3 4 }
    ^ ( sum q )
}
