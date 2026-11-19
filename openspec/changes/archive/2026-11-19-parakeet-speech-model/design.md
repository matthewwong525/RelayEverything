# Design

## Context

See proposal.md, Why. Today `SpeechModel` (`mobile/lib/voice/model.dart`) downloads one file, `ggml-base.en-q5_1.bin`, with `Range` resume through a `.part` file and one SHA-256. `WhisperTranscriber` (`mobile/lib/voice/transcriber.dart`) loads it through `whisper_cpp_flutter_plus`, which runs each job in its own isolate and can cancel it. The base `Transcriber` owns the queue and time limits, and stays as it is.

Facts checked on 2026-11-18:

- The sherpa-onnx `asr-models` release on GitHub has `sherpa-onnx-nemo-parakeet_tdt_transducer_110m-en-36000-int8.tar.bz2`: 108,035,095 bytes, SHA-256 `f628312e9fdf8686374cb01a69425c41732529d540860311f16f37cbc32cfe9b` (GitHub's asset digest). The address answers a `Range` request with `206`.
- Inside, under `sherpa-onnx-nemo-parakeet_tdt_transducer_110m-en-36000-int8/`:

  | File | Bytes | SHA-256 |
  |---|---|---|
  | `encoder.int8.onnx` | 131,113,202 | `0f35509ddeb9b39002fb077d979a9fe74f06eb0bc4dd5c34f512f82e5111d657` |
  | `decoder.int8.onnx` | 3,955,863 | `f7c331c5504c2e593c76ed22b728e3f554af6c4a383dde862e719ced08b1da19` |
  | `joiner.int8.onnx` | 1,411,403 | `bf7dff69e9f2cdbe9943d70da358f38b361c115ba0105bae7e908e0d6ec782f6` |
  | `tokens.txt` | 9,953 | `450e56bd2f036fe5b6aa821865838cc5aa9d8b0106134ce9a9ba0664abe6cd10` |

  Total 136,490,421 bytes (130 MB). The archive also holds `test_wavs/`, which the phone skips.
- sherpa-onnx 2.0.1 (Python) on this Linux machine, `model_type="nemo_transducer"`, 2 threads: a 7.4 s clip loads in 1.8 s and decodes in 0.23 s, with punctuation and capitals.
- `sherpa_onnx` 2.0.1 on pub.dev has iOS, Android and macOS parts. On iOS it ships `SherpaOnnxC.xcframework`, a dynamic framework of 26 MB for `ios-arm64`, and finds it with `DynamicLibrary.process()`.
- The model is NVIDIA's, under CC-BY-4.0: the website names it and links its card.

## Goals / Non-Goals

**Goals:** one speech engine (sherpa-onnx) that every later model uses; a model described by data, so a new model is a new list item.

**Non-Goals:** a model picker; a side-by-side test against whisper; voice notes on the Mac (`main_mac.dart` still reaches no speech code).

## Decisions

1. **A list of models: `speechModels`, with `SpeechModelInfo` items.** Each item has an `id` (`parakeet-small`), a display name, the archive address, its SHA-256 and size, the folder inside the archive, the files to keep with each size and SHA-256, and how sherpa-onnx loads it (a `nemo_transducer` with encoder, decoder, joiner and tokens). `currentSpeechModel` is the one item for now. `SpeechModel` takes an item, not a URL and a checksum. Alternative: keep constants and change their values: the next model would need this change again.
2. **Get the archive, then unpack it on the phone.** The download keeps today's shape: `Range` resume into `<id>.tar.bz2.part`, then the archive's SHA-256 in an isolate. Then, in an isolate, the `archive` package streams the bzip2 into a `.tar` file and reads only the four named entries into `speech-model/<id>.part/`. Each file's SHA-256 is checked, the archive and the `.tar` are deleted, and the folder is renamed to `speech-model/<id>/`. The rename is the only *ready* mark, so a phone that stops halfway never uses half a model. Alternative: download each file from a mirror: no trusted mirror holds them, and a copy on our own GitHub release is a second thing to keep and a public upload.
3. **Old model clean-up at `load()`.** Any file or folder in `speech-model/` that is not the current model's folder, its `.part` folder or its archive parts is deleted, such as `ggml-base.en-q5_1.bin` and its `.part`. This also serves a later model change. It runs before `ready` is read, so the old model never counts as ready.
4. **`SherpaTranscriber` in a long-lived worker isolate.** sherpa-onnx's decode is a blocking FFI call, and an `OfflineRecognizer` can not cross isolates. So a worker isolate loads the recognizer once (CPU, 2 threads), reads the WAV, decodes it, and sends back the text. The transcriber keeps today's contract: one job at a time, `cleanWords` on the result, and `dropsEngine` after a failed run. sherpa-onnx has no cancel, so at the time limit `WordsJob.onCancel` kills the worker isolate; the next job starts a new one and loads again. A test gives a fake engine, as today. Alternative: `Isolate.run` for each note: each note then pays the load, about 1–2 s.
5. **The iPhone build check looks for sherpa-onnx's functions.** `SPEECH_PARTS` becomes `_SherpaOnnxCreateOfflineRecognizer`, `_SherpaOnnxCreateOfflineStream`, `_SherpaOnnxAcceptWaveformOffline`, `_SherpaOnnxDecodeOfflineStream` and `_SherpaOnnxGetOfflineStreamResultAsJson`: the names `sherpa_onnx` 2.0.1 looks up for one offline decode. `check_speech_parts` already reads `Frameworks/*.framework`. The `-Wl,-u,_wf_*` flags go from `OTHER_LDFLAGS`. `STRIP_STYLE = non-global` stays: it is cheap and keeps a later static library safe.
6. **The CPU on every phone.** `whisperConfig` and its Metal note go. sherpa-onnx's CPU provider works with the app not on screen and on the simulator, so the watch and locked-phone cases keep working with no switch.
7. **The size the app says.** The ask says the download, 103 MB; Settings says what the phone keeps, 130 MB. `Relay.modelBytes` splits into `modelDownloadBytes` and `modelBytes`.

## Risks / Trade-offs

- [Unpacking bzip2 in Dart is slow on a phone] → it runs in an isolate, after the download, with the same *Getting it…* progress (the last 10% is the unpack). If a real phone takes over a minute, a later change can host a `.tar` or plain files.
- [Disk space: up to about 380 MB at the peak of the unpack] → the archive is deleted as soon as the `.tar` is written, and the `.tar` after the four files; a write that fails for space is the `offline` problem, and *Try again* starts the unpack again.
- [The app grows] → about 26 MB for iOS and a similar `.so` for each Android ABI, while whisper's part goes. Report the `.ipa` size from the first build.
- [GitHub moves the asset] → the checksum refuses any other file, and the ask shows *Try again*; a later change can move the address.
- [A different word from what whisper gave on the same recording] → the words of saved notes do not change; only new writes use Parakeet.

## Migration Plan

The first open after the update deletes the old model (Decision 3). Notes keep their words. A note whose words failed writes them with Parakeet once the new model is in. Rollback: an older build has no old model and asks again for its 57 MB file.
