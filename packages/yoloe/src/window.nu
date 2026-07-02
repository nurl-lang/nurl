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
& `c` @ nurl_poke_i32 *u base i idx i32 val → v
& `c` @ nurl_peek_i32 *u base i idx → i32

// Pointers (Display*, GC, XImage*, data) carried as i64; w/h the frame size.
: XWin { i dpy  i win  i gc  i img  i data  i w  i h  i ok }

@ xwin_ok XWin x → b { ^ != . x ok 0 }

// Open a window of w×h titled `title`. ok=0 if no X display (run headless).
@ xwin_open i w i h s title → XWin {
    : *u dpy ( XOpenDisplay # *u 0 )
    ? == # i dpy 0 { ^ @ XWin { 0 0 0 0 0 w h 0 } } {}
    : i screen ( XDefaultScreen dpy )
    : i root ( XRootWindow dpy screen )
    : *u vis ( XDefaultVisual dpy screen )
    : i depth ( XDefaultDepth dpy screen )
    : i win ( XCreateSimpleWindow dpy root 0 0 w h 0 0 0 )
    ( XStoreName dpy win title )
    ( XSelectInput dpy win 5 )            // KeyPressMask(1) | ButtonPressMask(4)
    : i wmdel ( XInternAtom dpy `WM_DELETE_WINDOW` 0 )
    : *u protos ( nurl_alloc 8 ) ( nurl_poke protos 0 wmdel )
    ( XSetWMProtocols dpy win protos 1 )
    ( nurl_free protos )
    ( XMapWindow dpy win )
    : *u gc ( XCreateGC dpy win 0 # *u 0 )
    : *u data ( nurl_alloc * * w h 4 )     // 32-bit BGRX per pixel
    : *u img ( XCreateImage dpy vis depth 2 0 data w h 32 0 )  // ZPixmap=2, pad 32
    ( XFlush dpy )
    ^ @ XWin { # i dpy win # i gc # i img # i data w h 1 }
}

// Blit one RGB Image into the window. The frame must match the window size.
@ xwin_show XWin x Image im → v {
    ? == . x ok 0 { ^ {} } {}
    : *u data # *u . x data
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
@ xwin_should_close XWin x → b {
    ? == . x ok 0 { ^ T } {}
    : *u dpy # *u . x dpy
    : *u ev ( nurl_alloc 256 )
    : ~ b quit F
    ~ > ( XPending dpy ) 0 {
        ( XNextEvent dpy ev )
        : i t ( nurl_peek_i32 ev 0 )
        // KeyPress(2) ButtonPress(4) DestroyNotify(17) ClientMessage(33)
        ? | | | == t 2 == t 4 == t 17 == t 33 { = quit T } {}
    }
    ( nurl_free ev )
    ^ quit
}

@ xwin_close XWin x → v {
    ? == . x ok 0 { ^ {} } {}
    ( XCloseDisplay # *u . x dpy )
}
