// Options made in a loop, matched each round, the loop left on None.
@ next i k → ?i { ? > k 3 { ^ @ ?i { F } } {} ^ @ ?i { T + k 1 } }

@ main → i {
    : ~ i k 0
    : ~ i acc 0
    ~ T {
        : ?i o ( next k )
        ?? o { T x → { = k x = acc + acc x } F → { break } }
    }
    ^ acc
}
