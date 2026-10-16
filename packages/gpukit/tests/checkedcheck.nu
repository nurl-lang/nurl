// tests/checkedcheck.nu — gk_run_checked: which bodies the subset takes,
// and what a checked kernel does on the CPU backend, out-of-range indices
// included. Prints one `ok …` / `FAIL …` line per case and a summary.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/floatbits.nu`
$ `src/checked.nu`
$ `src/dev.nu`

: ~ i g_fail 0

@ verdict GpuKit kit s body b want → v {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_in_f c `x` ( vec_zeroed [f] 4 ) )
    ( gk_call_out_f c `y` ( vec_zeroed [f] 4 ) )
    ( gk_call_i64 c `n` 4 )
    : b ok ( gk_run_checked kit c `t` body 4 64 )
    ? == ok want { ( nurl_print `ok   ` ) } { ( nurl_print `FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print ? want `accepts ` `rejects ` ) ( nurl_print body )
    ? ok {} { ( nurl_print `  (` ) ( nurl_print ( gk_checked_error c ) ) ( nurl_print `)` ) }
    ( nurl_print `\n` )
}

@ subset GpuKit kit → v {
    ( verdict kit `ST(y, gid, 2.0 * LD(x, gid));` T )
    ( verdict kit `double a = LD(x, gid) * 3.5e-2; if (a > 1.0) { ST(y, gid, a); }` T )
    ( verdict kit `for (long long k = 0; k < n; k++) { ST(y, k, LD(x, k) + 1.0); }` T )
    ( verdict kit `double s = __dadd_rn(LD(x, 0), .5); ST(y, gid & 3, s);` T )
    ( verdict kit `long long v = gid; v *= 2; v &= 3; ST(y, v, (double)(long long)v);` T )
    ( verdict kit `double* p = 0; *p = 1.0;` F )
    ( verdict kit `double *p;` F )
    ( verdict kit `ST(y, gid, *(&n));` F )
    ( verdict kit `long long a = n; long long b = &a;` F )
    ( verdict kit `__gk_p0[gid] = 1.0;` F )
    ( verdict kit `double q = __gk_n0;` F )
    ( verdict kit `ST(x, gid, 1.0);` F )
    ( verdict kit `LOCAL_D(a, 3); ST(a, 1, 2.0); ST(y, gid, LD(a, 1) + LD(a, 7));` T )
    ( verdict kit `LOCAL_D(x, 4);` F )
    ( verdict kit `LOCAL_D(a, 2); LOCAL_F(a, 2);` F )
    ( verdict kit `if (gid > 0) { LOCAL_D(a, 2); }` F )
    ( verdict kit `LOCAL_D(a, 2000);` F )
    ( verdict kit `LOCAL_D(a, n);` F )
    ( verdict kit `UNROLL for (int k = 0; k < 4; k++) { ST(y, gid, LD(x, k)); }` T )
    ( verdict kit `double UNROLL = 1.0;` F )
    ( verdict kit `double v = SHFL_DOWN(1.0, 1);` F )
    ( verdict kit `ST(z, gid, 1.0);` F )
    ( verdict kit `} extern "C" void evil() {` F )
    ( verdict kit `printf("hi");` F )
    ( verdict kit `asm("nop");` F )
    ( verdict kit `#define X 1` F )
    ( verdict kit `struct S { int a; };` F )
    ( verdict kit `memcpy(0, 0, 4);` F )
    ( verdict kit `double v = n[0];` F )
    ( verdict kit `double v = blockIdx.x;` F )
    ( verdict kit `auto f = [](){};` F )
    ( verdict kit `ST(y, gid, static_cast<double>(n));` F )
    ( verdict kit `goto out; out: ;` F )
}

// Run a checked kernel for real: in-range work, an index past the end and
// a negative one (a load reads the last element, a store is dropped).
@ run GpuKit kit → v {
    : ~ ( Vec f ) xs ( vec_new [f] )
    ( vec_push [f] xs 1.5 ) ( vec_push [f] xs 2.5 ) ( vec_push [f] xs 3.5 ) ( vec_push [f] xs 4.5 )
    : ~ GkCall c ( gk_call_new )
    ( gk_call_in_f c `x` xs )
    ( gk_call_out_f c `y` ( vec_zeroed [f] 6 ) )
    ( gk_call_i64 c `n` 4 )
    // thread 4 reads x[4] (past the end → x[3]); thread 5 stores at -1 (dropped)
    : b ok ( gk_run_checked kit c `checked_run` `if (gid < 5) ST(y, gid, 2.0 * LD(x, gid)); else ST(y, -1, 99.0);` 6 64 )
    : ( Vec f ) ys ( gk_call_take_f c `y` )
    : ~ String got ( string_new )
    : ~ i k 0
    ~ < k ( vec_len [f] ys ) { ? > k 0 { ( string_push_char got 44 ) } {} ( string_push_float got ( vec_at [f] ys k ) ) = k + k 1 }
    : b want_ok ( nurl_str_eq ( string_data got ) `3,5,7,9,9,0` )
    ? & ok != 0 want_ok { ( nurl_print `ok   checked kernel ran: ` ) } { ( nurl_print `FAIL checked kernel ran: ` ) = g_fail + g_fail 1 }
    ( nurl_print ( string_data got ) ) ( nurl_print `\n` )
}

// Inputs bound as views (gk_call_view_f / _i): read in place, an index
// past the end of either reads its last element.
@ run_views GpuKit kit → v {
    : ~ ( Vec f ) xs ( vec_new [f] )
    ( vec_push [f] xs 1.5 ) ( vec_push [f] xs 2.5 ) ( vec_push [f] xs 3.5 )
    : ~ ( Vec i ) ks ( vec_new [i] )
    ( vec_push [i] ks 2 ) ( vec_push [i] ks 0 ) ( vec_push [i] ks 7 )
    : ~ GkCall c ( gk_call_new )
    ( gk_call_view_f c `x` ( slice_from_vec [f] xs ) )
    ( gk_call_view_i c `k` ( slice_from_vec [i] ks ) )
    ( gk_call_out_f c `y` ( vec_zeroed [f] 4 ) )
    : b ok ( gk_run_checked kit c `checked_views` `ST(y, gid, LD(x, LD(k, gid)) + (double)gid);` 4 64 )
    : ( Vec f ) ys ( gk_call_take_f c `y` )
    : ~ String got ( string_new )
    : ~ i j 0
    ~ < j ( vec_len [f] ys ) { ? > j 0 { ( string_push_char got 44 ) } {} ( string_push_float got ( vec_at [f] ys j ) ) = j + j 1 }
    : b want_ok ( nurl_str_eq ( string_data got ) `3.5,2.5,5.5,6.5` )
    ? & ok != 0 want_ok { ( nurl_print `ok   checked kernel over views: ` ) } { ( nurl_print `FAIL checked kernel over views: ` ) = g_fail + g_fail 1 }
    ( nurl_print ( string_data got ) ) ( nurl_print `\n` )
}

// Block launches: which cooperative bodies are taken (SYNC() only where the
// whole block arrives), over device buffers x (read, 256 doubles), cnt
// (read, i64 [3]) and o (written, 256 doubles), scalar n = 256.
@ dverdict GpuKit kit s body b want → v {
    : GkBuf x ( gk_dbuf_new kit 256 GK_F64 )
    : GkBuf cnt ( gk_dbuf_new kit 1 GK_I64 )
    : GkBuf o ( gk_dbuf_new kit 256 GK_F64 )
    : b _u ( gk_dbuf_upload_i kit cnt ( vec_zeroed [i] 1 ) )
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev_in c `x` x )
    ( gk_call_dev_in c `cnt` cnt )
    ( gk_call_dev c `o` o )
    ( gk_call_i64 c `n` 256 )
    : b ok ( gk_run_checked_dev kit c `dv` body 2 64 )
    ? == ok want { ( nurl_print `ok   ` ) } { ( nurl_print `FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print ? want `accepts ` `rejects ` ) ( nurl_print body )
    ? ok {} { ( nurl_print `  (` ) ( nurl_print ( gk_checked_error c ) ) ( nurl_print `)` ) }
    ( nurl_print `\n` )
}

@ dsubset GpuKit kit → v {
    ( dverdict kit `SHARED_D(t, 64); ST(t, tid, LD(x, gid)); SYNC(); ST(o, gid, LD(t, bdim - 1 - tid));` T )
    ( dverdict kit `for (long long s = bdim / 2; s > 0; s = s / 2) { SYNC(); }` T )
    ( dverdict kit `long long m = bdim / 2; while (m > 0) { SYNC(); m = m / 2; }` T )
    ( dverdict kit `for (long long k = 0; k < LD(cnt, 0); k++) { SYNC(); }` T )
    ( dverdict kit `if (bid == 0) { SYNC(); } else { SYNC(); }` T )
    ( dverdict kit `if (tid == 0) { ST(o, bid, 1.0); } SYNC();` T )
    ( dverdict kit `if (tid == 0) { SYNC(); }` F )
    ( dverdict kit `if (gid < n) { SYNC(); }` F )
    ( dverdict kit `long long m = tid; for (long long k = 0; k < m; k++) { SYNC(); }` F )
    ( dverdict kit `long long m = 4; if (tid == 0) { m = 3; } for (long long k = 0; k < m; k++) { SYNC(); }` F )
    ( dverdict kit `for (long long k = 0; k < LD(o, 0); k++) { SYNC(); }` F )
    ( dverdict kit `SHARED_D(t, 4); for (long long k = 0; k < LD(t, 0); k++) { SYNC(); }` F )
    ( dverdict kit `if (bid == 0) { if (tid == 0) { ST(o, 0, 1.0); } else { SYNC(); } }` F )
    ( dverdict kit `if (tid > 0) { ST(o, 0, 1.0); } else if (bid == 0) { SYNC(); }` F )
    ( dverdict kit `if (tid == 0) { return; } SYNC();` F )
    ( dverdict kit `for (long long k = 0; k < 4; k++) { if (tid == k) { break; } SYNC(); }` F )
    ( dverdict kit `if (bid == 0) SYNC();` F )
    ( dverdict kit `if (bid == 0) { SHARED_D(t, 4); }` F )
    ( dverdict kit `SHARED_D(t, 5000);` F )
    ( dverdict kit `SHARED_D(x, 4);` F )
    ( dverdict kit `__syncthreads();` F )
    ( dverdict kit `double z; ST(o, gid, z);` T )
    ( dverdict kit `double a = 1.0, z; ST(o, gid, a + z);` T )
    ( dverdict kit `ST(x, gid, 1.0);` F )
    ( dverdict kit `double v = LD(x, gid); for (int off = 16; off > 0; off >>= 1) { v += SHFL_DOWN(v, off); } ST(o, gid, v);` T )
    ( dverdict kit `double v = LD(x, gid); if (tid < 16) { v = SHFL_XOR(v, 1); } ST(o, gid, v);` F )
    ( dverdict kit `double v = 1.0; for (int k = 0; k < tid; k++) { v = SHFL_DOWN(v, 1); }` F )
    ( dverdict kit `if (tid == 0) { return; } double v = SHFL_DOWN(1.0, 1);` F )
    ( dverdict kit `LOCAL_F(acc, 8); UNROLL for (int j = 0; j < 8; j++) { ST(acc, j, LD(x, gid + j)); } ST(o, gid, LD(acc, 3));` T )
    ( dverdict kit `SHARED_D(t, 4); LOCAL_D(t, 4);` F )
}

// A block launch for real: each block sums its 64 inputs in a shared array
// (a tree reduction with a barrier per level) and its thread 0 stores the
// sum; f32 buffers through SHARED_F; a buffer read and written at once is
// refused; and a second kernel given the first one's name runs its own body.
@ drun GpuKit kit → v {
    : ~ ( Vec f ) xs ( vec_new [f] )
    : ~ i k 0
    ~ < k 256 { ( vec_push [f] xs # f + k 1 ) = k + k 1 }
    : GkBuf x ( gk_dbuf_new kit 256 GK_F64 )
    : GkBuf o ( gk_dbuf_new kit 4 GK_F64 )
    : b _u ( gk_dbuf_upload kit x xs )
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev_in c `x` x )
    ( gk_call_dev c `o` o )
    : s red `SHARED_D(t, 64);
ST(t, tid, LD(x, gid));
SYNC();
for (long long s = bdim / 2; s > 0; s = s / 2) {
    if (tid < s) { ST(t, tid, LD(t, tid) + LD(t, tid + s)); }
    SYNC();
}
if (tid == 0) { ST(o, bid, LD(t, 0)); }`
    : b ok ( gk_run_checked_dev kit c `blocksum` red 4 64 )
    : ~ ( Vec f ) got ( vec_zeroed [f] 4 )
    : b _d ( gk_dbuf_download kit o got )
    : b good & & ok == ( vec_at [f] got 0 ) 2080.0 & == ( vec_at [f] got 1 ) 6176.0 & == ( vec_at [f] got 2 ) 10272.0 == ( vec_at [f] got 3 ) 14368.0
    ? good { ( nurl_print `ok   block sums through a shared array\n` ) } { ( nurl_print `FAIL block sums: ` ) ( nurl_print ( gk_checked_error c ) ) ( nurl_print `\n` ) = g_fail + g_fail 1 }

    // f32 in, f32 shared, f32 out
    : GkBuf xf ( gk_dbuf_new kit 64 GK_F32 )
    : GkBuf of ( gk_dbuf_new kit 64 GK_F32 )
    : b _u2 ( gk_dbuf_upload kit xf xs )
    : ~ GkCall c2 ( gk_call_new )
    ( gk_call_dev_in c2 `x` xf )
    ( gk_call_dev c2 `o` of )
    : b ok2 ( gk_run_checked_dev kit c2 `rev32` `SHARED_F(t, 64); ST(t, tid, LD(x, tid) * 0.5f); SYNC(); ST(o, tid, LD(t, 63 - tid));` 1 64 )
    : ~ ( Vec f ) g2 ( vec_zeroed [f] 64 )
    : b _d2 ( gk_dbuf_download kit of g2 )
    ? & & ok2 == ( vec_at [f] g2 0 ) 32.0 == ( vec_at [f] g2 63 ) 0.5 { ( nurl_print `ok   f32 buffers and a float shared array\n` ) } { ( nurl_print `FAIL f32: ` ) ( nurl_print ( gk_checked_error c2 ) ) ( nurl_print `\n` ) = g_fail + g_fail 1 }

    // one buffer bound as read-only and as written: refused
    : ~ GkCall c3 ( gk_call_new )
    ( gk_call_dev_in c3 `a` x )
    ( gk_call_dev c3 `b` x )
    ? ( gk_run_checked_dev kit c3 `alias` `ST(b, gid, LD(a, gid));` 1 64 ) { ( nurl_print `FAIL a read buffer overlapping a written one was launched\n` ) = g_fail + g_fail 1 } { ( nurl_print `ok   rejects a read buffer that overlaps a written one\n` ) }

    // the same kernel name with another body (and bindings) runs that body
    : ~ GkCall c4 ( gk_call_new )
    ( gk_call_dev c4 `o` o )
    ( gk_call_f64 c4 `v` 7.0 )
    : b ok4 ( gk_run_checked_dev kit c4 `blocksum` `ST(o, gid, v);` 1 4 )
    : ~ ( Vec f ) g4 ( vec_zeroed [f] 4 )
    : b _d4 ( gk_dbuf_download kit o g4 )
    ? & ok4 == ( vec_at [f] g4 3 ) 7.0 { ( nurl_print `ok   a reused kernel name runs its own body\n` ) } { ( nurl_print `FAIL reused kernel name\n` ) = g_fail + g_fail 1 }
}

// 16-bit float buffers, warp shuffles and per-thread arrays, for real.
@ xrun GpuKit kit → v {
    // Every f16 and every bf16 bit pattern, converted by the kernel and on
    // the host: bit for bit (NaNs: both NaN).
    : ~ ( Vec u ) bytes ( vec_with_cap [u] 131072 )
    : ~ i k 0
    ~ < k 65536 { ( vec_push [u] bytes # u & k 255 ) ( vec_push [u] bytes # u >> k 8 ) = k + k 1 }
    : ~ b bf F
    : ~ i round 0
    ~ < round 2 {
        : GkHBuf h ( gk_hbuf_new kit 65536 bf )
        : b _u ( gk_hbuf_upload_bytes kit h ( slice_from_vec [u] bytes ) )
        : GkBuf o ( gk_dbuf_new kit 65536 GK_F32 )
        : ~ GkCall c ( gk_call_new )
        ( gk_call_half_in c `h` h )
        ( gk_call_dev c `o` o )
        // (odd elements through a window over the buffer: the same conversion)
        : b ok ( gk_run_checked_dev kit c `halves` `WIN(hw, h, 0, 65536); ST(o, gid, gid % 2 == 0 ? LD(h, gid) : LD(hw, gid));` 256 256 )
        : ~ ( Vec f ) got ( vec_zeroed [f] 65536 )
        : b _d ( gk_dbuf_download kit o got )
        : ~ i bad 0
        = k 0
        ~ < k 65536 {
            : f want ? bf ( bf16_to_f k ) ( f16_to_f k )
            : f g ( vec_at [f] got k )
            ? != want want {
                ? == g g { = bad + bad 1 } {}
            } {
                ? != ( f32_to_bits # f32 g ) ( f32_to_bits # f32 want ) { = bad + bad 1 } {}
            }
            = k + k 1
        }
        ? & ok == bad 0 { ( nurl_print `ok   every ` ) } { ( nurl_print `FAIL ` ) = g_fail + g_fail 1 }
        ( nurl_print ? bf `bf16` `f16` ) ( nurl_print ` bit pattern loads as the host converts it, directly and through a window (bad ` ) ( nurl_print_int bad ) ( nurl_print `)\n` )
        = bf T
        = round + round 1
    }

    // a half buffer is read only: a store into one is refused
    : GkHBuf h2 ( gk_hbuf_new kit 64 F )
    : GkBuf o2 ( gk_dbuf_new kit 64 GK_F32 )
    : ~ GkCall c2 ( gk_call_new )
    ( gk_call_half_in c2 `h` h2 )
    ( gk_call_dev c2 `o` o2 )
    ? ( gk_run_checked_dev kit c2 `hstore` `ST(h, gid, 1.0f);` 1 64 ) { ( nurl_print `FAIL a store into a half buffer was launched\n` ) = g_fail + g_fail 1 } { ( nurl_print `ok   refuses a store into a half buffer\n` ) }
    // a half view of a buffer's bytes, inside it only
    : GkBuf base ( gk_dbuf_new kit 8 GK_F32 )
    ? & & ( gk_hbuf_ok ( gk_hbuf_of base 0 16 F ) ) ! ( gk_hbuf_ok ( gk_hbuf_of base 2 16 F ) ) & ! ( gk_hbuf_ok ( gk_hbuf_of base 1 2 F ) ) ! ( gk_hbuf_ok ( gk_hbuf_of base -2 2 F ) ) { ( nurl_print `ok   a half view stays inside its buffer\n` ) } { ( nurl_print `FAIL half view bounds\n` ) = g_fail + g_fail 1 }

    // warp sums: a SHFL_DOWN tree into lane 0, a SHFL_XOR butterfly into
    // every lane, over 2 blocks of 64 (four warps of 1..32, 33..64, …)
    : ~ ( Vec f ) xs ( vec_new [f] )
    = k 0
    ~ < k 128 { ( vec_push [f] xs # f + k 1 ) = k + k 1 }
    : GkBuf x ( gk_dbuf_new kit 128 GK_F64 )
    : GkBuf ws ( gk_dbuf_new kit 4 GK_F64 )
    : GkBuf wa ( gk_dbuf_new kit 128 GK_F64 )
    : b _ux ( gk_dbuf_upload kit x xs )
    : ~ GkCall c3 ( gk_call_new )
    ( gk_call_dev_in c3 `x` x ) ( gk_call_dev c3 `ws` ws ) ( gk_call_dev c3 `wa` wa )
    : b ok3 ( gk_run_checked_dev kit c3 `warpsum` `double v = LD(x, gid);
double w = v;
for (int off = 16; off > 0; off >>= 1) { v += SHFL_DOWN(v, off); }
for (int m = 1; m < 32; m <<= 1) { w += SHFL_XOR(w, m); }
if ((tid & 31) == 0) { ST(ws, gid / 32, v); }
ST(wa, gid, w);` 2 64 )
    : ~ ( Vec f ) g3 ( vec_zeroed [f] 4 )
    : ~ ( Vec f ) g4 ( vec_zeroed [f] 128 )
    : b _d3 ( gk_dbuf_download kit ws g3 )
    : b _d4 ( gk_dbuf_download kit wa g4 )
    : b sums & & == ( vec_at [f] g3 0 ) 528.0 == ( vec_at [f] g3 1 ) 1552.0 & == ( vec_at [f] g3 2 ) 2576.0 == ( vec_at [f] g3 3 ) 3600.0
    : b alls & & == ( vec_at [f] g4 0 ) 528.0 == ( vec_at [f] g4 31 ) 528.0 & == ( vec_at [f] g4 64 ) 2576.0 == ( vec_at [f] g4 127 ) 3600.0
    ? & & ok3 sums alls { ( nurl_print `ok   warp sums through SHFL_DOWN and SHFL_XOR\n` ) } { ( nurl_print `FAIL warp sums: ` ) ( nurl_print ( gk_checked_error c3 ) ) ( nurl_print `\n` ) = g_fail + g_fail 1 }
    // the same kernel in blocks that are not whole warps: refused
    ? ( gk_run_checked_dev kit c3 `warpsum` `double v = LD(x, gid);
double w = v;
for (int off = 16; off > 0; off >>= 1) { v += SHFL_DOWN(v, off); }
for (int m = 1; m < 32; m <<= 1) { w += SHFL_XOR(w, m); }
if ((tid & 31) == 0) { ST(ws, gid / 32, v); }
ST(wa, gid, w);` 2 48 ) { ( nurl_print `FAIL a shuffle in blocks of 48 was launched\n` ) = g_fail + g_fail 1 } { ( nurl_print `ok   refuses a shuffle in blocks that are not whole warps\n` ) }

    // a per-thread array, unrolled: o[gid] = x[gid] * (1 + 2 + 3 + 4)
    : GkBuf o5 ( gk_dbuf_new kit 128 GK_F64 )
    : ~ GkCall c5 ( gk_call_new )
    ( gk_call_dev_in c5 `x` x ) ( gk_call_dev c5 `o` o5 )
    : b ok5 ( gk_run_checked_dev kit c5 `localarr` `LOCAL_D(acc, 4);
UNROLL for (int j = 0; j < 4; j++) { ST(acc, j, LD(x, gid) * (double)(j + 1)); }
double s = 0.0;
UNROLL for (int j = 0; j < 4; j++) { s += LD(acc, j); }
ST(o, gid, s + LD(acc, 9) - LD(acc, 3));` 2 64 )
    : ~ ( Vec f ) g5 ( vec_zeroed [f] 128 )
    : b _d5 ( gk_dbuf_download kit o5 g5 )
    ? & & ok5 == ( vec_at [f] g5 0 ) 10.0 == ( vec_at [f] g5 127 ) 1280.0 { ( nurl_print `ok   a per-thread array (out-of-range reads its last element)\n` ) } { ( nurl_print `FAIL per-thread array: ` ) ( nurl_print ( gk_checked_error c5 ) ) ( nurl_print `\n` ) = g_fail + g_fail 1 }

    // a length whose byte count wraps is no buffer at all
    : GkBuf huge ( gk_dbuf_new kit 2305843009213693953 GK_F64 )
    ? ( gk_buf_ok huge ) { ( nurl_print `FAIL a buffer of 2^61 + 1 doubles was made\n` ) = g_fail + g_fail 1 } { ( nurl_print `ok   refuses a buffer whose byte count overflows\n` ) }
}

// Recorded launches: checked and bound once, replayed many times; a
// record holds its buffers, so it outlives the caller's handles to them.
@ rrun GpuKit kit → v {
    : ~ ( Vec f ) xs ( vec_new [f] )
    : ~ i k 0
    ~ < k 64 { ( vec_push [f] xs # f k ) = k + k 1 }
    : ~ GkLaunch rec ( gk_launch_none kit )
    : ~ GkLaunch bad ( gk_launch_none kit )
    : GkBuf o ( gk_dbuf_new kit 64 GK_F64 )
    : b _z ( gk_dbuf_upload kit o ( vec_zeroed [f] 64 ) )
    {
        : GkBuf x ( gk_dbuf_new kit 64 GK_F64 )
        : b _u ( gk_dbuf_upload kit x xs )
        : ~ GkCall c ( gk_call_new )
        ( gk_call_dev_in c `x` x ) ( gk_call_dev c `o` o ) ( gk_call_f64 c `w` 0.5 )
        = rec ( gk_record_dev kit c `acc` `if (gid < 64) { ST(o, gid, LD(o, gid) + w * LD(x, gid)); }` 1 64 )
        : ~ GkCall c2 ( gk_call_new )
        ( gk_call_dev c2 `o` o )
        = bad ( gk_record_dev kit c2 `bad` `double* p = 0;` 1 64 )
    }
    // x's own handle is gone; the record still holds the buffer
    : ~ b ok ( gk_launch_ok rec )
    = k 0
    ~ < k 4 { = ok & ok ( gk_replay rec ) = k + k 1 }
    : ~ ( Vec f ) got ( vec_zeroed [f] 64 )
    : b _d ( gk_dbuf_download kit o got )
    ? & & ok == ( vec_at [f] got 0 ) 0.0 == ( vec_at [f] got 63 ) 126.0 { ( nurl_print `ok   a recorded launch replayed four times (its input held by the record)\n` ) } { ( nurl_print `FAIL recorded launch\n` ) = g_fail + g_fail 1 }
    ? | ( gk_launch_ok bad ) ( gk_replay bad ) { ( nurl_print `FAIL a refused body made a launch record\n` ) = g_fail + g_fail 1 } { ( nurl_print `ok   a refused body makes a record that launches nothing\n` ) }
}

// A record's scalars and block count change between replays (a decoder's
// position); half and f32 buffers go up in one batch.
@ urun GpuKit kit → v {
    : GkBuf o ( gk_dbuf_new kit 256 GK_F64 )
    : b _z ( gk_dbuf_upload kit o ( vec_zeroed [f] 256 ) )
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev c `o` o ) ( gk_call_i64 c `k` 0 ) ( gk_call_f64 c `w` 1.0 )
    : ~ GkLaunch l ( gk_record_dev kit c `upd` `ST(o, gid, LD(o, gid) + w * (double)k);` 1 64 )
    : ~ b ok ( gk_launch_ok l )
    = ok & ok ( gk_launch_set_i64 l `k` 3 )
    = ok & ok ( gk_launch_set_f64 l `w` 0.5 )
    = ok & ok ( gk_replay l )
    = ok & ok ( gk_launch_set_blocks l 4 )
    = ok & ok ( gk_launch_set_i64 l `k` 2 )
    = ok & ok ( gk_replay l )
    : b nope | ( gk_launch_set_i64 l `o` 1 ) ( gk_launch_set_i64 l `zz` 1 )
    : ~ ( Vec f ) got ( vec_zeroed [f] 256 )
    : b _d ( gk_dbuf_download kit o got )
    // blocks of 64: the first replay reached o[0..64) (+1.5), the second all
    // 256 (+1.0)
    ? & & ok ! nope & == ( vec_at [f] got 0 ) 2.5 == ( vec_at [f] got 255 ) 1.0 {
        ( nurl_print `ok   a record's scalars and block count change between replays (a buffer's words do not)\n` )
    } { ( nurl_print `FAIL record updates\n` ) = g_fail + g_fail 1 }

    // one batch, an f32 buffer and a half buffer
    : GkBuf fb ( gk_dbuf_new kit 3 GK_F32 )
    : GkHBuf hb ( gk_hbuf_new kit 2 F )
    : ~ ( Vec u ) fbytes ( vec_new [u] )
    ( bytes_push_u32_le fbytes # u32 ( f32_to_bits # f32 1.5 ) )
    ( bytes_push_u32_le fbytes # u32 ( f32_to_bits # f32 -2.0 ) )
    ( bytes_push_u32_le fbytes # u32 ( f32_to_bits # f32 4.0 ) )
    : ~ ( Vec u ) hbytes ( vec_new [u] )
    ( vec_push [u] hbytes 0 ) ( vec_push [u] hbytes 60 )  // 1.0 in f16: 0x3C00
    ( vec_push [u] hbytes 0 ) ( vec_push [u] hbytes 192 )  // -2.0: 0xC000
    : ~ ( Vec GkBuf ) ds ( vec_new [GkBuf] ) ( vec_push [GkBuf] ds ( mem_dup fb ) )
    : ~ ( Vec ( Slice u ) ) ss ( vec_new [( Slice u )] ) ( vec_push [( Slice u )] ss ( slice_from_vec [u] fbytes ) )
    : ~ ( Vec GkHBuf ) hds ( vec_new [GkHBuf] ) ( vec_push [GkHBuf] hds ( mem_dup hb ) )
    : ~ ( Vec ( Slice u ) ) hss ( vec_new [( Slice u )] ) ( vec_push [( Slice u )] hss ( slice_from_vec [u] hbytes ) )
    : b up ( gk_upload_batch kit ds ss hds hss F )
    : GkBuf sum ( gk_dbuf_new kit 3 GK_F64 )
    : ~ GkCall c2 ( gk_call_new )
    ( gk_call_dev_in c2 `a` fb ) ( gk_call_half_in c2 `h` hb ) ( gk_call_dev c2 `s` sum )
    : b ran ( gk_run_checked_dev kit c2 `hsum` `if (gid < 3) { ST(s, gid, (double)LD(a, gid) + (double)LD(h, gid)); }` 1 32 )
    : ~ ( Vec f ) g2 ( vec_zeroed [f] 3 )
    : b _d2 ( gk_dbuf_download kit sum g2 )
    // a short source is refused, nothing sent
    : ~ ( Vec ( Slice u ) ) bad ( vec_new [( Slice u )] ) ( vec_push [( Slice u )] bad ( slice_prefix [u] ( slice_from_vec [u] hbytes ) 2 ) )
    : b short ( gk_upload_batch kit ( vec_new [GkBuf] ) ( vec_new [( Slice u )] ) hds bad F )
    // (the half buffer's last element reads its last element: h[2] = h[1])
    ? & & & up ran ! short & & == ( vec_at [f] g2 0 ) 2.5 == ( vec_at [f] g2 1 ) -4.0 == ( vec_at [f] g2 2 ) 2.0 {
        ( nurl_print `ok   f32 and half buffers go up in one batch; a short source is refused\n` )
    } { ( nurl_print `FAIL mixed upload batch\n` ) = g_fail + g_fail 1 }
}

// Byte buffers: LD a byte, LD16 / LD32 the aligned word holding it, F16
// of a word's bits; LD16 on any other buffer is refused.
@ qrun GpuKit kit → v {
    : ~ ( Vec u ) bytes ( vec_new [u] )
    : ~ i k 0
    ~ < k 64 { ( vec_push [u] bytes # u * k 3 ) = k + k 1 }
    // bytes 8..9 hold the f16 1.5 (0x3E00), little endian
    ( vec_put [u] bytes 8 0 ) ( vec_put [u] bytes 9 62 )
    : GkBBuf q ( gk_bbuf_new kit 64 )
    : b up ( gk_bbuf_upload_bytes kit q ( slice_from_vec [u] bytes ) )
    : GkBuf o ( gk_dbuf_new kit 8 GK_F64 )
    : ~ GkCall c ( gk_call_new )
    ( gk_call_bytes_in c `q` q ) ( gk_call_dev c `o` o )
    : b ran ( gk_run_checked_dev kit c `bytes` `if (gid == 0) {
    ST(o, 0, (double)LD(q, 5));
    ST(o, 1, (double)LD16(q, 3));
    ST(o, 2, (double)LD32(q, 6));
    ST(o, 3, (double)LD(q, 1000));
    ST(o, 4, (double)LD32(q, 1000));
    ST(o, 5, (double)F16(LD16(q, 8)));
    ST(o, 6, (double)(signed char)LD(q, 63));
    ST(o, 7, (double)LD16(q, -1));
}` 1 32 )
    : ~ ( Vec f ) g ( vec_zeroed [f] 8 )
    : b _d ( gk_dbuf_download kit o g )
    // byte 5 = 15; word 1 (bytes 2,3) = 6 | 9<<8; word 1 of 32 (bytes 4..7) =
    // 12 | 15<<8 | 18<<16 | 21<<24; byte 1000 → the last byte (189); word
    // 1000/4 → the last word (bytes 60..63); F16 0x3E00 = 1.5; byte 63 = 189
    // as signed char = -67; a negative index reads the last word too
    : f w1 # f + 6 * 9 256
    : f w32 # f + + + 12 * 15 256 * 18 65536 * 21 16777216
    : f wlast # f + + + 180 * 183 256 * 186 65536 * 189 16777216
    : f h63 # f + 186 * 189 256
    ? & & & up ran & == ( vec_at [f] g 0 ) 15.0 == ( vec_at [f] g 1 ) w1 & & == ( vec_at [f] g 2 ) w32 == ( vec_at [f] g 3 ) 189.0 & & == ( vec_at [f] g 4 ) wlast == ( vec_at [f] g 5 ) 1.5 & == ( vec_at [f] g 6 ) -67.0 == ( vec_at [f] g 7 ) h63 {
        ( nurl_print `ok   a byte buffer reads bytes, aligned 16/32-bit words and f16 bits; past the end, the last byte or word\n` )
    } { ( nurl_print `FAIL byte buffer loads: ` ) ( nurl_print ( gk_checked_error c ) ) ( nurl_print `\n` ) = g_fail + g_fail 1 }
    // LD16 needs a byte buffer; a byte buffer is never written
    : GkBuf fb ( gk_dbuf_new kit 8 GK_F32 )
    : ~ GkCall c2 ( gk_call_new )
    ( gk_call_dev_in c2 `x` fb ) ( gk_call_dev c2 `o` o )
    : b bad1 ( gk_run_checked_dev kit c2 `ld16f` `ST(o, 0, (double)LD16(x, 0));` 1 32 )
    : ~ GkCall c3 ( gk_call_new )
    ( gk_call_bytes_in c3 `q` q ) ( gk_call_dev c3 `o` o )
    : b bad2 ( gk_run_checked_dev kit c3 `stq` `ST(q, 0, 1);` 1 32 )
    ? | bad1 bad2 { ( nurl_print `FAIL LD16 on a float buffer or a store into bytes was launched\n` ) = g_fail + g_fail 1 } { ( nurl_print `ok   refuses LD16 on a non-byte buffer and a store into a byte buffer\n` ) }
    // a written byte buffer: ST stores the low byte; the read-only view of
    // the same bytes cannot be bound beside it
    : GkBBuf qw ( gk_bbuf_new kit 8 )
    : ~ GkCall c5 ( gk_call_new )
    ( gk_call_bytes c5 `w` qw )
    : b wr ( gk_run_checked_dev kit c5 `stb` `if (gid < 8) { ST(w, gid, 250 + gid * 3); } ST(w, 99, 1);` 1 32 )
    : ~ ( Vec u ) back ( vec_zeroed [u] 8 )
    : GkBuf qwf ( gk_dbuf_new kit 2 GK_F32 )
    : ~ GkCall c6 ( gk_call_new )
    ( gk_call_bytes_in c6 `r` q ) ( gk_call_bytes c6 `w` q )
    : b ovl ( gk_run_checked_dev kit c6 `ovl` `ST(w, gid, LD(r, gid));` 1 32 )
    : ~ GkCall c7 ( gk_call_new )
    ( gk_call_bytes_in c7 `r` qw ) ( gk_call_dev c7 `o` o )
    : b rd ( gk_run_checked_dev kit c7 `rdb` `if (gid < 8) { ST(o, gid, (double)LD(r, gid)); }` 1 32 )
    : ~ ( Vec f ) g7 ( vec_zeroed [f] 8 )
    : b _d7 ( gk_dbuf_download kit o g7 )
    // 250, 253, 256→0, 259→3, …
    ? & & & wr rd ! ovl & & == ( vec_at [f] g7 0 ) 250.0 == ( vec_at [f] g7 2 ) 0.0 == ( vec_at [f] g7 7 ) 15.0 {
        ( nurl_print `ok   a written byte buffer stores low bytes; it cannot overlap a read one\n` )
    } { ( nurl_print `FAIL byte stores: ` ) ( nurl_print ( gk_checked_error c5 ) ) ( nurl_print ( gk_checked_error c7 ) ) ( nurl_print `\n` ) = g_fail + g_fail 1 }
    // windows over bytes: a read window of q, a strided one, one past the
    // end (empty), and stores through a window of a written byte buffer
    : GkBBuf qw2 ( gk_bbuf_new kit 8 )
    : ~ GkCall c8 ( gk_call_new )
    ( gk_call_bytes_in c8 `q` q ) ( gk_call_bytes c8 `w` qw2 ) ( gk_call_dev c8 `o` o )
    : b wran ( gk_run_checked_dev kit c8 `bwin` `if (gid == 0) {
    WIN(qb, q, 10, 4);
    double s = 0.0;
    for (int j = 0; j < LEN(qb); j++) { s += (double)LD(qb, j); }
    ST(o, 0, s);
    WINS(qs, q, 1, 3, 20);
    ST(o, 1, (double)(LD(qs, 0) + LD(qs, 1) + LD(qs, 2)));
    WIN(qx, q, 60, 8);
    ST(o, 2, (double)LEN(qx));
    WIN(wb, w, 2, 4);
    for (int j = 0; j < 6; j++) { ST(wb, j, 200 + j * 20); }
}` 1 32 )
    : ~ GkCall c9 ( gk_call_new )
    ( gk_call_bytes_in c9 `r` qw2 ) ( gk_call_dev c9 `o` o )
    : b wrd ( gk_run_checked_dev kit c9 `bwrd` `if (gid < 5) { ST(o, 3 + gid, (double)LD(r, gid + 2)); }` 1 32 )
    : ~ ( Vec f ) g9 ( vec_zeroed [f] 8 )
    : b _d9 ( gk_dbuf_download kit o g9 )
    // q[10..14) = 30+33+36+39 = 138; q[1], q[21], q[41] = 3+63+123 = 189;
    // q[60..68) runs past the end (empty); w[2..6) = 200, 220, 240, 260→4,
    // the rest dropped — o[3..8) = w[2..7) = 200 220 240 4 0
    : b bw & & == ( vec_at [f] g9 3 ) 200.0 == ( vec_at [f] g9 4 ) 220.0 & & == ( vec_at [f] g9 5 ) 240.0 == ( vec_at [f] g9 6 ) 4.0 == ( vec_at [f] g9 7 ) 0.0
    ? & & & wran wrd & == ( vec_at [f] g9 0 ) 138.0 == ( vec_at [f] g9 1 ) 189.0 & == ( vec_at [f] g9 2 ) 0.0 bw {
        ( nurl_print `ok   windows over bytes read and store bytes in their range\n` )
    } {
        ( nurl_print `FAIL byte windows: ` ) ( nurl_print ( gk_checked_error c8 ) ) ( nurl_print ( gk_checked_error c9 ) )
        : ~ String vs ( string_new )
        : ~ i q 0
        ~ < q 8 { ( string_push_str vs ` ` ) ( string_push_float vs ( vec_at [f] g9 q ) ) = q + q 1 }
        ( nurl_print ( string_data vs ) ) ( nurl_print `\n` ) = g_fail + g_fail 1
    }
    : ~ GkCall c10 ( gk_call_new )
    ( gk_call_bytes_in c10 `q` q ) ( gk_call_dev c10 `o` o )
    : b bad3 ( gk_run_checked_dev kit c10 `bwst` `WIN(qb, q, 0, 4); ST(qb, 0, 1);` 1 32 )
    : b bad4 ( gk_run_checked_dev kit c10 `bwld32` `WIN(qb, q, 0, 4); ST(o, 0, (double)LD32(qb, 0));` 1 32 )
    ? | bad3 bad4 { ( nurl_print `FAIL a store into a read byte window or LD32 through a window was launched\n` ) = g_fail + g_fail 1 } { ( nurl_print `ok   refuses a store into a read byte window and LD32 through a window\n` ) }
    // views: 4-byte aligned starts, at least 4 bytes, inside the buffer
    : GkBuf base ( gk_dbuf_new kit 4 GK_F32 )
    ? & & ( gk_bbuf_ok ( gk_bbuf_of base 4 12 ) ) ! ( gk_bbuf_ok ( gk_bbuf_of base 2 8 ) ) & ! ( gk_bbuf_ok ( gk_bbuf_of base 0 3 ) ) ! ( gk_bbuf_ok ( gk_bbuf_of base 8 12 ) ) {
        ( nurl_print `ok   a byte view starts 4-byte aligned, holds a word and stays inside its buffer\n` )
    } { ( nurl_print `FAIL byte view bounds\n` ) = g_fail + g_fail 1 }
}

// LD4: the aligned group of four f32 holding element i, in one load; a
// buffer that is not 16-byte aligned is refused, and LD4's targets are per
// thread for SYNC's rule.
@ v4run GpuKit kit → v {
    : ~ ( Vec f ) xs ( vec_new [f] )
    : ~ i k 0
    ~ < k 10 { ( vec_push [f] xs # f + k 1 ) = k + k 1 }
    : GkBuf x ( gk_dbuf_new kit 10 GK_F32 )
    : b _u ( gk_dbuf_upload kit x xs )
    : GkBuf o ( gk_dbuf_new kit 8 GK_F64 )
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev_in c `x` x ) ( gk_call_dev c `o` o )
    : b ran ( gk_run_checked_dev kit c `ld4` `float a = 0.0f; float b = 0.0f; float e = 0.0f; float d = 0.0f;
if (gid == 0) {
    LD4(x, 5, a, b, e, d);
    ST(o, 0, (double)a); ST(o, 1, (double)d);
    LD4(x, 9, a, b, e, d);
    ST(o, 2, (double)a); ST(o, 3, (double)d);
    LD4(x, -3, a, b, e, d);
    ST(o, 4, (double)a);
}` 1 32 )
    : ~ ( Vec f ) g ( vec_zeroed [f] 8 )
    : b _d ( gk_dbuf_download kit o g )
    // element 5 is in the group 4..7 (5, 8); element 9's group 8..11 is not
    // whole, so the last whole group 4..7 is read; a negative index too
    ? & & ran & == ( vec_at [f] g 0 ) 5.0 == ( vec_at [f] g 1 ) 8.0 & & == ( vec_at [f] g 2 ) 5.0 == ( vec_at [f] g 3 ) 8.0 == ( vec_at [f] g 4 ) 5.0 {
        ( nurl_print `ok   LD4 reads an aligned group of four, past the end the last whole group\n` )
    } { ( nurl_print `FAIL LD4 loads: ` ) ( nurl_print ( gk_checked_error c ) ) ( nurl_print `\n` ) = g_fail + g_fail 1 }
    // a view one element in is 4-byte aligned only; an f64 buffer is not f32
    : GkBuf xv ( gk_buf_view x 1 8 )
    : ~ GkCall c2 ( gk_call_new )
    ( gk_call_dev_in c2 `x` xv ) ( gk_call_dev c2 `o` o )
    : b bad1 ( gk_run_checked_dev kit c2 `ld4` `float a = 0.0f; float b = 0.0f; float e = 0.0f; float d = 0.0f;
if (gid == 0) {
    LD4(x, 5, a, b, e, d);
    ST(o, 0, (double)a); ST(o, 1, (double)d);
    LD4(x, 9, a, b, e, d);
    ST(o, 2, (double)a); ST(o, 3, (double)d);
    LD4(x, -3, a, b, e, d);
    ST(o, 4, (double)a);
}` 1 32 )
    : ~ GkCall c3 ( gk_call_new )
    ( gk_call_dev_in c3 `x` o ) ( gk_call_dev c3 `o` x )
    : b bad2 ( gk_run_checked_dev kit c3 `ld4d` `float a = 0.0f; float b = 0.0f; float e = 0.0f; float d = 0.0f; LD4(x, 0, a, b, e, d); ST(o, gid, a);` 1 32 )
    // a SYNC behind an LD4 value is behind a per-thread value
    : ~ GkCall c4 ( gk_call_new )
    ( gk_call_dev_in c4 `x` x ) ( gk_call_dev c4 `o` o )
    : b bad3 ( gk_run_checked_dev kit c4 `ld4s` `float a = 0.0f; float b = 0.0f; float e = 0.0f; float d = 0.0f;
LD4(x, tid, a, b, e, d);
if (a > 2.0f) { SYNC(); }
ST(o, 0, (double)a);` 1 32 )
    ? | | bad1 bad2 bad3 { ( nurl_print `FAIL an LD4 over a misaligned or f64 buffer, or a SYNC behind it, was launched\n` ) = g_fail + g_fail 1 } { ( nurl_print `ok   refuses LD4 on a misaligned or non-f32 buffer, and a SYNC behind an LD4 value\n` ) }
}

// Windows: WIN / WINS over a device buffer; a window out of its buffer
// is empty; LD / ST through one; refusals.
@ wrun GpuKit kit → v {
    : ~ ( Vec f ) xs ( vec_new [f] )
    : ~ i k 0
    ~ < k 12 { ( vec_push [f] xs # f + k 1 ) = k + k 1 }
    : GkBuf x ( gk_dbuf_new kit 12 GK_F64 )
    : b _u ( gk_dbuf_upload kit x xs )
    : GkBuf o ( gk_dbuf_new kit 12 GK_F64 )
    : b _z ( gk_dbuf_upload kit o ( vec_zeroed [f] 12 ) )
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev_in c `x` x ) ( gk_call_dev c `o` o ) ( gk_call_i64 c `n` 4 )
    : b ran ( gk_run_checked_dev kit c `win` `if (gid == 0) {
    WIN(row, x, 4, n);
    double s = 0.0;
    for (long long j = 0; j < LEN(row); j++) { s += LD(row, j); }
    ST(o, 0, s);
    WINS(col, x, 1, 3, 4);
    double t = 0.0;
    for (long long j = 0; j < LEN(col); j++) { t += LD(col, j); }
    ST(o, 1, t);
    WIN(bad, x, 10, 5);
    ST(o, 2, (double)LEN(bad));
    ST(o, 3, LD(bad, 7));
    WINS(far, x, 2, 4, 4);
    ST(o, 4, (double)LEN(far));
    WIN(ow, o, 5, 3);
    for (long long j = 0; j < 4; j++) { ST(ow, j, 9.0); }
    WIN(e, x, 1000000, 0);
    ST(o, 8, LD(e, 0) + (double)LEN(e));
    long long k = 3;
    double v = LD(row, k++);
    WIN(o2, o, 10, 2);
    long long m = 1;
    ST(o2, m++, v + (double)k);
    ST(o, 10, (double)m);
    ST(o, 9, LD(row, LD(col, 0) + 0.5) + LD(row, (int)LD(row, 0) - 4));
}` 1 32 )
    : ~ ( Vec f ) g ( vec_zeroed [f] 12 )
    : b _d ( gk_dbuf_download kit o g )
    // row = x[4..8) = 5+6+7+8; col = x[1], x[5], x[9] = 2+6+10; a window
    // past the end is empty and reads the buffer's first element; 2+3·4 = 14
    // is past the end too; ST through a window stops at its length; an
    // empty window past the end is the empty window at 0 (reads x[0] = 1);
    // an index with a side effect is evaluated once: row[3] = 8, k = 4,
    // the store lands at o2[1] = o[11] and m = 2; a window's load may index
    // by another (col[0] = 2 → row[2] = 7) and by a float, truncated as
    // LD's index is (2.5 → 2, row[2] = 7), and by an int (5 - 4 → row[1] = 6)
    : b more & & == ( vec_at [f] g 8 ) 1.0 == ( vec_at [f] g 11 ) 12.0 & == ( vec_at [f] g 10 ) 2.0 == ( vec_at [f] g 9 ) 13.0
    ? & more & & ran & == ( vec_at [f] g 0 ) 26.0 == ( vec_at [f] g 1 ) 18.0 & & == ( vec_at [f] g 2 ) 0.0 == ( vec_at [f] g 3 ) 1.0 & & == ( vec_at [f] g 4 ) 0.0 == ( vec_at [f] g 5 ) 9.0 & == ( vec_at [f] g 7 ) 9.0 == ( vec_at [f] g 6 ) 9.0 {
        ( nurl_print `ok   windows read and write their range; one outside its buffer is empty\n` )
    } {
        ( nurl_print `FAIL windows: ` ) ( nurl_print ( gk_checked_error c ) )
        : ~ String vs ( string_new )
        : ~ i q 0
        ~ < q 12 { ( string_push_str vs ` ` ) ( string_push_float vs ( vec_at [f] g q ) ) = q + q 1 }
        ( nurl_print ( string_data vs ) ) ( nurl_print `\n` ) = g_fail + g_fail 1
    }
    // refusals: a window into a read-only window's buffer cannot be written,
    // a name used twice, a SYNC behind a window's length
    : ~ GkCall c2 ( gk_call_new )
    ( gk_call_dev_in c2 `x` x ) ( gk_call_dev c2 `o` o )
    : b bad1 ( gk_run_checked_dev kit c2 `wst` `WIN(r, x, 0, 4); ST(r, 0, 1.0);` 1 32 )
    : b bad2 ( gk_run_checked_dev kit c2 `wdup` `WIN(r, x, 0, 4); WIN(r, x, 4, 4); ST(o, 0, LD(r, 0));` 1 32 )
    : b bad3 ( gk_run_checked_dev kit c2 `wsync` `WIN(r, x, tid, 4); if (LEN(r) > 2) { SYNC(); } ST(o, 0, LD(r, 0));` 1 32 )
    : b bad4 ( gk_run_checked_dev kit c2 `wexpr` `double v = 1.0 + WIN(r, x, 0, 4); ST(o, 0, v);` 1 32 )
    ? | | | bad1 bad2 bad3 bad4 { ( nurl_print `FAIL a store into a read window, a window declared twice, a SYNC behind a window or a window in an expression was launched\n` ) = g_fail + g_fail 1 } { ( nurl_print `ok   refuses a store into a read window, a name twice, a SYNC behind one, one inside an expression\n` ) }
}

// 2-D windows: rows of COLS elements, a stride apart; one that does not fit
// is empty; ST2 outside its rows / columns is dropped.
@ w2run GpuKit kit → v {
    : ~ ( Vec f ) xs ( vec_new [f] )
    : ~ i k 0
    ~ < k 20 { ( vec_push [f] xs # f k ) = k + k 1 }
    : GkBuf x ( gk_dbuf_new kit 20 GK_F64 )
    : b _u ( gk_dbuf_upload kit x xs )
    : GkBuf o ( gk_dbuf_new kit 16 GK_F64 )
    : b _z ( gk_dbuf_upload kit o ( vec_zeroed [f] 16 ) )
    : ~ ( Vec u ) bytes ( vec_new [u] )
    = k 0
    ~ < k 24 { ( vec_push [u] bytes # u + k 100 ) = k + k 1 }
    : GkBBuf q ( gk_bbuf_new kit 24 )
    : b _q ( gk_bbuf_upload_bytes kit q ( slice_from_vec [u] bytes ) )
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev_in c `x` x ) ( gk_call_dev c `o` o ) ( gk_call_bytes_in c `q` q )
    : b ran ( gk_run_checked_dev kit c `win2` `if (gid == 0) {
    WIN2(m, x, 1, 3, 5, 4);
    double s = 0.0;
    for (int r = 0; r < ROWS(m); r++) {
        if (COLS(m) == 4) { for (int c = 0; c < 4; c++) { s += LD2(m, r, c); } }
    }
    ST(o, 0, s);
    ST(o, 1, (double)(ROWS(m) * 10 + COLS(m)));
    WIN2(bad, x, 10, 3, 5, 4);
    ST(o, 2, (double)(ROWS(bad) * 10 + COLS(bad)));
    WIN2(edge, x, 12, 2, 5, 3);
    ST(o, 3, (double)(ROWS(edge) * 10 + COLS(edge)));
    WIN2(ow, o, 8, 2, 4, 2);
    for (int r = 0; r < 3; r++) { for (int c = 0; c < 3; c++) { ST2(ow, r, c, (double)(100 + r * 10 + c)); } }
    WIN2(qm, q, 2, 2, 10, 3);
    ST(o, 4, (double)(LD2(qm, 0, 0) + LD2(qm, 1, 2) + LD2(qm, 5, 5)));
}` 1 32 )
    : ~ ( Vec f ) g ( vec_zeroed [f] 16 )
    : b _d ( gk_dbuf_download kit o g )
    // rows start at 1, 6, 11, four each: (1+2+3+4) + (6+..+9) + (11+..+14) =
    // 10 + 30 + 50 = 90; 3 rows of 4. Rows at 10, 15, 20 run past 20
    // elements: empty. 12 + 5 + 2 = 19 is the last element: fits (2 rows of
    // 3). ST2 writes o[8], o[9], o[12], o[13] only. q: 102 + (12 + 2 + 100)
    // + q[2] (5, 5 is outside: the window's first byte)
    : b vals & & == ( vec_at [f] g 0 ) 90.0 == ( vec_at [f] g 1 ) 34.0 & & == ( vec_at [f] g 2 ) 0.0 == ( vec_at [f] g 3 ) 23.0 == ( vec_at [f] g 4 ) 318.0
    : b sts & & & == ( vec_at [f] g 8 ) 100.0 == ( vec_at [f] g 9 ) 101.0 & == ( vec_at [f] g 12 ) 110.0 == ( vec_at [f] g 13 ) 111.0 & & == ( vec_at [f] g 10 ) 0.0 == ( vec_at [f] g 11 ) 0.0 == ( vec_at [f] g 14 ) 0.0
    ? & & ran vals sts {
        ( nurl_print `ok   2-D windows read and write their rows and columns; one outside its buffer is empty\n` )
    } {
        ( nurl_print `FAIL 2-D windows: ` ) ( nurl_print ( gk_checked_error c ) )
        : ~ String vs ( string_new )
        : ~ i r 0
        ~ < r 16 { ( string_push_str vs ` ` ) ( string_push_float vs ( vec_at [f] g r ) ) = r + r 1 }
        ( nurl_print ( string_data vs ) ) ( nurl_print `\n` ) = g_fail + g_fail 1
    }
    : ~ GkCall c2 ( gk_call_new )
    ( gk_call_dev_in c2 `x` x ) ( gk_call_dev c2 `o` o )
    : b bad1 ( gk_run_checked_dev kit c2 `w2st` `WIN2(m, x, 0, 2, 4, 2); ST2(m, 0, 0, 1.0);` 1 32 )
    : b bad2 ( gk_run_checked_dev kit c2 `w2ld` `WIN2(m, x, 0, 2, 4, 2); ST(o, 0, LD(m, 0));` 1 32 )
    ? | bad1 bad2 { ( nurl_print `FAIL a store into a read 2-D window or LD on one was launched\n` ) = g_fail + g_fail 1 } { ( nurl_print `ok   refuses a store into a read 2-D window and LD on one\n` ) }
}

// 3-D windows (WIN3 / LD3 / ST3 / PLANES), exact lengths (gk_call_exact)
// and launches by tag (gk_run_checked_dev_tagged)
: ~ i g_mk 0

@ w3run GpuKit kit → v {
    : ~ ( Vec f ) xs ( vec_new [f] )
    : ~ i k 0
    ~ < k 60 { ( vec_push [f] xs # f k ) = k + k 1 }
    : GkBuf x ( gk_dbuf_new kit 60 GK_F64 )
    : b _u ( gk_dbuf_upload kit x xs )
    : GkBuf o ( gk_dbuf_new kit 8 GK_F64 )
    : b _z ( gk_dbuf_upload kit o ( vec_zeroed [f] 8 ) )
    : GkBuf o3 ( gk_dbuf_new kit 16 GK_F64 )
    : b _z3 ( gk_dbuf_upload kit o3 ( vec_zeroed [f] 16 ) )
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev_in c `x` x ) ( gk_call_dev c `o` o ) ( gk_call_dev c `o3` o3 )
    : b ran ( gk_run_checked_dev kit c `win3` `if (gid == 0) {
    WIN3(m, x, 0, 3, 20, 4, 5, 5);
    double s = 0.0;
    for (int p = 0; p < PLANES(m); p++) { for (int r = 0; r < ROWS(m); r++) { for (int q = 0; q < COLS(m); q++) { s += LD3(m, p, r, q); } } }
    ST(o, 0, s);
    ST(o, 1, (double)(PLANES(m) * 100 + ROWS(m) * 10 + COLS(m)));
    WIN3(t, x, 7, 2, 30, 2, 10, 3);
    double u = 0.0;
    for (int p = 0; p < 2; p++) { for (int r = 0; r < 2; r++) { for (int q = 0; q < 3; q++) { u += LD3(t, p, r, q); } } }
    ST(o, 2, u);
    WIN3(bad, x, 40, 3, 10, 2, 5, 5);
    ST(o, 3, (double)(PLANES(bad) * 100 + ROWS(bad) * 10 + COLS(bad)));
    WIN3(edge, x, 40, 2, 15, 2, 4, 1);
    ST(o, 4, (double)(PLANES(edge) * 100 + ROWS(edge) * 10 + COLS(edge)) + LD3(edge, 1, 1, 0));
    WIN3(ow, o3, 0, 2, 8, 2, 3, 2);
    for (int p = 0; p < 3; p++) { for (int r = 0; r < 3; r++) { for (int q = 0; q < 3; q++) { ST3(ow, p, r, q, (double)(1000 + p * 100 + r * 10 + q)); } } }
}` 1 32 )
    : ~ ( Vec f ) g ( vec_zeroed [f] 8 )
    : b _d ( gk_dbuf_download kit o g )
    : ~ ( Vec f ) g3 ( vec_zeroed [f] 16 )
    : b _d3 ( gk_dbuf_download kit o3 g3 )
    // 0..59 as 3 planes of 4 rows of 5: 1770, shape 345. Planes 30 apart,
    // rows 10 apart, 3 columns from 7: 7..9 17..19 37..39 47..49 = 336. A
    // window past element 59 is empty; one ending on it (40 + 15 + 4)
    // fits: shape 221 plus element 59. ST3 writes o3 at p*8 + r*3 + q for
    // p, r, q below 2 only.
    : b vals & & == ( vec_at [f] g 0 ) 1770.0 == ( vec_at [f] g 1 ) 345.0 & & == ( vec_at [f] g 2 ) 336.0 == ( vec_at [f] g 3 ) 0.0 == ( vec_at [f] g 4 ) 280.0
    : b st1 & & == ( vec_at [f] g3 0 ) 1000.0 == ( vec_at [f] g3 1 ) 1001.0 & == ( vec_at [f] g3 3 ) 1010.0 == ( vec_at [f] g3 4 ) 1011.0
    : b st2 & & == ( vec_at [f] g3 8 ) 1100.0 == ( vec_at [f] g3 12 ) 1111.0 & == ( vec_at [f] g3 2 ) 0.0 == ( vec_at [f] g3 15 ) 0.0
    : b sts & st1 st2
    ? & & ran vals sts {
        ( nurl_print `ok   3-D windows read and write their planes, rows and columns; one outside its buffer is empty\n` )
    } {
        ( nurl_print `FAIL 3-D windows: ` ) ( nurl_print ( gk_checked_error c ) )
        : ~ String vs ( string_new )
        : ~ i r 0
        ~ < r 8 { ( string_push_str vs ` ` ) ( string_push_float vs ( vec_at [f] g r ) ) = r + r 1 }
        ( nurl_print ( string_data vs ) ) ( nurl_print `\n` ) = g_fail + g_fail 1
    }
    : ~ GkCall c2 ( gk_call_new )
    ( gk_call_dev_in c2 `x` x ) ( gk_call_dev c2 `o` o )
    : b bad1 ( gk_run_checked_dev kit c2 `w3st` `WIN3(m, x, 0, 2, 20, 2, 5, 2); ST3(m, 0, 0, 0, 1.0);` 1 32 )
    : b bad2 ( gk_run_checked_dev kit c2 `w3ld` `WIN3(m, x, 0, 2, 20, 2, 5, 2); ST(o, 0, LD(m, 0));` 1 32 )
    : b bad3 ( gk_run_checked_dev kit c2 `w3ld2` `WIN2(m, x, 0, 2, 5, 2); ST(o, 0, LD3(m, 0, 0, 0));` 1 32 )
    ? | | bad1 bad2 bad3 { ( nurl_print `FAIL a store into a read 3-D window, LD on one or LD3 on a 2-D one was launched\n` ) = g_fail + g_fail 1 } { ( nurl_print `ok   refuses a store into a read 3-D window, LD on one and LD3 on a 2-D one\n` ) }

    // exact lengths: the same body over two lengths builds two kernels,
    // each summing its own buffer whole
    : GkBuf x2 ( gk_dbuf_new kit 24 GK_F64 )
    : b _u2 ( gk_dbuf_upload kit x2 ( vec_zeroed [f] 24 ) )
    : ~ i ex 0
    : ~ i which 0
    ~ < which 2 {
        : ~ GkCall ce ( gk_call_new )
        ? == which 0 { ( gk_call_dev_in ce `x` x ) } { ( gk_call_dev_in ce `x` x2 ) }
        ( gk_call_dev ce `o` o ) ( gk_call_exact ce )
        : ~ String eb ( string_from `if (gid == 0) { WIN(w, x, 0, ` )
        ( string_push_str eb ? == which 0 `60` `24` )
        ( string_push_str eb `); double s = 0.0; for (int j = 0; j < LEN(w); j++) { s += LD(w, j); } ST(o, 5, s); }` )
        : b ok ( gk_run_checked_dev kit ce `exsum` ( string_data eb ) 1 32 )
        : ~ ( Vec f ) ge ( vec_zeroed [f] 8 )
        : b _de ( gk_dbuf_download kit o ge )
        ? & ok == ( vec_at [f] ge 5 ) ? == which 0 1770.0 0.0 { = ex + ex 1 } {}
        = which + which 1
    }
    ? == ex 2 { ( nurl_print `ok   exact-length kernels over two lengths each read their own buffer\n` ) } { ( nurl_print `FAIL exact-length kernels\n` ) = g_fail + g_fail 1 }

    // by tag: the body is made once per tag, launch after launch
    = g_mk 0
    : ~ i tg 0
    : ~ i rep 0
    ~ < rep 3 {
        : ~ GkCall ct ( gk_call_new )
        ( gk_call_dev_in ct `x` x ) ( gk_call_dev ct `o` o )
        : b ok ( gk_run_checked_dev_tagged kit ct `tagged` `t1` \ → String {
            = g_mk + g_mk 1
            ^ ( string_from `if (gid == 0) { ST(o, 6, LD(x, 3) + LD(x, 4)); }` )
        } 1 32 )
        ? ok { = tg + tg 1 } {}
        = rep + rep 1
    }
    : ~ GkCall ct2 ( gk_call_new )
    ( gk_call_dev_in ct2 `x` x ) ( gk_call_dev ct2 `o` o )
    : b ok2 ( gk_run_checked_dev_tagged kit ct2 `tagged` `t2` \ → String {
        = g_mk + g_mk 1
        ^ ( string_from `if (gid == 0) { ST(o, 7, LD(x, 5) * 2.0); }` )
    } 1 32 )
    : ~ ( Vec f ) gt ( vec_zeroed [f] 8 )
    : b _dt ( gk_dbuf_download kit o gt )
    ? & & == tg 3 ok2 & & == g_mk 2 == ( vec_at [f] gt 6 ) 7.0 == ( vec_at [f] gt 7 ) 10.0 { ( nurl_print `ok   a tagged kernel's body is made once per tag\n` ) } { ( nurl_print `FAIL tagged launches (bodies made: ` ) ( nurl_print_int g_mk ) ( nurl_print `)\n` ) = g_fail + g_fail 1 }
    : ~ GkCall ct3 ( gk_call_new )
    ( gk_call_dev_in ct3 `x` x ) ( gk_call_dev ct3 `o` o )
    ? ( gk_run_checked_dev_tagged kit ct3 `tagged4` `t` \ → String { ^ ( string_from `float a, b, c, d; LD4(x, 0, a, b, c, d); ST(o, 0, a);` ) } 1 32 ) { ( nurl_print `FAIL a tagged kernel reading LD4 was launched\n` ) = g_fail + g_fail 1 } { ( nurl_print `ok   refuses LD4 in a tagged kernel\n` ) }
}

@ main → i {
    : GpuKit kit ( gk_open_best )
    ? ( gk_ok kit ) {} { ( nurl_print `SKIP no device\n` ) ^ 0 }
    ( subset kit )
    ( run kit )
    ( run_views kit )
    ( dsubset kit )
    ( drun kit )
    ( xrun kit )
    ( rrun kit )
    ( urun kit )
    ( qrun kit )
    ( v4run kit )
    ( wrun kit )
    ( w2run kit )
    ( w3run kit )
    ? == g_fail 0 { ( nurl_print `checked: all passed\n` ) } { ( nurl_print `checked: FAILURES\n` ) }
    ^ 0
}
