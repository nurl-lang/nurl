// image/jpeg.nu — baseline (sequential DCT, Huffman) JPEG decode.
//
// Supports the baseline JPEGs real encoders emit: 8-bit precision, Huffman
// coding, 1 component (greyscale) or 3 (YCbCr → RGB), any 4:4:4 / 4:2:2 /
// 4:2:0 / 4:1:1 subsampling, and restart intervals (DRI/RSTn). Chroma planes
// are box-upsampled and a separable float IDCT is used, so output matches a
// reference decoder (libjpeg) to within IDCT/upsampling rounding — JPEG is
// lossy and the spec permits IDCT variation, so this is not bit-exact.
//
// Not supported (clean None, never an out-of-bounds read): progressive JPEG,
// arithmetic coding, 12-bit, and 4-component (CMYK/YCCK).

$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `core.nu`

: Jpeg {
    ( Vec u ) buf   i len
    i width  i height  i ncomp
    ( Vec i ) cid  ( Vec i ) chf  ( Vec i ) cvf  ( Vec i ) ctq  ( Vec i ) ctd  ( Vec i ) cta  ( Vec i ) cpred
    i hmax  i vmax  i restart
    ( Vec i ) qt
    ( Vec i ) hmin  ( Vec i ) hmaxc  ( Vec i ) hptr  ( Vec i ) hvals
    ( Vec f ) idct_a  ( Vec i ) zz
    i bpos  i bbuf  i bcnt  i marker
    b ok
}

@ __ivec i n i fill → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] n )
    : ~ i k 0
    ~ < k n { ( vec_push [i] v fill ) = k + k 1 }
    ^ v
}

@ __idct_basis → ( Vec f ) {
    : ( Vec f ) a ( vec_with_cap [f] 64 )
    ( vec_push [f] a 0.70710678118654746 ) ( vec_push [f] a 0.70710678118654746 ) ( vec_push [f] a 0.70710678118654746 ) ( vec_push [f] a 0.70710678118654746 ) ( vec_push [f] a 0.70710678118654746 ) ( vec_push [f] a 0.70710678118654746 ) ( vec_push [f] a 0.70710678118654746 ) ( vec_push [f] a 0.70710678118654746 )
    ( vec_push [f] a 0.98078528040323043 ) ( vec_push [f] a 0.83146961230254524 ) ( vec_push [f] a 0.55557023301960229 ) ( vec_push [f] a 0.19509032201612833 ) ( vec_push [f] a -0.19509032201612819 ) ( vec_push [f] a -0.55557023301960196 ) ( vec_push [f] a -0.83146961230254535 ) ( vec_push [f] a -0.98078528040323043 )
    ( vec_push [f] a 0.92387953251128674 ) ( vec_push [f] a 0.38268343236508984 ) ( vec_push [f] a -0.38268343236508973 ) ( vec_push [f] a -0.92387953251128674 ) ( vec_push [f] a -0.92387953251128685 ) ( vec_push [f] a -0.38268343236509034 ) ( vec_push [f] a 0.38268343236509 ) ( vec_push [f] a 0.92387953251128652 )
    ( vec_push [f] a 0.83146961230254524 ) ( vec_push [f] a -0.19509032201612819 ) ( vec_push [f] a -0.98078528040323043 ) ( vec_push [f] a -0.55557023301960218 ) ( vec_push [f] a 0.55557023301960184 ) ( vec_push [f] a 0.98078528040323043 ) ( vec_push [f] a 0.19509032201612878 ) ( vec_push [f] a -0.83146961230254512 )
    ( vec_push [f] a 0.70710678118654757 ) ( vec_push [f] a -0.70710678118654746 ) ( vec_push [f] a -0.70710678118654768 ) ( vec_push [f] a 0.70710678118654735 ) ( vec_push [f] a 0.70710678118654768 ) ( vec_push [f] a -0.70710678118654668 ) ( vec_push [f] a -0.70710678118654713 ) ( vec_push [f] a 0.70710678118654657 )
    ( vec_push [f] a 0.55557023301960229 ) ( vec_push [f] a -0.98078528040323043 ) ( vec_push [f] a 0.1950903220161283 ) ( vec_push [f] a 0.83146961230254546 ) ( vec_push [f] a -0.83146961230254512 ) ( vec_push [f] a -0.19509032201612803 ) ( vec_push [f] a 0.98078528040323065 ) ( vec_push [f] a -0.55557023301960151 )
    ( vec_push [f] a 0.38268343236508984 ) ( vec_push [f] a -0.92387953251128685 ) ( vec_push [f] a 0.92387953251128652 ) ( vec_push [f] a -0.38268343236508989 ) ( vec_push [f] a -0.38268343236509056 ) ( vec_push [f] a 0.92387953251128674 ) ( vec_push [f] a -0.92387953251128641 ) ( vec_push [f] a 0.38268343236508956 )
    ( vec_push [f] a 0.19509032201612833 ) ( vec_push [f] a -0.55557023301960218 ) ( vec_push [f] a 0.83146961230254546 ) ( vec_push [f] a -0.98078528040323065 ) ( vec_push [f] a 0.98078528040323043 ) ( vec_push [f] a -0.83146961230254501 ) ( vec_push [f] a 0.55557023301960151 ) ( vec_push [f] a -0.19509032201612858 )
    ^ a
}
@ __zigzag → ( Vec i ) {
    : ( Vec i ) z ( vec_with_cap [i] 64 )
    ( vec_push [i] z 0 ) ( vec_push [i] z 1 ) ( vec_push [i] z 8 ) ( vec_push [i] z 16 ) ( vec_push [i] z 9 ) ( vec_push [i] z 2 ) ( vec_push [i] z 3 ) ( vec_push [i] z 10 )
    ( vec_push [i] z 17 ) ( vec_push [i] z 24 ) ( vec_push [i] z 32 ) ( vec_push [i] z 25 ) ( vec_push [i] z 18 ) ( vec_push [i] z 11 ) ( vec_push [i] z 4 ) ( vec_push [i] z 5 )
    ( vec_push [i] z 12 ) ( vec_push [i] z 19 ) ( vec_push [i] z 26 ) ( vec_push [i] z 33 ) ( vec_push [i] z 40 ) ( vec_push [i] z 48 ) ( vec_push [i] z 41 ) ( vec_push [i] z 34 )
    ( vec_push [i] z 27 ) ( vec_push [i] z 20 ) ( vec_push [i] z 13 ) ( vec_push [i] z 6 ) ( vec_push [i] z 7 ) ( vec_push [i] z 14 ) ( vec_push [i] z 21 ) ( vec_push [i] z 28 )
    ( vec_push [i] z 35 ) ( vec_push [i] z 42 ) ( vec_push [i] z 49 ) ( vec_push [i] z 56 ) ( vec_push [i] z 57 ) ( vec_push [i] z 50 ) ( vec_push [i] z 43 ) ( vec_push [i] z 36 )
    ( vec_push [i] z 29 ) ( vec_push [i] z 22 ) ( vec_push [i] z 15 ) ( vec_push [i] z 23 ) ( vec_push [i] z 30 ) ( vec_push [i] z 37 ) ( vec_push [i] z 44 ) ( vec_push [i] z 51 )
    ( vec_push [i] z 58 ) ( vec_push [i] z 59 ) ( vec_push [i] z 52 ) ( vec_push [i] z 45 ) ( vec_push [i] z 38 ) ( vec_push [i] z 31 ) ( vec_push [i] z 39 ) ( vec_push [i] z 46 )
    ( vec_push [i] z 53 ) ( vec_push [i] z 60 ) ( vec_push [i] z 61 ) ( vec_push [i] z 54 ) ( vec_push [i] z 47 ) ( vec_push [i] z 55 ) ( vec_push [i] z 62 ) ( vec_push [i] z 63 )
    ^ z
}

@ __jp_new ( Vec u ) buf → *Jpeg {
    : *Jpeg j # *Jpeg ( nurl_malloc Z Jpeg )
    = . j buf buf
    = . j len ( vec_len [u] buf )
    = . j cid ( __ivec 4 0 )
    = . j chf ( __ivec 4 1 )
    = . j cvf ( __ivec 4 1 )
    = . j ctq ( __ivec 4 0 )
    = . j ctd ( __ivec 4 0 )
    = . j cta ( __ivec 4 0 )
    = . j cpred ( __ivec 4 0 )
    = . j qt ( __ivec 256 0 )
    = . j hmin ( __ivec 136 0 )
    = . j hmaxc ( __ivec 136 -1 )
    = . j hptr ( __ivec 136 0 )
    = . j hvals ( __ivec 2048 0 )
    = . j idct_a ( __idct_basis )
    = . j zz ( __zigzag )
    = . j bcnt 0
    = . j marker 0
    = . j restart 0
    = . j ok T
    ^ j
}

@ __jp_free *Jpeg j → v {
    ( vec_free [i] . j cid ) ( vec_free [i] . j chf ) ( vec_free [i] . j cvf )
    ( vec_free [i] . j ctq ) ( vec_free [i] . j ctd ) ( vec_free [i] . j cta )
    ( vec_free [i] . j cpred ) ( vec_free [i] . j qt )
    ( vec_free [i] . j hmin ) ( vec_free [i] . j hmaxc ) ( vec_free [i] . j hptr ) ( vec_free [i] . j hvals )
    ( vec_free [f] . j idct_a ) ( vec_free [i] . j zz )
    ( nurl_free j )
}

// ── 16-bit big-endian at a byte position ──────────────────────────────
@ __u16 ( Vec u ) buf i p → i { ^ + * ( __b buf p ) 256 ( __b buf + p 1 ) }

// ── Entropy bit reader (handles 0xFF00 stuffing; stops at a marker) ────
@ __jp_bit *Jpeg j → i {
    ? > . j bcnt 0 {} {
        : i p . j bpos
        ? >= p . j len { = . j marker 217 ^ 0 } {}
        : i b ( __b . j buf p )
        ? == b 255 {
            : i b2 ( __b . j buf + p 1 )
            ? == b2 0 {
                = . j bpos + p 2
                = . j bbuf 255
            } {
                = . j marker b2
                ^ 0
            }
        } {
            = . j bpos + p 1
            = . j bbuf b
        }
        = . j bcnt 8
    }
    = . j bcnt - . j bcnt 1
    ^ & >> . j bbuf . j bcnt 1
}

@ __jp_receive *Jpeg j i n → i {
    : ~ i v 0
    : ~ i k 0
    ~ < k n { = v | << v 1 ( __jp_bit j ) = k + k 1 }
    ^ v
}
@ __jp_extend i v i n → i {
    ? == n 0 { ^ 0 } {}
    ? < v << 1 - n 1 { ^ - v - << 1 n 1 } { ^ v }
}

// Decode one Huffman symbol from table `t` (0..7 = 4 DC then 4 AC).
@ __jp_huff *Jpeg j i t → i {
    : i base * t 17
    : ~ i code ( __jp_bit j )
    : ~ i len 1
    ~ & <= len 16 > code ( __b_i . j hmaxc + base len ) {
        = code | << code 1 ( __jp_bit j )
        = len + len 1
    }
    ? > len 16 { ^ -1 } {}
    : i idx + ( __b_i . j hptr + base len ) - code ( __b_i . j hmin + base len )
    ^ ( __b_i . j hvals + * t 256 idx )
}

// int-vector read (0 out of range)
@ __b_i ( Vec i ) v i p → i {
    ?? ( vec_get [i] v p ) { T x → { ^ x } F _ → { ^ 0 } }
}

// ── Decode + dequantize one 8×8 block into `blk` (natural order) ──────
@ __jp_block *Jpeg j i comp ( Vec i ) blk → v {
    : ~ i k 0
    ~ < k 64 { ( vec_set [i] blk k 0 ) = k + k 1 }
    : i tq * ( __b_i . j ctq comp ) 64
    : i td ( __b_i . j ctd comp )
    : i ta + 4 ( __b_i . j cta comp )
    : i s ( __jp_huff j td )
    : i diff ? > s 0 { ( __jp_extend ( __jp_receive j s ) s ) } { 0 }
    : i pred + ( __b_i . j cpred comp ) diff
    ( vec_set [i] . j cpred comp pred )
    ( vec_set [i] blk 0 * pred ( __b_i . j qt tq ) )
    : ~ i z 1
    ~ <= z 63 {
        : i rs ( __jp_huff j ta )
        : i r >> rs 4
        : i sz & rs 15
        ? == sz 0 {
            ? == r 15 { = z + z 16 } { = z 64 }
        } {
            = z + z r
            ? <= z 63 {
                : i val ( __jp_extend ( __jp_receive j sz ) sz )
                ( vec_set [i] blk ( __b_i . j zz z ) * val ( __b_i . j qt + tq z ) )
                = z + z 1
            } { = z 64 }
        }
    }
}

// ── Separable float IDCT: blk (natural) → out (8×8 row-major, 0..255) ──
@ __jp_idct *Jpeg j ( Vec i ) blk ( Vec f ) tmp ( Vec i ) out i ox i oy i pw → v {
    : ( Vec f ) A . j idct_a
    // rows: tmp[y*8+x] = 0.5 * Σ_u A[u*8+x] blk[y*8+u]
    : ~ i y 0
    ~ < y 8 {
        : ~ i x 0
        ~ < x 8 {
            : ~ f s 0.0
            : ~ i u 0
            ~ < u 8 { = s + s * ( __b_f A + * u 8 x ) # f ( __b_i blk + * y 8 u ) = u + u 1 }
            ( vec_set [f] tmp + * y 8 x * s 0.5 )
            = x + x 1
        }
        = y + y 1
    }
    // cols: out[y*8+x] = clamp( round(0.5 * Σ_v A[v*8+y] tmp[v*8+x]) + 128 )
    : ~ i x2 0
    ~ < x2 8 {
        : ~ i y2 0
        ~ < y2 8 {
            : ~ f s2 0.0
            : ~ i v 0
            ~ < v 8 { = s2 + s2 * ( __b_f A + * v 8 y2 ) ( __b_f tmp + * v 8 x2 ) = v + v 1 }
            : f fv + * s2 0.5 128.0
            : ~ i r ? >= fv 0.0 { # i + fv 0.5 } { # i - fv 0.5 }
            ? < r 0 { = r 0 } {}
            ? > r 255 { = r 255 } {}
            ( vec_set [i] out + * + oy y2 pw + ox x2 r )
            = y2 + y2 1
        }
        = x2 + x2 1
    }
}
@ __b_f ( Vec f ) v i p → f {
    ?? ( vec_get [f] v p ) { T x → { ^ x } F _ → { ^ 0.0 } }
}

// Reset at a restart marker: drop partial bits, skip FFDn, clear predictors.
@ __jp_restart *Jpeg j → v {
    = . j bcnt 0
    = . j marker 0
    : i p . j bpos
    ? & == ( __b . j buf p ) 255 & >= ( __b . j buf + p 1 ) 208 <= ( __b . j buf + p 1 ) 215 {
        = . j bpos + p 2
    } {}
    : ~ i c 0
    ~ < c 4 { ( vec_set [i] . j cpred c 0 ) = c + c 1 }
}

// ── Segment parsers ───────────────────────────────────────────────────

@ __jp_dqt *Jpeg j i dp i dend → v {
    : ~ i p dp
    ~ < p dend {
        : i pqtq ( __b . j buf p )
        : i pq >> pqtq 4
        : i tq & pqtq 15
        = p + p 1
        : ~ i k 0
        ~ < k 64 {
            : i val ? == pq 0 { ( __b . j buf + p k ) } { ( __u16 . j buf + p * k 2 ) }
            ( vec_set [i] . j qt + * tq 64 k val )
            = k + k 1
        }
        = p + p ? == pq 0 { 64 } { 128 }
    }
}

@ __jp_dht *Jpeg j i dp i dend → v {
    : ~ i p dp
    ~ < p dend {
        : i tcth ( __b . j buf p )
        : i tc >> tcth 4
        : i th & tcth 15
        : i t + * tc 4 th
        = p + p 1
        : ( Vec i ) counts ( __ivec 17 0 )
        : ~ i total 0
        : ~ i L 1
        ~ <= L 16 {
            : i c ( __b . j buf + p - L 1 )
            ( vec_set [i] counts L c )
            = total + total c
            = L + L 1
        }
        = p + p 16
        : i base * t 17
        : ~ i code 0
        : ~ i kk 0
        : ~ i LL 1
        ~ <= LL 16 {
            : i cnt ( __b_i counts LL )
            ? == cnt 0 {
                ( vec_set [i] . j hmaxc + base LL -1 )
            } {
                ( vec_set [i] . j hptr + base LL kk )
                ( vec_set [i] . j hmin + base LL code )
                = code + code cnt
                ( vec_set [i] . j hmaxc + base LL - code 1 )
                = kk + kk cnt
            }
            = code << code 1
            = LL + LL 1
        }
        : ~ i si 0
        ~ < si total {
            ( vec_set [i] . j hvals + * t 256 si ( __b . j buf + p si ) )
            = si + si 1
        }
        = p + p total
        ( vec_free [i] counts )
    }
}

@ __jp_sof *Jpeg j i dp → b {
    ? == ( __b . j buf dp ) 8 {} { ^ F }
    = . j height ( __u16 . j buf + dp 1 )
    = . j width ( __u16 . j buf + dp 3 )
    : i nc ( __b . j buf + dp 5 )
    ? || == nc 1 == nc 3 {} { ^ F }
    = . j ncomp nc
    : ~ i hmax 1
    : ~ i vmax 1
    : ~ i c 0
    ~ < c nc {
        : i o + dp + 6 * c 3
        ( vec_set [i] . j cid c ( __b . j buf o ) )
        : i hv ( __b . j buf + o 1 )
        : i h >> hv 4
        : i vv & hv 15
        ( vec_set [i] . j chf c h )
        ( vec_set [i] . j cvf c vv )
        ( vec_set [i] . j ctq c ( __b . j buf + o 2 ) )
        ? > h hmax { = hmax h } {}
        ? > vv vmax { = vmax vv } {}
        = c + c 1
    }
    = . j hmax hmax
    = . j vmax vmax
    ^ T
}

@ __jp_sos *Jpeg j i dp → v {
    : i ns ( __b . j buf dp )
    : ~ i s 0
    ~ < s ns {
        : i cs ( __b . j buf + dp + 1 * s 2 )
        : i tdta ( __b . j buf + dp + 2 * s 2 )
        : ~ i ci 0
        : ~ i cc 0
        ~ < cc . j ncomp {
            ? == ( __b_i . j cid cc ) cs { = ci cc } {}
            = cc + cc 1
        }
        ( vec_set [i] . j ctd ci >> tdta 4 )
        ( vec_set [i] . j cta ci & tdta 15 )
        = s + s 1
    }
    = . j bpos + dp + 1 + * ns 2 3
    = . j bcnt 0
}

// Walk segments up to SOS; return the entropy-data start, or -1.
@ __jp_parse *Jpeg j → i {
    : ~ i p 2
    : i n . j len
    : ~ i result -1
    : ~ b going T
    ~ & going < + p 4 n {
        ? == ( __b . j buf p ) 255 {} { = going F = . j ok F }
        ? going {
            : i m ( __b . j buf + p 1 )
            ? == m 255 { = p + p 1 } {
                : i seg + p 2
                : i slen ( __u16 . j buf seg )
                : i dp + seg 2
                : i dend + seg slen
                ? == m 217 { = going F } {
                ? == m 219 { ( __jp_dqt j dp dend ) = p dend } {
                ? == m 196 { ( __jp_dht j dp dend ) = p dend } {
                ? == m 221 { = . j restart ( __u16 . j buf dp ) = p dend } {
                ? == m 192 { ? ( __jp_sof j dp ) {} { = . j ok F = going F } = p dend } {
                ? || == m 193 == m 194 { = . j ok F = going F } {
                ? == m 218 { ( __jp_sos j dp ) = result . j bpos = going F } {
                    = p dend
                } } } } } } }
            }
        } {}
    }
    ^ result
}

// ── Scan: decode MCUs into per-component planes, upsample, colour-convert.

@ __jp_sample ( Vec i ) plane i pw i hf i vf i hmax i vmax i x i y → i {
    : i sx / * x hf hmax
    : i sy / * y vf vmax
    ^ ( __b_i plane + * sy pw sx )
}

@ __jp_scan *Jpeg j → ?Image {
    : i W . j width
    : i H . j height
    : i hmax . j hmax
    : i vmax . j vmax
    ? & & > W 0 > H 0 & > hmax 0 > vmax 0 {} { ^ @ ?Image { F } }
    : i mcux / + W - * hmax 8 1 * hmax 8
    : i mcuy / + H - * vmax 8 1 * vmax 8
    : i nc . j ncomp

    : ( Vec ( Vec i ) ) planes ( vec_new [( Vec i )] )
    : ~ i c 0
    ~ < c nc {
        : i pw * * mcux ( __b_i . j chf c ) 8
        : i ph * * mcuy ( __b_i . j cvf c ) 8
        ( vec_push [( Vec i )] planes ( __ivec * pw ph 0 ) )
        = c + c 1
    }

    : ( Vec i ) blk ( __ivec 64 0 )
    : ( Vec f ) tmp ( vec_with_cap [f] 64 )
    : ~ i tz 0
    ~ < tz 64 { ( vec_push [f] tmp 0.0 ) = tz + tz 1 }

    : ~ i mcount 0
    : ~ i my 0
    ~ & . j ok < my mcuy {
        : ~ i mx 0
        ~ & . j ok < mx mcux {
            ? & & > . j restart 0 > mcount 0 == % mcount . j restart 0 { ( __jp_restart j ) } {}
            : ~ i cc 0
            ~ < cc nc {
                : i hf ( __b_i . j chf cc )
                : i vf ( __b_i . j cvf cc )
                : i pw * * mcux hf 8
                ?? ( vec_get [( Vec i )] planes cc ) {
                    T plane → {
                        : ~ i by 0
                        ~ < by vf {
                            : ~ i bx 0
                            ~ < bx hf {
                                ( __jp_block j cc blk )
                                : i ox * + * mx hf bx 8
                                : i oy * + * my vf by 8
                                ( __jp_idct j blk tmp plane ox oy pw )
                                = bx + bx 1
                            }
                            = by + by 1
                        }
                    }
                    F _ → {}
                }
                = cc + cc 1
            }
            = mcount + mcount 1
            = mx + mx 1
        }
        = my + my 1
    }
    ( vec_free [i] blk )
    ( vec_free [f] tmp )

    : i outch ? == nc 1 { 1 } { 3 }
    : ( Vec u ) out ( vec_with_cap [u] * * W H outch )
    ?? ( vec_get [( Vec i )] planes 0 ) {
        T p0 → {
            : i pw0 * * mcux ( __b_i . j chf 0 ) 8
            : ~ i y 0
            ~ < y H {
                : ~ i x 0
                ~ < x W {
                    ? == nc 1 {
                        ( vec_push [u] out & ( __b_i p0 + * y pw0 x ) 255 )
                    } {
                        : i Y ( __jp_sample p0 pw0 ( __b_i . j chf 0 ) ( __b_i . j cvf 0 ) hmax vmax x y )
                        : ~ i Cb 128
                        : ~ i Cr 128
                        ?? ( vec_get [( Vec i )] planes 1 ) {
                            T p1 → { = Cb ( __jp_sample p1 * * mcux ( __b_i . j chf 1 ) 8 ( __b_i . j chf 1 ) ( __b_i . j cvf 1 ) hmax vmax x y ) }
                            F _ → {}
                        }
                        ?? ( vec_get [( Vec i )] planes 2 ) {
                            T p2 → { = Cr ( __jp_sample p2 * * mcux ( __b_i . j chf 2 ) 8 ( __b_i . j chf 2 ) ( __b_i . j cvf 2 ) hmax vmax x y ) }
                            F _ → {}
                        }
                        : f cbf # f - Cb 128
                        : f crf # f - Cr 128
                        : i R ( __jp_clamp + # f Y * 1.402 crf )
                        : i G ( __jp_clamp + # f Y - - 0.0 * 0.344136 cbf * 0.714136 crf )
                        : i B ( __jp_clamp + # f Y * 1.772 cbf )
                        ( vec_push [u] out R )
                        ( vec_push [u] out G )
                        ( vec_push [u] out B )
                    }
                    = x + x 1
                }
                = y + y 1
            }
        }
        F _ → {}
    }

    : ~ i fc 0
    ~ < fc nc {
        ?? ( vec_get [( Vec i )] planes fc ) { T pv → { ( vec_free [i] pv ) } F _ → {} }
        = fc + fc 1
    }
    ( vec_free [( Vec i )] planes )
    ^ @ ?Image { T ( image_of W H outch out ) }
}

@ __jp_clamp f v → i {
    : i r ? >= v 0.0 { # i + v 0.5 } { # i - v 0.5 }
    ? < r 0 { ^ 0 } {}
    ? > r 255 { ^ 255 } {}
    ^ r
}

// ── Public entry ──────────────────────────────────────────────────────

@ jpeg_decode ( Vec u ) buf → ?Image {
    : i n ( vec_len [u] buf )
    ? < n 4 { ^ @ ?Image { F } } {}
    ? & == ( __b buf 0 ) 255 == ( __b buf 1 ) 216 {} { ^ @ ?Image { F } }
    : *Jpeg j ( __jp_new buf )
    : i estart ( __jp_parse j )
    ? & . j ok >= estart 0 {} { ( __jp_free j ) ^ @ ?Image { F } }
    : ?Image im ( __jp_scan j )
    ( __jp_free j )
    ^ im
}
