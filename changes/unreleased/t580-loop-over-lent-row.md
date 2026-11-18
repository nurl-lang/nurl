### Fixed

- **A `~` loop over a row lent out of a Vec of Vecs now ends when that row grows through another borrow of it** (AGORA-580; one AGORA-774 shape). With `: b ( vec_at vv 0 )  : c ( vec_at vv 0 )  ~ x b { ( vec_push c … ) }`, the loop read its next element from a freed buffer. That is refused now. Growing `vv` itself inside the loop, or only reading `c`, is still accepted. A container two lends deep stays open.
