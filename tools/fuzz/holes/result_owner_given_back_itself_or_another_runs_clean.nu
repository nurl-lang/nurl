// result_owner_given_back_itself_or_another_runs_clean: `= o ( pick o other k )` with o a `!( Vec i ) i` result: keyed by its active side
// main 3358873a: refused by gen_assign's #412 rule when the callee is compiled before the call (and accepted below it); the key test answers each run (AGORA-869).
// map: §7.6 | A2 | runs-clean | - | agora #412: `= o ( pick o other k )` with o a `!( Vec i ) i` result: keyed by its active side
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pick !( Vec i ) i a !( Vec i ) i b i k → !( Vec i ) i { ? == k 1 { ^ a } {} ^ b }

@ show !( Vec i ) i o → v { ?? o { T v → { ( nurl_println_int ( vec_len [i] v ) ) } F e → { ( nurl_println_int e ) } } }

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 7 )
    : ~ !( Vec i ) i o @ !( Vec i ) i { T xs }
    : ( Vec i ) ys ( vec_new [i] )
    ( vec_push [i] ys 1 ) ( vec_push [i] ys 2 )
    : !( Vec i ) i other @ !( Vec i ) i { T ys }
    = o ( pick o other 1 )
    ( show o )
    = o ( pick o other 0 )
    ( show o )
    = o ( pick o other 1 )
    ( show o )
    ( show other )
    ^ 0
}
