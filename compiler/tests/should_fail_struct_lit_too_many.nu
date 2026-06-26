// More field values than the struct has fields — the surplus would
// insertvalue into a non-existent slot (invalid IR). Compile error.
: A { i x }

@ main → i { : A a @ A { 1 2 } ^ . a x }
