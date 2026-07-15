// image/jpeg_enc.nu — baseline JPEG (JFIF) encode.
//
// Writes the interoperable core of the format: baseline sequential DCT,
// 8-bit, Huffman-coded with the ITU T.81 Annex K standard tables, Annex K
// quantisation tables scaled by a libjpeg-style quality factor (1–100).
// Greyscale images (1/2 channels) encode as one component; colour (3/4)
// as YCbCr with 4:4:4, 4:2:2 or 4:2:0 subsampling — chroma is box-averaged
// before encoding. Alpha channels are dropped.
//
//   ( jpeg_encode im 90 )          → ( Vec u )   4:2:0 below quality 90,
//                                                4:4:4 from 90 up
//   ( jpeg_encode_sub im 85 2 )    → ( Vec u )   subsampling forced:
//                                                0 = 4:4:4, 1 = 4:2:2, 2 = 4:2:0
//
// A decode→encode→decode round trip stays within normal JPEG loss for the
// chosen quality; the output decodes in libjpeg/Pillow and in this
// package's own jpeg_decode.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `core.nu`
$ `jpeg.nu`

// Parse a space-separated decimal list into a Vec i (table literals).
@ __jpe_ints s txt → ( Vec i ) {
    : ( Vec u ) b ( vec_new [u] )
    ( bytes_extend_str b txt )
    : i n ( vec_len [u] b )
    : ( Vec i ) out ( vec_new [i] )
    : ~ i p 0
    ~ < p n {
        : i c ( _byte b p )
        ? & >= c 48 <= c 57 {
            : ~ i v 0
            ~ & < p n & >= ( _byte b p ) 48 <= ( _byte b p ) 57 {
                = v + * v 10 - ( _byte b p ) 48
                = p + p 1
            }
            ( vec_push [i] out v )
        } { = p + p 1 }
    }
    ( vec_free [u] b )
    ^ out
}

// ── Annex K tables ────────────────────────────────────────────────────

// Base quantisation tables, natural (row-major) order.
@ __jpe_qbase_luma → ( Vec i ) {
    ^ ( __jpe_ints `16 11 10 16 24 40 51 61 12 12 14 19 26 58 60 55 14 13 16 24 40 57 69 56 14 17 22 29 51 87 80 62 18 22 37 56 68 109 103 77 24 35 55 64 81 104 113 92 49 64 78 87 103 121 120 101 72 92 95 98 112 100 103 99` )
}

@ __jpe_qbase_chroma → ( Vec i ) {
    ^ ( __jpe_ints `17 18 24 47 99 99 99 99 18 21 26 66 99 99 99 99 24 26 56 99 99 99 99 99 47 66 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99` )
}

// Standard Huffman specs: 16 length counts, then the symbol list.
@ __jpe_hbits_dc_l → ( Vec i ) { ^ ( __jpe_ints `0 1 5 1 1 1 1 1 1 0 0 0 0 0 0 0` ) }

@ __jpe_hvals_dc → ( Vec i ) { ^ ( __jpe_ints `0 1 2 3 4 5 6 7 8 9 10 11` ) }

@ __jpe_hbits_dc_c → ( Vec i ) { ^ ( __jpe_ints `0 3 1 1 1 1 1 1 1 1 1 0 0 0 0 0` ) }

@ __jpe_hbits_ac_l → ( Vec i ) { ^ ( __jpe_ints `0 2 1 3 3 2 4 3 5 5 4 4 0 0 1 125` ) }

@ __jpe_hvals_ac_l → ( Vec i ) {
    ^ ( __jpe_ints `1 2 3 0 4 17 5 18 33 49 65 6 19 81 97 7 34 113 20 50 129 145 161 8 35 66 177 193 21 82 209 240 36 51 98 114 130 9 10 22 23 24 25 26 37 38 39 40 41 42 52 53 54 55 56 57 58 67 68 69 70 71 72 73 74 83 84 85 86 87 88 89 90 99 100 101 102 103 104 105 106 115 116 117 118 119 120 121 122 131 132 133 134 135 136 137 138 146 147 148 149 150 151 152 153 154 162 163 164 165 166 167 168 169 170 178 179 180 181 182 183 184 185 186 194 195 196 197 198 199 200 201 202 210 211 212 213 214 215 216 217 218 225 226 227 228 229 230 231 232 233 234 241 242 243 244 245 246 247 248 249 250` )
}

@ __jpe_hbits_ac_c → ( Vec i ) { ^ ( __jpe_ints `0 2 1 2 4 4 3 4 7 5 4 4 0 1 2 119` ) }

@ __jpe_hvals_ac_c → ( Vec i ) {
    ^ ( __jpe_ints `0 1 2 3 17 4 5 33 49 6 18 65 81 7 97 113 19 34 50 129 8 20 66 145 161 177 193 9 35 51 82 240 21 98 114 209 10 22 36 52 225 37 241 23 24 25 26 38 39 40 41 42 53 54 55 56 57 58 67 68 69 70 71 72 73 74 83 84 85 86 87 88 89 90 99 100 101 102 103 104 105 106 115 116 117 118 119 120 121 122 130 131 132 133 134 135 136 137 138 146 147 148 149 150 151 152 153 154 162 163 164 165 166 167 168 169 170 178 179 180 181 182 183 184 185 186 194 195 196 197 198 199 200 201 202 210 211 212 213 214 215 216 217 218 226 227 228 229 230 231 232 233 234 242 243 244 245 246 247 248 249 250` )
}

// Canonical code assignment: co[sym] = code, si[sym] = length.
@ __jpe_huff_build ( Vec i ) bits ( Vec i ) vals ( Vec i ) co ( Vec i ) si → v {
    : ~ i code 0
    : ~ i k 0
    : ~ i L 1
    ~ <= L 16 {
        : ~ i c 0
        ~ < c ( _b_i bits - L 1 ) {
            : i sym ( _b_i vals k )
            ( vec_set [i] co sym code )
            ( vec_set [i] si sym L )
            = code + code 1
            = k + k 1
            = c + c 1
        }
        = code << code 1
        = L + L 1
    }
}

// ── Encoder state ─────────────────────────────────────────────────────

: JEnc {
    ( Vec u ) out
    i bbuf i bcnt
    ( Vec i ) qy ( Vec i ) qc  // quant tables, zigzag order
    ( Vec i ) ydc_co ( Vec i ) ydc_si
    ( Vec i ) yac_co ( Vec i ) yac_si
    ( Vec i ) cdc_co ( Vec i ) cdc_si
    ( Vec i ) cac_co ( Vec i ) cac_si
    ( Vec f ) A ( Vec i ) zz
}

// libjpeg quality scaling: 1..100 → per-entry scale, clamped to 1..255.
@ __jpe_scale_q ( Vec i ) base i quality ( Vec i ) zz → ( Vec i ) {
    : ~ i q quality
    ? < q 1 { = q 1 } {}
    ? > q 100 { = q 100 } {}
    : i sf ? < q 50 { / 5000 q } { - 200 * 2 q }
    : ( Vec i ) out ( vec_with_cap [i] 64 )
    : ~ i z 0
    ~ < z 64 {
        : ~ i v / + * ( _b_i base ( _b_i zz z ) ) sf 50 100
        ? < v 1 { = v 1 } {}
        ? > v 255 { = v 255 } {}
        ( vec_push [i] out v )
        = z + z 1
    }
    ^ out
}

@ __jpe_new i quality → *JEnc {
    : *JEnc e # *JEnc ( nurl_malloc Z JEnc )
    = . e out ( vec_new [u] )
    = . e bbuf 0
    = . e bcnt 0
    = . e A ( _idct_basis )
    = . e zz ( _zigzag )
    : ( Vec i ) bl ( __jpe_qbase_luma )
    : ( Vec i ) bc ( __jpe_qbase_chroma )
    = . e qy ( __jpe_scale_q bl quality . e zz )
    = . e qc ( __jpe_scale_q bc quality . e zz )
    ( vec_free [i] bl ) ( vec_free [i] bc )
    = . e ydc_co ( _ivec 256 0 ) = . e ydc_si ( _ivec 256 0 )
    = . e yac_co ( _ivec 256 0 ) = . e yac_si ( _ivec 256 0 )
    = . e cdc_co ( _ivec 256 0 ) = . e cdc_si ( _ivec 256 0 )
    = . e cac_co ( _ivec 256 0 ) = . e cac_si ( _ivec 256 0 )
    : ( Vec i ) b1 ( __jpe_hbits_dc_l )
    : ( Vec i ) v1 ( __jpe_hvals_dc )
    ( __jpe_huff_build b1 v1 . e ydc_co . e ydc_si )
    : ( Vec i ) b2 ( __jpe_hbits_ac_l )
    : ( Vec i ) v2 ( __jpe_hvals_ac_l )
    ( __jpe_huff_build b2 v2 . e yac_co . e yac_si )
    : ( Vec i ) b3 ( __jpe_hbits_dc_c )
    ( __jpe_huff_build b3 v1 . e cdc_co . e cdc_si )
    : ( Vec i ) b4 ( __jpe_hbits_ac_c )
    : ( Vec i ) v4 ( __jpe_hvals_ac_c )
    ( __jpe_huff_build b4 v4 . e cac_co . e cac_si )
    ( vec_free [i] b1 ) ( vec_free [i] v1 ) ( vec_free [i] b2 ) ( vec_free [i] v2 )
    ( vec_free [i] b3 ) ( vec_free [i] b4 ) ( vec_free [i] v4 )
    ^ e
}

@ __jpe_free * JEnc e → v {
    ( vec_free [i] . e qy ) ( vec_free [i] . e qc )
    ( vec_free [i] . e ydc_co ) ( vec_free [i] . e ydc_si )
    ( vec_free [i] . e yac_co ) ( vec_free [i] . e yac_si )
    ( vec_free [i] . e cdc_co ) ( vec_free [i] . e cdc_si )
    ( vec_free [i] . e cac_co ) ( vec_free [i] . e cac_si )
    ( vec_free [f] . e A ) ( vec_free [i] . e zz )
    ( nurl_free e )
}

// ── Bit writer (MSB first, 0xFF byte-stuffed) ─────────────────────────

@ __jpe_bits * JEnc e i code i len → v {
    : ~ i k - len 1
    ~ >= k 0 {
        = . e bbuf | << . e bbuf 1 & >> code k 1
        = . e bcnt + . e bcnt 1
        ? == . e bcnt 8 {
            : i byte & . e bbuf 255
            ( vec_push [u] . e out byte )
            ? == byte 255 { ( vec_push [u] . e out 0 ) } {}
            = . e bbuf 0
            = . e bcnt 0
        } {}
        = k - k 1
    }
}

@ __jpe_flush_bits * JEnc e → v {
    ~ != . e bcnt 0 { ( __jpe_bits e 1 1 ) }
}

// Magnitude category (number of bits) of |v|.
@ __jpe_nbits i v → i {
    : ~ i a ? < v 0 { - 0 v } { v }
    : ~ i n 0
    ~ > a 0 { = n + n 1 = a >> a 1 }
    ^ n
}

// ── Forward DCT + quantise one 8×8 block ──────────────────────────────

// px: 64 samples 0..255 (natural order). out: 64 quantised coefficients in
// ZIGZAG order (what the entropy coder wants).
@ __jpe_fdct_quant * JEnc e ( Vec i ) px ( Vec f ) tmp ( Vec i ) out b chroma → v {
    : ( Vec f ) A . e A
    // rows: tmp[y*8+u] = Σ_x (px-128) A[u*8+x]
    : ~ i y 0
    ~ < y 8 {
        : ~ i u 0
        ~ < u 8 {
            : ~ f s 0.0
            : ~ i x 0
            ~ < x 8 { = s + s * # f - ( _b_i px + * y 8 x ) 128 ( _b_f A + * u 8 x ) = x + x 1 }
            ( vec_set [f] tmp + * y 8 u s )
            = u + u 1
        }
        = y + y 1
    }
    // cols + quantise, straight into zigzag order
    : ( Vec i ) qt ? chroma { . e qc } { . e qy }
    : ~ i z 0
    ~ < z 64 {
        : i nat ( _b_i . e zz z )
        : i u & nat 7
        : i vv >> nat 3
        : ~ f s2 0.0
        : ~ i yy 0
        ~ < yy 8 { = s2 + s2 * ( _b_f tmp + * yy 8 u ) ( _b_f A + * vv 8 yy ) = yy + yy 1 }
        : f coef * s2 0.25
        : f qf # f ( _b_i qt z )
        : f r / coef qf
        ( vec_set [i] out z ? >= r 0.0 { # i + r 0.5 } { - 0 # i + - 0.0 r 0.5 } )
        = z + z 1
    }
}

// ── Entropy-code one quantised block (zigzag order) ───────────────────

// Returns the block's DC value so the caller can carry the predictor.
@ __jpe_code_block * JEnc e ( Vec i ) zq i pred b chroma → i {
    : ( Vec i ) dc_co ? chroma { . e cdc_co } { . e ydc_co }
    : ( Vec i ) dc_si ? chroma { . e cdc_si } { . e ydc_si }
    : ( Vec i ) ac_co ? chroma { . e cac_co } { . e yac_co }
    : ( Vec i ) ac_si ? chroma { . e cac_si } { . e yac_si }
    : i dc ( _b_i zq 0 )
    : i diff - dc pred
    : i ds ( __jpe_nbits diff )
    ( __jpe_bits e ( _b_i dc_co ds ) ( _b_i dc_si ds ) )
    ? > ds 0 {
        : i dbits ? < diff 0 { + diff - << 1 ds 1 } { diff }
        ( __jpe_bits e dbits ds )
    } {}
    : ~ i run 0
    : ~ i z 1
    ~ < z 64 {
        : i v ( _b_i zq z )
        ? == v 0 { = run + run 1 } {
            ~ >= run 16 {
                ( __jpe_bits e ( _b_i ac_co 240 ) ( _b_i ac_si 240 ) )  // ZRL
                = run - run 16
            }
            : i sz ( __jpe_nbits v )
            : i sym | << run 4 sz
            ( __jpe_bits e ( _b_i ac_co sym ) ( _b_i ac_si sym ) )
            : i vbits ? < v 0 { + v - << 1 sz 1 } { v }
            ( __jpe_bits e vbits sz )
            = run 0
        }
        = z + z 1
    }
    ? > run 0 {
        ( __jpe_bits e ( _b_i ac_co 0 ) ( _b_i ac_si 0 ) )  // EOB
    } {}
    ^ dc
}

// ── Headers ───────────────────────────────────────────────────────────

@ __jpe_marker ( Vec u ) out i m → v {
    ( vec_push [u] out 255 ) ( vec_push [u] out m )
}

@ __jpe_headers * JEnc e i W i H i nc i hs i vs → v {
    : ( Vec u ) out . e out
    ( __jpe_marker out 216 )  // SOI
    // APP0 JFIF
    ( __jpe_marker out 224 )
    ( _push_u16be out 16 )
    ( bytes_extend_str out `JFIF` )
    ( vec_push [u] out 0 ) ( vec_push [u] out 1 ) ( vec_push [u] out 1 )
    ( vec_push [u] out 0 )
    ( _push_u16be out 1 ) ( _push_u16be out 1 )
    ( vec_push [u] out 0 ) ( vec_push [u] out 0 )
    // DQT (luma; chroma too when colour)
    ( __jpe_marker out 219 )
    ( _push_u16be out + 2 * + 1 64 ? == nc 3 { 2 } { 1 } )
    ( vec_push [u] out 0 )
    : ~ i z 0
    ~ < z 64 { ( vec_push [u] out ( _b_i . e qy z ) ) = z + z 1 }
    ? == nc 3 {
        ( vec_push [u] out 1 )
        : ~ i z2 0
        ~ < z2 64 { ( vec_push [u] out ( _b_i . e qc z2 ) ) = z2 + z2 1 }
    } {}
    // SOF0
    ( __jpe_marker out 192 )
    ( _push_u16be out + 8 * nc 3 )
    ( vec_push [u] out 8 )
    ( _push_u16be out H )
    ( _push_u16be out W )
    ( vec_push [u] out nc )
    ( vec_push [u] out 1 )
    ( vec_push [u] out | << hs 4 vs )
    ( vec_push [u] out 0 )
    ? == nc 3 {
        ( vec_push [u] out 2 ) ( vec_push [u] out 17 ) ( vec_push [u] out 1 )
        ( vec_push [u] out 3 ) ( vec_push [u] out 17 ) ( vec_push [u] out 1 )
    } {}
    // DHT
    ( __jpe_dht e 0 0 ( __jpe_hbits_dc_l ) ( __jpe_hvals_dc ) )
    ( __jpe_dht e 1 0 ( __jpe_hbits_ac_l ) ( __jpe_hvals_ac_l ) )
    ? == nc 3 {
        ( __jpe_dht e 0 1 ( __jpe_hbits_dc_c ) ( __jpe_hvals_dc ) )
        ( __jpe_dht e 1 1 ( __jpe_hbits_ac_c ) ( __jpe_hvals_ac_c ) )
    } {}
    // SOS
    ( __jpe_marker out 218 )
    ( _push_u16be out + 6 * nc 2 )
    ( vec_push [u] out nc )
    ( vec_push [u] out 1 ) ( vec_push [u] out 0 )
    ? == nc 3 {
        ( vec_push [u] out 2 ) ( vec_push [u] out 17 )
        ( vec_push [u] out 3 ) ( vec_push [u] out 17 )
    } {}
    ( vec_push [u] out 0 ) ( vec_push [u] out 63 ) ( vec_push [u] out 0 )
}

// Emit one DHT segment; consumes (frees) bits/vals.
@ __jpe_dht * JEnc e i class i id ( Vec i ) bits ( Vec i ) vals → v {
    : ( Vec u ) out . e out
    : i nv ( vec_len [i] vals )
    ( __jpe_marker out 196 )
    ( _push_u16be out + + 2 17 nv )
    ( vec_push [u] out | << class 4 id )
    : ~ i L 0
    ~ < L 16 { ( vec_push [u] out ( _b_i bits L ) ) = L + L 1 }
    : ~ i k 0
    ~ < k nv { ( vec_push [u] out ( _b_i vals k ) ) = k + k 1 }
    ( vec_free [i] bits ) ( vec_free [i] vals )
}

// ── Planes ────────────────────────────────────────────────────────────

// Build the (possibly box-downsampled) component plane, converting RGB →
// YCbCr on the fly. comp: 0 Y, 1 Cb, 2 Cr. step = hmax/hc (1 or 2), same
// vertically. Returns a pw×ph Vec i.
@ __jpe_plane Image im i comp i stepx i stepy i pw i ph → ( Vec i ) {
    : i W . im width
    : i H . im height
    : i ch . im channels
    : b grey <= ch 2
    : ( Vec i ) pl ( vec_with_cap [i] * pw ph )
    : ~ i py 0
    ~ < py ph {
        : ~ i px 0
        ~ < px pw {
            : ~ f acc 0.0
            : ~ i cnt 0
            : ~ i sy * py stepy
            : i ey + * py stepy stepy
            ~ < sy ey {
                : ~ i sx * px stepx
                : i ex + * px stepx stepx
                ~ < sx ex {
                    : i cx ? >= sx W { - W 1 } { sx }
                    : i cy ? >= sy H { - H 1 } { sy }
                    ? grey {
                        = acc + acc # f ( image_get im cx cy 0 )
                    } {
                        : f r # f ( image_get im cx cy 0 )
                        : f g # f ( image_get im cx cy 1 )
                        : f b # f ( image_get im cx cy 2 )
                        ? == comp 0 { = acc + acc + + * 0.299 r * 0.587 g * 0.114 b } {
                            ? == comp 1 { = acc + acc + 128.0 + + * -0.168736 r * -0.331264 g * 0.5 b } {
                                = acc + acc + 128.0 + + * 0.5 r * -0.418688 g * -0.081312 b
                            } }
                    }
                    = cnt + cnt 1
                    = sx + sx 1
                }
                = sy + sy 1
            }
            : f m / acc # f cnt
            : ~ i vi # i + m 0.5
            ? < vi 0 { = vi 0 } {}
            ? > vi 255 { = vi 255 } {}
            ( vec_push [i] pl vi )
            = px + px 1
        }
        = py + py 1
    }
    ^ pl
}

// Copy the 8×8 block at (bx*8, by*8) out of a plane, replicating edges.
@ __jpe_block_from ( Vec i ) pl i pw i ph i bx i by ( Vec i ) px → v {
    : ~ i y 0
    ~ < y 8 {
        : ~ i sy + * by 8 y
        ? >= sy ph { = sy - ph 1 } {}
        : ~ i x 0
        ~ < x 8 {
            : ~ i sx + * bx 8 x
            ? >= sx pw { = sx - pw 1 } {}
            ( vec_set [i] px + * y 8 x ( _b_i pl + * sy pw sx ) )
            = x + x 1
        }
        = y + y 1
    }
}

// ── Public entry ──────────────────────────────────────────────────────

// subsamp: 0 = 4:4:4, 1 = 4:2:2, 2 = 4:2:0 (ignored for greyscale).
@ jpeg_encode_sub Image im i quality i subsamp → ( Vec u ) {
    : i W . im width
    : i H . im height
    ? || <= W 0 <= H 0 { ^ ( vec_new [u] ) } {}
    : b grey <= . im channels 2
    : i nc ? grey { 1 } { 3 }
    : i hs ? grey { 1 } { ? == subsamp 0 { 1 } { 2 } }
    : i vs ? grey { 1 } { ? == subsamp 2 { 2 } { 1 } }

    : *JEnc e ( __jpe_new quality )
    ( __jpe_headers e W H nc hs vs )

    : i mcux / + W - * hs 8 1 * hs 8
    : i mcuy / + H - * vs 8 1 * vs 8

    // planes: Y at full size, chroma downsampled by hs/vs
    : i ypw * * mcux hs 8
    : i yph * * mcuy vs 8
    : ( Vec i ) py ( __jpe_plane im 0 1 1 ypw yph )
    : ~ ( Vec i ) pcb ( vec_new [i] )
    : ~ ( Vec i ) pcr ( vec_new [i] )
    : i cpw * mcux 8
    : i cph * mcuy 8
    ? == nc 3 {
        ( vec_free [i] pcb ) ( vec_free [i] pcr )
        = pcb ( __jpe_plane im 1 hs vs cpw cph )
        = pcr ( __jpe_plane im 2 hs vs cpw cph )
    } {}

    : ( Vec i ) blk ( _ivec 64 0 )
    : ( Vec i ) zq ( _ivec 64 0 )
    : ( Vec f ) tmp ( vec_with_cap [f] 64 )
    : ~ i tz 0
    ~ < tz 64 { ( vec_push [f] tmp 0.0 ) = tz + tz 1 }

    : ~ i predy 0
    : ~ i predcb 0
    : ~ i predcr 0
    : ~ i my 0
    ~ < my mcuy {
        : ~ i mx 0
        ~ < mx mcux {
            : ~ i by 0
            ~ < by vs {
                : ~ i bx 0
                ~ < bx hs {
                    ( __jpe_block_from py ypw yph + * mx hs bx + * my vs by blk )
                    ( __jpe_fdct_quant e blk tmp zq F )
                    = predy ( __jpe_code_block e zq predy F )
                    = bx + bx 1
                }
                = by + by 1
            }
            ? == nc 3 {
                ( __jpe_block_from pcb cpw cph mx my blk )
                ( __jpe_fdct_quant e blk tmp zq T )
                = predcb ( __jpe_code_block e zq predcb T )
                ( __jpe_block_from pcr cpw cph mx my blk )
                ( __jpe_fdct_quant e blk tmp zq T )
                = predcr ( __jpe_code_block e zq predcr T )
            } {}
            = mx + mx 1
        }
        = my + my 1
    }

    ( __jpe_flush_bits e )
    ( __jpe_marker . e out 217 )  // EOI

    ( vec_free [i] py ) ( vec_free [i] pcb ) ( vec_free [i] pcr )
    ( vec_free [i] blk ) ( vec_free [i] zq ) ( vec_free [f] tmp )
    : ( Vec u ) out . e out
    ( __jpe_free e )
    ^ out
}

// Quality-driven default: 4:2:0 below 90, 4:4:4 from 90 up (mirrors what
// mainstream encoders pick at high quality).
@ jpeg_encode Image im i quality → ( Vec u ) {
    ^ ( jpeg_encode_sub im quality ? >= quality 90 { 0 } { 2 } )
}
