// simd_v4_dispatch.nu — `simd v4` (grammar v2.12): a third clone for
// x86-64-v4 beside the baseline and x86-64-v3 ones, and the prefix in
// either order with `pub`. The answer is the same whichever clone the
// dispatcher picks; simd_dispatch_ir.sh checks that the clone exists,
// that it is AVX-512 code, and runs this again with NURL_CPU_V4=0.

$ `stdlib/core/vec.nu`

// A rotate-heavy lane loop: VPROLD in the v4 clone, shift pairs below.
simd v4

@ mix ( Vec u32 ) v → u32 {
    : ~ u32 acc 0
    : ~ i k 0
    ~ < k ( vec_len [u32] v ) {
        : u32 x ?? ( vec_get [u32] v k ) { T y → y F _ → # u32 0 }
        : u32 r | << x # u32 7 >> x # u32 25
        = acc + acc ^^ r | << x # u32 13 >> x # u32 19
        = k + k 1
    }
    ^ acc
}

pub simd v4

@ twice i x → i { ^ * x 2 }

// The CPU level, asked from inside each clone. The probes its dispatcher
// already answered fold to constants there (v3 and v4 in `.x86v4`, v3 in
// `.x86v3`, both in `.base`), and must still say what the runtime says
// outside. A plain `simd` `.x86v3` also runs on a v4 CPU: its v4 probe
// stays a call.
simd v4

@ level → i { ^ + # i ( nurl_cpu_x86_v3 ) * 2 # i ( nurl_cpu_x86_v4 ) }

simd @ level3 → i { ^ + # i ( nurl_cpu_x86_v3 ) * 2 # i ( nurl_cpu_x86_v4 ) }

@ main → i {
    : ( Vec u32 ) v ( vec_with_cap [u32] 1000 )
    : ~ i k 0
    ~ < k 1000 { ( vec_push [u32] v # u32 + * k 2654435761 12345 ) = k + k 1 }
    ( nurl_println_int # i ( mix v ) )
    ( nurl_println_int ( twice 21 ) )
    : i want + # i ( nurl_cpu_x86_v3 ) * 2 # i ( nurl_cpu_x86_v4 )
    ( nurl_println ? & == ( level ) want == ( level3 ) want `probes agree` `probes DISAGREE` )
    ^ 0
}
