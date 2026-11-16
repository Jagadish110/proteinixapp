import 'dart:io';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/utils/image_compressor.dart';
import 'supabase_service.dart';

/// Uploads profile photos to the public `avatars` storage bucket.
class AvatarService {
  const AvatarService._();

  /// Uploads [image] as the user's avatar and returns a public URL.
  ///
  /// Always writes to the same path per user (`{uid}/avatar.jpg`) so old
  /// photos don't pile up in storage — `upsert: true` overwrites in place.
  /// A cache-busting query param is appended to the returned URL since a
  /// fixed path would otherwise keep serving a cached copy of the old photo.
  static Future<String> upload(File image, String uid) async {
    final Uint8List bytes =
        await ImageCompressor.compress(image, maxBytes: 500000);
    final path = '$uid/avatar.jpg';

    await SupabaseService.client.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );

    final publicUrl =
        SupabaseService.client.storage.from('avatars').getPublicUrl(path);
    return '$publicUrl?updated=${DateTime.now().millisecondsSinceEpoch}';
  }
}
