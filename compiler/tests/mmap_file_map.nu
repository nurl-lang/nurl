// stdlib/std/mmap.nu over a real file: file_map and file_map_stream map it
// (mmap on POSIX, MapViewOfFile on Windows) and read back the bytes that
// were written; an empty file maps to no bytes; a missing one is NotFound.
// The file is deleted after the last MappedFile over it is dropped — on
// Windows a mapped file cannot be removed, so this also shows the drop
// unmapped it.
$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/mmap.nu`
$ `stdlib/ext/env.nu`

// Bytes i*7+3 (mod 256), 1 MiB + 13: more than one page, an odd tail.
@ pattern i n → ( Vec u ) {
    : ( Vec u ) v ( vec_zeroed [u] n )
    : ~ i k 0
    ~ < k n {
        : b _s ( vec_set [u] v k # u & + * k 7 3 255 )
        = k + k 1
    }
    ^ v
}

@ show_map s label ! MappedFile IoErr r i n → v {
    ?? r {
        T m → {
            : ( Slice u ) b ( mapped_bytes m )
            : ~ i sum 0
            : ~ i bad 0
            : ~ i k 0
            ~ < k ( mapped_len m ) {
                : i x # i ( slice_at [u] b k )
                = sum + sum x
                ? != x & + * k 7 3 255 { = bad + bad 1 } {}
                = k + k 1
            }
            ( nurl_print label )
            ( nurl_print ` len=` )
            ( nurl_print_int ( mapped_len m ) )
            ( nurl_print ` same=` )
            ( nurl_print ? == ( mapped_len m ) n `yes` `no` )
            ( nurl_print ` wrong=` )
            ( nurl_print_int bad )
            ( nurl_print ` sum=` )
            ( nurl_println_int sum )
        }
        F e → {
            ( nurl_print label )
            ( nurl_print ` failed: ` )
            ( nurl_println ( io_err_msg e ) )
        }
    }
}

@ main → i {
    : String root ( env_temp_dir )
    : String path ( string_from ( string_data root ) )
    ( string_push_str path `/_nurl_mmap_file_map.bin` )
    : String empty ( string_from ( string_data root ) )
    ( string_push_str empty `/_nurl_mmap_file_map_empty.bin` )
    : String gone ( string_from ( string_data root ) )
    ( string_push_str gone `/_nurl_mmap_file_map_missing.bin` )

    : i n + 1048576 13
    ?? ( write_file_bytes ( string_data path ) ( pattern n ) ) {
        T _ → {}
        F e → { ( nurl_println ( io_err_msg e ) ) ^ 1 }
    }
    ( show_map `file_map` ( file_map ( string_data path ) ) n )
    ( show_map `file_map_stream` ( file_map_stream ( string_data path ) ) n )

    ?? ( write_file_bytes ( string_data empty ) ( vec_new [u] ) ) {
        T _ → {}
        F e → { ( nurl_println ( io_err_msg e ) ) ^ 1 }
    }
    ( show_map `empty` ( file_map ( string_data empty ) ) 0 )

    ?? ( file_map ( string_data gone ) ) {
        T _ → { ( nurl_println `missing: mapped?` ) }
        F e → {
            ( nurl_print `missing: ` )
            ( nurl_println ( io_err_msg e ) )
        }
    }

    ?? ( file_delete ( string_data path ) ) {
        T _ → { ( nurl_println `deleted after unmap` ) }
        F e → {
            ( nurl_print `delete failed: ` )
            ( nurl_println ( io_err_msg e ) )
        }
    }
    ?? ( file_delete ( string_data empty ) ) { T _ → {} F _ → {} }
    ^ 0
}
