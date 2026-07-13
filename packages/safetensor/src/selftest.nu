// packages/safetensor/src/selftest.nu — the parser meets files that lie.
//
// The container has exactly one interesting property: every tensor's bytes are
// addressed by offsets the FILE supplies. So the whole test is: craft headers
// whose offsets are wrong in every way a header can be wrong, and require a
// clean error each time — never a crash, never a read outside the mapping,
// never an allocation sized by a number we were handed.
//
// A round-trip check comes first, so the negative cases are known to be
// rejected for the RIGHT reason: the same bytes with a truthful header parse.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `src/safetensor.nu`

: ~ i __st_pass 0
: ~ i __st_fail 0

@ __ok b cond s name → v {
    ? cond {
        = __st_pass + __st_pass 1
        : String m ( string_from `  PASS ` )
        ( string_push_str m name )
        ( nurl_print ( string_data m ) ) ( nurl_print `\n` )
        ( string_free m )
    } {
        = __st_fail + __st_fail 1
        : String m ( string_from `  FAIL ` )
        ( string_push_str m name )
        ( nurl_print ( string_data m ) ) ( nurl_print `\n` )
        ( string_free m )
    }
}

// Build an in-memory safetensors image: `hdr` is the JSON header text, `data`
// the tensor-data region appended after it.
@ __st_image s hdr ( Vec u ) data → ( Vec u ) {
    : ( Vec u ) img ( vec_new [u] )
    : i hl ( nurl_str_len hdr )
    // u64 LE header length
    : ~ i k 0
    ~ < k 8 {
        ( vec_push [u] img # u & 255 >> hl * k 8 )
        = k + k 1
    }
    = k 0
    ~ < k hl {
        ( vec_push [u] img # u ( nurl_str_get hdr k ) )
        = k + k 1
    }
    = k 0
    ~ < k ( vec_len [u] data ) {
        ?? ( vec_get [u] data k ) { T b → { ( vec_push [u] img b ) } F → {} }
        = k + k 1
    }
    ^ img
}

// f32 little-endian bytes for a 4-element tensor 1,2,3,4
@ __st_data4 → ( Vec u ) {
    : ( Vec u ) d ( vec_new [u] )
    : ~ i k 0
    ~ < k 4 {
        ( bytes_push_u32_le d # u32 ( f32_to_bits # f32 # f + k 1 ) )
        = k + k 1
    }
    ^ d
}

// A header must be REJECTED. TAKES OWNERSHIP of `data` — every call site passes
// a fresh `( __st_data4 )`, and a Vec handed to a call is not dropped for us.
// (The image is freed here too; the parser borrows it, so a successful parse is
// closed before the buffer goes away.)
@ __st_reject s hdr ( Vec u ) data s name → v {
    : ( Vec u ) img ( __st_image hdr data )
    ( vec_free [u] data )
    ?? ( st_parse_bytes img ) {
        T st → {
            ( st_close st )
            ( __ok F name )
        }
        F e → {
            ( string_free e )
            ( __ok T name )
        }
    }
    ( vec_free [u] img )
}

@ st_selftest → i {
    ( nurl_print `safetensor selftest — a header that lies must be a clean error` ) ( nurl_print `\n` )

    // ── the honest file parses, and its numbers come back ──────────────
    : ( Vec u ) d4 ( __st_data4 )
    : ( Vec u ) good ( __st_image
    `{"t":{"dtype":"F32","shape":[2,2],"data_offsets":[0,16]}}` d4 )
    ?? ( st_parse_bytes good ) {
        T st → {
            ( __ok == 1 ( st_n_tensors st ) `honest file: one tensor` )
            : i idx ( st_find_tensor st `t` )
            ( __ok >= idx 0 `honest file: tensor found by name` )
            ?? ( st_dequant st idx ) {
                T raw → {
                    : *u p ( vec_data [u] raw )
                    : ~ b eq == 16 ( vec_len [u] raw )
                    : ~ i k 0
                    ~ < k 4 {
                        : f v # f ( bits_to_f32 ( __st_u32 p * k 4 ) )
                        ? != v # f + k 1 { = eq F } {}
                        = k + k 1
                    }
                    ( __ok eq `honest file: f32 values round-trip (1,2,3,4)` )
                    ( vec_free [u] raw )
                }
                F e → {
                    ( string_free e )
                    ( __ok F `honest file: dequant` )
                }
            }
            ( st_close st )
        }
        F e → {
            ( string_free e )
            ( __ok F `honest file parses` )
        }
    }
    ( vec_free [u] good )
    ( vec_free [u] d4 )

    // ── every way a header can lie ─────────────────────────────────────
    // data_offsets past the end of the data region
    ( __st_reject `{"t":{"dtype":"F32","shape":[2,2],"data_offsets":[0,1600]}}`
    ( __st_data4 ) `rejects: extent runs past the end of the file` )

    // extent does not match dtype × shape (4 f32 = 16 bytes, not 12)
    ( __st_reject `{"t":{"dtype":"F32","shape":[2,2],"data_offsets":[0,12]}}`
    ( __st_data4 ) `rejects: extent disagrees with dtype × shape` )

    // reversed range
    ( __st_reject `{"t":{"dtype":"F32","shape":[2,2],"data_offsets":[16,0]}}`
    ( __st_data4 ) `rejects: data_offsets reversed (b < a)` )

    // negative offset
    ( __st_reject `{"t":{"dtype":"F32","shape":[2,2],"data_offsets":[-16,0]}}`
    ( __st_data4 ) `rejects: negative offset` )

    // shape that would overflow i64 if multiplied without a check
    ( __st_reject
    `{"t":{"dtype":"F32","shape":[4611686018427387904,4],"data_offsets":[0,16]}}`
    ( __st_data4 ) `rejects: shape whose element count overflows` )

    // unknown dtype
    ( __st_reject `{"t":{"dtype":"F1000","shape":[2,2],"data_offsets":[0,16]}}`
    ( __st_data4 ) `rejects: unknown dtype` )

    // missing shape
    ( __st_reject `{"t":{"dtype":"F32","data_offsets":[0,16]}}`
    ( __st_data4 ) `rejects: tensor without a shape` )

    // missing data_offsets
    ( __st_reject `{"t":{"dtype":"F32","shape":[2,2]}}`
    ( __st_data4 ) `rejects: tensor without data_offsets` )

    // header is not JSON at all
    ( __st_reject `not json {{{` ( __st_data4 ) `rejects: header is not valid JSON` )

    // header is JSON but not an object
    ( __st_reject `[1,2,3]` ( __st_data4 ) `rejects: header JSON is not an object` )

    // tensor entry is a scalar, not an object
    ( __st_reject `{"t":7}` ( __st_data4 ) `rejects: tensor entry is not an object` )

    // ── a header length that lies about itself ─────────────────────────
    // 8-byte prefix claiming a header far larger than the file
    : ( Vec u ) huge ( vec_new [u] )
    : ~ i k 0
    ~ < k 8 {
        ( vec_push [u] huge # u ? < k 6 255 0 )
        = k + k 1
    }
    ~ < k 40 {
        ( vec_push [u] huge # u 65 )
        = k + k 1
    }
    ?? ( st_parse_bytes huge ) {
        T st → {
            ( st_close st )
            ( __ok F `rejects: header length larger than the file` )
        }
        F e → {
            ( string_free e )
            ( __ok T `rejects: header length larger than the file` )
        }
    }
    ( vec_free [u] huge )

    // truncated file (fewer than 8 bytes)
    : ( Vec u ) tiny ( vec_new [u] )
    ( vec_push [u] tiny # u 1 )
    ( vec_push [u] tiny # u 2 )
    ?? ( st_parse_bytes tiny ) {
        T st → {
            ( st_close st )
            ( __ok F `rejects: file shorter than the 8-byte length prefix` )
        }
        F e → {
            ( string_free e )
            ( __ok T `rejects: file shorter than the 8-byte length prefix` )
        }
    }
    ( vec_free [u] tiny )

    // ── the widening dtypes ────────────────────────────────────────────
    // F16 0x3C00 = 1.0, 0x4000 = 2.0 ; BF16 0x3F80 = 1.0, 0x4000 = 2.0
    : ( Vec u ) f16d ( vec_new [u] )
    ( vec_push [u] f16d # u 0 ) ( vec_push [u] f16d # u 60 )
    ( vec_push [u] f16d # u 0 ) ( vec_push [u] f16d # u 64 )
    : ( Vec u ) f16img ( __st_image
    `{"t":{"dtype":"F16","shape":[2],"data_offsets":[0,4]}}` f16d )
    ( vec_free [u] f16d )
    ?? ( st_parse_bytes f16img ) {
        T st → {
            ?? ( st_dequant st 0 ) {
                T raw → {
                    : *u p ( vec_data [u] raw )
                    : f a # f ( bits_to_f32 ( __st_u32 p 0 ) )
                    : f b # f ( bits_to_f32 ( __st_u32 p 4 ) )
                    ( __ok & == a 1.0 == b 2.0 `F16 widens to f32 (1.0, 2.0)` )
                    ( vec_free [u] raw )
                }
                F e → {
                    ( string_free e )
                    ( __ok F `F16 widens to f32` )
                }
            }
            ( st_close st )
        }
        F e → {
            ( string_free e )
            ( __ok F `F16 file parses` )
        }
    }
    ( vec_free [u] f16img )

    : ( Vec u ) bf16d ( vec_new [u] )
    ( vec_push [u] bf16d # u 128 ) ( vec_push [u] bf16d # u 63 )
    ( vec_push [u] bf16d # u 0 ) ( vec_push [u] bf16d # u 64 )
    : ( Vec u ) bfimg ( __st_image
    `{"t":{"dtype":"BF16","shape":[2],"data_offsets":[0,4]}}` bf16d )
    ( vec_free [u] bf16d )
    ?? ( st_parse_bytes bfimg ) {
        T st → {
            ?? ( st_dequant st 0 ) {
                T raw → {
                    : *u p ( vec_data [u] raw )
                    : f a # f ( bits_to_f32 ( __st_u32 p 0 ) )
                    : f b # f ( bits_to_f32 ( __st_u32 p 4 ) )
                    ( __ok & == a 1.0 == b 2.0 `BF16 widens to f32 (1.0, 2.0)` )
                    ( vec_free [u] raw )
                }
                F e → {
                    ( string_free e )
                    ( __ok F `BF16 widens to f32` )
                }
            }
            ( st_close st )
        }
        F e → {
            ( string_free e )
            ( __ok F `BF16 file parses` )
        }
    }
    ( vec_free [u] bfimg )

    // ── an element range must stay inside the tensor ───────────────────
    : ( Vec u ) rdata ( __st_data4 )
    : ( Vec u ) rimg ( __st_image
    `{"t":{"dtype":"F32","shape":[2,2],"data_offsets":[0,16]}}` rdata )
    ( vec_free [u] rdata )
    ?? ( st_parse_bytes rimg ) {
        T st → {
            ?? ( st_dequant_range st 0 2 2 ) {
                T raw → {
                    : *u p ( vec_data [u] raw )
                    : f a # f ( bits_to_f32 ( __st_u32 p 0 ) )
                    ( __ok & == 8 ( vec_len [u] raw ) == a 3.0 `element range [2,4) is exact` )
                    ( vec_free [u] raw )
                }
                F e → {
                    ( string_free e )
                    ( __ok F `element range` )
                }
            }
            ?? ( st_dequant_range st 0 3 2 ) {
                T raw → {
                    ( vec_free [u] raw )
                    ( __ok F `rejects: element range running past the tensor` )
                }
                F e → {
                    ( string_free e )
                    ( __ok T `rejects: element range running past the tensor` )
                }
            }
            ( st_close st )
        }
        F e → {
            ( string_free e )
            ( __ok F `range file parses` )
        }
    }
    ( vec_free [u] rimg )

    : String m ( string_from `safetensor selftest: ` )
    ( string_push_int m __st_pass )
    ( string_push_str m ` passed, ` )
    ( string_push_int m __st_fail )
    ( string_push_str m ` failed` )
    ( nurl_print ( string_data m ) ) ( nurl_print `\n` )
    ( string_free m )
    ^ ? > __st_fail 0 1 0
}
