// zip_archive_outlives_its_bytes: zip_open (stdlib/ext/zip.nu) was safe, and the archive it returned kept a bare pointer into the caller's Vec: the Vec could go first, and every read of the archive after it read freed memory.
// Closed: a ZipArchive reads a MappedFile it owns or shares (stdlib/std/mmap.nu) — zip_open keeps a copy of the bytes, zip_open_owned takes them over, zip_open_mapped shares a mapping — through checked views; zip_open_ptr is gone.
// main's compiler: heap-use-after-free.
// map: §6.4 | B | runs-clean | h260 | stdlib ZipArchive kept bare pointer into caller's Vec; Vec freed first
$ `stdlib/core/io.nu`
$ `stdlib/ext/zip.nu`

@ open_tmp → !ZipArchive ZipErr {
    : Zip z ( zip_new )
    : !v ZipErr _a ( zip_add_stored z `a.txt` ( bytes_from_str `hello zip world` ) )
    : ( Vec u ) bytes ( zip_finish z )
    ^ ( zip_open bytes )
}

@ main → i {
    ?? ( open_tmp ) {
        T za → {
            ?? ( zip_extract za 0 ) { T d → { ( nurl_println_int ( vec_len [u] d ) ) } F _ → { ( nurl_println `err` ) } }
        }
        F _ → { ( nurl_println `open err` ) }
    }
    ^ 0
}
