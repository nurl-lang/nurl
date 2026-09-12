// Test adapter: a fixed all-scalar schema, packed repeated int32, nested
// messages and unknown fields. The Python oracle owns schema generation.
$ `stdlib/ext/protobuf.nu`
$ `stdlib/core/io.nu`

@ transcode inout ProtoReader r ( Vec u ) out → !v ProtoError {
    ~ ( proto_more r ) {
        : ProtoReader before r
        : ProtoTag tag \ ( proto_read_tag r )
        ?? . tag number {
            1 → {
                \ ( proto_expect tag 1 ( proto_offset before ) )
                : f value \ ( proto_read_double r )
                \ ( proto_write_double out 1 value )
            }
            2 → {
                \ ( proto_expect tag 5 ( proto_offset before ) )
                : f32 value \ ( proto_read_float r )
                \ ( proto_write_float out 2 value )
            }
            3 → {
                \ ( proto_expect tag 0 ( proto_offset before ) )
                : i value \ ( proto_read_int64 r )
                \ ( proto_write_int64 out 3 value )
            }
            4 → {
                \ ( proto_expect tag 0 ( proto_offset before ) )
                : u64 value \ ( proto_read_uint64 r )
                \ ( proto_write_uint64 out 4 value )
            }
            5 → {
                \ ( proto_expect tag 0 ( proto_offset before ) )
                : i32 value \ ( proto_read_int32 r )
                \ ( proto_write_int32 out 5 value )
            }
            6 → {
                \ ( proto_expect tag 1 ( proto_offset before ) )
                : u64 value \ ( proto_read_fixed64 r )
                \ ( proto_write_fixed64 out 6 value )
            }
            7 → {
                \ ( proto_expect tag 5 ( proto_offset before ) )
                : u32 value \ ( proto_read_fixed32 r )
                \ ( proto_write_fixed32 out 7 value )
            }
            8 → {
                \ ( proto_expect tag 0 ( proto_offset before ) )
                : b value \ ( proto_read_bool r )
                \ ( proto_write_bool out 8 value )
            }
            9 → {
                \ ( proto_expect tag 2 ( proto_offset before ) )
                : String value \ ( proto_read_string r )
                : !v ProtoError status ( proto_write_string out 9 value )
                ( string_free value )
                \ status
            }
            10 → {
                \ ( proto_expect tag 2 ( proto_offset before ) )
                : ( Slice u ) value \ ( proto_read_bytes r )
                \ ( proto_write_slice out 10 value )
            }
            11 → {
                \ ( proto_expect tag 0 ( proto_offset before ) )
                : u32 value \ ( proto_read_uint32 r )
                \ ( proto_write_uint32 out 11 value )
            }
            12 → {
                \ ( proto_expect tag 5 ( proto_offset before ) )
                : i32 value \ ( proto_read_sfixed32 r )
                \ ( proto_write_sfixed32 out 12 value )
            }
            13 → {
                \ ( proto_expect tag 1 ( proto_offset before ) )
                : i value \ ( proto_read_sfixed64 r )
                \ ( proto_write_sfixed64 out 13 value )
            }
            14 → {
                \ ( proto_expect tag 0 ( proto_offset before ) )
                : i32 value \ ( proto_read_sint32 r )
                \ ( proto_write_sint32 out 14 value )
            }
            15 → {
                \ ( proto_expect tag 0 ( proto_offset before ) )
                : i value \ ( proto_read_sint64 r )
                \ ( proto_write_sint64 out 15 value )
            }
            16 → {
                ? == . tag wire 2 {
                    : ~ ProtoReader packed \ ( proto_read_packed r )
                    ~ ( proto_more packed ) {
                        : i32 x \ ( proto_read_int32 packed )
                        \ ( proto_write_int32 out 16 x )
                    }
                } {
                    \ ( proto_expect tag 0 ( proto_offset before ) )
                    : i32 x \ ( proto_read_int32 r )
                    \ ( proto_write_int32 out 16 x )
                }
            }
            17 → {
                \ ( proto_expect tag 2 ( proto_offset before ) )
                : ~ ProtoReader child \ ( proto_read_message r )
                : ( Vec u ) encoded ( vec_new [u] )
                : !v ProtoError status ( transcode child encoded )
                ?? status {
                    T → {
                        : !v ProtoError write_status ( proto_write_bytes out 17 encoded )
                        ( vec_free [u] encoded )
                        \ write_status
                    }
                    F e → { ( vec_free [u] encoded ) ^ @ !v ProtoError { F e } }
                }
            }
            18 → {
                \ ( proto_expect tag 0 ( proto_offset before ) )
                : i32 value \ ( proto_read_int32 r )
                \ ( proto_write_int32 out 18 value )
            }
            _ → {
                = r before
                : ( Slice u ) raw \ ( proto_read_raw_field r )
                : *u data . raw data
                : ~ i k 0
                ~ < k . raw len { ( vec_push [u] out . data k ) = k + k 1 }
            }
        }
    }
    ^ @ !v ProtoError { T }
}

@ process ( Vec u ) bytes b validate → v {
    : ( Vec u ) out ( vec_new [u] )
    : ~ ! v ProtoError status @ !v ProtoError { T }
    ? validate { = status ( proto_validate bytes ) } {
        ?? ( proto_reader bytes ) {
            T reader → {
                : ~ ProtoReader r reader
                = status ( transcode r out )
            }
            F e → { = status @ !v ProtoError { F e } }
        }
    }
    ?? status {
        T → {
            ( nurl_print `ok ` )
            : String hex ( bytes_to_hex out )
            ( nurl_print ( string_data hex ) )
            ( string_free hex )
        }
        F e → { ( nurl_print `err ` ) ( nurl_print ( proto_error_name . e code ) ) }
    }
    ( nurl_print `\n` )
    ( vec_free [u] out )
}

@ main → i {
    : ~ b done F
    ~ ! done {
        : String line ( read_line )
        ? ( stdin_eof ) { = done T } {
            : b validate == ( string_get line 0 ) 118
            : String hex ( string_substr line 2 - ( string_len line ) 2 )
            ? == ( string_len hex ) 0 {
                : ( Vec u ) empty ( vec_new [u] )
                ( process empty validate )
                ( vec_free [u] empty )
            } {
                ?? ( bytes_from_hex ( string_data hex ) ) {
                    T bytes → { ( process bytes validate ) ( vec_free [u] bytes ) }
                    F _ → { ( nurl_print `bad test hex\n` ) }
                }
            }
            ( string_free hex )
        }
        ( string_free line )
    }
    ^ 0
}
