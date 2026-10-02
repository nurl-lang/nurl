// packages/yoloe/src/window.nu — a real GUI window for the live preview, in
// pure NURL via Xlib (libX11) bound directly — no SDL, no GTK, no toolkit.
//
// Opens an X11 window the size of the camera frame and blits each segmented
// RGB frame at full resolution with XPutImage (so unlike the terminal view
// there's no down-scaling). Polls for a keypress / window-close so the loop
// can exit cleanly. The toolchain auto-links -lX11 only when `@XOpenDisplay`
// appears (build.sh writes the `runtime.X11` sentinel when libX11 is found),
// so a headless build is unaffected.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/rcbox.nu`
$ `image.nu`

& `X11` @ XOpenDisplay *u name → *u

& `X11` @ XDefaultScreen *u dpy → i

& `X11` @ XRootWindow *u dpy i screen → i

& `X11` @ XDefaultVisual *u dpy i screen → *u

& `X11` @ XDefaultDepth *u dpy i screen → i

& `X11` @ XCreateSimpleWindow *u dpy i parent i x i y i w i h i bw i border i bg → i

& `X11` @ XStoreName *u dpy i win s name → i

& `X11` @ XSelectInput *u dpy i win i mask → i

& `X11` @ XMapWindow *u dpy i win → i

& `X11` @ XCreateGC *u dpy i drawable i valuemask *u values → *u

& `X11` @ XCreateImage *u dpy *u visual i depth i format i offset *u data i width i height i pad i bpl → *u

& `X11` @ XPutImage *u dpy i d *u gc *u image i sx i sy i dx i dy i w i h → i

& `X11` @ XFlush *u dpy → i

& `X11` @ XPending *u dpy → i

& `X11` @ XNextEvent *u dpy *u event → i

& `X11` @ XInternAtom *u dpy s name i only → i

& `X11` @ XSetWMProtocols *u dpy i win *u protocols i count → i

& `X11` @ XCloseDisplay *u dpy → i

& `X11` @ XDestroyImage *u image → i

& `X11` @ XFreeGC *u dpy *u gc → i

& `c` @ nurl_poke_i32 *u base i idx i32 val → v

& `c` @ nurl_peek_i32 *u base i idx → i32

// Pointers (Display*, GC, XImage*) carried as i64; w/h the frame size. The
// pixel buffer the XImage points at is the window's own Vec.
: XWinImpl { i dpy i win i gc i img ( Vec u ) data i w i h i ok }

% Drop XWinImpl { @ drop XWinImpl x → v { ( __xwin_release . x dpy . x gc . x img ) } }

// A window is a handle: every copy is the same window, and its last owner
// closes the display connection (xwin_close does that now — an optional
// early release).
: XWin { s ctl }

@ XWin_share XWin h → XWin { ^ @ XWin { # s ( rcbox_share # i . h ctl ) } }

@ XWin_drop sink XWin h → v { ( mem_forget h ) ( rcbox_release [XWinImpl] # i . h ctl ) }

@ __XWin_ptr XWin h → *XWinImpl { ^ ( rcbox_ptr [XWinImpl] # i . h ctl ) }

// The window that never opened (ok=0): w×h is still the frame size.
@ xwin_none i w i h → XWin { ^ @ XWin { # s ( rcbox_new [XWinImpl] @ XWinImpl { 0 0 0 0 ( vec_new [u] ) w h 0 } ) } }

@ xwin_ok XWin h → b { : *XWinImpl x ( __XWin_ptr h ) ^ != . x ok 0 }

// Free the XImage (not its pixels — they are the Vec's: XDestroyImage frees
// a non-null data pointer, so it is cleared first) and the GC, and close the
// display, which releases the window with it.
@ __xwin_release i dpy i gc i img → v {
    ? != img 0 {
        ( nurl_poke # *u img 2 0 )  // XImage.data @16
        ( XDestroyImage # *u img )
    } {}
    ? & != dpy 0 != gc 0 { ( XFreeGC # *u dpy # *u gc ) } {}
    ? != dpy 0 { ( XCloseDisplay # *u dpy ) } {}
}

// Open a window of w×h titled `title`. ok=0 if no X display (run headless).
@ xwin_open i w i h s title → XWin {
    : *u dpy ( XOpenDisplay # *u 0 )
    ? == # i dpy 0 { ^ ( xwin_none w h ) } {}
    : i screen ( XDefaultScreen dpy )
    : i root ( XRootWindow dpy screen )
    : *u vis ( XDefaultVisual dpy screen )
    : i depth ( XDefaultDepth dpy screen )
    : i win ( XCreateSimpleWindow dpy root 0 0 w h 0 0 0 )
    ( XStoreName dpy win title )
    ( XSelectInput dpy win 5 )  // KeyPressMask(1) | ButtonPressMask(4)
    : i wmdel ( XInternAtom dpy `WM_DELETE_WINDOW` 0 )
    : ( Vec u ) protov ( vec_zeroed [u] 8 )
    : *u protos ( vec_data [u] protov )
    ( nurl_poke protos 0 wmdel )
    ( XSetWMProtocols dpy win protos 1 )
    ( XMapWindow dpy win )
    : *u gc ( XCreateGC dpy win 0 # *u 0 )
    : ( Vec u ) data ( vec_zeroed [u] * * w h 4 )  // 32-bit BGRX per pixel
    : *u img ( XCreateImage dpy vis depth 2 0 ( vec_data [u] data ) w h 32 0 )  // ZPixmap=2, pad 32
    ( XFlush dpy )
    ^ @ XWin { # s ( rcbox_new [XWinImpl] @ XWinImpl { # i dpy win # i gc # i img data w h 1 } ) }
}

// Blit one RGB Image into the window. The frame must match the window size.
@ xwin_show XWin x__h Image im → v {
    : *XWinImpl x ( __XWin_ptr x__h )
    ? == . x ok 0 { ^ {} } {}
    : *u data ( vec_data [u] . x data )
    : i w . x w
    : i h . x h
    : ~ i y 0
    ~ < y h {
        : i row * y w
        : ~ i xx 0
        ~ < xx w {
            // TrueColor depth-24/32 pixel = R<<16 | G<<8 | B (LE bytes B,G,R,0)
            : i px | | << ( img_get im xx y 0 ) 16 << ( img_get im xx y 1 ) 8 ( img_get im xx y 2 )
            ( nurl_poke_i32 data + row xx px )
            = xx + xx 1
        }
        = y + y 1
    }
    : *u dpy # *u . x dpy
    ( XPutImage dpy . x win # *u . x gc # *u . x img 0 0 0 0 w h )
    ( XFlush dpy )
}

// Drain pending events; return T if the user asked to close (key, click, or
// the window-manager close button).
@ xwin_should_close XWin x__h → b {
    : *XWinImpl x ( __XWin_ptr x__h )
    ? == . x ok 0 { ^ T } {}
    : *u dpy # *u . x dpy
    : ( Vec u ) evv ( vec_zeroed [u] 256 )  // an XEvent
    : *u ev ( vec_data [u] evv )
    : ~ b quit F
    ~ > ( XPending dpy ) 0 {
        ( XNextEvent dpy ev )
        : i t ( nurl_peek_i32 ev 0 )
        // KeyPress(2) ButtonPress(4) DestroyNotify(17) ClientMessage(33)
        ? | | | == t 2 == t 4 == t 17 == t 33 { = quit T } {}
    }
    ^ quit
}

// Close the window now (optional — its last owner does it anyway).
@ xwin_close XWin x__h → v {
    : *XWinImpl x ( __XWin_ptr x__h )
    ( __xwin_release . x dpy . x gc . x img )
    = . x dpy 0
    = . x gc 0
    = . x img 0
    = . x ok 0
}
