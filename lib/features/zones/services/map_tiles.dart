import 'dart:io';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Standard OpenStreetMap raster tiles. No key, no paid provider.
const osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const osmCopyrightUrl = 'https://www.openstreetmap.org/copyright';

/// Identifies the app to the OSM tile servers (tile usage policy).
const mapUserAgentPackage = 'com.nolean.no_lean';

/// OSM serves zoom 0–19.
const osmMaxNativeZoom = 19;

/// Persistent tile cache cap. Only tiles the user actually viewed are stored;
/// nothing is prefetched or bulk-downloaded.
const mapTileCacheBytes = 150 * 1024 * 1024;

/// Builds the network tile provider with flutter_map's built-in cache in app
/// support storage (not the OS cache dir, which Android may clear), so tiles
/// already seen keep working offline. Stale tiles are revalidated with HTTP
/// cache headers when online and served from cache when the network fails.
Future<TileProvider> createOsmTileProvider() async {
  MapCachingProvider? cache;
  try {
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}/map_tiles');
    cache = BuiltInMapCachingProvider.getOrCreateInstance(
      cacheDirectory: directory.path,
      maxCacheSize: mapTileCacheBytes,
    );
  } catch (_) {
    cache = null; // flutter_map falls back to its default cache location.
  }
  return NetworkTileProvider(cachingProvider: cache);
}

/// Street tiles for the danger-zone map. Resolves to null when tiles should
/// not be used; the offline grid is always drawn underneath either way.
final mapTileProviderProvider = FutureProvider<TileProvider?>(
  (ref) => createOsmTileProvider(),
);
