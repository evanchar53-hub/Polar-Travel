import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoicePreset {
  final String id;
  final String title;
  final String subtitle;
  final String locale;
  final double pitch;
  final String sampleText;

  const VoicePreset({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.locale,
    required this.pitch,
    required this.sampleText,
  });
}

const List<VoicePreset> kPolarVoicePresets = [
  VoicePreset(
    id: 'arctic_clear',
    title: 'Arctic Clear',
    subtitle: 'English (Canada)',
    locale: 'en-CA',
    pitch: 1.0,
    sampleText: 'In 350 meters, turn right onto King Street West.',
  ),
  VoicePreset(
    id: 'boreal_calm',
    title: 'Boreal Calm',
    subtitle: 'English (UK)',
    locale: 'en-GB',
    pitch: 0.95,
    sampleText: 'In 350 meters, turn right onto King Street West.',
  ),
  VoicePreset(
    id: 'aurora_fr',
    title: 'Aurora',
    subtitle: 'French (Canada)',
    locale: 'fr-CA',
    pitch: 1.05,
    sampleText: 'Dans 350 mètres, tournez à droite sur la rue King Ouest.',
  ),
  VoicePreset(
    id: 'tundra_crisp',
    title: 'Tundra Crisp',
    subtitle: 'English (US)',
    locale: 'en-US',
    pitch: 1.0,
    sampleText: 'In 350 meters, turn right onto King Street West.',
  ),
];

class VoiceSettings {
  final String selectedVoiceId;
  final bool voiceEnabled;
  final bool spokenStreetNames;
  final double speechRate;

  const VoiceSettings({
    this.selectedVoiceId = 'arctic_clear',
    this.voiceEnabled = true,
    this.spokenStreetNames = true,
    this.speechRate = 0.5,
  });

  VoicePreset get activePreset => kPolarVoicePresets.firstWhere(
        (v) => v.id == selectedVoiceId,
        orElse: () => kPolarVoicePresets.first,
      );

  VoiceSettings copyWith({
    String? selectedVoiceId,
    bool? voiceEnabled,
    bool? spokenStreetNames,
    double? speechRate,
  }) =>
      VoiceSettings(
        selectedVoiceId: selectedVoiceId ?? this.selectedVoiceId,
        voiceEnabled: voiceEnabled ?? this.voiceEnabled,
        spokenStreetNames: spokenStreetNames ?? this.spokenStreetNames,
        speechRate: speechRate ?? this.speechRate,
      );
}

class NavigationVoicesScreen extends StatefulWidget {
  final VoiceSettings initialSettings;
  final FlutterTts tts;

  const NavigationVoicesScreen({
    super.key,
    required this.initialSettings,
    required this.tts,
  });

  @override
  State<NavigationVoicesScreen> createState() => _NavigationVoicesScreenState();
}

class _NavigationVoicesScreenState extends State<NavigationVoicesScreen> {
  static const _royalBlue = Color(0xFF1E40AF);
  static const _deepRoyal = Color(0xFF172554);
  static const _powderBlue = Color(0xFFB0E0E6);
  static const _silver = Color(0xFFC0C0C0);
  static const _white = Color(0xFFFFFFFF);
  static const _iceSurface = Color(0xFFF4F9FC);

  late VoiceSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
  }

  Future<void> _previewVoice(VoicePreset preset) async {
    await widget.tts.stop();
    await widget.tts.setLanguage(preset.locale);
    await widget.tts.setPitch(preset.pitch);
    await widget.tts.setSpeechRate(_settings.speechRate);
    await widget.tts.speak(preset.sampleText);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _iceSurface,
      appBar: AppBar(
        backgroundColor: _royalBlue,
        foregroundColor: _white,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/icon/polar_travel_icon.png',
                width: 30,
                height: 30,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Navigation Voices',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _settings),
            child: const Text(
              'Save',
              style: TextStyle(
                color: _powderBlue,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'OFFLINE NAVIGATION VOICES',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: _deepRoyal,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          ...kPolarVoicePresets.map((preset) {
            final isActive = _settings.selectedVoiceId == preset.id;
            return Card(
              color: _white,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isActive ? _royalBlue : _silver,
                  width: isActive ? 2.0 : 1.2,
                ),
              ),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                title: Text(
                  '${preset.title} — ${preset.subtitle}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _deepRoyal,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isActive)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _powderBlue,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Active',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _deepRoyal,
                          ),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(
                        Icons.play_circle_outline,
                        color: _royalBlue,
                        size: 28,
                      ),
                      tooltip: 'Preview voice',
                      onPressed: () => _previewVoice(preset),
                    ),
                  ],
                ),
                onTap: () {
                  setState(() {
                    _settings =
                        _settings.copyWith(selectedVoiceId: preset.id);
                  });
                  _previewVoice(preset);
                },
              ),
            );
          }),
          const SizedBox(height: 14),
          const Text(
            'VOICE SETTINGS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: _deepRoyal,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          Card(
            color: _white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: _silver, width: 1.2),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  activeTrackColor: _royalBlue,
                  title: const Text(
                    'Voice Guidance Enabled',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _deepRoyal,
                    ),
                  ),
                  subtitle: const Text(
                    'Speak turn-by-turn alerts during active navigation',
                  ),
                  value: _settings.voiceEnabled,
                  onChanged: (val) => setState(
                    () => _settings = _settings.copyWith(voiceEnabled: val),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  activeTrackColor: _royalBlue,
                  title: const Text(
                    'Spoken Street Names',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _deepRoyal,
                    ),
                  ),
                  subtitle: const Text(
                    'Announce full street names (e.g. "onto King St W")',
                  ),
                  value: _settings.spokenStreetNames,
                  onChanged: (val) => setState(
                    () => _settings =
                        _settings.copyWith(spokenStreetNames: val),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Speech Speed (${(_settings.speechRate * 2).toStringAsFixed(1)}x)',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _deepRoyal,
                        ),
                      ),
                      Slider(
                        activeColor: _royalBlue,
                        min: 0.3,
                        max: 0.75,
                        value: _settings.speechRate,
                        onChanged: (val) => setState(
                          () =>
                              _settings = _settings.copyWith(speechRate: val),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
