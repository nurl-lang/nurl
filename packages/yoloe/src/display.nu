// packages/yoloe/src/display.nu — show an Image live in the terminal.
//
// Renders a packed-RGB Image as 24-bit-colour half-blocks: each character
// cell is the upper-half-block glyph `▀` whose FOREGROUND colour is one image
// pixel and BACKGROUND colour the pixel just below it — so one cell carries
// two vertical pixels, giving a square-ish picture in any truecolor terminal
// (gnome-terminal, kitty, xterm, … and over SSH). No X11, no SDL, no library.
//
// The frame is scaled to fit the terminal (size via TIOCGWINSZ) preserving
// aspect, built into one String, and printed after homing the cursor so a
// continuous capture loop overwrites in place like a video.

$ `stdlib/core/string.nu`
$ `image.nu`

// `ioctl` as C declares it — `int ioctl(int, unsigned long, ...)`.
// stdlib/std/term.nu declares the same symbol, and one linker symbol
// has one ABI: stating it with `i` where C says `int` is a different
// function, which the compiler now rejects rather than miscompiling.
& `c` @ ioctl i32 fd i req ... → i32

& `c` @ nurl_poke_i32 *u base i idx i32 val → v

& `c` @ nurl_peek_i32 *u base i idx → i32

@ __TIOCGWINSZ → i { ^ 21523 }  // 0x5413; struct winsize { u16 row, col, xpx, ypx }

// Terminal (rows, cols) from ioctl on stdout; sensible fallback off a tty.
@ __winsize * i rowcell → i {  // returns cols, writes rows via cell
    : *u ws ( nurl_alloc 8 )
    ( nurl_poke_i32 ws 0 0 ) ( nurl_poke_i32 ws 1 0 )
    : i r ( ioctl # i32 1 ( __TIOCGWINSZ ) ws )
    : i v ( nurl_peek_i32 ws 0 )  // [row:16][col:16] little-endian
    ( nurl_free ws )
    : ~ i rows & v 65535
    : ~ i cols & >> v 16 65535
    ? | < r 0 == rows 0 { = rows 24 } {}
    ? == cols 0 { = cols 80 } {}
    ( nurl_poke # *u rowcell 0 rows )
    ^ cols
}

// Push the decimal digits of n (0..255) onto a String.
@ __push_num String s i n → v { ( string_push_str s ( nurl_str_int n ) ) }

// Average a source rectangle [x0,x1)×[y0,y1) of `im` into out[0..2] (R,G,B),
// 4-byte slots. This box filter (area average) is what makes the downscaled
// preview look smooth instead of the aliased mess that point-sampling a
// 640-wide frame into ~100 cells produces. At least one pixel is sampled.
@ __avg3 Image im i x0 i x1 i y0 i y1 * u out → v {
    : i xb ? > x1 + x0 1 x1 + x0 1
    : i yb ? > y1 + y0 1 y1 + y0 1
    : ~ i sr 0
    : ~ i sg 0
    : ~ i sb 0
    : ~ i cnt 0
    : ~ i y y0
    ~ < y yb {
        : ~ i x x0
        ~ < x xb {
            = sr + sr ( img_get im x y 0 )
            = sg + sg ( img_get im x y 1 )
            = sb + sb ( img_get im x y 2 )
            = cnt + cnt 1
            = x + x 1
        }
        = y + y 1
    }
    ? == cnt 0 { = cnt 1 } {}
    ( nurl_poke_i32 out 0 / sr cnt )
    ( nurl_poke_i32 out 1 / sg cnt )
    ( nurl_poke_i32 out 2 / sb cnt )
}

// Clear the screen and hide the cursor (call once before a live loop).
@ term_enter → v {
    : String s ( string_with_cap 16 )
    ( string_push_char s 27 ) ( string_push_str s `[2J` )  // clear
    ( string_push_char s 27 ) ( string_push_str s `[?25l` )  // hide cursor
    ( nurl_print ( string_data s ) ) ( string_free s )
}
// Show the cursor again (call when the live loop ends).
@ term_leave → v {
    : String s ( string_with_cap 16 )
    ( string_push_char s 27 ) ( string_push_str s `[?25h` )
    ( string_push_char s 27 ) ( string_push_str s `[0m` )
    ( nurl_print ( string_data s ) ) ( string_free s )
}

// Render `im` to the terminal as truecolor half-blocks, scaled to fit.
@ img_show Image im → v {
    : i W ( img_w im )
    : i H ( img_h im )
    : *i rc # *i ( nurl_alloc 8 )
    : i cols ( __winsize rc )
    : i rows ( nurl_peek # *u rc 0 )
    ( nurl_free # *u rc )

    // Use the FULL terminal width (each cell = 1 px wide × 2 px tall), then
    // pick the row count that preserves aspect, capped to the window height.
    : ~ i out_w cols
    : i out_h_px0 / * out_w H W
    : ~ i out_rows / out_h_px0 2
    : i max_rows - rows 2  // leave a line for the status
    ? > out_rows max_rows {
        = out_rows max_rows
        = out_w / * * 2 out_rows W H
        ? > out_w cols { = out_w cols } {}
    } {}
    ? < out_w 1 { = out_w 1 } {}
    ? < out_rows 1 { = out_rows 1 } {}
    : i out_h_px * 2 out_rows

    : *u tcell ( nurl_alloc 16 )
    : *u bcell ( nurl_alloc 16 )
    : String s ( string_with_cap + 64 * * out_w out_rows 44 )
    ( string_push_char s 27 ) ( string_push_str s `[H` )  // cursor home
    : ~ i ry 0
    ~ < ry out_rows {
        : i syt0 / * * 2 ry H out_h_px
        : i syt1 / * + * 2 ry 1 H out_h_px
        : i syb1 / * + * 2 ry 2 H out_h_px
        : ~ i cx 0
        ~ < cx out_w {
            : i sx0 / * cx W out_w
            : i sx1 / * + cx 1 W out_w
            ( __avg3 im sx0 sx1 syt0 syt1 tcell )  // top pixel (foreground)
            ( __avg3 im sx0 sx1 syt1 syb1 bcell )  // bottom pixel (background)
            // ESC [ 38;2;tr;tg;tb;48;2;br;bg;bb m  ▀(U+2580 = 226 150 128)
            ( string_push_char s 27 ) ( string_push_str s `[38;2;` )
            ( __push_num s ( nurl_peek_i32 tcell 0 ) ) ( string_push_char s 59 )
            ( __push_num s ( nurl_peek_i32 tcell 1 ) ) ( string_push_char s 59 )
            ( __push_num s ( nurl_peek_i32 tcell 2 ) )
            ( string_push_str s `;48;2;` )
            ( __push_num s ( nurl_peek_i32 bcell 0 ) ) ( string_push_char s 59 )
            ( __push_num s ( nurl_peek_i32 bcell 1 ) ) ( string_push_char s 59 )
            ( __push_num s ( nurl_peek_i32 bcell 2 ) )
            ( string_push_char s 109 )  // 'm'
            ( string_push_char s 226 ) ( string_push_char s 150 ) ( string_push_char s 128 )
            = cx + cx 1
        }
        ( string_push_char s 27 ) ( string_push_str s `[0m` )  // reset colours
        ( string_push_char s 10 )  // newline
        = ry + ry 1
    }
    ( nurl_print ( string_data s ) )
    ( string_free s )
    ( nurl_free tcell ) ( nurl_free bcell )
}
