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
| encoder + decoder | this package | HF's `WhisperModel.encoder` (r = 1.00000000) and its transcription, word for word |

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

## The control tokens are looked up, not hardcoded

A whisper prompt is four tokens — `<|startoftranscript|>`, the language,
`<|transcribe|>`, `<|notimestamps|>` — and they are the model being *told
what task it is doing*. Their ids move between whisper versions (v3 added
a language, and every id after it shifted), so they are looked up in the
vocabulary the checkpoint ships with.

## License

MIT OR Apache-2.0
