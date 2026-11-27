// An option of a literal number, given another value.
@ main → i {
    : ~ ? i o @ ?i { T 5 }
    = o @ ?i { F }
    ?? o { T x → { ^ x } F → { ^ 1 } }
}
