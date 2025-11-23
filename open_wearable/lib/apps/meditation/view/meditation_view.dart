import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../model/mock_hr_sensor.dart';
import '../model/stress_detector.dart';
import 'stress_prompt_dialog.dart';
import 'snooze_dialog.dart';
import 'success_dialog.dart';
import '../widgets/hr_hrv_display_new.dart';
import '../widgets/breathing_animation.dart';

/// Main meditation view
/// 
/// Features:
/// - Real-time HR/HRV display
/// - Automatic stress detection
/// - Meditation session management
class MeditationView extends StatefulWidget {
  const MeditationView({super.key});
  
  @override
  State<MeditationView> createState() => _MeditationViewState();
}

class _MeditationViewState extends State<MeditationView> {
  final MockHrSensor _sensor = MockHrSensor();
  final StressDetector _detector = StressDetector();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  double _currentHr = 75.0;
  double _currentHrv = 40.0;
  double _hrBeforeMeditation = 75.0;
  double _hrvBeforeMeditation = 40.0;
  bool _isMeditating = false;
  bool _dialogShown = false;
  bool _wasStressedBeforeMeditation = false;
  
  StreamSubscription<double>? _hrSubscription;
  StreamSubscription<Map<String, double>>? _hrvSubscription;
  
  @override
  void initState() {
    super.initState();
    _startMonitoring();
  }
  
  void _startMonitoring() {
    _sensor.start();
    
    _hrSubscription = _sensor.hrStream.listen((hr) {
      setState(() {
        _currentHr = hr;
      });
      _checkStress();
      _checkRelaxationDuringMeditation();
    });
    
    _hrvSubscription = _sensor.hrvStream.listen((hrv) {
      setState(() {
        _currentHrv = hrv['HRV_RMSSD'] ?? 40.0;
      });
    });
  }
  
  void _checkStress() {
    if (_isMeditating || _dialogShown) return;
    
    if (_detector.isStressed(_currentHr, _currentHrv)) {
      _checkSnoozeAndShowDialog();
    }
  }
  
  void _checkRelaxationDuringMeditation() {
    if (!_isMeditating) return;
    
    final isRelaxed = _detector.isRelaxed(_currentHr, _currentHrv);
    
    // Debug output
    if (isRelaxed) {
      print('✅ Relaxed detected: HR=$_currentHr, HRV=$_currentHrv');
      print('   Was stressed before: $_wasStressedBeforeMeditation');
    }
    
    // Only auto-stop if person was stressed before meditation
    // This prevents auto-stopping when testing or when already relaxed
    if (!_wasStressedBeforeMeditation) {
      if (isRelaxed) {
        print('   ❌ Not auto-stopping (was not stressed before)');
      }
      return;
    }
    
    // Check if person has become relaxed during meditation
    if (isRelaxed) {
      print('   🎉 Auto-stopping meditation!');
      _stopMeditation();
    }
  }
  
  Future<void> _checkSnoozeAndShowDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final snoozeUntil = prefs.getInt('meditation_snooze_until') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    if (now >= snoozeUntil) {
      _dialogShown = true;
      _showStressDialog();
    }
  }
  
  void _showStressDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StressPromptDialog(
        currentHr: _currentHr,
        currentHrv: _currentHrv,
        onYes: () {
          Navigator.pop(context);
          _startMeditation();
        },
        onNo: () {
          Navigator.pop(context);
          _showSnoozeDialog();
        },
      ),
    );
  }
  
  void _showSnoozeDialog() {
    showDialog(
      context: context,
      builder: (context) => SnoozeDialog(
        onSnooze10Min: () => _setSnooze(10),
        onSnooze30Min: () => _setSnooze(30),
        onSnooze1Hour: () => _setSnooze(60),
        onSnoozeToday: () => _snoozeUntilEndOfDay(),
      ),
    );
  }
  
  Future<void> _setSnooze(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    final snoozeUntil = DateTime.now().add(Duration(minutes: minutes)).millisecondsSinceEpoch;
    await prefs.setInt('meditation_snooze_until', snoozeUntil);
    _dialogShown = false;
  }
  
  Future<void> _snoozeUntilEndOfDay() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);
    await prefs.setInt('meditation_snooze_until', endOfDay.millisecondsSinceEpoch);
    _dialogShown = false;
  }
  
  Future<void> _resetToBaseline() async {
    // Reset sensor to baseline values
    _sensor.reset();
    
    // Clear snooze timer so dialog can appear again
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('meditation_snooze_until');
    _dialogShown = false;
  }
  
  void _startMeditation() async {
    final wasStressed = _detector.isStressed(_currentHr, _currentHrv);
    
    setState(() {
      _hrBeforeMeditation = _currentHr;
      _hrvBeforeMeditation = _currentHrv;
      _isMeditating = true;
      // Remember if person was stressed when starting meditation
      _wasStressedBeforeMeditation = wasStressed;
    });
    
    print('🧘 Meditation started:');
    print('  HR: $_currentHr, HRV: $_currentHrv');
    print('  Was stressed: $wasStressed');
    
    // Start audio playback
    try {
      await _audioPlayer.setSource(AssetSource('meditation_sound.mp3'));
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.resume();
      print('Audio started successfully');
    } catch (e) {
      print('Audio playback error: $e');
    }
  }
  
  void _stopMeditation() {
    if (!_isMeditating) return;
    
    final bool isRelaxed = _detector.isRelaxed(_currentHr, _currentHrv);
    
    setState(() {
      _isMeditating = false;
      _dialogShown = false;
      _wasStressedBeforeMeditation = false; // Reset for next meditation
    });
    
    // Stop audio playback
    _audioPlayer.stop();
    
    // Show success dialog if actually relaxed
    if (isRelaxed) {
      // Wait for UI to update before showing dialog
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _showSuccessMessage();
        }
      });
    }
  }
  
  void _showSuccessMessage() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SuccessDialog(
        hrBefore: _hrBeforeMeditation,
        hrvBefore: _hrvBeforeMeditation,
        hrAfter: _currentHr,
        hrvAfter: _currentHrv,
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: const Text('Meditation'),
        material: (_, __) => MaterialAppBarData(
          backgroundColor: const Color(0xFF6366F1),
          foregroundColor: Colors.white,
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF5F3FF),
              Color(0xFFEDE9FE),
              Color(0xFFDDD6FE),
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    HrHrvDisplayNew(
                      hr: _currentHr,
                      hrv: _currentHrv,
                      stressLevel: _detector.getStressCategory(_currentHr, _currentHrv),
                    ),
                  const SizedBox(height: 24),
                  
                  if (_isMeditating) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: BreathingAnimation(isActive: _isMeditating),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _stopMeditation,
                        icon: const Icon(Icons.stop_circle_outlined, size: 20),
                        label: const Text('Stop Meditation'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF6366F1),
                          side: const BorderSide(color: Color(0xFF6366F1), width: 2),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 48), // Space for collapsed dev controls
                  ] else ...[
                    const Spacer(),
                  ],
                  
                  if (!_isMeditating) const Spacer(),
                  
                  // Development Controls (only show when NOT meditating)
                  if (!_isMeditating) ...[
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _sensor.simulateStress(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange[100],
                              foregroundColor: Colors.orange[900],
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Simulate Stress'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _resetToBaseline,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[200],
                              foregroundColor: Colors.grey[800],
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Reset'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
            // Overlay Dev Controls for meditation mode
            if (_isMeditating)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      title: Text(
                        'Dev Controls',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      initiallyExpanded: false,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              // Just simulate relaxation, let the user see the values go down
                              _sensor.simulateRelaxation();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[100],
                              foregroundColor: Colors.green[900],
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Simulate Relax'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),);
  }
  
  @override
  void dispose() {
    _hrSubscription?.cancel();
    _hrvSubscription?.cancel();
    _sensor.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
}
