// packages/yoloe/src/v4l2.nu — webcam capture in pure NURL via Video4Linux2.
//
// Opens /dev/videoN, negotiates a YUYV capture format, sets up memory-mapped
// streaming buffers, and hands back decoded RGB frames — no ffmpeg, no
// OpenCV, just open/ioctl/mmap on the kernel's V4L2 ABI through the FFI. The
// ioctl request codes and struct field offsets below are the stable x86_64
// <linux/videodev2.h> layout (verified against the system headers):
//
//   v4l2_format          208 B  type@0  pix.width@8 height@12 pixelformat@16 field@20
//   v4l2_requestbuffers   20 B  count@0 type@4 memory@8
//   v4l2_buffer           88 B  index@0 type@4 bytesused@8 memory@60 m.offset@64 length@72
//
// Frames arrive as YUYV (4:2:2, 2 bytes/pixel) and are converted to packed
// RGB with the BT.601 integer transform. One Camera owns the fd plus the
// mmap'd ring of capture buffers: it is a handle, every copy is the same
// stream, and its last owner stops it, unmaps the ring and closes the fd
// (cam_close does that now — an optional early release).

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
// open / close / mmap / munmap come from the stdlib, which has the
// REAL C prototypes (`int open(const char *, int, ...)` and friends).
// This file used to restate them with `i` where C says `int`, which is
// a different ABI for the same linker symbol — and the compiler now
// says so instead of emitting a call the module never declared.
$ `stdlib/core/posix.nu`
$ `stdlib/core/rcbox.nu`

// `ioctl` as C declares it — `int ioctl(int, unsigned long, ...)`.
// stdlib/std/term.nu declares the same symbol, and one linker symbol
// has one ABI: stating it with `i` where C says `int` is a different
// function, which the compiler now rejects rather than miscompiling.
& `c` @ ioctl i32 fd i req ... → i32

& `c` @ nurl_peek_i32 *u base i idx → i32

& `c` @ nurl_poke_i32 *u base i idx i32 val → v

// A streaming webcam: fd, frame geometry, and the mmap'd buffer ring.
: CameraImpl { i fd i w i h i nbuf ( Vec i ) bufptr ( Vec i ) buflen i ok }

% Drop CameraImpl { @ drop CameraImpl c → v { ( __cam_release c ) } }

: Camera { s ctl }

unsafe @ Camera_share Camera h → Camera { ^ @ Camera { # s ( rcbox_share # i . h ctl ) } }

@ Camera_drop sink Camera h → v { ( mem_forget h ) ( rcbox_release [CameraImpl] # i . h ctl ) }

unsafe @ __Camera_ptr Camera h → *CameraImpl { ^ ( rcbox_ptr [CameraImpl] # i . h ctl ) }

unsafe @ __cam_new CameraImpl c → Camera { ^ @ Camera { # s ( rcbox_new [CameraImpl] c ) } }

@ __O_RDWR → i { ^ 2 }

@ __VIDIOC_S_FMT → i { ^ 3234878981 }  // 0xc0d05605
@ __VIDIOC_REQBUFS → i { ^ 3222558216 }  // 0xc0145608
@ __VIDIOC_QUERYBUF → i { ^ 3227014665 }  // 0xc0585609
@ __VIDIOC_QBUF → i { ^ 3227014671 }  // 0xc058560f
@ __VIDIOC_DQBUF → i { ^ 3227014673 }  // 0xc0585611
@ __VIDIOC_STREAMON → i { ^ 1074026002 }  // 0x40045612
@ __VIDIOC_STREAMOFF → i { ^ 1074026003 }  // 0x40045613
@ __PIXFMT_YUYV → i { ^ 1448695129 }  // 0x56595559 'YUYV'
@ __BUF_TYPE_CAPTURE → i { ^ 1 }

@ __MEMORY_MMAP → i { ^ 1 }

@ __FIELD_NONE → i { ^ 1 }

@ __PROT_RW → i { ^ 3 }

@ __MAP_SHARED → i { ^ 1 }

// Zero `nslots` 4-byte slots of a buffer.
unsafe @ __zero * u b i nslots → v {
    : ~ i k 0
    ~ < k nslots { ( nurl_poke_i32 b k 0 ) = k + k 1 }
}

// Open a webcam and start YUYV streaming at w×h with `nbuf` ring buffers.
unsafe @ cam_open s path i w i h i nbuf → Camera {
    : i fd # i ( open path # i32 ( __O_RDWR ) )
    ? < fd 0 { ^ ( __cam_new @ CameraImpl { - 0 1 w h 0 ( vec_new [i] ) ( vec_new [i] ) 0 } ) } {}

    // VIDIOC_S_FMT: request YUYV w×h, progressive.
    : ( Vec u ) fmtv ( vec_zeroed [u] 208 )
    : *u fmt ( vec_data [u] fmtv )
    ( nurl_poke_i32 fmt 0 ( __BUF_TYPE_CAPTURE ) )  // type @0
    ( nurl_poke_i32 fmt 2 w )  // pix.width @8
    ( nurl_poke_i32 fmt 3 h )  // pix.height @12
    ( nurl_poke_i32 fmt 4 ( __PIXFMT_YUYV ) )  // pix.pixelformat @16
    ( nurl_poke_i32 fmt 5 ( __FIELD_NONE ) )  // pix.field @20
    : i rf ( ioctl # i32 fd ( __VIDIOC_S_FMT ) fmt )
    ? < rf 0 { ( close fd )
        ^ ( __cam_new @ CameraImpl { - 0 1 w h 0 ( vec_new [i] ) ( vec_new [i] ) 0 } ) } {}
    // the driver may adjust geometry — read back what it granted
    : i aw ( nurl_peek_i32 fmt 2 )
    : i ah ( nurl_peek_i32 fmt 3 )

    // VIDIOC_REQBUFS: nbuf mmap buffers.
    : ( Vec u ) rbv ( vec_zeroed [u] 20 )
    : *u rb ( vec_data [u] rbv )
    ( nurl_poke_i32 rb 0 nbuf )  // count @0
    ( nurl_poke_i32 rb 1 ( __BUF_TYPE_CAPTURE ) )  // type @4
    ( nurl_poke_i32 rb 2 ( __MEMORY_MMAP ) )  // memory @8
    : i rr ( ioctl # i32 fd ( __VIDIOC_REQBUFS ) rb )
    : i got ( nurl_peek_i32 rb 0 )
    ? | < rr 0 < got 1 { ( close fd )
        ^ ( __cam_new @ CameraImpl { - 0 1 aw ah 0 ( vec_new [i] ) ( vec_new [i] ) 0 } ) } {}

    // Query + mmap each buffer, then queue it.
    : ( Vec i ) ptrs ( vec_new [i] )
    : ( Vec i ) lens ( vec_new [i] )
    : ~ b allok T
    : ( Vec u ) bfv ( vec_zeroed [u] 88 )
    : *u bf ( vec_data [u] bfv )
    : ~ i bi 0
    ~ < bi got {
        ( __zero bf 22 )
        ( nurl_poke_i32 bf 0 bi )  // index @0
        ( nurl_poke_i32 bf 1 ( __BUF_TYPE_CAPTURE ) )  // type @4
        ( nurl_poke_i32 bf 15 ( __MEMORY_MMAP ) )  // memory @60
        : i qr ( ioctl # i32 fd ( __VIDIOC_QUERYBUF ) bf )
        : i moff ( nurl_peek_i32 bf 16 )  // m.offset @64
        : i blen ( nurl_peek_i32 bf 18 )  // length @72
        ? < qr 0 { = allok F } {
            : *u m ( mmap # *u 0 blen # i32 ( __PROT_RW ) # i32 ( __MAP_SHARED ) # i32 fd moff )
            ? | == # i m 0 == # i m - 0 1 { = allok F } {
                ( vec_push [i] ptrs # i m )
                ( vec_push [i] lens blen )
                // queue the buffer for capture
                ( ioctl # i32 fd ( __VIDIOC_QBUF ) bf )
            }
        }
        = bi + bi 1
    }

    // STREAMON
    : ( Vec u ) tv ( vec_zeroed [u] 4 )
    : *u t ( vec_data [u] tv )
    ( nurl_poke_i32 t 0 ( __BUF_TYPE_CAPTURE ) )
    : i so ( ioctl # i32 fd ( __VIDIOC_STREAMON ) t )
    // a stream that did not start still has its ring mapped: the drop unmaps it
    ? | < so 0 ! allok { ( close fd )
        ^ ( __cam_new @ CameraImpl { - 0 1 aw ah got ptrs lens 0 } ) } {}
    ^ ( __cam_new @ CameraImpl { fd aw ah got ptrs lens 1 } )
}

unsafe @ cam_ok Camera h → b { : *CameraImpl c ( __Camera_ptr h ) ^ != . c ok 0 }

unsafe @ cam_w Camera h → i { : *CameraImpl c ( __Camera_ptr h ) ^ . c w }

unsafe @ cam_h Camera h → i { : *CameraImpl c ( __Camera_ptr h ) ^ . c h }

@ __clip255 i v → i { ^ ? < v 0 0 ? > v 255 255 v }

// Grab one frame: dequeue a filled buffer, convert YUYV→RGB into `rgb`
// (packed, 3 bytes/pixel, w*h*3 bytes), and requeue. Returns T on success.
unsafe @ cam_grab Camera cam__h ( Vec u ) rgb → b {
    : *CameraImpl c ( __Camera_ptr cam__h )
    : ( Vec u ) bfv ( vec_zeroed [u] 88 )
    : *u bf ( vec_data [u] bfv )
    ( nurl_poke_i32 bf 1 ( __BUF_TYPE_CAPTURE ) )  // type @4
    ( nurl_poke_i32 bf 15 ( __MEMORY_MMAP ) )  // memory @60
    : i dr ( ioctl # i32 . c fd ( __VIDIOC_DQBUF ) bf )
    ? < dr 0 { ^ F } {}
    : i idx ( nurl_peek_i32 bf 0 )  // index @0
    : *u src # *u ?? ( vec_get [i] . c bufptr idx ) { T x → x F _ → 0 }
    : i w . c w
    : i h . c h
    // YUYV: each 4-byte group (one i32) is two pixels: Y0 U Y1 V (LE bytes).
    : i npix * w h
    : i ngrp / npix 2
    : ~ i gi 0
    ~ < gi ngrp {
        // widen the i32 group to i before masking (& needs matching types)
        : i v & # i ( nurl_peek_i32 src gi ) 4294967295
        : i y0 & v 255
        : i uu & >> v 8 255
        : i y1 & >> v 16 255
        : i vv & >> v 24 255
        : i d - uu 128
        : i ee - vv 128
        : i c0 - y0 16
        : i c1 - y1 16
        // BT.601 full transform, fixed-point /256
        : i r0 ( __clip255 >> + + * 298 c0 * 409 ee 128 8 )
        : i g0 ( __clip255 >> - - + * 298 c0 128 * 100 d * 208 ee 8 )
        : i b0 ( __clip255 >> + + * 298 c0 * 516 d 128 8 )
        : i r1 ( __clip255 >> + + * 298 c1 * 409 ee 128 8 )
        : i g1 ( __clip255 >> - - + * 298 c1 128 * 100 d * 208 ee 8 )
        : i b1 ( __clip255 >> + + * 298 c1 * 516 d 128 8 )
        : i o * gi 6
        ( vec_set [u] rgb + o 0 # u r0 ) ( vec_set [u] rgb + o 1 # u g0 ) ( vec_set [u] rgb + o 2 # u b0 )
        ( vec_set [u] rgb + o 3 # u r1 ) ( vec_set [u] rgb + o 4 # u g1 ) ( vec_set [u] rgb + o 5 # u b1 )
        = gi + gi 1
    }
    // requeue this buffer
    ( ioctl # i32 . c fd ( __VIDIOC_QBUF ) bf )
    ^ T
}

// Stop streaming, unmap the ring and close the fd.
unsafe @ __cam_release_parts i fd i nbuf ( Vec i ) ptrs ( Vec i ) lens → v {
    ? >= fd 0 {
        : ( Vec u ) tv ( vec_zeroed [u] 4 )
        : *u t ( vec_data [u] tv )
        ( nurl_poke_i32 t 0 ( __BUF_TYPE_CAPTURE ) )
        ( ioctl # i32 fd ( __VIDIOC_STREAMOFF ) t )
    } {}
    : ~ i k 0
    ~ < k nbuf {
        : *u m # *u ?? ( vec_get [i] ptrs k ) { T x → x F _ → 0 }
        : i ln ?? ( vec_get [i] lens k ) { T x → x F _ → 0 }
        ? != # i m 0 { ( munmap m ln ) } {}
        = k + k 1
    }
    ? >= fd 0 { ( close fd ) } {}
}

@ __cam_release CameraImpl c → v { ( __cam_release_parts . c fd . c nbuf . c bufptr . c buflen ) }

// Release the camera now (optional — its last owner does it anyway). The
// fields are cleared, so the drop finds nothing left to release.
unsafe @ cam_close Camera h → v {
    : *CameraImpl c ( __Camera_ptr h )
    ( __cam_release_parts . c fd . c nbuf . c bufptr . c buflen )
    = . c nbuf 0
    = . c fd - 0 1
    = . c ok 0
}
