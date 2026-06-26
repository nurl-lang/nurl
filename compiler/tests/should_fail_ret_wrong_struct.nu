// Returning a value of the wrong named struct by value (the return dual of
// the call-site check) must be a compile error, not invalid IR clang
// rejects late.
: A { i x i y }
: B { i p i q i r }

@ f → A { : B b @ B { 1 2 3 } ^ b }

@ main → i { ^ . ( f ) x }
