import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class PlaceResult {
  final String displayName;
  final String shortName;
  final LatLng location;

  const PlaceResult({
    required this.displayName,
    required this.shortName,
    required this.location,
  });
}

class RouteStep {
  final String instruction;
  final String genericInstruction;
  final double distanceMeters;
  final LatLng location;

  const RouteStep({
    required this.instruction,
    required this.genericInstruction,
    required this.distanceMeters,
    required this.location,
  });
}

class RouteResult {
  final List<LatLng> polyline;
  final double distanceMeters;
  final double durationSeconds;
  final List<RouteStep> steps;

  const RouteResult({
    required this.polyline,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.steps,
  });

  String get formattedDistance {
    if (distanceMeters < 1000) {
      return '${distanceMeters.toStringAsFixed(0)} m';
    }
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }

  String get formattedDuration {
    final mins = (durationSeconds / 60).round();
    if (mins < 60) return '$mins min';
    final hrs = mins ~/ 60;
    final rem = mins % 60;
    return '${hrs}h ${rem}m';
  }
}

class OsmService {
  static const _headers = {
    'User-Agent': 'PolarTravel/2.0 (Open-Source Navigation App)',
  };

  static Future<List<PlaceResult>> searchPlaces(String query) async {
    if (query.trim().isEmpty) return [];
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query.trim(),
      'format': 'json',
      'limit': '6',
      'addressdetails': '1',
    });

    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) return [];

    final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
    return data.map((item) {
      final map = item as Map<String, dynamic>;
      final display = (map['display_name'] as String?) ?? 'Unknown place';
      final short = display.split(',').first.trim();
      return PlaceResult(
        displayName: display,
        shortName: short,
        location: LatLng(
          double.parse(map['lat'].toString()),
          double.parse(map['lon'].toString()),
        ),
      );
    }).toList();
  }

  static Future<RouteResult?> getRoute({
    required LatLng origin,
    required LatLng destination,
    required String profile,
  }) async {
    final osrmProfile = switch (profile) {
      'walking' => 'foot',
      'cycling' => 'bike',
      _ => 'driving',
    };

    final coords =
        '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}';
    final uri = Uri.https(
      'router.project-osrm.org',
      '/route/v1/$osrmProfile/$coords',
      {
        'overview': 'full',
        'geometries': 'geojson',
        'steps': 'true',
      },
    );

    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) return null;

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final routes = body['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) return null;

    final route = routes.first as Map<String, dynamic>;
    final geometry = route['geometry'] as Map<String, dynamic>;
    final rawCoords = geometry['coordinates'] as List<dynamic>;

    final polyline = rawCoords
        .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
        .toList();

    final steps = <RouteStep>[];
    final legs = route['legs'] as List<dynamic>? ?? [];
    for (final leg in legs) {
      final legSteps =
          (leg as Map<String, dynamic>)['steps'] as List<dynamic>? ?? [];
      for (final s in legSteps) {
        final stepMap = s as Map<String, dynamic>;
        final maneuver = stepMap['maneuver'] as Map<String, dynamic>? ?? {};
        final type = (maneuver['type'] as String?) ?? 'continue';
        final modifier = (maneuver['modifier'] as String?) ?? '';
        final roadName = (stepMap['name'] as String?) ?? '';
        final dist = (stepMap['distance'] as num?)?.toDouble() ?? 0;
        final locArr = maneuver['location'] as List<dynamic>?;
        final loc = (locArr != null && locArr.length >= 2)
            ? LatLng(
                (locArr[1] as num).toDouble(),
                (locArr[0] as num).toDouble(),
              )
            : origin;

        String fullText;
        String genericText;
        if (type == 'depart') {
          genericText = 'Head out on your route';
          fullText = roadName.isNotEmpty ? 'Start on $roadName' : genericText;
        } else if (type == 'arrive') {
          genericText = 'You have arrived at your destination';
          fullText = genericText;
        } else {
          final action = modifier.isNotEmpty ? '$type $modifier' : type;
          final capAction = action[0].toUpperCase() + action.substring(1);
          genericText = capAction;
          fullText = roadName.isNotEmpty ? '$capAction onto $roadName' : capAction;
        }
        steps.add(
          RouteStep(
            instruction: fullText,
            genericInstruction: genericText,
            distanceMeters: dist,
            location: loc,
          ),
        );
      }
    }

    return RouteResult(
      polyline: polyline,
      distanceMeters: (route['distance'] as num).toDouble(),
      durationSeconds: (route['duration'] as num).toDouble(),
      steps: steps,
    );
  }
}
