// diag_pfile_read_into_frozen.nu — a read from a file is a write to the
// buffer it fills.
//
// pfile_read_at hands its slice to the C library's pread, which writes
// through it. The FFI declaration says so (a `*u` parameter not declared
// `in` or `sync`), so the call is a change to the slice's storage: handed
// a view a read guard or an Arc lends — shared with other threads reading
// it — it is rejected, here in two spellings. pfile_write_at only reads
// its slice (`in *u`), so writing the same frozen page out to the file is
// fine: that is how a buffer pool flushes a page under a read latch.

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/rwlock.nu`
$ `stdlib/std/pfile.nu`

: Page { ( Vec u ) data }

@ main → i {
    : PFile f ?? ( pfile_open `/tmp/nurl_diag_pfile.dat` PFILE_CREATE ) { T h → h F _ → { ^ 1 } }
    : ( RwLocked Page ) l ( rw_new [Page] @ Page { ( vec_zeroed [u] 64 ) } )
    : ( RGuard Page ) r ( rw_read [Page] l )
    : ( Slice u ) view ( slice_from_vec [u] . ( rguard_get [Page] r ) data )
    ?? ( pfile_write_at f view 0 ) { T _ → {} F _ → {} }
    ?? ( pfile_read_at f view 0 ) { T _ → {} F _ → {} }
    : ( Arc Page ) a ( arc_new [Page] @ Page { ( vec_zeroed [u] 64 ) } )
    ?? ( pfile_read_exact_at f ( slice_from_vec [u] . ( arc_get [Page] a ) data ) 0 ) { T _ → {} F _ → {} }
    ^ 0
}
