import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'osm_service.dart';
import 'overpass_service.dart';
import 'voices_screen.dart';

void main() => runApp(const PolarTravelApp());

class PolarColors {
  static const Color royalBlue = Color(0xFF1E40AF);
  static const Color deepRoyal = Color(0xFF172554);
  static const Color powderBlue = Color(0xFFB0E0E6);
  static const Color silver = Color(0xFFC0C0C0);
  static const Color white = Color(0xFFFFFFFF);
  static const Color iceSurface = Color(0xFFF4F9FC);
}

enum BaseMapStyle { street, satellite, hybrid }

class UserHazardReport {
  final String id;
  final String category; // 'Speed Trap', 'Road Closure', 'Construction', 'Heavy Traffic'
  final LatLng location;
  final DateTime reportedAt;

  const UserHazardReport({
    required this.id,
    required this.category,
    required this.location,
    required this.reportedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'lat': location.latitude,
        'lon': location.longitude,
        'reportedAt': reportedAt.toIso8601String(),
      };

  factory UserHazardReport.fromJson(Map<String, dynamic> json) =>
      UserHazardReport(
        id: json['id'] as String,
        category: json['category'] as String,
        location: LatLng(
          (json['lat'] as num).toDouble(),
          (json['lon'] as num).toDouble(),
        ),
        reportedAt: DateTime.tryParse(json['reportedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

class PolarTravelApp extends StatelessWidget {
  const PolarTravelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Polar Travel',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.light(
          primary: PolarColors.royalBlue,
          onPrimary: PolarColors.white,
          secondary: PolarColors.powderBlue,
          onSecondary: PolarColors.deepRoyal,
          surface: PolarColors.white,
          onSurface: PolarColors.deepRoyal,
          outline: PolarColors.silver,
        ),
        scaffoldBackgroundColor: PolarColors.iceSurface,
      ),
      home: const PolarTravelHomePage(),
    );
  }
}

class PolarTravelHomePage extends StatefulWidget {
  const PolarTravelHomePage({super.key});

  @override
  State<PolarTravelHomePage> createState() => _PolarTravelHomePageState();
}

class _PolarTravelHomePageState extends State<PolarTravelHomePage> {
  final MapController _mapController = MapController();
  final TextEditingController _searchCtrl = TextEditingController();
  final FlutterTts _tts = FlutterTts();

  StreamSubscription<Position>? _gpsSub;
  LatLng? _currentLocation;

  // Map style & optional TomTom Rush-Hour Traffic Flow layer
  BaseMapStyle _mapStyle = BaseMapStyle.street;
  bool _showTrafficFlow = false;
  String _tomTomApiKey = '';

  // Overpass Road Feature Overlay Toggles
  bool _showStopSigns = false;
  bool _showTrafficLights = false;
  bool _showSchoolZones = true;
  bool _showSpeedCameras = true;
  bool _showConstruction = true;
  bool _isLoadingOverlays = false;
  List<RoadFeature> _roadFeatures = [];

  // Waze-style quick hazard reports
  List<UserHazardReport> _userReports = [];

  // Search, Routing & Navigation
  List<PlaceResult> _searchResults = [];
  bool _isSearching = false;
  bool _isRouting = false;
  PlaceResult? _selectedDestination;
  RouteResult? _activeRoute;
  String _travelMode = 'driving';
  bool _isNavigating = false;
  int _activeStepIndex = 0;

  // Voice Settings
  VoiceSettings _voiceSettings = const VoiceSettings();

  @override
  void initState() {
    super.initState();
    _loadPersistedSettings();
    _initGps();
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _searchCtrl.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _loadPersistedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedKey = prefs.getString('tomtom_api_key') ?? '';
    final rawReports = prefs.getString('user_hazard_reports');
    final reports = <UserHazardReport>[];
    if (rawReports != null) {
      try {
        final list = jsonDecode(rawReports) as List<dynamic>;
        for (final item in list) {
          reports.add(
            UserHazardReport.fromJson(Map<String, dynamic>.from(item as Map)),
          );
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _tomTomApiKey = savedKey;
        _showTrafficFlow = savedKey.isNotEmpty &&
            (prefs.getBool('show_traffic_flow') ?? false);
        _userReports = reports;
      });
    }
    await _applyVoiceSettings();
  }

  Future<void> _saveReports() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'user_hazard_reports',
      jsonEncode(_userReports.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _applyVoiceSettings() async {
    final preset = _voiceSettings.activePreset;
    await _tts.setLanguage(preset.locale);
    await _tts.setPitch(preset.pitch);
    await _tts.setSpeechRate(_voiceSettings.speechRate);
  }

  Future<void> _speakStep(RouteStep step) async {
    if (!_voiceSettings.voiceEnabled) return;
    await _applyVoiceSettings();
    final text = _voiceSettings.spokenStreetNames
        ? step.instruction
        : step.genericInstruction;
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> _initGps() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    final initial = await Geolocator.getCurrentPosition();
    final startPoint = LatLng(initial.latitude, initial.longitude);
    if (mounted) {
      setState(() => _currentLocation = startPoint);
      _mapController.move(startPoint, 14);
      _refreshRoadOverlays();
    }

    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
      ),
    ).listen((pos) {
      final pt = LatLng(pos.latitude, pos.longitude);
      setState(() => _currentLocation = pt);
      if (_isNavigating) {
        _mapController.move(pt, 17);
        _advanceNavigationStepIfNeeded(pt);
      }
    });
  }

  void _advanceNavigationStepIfNeeded(LatLng current) {
    if (_activeRoute == null || _activeRoute!.steps.isEmpty) return;
    final nextIdx = _activeStepIndex + 1;
    if (nextIdx >= _activeRoute!.steps.length) return;

    const distCalc = Distance();
    final distToNext = distCalc.as(
      LengthUnit.Meter,
      current,
      _activeRoute!.steps[nextIdx].location,
    );
    if (distToNext < 45) {
      setState(() => _activeStepIndex = nextIdx);
      _speakStep(_activeRoute!.steps[nextIdx]);
    }
  }

  Future<void> _refreshRoadOverlays() async {
    if (!_showStopSigns &&
        !_showTrafficLights &&
        !_showSchoolZones &&
        !_showSpeedCameras &&
        !_showConstruction) {
      setState(() => _roadFeatures = []);
      return;
    }

    final bounds = _mapController.camera.visibleBounds;
    setState(() => _isLoadingOverlays = true);
    try {
      final features = await OverpassService.fetchRoadFeatures(
        bounds: bounds,
        stopSigns: _showStopSigns,
        trafficLights: _showTrafficLights,
        schoolZones: _showSchoolZones,
        speedCameras: _showSpeedCameras,
        construction: _showConstruction,
      );
      if (mounted) {
        setState(() => _roadFeatures = features);
      }
    } catch (_) {
      // Overpass rate-limited or offline; keep current markers
    } finally {
      if (mounted) setState(() => _isLoadingOverlays = false);
    }
  }

  Future<void> _runSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isSearching = true);
    try {
      final results = await OsmService.searchPlaces(query);
      if (mounted) setState(() => _searchResults = results);
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _selectPlace(PlaceResult place) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _selectedDestination = place;
      _searchResults = [];
      _searchCtrl.text = place.shortName;
      _activeRoute = null;
      _isNavigating = false;
      _activeStepIndex = 0;
    });
    _mapController.move(place.location, 15);
    await _calculateRoute();
  }

  Future<void> _calculateRoute() async {
    if (_selectedDestination == null) return;
    final origin = _currentLocation ?? const LatLng(43.6532, -79.3832);

    setState(() => _isRouting = true);
    try {
      final route = await OsmService.getRoute(
        origin: origin,
        destination: _selectedDestination!.location,
        profile: _travelMode,
      );
      if (!mounted) return;
      setState(() {
        _activeRoute = route;
        _activeStepIndex = 0;
      });
      if (route != null && route.polyline.length > 1) {
        final bounds = LatLngBounds.fromPoints(route.polyline);
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.fromLTRB(36, 130, 36, 230),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRouting = false);
    }
  }

  void _clearRoute() {
    _tts.stop();
    setState(() {
      _selectedDestination = null;
      _activeRoute = null;
      _isNavigating = false;
      _activeStepIndex = 0;
      _searchCtrl.clear();
    });
  }

  Future<void> _openVoicesScreen() async {
    final updated = await Navigator.push<VoiceSettings>(
      context,
      MaterialPageRoute(
        builder: (_) => NavigationVoicesScreen(
          initialSettings: _voiceSettings,
          tts: _tts,
        ),
      ),
    );
    if (updated != null && mounted) {
      setState(() => _voiceSettings = updated);
      await _applyVoiceSettings();
    }
  }

  void _openLayersSheet() {
    final keyCtrl = TextEditingController(text: _tomTomApiKey);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: PolarColors.iceSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Map Style & Overlays',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: PolarColors.deepRoyal,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<BaseMapStyle>(
                    segments: const [
                      ButtonSegment(
                        value: BaseMapStyle.street,
                        label: Text('Street'),
                        icon: Icon(Icons.map),
                      ),
                      ButtonSegment(
                        value: BaseMapStyle.satellite,
                        label: Text('Satellite'),
                        icon: Icon(Icons.satellite_alt),
                      ),
                      ButtonSegment(
                        value: BaseMapStyle.hybrid,
                        label: Text('Hybrid'),
                        icon: Icon(Icons.layers),
                      ),
                    ],
                    selected: {_mapStyle},
                    onSelectionChanged: (sel) {
                      setSheetState(() => _mapStyle = sel.first);
                      setState(() => _mapStyle = sel.first);
                    },
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'OPENSTREETMAP ROAD OVERLAYS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: PolarColors.deepRoyal,
                    ),
                  ),
                  SwitchListTile(
                    dense: true,
                    activeTrackColor: PolarColors.royalBlue,
                    title: const Text('Stop Signs'),
                    value: _showStopSigns,
                    onChanged: (v) {
                      setSheetState(() => _showStopSigns = v);
                      setState(() => _showStopSigns = v);
                    },
                  ),
                  SwitchListTile(
                    dense: true,
                    activeTrackColor: PolarColors.royalBlue,
                    title: const Text('Traffic Lights'),
                    value: _showTrafficLights,
                    onChanged: (v) {
                      setSheetState(() => _showTrafficLights = v);
                      setState(() => _showTrafficLights = v);
                    },
                  ),
                  SwitchListTile(
                    dense: true,
                    activeTrackColor: PolarColors.royalBlue,
                    title: const Text('School Zones'),
                    value: _showSchoolZones,
                    onChanged: (v) {
                      setSheetState(() => _showSchoolZones = v);
                      setState(() => _showSchoolZones = v);
                    },
                  ),
                  SwitchListTile(
                    dense: true,
                    activeTrackColor: PolarColors.royalBlue,
                    title: const Text('Fixed Speed Cameras'),
                    value: _showSpeedCameras,
                    onChanged: (v) {
                      setSheetState(() => _showSpeedCameras = v);
                      setState(() => _showSpeedCameras = v);
                    },
                  ),
                  SwitchListTile(
                    dense: true,
                    activeTrackColor: PolarColors.royalBlue,
                    title: const Text('Construction Zones'),
                    value: _showConstruction,
                    onChanged: (v) {
                      setSheetState(() => _showConstruction = v);
                      setState(() => _showConstruction = v);
                    },
                  ),
                  const Divider(),
                  const Text(
                    'RUSH-HOUR TRAFFIC FLOW (OPTIONAL TOMTOM KEY)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: PolarColors.deepRoyal,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: keyCtrl,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      hintText: 'Paste free TomTom API key for live traffic',
                    ),
                  ),
                  SwitchListTile(
                    dense: true,
                    activeTrackColor: PolarColors.royalBlue,
                    title: const Text('Show Live Rush-Hour Traffic'),
                    value: _showTrafficFlow,
                    onChanged: (v) {
                      setSheetState(() => _showTrafficFlow = v);
                      setState(() => _showTrafficFlow = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: PolarColors.royalBlue,
                      ),
                      onPressed: () async {
                        final trimmed = keyCtrl.text.trim();
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('tomtom_api_key', trimmed);
                        await prefs.setBool(
                          'show_traffic_flow',
                          _showTrafficFlow,
                        );
                        setState(() => _tomTomApiKey = trimmed);
                        if (ctx.mounted) Navigator.pop(ctx);
                        _refreshRoadOverlays();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Apply & Scan Visible Area'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openQuickReportSheet() {
    final targetLoc = _currentLocation ?? _mapController.camera.center;
    showModalBottomSheet(
      context: context,
      backgroundColor: PolarColors.iceSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Quick Road Report',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: PolarColors.deepRoyal,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Drop a pin at your current location (or map center):',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 14),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.5,
                children: [
                  _reportTile(
                    ctx,
                    'Speed Trap',
                    Icons.local_police,
                    Colors.indigo,
                    targetLoc,
                  ),
                  _reportTile(
                    ctx,
                    'Road Closure',
                    Icons.block,
                    Colors.red.shade700,
                    targetLoc,
                  ),
                  _reportTile(
                    ctx,
                    'Construction',
                    Icons.construction,
                    Colors.orange.shade800,
                    targetLoc,
                  ),
                  _reportTile(
                    ctx,
                    'Heavy Traffic',
                    Icons.traffic,
                    Colors.amber.shade900,
                    targetLoc,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reportTile(
    BuildContext ctx,
    String category,
    IconData icon,
    Color color,
    LatLng loc,
  ) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: PolarColors.white,
        foregroundColor: PolarColors.deepRoyal,
        side: const BorderSide(color: PolarColors.silver),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: () async {
        final report = UserHazardReport(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          category: category,
          location: loc,
          reportedAt: DateTime.now(),
        );
        setState(() => _userReports.add(report));
        await _saveReports();
        if (ctx.mounted) Navigator.pop(ctx);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: PolarColors.deepRoyal,
              content: Text('Reported $category on Polar Travel'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      icon: Icon(icon, color: color),
      label: Text(
        category,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );
  }

  void _showTurnByTurnSteps() {
    if (_activeRoute == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: PolarColors.iceSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Turn-by-Turn (${_activeRoute!.formattedDuration} • ${_activeRoute!.formattedDistance})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: PolarColors.deepRoyal,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _activeRoute!.steps.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final step = _activeRoute!.steps[i];
                    final distStr = step.distanceMeters >= 1000
                        ? '${(step.distanceMeters / 1000).toStringAsFixed(1)} km'
                        : '${step.distanceMeters.toStringAsFixed(0)} m';
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: PolarColors.royalBlue,
                        foregroundColor: PolarColors.white,
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      title: Text(step.instruction),
                      trailing: Text(
                        distStr,
                        style: const TextStyle(
                          color: PolarColors.royalBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: () => _speakStep(step),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Marker _buildRoadFeatureMarker(RoadFeature f) {
    final (IconData icon, Color bg) = switch (f.type) {
      RoadFeatureType.stopSign => (Icons.octagon_outlined, Colors.red.shade700),
      RoadFeatureType.trafficLight => (Icons.traffic, Colors.amber.shade800),
      RoadFeatureType.schoolZone => (Icons.school, PolarColors.royalBlue),
      RoadFeatureType.speedCamera => (Icons.camera_alt, Colors.deepPurple),
      RoadFeatureType.construction => (Icons.construction, Colors.orange.shade800),
    };

    return Marker(
      point: f.location,
      width: 28,
      height: 28,
      child: Tooltip(
        message: f.label,
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(color: PolarColors.white, width: 2),
            boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
          ),
          child: Icon(icon, color: PolarColors.white, size: 15),
        ),
      ),
    );
  }

  Marker _buildUserReportMarker(UserHazardReport r) {
    final (IconData icon, Color bg) = switch (r.category) {
      'Speed Trap' => (Icons.local_police, Colors.indigo),
      'Road Closure' => (Icons.block, Colors.red.shade700),
      'Construction' => (Icons.construction, Colors.orange.shade800),
      _ => (Icons.traffic, Colors.amber.shade900),
    };

    return Marker(
      point: r.location,
      width: 34,
      height: 34,
      child: GestureDetector(
        onTap: () {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(r.category),
              content: Text(
                'Reported at ${r.reportedAt.hour.toString().padLeft(2, '0')}:'
                '${r.reportedAt.minute.toString().padLeft(2, '0')}',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
                TextButton(
                  onPressed: () async {
                    setState(
                      () => _userReports.removeWhere((item) => item.id == r.id),
                    );
                    await _saveReports();
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Clear Report'),
                ),
              ],
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(color: PolarColors.powderBlue, width: 2.5),
            boxShadow: const [BoxShadow(blurRadius: 5, color: Colors.black38)],
          ),
          child: Icon(icon, color: PolarColors.white, size: 18),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentStep = (_activeRoute != null &&
            _activeStepIndex < _activeRoute!.steps.length)
        ? _activeRoute!.steps[_activeStepIndex]
        : null;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(43.6532, -79.3832),
              initialZoom: 14,
              minZoom: 3,
              maxZoom: 19,
              onLongPress: (_, point) {
                _selectPlace(
                  PlaceResult(
                    displayName:
                        'Dropped Pin (${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)})',
                    shortName: 'Dropped Pin',
                    location: point,
                  ),
                );
              },
            ),
            children: [
              // 1. Base Layer: Street OR Esri Satellite
              if (_mapStyle == BaseMapStyle.street)
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.polartravel.app',
                )
              else
                TileLayer(
                  urlTemplate:
                      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                  userAgentPackageName: 'com.polartravel.app',
                ),

              // 2. Hybrid Labels Overlay (when Hybrid is selected)
              if (_mapStyle == BaseMapStyle.hybrid)
                TileLayer(
                  urlTemplate:
                      'https://basemaps.cartocdn.com/rastertiles/voyager_only_labels/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.polartravel.app',
                ),

              // 3. Optional Live Rush-Hour Traffic Flow Overlay (TomTom)
              if (_showTrafficFlow && _tomTomApiKey.isNotEmpty)
                TileLayer(
                  urlTemplate:
                      'https://api.tomtom.com/traffic/map/4/tile/flow/relative0/{z}/{x}/{y}.png?key=$_tomTomApiKey',
                  userAgentPackageName: 'com.polartravel.app',
                ),

              // 4. School Zone Highlight Circles
              CircleLayer(
                circles: _roadFeatures
                    .where((f) => f.type == RoadFeatureType.schoolZone)
                    .map(
                      (f) => CircleMarker(
                        point: f.location,
                        radius: 120,
                        useRadiusInMeter: true,
                        color: PolarColors.powderBlue.withValues(alpha: 0.35),
                        borderColor: PolarColors.royalBlue,
                        borderStrokeWidth: 1.5,
                      ),
                    )
                    .toList(),
              ),

              // 5. Active Route Polyline
              if (_activeRoute != null && _activeRoute!.polyline.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _activeRoute!.polyline,
                      strokeWidth: 6.0,
                      color: PolarColors.royalBlue,
                      borderColor: PolarColors.white,
                      borderStrokeWidth: 2.0,
                    ),
                  ],
                ),

              // 6. Road Features, Community Reports, Destination & Live GPS
              MarkerLayer(
                markers: [
                  ..._roadFeatures.map(_buildRoadFeatureMarker),
                  ..._userReports.map(_buildUserReportMarker),
                  if (_selectedDestination != null)
                    Marker(
                      point: _selectedDestination!.location,
                      width: 42,
                      height: 42,
                      child: const Icon(
                        Icons.location_pin,
                        color: PolarColors.royalBlue,
                        size: 42,
                      ),
                    ),
                  if (_currentLocation != null)
                    Marker(
                      point: _currentLocation!,
                      width: 24,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(
                          color: PolarColors.royalBlue,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: PolarColors.white,
                            width: 3.5,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              blurRadius: 8,
                              color: PolarColors.powderBlue,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Top Search Bar + Navigation Banner
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_isNavigating)
                    Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(16),
                      color: PolarColors.white,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: PolarColors.silver),
                        ),
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 10),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.asset(
                                  'assets/icon/polar_travel_icon.png',
                                  width: 32,
                                  height: 32,
                                ),
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _searchCtrl,
                                textInputAction: TextInputAction.search,
                                onSubmitted: _runSearch,
                                decoration: const InputDecoration(
                                  hintText: 'Search Polar Travel...',
                                  border: InputBorder.none,
                                  contentPadding:
                                      EdgeInsets.symmetric(horizontal: 12),
                                ),
                              ),
                            ),
                            if (_isSearching)
                              const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: PolarColors.royalBlue,
                                  ),
                                ),
                              )
                            else if (_searchCtrl.text.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: _clearRoute,
                              )
                            else
                              IconButton(
                                icon: const Icon(
                                  Icons.search,
                                  color: PolarColors.royalBlue,
                                ),
                                onPressed: () => _runSearch(_searchCtrl.text),
                              ),
                            IconButton(
                              icon: const Icon(
                                Icons.record_voice_over,
                                color: PolarColors.royalBlue,
                              ),
                              tooltip: 'Navigation Voices',
                              onPressed: _openVoicesScreen,
                            ),
                          ],
                        ),
                      ),
                    ),

                  if (_searchResults.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      constraints: const BoxConstraints(maxHeight: 240),
                      decoration: BoxDecoration(
                        color: PolarColors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: PolarColors.silver),
                        boxShadow: const [
                          BoxShadow(blurRadius: 8, color: Colors.black26),
                        ],
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, idx) {
                          final place = _searchResults[idx];
                          return ListTile(
                            dense: true,
                            leading: const Icon(
                              Icons.place,
                              color: PolarColors.royalBlue,
                            ),
                            title: Text(
                              place.shortName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: PolarColors.deepRoyal,
                              ),
                            ),
                            subtitle: Text(
                              place.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _selectPlace(place),
                          );
                        },
                      ),
                    ),

                  // Active Turn-by-Turn Banner with Voice Indicator
                  if (_isNavigating && currentStep != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: PolarColors.deepRoyal,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: PolarColors.powderBlue,
                          width: 1.5,
                        ),
                        boxShadow: const [
                          BoxShadow(blurRadius: 8, color: Colors.black38),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.turn_right,
                            color: PolarColors.powderBlue,
                            size: 32,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentStep.distanceMeters >= 1000
                                      ? '${(currentStep.distanceMeters / 1000).toStringAsFixed(1)} km'
                                      : '${currentStep.distanceMeters.toStringAsFixed(0)} m',
                                  style: const TextStyle(
                                    color: PolarColors.powderBlue,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  currentStep.instruction,
                                  style: const TextStyle(
                                    color: PolarColors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              _voiceSettings.voiceEnabled
                                  ? Icons.volume_up
                                  : Icons.volume_off,
                              color: PolarColors.powderBlue,
                            ),
                            onPressed: () {
                              setState(() {
                                _voiceSettings = _voiceSettings.copyWith(
                                  voiceEnabled: !_voiceSettings.voiceEnabled,
                                );
                              });
                              if (!_voiceSettings.voiceEnabled) {
                                _tts.stop();
                              } else {
                                _speakStep(currentStep);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Right-Side Floating Controls (Layers, Scan Area, Quick Report, GPS)
          Positioned(
            right: 12,
            top: _isNavigating ? 120 : 108,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'layers_btn',
                  tooltip: 'Satellite & Road Overlays',
                  backgroundColor: PolarColors.white,
                  foregroundColor: PolarColors.royalBlue,
                  shape: const CircleBorder(
                    side: BorderSide(color: PolarColors.silver, width: 1.5),
                  ),
                  onPressed: _openLayersSheet,
                  child: const Icon(Icons.layers),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'scan_overlays_btn',
                  tooltip: 'Scan Road Features Here',
                  backgroundColor: PolarColors.white,
                  foregroundColor: PolarColors.royalBlue,
                  shape: const CircleBorder(
                    side: BorderSide(color: PolarColors.silver, width: 1.5),
                  ),
                  onPressed: _isLoadingOverlays ? null : _refreshRoadOverlays,
                  child: _isLoadingOverlays
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: PolarColors.royalBlue,
                          ),
                        )
                      : const Icon(Icons.radar),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'report_btn',
                  tooltip: 'Report Hazard / Speed Trap',
                  backgroundColor: PolarColors.royalBlue,
                  foregroundColor: PolarColors.white,
                  shape: const CircleBorder(
                    side: BorderSide(color: PolarColors.powderBlue, width: 1.5),
                  ),
                  onPressed: _openQuickReportSheet,
                  child: const Icon(Icons.add_alert),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'gps_btn',
                  tooltip: 'Center on GPS',
                  backgroundColor: PolarColors.white,
                  foregroundColor: PolarColors.royalBlue,
                  shape: const CircleBorder(
                    side: BorderSide(color: PolarColors.silver, width: 1.5),
                  ),
                  onPressed: _currentLocation == null
                      ? null
                      : () => _mapController.move(_currentLocation!, 15),
                  child: const Icon(Icons.my_location),
                ),
              ],
            ),
          ),

          // Route Summary Bottom Card
          if (_selectedDestination != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 16,
              child: Card(
                color: PolarColors.white,
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: PolarColors.silver, width: 1.4),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _selectedDestination!.shortName,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: PolarColors.deepRoyal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: _clearRoute,
                          ),
                        ],
                      ),
                      if (!_isNavigating)
                        Row(
                          children: [
                            _modeChip('driving', Icons.directions_car, 'Drive'),
                            const SizedBox(width: 8),
                            _modeChip('walking', Icons.directions_walk, 'Walk'),
                            const SizedBox(width: 8),
                            _modeChip('cycling', Icons.directions_bike, 'Bike'),
                          ],
                        ),
                      const SizedBox(height: 10),
                      if (_isRouting)
                        const LinearProgressIndicator(
                          color: PolarColors.royalBlue,
                        )
                      else if (_activeRoute != null)
                        Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _activeRoute!.formattedDuration,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: PolarColors.royalBlue,
                                  ),
                                ),
                                Text(
                                  _activeRoute!.formattedDistance,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            OutlinedButton(
                              onPressed: _showTurnByTurnSteps,
                              child: const Text('Steps'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: _isNavigating
                                    ? PolarColors.deepRoyal
                                    : PolarColors.royalBlue,
                              ),
                              onPressed: () {
                                final starting = !_isNavigating;
                                setState(() {
                                  _isNavigating = starting;
                                  _activeStepIndex = 0;
                                });
                                if (starting) {
                                  if (_currentLocation != null) {
                                    _mapController.move(_currentLocation!, 17);
                                  }
                                  if (_activeRoute!.steps.isNotEmpty) {
                                    _speakStep(_activeRoute!.steps.first);
                                  }
                                } else {
                                  _tts.stop();
                                }
                              },
                              icon: Icon(
                                _isNavigating ? Icons.stop : Icons.navigation,
                                size: 18,
                              ),
                              label: Text(_isNavigating ? 'Stop' : 'Start'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _modeChip(String mode, IconData icon, String label) {
    final selected = _travelMode == mode;
    return ChoiceChip(
      selected: selected,
      selectedColor: PolarColors.powderBlue,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: PolarColors.deepRoyal),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: PolarColors.deepRoyal,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      onSelected: (_) {
        if (_travelMode == mode) return;
        setState(() => _travelMode = mode);
        _calculateRoute();
      },
    );
  }
}
