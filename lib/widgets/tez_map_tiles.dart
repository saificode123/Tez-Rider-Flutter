import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';

/// Uses the existing disk cache and honours HTTP freshness on native. Browsers
/// retain their own HTTP cache/Referer. No prefetch or offline-download feature.
TileProvider tezMapTiles() =>
    kIsWeb ? NetworkTileProvider() : _CachedTezTiles();

class _CachedTezTiles extends TileProvider {
  _CachedTezTiles()
    : super(
        headers: {
          'User-Agent': defaultTargetPlatform == TargetPlatform.iOS
              ? 'TezRider/1.0 (iOS delivery app)'
              : 'TezRider/1.0 (Android delivery app)',
        },
      );
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      CachedNetworkImageProvider(
        getTileUrl(coordinates, options),
        headers: headers,
      );
}

class TezMapAttribution extends StatelessWidget {
  const TezMapAttribution({super.key});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: InkWell(
      onTap: () =>
          launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')),
      child: const Padding(
        padding: EdgeInsets.all(6),
        child: Text(
          '© OpenStreetMap contributors',
          style: TextStyle(fontSize: 11),
        ),
      ),
    ),
  );
}
