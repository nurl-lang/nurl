### Fixed

- **A slice join's fresh arm is released wherever the join goes** (AGORA-903). A `?` join of slices whose arm is a fresh slice a call made leaked that slice on the runs the arm was taken. This happened when the arm was a block (`? c { ( mk ) } a`), when the join was handed back (`^ ? c ( mk ) a`), and when it was a struct literal's field (`@ P { ? c ( mk ) a 3 }`). The fresh slice now goes to whoever takes the join. A lent arm stays its owner's, and one lending a local of the function is copied, as before.
