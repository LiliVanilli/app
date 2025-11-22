import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:audioplayers/audioplayers.dart';
import '../model/mock_hr_sensor.dart';
import '../model/stress_detector.dart';
import 'stress_prompt_dialog.dart';
import '../widgets/hr_hrv_display.dart';

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
      _dialogShown = true;
      _showStressDialog();
    }
  }
  
  void _showStressDialog() {
    showPlatformDialog(
      context: context,
      builder: (context) => StressPromptDialog(
        currentHr: _currentHr,
        currentHrv: _currentHrv,
        onYes: () {
          Navigator.pop(context);
          _startMeditation();
        },
        onNo: () {
          Navigator.pop(context);
          _dialogShown = false;
        },
      ),
    );
  }
  
  void _startMeditation() async {
    setState(() {
      _hrBeforeMeditation = _currentHr;
      _hrvBeforeMeditation = _currentHrv;
      _isMeditating = true;
    });
    
    // Start audio playback
    try {
      await _audioPlayer.setSource(AssetSource('meditation_sound.mp3'));
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.resume();
      print('Audio started successfully');
    } catch (e) {
      print('Audio playback error: $e');
    }
    
    // Monitor for relaxation
    _checkRelaxation();
  }
  
  void _checkRelaxation() {
    if (!_isMeditating) return;
    
    Future.delayed(const Duration(seconds: 2), () {
      if (_detector.isRelaxed(_currentHr, _currentHrv)) {
        _stopMeditation();
      } else {
        _checkRelaxation();
      }
    });
  }
  
  void _stopMeditation() {
    setState(() {
      _isMeditating = false;
      _dialogShown = false;
    });
    
    // Stop audio playback
    _audioPlayer.stop();
    
    _showSuccessMessage();
  }
  
  void _showSuccessMessage() {
    showPlatformDialog(
      context: context,
      builder: (context) => PlatformAlertDialog(
        title: const Text('Well Done!'),
        content: Text(
          'You are feeling calmer now.\n\n'
          'Before: ${_hrBeforeMeditation.toStringAsFixed(0)} BPM, ${_hrvBeforeMeditation.toStringAsFixed(1)} ms HRV\n'
          'After: ${_currentHr.toStringAsFixed(0)} BPM, ${_currentHrv.toStringAsFixed(1)} ms HRV',
        ),
        actions: [
          PlatformDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: const Text('Meditation'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HrHrvDisplay(
                hr: _currentHr,
                hrv: _currentHrv,
                isStressed: _detector.isStressed(_currentHr, _currentHrv),
              ),
              const SizedBox(height: 24),
              
              if (_isMeditating) ...[
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Icon(Icons.self_improvement, size: 48),
                        SizedBox(height: 8),
                        Text(
                          'Meditation in progress...',
                          style: TextStyle(fontSize: 18),
                        ),
                        SizedBox(height: 8),
                        Text('Breathe in... breathe out...'),
                      ],
                    ),
                  ),
                ),
              ],
              
              const Spacer(),
              
              // Test buttons (for development)
              Text(
                'Development Controls',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _sensor.simulateStress(),
                      child: const Text('Simulate Stress'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _sensor.simulateRelaxation(),
                      child: const Text('Simulate Relaxation'),
                    ),
                  ),
                ],
              ),
              ElevatedButton(
                onPressed: () => _sensor.reset(),
                child: const Text('Reset to Baseline'),
              ),
            ],
          ),
        ),
      ),
    );
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
