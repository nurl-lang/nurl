/* stdlib/audio_wasm.c — wasm32-wasi microphone-analysis FFI.
 *
 * A companion to canvas_wasm.c. Forwards a handful of audio-analysis
 * queries to a host-supplied "audio" wasm import module. The browser
 * playground wires those imports to a Web Audio `AnalyserNode` fed by
 * `getUserMedia({ audio: true })`; a native back-end (e.g. SDL2) is
 * not provided here — this module is wasm-only.
 *
 * Compile:
 *     /opt/wasi-sdk/bin/clang --target=wasm32-wasi -O2 \
 *         -c stdlib/audio_wasm.c -o stdlib/audio.wasm.o
 *
 * The audio subsystem auto-initialises when the page runs a program
 * whose wasm imports the "audio" module — the JS shim requests mic
 * permission and wires the `AnalyserNode` before calling wasm. NURL
 * programs therefore don't need an explicit `audio_start` call; the
 * first `audio_level`/`audio_bin`/... just works (returning 0 while
 * permission is still pending).
 *
 * All entry points are synchronous pollers of the analyser's latest
 * frame; there's no need for Asyncify wrapping.
 */
#include <stdint.h>

/* ── Host-provided imports (module "audio") ──────────────────────── */

/* RMS amplitude of the most recent time-domain frame, in [0.0, 1.0]. */
__attribute__((import_module("audio"), import_name("level")))
extern double _host_audio_level(void);

/* Magnitude of frequency bin `i`, in [0.0, 1.0] (linearised from dB). */
__attribute__((import_module("audio"), import_name("bin")))
extern double _host_audio_bin(int64_t i);

/* Number of frequency bins the analyser exposes (fftSize / 2). */
__attribute__((import_module("audio"), import_name("bin_count")))
extern int64_t _host_audio_bin_count(void);

/* Index of the loudest bin this frame, or -1 if no data yet. */
__attribute__((import_module("audio"), import_name("peak_bin")))
extern int64_t _host_audio_peak_bin(void);

/* Spectral centroid (brightness) in Hz, or -1 if no data yet. */
__attribute__((import_module("audio"), import_name("centroid")))
extern double _host_audio_centroid(void);

/* Centre frequency of bin `i` in Hz, assuming the host's sample rate. */
__attribute__((import_module("audio"), import_name("freq_of")))
extern double _host_audio_freq_of(int64_t i);

/* Host sample rate in Hz (e.g. 48000). */
__attribute__((import_module("audio"), import_name("sample_rate")))
extern double _host_audio_sample_rate(void);

/* 1 while the analyser has live data below `threshold_pct`% RMS,
 * 0 otherwise. Useful for gating beat-drop visuals on pauses. */
__attribute__((import_module("audio"), import_name("is_silent")))
extern int64_t _host_audio_is_silent(int64_t threshold_pct);

/* 1 once the user has granted mic permission AND at least one frame
 * of audio has been analysed; 0 otherwise. */
__attribute__((import_module("audio"), import_name("ready")))
extern int64_t _host_audio_ready(void);

/* ── Public NURL-visible API ─────────────────────────────────────── */

/* audio_level: RMS amplitude of the most recent frame, 0.0–1.0. */
double audio_level(void)                      { return _host_audio_level(); }

/* audio_bin: linear magnitude of frequency bin `i`, 0.0–1.0.
 * Returns 0 if `i` is out of range. */
double audio_bin(int64_t i)                   { return _host_audio_bin(i); }

/* audio_bin_count: total number of frequency bins available. */
int64_t audio_bin_count(void)                 { return _host_audio_bin_count(); }

/* audio_peak_bin: index of the loudest bin in the current frame. */
int64_t audio_peak_bin(void)                  { return _host_audio_peak_bin(); }

/* audio_centroid: spectral centroid in Hz (perceived brightness). */
double audio_centroid(void)                   { return _host_audio_centroid(); }

/* audio_freq_of: centre frequency of bin `i` in Hz. */
double audio_freq_of(int64_t i)               { return _host_audio_freq_of(i); }

/* audio_sample_rate: the AudioContext sample rate in Hz. */
double audio_sample_rate(void)                { return _host_audio_sample_rate(); }

/* audio_is_silent: 1 if current-frame RMS is below `threshold_pct`% of
 * full scale, 0 otherwise. */
int64_t audio_is_silent(int64_t threshold_pct){ return _host_audio_is_silent(threshold_pct); }

/* audio_ready: 1 once microphone permission has been granted and at
 * least one analyser frame is available. */
int64_t audio_ready(void)                     { return _host_audio_ready(); }
