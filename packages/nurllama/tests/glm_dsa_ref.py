# Reference for the glm-dsa architecture (GLM-5.x, HF `glm_moe_dsa`):
# HF transformers' own GlmMoeDsaForCausalLM, in float32, on a TINY random
# checkpoint this script makes. Nothing here shares code with the NURL side.
#
# The tiny model keeps every structural feature of GLM-5.3 at small sizes:
#   * MLA attention — q through a low-rank q_a / q_a_norm / q_b, K and V from
#     ONE compressed latent (kv_a_proj_with_mqa → kv_a_norm → kv_b_proj), a
#     per-head [nope | rope] split, interleaved (adjacent-pair) RoPE on the
#     rope part only, a single shared k_rope
#   * the DSA lightning indexer with index_topk = 8, so a prompt longer than
#     8 tokens actually attends a SELECTION of the past, and "shared" layers
#     that reuse the previous full layer's selection
#   * dense FFN layers first (first_k_dense_replace), then sigmoid-routed
#     noaux_tc MoE with a selection-only bias, normalised top-k weights times
#     routed_scaling_factor, and a shared expert
# Every norm, bias and the router's correction bias are randomised, so a
# missing or misplaced one changes the output.
#
# usage:
#   glm_dsa_ref.py make <outdir> <tokenizer-dir>   write the HF checkpoint
#   glm_dsa_ref.py logits <hfdir> "<id id …>"      final-position logits
#   glm_dsa_ref.py greedy <hfdir> "<id id …>" <n>  n greedy ids (full
#                                                  recompute per step, no cache)
import os
import shutil
import sys

import torch


def make(outdir, tokdir):
    from transformers import GlmMoeDsaConfig, GlmMoeDsaForCausalLM
    torch.manual_seed(513)
    cfg = GlmMoeDsaConfig(
        vocab_size=154880,
        # every width distinct from every other (and heads·v_head ≠ hidden),
        # so a swapped or transposed dimension cannot pass by coincidence;
        # every matrix width a multiple of 32, so a q8_0 conversion works
        hidden_size=128,
        intermediate_size=224,
        moe_intermediate_size=32,
        num_hidden_layers=6,
        num_attention_heads=6,
        num_key_value_heads=6,
        n_shared_experts=1,
        n_routed_experts=16,
        num_experts_per_tok=4,
        routed_scaling_factor=2.5,
        n_group=1,
        topk_group=1,
        norm_topk_prob=True,
        first_k_dense_replace=2,
        kv_lora_rank=96,
        q_lora_rank=160,
        qk_rope_head_dim=16,
        qk_nope_head_dim=64,
        v_head_dim=32,
        index_topk=8,
        index_head_dim=48,
        index_n_heads=12,
        indexer_types=["full", "full", "shared", "full", "shared", "shared"],
        max_position_embeddings=1048576,
        rope_parameters={"rope_theta": 8000000.0, "rope_type": "default"},
        rms_norm_eps=1e-5,
        initializer_range=0.08,
        tie_word_embeddings=False,
        bos_token_id=None,
        eos_token_id=[154820, 154827, 154829],
        pad_token_id=154820,
    )
    model = GlmMoeDsaForCausalLM(cfg).float().eval()
    with torch.no_grad():
        for name, p in model.named_parameters():
            if name.endswith("norm.weight") or name.endswith("layernorm.weight"):
                p.copy_(1.0 + 0.1 * torch.randn_like(p))
            elif name.endswith("k_norm.bias"):
                p.copy_(0.1 * torch.randn_like(p))
        for name, b in model.named_buffers():
            if name.endswith("e_score_correction_bias"):
                b.copy_(0.05 * torch.randn_like(b))
    model.save_pretrained(outdir, safe_serialization=True)
    for f in ("tokenizer.json", "tokenizer_config.json", "chat_template.jinja", "generation_config.json"):
        src = os.path.join(tokdir, f)
        if os.path.exists(src):
            shutil.copy(src, os.path.join(outdir, f))


def load(hfdir):
    from transformers import GlmMoeDsaForCausalLM
    m = GlmMoeDsaForCausalLM.from_pretrained(hfdir, dtype=torch.float32, attn_implementation="eager")
    return m.eval()


def final_logits(m, ids):
    with torch.no_grad():
        out = m(input_ids=torch.tensor([ids]), use_cache=False)
    return out.logits[0, -1]


def main():
    cmd = sys.argv[1]
    if cmd == "make":
        make(sys.argv[2], sys.argv[3])
        return
    m = load(sys.argv[2])
    ids = [int(t) for t in sys.argv[3].split()]
    if cmd == "logits":
        for v in final_logits(m, ids).tolist():
            print("%.9g" % v)
    elif cmd == "greedy":
        n = int(sys.argv[4])
        out = []
        for _ in range(n):
            t = int(torch.argmax(final_logits(m, ids)))
            out.append(t)
            ids.append(t)
        print(" ".join(map(str, out)))
    else:
        raise SystemExit("unknown command " + cmd)


if __name__ == "__main__":
    main()
