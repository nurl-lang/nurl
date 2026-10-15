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
        : b ok ( gk_run_checked_dev kit c `halves` `ST(o, gid, LD(h, gid));` 256 256 )
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
        ( nurl_print ? bf `bf16` `f16` ) ( nurl_print ` bit pattern loads as the host converts it (bad ` ) ( nurl_print_int bad ) ( nurl_print `)\n` )
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

@ main → i {
    : GpuKit kit ( gk_open_best )
    ? ( gk_ok kit ) {} { ( nurl_print `SKIP no device\n` ) ^ 0 }
    ( subset kit )
    ( run kit )
    ( run_views kit )
    ( dsubset kit )
    ( drun kit )
    ( xrun kit )
    ? == g_fail 0 { ( nurl_print `checked: all passed\n` ) } { ( nurl_print `checked: FAILURES\n` ) }
    ^ 0
}
