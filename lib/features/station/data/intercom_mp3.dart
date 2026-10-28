import 'dart:io';
import 'dart:typed_data';

import 'package:audio_decoder/audio_decoder.dart';

import 'intercom_codec.dart';

/// Raw 16 kHz 16-bit mono PCM taken from an MP3.
class IntercomFilePcm {
  const IntercomFilePcm({required this.pcm, required this.trimmed});

  final Uint8List pcm;

  /// True when the file was longer than three minutes and the rest was left out.
  final bool trimmed;
}

/// Decodes an MP3 with Windows Media Foundation.
///
/// The bytes are the file as stored. Nothing here boosts, gates, or filters them.
Future<IntercomFilePcm> pcm16kFromMp3File(String path) async {
  final Uint8List mp3 = await File(path).readAsBytes();
  final Uint8List pcm = await AudioDecoder.convertToWavBytes(
    mp3,
    formatHint: 'mp3',
    sampleRate: IntercomCodec.sampleRate,
    channels: 1,
    bitDepth: 16,
    includeHeader: false,
  );
  const int maxBytes = IntercomCodec.sampleRate * 180 * 2;
  if (pcm.length <= maxBytes) {
    final int even = pcm.length.isEven ? pcm.length : pcm.length - 1;
    return IntercomFilePcm(
      pcm: even == pcm.length ? pcm : Uint8List.sublistView(pcm, 0, even),
      trimmed: false,
    );
  }
  return IntercomFilePcm(
    pcm: Uint8List.sublistView(pcm, 0, maxBytes),
    trimmed: true,
  );
}
