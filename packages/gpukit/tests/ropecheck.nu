// tests/ropecheck.nu — gkd_rope2d / gkd_rope3d against a host reference
// computing the same rotation in f64 from the same f32 inputs. Positions
// include one negative and one past the tables: those pairs must come
// back untouched. Prints `rope2d|ok <worst>` / `rope3d|ok <worst>` or a
// FAIL line, SKIP without a backend.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `src/devops.nu`

@ vals i n i seed → ( Vec f ) {
    : ~ ( Vec f ) v ( vec_with_cap [f] n )
    : ~ i s seed
    : ~ i k 0
    ~ < k n {
        = s % + * s 1103515245 12345 2147483648
        ( vec_push [f] v - / # f % s 2000 1000.0 1.0 )
        = k + k 1
    }
    ^ v
}

@ up GpuKit kit ( Vec f ) h → GkBuf {
    : GkBuf b ( gk_dbuf_new kit ( vec_len [f] h ) GK_F32 )
    : b _u ( gk_dbuf_upload kit b h )
    ^ b
}

@ upi GpuKit kit ( Vec i ) h → GkBuf {
    : GkBuf b ( gk_dbuf_new kit ( vec_len [i] h ) GK_I64 )
    : b _u ( gk_dbuf_upload_i kit b h )
    ^ b
}

@ down GpuKit kit GkBuf b i n → ( Vec f ) {
    : ~ ( Vec f ) h ( vec_zeroed [f] n )
    : b _d ( gk_dbuf_download kit b h )
    ^ h
}

// f32 rounding of a host value (the kernel computes in float)
@ r32 f x → f { ^ # f # f32 x }

@ worst ( Vec f ) a ( Vec f ) b → f {
    : ~ f w 0.0
    : i n ( vec_len [f] a )
    : ~ i k 0
    ~ < k n { : f d ( float_abs - ( vec_at [f] a k ) ( vec_at [f] b k ) ) ? > d w { = w d } {} = k + k 1 }
    ^ w
}

@ report s name f w → v {
    ( nurl_print name )
    ? < w 0.0001 { ( nurl_print `|ok ` ) } { ( nurl_print `|FAIL worst=` ) }
    : ~ String o ( string_new )
    ( string_push_float o w )
    ( nurl_print ( string_data o ) ) ( nurl_print `\n` )
}

@ check2d GpuKit kit → v {
    : i heads 2 : i n 5 : i dim 8 : i maxpos 4
    : i half / dim 2 : i quarter / half 2
    : ( Vec f ) x0 ( vals * * heads n dim 7 )
    : ( Vec i ) rows ( vec_new [i] ) : ( Vec i ) cols ( vec_new [i] )
    // token 3: a negative row; token 4: a column past the tables
    ( vec_push [i] rows 0 ) ( vec_push [i] rows 1 ) ( vec_push [i] rows 3 ) ( vec_push [i] rows -1 ) ( vec_push [i] rows 2 )
    ( vec_push [i] cols 2 ) ( vec_push [i] cols 0 ) ( vec_push [i] cols 1 ) ( vec_push [i] cols 3 ) ( vec_push [i] cols 9 )
    : ( Vec f ) ct ( vals * maxpos half 11 ) : ( Vec f ) st ( vals * maxpos half 13 )
    : GkBuf x ( up kit x0 )
    ? ( gkd_rope2d kit x ( upi kit rows ) ( upi kit cols ) ( up kit ct ) ( up kit st ) heads n dim ) {} { ( nurl_print `rope2d|FAIL launch\n` ) ^ v }
    : ( Vec f ) got ( down kit x * * heads n dim )
    : ~ ( Vec f ) want ( vec_clone [f] x0 )
    : i tl * maxpos half
    : ~ i h 0
    ~ < h heads {
        : ~ i t 0
        ~ < t n {
            : ~ i axis 0
            ~ < axis 2 {
                : i pos ? == axis 0 ( vec_at [i] rows t ) ( vec_at [i] cols t )
                : i tbl * pos half
                ? & >= pos 0 <= + tbl half tl {
                    : ~ i j 0
                    ~ < j quarter {
                        : i base + + * * h n dim * t dim * axis half
                        : f x1 ( vec_at [f] x0 + base j ) : f x2 ( vec_at [f] x0 + + base j quarter )
                        ( vec_put [f] want + base j ( r32 - * x1 ( vec_at [f] ct + tbl j ) * x2 ( vec_at [f] st + tbl j ) ) )
                        ( vec_put [f] want + + base j quarter ( r32 + * x2 ( vec_at [f] ct + + tbl j quarter ) * x1 ( vec_at [f] st + + tbl j quarter ) ) )
                        = j + j 1
                    }
                } {}
                = axis + axis 1
            }
            = t + t 1
        }
        = h + h 1
    }
    ( report `rope2d` ( worst got want ) )
}

@ check3d GpuKit kit → v {
    : i heads 2 : i n 4 : i dim 12 : i na 2 : i nb 2 : i maxpos 3
    : i width / dim 2
    : ( Vec f ) x0 ( vals * * heads n dim 17 )
    : ( Vec i ) fr ( vec_new [i] ) : ( Vec i ) rw ( vec_new [i] ) : ( Vec i ) cl ( vec_new [i] )
    ( vec_push [i] fr 0 ) ( vec_push [i] fr 2 ) ( vec_push [i] fr 1 ) ( vec_push [i] fr -2 )
    ( vec_push [i] rw 1 ) ( vec_push [i] rw 0 ) ( vec_push [i] rw 7 ) ( vec_push [i] rw 2 )
    ( vec_push [i] cl 2 ) ( vec_push [i] cl 1 ) ( vec_push [i] cl 0 ) ( vec_push [i] cl 1 )
    : ( Vec f ) ct ( vals * maxpos width 19 ) : ( Vec f ) st ( vals * maxpos width 23 )
    : GkBuf x ( up kit x0 )
    ? ( gkd_rope3d kit x ( upi kit fr ) ( upi kit rw ) ( upi kit cl ) ( up kit ct ) ( up kit st ) heads n dim na nb ) {} { ( nurl_print `rope3d|FAIL launch\n` ) ^ v }
    : ( Vec f ) got ( down kit x * * heads n dim )
    : ~ ( Vec f ) want ( vec_clone [f] x0 )
    : i tl * maxpos width
    : ~ i h 0
    ~ < h heads {
        : ~ i t 0
        ~ < t n {
            : ~ i j 0
            ~ < j width {
                : i pos ? < j na ( vec_at [i] fr t ) ? < j + na nb ( vec_at [i] rw t ) ( vec_at [i] cl t )
                : i tbl + * pos width j
                ? & >= pos 0 < tbl tl {
                    : i base + + * * h n dim * t dim * 2 j
                    : f c ( vec_at [f] ct tbl ) : f s ( vec_at [f] st tbl )
                    : f x1 ( vec_at [f] x0 base ) : f x2 ( vec_at [f] x0 + base 1 )
                    ( vec_put [f] want base ( r32 - * x1 c * x2 s ) )
                    ( vec_put [f] want + base 1 ( r32 + * x1 s * x2 c ) )
                } {}
                = j + j 1
            }
            = t + t 1
        }
        = h + h 1
    }
    ( report `rope3d` ( worst got want ) )
}

@ main → i {
    : GpuKit kit ( gk_open 0 )
    ? ( gk_ok kit ) {} { ( nurl_print `SKIP no device\n` ) ^ 0 }
    ( check2d kit )
    ( check3d kit )
    ^ 0
}
