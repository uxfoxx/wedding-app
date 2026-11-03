import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'api.dart';

/// Direct upload: ask the API for a one-time upload URL, send the bytes straight to storage,
/// then confirm. The server never handles the file bytes in production.
/// [single] uploads only the first file picked; [onComplete] gets each confirmation response.
Future<int> pickAndUpload(Api api,
    {required String startPath,
    required String Function(String id) completePath,
    bool videos = false,
    bool audio = false,
    bool single = false,
    Map<String, dynamic> extra = const {},
    void Function(Map<String, dynamic> done)? onComplete}) async {
  final files = await FilePicker.pickFiles(
    type: audio ? FileType.custom : (videos ? FileType.media : FileType.image),
    allowedExtensions: audio ? const ['mp3', 'm4a', 'aac'] : null,
  );
  var done = 0;
  for (final f in single ? files.take(1) : files) {
    var bytes = await f.xFile.readAsBytes();
    var ext = (f.extension ?? '').toLowerCase();
    if (!audio && !const ['mp4', 'mov'].contains(ext)) {
      final shrunk = await shrinkPhoto(bytes, ext);
      if (shrunk != null) (bytes, ext) = (shrunk, 'jpg');
    }
    final type = switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg', 'png' => 'image/png', 'webp' => 'image/webp',
      'mp4' => 'video/mp4', 'mov' => 'video/quicktime',
      'mp3' => 'audio/mpeg', 'm4a' => 'audio/mp4', 'aac' => 'audio/aac',
      _ => f.xFile.mimeType ?? 'application/octet-stream',
    };
    final start = await api.post(startPath, {'content_type': type, 'size': bytes.length, ...extra});
    final res = await http.put(Uri.parse(start['upload_url'] as String), headers: {'content-type': type}, body: bytes);
    if (res.statusCode >= 300) throw ApiException(res.statusCode, 'upload_failed', 'The upload did not finish. Please try again.');
    final complete = await api.post(completePath(start['id'] as String), {'upload_token': ?start['upload_token']});
    onComplete?.call(complete);
    done++;
  }
  return done;
}

/// Phones shrink photos before sending: anything over 1600 px on its longest side, and any
/// format guest browsers can't all show (iPhone HEIC), is redrawn at most 1600 px as a JPEG
/// (a few hundred KB, so guest pages stay quick on a weak connection). Returns null when the
/// photo can go as it is.
Future<Uint8List?> shrinkPhoto(Uint8List bytes, String ext, {int maxSide = 1600}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final desc = await ui.ImageDescriptor.encoded(buffer);
  final longest = desc.width > desc.height ? desc.width : desc.height;
  final webReady = const ['jpg', 'jpeg', 'png', 'webp'].contains(ext);
  if (webReady && longest <= maxSide) {
    desc.dispose();
    buffer.dispose();
    return null;
  }
  final scale = longest > maxSide ? maxSide / longest : 1.0;
  final codec = await desc.instantiateCodec(targetWidth: (desc.width * scale).round(), targetHeight: (desc.height * scale).round());
  final frame = await codec.getNextFrame();
  final w = frame.image.width, h = frame.image.height;
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  frame.image.dispose();
  codec.dispose();
  desc.dispose();
  buffer.dispose();
  if (data == null) return null;
  // The platform decodes (including HEIC); JPEG encoding runs off the UI thread.
  return compute(_encodeJpeg, (data.buffer.asUint8List(), w, h));
}

Uint8List _encodeJpeg((Uint8List, int, int) raw) {
  final (rgba, w, h) = raw;
  final image = img.Image.fromBytes(width: w, height: h, bytes: rgba.buffer, numChannels: 4);
  return img.encodeJpg(image, quality: 82);
}
