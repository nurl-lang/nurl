// --debug at -O2 over the memory-model helpers (`__nurl_cloneif_*`,
// `__nurl_clone_*`, `__dropif_*`, `__nurl_ret_own`, …): they are printed
// as literal IR with no `!dbg`, and a location-less call to one that
// inlines a function WITH a subprogram (here: HttpConn_share through
// `__nurl_cloneif_HttpConn` in http_pure's __hp_take_conn) left the
// inlined instructions in the wrong subprogram — clang then died in
// DwarfDebug::finalizeModuleInfo. tools/dwarf_test.sh builds this with
// --debug at -O2; linking at all is the assertion. As a plain test it
// only has to run: a stream that was never opened releases nothing.
$ `stdlib/ext/http_pure.nu`

@ main → i {
    : b open F
    ? open {
        : HttpStreamState st ( hp_stream_open `GET` `http://127.0.0.1:1/` # *u 0 0 `` 0 0 0 `` 1000 )
        ?? ( hp_stream_release st ) {
            T c → { ( hp_conn_close c ) }
            F → {}
        }
        : HttpStreamState st2 ( hp_stream_open `GET` `http://127.0.0.1:1/` # *u 0 0 `` 0 0 0 `` 1000 )
        ( hp_stream_close st2 )
    } {}
    ( nurl_println `dwarf hown helpers: ok` )
    ^ 0
}
