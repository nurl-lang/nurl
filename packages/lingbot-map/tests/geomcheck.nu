// geomcheck.nu — dump the camera-geometry results for a fixed set of pose
// encodings, in the format tests/geom_oracle.py emits from the reference
// torch implementation. A byte diff of the two is the test.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `src/geom.nu`

: i IMG_H 378
: i IMG_W 518

@ pr_f f x → v { ( nurl_print ` ` ) ( nurl_print ( nurl_str_float x ) ) }

@ dump_row s label ( Slice f ) v i n → v {
    ( nurl_print label )
    : ~ i j 0
    ~ < j n { ( pr_f ( slice_at [f] v j ) ) = j + j 1 }
    ( nurl_print `\n` )
}

// Deterministic pseudo-random pose encodings — the same generator runs in
// the python oracle, so both sides see identical inputs without a fixture
// file. A 64-bit LCG, values in [-1, 1).
@ lcg ( Slice i ) state → f {
    : i s + * ( slice_at [i] state 0 ) 6364136223846793005 1442695040888963407
    ( slice_put [i] state 0 s )
    : i top & / s 2048 4294967295
    ^ - / # f top 2147483648.0 1.0
}

@ main → i {
    : ( Vec i ) st__v ( vec_zeroed [i] 1 )
    : ( Slice i ) st ( slice_from_vec [i] st__v )
    ( slice_put [i] st 0 20260725 )
    : ( Vec f ) pe__v ( vec_zeroed [f] 16 )
    : ( Slice f ) pe ( slice_from_vec [f] pe__v )
    : ( Vec f ) m__v ( vec_zeroed [f] 16 )
    : ( Slice f ) m ( slice_from_vec [f] m__v )
    : ( Vec f ) q__v ( vec_zeroed [f] 8 )
    : ( Slice f ) q ( slice_from_vec [f] q__v )
    : ( Vec f ) ext__v ( vec_zeroed [f] 16 )
    : ( Slice f ) ext ( slice_from_vec [f] ext__v )
    : ( Vec f ) kk__v ( vec_zeroed [f] 16 )
    : ( Slice f ) kk ( slice_from_vec [f] kk__v )
    : ( Vec f ) ki__v ( vec_zeroed [f] 16 )
    : ( Slice f ) ki ( slice_from_vec [f] ki__v )
    : ( Vec f ) c2w__v ( vec_zeroed [f] 16 )
    : ( Slice f ) c2w ( slice_from_vec [f] c2w__v )
    : ( Vec f ) pt__v ( vec_zeroed [f] 8 )
    : ( Slice f ) pt ( slice_from_vec [f] pt__v )
    : ~ i case 0
    ~ < case 6 {
        ( nurl_print `case ` ) ( nurl_print ( nurl_str_int case ) ) ( nurl_print `\n` )
        // T in [-1,1), quaternion in [-1,1) (deliberately NOT normalised —
        // the model's output never is), fov in a plausible range
        : ~ i j 0
        ~ < j 7 { ( slice_put [f] pe j ( lcg st ) ) = j + j 1 }
        ( slice_put [f] pe 7 + 0.8 * 0.3 ( lcg st ) )
        ( slice_put [f] pe 8 + 1.1 * 0.3 ( lcg st ) )
        ( dump_row `pe` pe 9 )
        ( quat_to_mat ( slice_at [f] pe 3 ) ( slice_at [f] pe 4 ) ( slice_at [f] pe 5 ) ( slice_at [f] pe 6 ) m )
        ( dump_row `R` m 9 )
        ( mat_to_quat m q )
        ( dump_row `q` q 4 )
        ( pose_enc_to_extri pe ext )
        ( dump_row `extri` ext 12 )
        ( pose_enc_to_intri pe IMG_H IMG_W kk )
        ( dump_row `intri` kk 9 )
        ( intri_inverse kk ki )
        ( dump_row `intri_inv` ki 9 )
        ( pose_enc_to_c2w pe c2w )
        ( dump_row `c2w` c2w 16 )
        // a few pixels unprojected at varying depth
        : ~ i p 0
        ~ < p 4 {
            : f px * 137.0 # f p
            : f py * 91.0 # f p
            : f d + 0.5 * 2.0 # f p
            ( unproject px py d ki c2w pt )
            ( nurl_print `xyz` ) ( nurl_print ( nurl_str_int p ) )
            ( pr_f ( slice_at [f] pt 0 ) ) ( pr_f ( slice_at [f] pt 1 ) ) ( pr_f ( slice_at [f] pt 2 ) )
            ( nurl_print `\n` )
            = p + p 1
        }
        = case + case 1
    }
    ^ 0
}
