import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Compresses an image to ~1MB max for Gemini vision calls.
class ImageCompressor {
  static Future<Uint8List> compress(File file, {int maxBytes = 1000000}) async {
    final bytes = await file.readAsBytes();
    if (bytes.lengthInBytes <= maxBytes) return bytes;

    // Decoding a 12MP photo allocates ~50MB and takes seconds. On the UI
    // isolate that's a frozen app and an ANR risk, so push it to a worker.
    return compute(_compressBytes, _CompressRequest(bytes, maxBytes));
  }
}

class _CompressRequest {
  const _CompressRequest(this.bytes, this.maxBytes);
  final Uint8List bytes;
  final int maxBytes;
}

Uint8List _compressBytes(_CompressRequest req) {
  img.Image? decoded = img.decodeImage(req.bytes);
  if (decoded == null) return req.bytes;

  // Resize keeping aspect ratio.
  final width = decoded.width > 1024 ? 1024 : decoded.width;
  decoded = img.copyResize(decoded, width: width);

  var quality = 85;
  var out = Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
  while (out.lengthInBytes > req.maxBytes && quality > 30) {
    quality -= 10;
    out = Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
  }
  return out;
}
