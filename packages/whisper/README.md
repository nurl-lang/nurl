# whisper

Speech recognition in pure NURL. Real audio in, real text out — running
from the safetensors checkpoint Hugging Face ships, on the GPU or the CPU.

```
nurlpkg install whisper
```

```
$ whisper transcribe ./whisper-tiny jfk.wav
 And so my fellow Americans ask not what your country can do for you ask what you can do for your country.
```

Word for word what HF transformers produces from the same model — and the
CPU backend produces the same text as CUDA.

Bigger models just work, because nothing is hardcoded to a shape:

```
$ whisper transcribe ./distil-large-v3 jfk.wav
 And so, my fellow Americans, ask not what your country can do for you. Ask what you can do for your country.
```

(128 mel bands instead of 80, 1280-wide, 32 encoder layers and 2 decoder
layers — every one of those read out of the model's own `config.json`.)

A model directory is what Hugging Face ships: `config.json`,
`model.safetensors`, `tokenizer.json`, side by side.

## Built package by package

Nothing here is a black box, and every stage is verified against an
independent implementation rather than against my own understanding of it:

| stage | package | verified against |
|---|---|---|
| WAV → 16 kHz mono | `audio` | scipy's `resample_poly` (r = 0.99992); a tone above the new Nyquist is killed by 82 dB |
| → log-mel | `audio` | HF's `WhisperFeatureExtractor` — max \|Δ\| = 1.8e-5, r = 1.00000000 |
| n_fft = 400 (not a power of two) | `stdlib/std/fft.nu` | numpy's `np.fft` — Bluestein, 1.9e-14 |
| weights | `safetensor` | 167 tensors bit-exact; a whole forward pass at r = 1.00000000 |
| vocabulary | `tokenizer` | HF's own tokenizer, 20/20 strings |
| encoder + decoder | this package | HF's `WhisperModel.encoder` (r = 1.00000000) and its transcription, word for word — on whisper-tiny **and** distil-large-v3 |

## Whisper is not the llama shape

Every kernel is a place it differs:

* **LayerNorm**, not RMSNorm — it subtracts the mean, and it has a bias.
* **GELU with the error function**, not the tanh approximation. Gemma
  wants the other one; they are different functions.
* **conv1d**, twice (stride 1 then 2) — that is what turns 3000
  spectrogram frames into 1500 encoder positions.
* **Non-causal attention.** Every attention in this ecosystem before this
  masked the future. A speech encoder hears the whole 30 seconds at once.
* **Cross-attention**: the decoder's queries, the *encoder's* keys and
  values — computed **once per clip**, not once per generated token.
* **`k_proj` has no bias**, alone among the projections.

## `--vad`: the model never sees the silence

```
$ whisper transcribe distil-large-v3 meeting.wav
 Thank you. Thank you. And so, my fellow Americans, ask not what your country
 can do for you. Ask what you can do for your country. Thank you. Thank you.
 Thank you. […]                                                       13.3 s

$ whisper transcribe distil-large-v3 meeting.wav --vad
 And so, my fellow Americans, ask not what your country can do for you. Ask
 what you can do for your country.                                     2.2 s
```

Two things are wrong with the first one, and only one of them is the clock.

A recording is mostly not speech, and whisper costs exactly the same over a
silent 30 seconds as over a spoken one — so on a 292-second recording that is
8 % speech, essentially the whole bill is silence. That is the 13.3 s.

But whisper handed silence does not stay quiet. It was trained on audio that
had somebody talking in it, so asked what was said when nothing was, it
answers anyway: `[BLANK_AUDIO]`, `[silence]`, `Thank you.` The `Thank you.`
above is not a bug in this implementation — it is what the checkpoint says.

`--vad` finds the speech first (packages/audio) and hands the model only that,
with a half-second of the real room kept between segments so two utterances do
not run together. Where there is speech the words are unchanged, byte for
byte. Where there is none, there is now nothing to hallucinate about.

It also rescues speech the windowing would otherwise eat. The encoder sees
exactly 30 seconds, so an utterance that straddles a window boundary is cut in
half — and distil, handed the back half of a sentence, returns
` And so my fellow Americans country.` VAD moves the boundary off the speech.

## `--timestamps`: the model's own clock, in the recording's timeline

```
$ whisper transcribe distil-large-v3 meeting.wav --vad --timestamps
[00:59.85 --> 01:07.49] And so, my fellow Americans, ask not what your country can do for you.
[01:08.21 --> 01:10.39] Ask what you can do for your country.
[03:10.84 --> 03:18.48] And so, my fellow Americans, ask not what your country can do for you.
[03:19.20 --> 03:21.38] Ask what you can do for your country.
```

The timestamps are whisper's own: leave `<|notimestamps|>` out of the prompt
and the model interleaves timestamp tokens (`<|0.00|>` … `<|30.00|>`, one per
20 ms) with the words — it was trained to. But greedy decoding alone almost
never emits one, and the reason is worth stating: no *single* 20 ms bin ever
outscores "the". A spoken boundary spreads its probability over dozens of
bins, so the bins win **collectively or not at all** — which is exactly what
openai's constrained-decoding rules encode (the summed timestamp probability
is compared against the best text token; timestamps open every window, never
run backwards, and come in close-open pairs). Those rules are implemented
here, on the host, over the same logits either backend produced.

Under `--vad` there is a second translation. The model transcribed *condensed*
audio — second 0.2 of what it heard may be second 20 of the file — so every
timestamp is walked back through the condensation map (`VadRun`, from
packages/audio) before it is printed. A subtitle at `00:00.20` for words
spoken at `00:20` would be worse than no subtitle at all; the four lines
above land on the recording's real clock.

## `whisper serve`: the model held open

```
$ whisper serve distil-large-v3 --addr 0.0.0.0:6543
whisper serving on http://0.0.0.0:6543 (POST /inference, GET /health)

$ curl -F file=@jfk.wav http://localhost:6543/inference
{"text":"And so, my fellow Americans, ask not what your country can do for you. Ask what you can do for your country."}
```

The point of a server is *when the model loads*. The CLI pays the whole
bill per invocation — read 1.5 GB of safetensors, convert f16 to f32 on
the device, compile the kernels — and only then hears the audio. The
server pays it once, before the port opens: the same 11-second clip that
costs the CLI 1.15 s costs a warm request **0.33 s**.

The HTTP surface is whisper.cpp's server, so its clients work unchanged:
`POST /inference` with a multipart `file` field, optional `language` and
`response_format` (`json`|`text`) fields. Two additions, both because
there was no reason not to: a **raw WAV body** works (`curl --data-binary`
is not a browser form and does not have to pretend to be one), and
per-request `vad=true` / `timestamps=true` fields override the server
flags — one server serves both a subtitle pipeline and a bare-text one.

## The control tokens are looked up, not hardcoded

A whisper prompt is four tokens — `<|startoftranscript|>`, the language,
`<|transcribe|>`, `<|notimestamps|>` — and they are the model being *told
what task it is doing*. Their ids move between whisper versions (v3 added
a language, and every id after it shifted), so they are looked up in the
vocabulary the checkpoint ships with.

## License

MIT OR Apache-2.0
