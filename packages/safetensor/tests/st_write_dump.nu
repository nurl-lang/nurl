// st_write_dump.nu — writes a fixed multi-dtype safetensors file to
// /tmp/nurl_st_write_oracle.safetensors for st_write_oracle.sh, which reads
// it back with the reference `safetensors` Python library. Values are all
// exactly representable in f16/f32/f64 so the cross-check is exact.

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `src/safetensor.nu`
$ `src/write.nu`

@ shp2 i a i b → ( Vec i ) {
    : ( Vec i ) s ( vec_new [i] )
    ( vec_push [i] s a ) ( vec_push [i] s b )
    ^ s
}

@ main → i {
    : *StWriter w ( stw_new )
    // F32 [2,3] = [[0,0.5,1],[1.5,2,2.5]]
    : ( Vec f ) a ( vec_new [f] )
    : ~ i k 0
    ~ < k 6 { ( vec_push [f] a * 0.5 # f k ) = k + k 1 }
    ( stw_add_f32 w `a` ( shp2 2 3 ) a )
    // F64 [4]
    : ( Vec f ) b ( vec_new [f] )
    ( vec_push [f] b 0.5 ) ( vec_push [f] b -0.25 ) ( vec_push [f] b 128.0 ) ( vec_push [f] b 0.0 )
    : ( Vec i ) sb ( vec_new [i] )
    ( vec_push [i] sb 4 )
    ( stw_add_f64 w `b` sb b )
    // F16 [3]
    : ( Vec f ) c ( vec_new [f] )
    ( vec_push [f] c 1.0 ) ( vec_push [f] c 0.5 ) ( vec_push [f] c -2.0 )
    : ( Vec i ) sc ( vec_new [i] )
    ( vec_push [i] sc 3 )
    ( stw_add_f16 w `c` sc c )
    // I64 [2,2]
    : ( Vec i ) iv ( vec_new [i] )
    ( vec_push [i] iv 7 ) ( vec_push [i] iv -3 ) ( vec_push [i] iv 1000000 ) ( vec_push [i] iv 0 )
    ( stw_add_i64 w `d` ( shp2 2 2 ) iv )
    ?? ( stw_write w `/tmp/nurl_st_write_oracle.safetensors` ) {
        T _ → { ( nurl_print `wrote ok\n` ) }
        F e → { ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) ^ 1 }
    }
    ( stw_free w )
    ( vec_free [f] a ) ( vec_free [f] b ) ( vec_free [f] c ) ( vec_free [i] iv )
    ^ 0
}
