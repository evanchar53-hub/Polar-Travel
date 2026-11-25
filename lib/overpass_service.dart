import 'dart:convert';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

enum RoadFeatureType {
  stopSign,
  trafficLight,
  schoolZone,
  speedCamera,
  construction,
}

class RoadFeature {
  final RoadFeatureType type;
  final LatLng location;
  final String label;

  const RoadFeature({
    required this.type,
    required this.location,
    required this.label,
  });
}

class OverpassService {
  static const _endpoint = 'https://overpass-api.de/api/interpreter';

  /// Fetches requested OpenStreetMap road features inside [bounds].
  static Future<List<RoadFeature>> fetchRoadFeatures({
    required LatLngBounds bounds,
    required bool stopSigns,
    required bool trafficLights,
    required bool schoolZones,
    required bool speedCameras,
    required bool construction,
  }) async {
    if (!stopSigns &&
        !trafficLights &&
        !schoolZones &&
        !speedCameras &&
        !construction) {
      return [];
    }

    // Clamp query area to avoid Overpass timeouts when zoomed way out
    final latSpan = (bounds.north - bounds.south).abs();
    final lonSpan = (bounds.east - bounds.west).abs();
    if (latSpan > 0.25 || lonSpan > 0.25) {
      return [];
    }

    final bbox =
        '${bounds.south.toStringAsFixed(5)},${bounds.west.toStringAsFixed(5)},'
        '${bounds.north.toStringAsFixed(5)},${bounds.east.toStringAsFixed(5)}';

    final clauses = <String>[];
    if (stopSigns) clauses.add('node["highway"="stop"]($bbox);');
    if (trafficLights) clauses.add('node["highway"="traffic_signals"]($bbox);');
    if (speedCameras) clauses.add('node["highway"="speed_camera"]($bbox);');
    if (schoolZones) {
      clauses.add('node["amenity"="school"]($bbox);');
      clauses.add('way["amenity"="school"]($bbox);');
    }
    if (construction) {
      clauses.add('way["highway"="construction"]($bbox);');
      clauses.add('node["barrier"="block"]($bbox);');
    }

    final query =
        '[out:json][timeout:15];(${clauses.join()});out center 150;';

    final res = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'User-Agent': 'PolarTravel/2.0 (Open-Source Navigation App)',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {'data': query},
    );

    if (res.statusCode != 200) return [];

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final elements = json['elements'] as List<dynamic>? ?? [];
    final results = <RoadFeature>[];

    for (final raw in elements) {
      final el = raw as Map<String, dynamic>;
      final tags = (el['tags'] as Map<String, dynamic>?) ?? {};

      double? lat = (el['lat'] as num?)?.toDouble();
      double? lon = (el['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) {
        final center = el['center'] as Map<String, dynamic>?;
        lat = (center?['lat'] as num?)?.toDouble();
        lon = (center?['lon'] as num?)?.toDouble();
      }
      if (lat == null || lon == null) continue;

      final pt = LatLng(lat, lon);
      final name = (tags['name'] as String?) ?? '';

      if (tags['highway'] == 'stop') {
        results.add(RoadFeature(
          type: RoadFeatureType.stopSign,
          location: pt,
          label: 'Stop Sign',
        ));
      } else if (tags['highway'] == 'traffic_signals') {
        results.add(RoadFeature(
          type: RoadFeatureType.trafficLight,
          location: pt,
          label: 'Traffic Signal',
        ));
      } else if (tags['highway'] == 'speed_camera') {
        final maxspeed = tags['maxspeed'] != null ? ' (${tags['maxspeed']})' : '';
        results.add(RoadFeature(
          type: RoadFeatureType.speedCamera,
          location: pt,
          label: 'Speed Camera$maxspeed',
        ));
      } else if (tags['amenity'] == 'school') {
        results.add(RoadFeature(
          type: RoadFeatureType.schoolZone,
          location: pt,
          label: name.isNotEmpty ? 'School Zone: $name' : 'School Zone',
        ));
      } else if (tags['highway'] == 'construction' ||
          tags['barrier'] == 'block') {
        results.add(RoadFeature(
          type: RoadFeatureType.construction,
          location: pt,
          label: name.isNotEmpty ? 'Construction: $name' : 'Construction Zone',
        ));
      }
    }
    return results;
  }
}
