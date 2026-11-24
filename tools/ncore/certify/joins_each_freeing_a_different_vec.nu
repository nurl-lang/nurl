$ `stdlib/core/vec.nu`

// 22 conditionals, each freeing a different Vec on one arm: each `if` joins
// its arms. A join is materialized over the domain (C.joinTbl), so this
// certifies in about a second; with each join a closure over both arms',
// lookups grew as 2ⁿ (n = 12 took 144 s; github#2242's review).
@ main → i {
    : ~ i k 0
    : ~ ( Vec i ) v0 ( vec_new [i] )
    : ~ ( Vec i ) v1 ( vec_new [i] )
    : ~ ( Vec i ) v2 ( vec_new [i] )
    : ~ ( Vec i ) v3 ( vec_new [i] )
    : ~ ( Vec i ) v4 ( vec_new [i] )
    : ~ ( Vec i ) v5 ( vec_new [i] )
    : ~ ( Vec i ) v6 ( vec_new [i] )
    : ~ ( Vec i ) v7 ( vec_new [i] )
    : ~ ( Vec i ) v8 ( vec_new [i] )
    : ~ ( Vec i ) v9 ( vec_new [i] )
    : ~ ( Vec i ) v10 ( vec_new [i] )
    : ~ ( Vec i ) v11 ( vec_new [i] )
    : ~ ( Vec i ) v12 ( vec_new [i] )
    : ~ ( Vec i ) v13 ( vec_new [i] )
    : ~ ( Vec i ) v14 ( vec_new [i] )
    : ~ ( Vec i ) v15 ( vec_new [i] )
    : ~ ( Vec i ) v16 ( vec_new [i] )
    : ~ ( Vec i ) v17 ( vec_new [i] )
    : ~ ( Vec i ) v18 ( vec_new [i] )
    : ~ ( Vec i ) v19 ( vec_new [i] )
    : ~ ( Vec i ) v20 ( vec_new [i] )
    : ~ ( Vec i ) v21 ( vec_new [i] )
    ? > k 0 { ( vec_free [i] v0 ) } {}
    ? > k 1 { ( vec_free [i] v1 ) } {}
    ? > k 2 { ( vec_free [i] v2 ) } {}
    ? > k 3 { ( vec_free [i] v3 ) } {}
    ? > k 4 { ( vec_free [i] v4 ) } {}
    ? > k 5 { ( vec_free [i] v5 ) } {}
    ? > k 6 { ( vec_free [i] v6 ) } {}
    ? > k 7 { ( vec_free [i] v7 ) } {}
    ? > k 8 { ( vec_free [i] v8 ) } {}
    ? > k 9 { ( vec_free [i] v9 ) } {}
    ? > k 10 { ( vec_free [i] v10 ) } {}
    ? > k 11 { ( vec_free [i] v11 ) } {}
    ? > k 12 { ( vec_free [i] v12 ) } {}
    ? > k 13 { ( vec_free [i] v13 ) } {}
    ? > k 14 { ( vec_free [i] v14 ) } {}
    ? > k 15 { ( vec_free [i] v15 ) } {}
    ? > k 16 { ( vec_free [i] v16 ) } {}
    ? > k 17 { ( vec_free [i] v17 ) } {}
    ? > k 18 { ( vec_free [i] v18 ) } {}
    ? > k 19 { ( vec_free [i] v19 ) } {}
    ? > k 20 { ( vec_free [i] v20 ) } {}
    ? > k 21 { ( vec_free [i] v21 ) } {}
    ^ k
}
