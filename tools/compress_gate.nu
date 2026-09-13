// File-based differential driver; malformed input is an ordinary nonzero
// result with an error name, so the oracle distinguishes rejection from crash.
$ `stdlib/ext/compress.nu`
$ `stdlib/std/fs.nu`

@ compress_gate_run s mode ( Vec u ) src i cap → !( Vec u ) CompressErr {
    ? ( nurl_str_eq mode `gzip-encode` ) { ^ ( gzip_compress src ) } {}
    ? ( nurl_str_eq mode `zlib-encode` ) { ^ ( zlib_compress src ) } {}
    ? ( nurl_str_eq mode `gzip` ) { ^ ( gzip_decompress_max src cap ) } {}
    ? ( nurl_str_eq mode `zlib` ) { ^ ( zlib_decompress_max src cap ) } {}
    ?? ( inflate_max src cap ) {
        T out → ^ @ !( Vec u ) CompressErr { T out }
        F error → {
            : CompressErr mapped ?? error {
                DeflateLimit → # CompressErr CompressBufTooSmall
                _ → # CompressErr CompressData
            }
            ^ @ !( Vec u ) CompressErr { F mapped }
        }
    }
}

@ compress_gate_files s mode s input s output i cap → i {
    : ( Vec u ) src ?? ( read_file_bytes input ) {
        T data → data
        F _ → { ^ 2 }
    }
    : ~ i status 0
    ?? ( compress_gate_run mode src cap ) {
        F error → { ( nurl_eprintln ( compress_err_name error ) ) = status 1 }
        T out → {
            ?? ( write_file_bytes output out ) { T _ → {} F _ → { = status 2 } }
            ( vec_free [u] out )
        }
    }
    ( vec_free [u] src )
    ^ status
}

@ main → i {
    ? != ( nurl_argv_count ) 5 { ^ 2 } {}
    : s mode ( nurl_argv_get 1 )
    : s input ( nurl_argv_get 2 )
    : s output ( nurl_argv_get 3 )
    : s cap ( nurl_argv_get 4 )
    : i status ( compress_gate_files mode input output ( nurl_str_to_int cap ) )
    ^ status
}
