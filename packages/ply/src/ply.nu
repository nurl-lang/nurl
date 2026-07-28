// packages/ply/src/ply.nu — a streaming PLY point-cloud writer.
//
// The property layout is the one every viewer reads and the bundled
// viewer parses: x, y, z as float32 and red, green, blue as uchar —
// 15 bytes a vertex in binary_little_endian, one line a vertex in ascii.
//
// The vertex count is usually not known until the last point is pushed,
// so the header is written with a fixed-width zero-padded placeholder
// and patched in place at the end, rather than holding the whole cloud
// in memory:
//
//   ( ply_create path ascii comment )   → !*PlyW String
//   ( ply_vertex w x y z r g b )        → v   buffered; flushes itself
//   ( ply_count w )                     → i   vertices pushed so far
//   ( ply_finish w )                    → b   flush, patch the count, close
//
// `ply_finish` frees the handle either way; its F means the file could
// not be finished and should not be trusted.
//
// Writes are buffered ~4 KB at a time — a vertex is 15 bytes, and a
// write per vertex would make the file the slowest part of a pipeline
// that computes millions of them.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`

// The count field is fixed-width so the header keeps its byte length
// when the real number is patched in. 12 digits holds any cloud a
// filesystem holds.
: i PLY_COUNT_WIDTH 12
: i PLY_FLUSH_AT 4096

: PlyW {
    File f
    i n
    i ascii
    i cnt_off  // where the count field starts, for the patch at the end
    String abuf
    ( Vec u ) bbuf
}

@ __ply_wr File f String s → b {
    : ( Vec u ) b ( bytes_from_str ( string_data s ) )
    ?? ( file_write_chunk f b ) {
        T _x → { ( vec_free [u] b ) ^ T }
        F _e → { ( vec_free [u] b ) ^ F }
    }
}

@ __ply_count_field i n → String {
    : String d ( string_from `` )
    ( string_push_int d n )
    : String s ( string_from `` )
    : ~ i k ( string_len d )
    ~ < k PLY_COUNT_WIDTH { ( string_push_char s 48 ) = k + k 1 }
    ( string_push_str s ( string_data d ) )
    ( string_free d )
    ^ s
}

// The header, up to (but excluding) the vertex-count field; its length
// is where the patch seeks back to.
@ __ply_head i ascii s comment → String {
    : String h ( string_from `ply\nformat ` )
    ( string_push_str h ? != ascii 0 `ascii` `binary_little_endian` )
    ( string_push_str h ` 1.0\n` )
    ? > ( nurl_str_len comment ) 0 {
        ( string_push_str h `comment ` )
        ( string_push_str h comment )
        ( string_push_char h 10 )
    } {}
    ( string_push_str h `element vertex ` )
    ^ h
}

// Open `path` and write the header. `comment` goes in as one comment
// line ("" for none) — a place for provenance, not for structure.
@ ply_create s path i ascii s comment → !*PlyW String {
    ?? ( file_create path ) {
        F _e → {
            : String m ( string_from `ply: cannot write ` )
            ( string_push_str m path )
            ^ @ !*PlyW String { F m }
        }
        T f → {
            : String h ( __ply_head ascii comment )
            : i off ( string_len h )
            : String c ( __ply_count_field 0 )
            ( string_push_str h ( string_data c ) )
            ( string_free c )
            ( string_push_str h `\nproperty float x\nproperty float y\nproperty float z\nproperty uchar red\nproperty uchar green\nproperty uchar blue\nend_header\n` )
            : b ok ( __ply_wr f h )
            ( string_free h )
            ? ok {} {
                ( file_close f )
                ^ @ !*PlyW String { F ( string_from `ply: cannot write the header` ) }
            }
            : *PlyW w # *PlyW ( nurl_alloc Z PlyW )
            = . w f f
            = . w n 0
            = . w ascii ascii
            = . w cnt_off off
            = . w abuf ( string_new )
            = . w bbuf ( vec_new [u] )
            ^ @ !*PlyW String { T w }
        }
    }
}

@ ply_count * PlyW w → i { ^ . w n }

// One little-endian float32, appended to the binary buffer.
@ __ply_put_f32 ( Vec u ) b f v → v {
    : i x ( f32_to_bits # f32 v )
    ( vec_push [u] b # u & x 255 )
    ( vec_push [u] b # u & >> x 8 255 )
    ( vec_push [u] b # u & >> x 16 255 )
    ( vec_push [u] b # u & >> x 24 255 )
}

@ __ply_clamp_u8 i v → i {
    ? < v 0 { ^ 0 } {}
    ? > v 255 { ^ 255 } {}
    ^ v
}

// Write out whatever is buffered. Idempotent; ply_vertex calls it on
// its own past PLY_FLUSH_AT bytes.
@ ply_flush * PlyW w → b {
    : ~ b ok T
    ? != . w ascii 0 {
        ? > ( string_len . w abuf ) 0 {
            = ok ( __ply_wr . w f . w abuf )
            ( string_free . w abuf )
            = . w abuf ( string_new )
        } {}
    } {
        ? > ( vec_len [u] . w bbuf ) 0 {
            ?? ( file_write_chunk . w f . w bbuf ) {
                T _x → {}
                F _e → { = ok F }
            }
            : b _t ( vec_set_len [u] . w bbuf 0 )
        } {}
    }
    ^ ok
}

// Push one vertex. Colour components are clamped to 0..255.
@ ply_vertex * PlyW w f x f y f z i r i g i b → v {
    : i rr ( __ply_clamp_u8 r )
    : i gg ( __ply_clamp_u8 g )
    : i bb ( __ply_clamp_u8 b )
    ? != . w ascii 0 {
        : String buf . w abuf
        ( string_push_str buf ( nurl_str_float x ) )
        ( string_push_char buf 32 )
        ( string_push_str buf ( nurl_str_float y ) )
        ( string_push_char buf 32 )
        ( string_push_str buf ( nurl_str_float z ) )
        ( string_push_char buf 32 )
        ( string_push_int buf rr )
        ( string_push_char buf 32 )
        ( string_push_int buf gg )
        ( string_push_char buf 32 )
        ( string_push_int buf bb )
        ( string_push_char buf 10 )
        ? > ( string_len buf ) PLY_FLUSH_AT { : b _f ( ply_flush w ) } {}
    } {
        : ( Vec u ) bin . w bbuf
        ( __ply_put_f32 bin x )
        ( __ply_put_f32 bin y )
        ( __ply_put_f32 bin z )
        ( vec_push [u] bin # u rr )
        ( vec_push [u] bin # u gg )
        ( vec_push [u] bin # u bb )
        ? > ( vec_len [u] bin ) PLY_FLUSH_AT { : b _f ( ply_flush w ) } {}
    }
    = . w n + . w n 1
}

// Flush, rewind to the count field, overwrite it in place, close, free.
@ ply_finish * PlyW w → b {
    : ~ b ok ( ply_flush w )
    : File f . w f
    ? ok {
        ?? ( file_seek f . w cnt_off 0 ) {
            T _o → {
                : String c ( __ply_count_field . w n )
                = ok ( __ply_wr f c )
                ( string_free c )
            }
            F _e → { = ok F }
        }
    } {}
    ( file_close f )
    ( string_free . w abuf )
    ( vec_free [u] . w bbuf )
    ( nurl_free # s w )
    ^ ok
}
