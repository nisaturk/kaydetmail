import 'dart:typed_data';

/// Web stand-in for `share_intake_io.dart`.
///
/// Never actually called: [ShareIntake.start] no-ops under `kIsWeb` because
/// there is no OS share sheet on the web, so `ShareIntake` never reads a
/// shared file. This only exists so the conditional import in
/// `share_intake.dart` resolves to something on the web target.
Future<Uint8List> readSharedFileBytes(String path) =>
    throw UnsupportedError('Share intake is not supported on web.');

/// The filename portion of a share-intent path. See [readSharedFileBytes].
String fileNameFromPath(String path) => path;
