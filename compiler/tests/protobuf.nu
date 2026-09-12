// Protocol Buffers wire vectors, typed round trips and failure atomicity.
$ `stdlib/ext/protobuf.nu`

@ check b condition s message → v {
    ? ! condition { ( nurl_print message ) ( nurl_print `\n` ) ( nurl_exit 1 ) } {}
}

@ hx s hex → ( Vec u ) {
    ? == ( nurl_str_len hex ) 0 { ^ ( vec_new [u] ) } {}
    ^ ?? ( bytes_from_hex hex ) { T bytes → bytes F _ → { ( nurl_exit 2 ) ( vec_new [u] ) } }
}

@ same ( Vec u ) bytes s hex → v {
    : ( Vec u ) expected ( hx hex )
    ( check ( bytes_eq bytes expected ) `wire bytes differ` )
    ( vec_free [u] expected )
}

@ vectors → !v ProtoError {
    : ( Vec u ) b0 ( vec_new [u] )
    \ ( proto_put_uint64 b0 # u64 0 )
    ( same b0 `00` )
    : ~ ProtoReader r0 \ ( proto_reader b0 )
    : u64 v0 \ ( proto_read_uint64 r0 )
    ( check == v0 # u64 0 `uint64 roundtrip 0` )
    ( check ! ( proto_more r0 ) `scalar end` )
    ( vec_free [u] b0 )
    : ( Vec u ) f0 ( vec_new [u] )
    \ ( proto_write_uint64 f0 1 # u64 0 )
    ( same f0 `0800` )
    \ ( proto_validate f0 )
    ( vec_free [u] f0 )
    : ( Vec u ) b1 ( vec_new [u] )
    \ ( proto_put_uint64 b1 # u64 127 )
    ( same b1 `7f` )
    : ~ ProtoReader r1 \ ( proto_reader b1 )
    : u64 v1 \ ( proto_read_uint64 r1 )
    ( check == v1 # u64 127 `uint64 roundtrip 1` )
    ( check ! ( proto_more r1 ) `scalar end` )
    ( vec_free [u] b1 )
    : ( Vec u ) f1 ( vec_new [u] )
    \ ( proto_write_uint64 f1 1 # u64 127 )
    ( same f1 `087f` )
    \ ( proto_validate f1 )
    ( vec_free [u] f1 )
    : ( Vec u ) b2 ( vec_new [u] )
    \ ( proto_put_uint64 b2 # u64 128 )
    ( same b2 `8001` )
    : ~ ProtoReader r2 \ ( proto_reader b2 )
    : u64 v2 \ ( proto_read_uint64 r2 )
    ( check == v2 # u64 128 `uint64 roundtrip 2` )
    ( check ! ( proto_more r2 ) `scalar end` )
    ( vec_free [u] b2 )
    : ( Vec u ) f2 ( vec_new [u] )
    \ ( proto_write_uint64 f2 1 # u64 128 )
    ( same f2 `088001` )
    \ ( proto_validate f2 )
    ( vec_free [u] f2 )
    : ( Vec u ) b3 ( vec_new [u] )
    \ ( proto_put_uint64 b3 # u64 150 )
    ( same b3 `9601` )
    : ~ ProtoReader r3 \ ( proto_reader b3 )
    : u64 v3 \ ( proto_read_uint64 r3 )
    ( check == v3 # u64 150 `uint64 roundtrip 3` )
    ( check ! ( proto_more r3 ) `scalar end` )
    ( vec_free [u] b3 )
    : ( Vec u ) f3 ( vec_new [u] )
    \ ( proto_write_uint64 f3 1 # u64 150 )
    ( same f3 `089601` )
    \ ( proto_validate f3 )
    ( vec_free [u] f3 )
    : ( Vec u ) b4 ( vec_new [u] )
    \ ( proto_put_uint64 b4 # u64 16384 )
    ( same b4 `808001` )
    : ~ ProtoReader r4 \ ( proto_reader b4 )
    : u64 v4 \ ( proto_read_uint64 r4 )
    ( check == v4 # u64 16384 `uint64 roundtrip 4` )
    ( check ! ( proto_more r4 ) `scalar end` )
    ( vec_free [u] b4 )
    : ( Vec u ) f4 ( vec_new [u] )
    \ ( proto_write_uint64 f4 1 # u64 16384 )
    ( same f4 `08808001` )
    \ ( proto_validate f4 )
    ( vec_free [u] f4 )
    : ( Vec u ) b5 ( vec_new [u] )
    \ ( proto_put_uint64 b5 # u64 4294967295 )
    ( same b5 `ffffffff0f` )
    : ~ ProtoReader r5 \ ( proto_reader b5 )
    : u64 v5 \ ( proto_read_uint64 r5 )
    ( check == v5 # u64 4294967295 `uint64 roundtrip 5` )
    ( check ! ( proto_more r5 ) `scalar end` )
    ( vec_free [u] b5 )
    : ( Vec u ) f5 ( vec_new [u] )
    \ ( proto_write_uint64 f5 1 # u64 4294967295 )
    ( same f5 `08ffffffff0f` )
    \ ( proto_validate f5 )
    ( vec_free [u] f5 )
    : ( Vec u ) b6 ( vec_new [u] )
    \ ( proto_put_uint64 b6 # u64 9223372036854775807 )
    ( same b6 `ffffffffffffffff7f` )
    : ~ ProtoReader r6 \ ( proto_reader b6 )
    : u64 v6 \ ( proto_read_uint64 r6 )
    ( check == v6 # u64 9223372036854775807 `uint64 roundtrip 6` )
    ( check ! ( proto_more r6 ) `scalar end` )
    ( vec_free [u] b6 )
    : ( Vec u ) f6 ( vec_new [u] )
    \ ( proto_write_uint64 f6 1 # u64 9223372036854775807 )
    ( same f6 `08ffffffffffffffff7f` )
    \ ( proto_validate f6 )
    ( vec_free [u] f6 )
    : ( Vec u ) b7 ( vec_new [u] )
    \ ( proto_put_uint64 b7 # u64 9223372036854775808 )
    ( same b7 `80808080808080808001` )
    : ~ ProtoReader r7 \ ( proto_reader b7 )
    : u64 v7 \ ( proto_read_uint64 r7 )
    ( check == v7 # u64 9223372036854775808 `uint64 roundtrip 7` )
    ( check ! ( proto_more r7 ) `scalar end` )
    ( vec_free [u] b7 )
    : ( Vec u ) f7 ( vec_new [u] )
    \ ( proto_write_uint64 f7 1 # u64 9223372036854775808 )
    ( same f7 `0880808080808080808001` )
    \ ( proto_validate f7 )
    ( vec_free [u] f7 )
    : ( Vec u ) b8 ( vec_new [u] )
    \ ( proto_put_uint64 b8 # u64 18446744073709551615 )
    ( same b8 `ffffffffffffffffff01` )
    : ~ ProtoReader r8 \ ( proto_reader b8 )
    : u64 v8 \ ( proto_read_uint64 r8 )
    ( check == v8 # u64 18446744073709551615 `uint64 roundtrip 8` )
    ( check ! ( proto_more r8 ) `scalar end` )
    ( vec_free [u] b8 )
    : ( Vec u ) f8 ( vec_new [u] )
    \ ( proto_write_uint64 f8 1 # u64 18446744073709551615 )
    ( same f8 `08ffffffffffffffffff01` )
    \ ( proto_validate f8 )
    ( vec_free [u] f8 )
    : ( Vec u ) b9 ( vec_new [u] )
    \ ( proto_put_int64 b9 -1 )
    ( same b9 `ffffffffffffffffff01` )
    : ~ ProtoReader r9 \ ( proto_reader b9 )
    : i v9 \ ( proto_read_int64 r9 )
    ( check == v9 -1 `int64 roundtrip 9` )
    ( check ! ( proto_more r9 ) `scalar end` )
    ( vec_free [u] b9 )
    : ( Vec u ) f9 ( vec_new [u] )
    \ ( proto_write_int64 f9 1 -1 )
    ( same f9 `08ffffffffffffffffff01` )
    \ ( proto_validate f9 )
    ( vec_free [u] f9 )
    : ( Vec u ) b10 ( vec_new [u] )
    \ ( proto_put_int64 b10 -9223372036854775808 )
    ( same b10 `80808080808080808001` )
    : ~ ProtoReader r10 \ ( proto_reader b10 )
    : i v10 \ ( proto_read_int64 r10 )
    ( check == v10 -9223372036854775808 `int64 roundtrip 10` )
    ( check ! ( proto_more r10 ) `scalar end` )
    ( vec_free [u] b10 )
    : ( Vec u ) f10 ( vec_new [u] )
    \ ( proto_write_int64 f10 1 -9223372036854775808 )
    ( same f10 `0880808080808080808001` )
    \ ( proto_validate f10 )
    ( vec_free [u] f10 )
    : ( Vec u ) b11 ( vec_new [u] )
    \ ( proto_put_int32 b11 # i32 -1 )
    ( same b11 `ffffffffffffffffff01` )
    : ~ ProtoReader r11 \ ( proto_reader b11 )
    : i32 v11 \ ( proto_read_int32 r11 )
    ( check == v11 # i32 -1 `int32 roundtrip 11` )
    ( check ! ( proto_more r11 ) `scalar end` )
    ( vec_free [u] b11 )
    : ( Vec u ) f11 ( vec_new [u] )
    \ ( proto_write_int32 f11 1 # i32 -1 )
    ( same f11 `08ffffffffffffffffff01` )
    \ ( proto_validate f11 )
    ( vec_free [u] f11 )
    : ( Vec u ) b12 ( vec_new [u] )
    \ ( proto_put_int32 b12 # i32 -2147483648 )
    ( same b12 `80808080f8ffffffff01` )
    : ~ ProtoReader r12 \ ( proto_reader b12 )
    : i32 v12 \ ( proto_read_int32 r12 )
    ( check == v12 # i32 -2147483648 `int32 roundtrip 12` )
    ( check ! ( proto_more r12 ) `scalar end` )
    ( vec_free [u] b12 )
    : ( Vec u ) f12 ( vec_new [u] )
    \ ( proto_write_int32 f12 1 # i32 -2147483648 )
    ( same f12 `0880808080f8ffffffff01` )
    \ ( proto_validate f12 )
    ( vec_free [u] f12 )
    : ( Vec u ) b13 ( vec_new [u] )
    \ ( proto_put_uint32 b13 # u32 4294967295 )
    ( same b13 `ffffffff0f` )
    : ~ ProtoReader r13 \ ( proto_reader b13 )
    : u32 v13 \ ( proto_read_uint32 r13 )
    ( check == v13 # u32 4294967295 `uint32 roundtrip 13` )
    ( check ! ( proto_more r13 ) `scalar end` )
    ( vec_free [u] b13 )
    : ( Vec u ) f13 ( vec_new [u] )
    \ ( proto_write_uint32 f13 1 # u32 4294967295 )
    ( same f13 `08ffffffff0f` )
    \ ( proto_validate f13 )
    ( vec_free [u] f13 )
    : ( Vec u ) b14 ( vec_new [u] )
    \ ( proto_put_sint32 b14 # i32 -2147483648 )
    ( same b14 `ffffffff0f` )
    : ~ ProtoReader r14 \ ( proto_reader b14 )
    : i32 v14 \ ( proto_read_sint32 r14 )
    ( check == v14 # i32 -2147483648 `sint32 roundtrip 14` )
    ( check ! ( proto_more r14 ) `scalar end` )
    ( vec_free [u] b14 )
    : ( Vec u ) f14 ( vec_new [u] )
    \ ( proto_write_sint32 f14 1 # i32 -2147483648 )
    ( same f14 `08ffffffff0f` )
    \ ( proto_validate f14 )
    ( vec_free [u] f14 )
    : ( Vec u ) b15 ( vec_new [u] )
    \ ( proto_put_sint32 b15 # i32 2147483647 )
    ( same b15 `feffffff0f` )
    : ~ ProtoReader r15 \ ( proto_reader b15 )
    : i32 v15 \ ( proto_read_sint32 r15 )
    ( check == v15 # i32 2147483647 `sint32 roundtrip 15` )
    ( check ! ( proto_more r15 ) `scalar end` )
    ( vec_free [u] b15 )
    : ( Vec u ) f15 ( vec_new [u] )
    \ ( proto_write_sint32 f15 1 # i32 2147483647 )
    ( same f15 `08feffffff0f` )
    \ ( proto_validate f15 )
    ( vec_free [u] f15 )
    : ( Vec u ) b16 ( vec_new [u] )
    \ ( proto_put_sint32 b16 # i32 -1 )
    ( same b16 `01` )
    : ~ ProtoReader r16 \ ( proto_reader b16 )
    : i32 v16 \ ( proto_read_sint32 r16 )
    ( check == v16 # i32 -1 `sint32 roundtrip 16` )
    ( check ! ( proto_more r16 ) `scalar end` )
    ( vec_free [u] b16 )
    : ( Vec u ) f16 ( vec_new [u] )
    \ ( proto_write_sint32 f16 1 # i32 -1 )
    ( same f16 `0801` )
    \ ( proto_validate f16 )
    ( vec_free [u] f16 )
    : ( Vec u ) b17 ( vec_new [u] )
    \ ( proto_put_sint64 b17 -9223372036854775808 )
    ( same b17 `ffffffffffffffffff01` )
    : ~ ProtoReader r17 \ ( proto_reader b17 )
    : i v17 \ ( proto_read_sint64 r17 )
    ( check == v17 -9223372036854775808 `sint64 roundtrip 17` )
    ( check ! ( proto_more r17 ) `scalar end` )
    ( vec_free [u] b17 )
    : ( Vec u ) f17 ( vec_new [u] )
    \ ( proto_write_sint64 f17 1 -9223372036854775808 )
    ( same f17 `08ffffffffffffffffff01` )
    \ ( proto_validate f17 )
    ( vec_free [u] f17 )
    : ( Vec u ) b18 ( vec_new [u] )
    \ ( proto_put_sint64 b18 9223372036854775807 )
    ( same b18 `feffffffffffffffff01` )
    : ~ ProtoReader r18 \ ( proto_reader b18 )
    : i v18 \ ( proto_read_sint64 r18 )
    ( check == v18 9223372036854775807 `sint64 roundtrip 18` )
    ( check ! ( proto_more r18 ) `scalar end` )
    ( vec_free [u] b18 )
    : ( Vec u ) f18 ( vec_new [u] )
    \ ( proto_write_sint64 f18 1 9223372036854775807 )
    ( same f18 `08feffffffffffffffff01` )
    \ ( proto_validate f18 )
    ( vec_free [u] f18 )
    : ( Vec u ) b19 ( vec_new [u] )
    \ ( proto_put_sint64 b19 -1 )
    ( same b19 `01` )
    : ~ ProtoReader r19 \ ( proto_reader b19 )
    : i v19 \ ( proto_read_sint64 r19 )
    ( check == v19 -1 `sint64 roundtrip 19` )
    ( check ! ( proto_more r19 ) `scalar end` )
    ( vec_free [u] b19 )
    : ( Vec u ) f19 ( vec_new [u] )
    \ ( proto_write_sint64 f19 1 -1 )
    ( same f19 `0801` )
    \ ( proto_validate f19 )
    ( vec_free [u] f19 )
    : ( Vec u ) b20 ( vec_new [u] )
    \ ( proto_put_bool b20 T )
    ( same b20 `01` )
    : ~ ProtoReader r20 \ ( proto_reader b20 )
    : b v20 \ ( proto_read_bool r20 )
    ( check == v20 T `bool roundtrip 20` )
    ( check ! ( proto_more r20 ) `scalar end` )
    ( vec_free [u] b20 )
    : ( Vec u ) f20 ( vec_new [u] )
    \ ( proto_write_bool f20 1 T )
    ( same f20 `0801` )
    \ ( proto_validate f20 )
    ( vec_free [u] f20 )
    : ( Vec u ) b21 ( vec_new [u] )
    \ ( proto_put_bool b21 F )
    ( same b21 `00` )
    : ~ ProtoReader r21 \ ( proto_reader b21 )
    : b v21 \ ( proto_read_bool r21 )
    ( check == v21 F `bool roundtrip 21` )
    ( check ! ( proto_more r21 ) `scalar end` )
    ( vec_free [u] b21 )
    : ( Vec u ) f21 ( vec_new [u] )
    \ ( proto_write_bool f21 1 F )
    ( same f21 `0800` )
    \ ( proto_validate f21 )
    ( vec_free [u] f21 )
    : ( Vec u ) b22 ( vec_new [u] )
    \ ( proto_put_fixed32 b22 # u32 4294967295 )
    ( same b22 `ffffffff` )
    : ~ ProtoReader r22 \ ( proto_reader b22 )
    : u32 v22 \ ( proto_read_fixed32 r22 )
    ( check == v22 # u32 4294967295 `fixed32 roundtrip 22` )
    ( check ! ( proto_more r22 ) `scalar end` )
    ( vec_free [u] b22 )
    : ( Vec u ) f22 ( vec_new [u] )
    \ ( proto_write_fixed32 f22 1 # u32 4294967295 )
    ( same f22 `0dffffffff` )
    \ ( proto_validate f22 )
    ( vec_free [u] f22 )
    : ( Vec u ) b23 ( vec_new [u] )
    \ ( proto_put_fixed64 b23 # u64 18446744073709551615 )
    ( same b23 `ffffffffffffffff` )
    : ~ ProtoReader r23 \ ( proto_reader b23 )
    : u64 v23 \ ( proto_read_fixed64 r23 )
    ( check == v23 # u64 18446744073709551615 `fixed64 roundtrip 23` )
    ( check ! ( proto_more r23 ) `scalar end` )
    ( vec_free [u] b23 )
    : ( Vec u ) f23 ( vec_new [u] )
    \ ( proto_write_fixed64 f23 1 # u64 18446744073709551615 )
    ( same f23 `09ffffffffffffffff` )
    \ ( proto_validate f23 )
    ( vec_free [u] f23 )
    : ( Vec u ) b24 ( vec_new [u] )
    \ ( proto_put_sfixed32 b24 # i32 -2147483648 )
    ( same b24 `00000080` )
    : ~ ProtoReader r24 \ ( proto_reader b24 )
    : i32 v24 \ ( proto_read_sfixed32 r24 )
    ( check == v24 # i32 -2147483648 `sfixed32 roundtrip 24` )
    ( check ! ( proto_more r24 ) `scalar end` )
    ( vec_free [u] b24 )
    : ( Vec u ) f24 ( vec_new [u] )
    \ ( proto_write_sfixed32 f24 1 # i32 -2147483648 )
    ( same f24 `0d00000080` )
    \ ( proto_validate f24 )
    ( vec_free [u] f24 )
    : ( Vec u ) b25 ( vec_new [u] )
    \ ( proto_put_sfixed64 b25 -9223372036854775808 )
    ( same b25 `0000000000000080` )
    : ~ ProtoReader r25 \ ( proto_reader b25 )
    : i v25 \ ( proto_read_sfixed64 r25 )
    ( check == v25 -9223372036854775808 `sfixed64 roundtrip 25` )
    ( check ! ( proto_more r25 ) `scalar end` )
    ( vec_free [u] b25 )
    : ( Vec u ) f25 ( vec_new [u] )
    \ ( proto_write_sfixed64 f25 1 -9223372036854775808 )
    ( same f25 `090000000000000080` )
    \ ( proto_validate f25 )
    ( vec_free [u] f25 )
    : ( Vec u ) b26 ( vec_new [u] )
    \ ( proto_put_float b26 # f32 1.5 )
    ( same b26 `0000c03f` )
    : ~ ProtoReader r26 \ ( proto_reader b26 )
    : f32 v26 \ ( proto_read_float r26 )
    ( check == v26 # f32 1.5 `float roundtrip 26` )
    ( check ! ( proto_more r26 ) `scalar end` )
    ( vec_free [u] b26 )
    : ( Vec u ) f26 ( vec_new [u] )
    \ ( proto_write_float f26 1 # f32 1.5 )
    ( same f26 `0d0000c03f` )
    \ ( proto_validate f26 )
    ( vec_free [u] f26 )
    : ( Vec u ) b27 ( vec_new [u] )
    \ ( proto_put_double b27 -1.5 )
    ( same b27 `000000000000f8bf` )
    : ~ ProtoReader r27 \ ( proto_reader b27 )
    : f v27 \ ( proto_read_double r27 )
    ( check == v27 -1.5 `double roundtrip 27` )
    ( check ! ( proto_more r27 ) `scalar end` )
    ( vec_free [u] b27 )
    : ( Vec u ) f27 ( vec_new [u] )
    \ ( proto_write_double f27 1 -1.5 )
    ( same f27 `09000000000000f8bf` )
    \ ( proto_validate f27 )
    ( vec_free [u] f27 )
    ^ @ !v ProtoError { T }
}

// Each malformed vector must fail without consuming any input. This
// independently asserts the exact error code and absolute byte offset.
@ bad s hex i operation ProtoCode want i offset → !v ProtoError {
    : ( Vec u ) bytes ( hx hex )
    : ~ ProtoReader r \ ( proto_reader bytes )
    : ~ ! v ProtoError result @ !v ProtoError { T }
    ?? operation {
        0 → { ?? ( proto_read_uint64 r ) { T _ → {} F e → { = result @ !v ProtoError { F e } } } }
        1 → { ?? ( proto_read_tag r ) { T _ → {} F e → { = result @ !v ProtoError { F e } } } }
        2 → { ?? ( proto_read_bytes r ) { T _ → {} F e → { = result @ !v ProtoError { F e } } } }
        3 → { ?? ( proto_read_fixed32 r ) { T _ → {} F e → { = result @ !v ProtoError { F e } } } }
        4 → { ?? ( proto_read_fixed64 r ) { T _ → {} F e → { = result @ !v ProtoError { F e } } } }
        5 → { ?? ( proto_read_string r ) { T str → { ( string_free str ) } F e → { = result @ !v ProtoError { F e } } } }
        6 → { ?? ( proto_read_raw_field r ) { T _ → {} F e → { = result @ !v ProtoError { F e } } } }
    }
    ?? result {
        T → { ( nurl_print hex ) ( check F `accepted malformed input` ) }
        F e → {
            ( check == # i . e code # i want `wrong error code` )
            ( check == . e offset offset `wrong error offset` )
        }
    }
    ( check == . r pos 0 `failed read moved cursor` )
    ( vec_free [u] bytes )
    ^ @ !v ProtoError { T }
}

@ errors → !v ProtoError {
    \ ( bad `` 0 ProtoTruncated 0 )
    \ ( bad `80` 0 ProtoTruncated 1 )
    \ ( bad `808080808080808080` 0 ProtoTruncated 9 )
    \ ( bad `80808080808080808002` 0 ProtoVarintOverflow 9 )
    \ ( bad `ffffffffffffffffff7f` 0 ProtoVarintOverflow 9 )
    \ ( bad `8080808080808080808000` 0 ProtoVarintOverflow 9 )
    \ ( bad `00` 1 ProtoBadTag 0 )
    \ ( bad `01` 1 ProtoBadTag 0 )
    \ ( bad `07` 1 ProtoBadTag 0 )
    \ ( bad `0e` 1 ProtoBadWire 0 )
    \ ( bad `0f` 1 ProtoBadWire 0 )
    \ ( bad `8080808010` 1 ProtoBadTag 0 )
    \ ( bad `01` 2 ProtoTruncated 1 )
    \ ( bad `8001` 2 ProtoTruncated 2 )
    \ ( bad `8080808008` 2 ProtoBadLength 0 )
    \ ( bad `ffffffffffffffffff01` 2 ProtoBadLength 0 )
    \ ( bad `000102` 3 ProtoTruncated 0 )
    \ ( bad `00010203040506` 4 ProtoTruncated 0 )
    \ ( bad `01ff` 5 ProtoUtf8 1 )
    \ ( bad `02c080` 5 ProtoUtf8 1 )
    \ ( bad `03eda080` 5 ProtoUtf8 1 )
    \ ( bad `04f4908080` 5 ProtoUtf8 1 )
    \ ( bad `02e282` 5 ProtoUtf8 1 )
    \ ( bad `03008061` 5 ProtoUtf8 2 )
    \ ( bad `0c` 6 ProtoGroupMismatch 1 )
    \ ( bad `0b14` 6 ProtoGroupMismatch 1 )
    \ ( bad `0b` 6 ProtoTruncated 1 )
    \ ( bad `0b0880` 6 ProtoTruncated 3 )
    \ ( bad `0b0e` 6 ProtoBadWire 1 )
    \ ( bad `0d000000` 6 ProtoTruncated 1 )
    ^ @ !v ProtoError { T }
}

@ structures → !v ProtoError {
    : ( Vec u ) out ( vec_new [u] )
    : ( Vec u ) child ( hx `089601` )
    \ ( proto_write_bytes out 3 child )
    ( same out `1a03089601` )
    : ~ ProtoReader r \ ( proto_reader out )
    : ProtoTag tag \ ( proto_read_tag r )
    \ ( proto_expect tag 2 0 )
    : ~ ProtoReader sub \ ( proto_read_message r )
    ( check == ( proto_offset sub ) 2 `child absolute offset` )
    ( check == # i . . sub bytes data + # i ( vec_data [u] out ) 2 `child borrows buffer` )
    : ProtoTag inner \ ( proto_read_tag sub )
    : u64 value \ ( proto_read_uint64 sub )
    ( check == value # u64 150 `nested value` )
    ( check & ! ( proto_more r ) ! ( proto_more sub ) `child bounds` )
    ?? ( proto_read_uint64 sub ) {
        T _ → ( check F `child overread` )
        F e → ( check == . e offset 5 `child error absolute offset` )
    }
    ( vec_free [u] child )
    ( vec_free [u] out )

    // Parent has more bytes, but the nested varint cannot borrow them.
    : ( Vec u ) truncated ( hx `018001` )
    : ~ ProtoReader parent \ ( proto_reader truncated )
    : ~ ProtoReader bounded \ ( proto_read_message parent )
    ?? ( proto_read_uint64 bounded ) {
        T _ → ( check F `nested varint escaped boundary` )
        F e → ( check == . e offset 2 `bounded error` )
    }
    ( check == . bounded pos 0 `nested rollback` )
    : u64 sibling \ ( proto_read_uint64 parent )
    ( check == sibling # u64 1 `sibling preserved` )
    ( vec_free [u] truncated )

    // Packed fields can be split/interleaved with expanded occurrences.
    : ( Vec u ) mixed ( hx `0a020102100708030a0104` )
    : ~ ProtoReader m \ ( proto_reader mixed )
    : ~ i count 0
    : ~ i sum 0
    ~ ( proto_more m ) {
        : ProtoTag t \ ( proto_read_tag m )
        ? == . t number 1 {
            ? == . t wire 2 {
                : ~ ProtoReader packed \ ( proto_read_packed m )
                ~ ( proto_more packed ) {
                    : i x \ ( proto_read_int64 packed )
                    = sum + sum x
                    = count + count 1
                }
            } {
                \ ( proto_expect t 0 ( proto_offset m ) )
                : i x \ ( proto_read_int64 m )
                = sum + sum x
                = count + count 1
            }
        } { \ ( proto_skip m t ) }
    }
    ( check & == count 4 == sum 10 `packed and expanded sequence` )
    ( vec_free [u] mixed )

    : ( Vec u ) groups ( hx `0b10011b250000803f1c0c` )
    \ ( proto_validate groups )
    : ~ ProtoReader g \ ( proto_reader groups )
    : ( Slice u ) raw \ ( proto_read_raw_field g )
    ( check == . raw len ( vec_len [u] groups ) `whole unknown group` )
    ( check == # i . raw data # i ( vec_data [u] groups ) `raw borrows input` )
    ( vec_free [u] groups )

    // UTF-8, including an embedded NUL, must retain its explicit length.
    : ( Vec u ) text ( hx `086100c3a4f09f9880` )
    : ~ ProtoReader tr \ ( proto_reader text )
    : String str \ ( proto_read_string tr )
    ( check == ( string_len str ) 8 `string contains NUL` )
    : ( Vec u ) encoded ( vec_new [u] )
    \ ( proto_write_string encoded 2 str )
    ( same encoded `12086100c3a4f09f9880` )
    ( string_free str )
    ( vec_free [u] text )
    ( vec_free [u] encoded )

    // Full 32-bit field tags, reserved schema numbers, nonminimal values.
    : ( Vec u ) tags ( hx `f8ffffff0f00c0a3090088008100` )
    \ ( proto_validate tags )
    ( vec_free [u] tags )
    : ( Vec u ) bools ( hx `ffffffffffffffffff01` )
    : ~ ProtoReader br \ ( proto_reader bools )
    : b truth \ ( proto_read_bool br )
    ( check truth `nonzero bool` )
    ( vec_free [u] bools )
    ^ @ !v ProtoError { T }
}

@ limits → !v ProtoError {
    : ( Vec u ) bytes ( hx `0b0b0c0c` )
    : ~ ProtoReader r \ ( proto_reader_with_limits ( slice_from_vec [u] bytes ) 4 1 )
    ?? ( proto_read_raw_field r ) {
        T _ → ( check F `group depth` )
        F e → ( check == # i . e code # i ProtoDepth `depth error` )
    }
    ( check == . r pos 0 `depth rollback` )
    : ~ ProtoReader ok \ ( proto_reader_with_limits ( slice_from_vec [u] bytes ) 4 2 )
    \ ( proto_read_raw_field ok )
    ?? ( proto_reader_with_limits ( slice_from_vec [u] bytes ) 3 2 ) {
        T _ → ( check F `size limit` )
        F e → ( check == # i . e code # i ProtoSize `size error` )
    }
    ( vec_free [u] bytes )
    : ( Vec u ) zero ( hx `00` )
    : ~ ProtoReader no_depth \ ( proto_reader_with_limits ( slice_from_vec [u] zero ) 1 0 )
    ?? ( proto_read_message no_depth ) {
        T _ → ( check F `message depth` )
        F e → ( check == # i . e code # i ProtoDepth `message depth error` )
    }
    ( check == . no_depth pos 0 `message depth rollback` )
    : ProtoReader packed \ ( proto_read_packed no_depth )
    ( check ! ( proto_more packed ) `packed does not use message depth` )
    ( vec_free [u] zero )

    // Appending a slice of the destination survives reallocations.
    : ( Vec u ) alias ( hx `0102030405060708` )
    \ ( proto_write_bytes alias 1 alias )
    ( same alias `01020304050607080a080102030405060708` )
    : ( Slice u ) portion ?? ( slice_sub [u] ( slice_from_vec [u] alias ) 2 5 ) { T x → x F → @ ( Slice u ) { # *u 0 0 } }
    \ ( proto_write_slice alias 2 portion )
    ( same alias `01020304050607080a0801020304050607081203030405` )
    : i size ( vec_len [u] alias )
    ?? ( proto_write_uint64 alias 0 # u64 1 ) {
        T → ( check F `invalid encoder tag` ) F _ → {}
    }
    ?? ( proto_write_tag alias 1 6 ) {
        T → ( check F `invalid encoder wire` ) F _ → {}
    }
    ( check == ( vec_len [u] alias ) size `encoder rollback` )
    ( vec_free [u] alias )
    ^ @ !v ProtoError { T }
}

@ known_groups → !v ProtoError {
    : ( Vec u ) bytes ( hx `0b10011b250000803f1c0c2807` )
    : ~ ProtoReader r \ ( proto_reader bytes )
    : ProtoTag outer \ ( proto_read_tag r )
    : ~ ProtoReader group \ ( proto_read_group r . outer number )
    ( check == ( proto_offset group ) 1 `known group base` )
    ( check == . . group bytes len 9 `known group contents` )
    : ProtoTag first \ ( proto_read_tag group )
    : i value \ ( proto_read_int64 group )
    ( check & == . first number 2 == value 1 `known group scalar` )
    : ProtoTag nested \ ( proto_read_tag group )
    : ~ ProtoReader child \ ( proto_read_group group . nested number )
    : ProtoTag float_tag \ ( proto_read_tag child )
    : f32 number \ ( proto_read_float child )
    ( check & == . float_tag number 4 == number # f32 1.0 `nested group float` )
    ( check & ! ( proto_more child ) ! ( proto_more group ) `group boundaries` )
    : ProtoTag sibling_tag \ ( proto_read_tag r )
    : i sibling \ ( proto_read_int64 r )
    ( check & == . sibling_tag number 5 == sibling 7 `group sibling` )
    ( vec_free [u] bytes )
    : ( Vec u ) empty ( vec_new [u] )
    \ ( proto_write_tag empty 1 3 )
    \ ( proto_write_tag empty 1 4 )
    : ~ ProtoReader er \ ( proto_reader empty )
    : ProtoTag begin \ ( proto_read_tag er )
    : ProtoReader eg \ ( proto_read_group er . begin number )
    ( check ! ( proto_more eg ) `empty known group` )
    ( vec_free [u] empty )
    ^ @ !v ProtoError { T }
}

@ api_boundaries → !v ProtoError {
    : ( Slice u ) empty @ ( Slice u ) { # *u 0 0 }
    : ( Slice u ) invalid @ ( Slice u ) { # *u 0 -1 }
    ?? ( proto_reader_with_limits invalid 1 1 ) {
        T _ → ( check F `negative slice length` ) F _ → {}
    }
    ?? ( proto_reader_with_limits empty -1 1 ) {
        T _ → ( check F `negative byte limit` ) F _ → {}
    }
    ?? ( proto_reader_with_limits empty PROTO_MAX_BYTES -1 ) {
        T _ → ( check F `negative depth limit` ) F _ → {}
    }
    ?? ( proto_reader_with_limits empty PROTO_MAX_BYTES + PROTO_DEPTH_LIMIT 1 ) {
        T _ → ( check F `excessive depth limit` ) F _ → {}
    }
    : ( Slice u ) null_data @ ( Slice u ) { # *u 0 1 }
    ?? ( proto_reader_with_limits null_data 1 1 ) {
        T _ → ( check F `null data` ) F _ → {}
    }
    : ( Vec u ) out ( vec_new [u] )
    \ ( proto_write_uint64 out PROTO_MAX_FIELD # u64 1 )
    ( same out `f8ffffff0f01` )
    : i before ( vec_len [u] out )
    ?? ( proto_write_slice out 1 invalid ) {
        T → ( check F `negative write length` ) F _ → {}
    }
    : ( Slice u ) oversized @ ( Slice u ) { # *u 0 PROTO_MAX_BYTES }
    ?? ( proto_write_slice out 1 oversized ) {
        T → ( check F `null nonempty write` ) F _ → {}
    }
    // Capacity checks must happen before accessing even a huge raw range.
    : ( Slice u ) too_large @ ( Slice u ) { # *u 1 PROTO_MAX_BYTES }
    ?? ( proto_write_slice out 1 too_large ) {
        T → ( check F `output limit` )
        F e → ( check == # i . e code # i ProtoSize `output size error` )
    }
    ?? ( proto_write_uint64 out + PROTO_MAX_FIELD 1 # u64 1 ) {
        T → ( check F `field number overflow` ) F _ → {}
    }
    : ( Vec u ) utf ( hx `61ff` )
    : String invalid_text ( string_from_bytes ( vec_data [u] utf ) 2 )
    ?? ( proto_write_string out 2 invalid_text ) {
        T → ( check F `invalid encoder UTF8` ) F _ → {}
    }
    ( check == ( vec_len [u] out ) before `rejected writes unchanged` )
    ( same out `f8ffffff0f01` )
    ( string_free invalid_text )
    ( vec_free [u] utf )
    ( vec_free [u] out )

    // Packed fixed-width elements cannot read the sibling byte.
    : ( Vec u ) short ( hx `0301020304` )
    : ~ ProtoReader p \ ( proto_reader short )
    : ~ ProtoReader packed \ ( proto_read_packed p )
    ?? ( proto_read_fixed32 packed ) {
        T _ → ( check F `partial packed fixed32` ) F _ → {}
    }
    ( check == . packed pos 0 `packed fixed rollback` )
    : u64 sibling \ ( proto_read_uint64 p )
    ( check == sibling # u64 4 `packed sibling preserved` )
    ( vec_free [u] short )

    // Exact float transport, including signed zero and NaN payloads.
    : ( Vec u ) bits ( hx `000000800100807fffffffff0000000000000080010000000000f07fffffffffffffffff` )
    : ~ ProtoReader br \ ( proto_reader bits )
    : ( Vec u ) back ( vec_new [u] )
    : ~ i k 0
    ~ < k 3 {
        : f32 x \ ( proto_read_float br )
        \ ( proto_put_float back x )
        = k + k 1
    }
    = k 0
    ~ < k 3 {
        : f x \ ( proto_read_double br )
        \ ( proto_put_double back x )
        = k + k 1
    }
    ( check ( bytes_eq bits back ) `IEEE bit patterns changed` )
    ( vec_free [u] bits )
    ( vec_free [u] back )
    ^ @ !v ProtoError { T }
}

@ run → !v ProtoError {
    \ ( vectors )
    \ ( errors )
    \ ( structures )
    \ ( limits )
    \ ( api_boundaries )
    \ ( known_groups )
    ^ @ !v ProtoError { T }
}

@ main → i {
    ?? ( run ) {
        T → { ( nurl_print `protobuf: vectors, errors, structures, limits ok\n` ) ^ 0 }
        F error → { ( nurl_print ( proto_error_name . error code ) ) ( nurl_print `\n` ) ^ 1 }
    }
}
