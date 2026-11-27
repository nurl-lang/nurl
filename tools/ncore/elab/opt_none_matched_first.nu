// An option matched with its None arm first.
@ half i k → ?i { ? == k 0 { ^ @ ?i { F } } {} ^ @ ?i { T k } }

@ main → i {
    : ?i o ( half 4 )
    ?? o { F → { ^ 0 } T x → { ^ + x 1 } }
}
