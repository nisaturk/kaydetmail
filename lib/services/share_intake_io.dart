import 'dart:io';
import 'dart:typed_data';

/// Reads the bytes of a file the OS handed us via a share intent.
Future<Uint8List> readSharedFileBytes(String path) => File(path).readAsBytes();

/// The filename portion of a share-intent path.
String fileNameFromPath(String path) => path.split(Platform.pathSeparator).last;
