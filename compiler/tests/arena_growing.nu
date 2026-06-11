// arena_growing.nu — regression for the chained-chunk GROWING arena and
// the typed `arena_alloc_n [T]` allocator added on feature/arena-growing.
//
// Covers:
//   * a growing arena spills into multiple chunks once a chunk fills;
//   * pointers handed out BEFORE a grow stay valid AFTER it (chunks are
//     never moved/realloc'd) — the whole point of the chained model;
//   * arena_used / arena_cap sum across chunks;
//   * an oversized request (> chunk_sz) gets its own exact-fit chunk;
//   * typed arena_alloc_n [T] round-trips a struct array;
//   * arena_reset frees the extra chunks, keeps one base chunk, and the
//     arena is reusable;
//   * a FIXED arena still OOMs (no silent growth).
//
// Pointer bookkeeping deliberately avoids Vec (a standalone single-file
// compile can't realise the %Vec__i64 monomorph) — a small FIXED arena
// holds the pointer-as-int table instead, exercising that path too.
//
// main returns the number of failed checks (0 = all pass).

$ `stdlib/std/arena.nu`

: Pt { i x i y }

@ chk i got i want s tag → i {
    ? == got want {
        ( nurl_print tag ) ( nurl_print ` ok\n` ) ^ 0
    } {
        ( nurl_print tag ) ( nurl_print ` FAIL\n` ) ^ 1
    }
}

@ main → i {
    : ~ i f 0

    // Growing arena, tiny chunks (32 bytes ⇒ 4 i64 slots per chunk).
    : Arena g ( arena_growing 32 )
    // Side table holding 20 slot pointers (as ints) — a FIXED arena.
    : Arena store ( arena_with_cap 200 )
    : *i pbuf # *i ( arena_alloc store 160 )

    // Allocate 20 i64 slots one at a time, writing k into slot k. This
    // forces several grows; record every pointer in pbuf.
    : ~ i k 0
    ~ < k 20 {
        : *i slot # *i ( arena_alloc g 8 )
        = . slot 0 k
        : *i cell # *i + # i pbuf * k 8
        = . cell 0 # i slot
        = k + k 1
    }

    // It must actually have grown past one chunk.
    = f + f ( chk ? > ( arena_chunk_count g ) 1 1 0 1 `grew_multiple_chunks` )

    // Read every earlier pointer back — none corrupted by later grows.
    : ~ i sum 0
    : ~ i j 0
    ~ < j 20 {
        : *i cell # *i + # i pbuf * j 8
        : *i sp # *i . cell 0
        = sum + sum . sp 0
        = j + j 1
    }
    = f + f ( chk sum 190 `pointers_valid_across_growth` )  // 0+1+…+19

    // Accounting across chunks: 20 × 8 = 160 bytes consumed.
    = f + f ( chk ( arena_used g ) 160 `used_sums_chunks` )
    = f + f ( chk ? >= ( arena_cap g ) 160 1 0 1 `cap_covers_used` )

    // Oversized request (> chunk_sz = 32) gets its own exact-fit chunk.
    : *u big ( arena_alloc g 256 )
    = f + f ( chk ? != 0 # i big 1 0 1 `oversize_alloc_ok` )

    // Typed allocation: an array of 5 Pt in one shot.
    : *Pt arr ( arena_alloc_n [Pt] g 5 )
    = f + f ( chk ? != 0 # i arr 1 0 1 `alloc_n_nonnull` )
    : ~ i w 0
    ~ < w 5 {
        : *Pt e # *Pt + # i arr * w Z Pt
        = . e x w
        = . e y * w 10
        = w + w 1
    }
    : ~ i tsum 0
    : ~ i r 0
    ~ < r 5 {
        : *Pt e # *Pt + # i arr * r Z Pt
        = tsum + tsum + . e x . e y
        = r + r 1
    }
    // (0+1+2+3+4) + (0+10+20+30+40) = 10 + 100
    = f + f ( chk tsum 110 `alloc_n_roundtrip` )

    // Reset: extra chunks freed, back to one base chunk, reusable.
    ( arena_reset g )
    = f + f ( chk ( arena_chunk_count g ) 1 `reset_keeps_one_chunk` )
    = f + f ( chk ( arena_used g ) 0 `reset_zeroes_used` )
    : *i after # *i ( arena_alloc g 8 )
    = . after 0 777
    = f + f ( chk . after 0 777 `usable_after_reset` )

    ( arena_free g )
    ( arena_free store )

    // FIXED arena still OOMs — no silent growth.
    : Arena fx ( arena_with_cap 16 )
    : *u o1 ( arena_alloc fx 16 )
    : *u o2 ( arena_alloc fx 8 )
    = f + f ( chk ? != 0 # i o1 1 0 1 `fixed_first_ok` )
    = f + f ( chk ? == 0 # i o2 1 0 1 `fixed_oom_null` )
    = f + f ( chk ( arena_chunk_count fx ) 1 `fixed_never_grows` )
    ( arena_free fx )

    ^ f
}
