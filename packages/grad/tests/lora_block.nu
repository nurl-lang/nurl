// packages/grad/tests/lora_block.nu — the shared Qwen2-style LoRA block
// builder used by lora_block_test.nu (FD + replay + training) and
// lora_dump.nu (the PyTorch float64 oracle's bit dump). No main here.
// See lora_block_test.nu's header for the design notes.

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/rng.nu`
$ `src/grad.nu`
$ `deps/tensor/src/tensor.nu`

// ── model dimensions (small on purpose: FD probes rebuild the block) ──
@ cT → i { ^ 8 }

@ cH → i { ^ 16 }

@ cNH → i { ^ 4 }

@ cKV → i { ^ 2 }

@ cHD → i { ^ 4 }

@ cIN → i { ^ 32 }

@ cV → i { ^ 16 }

@ cR → i { ^ 2 }

@ cSCALE → f { ^ 2.0 }

// ── deterministic pseudo-random fill (shared with the oracle dump) ────
@ fill Rng g i n f sc ( Vec f ) out → v {
    : ~ i k 0
    ~ < k n { ( vec_push [f] out * sc - * 2.0 ( rng_u01 g ) 1.0 ) = k + k 1 }
}

// The whole frozen block + data, one flat context.
: Blk {
    ( Vec f ) x  // input rows [T,H]
    ( Vec f ) wq ( Vec f ) bq  // [H, NH*HD], [NH*HD]
    ( Vec f ) wk ( Vec f ) bk  // [H, KV*HD], [KV*HD]
    ( Vec f ) wv ( Vec f ) bv
    ( Vec f ) wo  // [NH*HD, H]
    ( Vec f ) wg ( Vec f ) wu  // [H, IN]
    ( Vec f ) wd  // [IN, H]
    ( Vec f ) n1 ( Vec f ) n2 ( Vec f ) nf  // rmsnorm weights [H]
    ( Vec f ) wout  // [H, V]
    ( Vec f ) cosv ( Vec f ) sinv  // [T, HD/2]
    ( Vec f ) mask  // [T, T] causal (0 / -1e9)
    ( Vec f ) onehot  // [T, V] targets
    ( Vec f ) la  // 7 adapters × A [.., R] — one flat vec, offsets by index
    ( Vec f ) lb  // 7 adapters × B [R, ..]
}

// adapter table: in/out per adapter index (q k v o gate up down)
@ ain i k → i {
    ? == k 3 { ^ * ( cNH ) ( cHD ) } {}
    ? == k 6 { ^ ( cIN ) } {}
    ^ ( cH )
}

@ aout i k → i {
    ? == k 0 { ^ * ( cNH ) ( cHD ) } {}
    ? | == k 1 == k 2 { ^ * ( cKV ) ( cHD ) } {}
    ? == k 3 { ^ ( cH ) } {}
    ? | == k 4 == k 5 { ^ ( cIN ) } {}
    ^ ( cH )
}

@ aoffA i k → i {
    : ~ i o 0
    : ~ i j 0
    ~ < j k { = o + o * ( ain j ) ( cR ) = j + j 1 }
    ^ o
}

@ aoffB i k → i {
    : ~ i o 0
    : ~ i j 0
    ~ < j k { = o + o * ( cR ) ( aout j ) = j + j 1 }
    ^ o
}

@ blk_new i seed b zero_b → Blk {
    : Rng g ( rng_seed seed )
    : i NT ( cT )
    : i H ( cH )
    : i QD * ( cNH ) ( cHD )
    : i KD * ( cKV ) ( cHD )
    : ( Vec f ) x ( vec_new [f] )
    ( fill g * NT H 0.8 x )
    : ( Vec f ) wq ( vec_new [f] )
    ( fill g * H QD 0.3 wq )
    : ( Vec f ) bq ( vec_new [f] )
    ( fill g QD 0.1 bq )
    : ( Vec f ) wk ( vec_new [f] )
    ( fill g * H KD 0.3 wk )
    : ( Vec f ) bk ( vec_new [f] )
    ( fill g KD 0.1 bk )
    : ( Vec f ) wv ( vec_new [f] )
    ( fill g * H KD 0.3 wv )
    : ( Vec f ) bv ( vec_new [f] )
    ( fill g KD 0.1 bv )
    : ( Vec f ) wo ( vec_new [f] )
    ( fill g * QD H 0.3 wo )
    : ( Vec f ) wg ( vec_new [f] )
    ( fill g * H ( cIN ) 0.3 wg )
    : ( Vec f ) wu ( vec_new [f] )
    ( fill g * H ( cIN ) 0.3 wu )
    : ( Vec f ) wd ( vec_new [f] )
    ( fill g * ( cIN ) H 0.3 wd )
    : ( Vec f ) n1 ( vec_new [f] )
    ( fill g H 0.2 n1 )
    : ~ i k 0
    ~ < k H { ( vec_set [f] n1 k + 1.0 ( _tf n1 k ) ) = k + k 1 }
    : ( Vec f ) n2 ( vec_new [f] )
    ( fill g H 0.2 n2 )
    = k 0
    ~ < k H { ( vec_set [f] n2 k + 1.0 ( _tf n2 k ) ) = k + k 1 }
    : ( Vec f ) nf ( vec_new [f] )
    ( fill g H 0.2 nf )
    = k 0
    ~ < k H { ( vec_set [f] nf k + 1.0 ( _tf nf k ) ) = k + k 1 }
    : ( Vec f ) wout ( vec_new [f] )
    ( fill g * H ( cV ) 0.3 wout )
    // NEOX rope tables: theta = 10000^(-2i/HD), pos t
    : ( Vec f ) cosv ( vec_new [f] )
    : ( Vec f ) sinv ( vec_new [f] )
    : i HALF / ( cHD ) 2
    : ~ i t 0
    ~ < t NT {
        : ~ i i2 0
        ~ < i2 HALF {
            : f fr ( pow 10000.0 / * -2.0 # f i2 # f ( cHD ) )
            : f ang * # f t fr
            ( vec_push [f] cosv ( float_cos ang ) )
            ( vec_push [f] sinv ( float_sin ang ) )
            = i2 + i2 1
        }
        = t + t 1
    }
    : ( Vec f ) mask ( vec_new [f] )
    = t 0
    ~ < t NT {
        : ~ i u 0
        ~ < u NT {
            ( vec_push [f] mask ? > u t -1000000000.0 0.0 )
            = u + u 1
        }
        = t + t 1
    }
    // one-hot targets: token (t*3+1) mod V at each position
    : ( Vec f ) onehot ( vec_new [f] )
    = t 0
    ~ < t NT {
        : i tgt % + * t 3 1 ( cV )
        : ~ i u 0
        ~ < u ( cV ) {
            ( vec_push [f] onehot ? == u tgt 1.0 0.0 )
            = u + u 1
        }
        = t + t 1
    }
    // adapters
    : ( Vec f ) la ( vec_new [f] )
    : ( Vec f ) lb ( vec_new [f] )
    = k 0
    ~ < k 7 {
        ( fill g * ( ain k ) ( cR ) 0.2 la )
        ? zero_b {
            : ~ i z 0
            ~ < z * ( cR ) ( aout k ) { ( vec_push [f] lb 0.0 ) = z + z 1 }
        } {
            ( fill g * ( cR ) ( aout k ) 0.2 lb )
        }
        = k + k 1
    }
    ( rng_free g )
    ^ @ Blk { x wq bq wk bk wv bv wo wg wu wd n1 n2 nf wout cosv sinv mask onehot la lb }
}

@ blk_free Blk b → v {
    ( vec_free [f] . b x )
    ( vec_free [f] . b wq ) ( vec_free [f] . b bq )
    ( vec_free [f] . b wk ) ( vec_free [f] . b bk )
    ( vec_free [f] . b wv ) ( vec_free [f] . b bv )
    ( vec_free [f] . b wo )
    ( vec_free [f] . b wg ) ( vec_free [f] . b wu ) ( vec_free [f] . b wd )
    ( vec_free [f] . b n1 ) ( vec_free [f] . b n2 ) ( vec_free [f] . b nf )
    ( vec_free [f] . b wout )
    ( vec_free [f] . b cosv ) ( vec_free [f] . b sinv )
    ( vec_free [f] . b mask ) ( vec_free [f] . b onehot )
    ( vec_free [f] . b la ) ( vec_free [f] . b lb )
}

// ── tape builders ─────────────────────────────────────────────────────

@ tconst * GTape tp ( Vec f ) v i r i c → GVar {
    : ( Vec i ) s ( vec_new [i] )
    ? > r 0 { ( vec_push [i] s r ) } {}
    ( vec_push [i] s c )
    : Tensor t ( tensor_from_data TE_F64 s v )
    : GVar o ( grad_const tp t )
    ( tensor_free t )
    ^ o
}

// slice a [la, c] range out of the la/lb pools as a const/param tensor
@ tsub * GTape tp ( Vec f ) pool i off i r i c b param → GVar {
    : ( Vec f ) v ( vec_with_cap [f] * r c )
    : ~ i k 0
    ~ < k * r c { ( vec_push [f] v ( _tf pool + off k ) ) = k + k 1 }
    : ( Vec i ) s ( vec_new [i] )
    ( vec_push [i] s r ) ( vec_push [i] s c )
    : Tensor t ( tensor_from_data TE_F64 s v )
    : GVar o ? param ( grad_param tp t ) ( grad_const tp t )
    ( tensor_free t ) ( vec_free [f] v )
    ^ o
}

// ones column [n,1] for row reductions
@ tones * GTape tp i n → GVar {
    : ( Vec f ) v ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n { ( vec_push [f] v 1.0 ) = k + k 1 }
    : GVar o ( tconst tp v n 1 )
    ( vec_free [f] v )
    ^ o
}

// rmsnorm: x ⊙ rsqrt(mean(x²)+eps) ⊙ w   (row mean via ones-matmul)
@ g_rmsnorm * GTape tp GVar x GVar w GVar ones i h → GVar {
    : GVar x2 ( g_mul tp x x )
    : GVar m ( g_muls tp ( g_matmul tp x2 ones ) / 1.0 # f h )  // [T,1]
    : GVar d ( g_sqrt tp ( g_adds tp m 0.000001 ) )
    ^ ( g_mul tp ( g_div tp x d ) w )
}

// LoRA linear: x·W0 (+bias) + (α/r)·(x·A)·B
@ g_lora_lin * GTape tp GVar x GVar w0 GVar a GVar b2 → GVar {
    : GVar base ( g_matmul tp x w0 )
    : GVar delta ( g_muls tp ( g_matmul tp ( g_matmul tp x a ) b2 ) / ( cSCALE ) # f ( cR ) )
    ^ ( g_add tp base delta )
}

// NEOX rope over one [T, HD] head: halves rotate with position tables
@ g_rope * GTape tp GVar h GVar cosc GVar sinc → GVar {
    : i NT ( cT )
    : i HALF / ( cHD ) 2
    : ( Vec i ) st1 ( vec_new [i] )
    ( vec_push [i] st1 0 ) ( vec_push [i] st1 0 )
    : ( Vec i ) sp1 ( vec_new [i] )
    ( vec_push [i] sp1 NT ) ( vec_push [i] sp1 HALF )
    : GVar x1 ( g_slice tp h st1 sp1 )
    : ( Vec i ) st2 ( vec_new [i] )
    ( vec_push [i] st2 0 ) ( vec_push [i] st2 HALF )
    : ( Vec i ) sp2 ( vec_new [i] )
    ( vec_push [i] sp2 NT ) ( vec_push [i] sp2 ( cHD ) )
    : GVar x2 ( g_slice tp h st2 sp2 )
    ( vec_free [i] st1 ) ( vec_free [i] sp1 )
    ( vec_free [i] st2 ) ( vec_free [i] sp2 )
    : GVar r1 ( g_sub tp ( g_mul tp x1 cosc ) ( g_mul tp x2 sinc ) )
    : GVar r2 ( g_add tp ( g_mul tp x2 cosc ) ( g_mul tp x1 sinc ) )
    ^ ( g_concat tp r1 r2 1 )
}

// head slice [T, off:off+HD] of a [T, n*HD] projection
@ g_head * GTape tp GVar q i off → GVar {
    : ( Vec i ) st ( vec_new [i] )
    ( vec_push [i] st 0 ) ( vec_push [i] st off )
    : ( Vec i ) sp ( vec_new [i] )
    ( vec_push [i] sp ( cT ) ) ( vec_push [i] sp + off ( cHD ) )
    : GVar o ( g_slice tp q st sp )
    ( vec_free [i] st ) ( vec_free [i] sp )
    ^ o
}

// Build the whole block on `tp`. Params (in registration order): the 14
// adapter tensors A0 B0 A1 B1 … (q k v o gate up down). Everything else is
// const. Writes the param GVars into `pav`/`pbv` (7 each) when non-0.
@ build_block * GTape tp Blk bl * u pav * u pbv → GVar {
    : i HT ( cT )
    : i H ( cH )
    : i QD * ( cNH ) ( cHD )
    : i KD * ( cKV ) ( cHD )
    // adapters FIRST (stable low ids for the optimizer + FD probes)
    : ~ i k 0
    ~ < k 7 {
        : GVar pa ( tsub tp . bl la ( aoffA k ) ( ain k ) ( cR ) T )
        : GVar pb ( tsub tp . bl lb ( aoffB k ) ( cR ) ( aout k ) T )
        ? != # i pav 0 { ( nurl_poke pav k . pa id ) } {}
        ? != # i pbv 0 { ( nurl_poke pbv k . pb id ) } {}
        = k + k 1
    }
    : GVar Aq @ GVar { 0 }
    : GVar Bq @ GVar { 1 }
    : GVar Ak @ GVar { 2 }
    : GVar Bk @ GVar { 3 }
    : GVar Av @ GVar { 4 }
    : GVar Bv @ GVar { 5 }
    : GVar Ao @ GVar { 6 }
    : GVar Bo @ GVar { 7 }
    : GVar Ag @ GVar { 8 }
    : GVar Bg @ GVar { 9 }
    : GVar Au @ GVar { 10 }
    : GVar Bu @ GVar { 11 }
    : GVar Ad @ GVar { 12 }
    : GVar Bd @ GVar { 13 }
    : GVar X ( tconst tp . bl x HT H )
    : GVar Wq ( tconst tp . bl wq H QD )
    : GVar Bqb ( tconst tp . bl bq 0 QD )
    : GVar Wk ( tconst tp . bl wk H KD )
    : GVar Bkb ( tconst tp . bl bk 0 KD )
    : GVar Wv ( tconst tp . bl wv H KD )
    : GVar Bvb ( tconst tp . bl bv 0 KD )
    : GVar Wo ( tconst tp . bl wo QD H )
    : GVar Wg ( tconst tp . bl wg H ( cIN ) )
    : GVar Wu ( tconst tp . bl wu H ( cIN ) )
    : GVar Wd ( tconst tp . bl wd ( cIN ) H )
    : GVar N1 ( tconst tp . bl n1 0 H )
    : GVar N2 ( tconst tp . bl n2 0 H )
    : GVar Nf ( tconst tp . bl nf 0 H )
    : GVar Wout ( tconst tp . bl wout H ( cV ) )
    : GVar Cos ( tconst tp . bl cosv HT / ( cHD ) 2 )
    : GVar Sin ( tconst tp . bl sinv HT / ( cHD ) 2 )
    : GVar Mask ( tconst tp . bl mask HT HT )
    : GVar Oh ( tconst tp . bl onehot HT ( cV ) )
    : GVar OnesH ( tones tp H )
    : GVar OnesV ( tones tp ( cV ) )

    // — attention —
    : GVar xn ( g_rmsnorm tp X N1 OnesH H )
    : GVar q ( g_add tp ( g_lora_lin tp xn Wq Aq Bq ) Bqb )
    : GVar kk ( g_add tp ( g_lora_lin tp xn Wk Ak Bk ) Bkb )
    : GVar vv ( g_add tp ( g_lora_lin tp xn Wv Av Bv ) Bvb )
    : ~ GVar ctx @ GVar { -1 }
    = k 0
    ~ < k ( cNH ) {
        : GVar qh ( g_rope tp ( g_head tp q * k ( cHD ) ) Cos Sin )
        : i kvi / k / ( cNH ) ( cKV )
        : GVar kh ( g_rope tp ( g_head tp kk * kvi ( cHD ) ) Cos Sin )
        : GVar vh ( g_head tp vv * kvi ( cHD ) )
        : GVar sc ( g_muls tp ( g_matmul tp qh ( g_transpose tp kh ) ) / 1.0 ( float_sqrt # f ( cHD ) ) )
        : GVar aw ( g_softmax tp ( g_add tp sc Mask ) 1 )
        : GVar ch ( g_matmul tp aw vh )
        ? < . ctx id 0 { = ctx ch } { = ctx ( g_concat tp ctx ch 1 ) }
        = k + k 1
    }
    : GVar attn ( g_lora_lin tp ctx Wo Ao Bo )
    : GVar x1 ( g_add tp X attn )
    // — mlp —
    : GVar x1n ( g_rmsnorm tp x1 N2 OnesH H )
    : GVar gate ( g_lora_lin tp x1n Wg Ag Bg )
    : GVar up ( g_lora_lin tp x1n Wu Au Bu )
    : GVar act ( g_mul tp ( g_mul tp gate ( g_sigmoid tp gate ) ) up )
    : GVar down ( g_lora_lin tp act Wd Ad Bd )
    : GVar x2 ( g_add tp x1 down )
    // — head + loss —
    : GVar xf ( g_rmsnorm tp x2 Nf OnesH H )
    : GVar logits ( g_matmul tp xf Wout )
    : GVar probs ( g_softmax tp logits 1 )
    : GVar picked ( g_matmul tp ( g_mul tp probs Oh ) OnesV )  // [T,1]
    ^ ( g_neg tp ( g_mean tp ( g_log tp picked ) ) )
}
