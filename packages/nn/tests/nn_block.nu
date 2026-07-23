// nn_block.nu — the SAME Qwen2-style LoRA block grad proves in
// tests/lora_block.nu, rebuilt from nn primitives. Data generation (Blk,
// blk_new, seed 42, the adapter table) is copied verbatim so the bit dump
// is byte-identical to grad's; only the graph is rewritten to call nn_*.
// nn_dump.nu prints the bits, nn_oracle.sh rebuilds the graph in PyTorch
// float64 and compares loss + all 14 adapter gradients to 1e-11.
// No main here.

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/rng.nu`
$ `src/nn.nu`
$ `deps/grad/src/grad.nu`
$ `deps/tensor/src/tensor.nu`

@ cT → i { ^ 8 }

@ cH → i { ^ 16 }

@ cNH → i { ^ 4 }

@ cKV → i { ^ 2 }

@ cHD → i { ^ 4 }

@ cIN → i { ^ 32 }

@ cV → i { ^ 16 }

@ cR → i { ^ 2 }

@ cSCALE → f { ^ 2.0 }

@ fill Rng g i n f sc ( Vec f ) out → v {
    : ~ i k 0
    ~ < k n { ( vec_push [f] out * sc - * 2.0 ( rng_u01 g ) 1.0 ) = k + k 1 }
}

: Blk {
    ( Vec f ) x
    ( Vec f ) wq ( Vec f ) bq
    ( Vec f ) wk ( Vec f ) bk
    ( Vec f ) wv ( Vec f ) bv
    ( Vec f ) wo
    ( Vec f ) wg ( Vec f ) wu
    ( Vec f ) wd
    ( Vec f ) n1 ( Vec f ) n2 ( Vec f ) nf
    ( Vec f ) wout
    ( Vec f ) cosv ( Vec f ) sinv
    ( Vec f ) mask
    ( Vec f ) onehot
    ( Vec f ) la
    ( Vec f ) lb
}

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
    : ( Vec f ) cosv ( vec_new [f] )
    : ( Vec f ) sinv ( vec_new [f] )
    ( nn_rope_fill NT ( cHD ) 10000.0 cosv sinv )
    : ( Vec f ) mask ( vec_new [f] )
    ( nn_causal_mask_fill NT mask )
    : ( Vec f ) onehot ( vec_new [f] )
    : ~ i t 0
    ~ < t NT {
        : i tgt % + * t 3 1 ( cV )
        : ~ i u 0
        ~ < u ( cV ) {
            ( vec_push [f] onehot ? == u tgt 1.0 0.0 )
            = u + u 1
        }
        = t + t 1
    }
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

// slice a [r,c] range out of the la/lb pools as a param/const tensor
@ tsub * GTape tp ( Vec f ) pool i off i r i c b param → GVar {
    : ( Vec f ) v ( vec_with_cap [f] * r c )
    : ~ i k 0
    ~ < k * r c { ( vec_push [f] v ( _tf pool + off k ) ) = k + k 1 }
    : GVar o ? param ( nn_param tp v r c ) ( nn_const tp v r c )
    ( vec_free [f] v )
    ^ o
}

// The block, built from nn primitives. Params (registration order): the 14
// adapter tensors A0 B0 A1 B1 … (q k v o gate up down). Writes param ids to
// pav/pbv (7 each) when non-0.
@ build_block * GTape tp Blk bl * u pav * u pbv → GVar {
    : i HT ( cT )
    : i H ( cH )
    : i QD * ( cNH ) ( cHD )
    : i KD * ( cKV ) ( cHD )
    : f SCALE / ( cSCALE ) # f ( cR )
    : f iscale / 1.0 ( float_sqrt # f ( cHD ) )
    // adapters FIRST
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
    : GVar X ( nn_const tp . bl x HT H )
    : GVar Wq ( nn_const tp . bl wq H QD )
    : GVar Bqb ( nn_const tp . bl bq 0 QD )
    : GVar Wk ( nn_const tp . bl wk H KD )
    : GVar Bkb ( nn_const tp . bl bk 0 KD )
    : GVar Wv ( nn_const tp . bl wv H KD )
    : GVar Bvb ( nn_const tp . bl bv 0 KD )
    : GVar Wo ( nn_const tp . bl wo QD H )
    : GVar Wg ( nn_const tp . bl wg H ( cIN ) )
    : GVar Wu ( nn_const tp . bl wu H ( cIN ) )
    : GVar Wd ( nn_const tp . bl wd ( cIN ) H )
    : GVar N1 ( nn_const tp . bl n1 0 H )
    : GVar N2 ( nn_const tp . bl n2 0 H )
    : GVar Nf ( nn_const tp . bl nf 0 H )
    : GVar Wout ( nn_const tp . bl wout H ( cV ) )
    : GVar Cos ( nn_const tp . bl cosv HT / ( cHD ) 2 )
    : GVar Sin ( nn_const tp . bl sinv HT / ( cHD ) 2 )
    : GVar Mask ( nn_const tp . bl mask HT HT )
    : GVar Oh ( nn_const tp . bl onehot HT ( cV ) )
    : GVar OnesH ( nn_ones tp H )
    : GVar OnesV ( nn_ones tp ( cV ) )

    // — attention —
    : GVar xn ( nn_rmsnorm tp X N1 OnesH H 0.000001 )
    : GVar q ( g_add tp ( nn_lora_linear tp xn Wq Aq Bq SCALE ) Bqb )
    : GVar kk ( g_add tp ( nn_lora_linear tp xn Wk Ak Bk SCALE ) Bkb )
    : GVar vv ( g_add tp ( nn_lora_linear tp xn Wv Av Bv SCALE ) Bvb )
    : GVar ctx ( nn_gqa_attention tp q kk vv Cos Sin Mask HT ( cNH ) ( cKV ) ( cHD ) iscale )
    : GVar attn ( nn_lora_linear tp ctx Wo Ao Bo SCALE )
    : GVar x1 ( g_add tp X attn )
    // — mlp —
    : GVar x1n ( nn_rmsnorm tp x1 N2 OnesH H 0.000001 )
    : GVar gate ( nn_lora_linear tp x1n Wg Ag Bg SCALE )
    : GVar up ( nn_lora_linear tp x1n Wu Au Bu SCALE )
    : GVar act ( nn_swiglu tp gate up )
    : GVar down ( nn_lora_linear tp act Wd Ad Bd SCALE )
    : GVar x2 ( g_add tp x1 down )
    // — head + loss —
    : GVar xf ( nn_rmsnorm tp x2 Nf OnesH H 0.000001 )
    : GVar logits ( nn_linear tp xf Wout )
    ^ ( nn_cross_entropy tp logits Oh OnesV )
}
