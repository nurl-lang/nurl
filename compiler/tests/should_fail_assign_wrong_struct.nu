// Reassigning a MUTABLE binding to a value of a different named struct must
// be a compile error (immutable targets already error; this is the
// type-agreement gap on mutable reassignment).
: A { i x }
: B { i y }

@ main → i {
    : ~ A a @ A { 1 }
    : B b @ B { 2 }
    = a b
    ^ . a x
}
