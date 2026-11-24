// packages/ply/src/read.nu — read a PLY point cloud into memory.
//
//   ( ply_read path )   → !PlyCloud String
//
// A PlyCloud is the vertices' positions (x y z, 3 numbers a point) and,
// when the file has them, their colours (r g b, 3 bytes a point). Read:
//   - format ascii or binary_little_endian (big-endian is refused);
//   - the vertex element first (a mesh's faces after it are ignored);
//   - x, y and z of any scalar type, required;
//   - red, green and blue (or diffuse_red, …) of any scalar type, optional:
//     integers are taken as 0..255, floats as 0..1;
//   - any other vertex property is skipped. A list property in the vertex
//     element is refused (its size is per vertex, there is no stride).
// The whole file is read at once: 15 bytes a point is 150 MB for ten
// million, which is the scale this is for.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`

: PlyCloud {
    i n
    ( Vec f ) xyz
    ( Vec u ) rgb  // 3 per point, or empty
}

@ ply_cloud_has_color PlyCloud c → b { ^ > ( vec_len [u] . c rgb ) 0 }

// type codes: 1 int8, 2 uint8, 3 int16, 4 uint16, 5 int32, 6 uint32, 7 f32, 8 f64
@ __ply_type s t → i {
    ? | ( __ply_eq t `char` ) ( __ply_eq t `int8` ) { ^ 1 } {}
    ? | ( __ply_eq t `uchar` ) ( __ply_eq t `uint8` ) { ^ 2 } {}
    ? | ( __ply_eq t `short` ) ( __ply_eq t `int16` ) { ^ 3 } {}
    ? | ( __ply_eq t `ushort` ) ( __ply_eq t `uint16` ) { ^ 4 } {}
    ? | ( __ply_eq t `int` ) ( __ply_eq t `int32` ) { ^ 5 } {}
    ? | ( __ply_eq t `uint` ) ( __ply_eq t `uint32` ) { ^ 6 } {}
    ? | ( __ply_eq t `float` ) ( __ply_eq t `float32` ) { ^ 7 } {}
    ? | ( __ply_eq t `double` ) ( __ply_eq t `float64` ) { ^ 8 } {}
    ^ 0
}

@ __ply_eq s a s b → b { ^ == 0 ( nurl_str_cmp a b ) }

// A header line's words: split on spaces and tabs, empties dropped.
@ __ply_words String line → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : ( Slice u ) bs ( slice_of_str ( string_data line ) )
    : ~ String cur ( string_new )
    : ~ i k 0
    ~ <= k ( slice_len [u] bs ) {
        : i c ? < k ( slice_len [u] bs ) # i ( slice_byte bs k ) 32
        ? | == c 32 == c 9 {
            ? > ( string_len cur ) 0 { ( vec_push [String] out cur ) = cur ( string_new ) } {}
        } { ( string_push_char cur c ) }
        = k + k 1
    }
    ^ out
}

@ __ply_size i t → i {
    ? | == t 1 == t 2 { ^ 1 } {}
    ? | == t 3 == t 4 { ^ 2 } {}
    ? == t 8 { ^ 8 } {}
    ^ 4
}

// One binary little-endian value as a float.
@ __ply_bin ( Vec u ) b i off i t → f {
    : ( Slice u ) s ( slice_from_vec [u] b )
    ? == t 7 { ?? ( bytes_read_f32_le b off ) { T v → { ^ # f v } F → { ^ 0.0 } } } {}
    ? == t 8 { ?? ( bytes_read_f64_le b off ) { T v → { ^ v } F → { ^ 0.0 } } } {}
    ? == t 2 { ^ # f # i ( slice_at [u] s off ) } {}
    ? == t 1 {
        : i v # i ( slice_at [u] s off )
        ^ # f ? > v 127 - v 256 v
    } {}
    ? | == t 3 == t 4 {
        : i v + # i ( slice_at [u] s off ) * 256 # i ( slice_at [u] s + off 1 )
        ? & == t 3 > v 32767 { ^ # f - v 65536 } {}
        ^ # f v
    } {}
    ?? ( bytes_read_u32_le b off ) {
        T v → {
            : i x # i v
            ? & == t 5 > x 2147483647 { ^ # f - x 4294967296 } {}
            ^ # f x
        }
        F → { ^ 0.0 }
    }
}

@ __ply_err s what s path → !PlyCloud String {
    : String e ( string_from `ply: ` )
    ( string_push_str e path )
    ( string_push_str e `: ` )
    ( string_push_str e what )
    ^ @ !PlyCloud String { F e }
}

@ __ply_u8 f v i t → u {
    // integer colours are 0..255 as they stand; float ones 0..1
    : f x ? | == t 7 == t 8 * v 255.0 v
    ? < x 0.0 { ^ # u 0 } {}
    ? > x 255.0 { ^ # u 255 } {}
    ^ # u # i + x 0.5
}

@ ply_read s path → !PlyCloud String {
    ?? ( read_file_bytes path ) {
        F _e → { ^ ( __ply_err `cannot read it` path ) }
        T b → { ^ ( __ply_parse b path ) }
    }
}

@ __ply_parse ( Vec u ) b s path → !PlyCloud String {
    : i nb ( vec_len [u] b )
    : ( Slice u ) p ( slice_from_vec [u] b )
    ? & & & >= nb 4 == 112 # i ( slice_at [u] p 0 ) == 108 # i ( slice_at [u] p 1 ) == 121 # i ( slice_at [u] p 2 ) {} {
        ^ ( __ply_err `does not start with 'ply'` path )
    }
    // the header, a line at a time
    : ~ i fmt 0  // 1 ascii, 2 binary little-endian
    : ~ i nv -1
    : ~ i invert 0  // inside the vertex element
    : ~ i seen_elem 0
    : ( Vec i ) ptype ( vec_new [i] )
    : ( Vec i ) prole ( vec_new [i] )  // 0 skip, 1..3 x y z, 4..6 r g b
    : ~ i body -1
    : ~ i ls 0
    : ~ i k 0
    : i lim ? < nb 65536 nb 65536
    ~ & < body 0 < k lim {
        ? == # i ( slice_at [u] p k ) 10 {
            : ~ String line ( string_new )
            : ~ i j ls
            ~ < j k {
                : i c # i ( slice_at [u] p j )
                ? != c 13 { ( string_push_char line c ) } {}
                = j + j 1
            }
            : ( Vec String ) w ( __ply_words line )
            : i nw ( vec_len [String] w )
            : ~ s w0 ``
            : ~ s w1 ``
            : ~ s w2 ``
            ?? ( vec_get [String] w 0 ) { T x → { = w0 ( string_data x ) } F → {} }
            ?? ( vec_get [String] w 1 ) { T x → { = w1 ( string_data x ) } F → {} }
            ?? ( vec_get [String] w 2 ) { T x → { = w2 ( string_data x ) } F → {} }
            ? ( __ply_eq w0 `format` ) {
                ? ( __ply_eq w1 `ascii` ) { = fmt 1 } {
                    ? ( __ply_eq w1 `binary_little_endian` ) { = fmt 2 } {
                        ^ ( __ply_err `only ascii and binary_little_endian are read` path )
                    }
                }
            } {}
            ? ( __ply_eq w0 `element` ) {
                ? ( __ply_eq w1 `vertex` ) {
                    ? != seen_elem 0 { ^ ( __ply_err `the vertex element must come first` path ) } {}
                    = nv ( nurl_str_to_int w2 )
                    = invert 1
                } { = invert 0 }
                = seen_elem 1
            } {}
            ? & ( __ply_eq w0 `property` ) == invert 1 {
                ? ( __ply_eq w1 `list` ) { ^ ( __ply_err `a list property in the vertex element` path ) } {}
                : i t ( __ply_type w1 )
                ? == t 0 { ^ ( __ply_err `an unknown property type` path ) } {}
                ( vec_push [i] ptype t )
                : ~ i role 0
                ? ( __ply_eq w2 `x` ) { = role 1 } {}
                ? ( __ply_eq w2 `y` ) { = role 2 } {}
                ? ( __ply_eq w2 `z` ) { = role 3 } {}
                ? | ( __ply_eq w2 `red` ) ( __ply_eq w2 `diffuse_red` ) { = role 4 } {}
                ? | ( __ply_eq w2 `green` ) ( __ply_eq w2 `diffuse_green` ) { = role 5 } {}
                ? | ( __ply_eq w2 `blue` ) ( __ply_eq w2 `diffuse_blue` ) { = role 6 } {}
                ( vec_push [i] prole role )
            } {}
            ? ( __ply_eq w0 `end_header` ) { = body + k 1 } {}
            : i _n nw
            = ls + k 1
        } {}
        = k + k 1
    }
    ? < body 0 { ^ ( __ply_err `no end_header` path ) } {}
    ? == fmt 0 { ^ ( __ply_err `no format line` path ) } {}
    ? < nv 0 { ^ ( __ply_err `no vertex element` path ) } {}
    : ( Slice i ) pt ( slice_from_vec [i] ptype )
    : ( Slice i ) pr ( slice_from_vec [i] prole )
    : i np ( slice_len [i] pt )
    : ~ i have 0
    : ~ i q 0
    ~ < q np { = have | have << 1 ( slice_at [i] pr q ) = q + q 1 }
    ? != & have 14 14 { ^ ( __ply_err `the vertices have no x, y and z` path ) } {}
    : b col == & have 112 112
    : ( Vec f ) xyz ( vec_with_cap [f] * nv 3 )
    : ( Vec u ) rgb ( vec_with_cap [u] ? col * nv 3 0 )
    : ( Vec f ) vals__v ( vec_zeroed [f] np )
    : ( Slice f ) vals ( slice_from_vec [f] vals__v )
    ? == fmt 2 {
        : ~ i stride 0
        = q 0
        ~ < q np { = stride + stride ( __ply_size ( slice_at [i] pt q ) ) = q + q 1 }
        ? > + body * nv stride nb { ^ ( __ply_err `the body is shorter than the header says` path ) } {}
        : ~ i off body
        : ~ i v 0
        ~ < v nv {
            = q 0
            ~ < q np {
                : i t ( slice_at [i] pt q )
                ? != ( slice_at [i] pr q ) 0 { ( slice_put [f] vals q ( __ply_bin b off t ) ) } {}
                = off + off ( __ply_size t )
                = q + q 1
            }
            ( __ply_take vals pr pt np xyz rgb col )
            = v + v 1
        }
    } {
        // ascii: whitespace-separated numbers, one vertex a line
        : ~ i pos body
        : ~ i v 0
        ~ < v nv {
            = q 0
            ~ < q np {
                ~ & < pos nb | | | == 32 # i ( slice_at [u] p pos ) == 10 # i ( slice_at [u] p pos ) == 13 # i ( slice_at [u] p pos ) == 9 # i ( slice_at [u] p pos ) { = pos + pos 1 }
                ? >= pos nb { ^ ( __ply_err `the body is shorter than the header says` path ) } {}
                : ~ String tok ( string_new )
                ~ & < pos nb & & & != 32 # i ( slice_at [u] p pos ) != 10 # i ( slice_at [u] p pos ) != 13 # i ( slice_at [u] p pos ) != 9 # i ( slice_at [u] p pos ) {
                    ( string_push_char tok # i ( slice_at [u] p pos ) )
                    = pos + pos 1
                }
                ( slice_put [f] vals q ( nurl_str_to_float ( string_data tok ) ) )
                = q + q 1
            }
            ( __ply_take vals pr pt np xyz rgb col )
            = v + v 1
        }
    }
    ^ @ !PlyCloud String { T @ PlyCloud { nv xyz rgb } }
}

// One vertex's values into the cloud.
@ __ply_take ( Slice f ) vals ( Slice i ) pr ( Slice i ) pt i np ( Vec f ) xyz ( Vec u ) rgb b col → v {
    : ~ f x 0.0
    : ~ f y 0.0
    : ~ f z 0.0
    : ~ u r # u 0
    : ~ u g # u 0
    : ~ u bb # u 0
    : ~ i q 0
    ~ < q np {
        : i role ( slice_at [i] pr q )
        : f v ( slice_at [f] vals q )
        ? == role 1 { = x v } {}
        ? == role 2 { = y v } {}
        ? == role 3 { = z v } {}
        ? == role 4 { = r ( __ply_u8 v ( slice_at [i] pt q ) ) } {}
        ? == role 5 { = g ( __ply_u8 v ( slice_at [i] pt q ) ) } {}
        ? == role 6 { = bb ( __ply_u8 v ( slice_at [i] pt q ) ) } {}
        = q + q 1
    }
    ( vec_push [f] xyz x ) ( vec_push [f] xyz y ) ( vec_push [f] xyz z )
    ? col { ( vec_push [u] rgb r ) ( vec_push [u] rgb g ) ( vec_push [u] rgb bb ) } {}
}
