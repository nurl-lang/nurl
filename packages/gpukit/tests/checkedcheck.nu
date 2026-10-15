// tests/checkedcheck.nu — gk_run_checked: which bodies the subset takes,
// and what a checked kernel does on the CPU backend, out-of-range indices
// included. Prints one `ok …` / `FAIL …` line per case and a summary.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
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
// a negative one (a load reads element 0, a store is dropped).
@ run GpuKit kit → v {
    : ~ ( Vec f ) xs ( vec_new [f] )
    ( vec_push [f] xs 1.5 ) ( vec_push [f] xs 2.5 ) ( vec_push [f] xs 3.5 ) ( vec_push [f] xs 4.5 )
    : ~ GkCall c ( gk_call_new )
    ( gk_call_in_f c `x` xs )
    ( gk_call_out_f c `y` ( vec_zeroed [f] 6 ) )
    ( gk_call_i64 c `n` 4 )
    // thread 4 reads x[4] (past the end → x[0]); thread 5 stores at -1 (dropped)
    : b ok ( gk_run_checked kit c `checked_run` `if (gid < 5) ST(y, gid, 2.0 * LD(x, gid)); else ST(y, -1, 99.0);` 6 64 )
    : ( Vec f ) ys ( gk_call_take_f c `y` )
    : ~ String got ( string_new )
    : ~ i k 0
    ~ < k ( vec_len [f] ys ) { ? > k 0 { ( string_push_char got 44 ) } {} ( string_push_float got ( vec_at [f] ys k ) ) = k + k 1 }
    : b want_ok ( nurl_str_eq ( string_data got ) `3,5,7,9,3,0` )
    ? & ok != 0 want_ok { ( nurl_print `ok   checked kernel ran: ` ) } { ( nurl_print `FAIL checked kernel ran: ` ) = g_fail + g_fail 1 }
    ( nurl_print ( string_data got ) ) ( nurl_print `\n` )
}

// Inputs bound as views (gk_call_view_f / _i): read in place, an index
// past the end of either reads its element 0.
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
    : b want_ok ( nurl_str_eq ( string_data got ) `3.5,2.5,3.5,6.5` )
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

@ main → i {
    : GpuKit kit ( gk_open 0 )
    ? ( gk_ok kit ) {} { ( nurl_print `SKIP no device\n` ) ^ 0 }
    ( subset kit )
    ( run kit )
    ( run_views kit )
    ( dsubset kit )
    ( drun kit )
    ? == g_fail 0 { ( nurl_print `checked: all passed\n` ) } { ( nurl_print `checked: FAILURES\n` ) }
    ^ 0
}
