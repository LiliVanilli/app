import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:logger/logger.dart';
import 'hr_sensor_interface.dart';
import 'improved_meditation_llm_service.dart';
import 'meditation_voice_service.dart';
import 'meditation_config.dart';
import 'user_account.dart';
import 'personalized_stress_detector.dart';
import 'meditation_history.dart';
import 'activity_detector.dart';

final _logger = Logger();

enum MeditationState {
  idle,
  measuringBaseline,
  generatingContent,
  speaking,
  waitingForBiosignals,
  paused,
  completed,
  error,
}

/// Main controller for adaptive meditation sessions
/// 
/// Manages the complete meditation flow including:
/// - Real-time biosignal monitoring (HR/HRV)
/// - Personalized stress detection with activity recognition
/// - LLM-generated meditation content
/// - Text-to-speech guidance
/// - Background music playback
/// - Session analytics and history tracking
class ImprovedMeditationController {
  final HrSensorInterface sensor;
  final ImprovedMeditationLLMService llmService;
  final MeditationVoiceService voiceService;
  final AudioPlayer backgroundMusicPlayer = AudioPlayer();
  final UserAccount userAccount;
  late PersonalizedStressDetector stressDetector;
  late ActivityDetector activityDetector;
  
  // State
  MeditationState _state = MeditationState.idle;
  MeditationState get state => _state;
  bool _isPaused = false;
  
  // Biosignal data
  double _baselineHr = 75.0;
  double _baselineHrv = 50.0;
  double _currentHr = 75.0;
  double _currentHrv = 50.0;
  
  // Calibration state
  bool _isCalibrating = true;
  DateTime? _calibrationStartTime;
  List<double> _hrMeasurements = [];
  List<double> _hrvMeasurements = [];
  static const int _calibrationDurationSeconds = 30; // 30 seconds for initial calibration
  
  // Session tracking
  int _iterationCount = 0;
  DateTime? _sessionStartTime;
  bool _isBaselineReady = false;
  double _peakStressLevel = 0.0;
  Timer? _sessionTimer;
  
  // Monitoring
  Timer? _stressMonitorTimer;
  bool _isMonitoringStress = false;
  bool _meditationAutoStarted = false;
  
  // Subscriptions
  StreamSubscription<double>? _hrSubscription;
  StreamSubscription<Map<String, double>>? _hrvSubscription;
  
  // Callbacks
  final void Function(MeditationState state)? onStateChanged;
  final void Function(String message)? onStatusMessage;
  final void Function(double hr, double hrv)? onBiosignalUpdate;
  final void Function()? onSessionComplete;
  final void Function(bool isStressed)? onStressDetected;
  final void Function(int currentSegment, int estimatedTotal)? onSegmentUpdate;
  final void Function(Duration elapsed)? onTimerUpdate;
  
  ImprovedMeditationController({
    required this.sensor,
    required this.llmService,
    required this.voiceService,
    required this.userAccount,
    this.onStateChanged,
    this.onStatusMessage,
    this.onBiosignalUpdate,
    this.onSessionComplete,
    this.onStressDetected,
    this.onSegmentUpdate,
    this.onTimerUpdate,
  }) {
    stressDetector = PersonalizedStressDetector(userAccount: userAccount);
    activityDetector = ActivityDetector();
    llmService.setUserAccount(userAccount);
  }
  
  void _setState(MeditationState newState) {
    _state = newState;
    onStateChanged?.call(newState);
    _logger.i('State: $newState');
  }
  
  void _sendStatus(String message) {
    onStatusMessage?.call(message);
    _logger.i('Status: $message');
  }
  
  /// Start meditation session
  Future<void> startSession() async {
    // Prevent starting if already active
    if (_state != MeditationState.idle) {
      _logger.w('Cannot start session - already in progress (state: $_state)');
      return;
    }
    
    try {
      _logger.i('Starting meditation session');
      _sessionStartTime = DateTime.now();
      _iterationCount = 0;
      _isBaselineReady = false;
      _meditationAutoStarted = false;
      _peakStressLevel = 0.0;
      _isPaused = false;
      
      llmService.startNewSession();
      
      // Start environment-based background ambience
      await _playBackgroundAmbience();
      
      // Subscribe to biosignals
      _subscribeToSensor();
      
      // Start session timer
      _startSessionTimer();
      
      // Measure baseline
      await _measureBaseline();
      
      // Generate welcome
      _setState(MeditationState.generatingContent);
      final welcomeText = await llmService.generatePersonalizedWelcome(
        currentHr: _currentHr,
        currentHrv: _currentHrv,
        baselineHr: _baselineHr,
        baselineHrv: _baselineHrv,
      );
      
      await _speak(welcomeText);
      
      // Start adaptive loop
      await _adaptiveLoop();
      
    } catch (e) {
      _logger.e('Error starting session: $e');
      _setState(MeditationState.error);
      _sendStatus('Error: $e');
    }
  }
  
  void _subscribeToSensor() {
    _hrSubscription = sensor.hrStream.listen((hr) {
      _currentHr = hr;
      _refineBaselineDuringCalibration(); // Adaptively refine baseline during first 30s
      onBiosignalUpdate?.call(_currentHr, _currentHrv);
    });
    
    _hrvSubscription = sensor.hrvStream.listen((hrvData) {
      _currentHrv = hrvData['HRV_RMSSD'] ?? hrvData['rmssd'] ?? hrvData['RMSSD'] ?? _currentHrv;
      _refineBaselineDuringCalibration(); // Adaptively refine baseline during first 30s
      onBiosignalUpdate?.call(_currentHr, _currentHrv);
    });
  }
  
  Future<void> _measureBaseline() async {
    _setState(MeditationState.measuringBaseline);
    
    // Start with research-based baseline immediately (no wait!)
    final researchBaseline = stressDetector.getResearchBaselines();
    _baselineHr = researchBaseline['baselineHr']!;
    _baselineHrv = researchBaseline['baselineHrv']!;
    
    _logger.i('📊 Starting with research baseline: HR=${_baselineHr.toStringAsFixed(1)}, HRV=${_baselineHrv.toStringAsFixed(1)}');
    _logger.i('   Based on: ${userAccount.age}y, ${userAccount.gender}, ${userAccount.fitnessLevel}');
    
    // Start calibration period
    _isCalibrating = true;
    _calibrationStartTime = DateTime.now();
    _hrMeasurements.clear();
    _hrvMeasurements.clear();
    
    _sendStatus('Starting meditation...');
    
    // Mark baseline as ready immediately - we can start right away!
    _isBaselineReady = true;
    
    // No delay - start meditation immediately with research baseline
  }
  
  /// Refine baseline during calibration period using live measurements
  void _refineBaselineDuringCalibration() {
    if (!_isCalibrating || _calibrationStartTime == null) return;
    
    // Collect current measurements
    if (_currentHr > 0) _hrMeasurements.add(_currentHr);
    if (_currentHrv > 0) _hrvMeasurements.add(_currentHrv);
    
    final elapsed = DateTime.now().difference(_calibrationStartTime!).inSeconds;
    
    // Check if calibration period is over
    if (elapsed >= _calibrationDurationSeconds) {
      _finishCalibration();
      return;
    }
    
    // Adaptive refinement during calibration
    if (_hrMeasurements.isEmpty || _hrvMeasurements.isEmpty) return;
    
    // Calculate measured average
    final measuredHr = _hrMeasurements.reduce((a, b) => a + b) / _hrMeasurements.length;
    final measuredHrv = _hrvMeasurements.reduce((a, b) => a + b) / _hrvMeasurements.length;
    
    // Get research baseline
    final researchBaseline = stressDetector.getResearchBaselines();
    final researchHr = researchBaseline['baselineHr']!;
    final researchHrv = researchBaseline['baselineHrv']!;
    
    // Weighted average: gradually trust measured values more over time
    // 0-10s: 80% research, 20% measured
    // 10-20s: 60% research, 40% measured  
    // 20-30s: 40% research, 60% measured
    final researchWeight = 1.0 - (elapsed / _calibrationDurationSeconds * 0.6);
    final measuredWeight = 1.0 - researchWeight;
    
    _baselineHr = (researchHr * researchWeight) + (measuredHr * measuredWeight);
    _baselineHrv = (researchHrv * researchWeight) + (measuredHrv * measuredWeight);
  }
  
  /// Complete calibration and finalize baseline
  void _finishCalibration() {
    if (!_isCalibrating) return;
    
    _isCalibrating = false;
    
    if (_hrMeasurements.length >= 5 && _hrvMeasurements.length >= 5) {
      // Use measured values with slight research influence
      final measuredHr = _hrMeasurements.reduce((a, b) => a + b) / _hrMeasurements.length;
      final measuredHrv = _hrvMeasurements.reduce((a, b) => a + b) / _hrvMeasurements.length;
      
      final researchBaseline = stressDetector.getResearchBaselines();
      _baselineHr = (measuredHr * 0.7) + (researchBaseline['baselineHr']! * 0.3);
      _baselineHrv = (measuredHrv * 0.7) + (researchBaseline['baselineHrv']! * 0.3);
      
      _logger.i('✓ Calibration complete! Refined baseline: HR=${_baselineHr.toStringAsFixed(1)}, HRV=${_baselineHrv.toStringAsFixed(1)}');
      _logger.i('  Collected ${_hrMeasurements.length} HR and ${_hrvMeasurements.length} HRV measurements');
    } else {
      _logger.i('✓ Calibration complete (keeping research baseline - insufficient measurements)');
    }
    
    _sendStatus('Meditation in progress...');
  }
  
  Future<void> _adaptiveLoop() async {
    const maxIterations = 10;
    
    while (_iterationCount < maxIterations && _state != MeditationState.idle && _state != MeditationState.completed) {
      if (_isPaused) {
        await Future.delayed(const Duration(seconds: 1));
        continue;
      }
      
      _iterationCount++;
      
      // Notify about segment progress
      onSegmentUpdate?.call(_iterationCount, maxIterations);
      
      _setState(MeditationState.waitingForBiosignals);
      
      // Check relaxation status multiple times during waiting period
      // This allows faster session completion if user becomes relaxed
      for (int i = 0; i < 3; i++) {
        await Future.delayed(const Duration(seconds: 1));
        
        if (_state == MeditationState.idle) break; // User stopped
        
        // Get activity level if available
        ActivityLevel? activityLevel;
        try {
          final dynamic dynamicSensor = sensor;
          activityLevel = dynamicSensor.activityLevel as ActivityLevel?;
        } catch (e) {
          // Sensor doesn't support activity detection - that's OK
        }
        
        // Check if ready to end (relaxed) - check every second!
        if (_iterationCount >= 2 && stressDetector.isReadyToEndSession(
            startHr: _baselineHr,
            startHrv: _baselineHrv,
            currentHr: _currentHr,
            currentHrv: _currentHrv,
            iterationCount: _iterationCount
        )) {
          final reason = stressDetector.getEndSessionReason(
            startHr: _baselineHr,
            startHrv: _baselineHrv,
            currentHr: _currentHr,
            currentHrv: _currentHrv,
          );
          _logger.i('✓ Session complete (during waiting): $reason');
          await _completeSession();
          return;
        }
      }
      
      if (_state == MeditationState.idle) break; // User stopped
      
      // Get activity level if available
      ActivityLevel? activityLevel;
      try {
        final dynamic dynamicSensor = sensor;
        activityLevel = dynamicSensor.activityLevel as ActivityLevel?;
      } catch (e) {
        // Sensor doesn't support activity detection - that's OK
      }
      
      // Check stress with personalized detector (activity-aware)
      final stressLevel = stressDetector.getStressLevel(_currentHr, _currentHrv, activityLevel: activityLevel);
      final isNowRelaxed = stressDetector.isRelaxed(_currentHr, _currentHrv);
      _peakStressLevel = stressLevel > _peakStressLevel ? stressLevel : _peakStressLevel;
      
      final readyToEnd = stressDetector.isReadyToEndSession(
        startHr: _baselineHr,
        startHrv: _baselineHrv,
        currentHr: _currentHr,
        currentHrv: _currentHrv,
        iterationCount: _iterationCount,
      );

      final hrChange = ((_baselineHr - _currentHr) / _baselineHr * 100);
      final hrvChange = ((_currentHrv - _baselineHrv) / _baselineHrv * 100);
      
      _logger.i('Iteration $_iterationCount: Stress=${stressLevel.toStringAsFixed(1)}%, '
                'Relaxed=$isNowRelaxed, HR change=${hrChange.toStringAsFixed(1)}%, '
                'HRV change=${hrvChange.toStringAsFixed(1)}%, Ready=$readyToEnd');
      
      if (readyToEnd) {
        final reason = stressDetector.getEndSessionReason(
          startHr: _baselineHr,
          startHrv: _baselineHrv,
          currentHr: _currentHr,
          currentHrv: _currentHrv,
        );
        _logger.i('✓ Session complete: $reason');
        await _completeSession();
        return;
      }
      
      // Generate next segment
      _setState(MeditationState.generatingContent);
      _sendStatus('Creating personalized guidance...');
      
      try {
        final segment = await llmService.generateMeditationSegment(
          currentHr: _currentHr,
          currentHrv: _currentHrv,
          baselineHr: _baselineHr,
          baselineHrv: _baselineHrv,
          isStressed: true,
          stressLevel: stressLevel,
        );
        
        if (_state == MeditationState.idle) break; // User stopped
        
        await _speak(segment);
        
        if (_state == MeditationState.idle) break; // User stopped
        
        // Check again after speaking - person might have relaxed during the segment
        if (_iterationCount >= 3 && stressDetector.isReadyToEndSession(
            startHr: _baselineHr, 
            startHrv: _baselineHrv, 
            currentHr: _currentHr, 
            currentHrv: _currentHrv, 
            iterationCount: _iterationCount
        )) {
             final reason = stressDetector.getEndSessionReason(
               startHr: _baselineHr,
               startHrv: _baselineHrv,
               currentHr: _currentHr,
               currentHrv: _currentHrv,
             );
             _logger.i('✓ Session complete after segment: $reason');
             await _completeSession();
             return;
        }

        await Future.delayed(const Duration(seconds: 3));
        
      } catch (e) {
        _logger.e('Error in loop: $e');
      }
    }
    
    if (_state != MeditationState.idle) {
      await _completeSession();
    }
  }
  
  Future<void> _speak(String text) async {
    if (_state == MeditationState.idle) return;
    
    _setState(MeditationState.speaking);
    _sendStatus('Guiding you...');
    
    // Lower background ambience during speech
    try {
      await backgroundMusicPlayer.setVolume(0.08); // Very quiet during voice (8%)
    } catch (e) {
      // Ignore if not playing
    }
    
    try {
      bool wasCancelled = false;
      final speakFuture = voiceService.speak(text);
      
      // Check every 200ms if we should stop
      final checkTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
        // Stop immediately if session ended or user relaxed
        final shouldEnd = _state == MeditationState.idle || 
            (_iterationCount >= 2 && stressDetector.isReadyToEndSession(
              startHr: _baselineHr,
              startHrv: _baselineHrv,
              currentHr: _currentHr,
              currentHrv: _currentHrv,
              iterationCount: _iterationCount
            ));
            
        if (shouldEnd) {
          wasCancelled = true;
          await voiceService.stop();
          timer.cancel();
          _logger.i('🛑 CANCELLED SPEAKING - iteration=$_iterationCount, state=$_state, isReadyToEnd=${stressDetector.isReadyToEndSession(
            startHr: _baselineHr,
            startHrv: _baselineHrv,
            currentHr: _currentHr,
            currentHrv: _currentHrv,
            iterationCount: _iterationCount
          )}');
        }
      });
      
      // Wait for speaking to complete or be cancelled
      await speakFuture;
      checkTimer.cancel();
      
      // If cancelled due to relaxation, SET STATE TO IDLE and complete session
      if (wasCancelled) {
        _logger.i('✓ Session cancelled during speech - completing now');
        _setState(MeditationState.idle); // STOP THE LOOP!
        if (_iterationCount >= 2) {
          await _completeSession();
        }
        return; // Exit immediately
      }
    } catch (e) {
      _logger.e('Speech error: $e');
    }
    
    // Restore ambience volume after speech
    try {
      await backgroundMusicPlayer.setVolume(0.15); // Back to 15%
    } catch (e) {
      // Ignore if not playing
    }
  }
  
  Future<void> _completeSession() async {
    if (_state == MeditationState.completed || _state == MeditationState.idle) return;
    
    _setState(MeditationState.generatingContent);
    
    try {
      final completionText = await llmService.generateCompletionText(
        startHr: _baselineHr,
        startHrv: _baselineHrv,
        endHr: _currentHr,
        endHrv: _currentHrv,
      );
      await _speak(completionText);
    } catch (e) {
      _logger.e('Completion error: $e');
    }
    
    // Stop audio
    await voiceService.stop();
    await backgroundMusicPlayer.stop();
    
    // Save to history
    final duration = DateTime.now().difference(_sessionStartTime!).inSeconds;
    await MeditationHistory.instance.addSession(
      userId: userAccount.userId,
      startHr: _baselineHr,
      startHrv: _baselineHrv,
      endHr: _currentHr,
      endHrv: _currentHrv,
      durationSeconds: duration,
      iterationCount: _iterationCount,
      peakStressLevel: _peakStressLevel,
    );
    
    _setState(MeditationState.completed);
    _sendStatus('Session complete!');
    _meditationAutoStarted = false;
    
    onSessionComplete?.call();
  }
  
  /// Stop session - PROPERLY
  Future<void> stopSession() async {
    _logger.i('Stopping session');
    
    // Set state first
    _setState(MeditationState.idle);
    _isPaused = false;
    _meditationAutoStarted = false;
    
    // Stop everything
    await voiceService.stop();
    await backgroundMusicPlayer.stop();
    
    _hrSubscription?.cancel();
    _hrvSubscription?.cancel();
    
    _logger.i('Session stopped');
  }
  
  /// Pause session - PROPERLY  
  Future<void> pauseSession() async {
    if (_state == MeditationState.idle) return;
    
    _logger.i('Pausing session');
    _isPaused = true;
    _setState(MeditationState.paused);
    
    await voiceService.pause();
    await backgroundMusicPlayer.pause();
  }
  
  /// Resume session
  Future<void> resumeSession() async {
    if (!_isPaused) return;
    
    _logger.i('Resuming session');
    _isPaused = false;
    _setState(MeditationState.speaking);
    
    await voiceService.resume();
    await backgroundMusicPlayer.resume();
  }
  
  /// Start monitoring
  void startMonitoring() {
    if (_isMonitoringStress) return;
    
    _logger.i('Starting stress monitoring');
    _isMonitoringStress = true;
    _subscribeToSensor();
    
    // Use research-based baseline immediately
    final researchBaseline = stressDetector.getResearchBaselines();
    _baselineHr = researchBaseline['baselineHr']!;
    _baselineHrv = researchBaseline['baselineHrv']!;
    _isBaselineReady = true;
    
    _logger.i('📊 Using research baseline: HR=${_baselineHr.toStringAsFixed(1)} BPM, HRV=${_baselineHrv.toStringAsFixed(1)} ms');
    _logger.i('   Profile: ${userAccount.age}y ${userAccount.gender}, ${userAccount.fitnessLevel} fitness');
    
    // Refine with measured values after 30 seconds
    Future.delayed(Duration(seconds: 30), () {
      if (_currentHr > 40 && _currentHrv > 10) {
        // Weighted average: 60% measured + 40% research
        _baselineHr = (_currentHr * 0.6) + (_baselineHr * 0.4);
        _baselineHrv = (_currentHrv * 0.6) + (_baselineHrv * 0.4);
        _logger.i('✓ Baseline refined with measurements: HR=${_baselineHr.toStringAsFixed(1)}, HRV=${_baselineHrv.toStringAsFixed(1)}');
      }
    });
    
    // Check stress periodically (faster checks for testing)
    _stressMonitorTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_isBaselineReady || _state != MeditationState.idle) return;
      
      // Get activity level from sensor (if available)
      ActivityLevel? activityLevel;
      if (sensor is HrSensorInterface) {
        // Try to get activity level if sensor supports it
        try {
          final dynamic dynamicSensor = sensor;
          activityLevel = dynamicSensor.activityLevel as ActivityLevel?;
        } catch (e) {
          // Sensor doesn't support activity detection - that's OK
        }
      }
      
      final isStressed = stressDetector.isStressed(_currentHr, _currentHrv, activityLevel: activityLevel);
      final stressLevel = stressDetector.getStressLevel(_currentHr, _currentHrv, activityLevel: activityLevel);
      
      _logger.i('Periodic stress check: HR=$_currentHr, HRV=$_currentHrv, activity=${activityLevel?.name ?? "unknown"}, stressed=$isStressed, level=${stressLevel.toStringAsFixed(1)}%');
      onStressDetected?.call(isStressed);
      
      if (isStressed && !_meditationAutoStarted) {
        _meditationAutoStarted = true;
        _sendStatus('Stress detected');
      } else if (!isStressed && _meditationAutoStarted) {
        _meditationAutoStarted = false;
      }
    });
  }
  
  void stopMonitoring() {
    _stressMonitorTimer?.cancel();
    _isMonitoringStress = false;
  }
  
  Map<String, dynamic> getCurrentBiosignals() {
    int? calibrationProgress;
    if (_isCalibrating && _calibrationStartTime != null) {
      final elapsed = DateTime.now().difference(_calibrationStartTime!).inSeconds;
      calibrationProgress = ((elapsed / _calibrationDurationSeconds) * 100).clamp(0, 100).toInt();
    }
    
    return {
      'currentHr': _currentHr,
      'currentHrv': _currentHrv,
      'baselineHr': _baselineHr,
      'baselineHrv': _baselineHrv,
      'isCalibrating': _isCalibrating,
      'calibrationProgress': calibrationProgress,
      'calibrationMeasurements': _hrMeasurements.length,
    };
  }
  
  void _startSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_sessionStartTime != null && _state != MeditationState.idle) {
        final elapsed = DateTime.now().difference(_sessionStartTime!);
        onTimerUpdate?.call(elapsed);
      }
    });
  }
  
  /// Play background ambience based on user's environment preference
  Future<void> _playBackgroundAmbience() async {
    String? audioFile;
    try {
      final environment = userAccount.preferredEnvironment.toLowerCase();
      
      // Map environment preference to audio file
      if (environment.contains('ocean') || environment.contains('beach')) {
        audioFile = 'Ocean_Beach.wav';
      } else if (environment.contains('mountain')) {
        audioFile = 'Mountain.wav';
      } else if (environment.contains('forest')) {
        audioFile = 'Forest.wav';
      } else if (environment.contains('garden')) {
        audioFile = 'Garden.mp3';
      } else if (environment.contains('nature')) {
        audioFile = 'Peaceful_Nature.wav';
      }
      
      if (audioFile != null) {
        _logger.i('🎵 Attempting to play: $audioFile');
        await backgroundMusicPlayer.setReleaseMode(ReleaseMode.loop);
        await backgroundMusicPlayer.setVolume(0.15); // Quiet background (15% volume)
        // Note: AssetSource automatically ensures the path is correct for Flutter assets
        // depending on configuration. Since files are in root assets/, we pass just the filename
        // and AssetSource adds 'assets/' prefix by default.
        await backgroundMusicPlayer.play(AssetSource(audioFile));
        _logger.i('Background ambience playing at 15% volume');
      } else {
        _logger.w('No specific audio file for environment: $environment. Using default.');
        // Fallback to default meditation sound if available
        try {
           audioFile = 'meditation_sound.mp3';
           await backgroundMusicPlayer.setReleaseMode(ReleaseMode.loop);
           await backgroundMusicPlayer.setVolume(0.15);
           await backgroundMusicPlayer.play(AssetSource(audioFile));
        } catch (e) {
           _logger.w('Default background sound failed: $e');
        }
      }
    } catch (e) {
      _logger.e('Background ambience failed: $e');
      _logger.e('Tried to play: $audioFile');
    }
  }
  
  Future<void> dispose() async {
    _stressMonitorTimer?.cancel();
    _sessionTimer?.cancel();
    await stopSession();
    await voiceService.dispose();
    await backgroundMusicPlayer.dispose();
    llmService.dispose();
  }
}

