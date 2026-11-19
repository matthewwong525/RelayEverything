import 'dart:math';
import 'dart:typed_data';

/// A recording's sound waves: [bars] levels from 0 to 1, the loudest part at 1, read from a 16-bit PCM WAV's samples.
/// Each level is the RMS of its part of the samples. A file that is not a 16-bit PCM WAV, such as a `.m4a`, gives an
/// empty list; a silent one gives [bars] zeros.
List<double> levelsOfWav(Uint8List bytes, {int bars = 48}) {
  final samples = _samplesOf(bytes);
  if (samples == null || bars <= 0) return const [];
  final count = samples.length;
  final rms = List<double>.filled(bars, 0);
  for (var bar = 0; bar < bars; bar++) {
    final start = bar * count ~/ bars, end = (bar + 1) * count ~/ bars;
    if (end <= start) continue;
    var sum = 0.0;
    for (var i = start; i < end; i++) {
      final sample = samples[i];
      sum += sample * sample;
    }
    rms[bar] = sqrt(sum / (end - start));
  }
  final loudest = rms.reduce(max);
  if (loudest == 0) return rms;
  return [for (final level in rms) level / loudest];
}

/// A 16-bit PCM WAV's sound as the speech engine reads it: mono samples from -1 to 1, and their sample rate. Null when
/// [bytes] are not a 16-bit PCM WAV. A recording with more than one channel is mixed down to one.
({Float32List samples, int sampleRate})? soundOfWav(Uint8List bytes) {
  final wav = _wavOf(bytes);
  if (wav == null) return null;
  final (:samples, :sampleRate, :channels) = wav;
  final frames = samples.length ~/ channels;
  final mono = Float32List(frames);
  for (var frame = 0; frame < frames; frame++) {
    var sum = 0;
    for (var channel = 0; channel < channels; channel++) {
      sum += samples[frame * channels + channel];
    }
    mono[frame] = sum / channels / 32768;
  }
  return (samples: mono, sampleRate: sampleRate);
}

/// The 16-bit samples after a WAV's `data` chunk header, or null when [bytes] are not a 16-bit PCM WAV.
Int16List? _samplesOf(Uint8List bytes) => _wavOf(bytes)?.samples;

/// A 16-bit PCM WAV's samples, as they are in the file, with its sample rate and number of channels; null when [bytes]
/// are not one. A `data` size the recorder did not write, such as 0 or more than the file holds, reads to the end of
/// the file.
({Int16List samples, int sampleRate, int channels})? _wavOf(Uint8List bytes) {
  if (bytes.length < 12) return null;
  final view = ByteData.sublistView(bytes);
  String tag(int at) => String.fromCharCodes(bytes, at, at + 4);
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return null;
  var pcm16 = false;
  var channels = 1, sampleRate = 16000;
  var at = 12;
  while (at + 8 <= bytes.length) {
    final name = tag(at);
    final size = view.getUint32(at + 4, Endian.little);
    final body = at + 8;
    if (name == 'fmt ') {
      if (body + 16 > bytes.length) return null;
      final format = view.getUint16(body, Endian.little);
      final bits = view.getUint16(body + 14, Endian.little);
      // 1 is PCM; 0xFFFE, the extensible format, also holds PCM in the recorders the phone uses.
      pcm16 = (format == 1 || format == 0xFFFE) && bits == 16;
      channels = view.getUint16(body + 2, Endian.little).clamp(1, 16);
      sampleRate = view.getUint32(body + 4, Endian.little);
    } else if (name == 'data') {
      if (!pcm16) return null;
      final left = bytes.length - body;
      final length = (size == 0 || size > left ? left : size) & ~1;
      final samples = Int16List(length ~/ 2);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = view.getInt16(body + i * 2, Endian.little);
      }
      return (samples: samples, sampleRate: sampleRate, channels: channels);
    }
    // Chunks are padded to an even size.
    at = body + size + (size & 1);
  }
  return null;
}
