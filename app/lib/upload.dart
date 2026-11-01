import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import 'api.dart';

/// Direct upload: ask the API for a one-time upload URL, send the bytes straight to storage,
/// then confirm. The server never handles the file bytes in production.
Future<int> pickAndUpload(Api api, {required String startPath, required String Function(String id) completePath, bool videos = false, Map<String, dynamic> extra = const {}}) async {
  final files = await FilePicker.pickFiles(type: videos ? FileType.media : FileType.image);
  var done = 0;
  for (final f in files) {
    final bytes = await f.xFile.readAsBytes();
    final ext = (f.extension ?? '').toLowerCase();
    final type = switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg', 'png' => 'image/png', 'webp' => 'image/webp',
      'mp4' => 'video/mp4', 'mov' => 'video/quicktime', _ => f.xFile.mimeType ?? 'application/octet-stream',
    };
    final start = await api.post(startPath, {'content_type': type, 'size': bytes.length, ...extra});
    final res = await http.put(Uri.parse(start['upload_url'] as String), headers: {'content-type': type}, body: bytes);
    if (res.statusCode >= 300) throw ApiException(res.statusCode, 'upload_failed', 'The upload did not finish. Please try again.');
    await api.post(completePath(start['id'] as String), {'upload_token': start['upload_token']});
    done++;
  }
  return done;
}
