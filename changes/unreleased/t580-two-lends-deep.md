### Fixed

- **A `~` loop over a container two lends deep ends when that container grows** (AGORA-580, now closed). With `: a ( vec_at vvv 0 )  : b ( vec_at a 0 )  ~ x b { ( vec_push ( vec_at a 0 ) … ) }`, the loop read its next element from a freed buffer, and the same happened through a second `( vec_at vvv 0 )`. Both are refused now. Growing `a` itself, or `vvv`, inside the loop moves only row handles and is accepted; growing `a` was refused before.
