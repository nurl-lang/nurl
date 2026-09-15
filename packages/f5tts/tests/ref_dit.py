#!/usr/bin/env python
"""Reference dump of one F5-TTS DiT forward pass, layer by layer.

Runs one forward with fixed inputs and writes every intermediate as raw
little-endian f32, so the NURL port can be compared against it tensor by
tensor. Imports the model modules by path so f5_tts/model/__init__.py (which
drags in the trainer, wandb and accelerate) never runs.

Environment:
  F5TTS_SRC    the reference F5-TTS source tree (the directory holding model/)
  F5TTS_CKPT   the checkpoint to dump
  F5TTS_VOCAB  its vocabulary (default: vocab.txt beside the checkpoint)
  F5TTS_REF_TEXT / F5TTS_GEN_TEXT  the two fixed strings (defaults below)

The default strings are deliberately full of letters outside jieba's character
class, because that is where the text front-end does something surprising and
where a port is most likely to disagree.
"""
import sys, types, os, json, warnings
warnings.filterwarnings("ignore")
import numpy as np
import torch


def _env(name, what):
    v = os.environ.get(name, "")
    if not v:
        sys.exit("%s is not set: %s" % (name, what))
    return v


# Nothing here is hardcoded to one machine or one checkpoint. Point these at
# whatever F5-TTS tree and weights you are comparing against.
SRC = _env("F5TTS_SRC", "the reference F5-TTS source tree, the directory holding model/")
CKPT = _env("F5TTS_CKPT", "the checkpoint to dump, a .safetensors file")
VOCAB = os.environ.get("F5TTS_VOCAB", "") or os.path.join(os.path.dirname(CKPT), "vocab.txt")
pkg = types.ModuleType("f5_tts"); pkg.__path__ = [SRC]; sys.modules["f5_tts"] = pkg
mp = types.ModuleType("f5_tts.model"); mp.__path__ = [SRC + "/model"]; sys.modules["f5_tts.model"] = mp
bp = types.ModuleType("f5_tts.model.backbones"); bp.__path__ = [SRC + "/model/backbones"]
sys.modules["f5_tts.model.backbones"] = bp

from f5_tts.model.backbones.dit import DiT
from f5_tts.model.utils import get_tokenizer, convert_char_to_pinyin

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/f5ref"
os.makedirs(OUT, exist_ok=True)

torch.manual_seed(0)
vocab_char_map, vocab_size = get_tokenizer(VOCAB, "custom")
print("vocab", vocab_size)

# dialogue_api.py's model_cfg, plus the DiT defaults for everything it omits:
# text_mask_padding=True, pe_attn_head=None, qk_norm=None, attn_mask_enabled=False.
model = DiT(dim=1024, depth=22, heads=16, ff_mult=2, text_dim=512, conv_layers=4,
            text_num_embeds=vocab_size, mel_dim=100)
model.eval()

from safetensors.torch import load_file
ck = load_file(CKPT, device="cpu")
sd = {k.replace("ema_model.transformer.", ""): v for k, v in ck.items()
      if k.startswith("ema_model.transformer.")}
missing, unexpected = model.load_state_dict(sd, strict=False)
print("missing", missing)
print("unexpected", unexpected)

# fixed, reproducible inputs
ref_text = os.environ.get("F5TTS_REF_TEXT", "Yöllä hiljaisessa mökissä kuuntelin tuulta. ")
gen_text = os.environ.get("F5TTS_GEN_TEXT", "Hei, tämä on koe.")
chars = convert_char_to_pinyin([ref_text + gen_text])
text = torch.tensor([[vocab_char_map.get(c, 0) for c in chars[0]]], dtype=torch.long)
nt = text.shape[1]
n = 400                      # mel frames in this probe
g = torch.Generator().manual_seed(1234)
x = torch.randn(1, n, 100, generator=g)
cond = torch.randn(1, n, 100, generator=g) * 0.5
t = torch.tensor([0.3])

def w(name, arr):
    a = np.ascontiguousarray(np.asarray(arr, dtype=np.float32))
    a.tofile(os.path.join(OUT, name + ".f32"))
    print(f"  {name:28s} {tuple(a.shape)}")

w("x", x.numpy()); w("cond", cond.numpy()); w("t", t.numpy())
np.asarray(text.numpy(), dtype=np.int32).tofile(os.path.join(OUT, "text_ids.i32"))
print("  text_ids", text.shape, "chars:", repr("".join(chars[0]))[:90])

taps = {}
def tap(name):
    def hook(mod, inp, out):
        o = out[0] if isinstance(out, tuple) else out
        taps[name] = o.detach()
    return hook

model.time_embed.register_forward_hook(tap("time_embed"))
model.text_embed.register_forward_hook(tap("text_embed"))
model.input_embed.register_forward_hook(tap("input_embed"))
model.text_embed.text_blocks[0].register_forward_hook(tap("text_block0"))
for i in (0, 1, 21):
    model.transformer_blocks[i].register_forward_hook(tap(f"block{i}"))
model.norm_out.register_forward_hook(tap("norm_out"))

with torch.inference_mode():
    out = model(x=x, cond=cond, text=text, time=t, mask=None,
                drop_audio_cond=False, drop_text=False, cache=False)

for k, v in taps.items():
    w(k, v.numpy())
w("out", out.numpy())

meta = dict(n=n, nt=nt, dim=1024, depth=22, heads=16, ff_mult=2, text_dim=512,
            conv_layers=4, mel_dim=100, vocab_size=vocab_size,
            ref_text=ref_text, gen_text=gen_text, time=float(t[0]))
json.dump(meta, open(os.path.join(OUT, "meta.json"), "w"), ensure_ascii=False, indent=1)
print("dumped to", OUT)
