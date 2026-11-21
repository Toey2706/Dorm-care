import 'dart:typed_data';

import 'package:image/image.dart' as img;

const maxPhotoSide = 1200;
const photoQuality = 78;
Uint8List compressPhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  var image = img.bakeOrientation(decoded);
  if (image.width > maxPhotoSide || image.height > maxPhotoSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxPhotoSide, interpolation: img.Interpolation.average)
        : img.copyResize(image, height: maxPhotoSide, interpolation: img.Interpolation.average);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: photoQuality));
}
