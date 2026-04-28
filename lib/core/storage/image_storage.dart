import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class ImageStorage {
  Future<String> saveChatImage({
    required Uint8List bytes,
    String? mimeType,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${directory.path}${Platform.pathSeparator}chat_images');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    final extension = _extensionFromMime(mimeType);
    final filename = 'img_${DateTime.now().microsecondsSinceEpoch}.$extension';
    final file = File('${imagesDir.path}${Platform.pathSeparator}$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<Uint8List> readBytes(String path) async {
    final file = File(path);
    return file.readAsBytes();
  }

  String mimeTypeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  String _extensionFromMime(String? mimeType) {
    final mime = (mimeType ?? '').toLowerCase().trim();
    return switch (mime) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      _ => 'jpg',
    };
  }
}

