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

& `c` @ ioctl i fd i req *u argp → i
& `c` @ nurl_poke_i32 *u base i idx i val → v
& `c` @ nurl_peek_i32 *u base i idx → i

@ __TIOCGWINSZ → i { ^ 21523 }   // 0x5413; struct winsize { u16 row, col, xpx, ypx }

// Terminal (rows, cols) from ioctl on stdout; sensible fallback off a tty.
@ __winsize *i rowcell → i {           // returns cols, writes rows via cell
    : *u ws ( nurl_alloc 8 )
    ( nurl_poke_i32 ws 0 0 ) ( nurl_poke_i32 ws 1 0 )
    : i r ( ioctl 1 ( __TIOCGWINSZ ) ws )
    : i v ( nurl_peek_i32 ws 0 )       // [row:16][col:16] little-endian
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

// Clear the screen and hide the cursor (call once before a live loop).
@ term_enter → v {
    : String s ( string_with_cap 16 )
    ( string_push_char s 27 ) ( string_push_str s `[2J` )    // clear
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

    // output: out_w cells wide, out_rows cells tall (each cell = 2 px high).
    : ~ i out_w ? < cols 160 cols 160
    : i out_h_px0 / * out_w H W
    : ~ i out_rows / out_h_px0 2
    : i max_rows - rows 2                 // leave a line for status
    ? > out_rows max_rows {
        = out_rows max_rows
        = out_w / * * 2 out_rows W H
        ? > out_w cols { = out_w cols } {}
    } {}
    ? < out_w 1 { = out_w 1 } {}
    ? < out_rows 1 { = out_rows 1 } {}
    : i out_h_px * 2 out_rows

    : String s ( string_with_cap + 64 * * out_w out_rows 40 )
    ( string_push_char s 27 ) ( string_push_str s `[H` )    // cursor home
    : ~ i ry 0
    ~ < ry out_rows {
        : i syt / * * 2 ry H out_h_px
        : i syb / * + * 2 ry 1 H out_h_px
        : ~ i cx 0
        ~ < cx out_w {
            : i sx / * cx W out_w
            : i tr ( img_get im sx syt 0 )
            : i tg ( img_get im sx syt 1 )
            : i tb ( img_get im sx syt 2 )
            : i br ( img_get im sx syb 0 )
            : i bg ( img_get im sx syb 1 )
            : i bb ( img_get im sx syb 2 )
            // ESC [ 38;2;tr;tg;tb;48;2;br;bg;bb m  ▀(U+2580 = 226 150 128)
            ( string_push_char s 27 ) ( string_push_str s `[38;2;` )
            ( __push_num s tr ) ( string_push_char s 59 ) ( __push_num s tg ) ( string_push_char s 59 ) ( __push_num s tb )
            ( string_push_str s `;48;2;` )
            ( __push_num s br ) ( string_push_char s 59 ) ( __push_num s bg ) ( string_push_char s 59 ) ( __push_num s bb )
            ( string_push_char s 109 )   // 'm'
            ( string_push_char s 226 ) ( string_push_char s 150 ) ( string_push_char s 128 )
            = cx + cx 1
        }
        ( string_push_char s 27 ) ( string_push_str s `[0m` )   // reset colours
        ( string_push_char s 10 )                                // newline
        = ry + ry 1
    }
    ( nurl_print ( string_data s ) )
    ( string_free s )
}
