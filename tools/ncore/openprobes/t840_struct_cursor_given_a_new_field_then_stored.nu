// map: §2.12 | A2 | runs-clean | - | agora #840: `: ~ H c h  = . c items ( vec_new )  @ W { c }` - the store takes c's new field and h keeps its own, the field freed twice
// AGORA-869: runs clean under ASan/LSan with the default compile (main 3358873a: faulted); the ticket's other shapes stay open.
$ `stdlib/core/vec.nu`

: H { ( Vec i ) items i n }
: W { H h i m }

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    : ~ i k 0
    ~ < k 64 { ( vec_push [i] xs k ) = k + k 1 }
    : ~ H h @ H { xs 0 }
    : ~ H c h
    = . c items ( vec_new [i] )
    : W w @ W { c 0 }
    ( nurl_println_int ( vec_len [i] . . w h items ) )
    ^ 0
}
