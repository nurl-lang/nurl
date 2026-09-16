#!/usr/bin/env python
"""Reference end-to-end generation: reference wav + text in, mel and waveform out.

Writes the noise it used, so the NURL port can integrate the same trajectory
and be compared frame by frame rather than by ear.

Environment:
  F5TTS_SRC      the reference F5-TTS source tree (the directory holding model/)
  F5TTS_CKPT     the checkpoint to generate with
  F5TTS_VOCAB    its vocabulary (default: vocab.txt beside the checkpoint)
  F5TTS_VOICE    a voice directory: config.json (with ref_text) + reference.wav
  F5TTS_VOCODER  the vocos snapshot directory: config.yaml + pytorch_model.bin
"""
import sys, types, os, json, warnings
warnings.filterwarnings("ignore")
import numpy as np
import torch
import soundfile as sf


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
import torchaudio

VOICE = _env("F5TTS_VOICE", "a voice directory holding config.json and reference.wav")
OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/f5gen"
GEN_TEXT = sys.argv[2] if len(sys.argv) > 2 else os.environ.get("F5TTS_GEN_TEXT", "Hei, tämä on koe.")
NFE = int(sys.argv[3]) if len(sys.argv) > 3 else 32
os.makedirs(OUT, exist_ok=True)

ref_text = json.load(open(VOICE + "/config.json"))["ref_text"]
if not ref_text.endswith(". ") and not ref_text.endswith("。"):
    ref_text = ref_text + " " if ref_text.endswith(".") else ref_text + ". "

vocab_char_map, vocab_size = get_tokenizer(VOCAB, "custom")
model = DiT(dim=1024, depth=22, heads=16, ff_mult=2, text_dim=512, conv_layers=4,
            text_num_embeds=vocab_size, mel_dim=100)
from safetensors.torch import load_file
ck = load_file(CKPT, device="cpu")
sd = {k.replace("ema_model.transformer.", ""): v for k, v in ck.items()
      if k.startswith("ema_model.transformer.")}
model.load_state_dict(sd, strict=True)
model.eval()

# the reference recording, exactly as infer_batch_process prepares it
data, sr = sf.read(VOICE + "/reference.wav", dtype="float32", always_2d=True)
audio = torch.from_numpy(data.T)
if audio.shape[0] > 1:
    audio = audio.mean(0, keepdim=True)
target_rms, hop_length, target_sample_rate = 0.1, 256, 24000
rms = torch.sqrt(torch.mean(torch.square(audio)))
if rms < target_rms:
    audio = audio * target_rms / rms
if sr != target_sample_rate:
    audio = torchaudio.transforms.Resample(sr, target_sample_rate)(audio)

mel_stft = torchaudio.transforms.MelSpectrogram(
    sample_rate=24000, n_fft=1024, win_length=1024, hop_length=256,
    n_mels=100, power=1, center=True, normalized=False, norm=None)
cond = mel_stft(audio).clamp(min=1e-5).log().permute(0, 2, 1)   # (1, T, 100)

gen_text = GEN_TEXT
if len(ref_text[-1].encode("utf-8")) == 1:
    ref_text_p = ref_text + " "
else:
    ref_text_p = ref_text
local_speed = 1.0
if len(gen_text.encode("utf-8")) < 10:
    local_speed = 0.3
chars = convert_char_to_pinyin([ref_text_p + gen_text])
text = torch.tensor([[vocab_char_map.get(c, 0) for c in chars[0]]], dtype=torch.long)

ref_audio_len = audio.shape[-1] // hop_length
ref_text_len = len(ref_text_p.encode("utf-8"))
gen_text_len = len(gen_text.encode("utf-8"))
duration = ref_audio_len + int(ref_audio_len / ref_text_len * gen_text_len / local_speed)

cond_seq_len = cond.shape[1]
lens = torch.tensor([cond_seq_len])
duration = int(max(max(int((text != -1).sum()), cond_seq_len) + 1, duration))
duration = min(duration, 4096)
print("ref_audio_len", ref_audio_len, "cond frames", cond_seq_len, "duration", duration,
      "text", text.shape[1], "local_speed", local_speed)

condp = torch.nn.functional.pad(cond, (0, 0, 0, duration - cond_seq_len), value=0.0)
cond_mask = torch.arange(duration)[None, :] < lens[:, None]
step_cond = torch.where(cond_mask.unsqueeze(-1), condp, torch.zeros_like(condp))

g = torch.Generator().manual_seed(4242)
y0 = torch.randn(1, duration, 100, generator=g)

cfg_strength, sway = 2.0, -1.0
t = torch.linspace(0, 1, NFE + 1)
t = t + sway * (torch.cos(torch.pi / 2 * t) - 1 + t)

y = y0.clone()
with torch.inference_mode():
    for i in range(NFE):
        dt = (t[i + 1] - t[i]).item()
        pred_cfg = model(x=y, cond=step_cond, text=text, time=t[i].reshape(1),
                         mask=None, cfg_infer=True, cache=True)
        pred, null_pred = torch.chunk(pred_cfg, 2, dim=0)
        v = pred + (pred - null_pred) * cfg_strength
        y = y + dt * v
model.clear_cache()

out = torch.where(cond_mask.unsqueeze(-1), condp, y)
gen_mel = out[:, ref_audio_len:, :]

def w(name, arr):
    np.ascontiguousarray(np.asarray(arr, dtype=np.float32)).tofile(os.path.join(OUT, name + ".f32"))

w("noise", y0.numpy()); w("cond_mel", cond.numpy()); w("y_final", y.numpy())
w("gen_mel", gen_mel.numpy())
np.asarray(text.numpy(), dtype=np.int32).tofile(os.path.join(OUT, "text_ids.i32"))

# the vocoder
from vocos import Vocos
VOCOS = _env("F5TTS_VOCODER", "the vocos snapshot directory: config.yaml + pytorch_model.bin")
voc = Vocos.from_hparams(VOCOS + "/config.yaml")
state = torch.load(VOCOS + "/pytorch_model.bin", map_location="cpu", weights_only=True)
voc.load_state_dict(state)
voc.eval()
with torch.inference_mode():
    wave = voc.decode(gen_mel.permute(0, 2, 1))
if rms < target_rms:
    wave = wave * rms / target_rms
w("wave", wave.numpy())
sf.write(os.path.join(OUT, "ref.wav"), wave[0].numpy(), 24000)

json.dump(dict(duration=duration, ref_audio_len=ref_audio_len, cond_frames=cond_seq_len,
               nfe=NFE, cfg=cfg_strength, sway=sway, gen_text=gen_text,
               ref_text=ref_text_p, rms=float(rms), local_speed=local_speed,
               n_text=int(text.shape[1]), chars="".join(chars[0])),
          open(os.path.join(OUT, "meta.json"), "w"), ensure_ascii=False, indent=1)
print("wrote", OUT, "wave", wave.shape)
