# whisper

Speech recognition in pure NURL: real audio in, real text out. Runs
OpenAI's whisper models from the checkpoints they are actually
distributed in — Hugging Face safetensors or whisper.cpp's `ggml-*.bin`
— on the GPU (CUDA) or the CPU (OpenMP), with identical output on both.

```
nurlpkg install whisper
```

```
$ whisper transcribe ggml-large-v3.bin meeting.wav --vad --timestamps
[00:59.85 --> 01:07.49] And so, my fellow Americans, ask not what your country can do for you.
[01:08.21 --> 01:10.39] Ask what you can do for your country.
```

Output is verified word-for-word against Hugging Face `transformers` on
the same model. Nothing is hardcoded to a model size: mel bands, widths,
layer and head counts are read from the checkpoint itself, so everything
from `tiny` to `large-v3` works with the same binary.

## Getting a model

Two formats are supported. Both download sources below have been stable
for years and are the canonical homes of these files:

**whisper.cpp ggml — one self-contained file** (hyperparameters,
vocabulary and weights together; the easiest to move around):

> https://huggingface.co/ggerganov/whisper.cpp

```
curl -LO https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin
whisper transcribe ggml-large-v3.bin clip.wav
```

Any of `ggml-tiny.bin` … `ggml-large-v3.bin` / `ggml-large-v3-turbo.bin`
works. The quantised variants (`q5_0`, `q8_0`) are refused with a clear
message for now — use the f16 files.

**Hugging Face checkpoint — a directory** with `config.json`,
`model.safetensors` and `tokenizer.json` side by side:

> https://huggingface.co/openai/whisper-large-v3
> https://huggingface.co/openai/whisper-tiny — likewise `-base`, `-small`, `-medium`
> https://huggingface.co/distil-whisper/distil-large-v3 — English-only, about twice as fast

```
mkdir large-v3 && cd large-v3
for f in config.json model.safetensors tokenizer.json; do
  curl -LO https://huggingface.co/openai/whisper-large-v3/resolve/main/$f
done
cd .. && whisper transcribe large-v3 clip.wav
```

The same weights in either container produce the same transcript.

## Transcribing

```
whisper transcribe <model> <audio.wav> [options]
```

| option | effect |
|---|---|
| `--lang CODE` | language, lowercase two-letter (`en`, `fi`, `sv`, …; default `en`). Uppercase input is normalized; an unknown code reports itself. |
| `--vad` | skip non-speech before the model sees it (adaptive-floor energy detector). Faster on sparse audio, and rescues speech that straddles a 30 s window boundary. |
| `--timestamps` | emit `[a --> b] text` segments using whisper's own timestamp tokens, under OpenAI's constrained-decoding rules. With `--vad`, times are mapped back to the recording's real clock. |
| `--nospeech P` | drop a window when the model itself is ≥ P sure it holds no speech (default 0.6; 1 disables). This is what keeps "Thank you." out of the silences. |
| `--max N` | stop after N tokens per window (default 200) |

WAV input at any sample rate and bit depth is resampled to 16 kHz mono
internally (windowed-sinc, not linear interpolation).

## Serving

```
$ whisper serve ggml-large-v3.bin --addr 0.0.0.0:6543 --tls --lang fi
whisper: self-signed TLS minted — the browser will warn once; accept it and the microphone works
whisper serving on https://0.0.0.0:6543 (test page at /, POST /inference, GET /health, WS: stream audio)
```

The model loads once, before the port opens; a request pays only for its
own audio (distil-large-v3: 0.33 s per warm request, where a cold CLI
invocation of the same clip costs 1.15 s).

**`GET /`** is a built-in test page: drop an audio file on it, or press
*Start microphone* and watch utterances appear as you pause. The page is
staged by `nurlpkg install` into `share/whisper/` next to the binary.

**`POST /inference`** is whisper.cpp's server surface, so its clients
work unchanged: multipart `file` field, optional `language` and
`response_format` (`json`|`text`) fields. A raw WAV body also works, and
per-request `vad=true` / `timestamps=true` fields override the server
flags.

**WebSocket, same port** — live audio in, utterances out:

```
→ {"format":"pcm16","lang":"fi"}                    (optional config first)
← {"status":"ok","format":"pcm16","vad":"adaptive-floor"}
→ <binary frames: raw PCM16 @ 16 kHz>
← {"text":" And so my fellow Americans.","t0":0.09,"t1":2.33}
← {"error":"…"}                                     (failures are named, never silent)
```

Utterances are cut by a streaming VAD whose noise floor is the 10th
percentile of the trailing minute, recomputed every second, and each is
gated by the model's own no-speech probability — a phone microphone's
auto-gain cannot talk it into transcribing an empty room. `t0`/`t1` are
seconds on the stream's clock. A run that reaches 28 s closes forcibly:
whisper's window is 30 s, and a lecture has no obligation to pause.

**TLS**: `--tls` mints a self-signed ECDSA-P256 certificate on the fly
(pure NURL) — browsers require a secure context before they allow
microphone capture, even on a LAN. `--cert FILE --key FILE` take real
PEMs; `wss://` works transparently.

**Access control**: by default the server is open, which is right for a
loopback bind. Give it a token — `--token TOKEN` or the `WHISPER_TOKEN`
environment variable (prefer the env var on a shared machine, where a
flag shows up in `ps`) — and every request must present it as
`Authorization: Bearer TOKEN` or `?token=TOKEN` in the query. `/health`
and the test page stay open (the page has a field to paste the token
into, remembered per browser); `/inference` and the WebSocket require it.
Binding to a non-loopback address with no token prints a warning, because
it should be a choice, not an accident.

**`GET /health`** reports the model shape and request count as JSON.

## How it is verified

Every stage is checked against an independent implementation, not against
this package's own understanding of itself:

| stage | verified against |
|---|---|
| resample → 16 kHz | scipy `resample_poly` (r = 0.99992); aliasing killed by 82 dB |
| log-mel spectrogram | HF `WhisperFeatureExtractor` — max \|Δ\| = 1.8e-5 |
| FFT (n_fft = 400) | `numpy.fft`, exact length via mixed radix |
| weights | bit-exact reads; a full forward pass at r = 1.00000000 |
| tokenizer | HF's own tokenizer, token for token |
| encoder | HF `WhisperModel.encoder`, r = 1.00000000 |
| end to end | HF `transformers` transcription, word for word — on tiny **and** distil-large-v3, CUDA **and** CPU |
| ggml container | same transcript as the safetensors checkpoint; timestamped output agrees with whisper.cpp's own CLI |

## Performance and memory

Measured on an RTX 4090; the CPU backend runs the same kernels through
OpenMP.

| | |
|---|---|
| 11 s of speech, whisper-tiny | ~0.5 s |
| 11 s of speech, distil-large-v3 | ~1.1 s (warm server: 0.33 s) |
| 292 s recording, 8 % speech, distil + `--vad` | ~1.3 s |
| large-v3 server VRAM | 4.9 GB (f16 weights stay f16 on the device) |

An f16 checkpoint's matrix weights are never widened to f32 in device
memory — the kernels widen at the point of use, exactly, so transcripts
are unchanged and the memory halves. This is what fits full large-v3 on
an 8 GB card. (bf16 checkpoints still widen: half of their exponent range
would not survive f16.)

## Implementation notes

* Whisper differs from the decoder-only shape in almost every kernel:
  LayerNorm (with bias) rather than RMSNorm, erf-GELU rather than tanh,
  two conv1d layers in front of the encoder, non-causal encoder
  attention, per-clip cross-attention K/V, and a bias-less `k_proj`.
* The prompt's control tokens (`<|startoftranscript|>`, the language,
  `<|transcribe|>`, `<|notimestamps|>`) are looked up in the checkpoint's
  own vocabulary — their ids move between whisper versions.
* ggml containers carry no special-token text at all; the loader
  synthesizes the standard spellings at whisper.cpp's positional ids, so
  both containers run through one code path.
* Built on `packages/audio` (WAV, resample, mel, VAD), `packages/safetensor`,
  `packages/tokenizer`, `packages/gpu` (CUDA + CPU backends) and
  `packages/http` (server + WebSocket) — each its own package, each with
  its own test suite.

## License

MIT OR Apache-2.0
