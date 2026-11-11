import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../relay.dart' show Playback;

/// Plays one recording at a time with `just_audio`, on the phone and in the browser, and tells how far it is. A new
/// recording stops the one before; the same one, paused, plays on from where it stopped. At its end it stops, and
/// [value] goes back to null. [Playback.length] is the length the player reads from the recording. A test's player
/// overrides [play], [pause] and [seek], and never makes an `AudioPlayer`.
class SoundPlayer extends ValueNotifier<Playback?> {
  SoundPlayer() : super(null);

  AudioPlayer? _player;
  final _listens = <StreamSubscription<Object?>>[];

  AudioPlayer get _open => _player ??= _start();

  AudioPlayer _start() {
    final player = AudioPlayer();
    _listens
      ..add(player.positionStream.listen((at) => _show(at: at)))
      ..add(player.durationStream.listen((length) => _show(length: length)))
      ..add(player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) return unawaited(_ended());
        _show(playing: state.playing);
      }, onError: (_) {}));
    return player;
  }

  void _show({Duration? at, bool? playing, Duration? length}) {
    final now = value;
    if (now == null) return;
    value = Playback(recording: now.recording, at: at ?? now.at, playing: playing ?? now.playing,
      length: length ?? now.length);
  }

  /// The end: the player goes back to the start, and no recording shows as playing.
  Future<void> _ended() async {
    value = null;
    await _player?.pause();
    await _player?.seek(Duration.zero);
  }

  /// Plays [recording] from [source], a file on this phone or an address. The recording that is paused plays on.
  Future<void> play(String recording, Uri source) async {
    final player = _open;
    if (value?.recording != recording) {
      value = null;
      await player.stop();
      final length = await player.setUrl(source.toString());
      value = Playback(recording: recording, at: Duration.zero, playing: true, length: length ?? player.duration);
    } else {
      _show(playing: true);
    }
    unawaited(player.play());
  }

  /// Pauses where it is.
  Future<void> pause() async {
    _show(playing: false);
    await _player?.pause();
  }

  /// Moves the recording that plays or is paused to [at]. With none, it does nothing.
  Future<void> seek(Duration at) async {
    if (value == null) return;
    _show(at: at);
    await _player?.seek(at);
  }

  @override
  void dispose() {
    for (final listen in _listens) {
      unawaited(listen.cancel());
    }
    unawaited(_player?.dispose());
    super.dispose();
  }
}
