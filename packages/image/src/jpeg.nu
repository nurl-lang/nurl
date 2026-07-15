// image/jpeg.nu — JPEG decode: baseline AND progressive (Huffman).
//
// Supports the JPEGs real encoders emit: 8-bit precision, Huffman coding,
// 1 component (greyscale) or 3 (YCbCr → RGB), any 4:4:4 / 4:2:2 / 4:2:0 /
// 4:1:1 subsampling, restart intervals (DRI/RSTn), sequential (SOF0/SOF1)
// and **progressive** (SOF2) frames — spectral selection and successive
// approximation, DC and AC first/refinement scans, EOB runs. Chroma planes
// use libjpeg's "fancy" (triangular) upsampling for 2x1/2x2 expansion —
// bit-matching libjpeg's default path — and a separable float IDCT, so
// output matches a reference decoder (libjpeg/Pillow) to within IDCT
// rounding — JPEG is lossy and the spec permits IDCT variation, so this is
// not bit-exact.
//
// Not supported (clean None, never an out-of-bounds read): arithmetic
// coding, 12-bit, lossless/hierarchical, and 4-component (CMYK/YCCK).

$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `core.nu`

: Jpeg {
    ( Vec u ) buf i len
    i width i height i ncomp
    ( Vec i ) cid ( Vec i ) chf ( Vec i ) cvf ( Vec i ) ctq ( Vec i ) ctd ( Vec i ) cta ( Vec i ) cpred
    i hmax i vmax i restart
    ( Vec i ) qt
    ( Vec i ) hmin ( Vec i ) hmaxc ( Vec i ) hptr ( Vec i ) hvals
    ( Vec f ) idct_a ( Vec i ) zz
    i bpos i bbuf i bcnt i marker
    b ok
    // progressive state: scan parameters, per-component coefficient grids
    b prog i ss i se i ah i al i eobrun
    i nscomp ( Vec i ) scomp
    ( Vec ( Vec i ) ) coefs
    ( Vec i ) cbw ( Vec i ) cbh  // padded block-grid dims per comp
}

@ _ivec i n i fill → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] n )
    : ~ i k 0
    ~ < k n { ( vec_push [i] v fill ) = k + k 1 }
    ^ v
}

@ _idct_basis → ( Vec f ) {
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

@ _zigzag → ( Vec i ) {
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

@ __jpg_new ( Vec u ) buf → *Jpeg {
    : *Jpeg j # *Jpeg ( nurl_malloc Z Jpeg )
    = . j buf buf
    = . j len ( vec_len [u] buf )
    = . j cid ( _ivec 4 0 )
    = . j chf ( _ivec 4 1 )
    = . j cvf ( _ivec 4 1 )
    = . j ctq ( _ivec 4 0 )
    = . j ctd ( _ivec 4 0 )
    = . j cta ( _ivec 4 0 )
    = . j cpred ( _ivec 4 0 )
    = . j qt ( _ivec 256 0 )
    = . j hmin ( _ivec 136 0 )
    = . j hmaxc ( _ivec 136 -1 )
    = . j hptr ( _ivec 136 0 )
    = . j hvals ( _ivec 2048 0 )
    = . j idct_a ( _idct_basis )
    = . j zz ( _zigzag )
    = . j bcnt 0
    = . j marker 0
    = . j restart 0
    = . j ok T
    = . j prog F
    = . j ss 0
    = . j se 63
    = . j ah 0
    = . j al 0
    = . j eobrun 0
    = . j nscomp 0
    = . j scomp ( _ivec 4 0 )
    = . j coefs ( vec_new [( Vec i )] )
    = . j cbw ( _ivec 4 0 )
    = . j cbh ( _ivec 4 0 )
    ^ j
}

@ __jpg_free * Jpeg j → v {
    ( vec_free [i] . j cid ) ( vec_free [i] . j chf ) ( vec_free [i] . j cvf )
    ( vec_free [i] . j ctq ) ( vec_free [i] . j ctd ) ( vec_free [i] . j cta )
    ( vec_free [i] . j cpred ) ( vec_free [i] . j qt )
    ( vec_free [i] . j hmin ) ( vec_free [i] . j hmaxc ) ( vec_free [i] . j hptr ) ( vec_free [i] . j hvals )
    ( vec_free [f] . j idct_a ) ( vec_free [i] . j zz )
    ( vec_free [i] . j scomp ) ( vec_free [i] . j cbw ) ( vec_free [i] . j cbh )
    : i ncf ( vec_len [( Vec i )] . j coefs )
    : ~ i k 0
    ~ < k ncf {
        ?? ( vec_get [( Vec i )] . j coefs k ) { T cv → { ( vec_free [i] cv ) } F _ → {} }
        = k + k 1
    }
    ( vec_free [( Vec i )] . j coefs )
    ( nurl_free j )
}

// ── 16-bit big-endian at a byte position ──────────────────────────────
@ __u16 ( Vec u ) buf i p → i { ^ + * ( _byte buf p ) 256 ( _byte buf + p 1 ) }

// ── Entropy bit reader (handles 0xFF00 stuffing; stops at a marker) ────
@ __jpg_bit * Jpeg j → i {
    ? > . j bcnt 0 {} {
        : i p . j bpos
        ? >= p . j len { = . j marker 217 ^ 0 } {}
        : i b ( _byte . j buf p )
        ? == b 255 {
            : i b2 ( _byte . j buf + p 1 )
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

@ __jpg_receive * Jpeg j i n → i {
    : ~ i v 0
    : ~ i k 0
    ~ < k n { = v | << v 1 ( __jpg_bit j ) = k + k 1 }
    ^ v
}

@ __jpg_extend i v i n → i {
    ? == n 0 { ^ 0 } {}
    ? < v << 1 - n 1 { ^ - v - << 1 n 1 } { ^ v }
}

// Decode one Huffman symbol from table `t` (0..7 = 4 DC then 4 AC).
@ __jpg_huff * Jpeg j i t → i {
    : i base * t 17
    : ~ i code ( __jpg_bit j )
    : ~ i len 1
    ~ & <= len 16 > code ( _b_i . j hmaxc + base len ) {
        = code | << code 1 ( __jpg_bit j )
        = len + len 1
    }
    ? > len 16 { ^ -1 } {}
    : i idx + ( _b_i . j hptr + base len ) - code ( _b_i . j hmin + base len )
    ^ ( _b_i . j hvals + * t 256 idx )
}

// int-vector read (0 out of range)
@ _b_i ( Vec i ) v i p → i {
    ?? ( vec_get [i] v p ) { T x → { ^ x } F _ → { ^ 0 } }
}

// ── Decode + dequantize one 8×8 block into `blk` (natural order) ──────
@ __jpg_block * Jpeg j i comp ( Vec i ) blk → v {
    : ~ i k 0
    ~ < k 64 { ( vec_set [i] blk k 0 ) = k + k 1 }
    : i tq * ( _b_i . j ctq comp ) 64
    : i td ( _b_i . j ctd comp )
    : i ta + 4 ( _b_i . j cta comp )
    : i s ( __jpg_huff j td )
    ? < s 0 { = . j ok F ^ } {}  // corrupt Huffman table/stream
    : i diff ? > s 0 { ( __jpg_extend ( __jpg_receive j s ) s ) } { 0 }
    : i pred + ( _b_i . j cpred comp ) diff
    ( vec_set [i] . j cpred comp pred )
    ( vec_set [i] blk 0 * pred ( _b_i . j qt tq ) )
    : ~ i z 1
    ~ & . j ok <= z 63 {
        : i rs ( __jpg_huff j ta )
        ? < rs 0 { = . j ok F ^ } {}
        : i r >> rs 4
        : i sz & rs 15
        ? == sz 0 {
            ? == r 15 { = z + z 16 } { = z 64 }
        } {
            = z + z r
            ? <= z 63 {
                : i val ( __jpg_extend ( __jpg_receive j sz ) sz )
                ( vec_set [i] blk ( _b_i . j zz z ) * val ( _b_i . j qt + tq z ) )
                = z + z 1
            } { = z 64 }
        }
    }
}

// ── Separable float IDCT: blk (natural) → out (8×8 row-major, 0..255) ──
@ __jpg_idct * Jpeg j ( Vec i ) blk ( Vec f ) tmp ( Vec i ) out i ox i oy i pw → v {
    : ( Vec f ) A . j idct_a
    // rows: tmp[y*8+x] = 0.5 * Σ_u A[u*8+x] blk[y*8+u]
    : ~ i y 0
    ~ < y 8 {
        : ~ i x 0
        ~ < x 8 {
            : ~ f s 0.0
            : ~ i u 0
            ~ < u 8 { = s + s * ( _b_f A + * u 8 x ) # f ( _b_i blk + * y 8 u ) = u + u 1 }
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
            ~ < v 8 { = s2 + s2 * ( _b_f A + * v 8 y2 ) ( _b_f tmp + * v 8 x2 ) = v + v 1 }
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

@ _b_f ( Vec f ) v i p → f {
    ?? ( vec_get [f] v p ) { T x → { ^ x } F _ → { ^ 0.0 } }
}

// Reset at a restart marker: drop partial bits, skip FFDn, clear predictors.
@ __jpg_restart * Jpeg j → v {
    = . j bcnt 0
    = . j marker 0
    : i p . j bpos
    ? & == ( _byte . j buf p ) 255 & >= ( _byte . j buf + p 1 ) 208 <= ( _byte . j buf + p 1 ) 215 {
        = . j bpos + p 2
    } {}
    : ~ i c 0
    ~ < c 4 { ( vec_set [i] . j cpred c 0 ) = c + c 1 }
}

// ── Segment parsers ───────────────────────────────────────────────────

@ __jpg_dqt * Jpeg j i dp i dend → v {
    : ~ i p dp
    ~ < p dend {
        : i pqtq ( _byte . j buf p )
        : i pq >> pqtq 4
        : i tq & pqtq 15
        = p + p 1
        : ~ i k 0
        ~ < k 64 {
            : i val ? == pq 0 { ( _byte . j buf + p k ) } { ( __u16 . j buf + p * k 2 ) }
            ( vec_set [i] . j qt + * tq 64 k val )
            = k + k 1
        }
        = p + p ? == pq 0 { 64 } { 128 }
    }
}

@ __jpg_dht * Jpeg j i dp i dend → v {
    : ~ i p dp
    ~ < p dend {
        : i tcth ( _byte . j buf p )
        : i tc >> tcth 4
        : i th & tcth 15
        : i t + * tc 4 th
        = p + p 1
        : ( Vec i ) counts ( _ivec 17 0 )
        : ~ i total 0
        : ~ i L 1
        ~ <= L 16 {
            : i c ( _byte . j buf + p - L 1 )
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
            : i cnt ( _b_i counts LL )
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
            ( vec_set [i] . j hvals + * t 256 si ( _byte . j buf + p si ) )
            = si + si 1
        }
        = p + p total
        ( vec_free [i] counts )
    }
}

@ __jpg_sof * Jpeg j i dp → b {
    ? == ( _byte . j buf dp ) 8 {} { ^ F }
    = . j height ( __u16 . j buf + dp 1 )
    = . j width ( __u16 . j buf + dp 3 )
    ? & > . j width 0 > . j height 0 {} { ^ F }
    ? <= * . j width . j height 67108864 {} { ^ F }  // ≤ 64 Mpx
    : i nc ( _byte . j buf + dp 5 )
    ? || == nc 1 == nc 3 {} { ^ F }
    = . j ncomp nc
    : ~ i hmax 1
    : ~ i vmax 1
    : ~ i c 0
    ~ < c nc {
        : i o + dp + 6 * c 3
        ( vec_set [i] . j cid c ( _byte . j buf o ) )
        : i hv ( _byte . j buf + o 1 )
        : i h >> hv 4
        : i vv & hv 15
        ? & & >= h 1 <= h 4 & >= vv 1 <= vv 4 {} { ^ F }  // T.81 sampling range
        ( vec_set [i] . j chf c h )
        ( vec_set [i] . j cvf c vv )
        : i tq ( _byte . j buf + o 2 )
        ? <= tq 3 {} { ^ F }
        ( vec_set [i] . j ctq c tq )
        ? > h hmax { = hmax h } {}
        ? > vv vmax { = vmax vv } {}
        = c + c 1
    }
    = . j hmax hmax
    = . j vmax vmax
    ^ T
}

@ __jpg_sos * Jpeg j i dp → v {
    : ~ i ns ( _byte . j buf dp )
    ? || < ns 1 > ns 4 { = ns 1 } {}
    = . j nscomp ns
    : ~ i s 0
    ~ < s ns {
        : i cs ( _byte . j buf + dp + 1 * s 2 )
        : i tdta ( _byte . j buf + dp + 2 * s 2 )
        : ~ i ci 0
        : ~ i cc 0
        ~ < cc . j ncomp {
            ? == ( _b_i . j cid cc ) cs { = ci cc } {}
            = cc + cc 1
        }
        ( vec_set [i] . j scomp s ci )
        ( vec_set [i] . j ctd ci >> tdta 4 )
        ( vec_set [i] . j cta ci & tdta 15 )
        = s + s 1
    }
    // Ss / Se / (Ah<<4 | Al) — baseline writes 0 / 63 / 0 here
    : i base + dp + 1 * ns 2
    = . j ss ( _byte . j buf base )
    = . j se ( _byte . j buf + base 1 )
    : i aa ( _byte . j buf + base 2 )
    = . j ah >> aa 4
    = . j al & aa 15
    ? > . j se 63 { = . j se 63 } {}
    ? > . j ss 63 { = . j ss 63 } {}
    = . j bpos + base 3
    = . j bcnt 0
    = . j marker 0
    = . j eobrun 0
    : ~ i c 0
    ~ < c 4 { ( vec_set [i] . j cpred c 0 ) = c + c 1 }
}

// ── Progressive scans ─────────────────────────────────────────────────
//
// A progressive frame (SOF2) sends the DCT coefficients over several scans:
// each covers one spectral band (Ss..Se) at one bit of precision (Ah/Al).
// We accumulate coefficients per component in full-precision grids and run
// the IDCT once, after the last scan.

// Allocate the per-component coefficient grids (padded to the MCU grid).
@ __jpg_prog_alloc * Jpeg j → v {
    : i mcux / + . j width - * . j hmax 8 1 * . j hmax 8
    : i mcuy / + . j height - * . j vmax 8 1 * . j vmax 8
    : ~ i c 0
    ~ < c . j ncomp {
        : i bw * mcux ( _b_i . j chf c )
        : i bh * mcuy ( _b_i . j cvf c )
        ( vec_set [i] . j cbw c bw )
        ( vec_set [i] . j cbh c bh )
        ( vec_push [( Vec i )] . j coefs ( _ivec * * bw bh 64 0 ) )
        = c + c 1
    }
}

@ __jpg_prog_restart * Jpeg j → v {
    ( __jpg_restart j )
    = . j eobrun 0
}

// DC scan, one block. First pass (Ah=0) decodes the diff at reduced
// precision; refinement passes append one magnitude bit.
@ __jpg_prog_dc * Jpeg j i ci ( Vec i ) cf i bidx → v {
    : i base * bidx 64
    ? == . j ah 0 {
        : i td ( _b_i . j ctd ci )
        : i s ( __jpg_huff j td )
        ? < s 0 { = . j ok F ^ } {}
        : i diff ? > s 0 { ( __jpg_extend ( __jpg_receive j s ) s ) } { 0 }
        : i pred + ( _b_i . j cpred ci ) diff
        ( vec_set [i] . j cpred ci pred )
        ( vec_set [i] cf base << pred . j al )
    } {
        ? == ( __jpg_bit j ) 1 {
            ( vec_set [i] cf base | ( _b_i cf base ) << 1 . j al )
        } {}
    }
}

// AC scan, first pass (Ah=0): run-length + size symbols with EOB runs.
@ __jpg_prog_ac1 * Jpeg j i ci ( Vec i ) cf i bidx → v {
    : i base * bidx 64
    ? > . j eobrun 0 { = . j eobrun - . j eobrun 1 ^ } {}
    : i ta + 4 ( _b_i . j cta ci )
    : ~ i k . j ss
    : ~ b going T
    ~ & going <= k . j se {
        : i rs ( __jpg_huff j ta )
        ? < rs 0 { = . j ok F = going F } {
            : i r >> rs 4
            : i s & rs 15
            ? == s 0 {
                ? == r 15 { = k + k 16 } {
                    : ~ i er - << 1 r 1
                    ? > r 0 { = er + er ( __jpg_receive j r ) } {}
                    = . j eobrun er
                    = going F
                }
            } {
                = k + k r
                ? > k . j se { = going F } {
                    : i val ( __jpg_extend ( __jpg_receive j s ) s )
                    ( vec_set [i] cf + base ( _b_i . j zz k ) << val . j al )
                    = k + k 1
                }
            }
        }
    }
}

// One correction bit for an already-nonzero coefficient.
@ __jpg_prog_fix * Jpeg j ( Vec i ) cf i pos i bit → v {
    : i cur ( _b_i cf pos )
    ? == ( __jpg_bit j ) 1 {
        ? == & cur bit 0 {
            ( vec_set [i] cf pos ? > cur 0 { + cur bit } { - cur bit } )
        } {}
    } {}
}

// AC scan, refinement pass (Ah>0): new coefficients arrive as ±1<<Al and
// every already-nonzero coefficient on the way gets a correction bit.
@ __jpg_prog_ac2 * Jpeg j i ci ( Vec i ) cf i bidx → v {
    : i base * bidx 64
    : i bit << 1 . j al
    ? > . j eobrun 0 {
        = . j eobrun - . j eobrun 1
        : ~ i k . j ss
        ~ <= k . j se {
            : i pos + base ( _b_i . j zz k )
            ? != ( _b_i cf pos ) 0 { ( __jpg_prog_fix j cf pos bit ) } {}
            = k + k 1
        }
        ^
    } {}
    : i ta + 4 ( _b_i . j cta ci )
    : ~ i k2 . j ss
    ~ & . j ok <= k2 . j se {
        : i rs ( __jpg_huff j ta )
        ? < rs 0 { = . j ok F ^ } {}
        : ~ i r >> rs 4
        : ~ i s & rs 15
        ? == s 0 {
            ? < r 15 {
                : ~ i er - << 1 r 1
                ? > r 0 { = er + er ( __jpg_receive j r ) } {}
                = . j eobrun er
                = r 64  // walk out the rest of the block
            } {}
        } {
            = s ? == ( __jpg_bit j ) 1 { bit } { - 0 bit }
        }
        : ~ b walking T
        ~ & walking <= k2 . j se {
            : i pos + base ( _b_i . j zz k2 )
            = k2 + k2 1
            ? != ( _b_i cf pos ) 0 { ( __jpg_prog_fix j cf pos bit ) } {
                ? == r 0 {
                    ? != s 0 { ( vec_set [i] cf pos s ) } {}
                    = walking F
                } { = r - r 1 }
            }
        }
    }
}

// Route one block to the right scan kind.
@ __jpg_prog_block * Jpeg j i ci ( Vec i ) cf i bidx → v {
    ? == . j ss 0 { ( __jpg_prog_dc j ci cf bidx ) } {
        ? == . j ah 0 { ( __jpg_prog_ac1 j ci cf bidx ) } { ( __jpg_prog_ac2 j ci cf bidx ) }
    }
}

// Run one progressive scan: interleaved (ns>1, MCU order) or single
// component (its own unpadded block raster).
@ __jpg_prog_scan * Jpeg j → v {
    : i ns . j nscomp
    ? == ns 1 {
        : i ci ( _b_i . j scomp 0 )
        : i cw / + * . j width ( _b_i . j chf ci ) - . j hmax 1 . j hmax
        : i chh / + * . j height ( _b_i . j cvf ci ) - . j vmax 1 . j vmax
        : i nbw / + cw 7 8
        : i nbh / + chh 7 8
        : i bw ( _b_i . j cbw ci )
        ?? ( vec_get [( Vec i )] . j coefs ci ) {
            T cf → {
                : ~ i cnt 0
                : ~ i by 0
                ~ & . j ok < by nbh {
                    : ~ i bx 0
                    ~ & . j ok < bx nbw {
                        ? & & > . j restart 0 > cnt 0 == % cnt . j restart 0 { ( __jpg_prog_restart j ) } {}
                        ( __jpg_prog_block j ci cf + * by bw bx )
                        = cnt + cnt 1
                        = bx + bx 1
                    }
                    = by + by 1
                }
            }
            F _ → { = . j ok F }
        }
    } {
        : i mcux / + . j width - * . j hmax 8 1 * . j hmax 8
        : i mcuy / + . j height - * . j vmax 8 1 * . j vmax 8
        : ~ i cnt 0
        : ~ i my 0
        ~ & . j ok < my mcuy {
            : ~ i mx 0
            ~ & . j ok < mx mcux {
                ? & & > . j restart 0 > cnt 0 == % cnt . j restart 0 { ( __jpg_prog_restart j ) } {}
                : ~ i sc 0
                ~ < sc ns {
                    : i ci ( _b_i . j scomp sc )
                    : i hf ( _b_i . j chf ci )
                    : i vf ( _b_i . j cvf ci )
                    : i bw ( _b_i . j cbw ci )
                    ?? ( vec_get [( Vec i )] . j coefs ci ) {
                        T cf → {
                            : ~ i by 0
                            ~ < by vf {
                                : ~ i bx 0
                                ~ < bx hf {
                                    ( __jpg_prog_block j ci cf + * + * my vf by bw + * mx hf bx )
                                    = bx + bx 1
                                }
                                = by + by 1
                            }
                        }
                        F _ → { = . j ok F }
                    }
                    = sc + sc 1
                }
                = cnt + cnt 1
                = mx + mx 1
            }
            = my + my 1
        }
    }
}

// After the last scan: dequantise + IDCT every block, then share the
// baseline upsample/colour-convert tail.
@ __jpg_prog_finish * Jpeg j → ?Image {
    ? & & > . j width 0 > . j height 0 & > . j hmax 0 > . j vmax 0 {} { ^ @ ?Image { F } }
    : i nc . j ncomp
    : ( Vec ( Vec i ) ) planes ( vec_new [( Vec i )] )
    : ( Vec i ) blk ( _ivec 64 0 )
    : ( Vec f ) tmp ( vec_with_cap [f] 64 )
    : ~ i tz 0
    ~ < tz 64 { ( vec_push [f] tmp 0.0 ) = tz + tz 1 }
    : ~ i c 0
    ~ < c nc {
        : i bw ( _b_i . j cbw c )
        : i bh ( _b_i . j cbh c )
        : i pw * bw 8
        : ( Vec i ) plane ( _ivec * pw * bh 8 0 )
        : i tq * ( _b_i . j ctq c ) 64
        ?? ( vec_get [( Vec i )] . j coefs c ) {
            T cf → {
                : ~ i by 0
                ~ < by bh {
                    : ~ i bx 0
                    ~ < bx bw {
                        : i base * + * by bw bx 64
                        : ~ i z 0
                        ~ < z 64 {
                            : i nat ( _b_i . j zz z )
                            ( vec_set [i] blk nat * ( _b_i cf + base nat ) ( _b_i . j qt + tq z ) )
                            = z + z 1
                        }
                        ( __jpg_idct j blk tmp plane * bx 8 * by 8 pw )
                        = bx + bx 1
                    }
                    = by + by 1
                }
            }
            F _ → {}
        }
        ( vec_push [( Vec i )] planes plane )
        = c + c 1
    }
    ( vec_free [i] blk )
    ( vec_free [f] tmp )
    ^ ( __jpg_to_image j planes )
}

// ── Segment walker ────────────────────────────────────────────────────

// Walk all segments. Sequential (SOF0/SOF1) frames decode at their single
// SOS; progressive (SOF2) frames accumulate scans until EOI, then finish.
@ __jpg_run * Jpeg j → ?Image {
    : ~ i p 2
    : i n . j len
    : ~ b sof F
    : ~ b sawscan F
    : ~ b going T
    ~ & & going . j ok < + p 2 n {
        ? == ( _byte . j buf p ) 255 {} { = . j ok F = going F }
        ? going {
            : i m ( _byte . j buf + p 1 )
            ? == m 255 { = p + p 1 } {
                ? || == m 1 & >= m 208 <= m 215 { = p + p 2 } {  // TEM / stray RSTn
                    ? == m 216 { = p + p 2 } {  // stray SOI
                        ? == m 217 { = going F } {  // EOI
                            ? < + p 4 n {} { = . j ok F = going F }
                            ? going {
                                : i seg + p 2
                                : i slen ( __u16 . j buf seg )
                                : i dp + seg 2
                                : i dend + seg slen
                                ? || < slen 2 > dend n { = . j ok F = going F } {
                                    : ~ i np dend
                                    ? == m 219 { ( __jpg_dqt j dp dend ) } {
                                        ? == m 196 { ( __jpg_dht j dp dend ) } {
                                            ? == m 221 { = . j restart ( __u16 . j buf dp ) } {
                                                ? || == m 192 == m 193 {
                                                    ? || sof ! ( __jpg_sof j dp ) {
                                                        ( _img_set_err `JPEG: unsupported frame (precision, size, components or sampling)` )
                                                        = . j ok F
                                                    } { = sof T = . j prog F }
                                                } {
                                                    ? == m 194 {
                                                        ? || sof ! ( __jpg_sof j dp ) {
                                                            ( _img_set_err `JPEG: unsupported frame (precision, size, components or sampling)` )
                                                            = . j ok F
                                                        } {
                                                            = sof T
                                                            = . j prog T
                                                            ( __jpg_prog_alloc j )
                                                        }
                                                    } {
                                                        ? & >= m 195 <= m 207 {
                                                            ? == m 204 {} {
                                                                ( _img_set_err `JPEG: unsupported coding (arithmetic, 12-bit or lossless)` )
                                                                = . j ok F
                                                            }
                                                        } {
                                                            ? == m 218 {
                                                                ? sof {} { = . j ok F }
                                                                ? . j ok {
                                                                    ( __jpg_sos j dp )
                                                                    ? . j prog {
                                                                        ( __jpg_prog_scan j )
                                                                        = sawscan T
                                                                        = np . j bpos
                                                                    } {
                                                                        ^ ( __jpg_scan j )
                                                                    }
                                                                } {}
                                                            } {} } } } } } }
                                    = p np
                                }
                            } {}
                        } } } }
        } {}
    }
    ? & & . j ok . j prog sawscan { ^ ( __jpg_prog_finish j ) } {}
    ^ @ ?Image { F }
}

// ── Scan: decode MCUs into per-component planes, upsample, colour-convert.

// Clamped component-plane read (sample coordinates; cw/ch are the REAL
// sample dimensions of the component — the plane is padded to the MCU grid
// and the padding must never be read).
@ __jpg_pat ( Vec i ) p i pw i cw i ch i sx i sy → i {
    : i xx ? < sx 0 { 0 } { ? < sx cw { sx } { - cw 1 } }
    : i yy ? < sy 0 { 0 } { ? < sy ch { sy } { - ch 1 } }
    ^ ( _b_i p + * yy pw xx )
}

// One full-resolution sample of a (possibly subsampled) component plane.
// Matches libjpeg's DEFAULT upsamplers exactly (do_fancy_upsampling=TRUE,
// what Pillow uses): direct read for 1:1; the triangular "fancy" filter for
// 2x1 and 2x2 expansion — out = (3*near + far + bias) with edge clamping,
// biases 1/2 (h2v1, >>2) and 8/7 (h2v2, >>4 on 3:1 column sums); plain box
// for any other ratio and for tiny components (cw <= 2), as libjpeg does.
@ __jpg_sample ( Vec i ) plane i pw i cw i ch i hf i vf i hmax i vmax i x i y → i {
    ? & == hf hmax == vf vmax { ^ ( _b_i plane + * y pw x ) } {}
    ? & & == * hf 2 hmax > cw 2 == vf vmax {
        // h2v1 fancy: (3*near + far + 1|2) >> 2
        : i sx / x 2
        : i px & x 1
        : i dx ? == px 0 { -1 } { 1 }
        : i near ( __jpg_pat plane pw cw ch sx y )
        : i far ( __jpg_pat plane pw cw ch + sx dx y )
        : i bias ? == px 0 { 1 } { 2 }
        ^ >> + + * 3 near far bias 2
    } {}
    ? & & == * hf 2 hmax > cw 2 == * vf 2 vmax {
        // h2v2 fancy: colsum = 3*near_row + far_row, then (3*cs + cs_far + 8|7) >> 4
        : i sx / x 2
        : i px & x 1
        : i dx ? == px 0 { -1 } { 1 }
        : i sy / y 2
        : i py & y 1
        : i dy ? == py 0 { -1 } { 1 }
        : i syf + sy dy
        : i sxf + sx dx
        : i cs0 + * 3 ( __jpg_pat plane pw cw ch sx sy ) ( __jpg_pat plane pw cw ch sx syf )
        : i cs1 + * 3 ( __jpg_pat plane pw cw ch sxf sy ) ( __jpg_pat plane pw cw ch sxf syf )
        : i bias ? == px 0 { 8 } { 7 }
        ^ >> + + * 3 cs0 cs1 bias 4
    } {}
    // box upsample (non-2x or fractional ratios)
    : i sx / * x hf hmax
    : i sy / * y vf vmax
    ^ ( _b_i plane + * sy pw sx )
}

@ __jpg_scan * Jpeg j → ?Image {
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
        : i pw * * mcux ( _b_i . j chf c ) 8
        : i ph * * mcuy ( _b_i . j cvf c ) 8
        ( vec_push [( Vec i )] planes ( _ivec * pw ph 0 ) )
        = c + c 1
    }

    : ( Vec i ) blk ( _ivec 64 0 )
    : ( Vec f ) tmp ( vec_with_cap [f] 64 )
    : ~ i tz 0
    ~ < tz 64 { ( vec_push [f] tmp 0.0 ) = tz + tz 1 }

    : ~ i mcount 0
    : ~ i my 0
    ~ & . j ok < my mcuy {
        : ~ i mx 0
        ~ & . j ok < mx mcux {
            ? & & > . j restart 0 > mcount 0 == % mcount . j restart 0 { ( __jpg_restart j ) } {}
            : ~ i cc 0
            ~ < cc nc {
                : i hf ( _b_i . j chf cc )
                : i vf ( _b_i . j cvf cc )
                : i pw * * mcux hf 8
                ?? ( vec_get [( Vec i )] planes cc ) {
                    T plane → {
                        : ~ i by 0
                        ~ < by vf {
                            : ~ i bx 0
                            ~ < bx hf {
                                ( __jpg_block j cc blk )
                                : i ox * + * mx hf bx 8
                                : i oy * + * my vf by 8
                                ( __jpg_idct j blk tmp plane ox oy pw )
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
    ^ ( __jpg_to_image j planes )
}

// Shared tail: per-component planes (padded to the MCU grid) → upsampled,
// colour-converted Image. Frees `planes`.
@ __jpg_to_image * Jpeg j ( Vec ( Vec i ) ) planes → ?Image {
    : i W . j width
    : i H . j height
    : i hmax . j hmax
    : i vmax . j vmax
    : i mcux / + W - * hmax 8 1 * hmax 8
    : i nc . j ncomp
    : i outch ? == nc 1 { 1 } { 3 }
    : ( Vec u ) out ( vec_with_cap [u] * * W H outch )
    ?? ( vec_get [( Vec i )] planes 0 ) {
        T p0 → {
            : i hf0 ( _b_i . j chf 0 )
            : i vf0 ( _b_i . j cvf 0 )
            : i pw0 * * mcux hf0 8
            : i cw0 / + * W hf0 - hmax 1 hmax
            : i ch0 / + * H vf0 - vmax 1 vmax
            : i hf1 ( _b_i . j chf 1 )
            : i vf1 ( _b_i . j cvf 1 )
            : i pw1 * * mcux hf1 8
            : i cw1 / + * W hf1 - hmax 1 hmax
            : i ch1 / + * H vf1 - vmax 1 vmax
            : i hf2 ( _b_i . j chf 2 )
            : i vf2 ( _b_i . j cvf 2 )
            : i pw2 * * mcux hf2 8
            : i cw2 / + * W hf2 - hmax 1 hmax
            : i ch2 / + * H vf2 - vmax 1 vmax
            : ~ i y 0
            ~ < y H {
                : ~ i x 0
                ~ < x W {
                    ? == nc 1 {
                        ( vec_push [u] out & ( _b_i p0 + * y pw0 x ) 255 )
                    } {
                        : i Y ( __jpg_sample p0 pw0 cw0 ch0 hf0 vf0 hmax vmax x y )
                        : ~ i Cb 128
                        : ~ i Cr 128
                        ?? ( vec_get [( Vec i )] planes 1 ) {
                            T p1 → { = Cb ( __jpg_sample p1 pw1 cw1 ch1 hf1 vf1 hmax vmax x y ) }
                            F _ → {}
                        }
                        ?? ( vec_get [( Vec i )] planes 2 ) {
                            T p2 → { = Cr ( __jpg_sample p2 pw2 cw2 ch2 hf2 vf2 hmax vmax x y ) }
                            F _ → {}
                        }
                        : f cbf # f - Cb 128
                        : f crf # f - Cr 128
                        : i R ( __jpg_clamp + # f Y * 1.402 crf )
                        : i G ( __jpg_clamp + # f Y - - 0.0 * 0.344136 cbf * 0.714136 crf )
                        : i B ( __jpg_clamp + # f Y * 1.772 cbf )
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

@ __jpg_clamp f v → i {
    : i r ? >= v 0.0 { # i + v 0.5 } { # i - v 0.5 }
    ? < r 0 { ^ 0 } {}
    ? > r 255 { ^ 255 } {}
    ^ r
}

// ── Public entry ──────────────────────────────────────────────────────

@ jpeg_decode ( Vec u ) buf → ?Image {
    ( _img_set_err `` )
    : i n ( vec_len [u] buf )
    ? < n 4 { ( _img_set_err `not a JPEG` ) ^ @ ?Image { F } } {}
    ? & == ( _byte buf 0 ) 255 == ( _byte buf 1 ) 216 {} { ( _img_set_err `not a JPEG` ) ^ @ ?Image { F } }
    : *Jpeg j ( __jpg_new buf )
    : ?Image im ( __jpg_run j )
    ( __jpg_free j )
    ?? im {
        T x → { ^ @ ?Image { T x } }
        F _ → {
            ? ( nurl_str_eq ( image_error ) `` ) { ( _img_set_err `JPEG: corrupt or unsupported stream` ) } {}
            ^ @ ?Image { F }
        }
    }
}
