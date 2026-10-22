import 'package:url_launcher/url_launcher.dart';

class MapsService {
  MapsService({Future<bool> Function(Uri)? launch})
    : _launch = launch ?? _externalLaunch;
  final Future<bool> Function(Uri) _launch;
  Uri addressUri(String address) => Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address.trim())}',
  );
  Future<bool> openAddress(String address) => _launch(addressUri(address));
  static Future<bool> _externalLaunch(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}
