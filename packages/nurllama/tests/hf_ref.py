# Tiny Hugging Face checkpoints, and HF transformers' own outputs for them —
# the reference tests/hf_dir_test.sh holds nurllama's direct opening of a
# checkpoint directory (src/hfmodel.nu) against.
#
# usage:
#   hf_ref.py make <arch> <outdir> <tokenizer-dir> [<exllamav3-dir>]
#       arch: llama | qwen3 | glm_moe_dsa. With an exllamav3 tree, every
#       attention output projection and MLP down projection is stored as an
#       EXL3 tensor group instead (random trellis, MCG 4 bits and MUL1 5
#       bits in turn; widths padded to 128 as exllamav3 pads them), and the
#       model the reference runs carries exactly the weights those groups
#       decode to (exllamav3's tests/testlib/trellis.py)
#   hf_ref.py logits <dir> "<id id …>"        final-position logits
#   hf_ref.py greedy <dir> "<id id …>" <n>    n greedy ids (full recompute)
import json
import os
import shutil
import sys

import numpy as np
import torch


def tiny_config(arch):
    common = dict(vocab_size=154880, hidden_size=128, intermediate_size=224, rms_norm_eps=1e-5,
                  max_position_embeddings=4096, tie_word_embeddings=False, initializer_range=0.08,
                  bos_token_id=None, eos_token_id=[154820, 154827, 154829], pad_token_id=154820)
    if arch == "llama":
        from transformers import LlamaConfig
        return LlamaConfig(num_hidden_layers=3, num_attention_heads=4, num_key_value_heads=2,
                           rope_parameters={"rope_theta": 10000.0, "rope_type": "default"}, **common)
    if arch == "qwen3":
        from transformers import Qwen3Config
        # head_dim stated, and not hidden / heads
        return Qwen3Config(num_hidden_layers=3, num_attention_heads=4, num_key_value_heads=2, head_dim=48,
                           rope_parameters={"rope_theta": 1000000.0, "rope_type": "default"}, **common)
    if arch == "glm_moe_dsa":
        from transformers import GlmMoeDsaConfig
        common.update(intermediate_size=224)
        return GlmMoeDsaConfig(
            num_hidden_layers=6, num_attention_heads=6, num_key_value_heads=6, moe_intermediate_size=32,
            n_shared_experts=1, n_routed_experts=16, num_experts_per_tok=4, routed_scaling_factor=2.5,
            n_group=1, topk_group=1, norm_topk_prob=True, first_k_dense_replace=2, kv_lora_rank=96,
            q_lora_rank=160, qk_rope_head_dim=16, qk_nope_head_dim=64, v_head_dim=32, index_topk=8,
            index_head_dim=48, index_n_heads=12, indexer_types=["full", "full", "shared", "full", "shared", "shared"],
            rope_parameters={"rope_theta": 8000000.0, "rope_type": "default"}, **common)
    raise SystemExit("unknown arch " + arch)


def exl3_targets(model):
    """The linears stored as EXL3: every attention output projection and MLP
    down projection (the routed experts' too)"""
    out = []
    for name, mod in model.named_modules():
        if isinstance(mod, torch.nn.Linear) and (name.endswith("o_proj") or name.endswith("down_proj")):
            out.append(name)
    return out


def make(arch, outdir, tokdir, exdir=None):
    from transformers import AutoModelForCausalLM
    from safetensors.torch import save_file
    torch.manual_seed(520)
    model = AutoModelForCausalLM.from_config(tiny_config(arch)).float().eval()
    with torch.no_grad():
        for name, p in model.named_parameters():
            if name.endswith("norm.weight") or name.endswith("layernorm.weight"):
                p.copy_(1.0 + 0.1 * torch.randn_like(p))
            elif name.endswith("norm.bias"):
                p.copy_(0.1 * torch.randn_like(p))
        for name, b in model.named_buffers():
            if name.endswith("e_score_correction_bias"):
                b.copy_(0.05 * torch.randn_like(b))
    groups = {}
    if exdir:
        sys.path.insert(0, exdir + "/tests/testlib")
        import trellis as ref
        gen = np.random.default_rng(520)
        for i, name in enumerate(exl3_targets(model)):
            mod = model.get_submodule(name)
            n, k = mod.weight.shape                      # HF [out, in]
            kp, np_ = (k + 127) // 128 * 128, (n + 127) // 128 * 128
            K, cb = (4, "mcg") if i % 2 == 0 else (5, "mul1")
            trellis = ref.random_packed((kp // 16) * (np_ // 16), K, gen).reshape(kp // 16, np_ // 16, -1)
            # signs scaled so the weights are of the initialiser's size
            suh = (gen.choice([-1.0, 1.0], kp) * gen.uniform(0.15, 0.4, kp)).astype(np.float16)
            svh = (gen.choice([-1.0, 1.0], np_) * gen.uniform(0.15, 0.4, np_)).astype(np.float16)
            W = ref.dequant(trellis, torch.from_numpy(suh), torch.from_numpy(svh), K, cb)[:k, :n]
            with torch.no_grad():
                mod.weight.copy_(W.t().float())
            g = {name + ".trellis": torch.from_numpy(np.ascontiguousarray(trellis)),
                 name + ".suh": torch.from_numpy(suh), name + ".svh": torch.from_numpy(svh)}
            mult = 0xCBAC1FED if cb == "mcg" else 0x83DCD12D
            g[name + "." + cb] = torch.from_numpy(np.array([mult], dtype=np.uint32).view(np.int32))
            groups[name] = g
    model.save_pretrained(outdir, safe_serialization=True)
    if groups:
        # the EXL3 linears replace their .weight in the checkpoint
        from safetensors.torch import load_file
        path = os.path.join(outdir, "model.safetensors")
        sd = load_file(path)
        for name, g in groups.items():
            del sd[name + ".weight"]
            sd.update(g)
        save_file(sd, path)
        torch.save({n: model.get_submodule(n).weight.detach().clone() for n in groups},
                   os.path.join(outdir, "exl3_reference_weights.pt"))
    for f in ("tokenizer.json", "tokenizer_config.json", "chat_template.jinja"):
        if os.path.exists(os.path.join(tokdir, f)):
            shutil.copy(os.path.join(tokdir, f), os.path.join(outdir, f))


def load(d):
    from transformers import AutoConfig, AutoModelForCausalLM
    ex = os.path.join(d, "exl3_reference_weights.pt")
    if not os.path.exists(ex):
        return AutoModelForCausalLM.from_pretrained(d, dtype=torch.float32, attn_implementation="eager").eval()
    # an EXL3 checkpoint: transformers cannot read the groups, so it loads a
    # copy holding the decoded weights in their place (through
    # from_pretrained, which maps the checkpoint's keys as it always does)
    import tempfile
    from safetensors.torch import load_file, save_file
    sd = {k: v for k, v in load_file(os.path.join(d, "model.safetensors")).items()
          if not k.endswith((".trellis", ".suh", ".svh", ".mcg", ".mul1"))}
    for n, w in torch.load(ex).items():
        sd[n + ".weight"] = w
    tmp = tempfile.mkdtemp()
    shutil.copy(os.path.join(d, "config.json"), tmp)
    save_file(sd, os.path.join(tmp, "model.safetensors"))
    m = AutoModelForCausalLM.from_pretrained(tmp, dtype=torch.float32, attn_implementation="eager").eval()
    shutil.rmtree(tmp)
    return m


def final_logits(m, ids):
    with torch.no_grad():
        return m(input_ids=torch.tensor([ids]), use_cache=False).logits[0, -1]


def main():
    cmd = sys.argv[1]
    if cmd == "make":
        make(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5] if len(sys.argv) > 5 else None)
        return
    m = load(sys.argv[2])
    ids = [int(t) for t in sys.argv[3].split()]
    if cmd == "logits":
        for v in final_logits(m, ids).tolist():
            print("%.9g" % v)
    elif cmd == "greedy":
        out = []
        for _ in range(int(sys.argv[4])):
            t = int(torch.argmax(final_logits(m, ids)))
            out.append(t)
            ids.append(t)
        print(" ".join(map(str, out)))


if __name__ == "__main__":
    main()
