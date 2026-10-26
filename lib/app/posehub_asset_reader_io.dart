import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readPoseHubAsset(Uri uri) {
  if (uri.scheme != 'file') {
    throw const FormatException('Installed pack images must be local files');
  }
  return File.fromUri(uri).readAsBytes();
}
