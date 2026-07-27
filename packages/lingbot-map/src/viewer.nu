// viewer.nu — look at the cloud.
//
// The reference's demo.py ends in a viser web viewer; this ends in a PLY,
// and this file is what closes that gap. It serves two things on
// localhost: the page, and the bytes of the file that was just written.
//
//   GET /        the viewer, one self-contained HTML document
//   GET /cloud   the PLY, verbatim
//
// The page is compiled into the binary (src/viewer_html_data.nu, generated
// by tools/embed_viewer.py) because `nurlpkg install` ships a binary and
// nothing else — a views/ path next to the executable can never resolve
// for an installed tool. --page FILE overrides it while editing the page.
//
// The cloud is read into memory once and handed out on every request. A
// 286-frame scene is ~129 MB, which is a lot to hold but exactly what the
// browser is about to hold anyway, and it means the file can be replaced
// underneath a running viewer without the server noticing a half-written
// one.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/bytes.nu`
$ `deps/http/src/http.nu`
$ `src/viewer_html_data.nu`

: VwState {
    String page
    String name
    ( Vec u ) cloud
}

: ~ i g_vw 0

// The page as compiled in. `--page FILE` reads from disk instead, which is
// the only way to iterate on the viewer without rebuilding.
@ vw_page s override → String {
    ? > ( nurl_str_len override ) 0 {
        ?? ( read_file override ) {
            T t → { ^ t }
            F _e → {
                ( nurl_print `lingbot-map: cannot read ` ) ( nurl_print override )
                ( nurl_print `, using the built-in page\n` )
            }
        }
    } {}
    : ~ String out ( string_with_cap 24576 )
    : i n ( viewer_html_chunks )
    : ~ i c 0
    ~ < c n { ( string_push_str out ( viewer_html_chunk c ) ) = c + c 1 }
    ^ out
}

@ h_vw_index HttpRequest req Params p → HttpResponse {
    : *VwState st # *VwState g_vw
    : HttpResponse r ( response_new 200 )
    ( response_set_header r `Content-Type` `text/html; charset=utf-8` )
    // the page is regenerated on every build; never let a browser keep one
    ( response_set_header r `Cache-Control` `no-store` )
    ( response_set_body_str r ( string_data . st page ) )
    ^ r
}

@ h_vw_cloud HttpRequest req Params p → HttpResponse {
    : *VwState st # *VwState g_vw
    : HttpResponse r ( response_new 200 )
    ( response_set_header r `Content-Type` `application/octet-stream` )
    // the page shows this instead of the URL, so the window says which
    // cloud is on screen when several are open at once
    ( response_set_header r `X-Cloud-Name` ( string_data . st name ) )
    ( response_set_header r `Cache-Control` `no-store` )
    ( response_set_body_bytes r . st cloud )
    ^ r
}

// Serve `path` until interrupted. Returns a process exit code.
@ vw_serve s path s host i port s page_override i quiet → i {
    : !( Vec u ) IoErr rd ( read_file_bytes path )
    : ~ ( Vec u ) blob ( vec_new [u] )
    ?? rd {
        F _e → {
            ( nurl_print `lingbot-map: cannot read ` ) ( nurl_print path )
            ( nurl_print `\n` )
            ( vec_free [u] blob )
            ^ 1
        }
        T b → { ( vec_free [u] blob ) = blob b }
    }
    ? < ( vec_len [u] blob ) 16 {
        ( nurl_print `lingbot-map: ` ) ( nurl_print path )
        ( nurl_print ` is not a PLY file (too short)\n` )
        ( vec_free [u] blob )
        ^ 1
    } {}
    // "ply" — checked here rather than in the browser so the error names
    // the file the user typed, on the terminal they typed it in
    : *u magic ( vec_data [u] blob )
    ? & & == 112 # i . magic 0 == 108 # i . magic 1 == 121 # i . magic 2 {} {
        ( nurl_print `lingbot-map: ` ) ( nurl_print path )
        ( nurl_print ` does not start with 'ply' — not a point cloud\n` )
        ( vec_free [u] blob )
        ^ 1
    }

    : *VwState st # *VwState ( nurl_alloc Z VwState )
    = . st page ( vw_page page_override )
    = . st name ( path_basename path )
    = . st cloud blob
    = g_vw # i st

    : *HttpApp a ( http_app_new )
    ( http_app_get a `/` \ HttpRequest rq Params pp → HttpResponse { ^ ( h_vw_index rq pp ) } )
    ( http_app_get a `/cloud` \ HttpRequest rq Params pp → HttpResponse { ^ ( h_vw_cloud rq pp ) } )
    ( http_app_quiet a )
    // one browser, a page and a cloud: a single worker is the whole load,
    // and a long idle would hold the connection open after the fetch
    ( http_app_idle_ms a 2000 )
    ( http_app_body_max a 1024 )

    ? == quiet 0 {
        ( nurl_print `viewer  http://` ) ( nurl_print host )
        ( nurl_print `:` ) ( nurl_print ( nurl_str_int port ) )
        ( nurl_print `\ncloud   ` ) ( nurl_print path )
        ( nurl_print `  ` )
        ( nurl_print ( nurl_str_int / ( vec_len [u] blob ) 1048576 ) )
        ( nurl_print ` MB\nCtrl-C to stop\n` )
    } {}

    : i rc ( http_app_listen a ( string_data ( string_from host ) ) port )
    ( http_app_free a )
    ^ ? == rc 0 0 1
}
