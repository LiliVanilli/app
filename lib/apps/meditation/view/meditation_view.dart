import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import '../model/mock_hr_sensor.dart';
import '../model/earable_hr_sensor.dart';
import '../model/hr_sensor_interface.dart';
import '../model/stress_detector.dart';
import '../model/activity_detector.dart';
import '../widgets/hr_hrv_display_new.dart';
import '../widgets/hr_hrv_chart.dart';
import '../widgets/llm_meditation_widget.dart';
import '../model/user_account.dart';
import '../widgets/user_onboarding_screen.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';

class MeditationView extends StatefulWidget {
  final Sensor? ppgSensor;
  final SensorConfigurationProvider? sensorConfigProvider;
  final SensorManager sensorManager;
  
  const MeditationView({
    super.key,
    this.ppgSensor,
    this.sensorConfigProvider,
    required this.sensorManager,
  });
  
  @override
  State<MeditationView> createState() => _MeditationViewState();
}

class _MeditationViewState extends State<MeditationView> {
  HrSensorInterface? _sensor;
  bool _useMockSensor = true;
  final StressDetector _stressDetector = StressDetector();
  final GlobalKey<LlmMeditationWidgetState> _meditationWidgetKey = GlobalKey<LlmMeditationWidgetState>();
  
  double _currentHr = 75.0;
  double _currentHrv = -1.0; // -1 means no data yet (RMSSD)
  double _currentSdnn = -1.0; // -1 means no data yet (SDNN - comparable to Apple Health)
  bool _hrvIsStable = false; // Track if HRV measurements are reliable
  int _hrvMeasurementCount = 0; // Count HRV measurements received
  int _measurementDurationSeconds = 0; // Track how long we've been measuring
  Timer? _measurementTimer; // Timer to track measurement duration
  
  StreamSubscription<double>? _hrSubscription;
  StreamSubscription<Map<String, double>>? _hrvSubscription;
  
  @override
  void initState() {
    super.initState();
    _initializeSensor();
  }
  
  void _initializeSensor() {
    // Always start with mock sensor
    // User can manually switch to earable by pressing "Use Earable" button
    print('Starting with mock sensor');
    _sensor = MockHrSensor();
    _useMockSensor = true;
    _startMonitoring();
  }
  
  void _switchToEarableSensor() {
    if (widget.ppgSensor == null) {
      _showErrorDialog('No earable device connected. Please connect an OpenEarable device first.');
      return;
    }
    
    print('Switching to earable sensor...');
    
    // Stop current sensor
    _hrSubscription?.cancel();
    _hrvSubscription?.cancel();
    _sensor?.dispose();
    
    // WICHTIG: Sensor-Konfiguration setzen, wie die Heart Tracker App es macht!
    final sensor = widget.ppgSensor!;
    final configProvider = widget.sensorConfigProvider;
    
    if (configProvider != null) {
      SensorConfiguration configuration = sensor.relatedConfigurations.first;

      // Stream-Option aktivieren
      if (configuration is ConfigurableSensorConfiguration &&
          configuration.availableOptions.contains(StreamSensorConfigOption())) {
        configProvider.addSensorConfigurationOption(configuration, StreamSensorConfigOption());
        print('Added stream configuration option');
      }

      // Konfiguration setzen
      List<SensorConfigurationValue> values = configProvider.getSensorConfigurationValues(configuration, distinct: true);
      configProvider.addSensorConfiguration(configuration, values.first);
      SensorConfigurationValue selectedValue = configProvider.getSelectedConfigurationValue(configuration)!;
      
      // KRITISCH: Sensor konfigurieren!
      configuration.setConfiguration(selectedValue);
      print('Set sensor configuration: $selectedValue');
    }
    
    // Get sample frequency from sensor configuration
    double sampleFreq = 84.0; // Default to 84 Hz for PPG
    if (widget.sensorConfigProvider != null) {
      for (final config in widget.ppgSensor!.relatedConfigurations) {
        final value = widget.sensorConfigProvider!.getSelectedConfigurationValue(config);
        if (value is SensorFrequencyConfigurationValue) {
          sampleFreq = value.frequencyHz;
          print('Using sample frequency: $sampleFreq Hz');
          break;
        }
      }
    }
    
    // Create real sensor
    _sensor = EarableHrSensor(
      ppgSensor: widget.ppgSensor!,
      sensorManager: widget.sensorManager,
      sampleFreq: sampleFreq,
    );
    
    setState(() {
      _useMockSensor = false;
    });
    
    // Restart monitoring with real sensor
    _startMonitoring();
    
    print('Switched to earable sensor! _useMockSensor = $_useMockSensor');
    
    // Show success message only if widget is still mounted
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showSuccessSnackbar('Now using real earable data!');
        }
      });
    }
  }
  
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => PlatformAlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          PlatformDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
  
  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }
  
  void _openLiveChart() {
    if (_sensor == null) return;
    
    // Get history from sensor if it's an EarableHrSensor
    List<double> hrHistory = [];
    List<double> hrvHistory = [];
    if (_sensor is EarableHrSensor) {
      hrHistory = (_sensor as EarableHrSensor).hrHistory;
      hrvHistory = (_sensor as EarableHrSensor).hrvHistory;
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HrHrvChart(
          hrStream: _sensor!.hrStream,
          hrvStream: _sensor!.hrvStream,
          initialHrData: hrHistory,
          initialHrvData: hrvHistory,
          measurementDurationSeconds: _measurementDurationSeconds,
        ),
      ),
    );
  }
  
  void _startMonitoring() {
    if (_sensor == null) return;
    
    _sensor!.start();
    
    // Reset stability tracking when starting new sensor
    setState(() {
      _hrvIsStable = _useMockSensor; // Mock sensor is always stable
      _hrvMeasurementCount = 0;
      _measurementDurationSeconds = 0;
    });
    
    // Start timer to track measurement duration
    _measurementTimer?.cancel();
    _measurementTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _measurementDurationSeconds++;
      });
    });
    
    _hrSubscription = _sensor!.hrStream.listen((hr) {
      setState(() {
        _currentHr = hr;
      });
    });
    
    _hrvSubscription = _sensor!.hrvStream.listen((hrv) {
      setState(() {
        _currentHrv = hrv['HRV_RMSSD'] ?? 40.0;
        _currentSdnn = hrv['HRV_SDNN'] ?? 40.0;
        _hrvMeasurementCount++;
        
        // HRV becomes stable after receiving 3 measurements
        // (which means ~30+ RR intervals collected)
        if (!_hrvIsStable && _hrvMeasurementCount >= 3 && !_useMockSensor) {
          _hrvIsStable = true;
          print('HRV measurements now stable ($_hrvMeasurementCount measurements)');
        }
      });
    });
  }
  

  
  void _simulateStress() {
    if (_sensor is MockHrSensor) {
      (_sensor as MockHrSensor).simulateStress();
      print('Simulating stress: HR -> 100 BPM, HRV -> 12 ms (triggers stress detection!)');
      _showSuccessSnackbar('Simulating stress: HR↑100, HRV↓12ms');
    }
  }
  
  void _simulateRelaxation() {
    if (_sensor is MockHrSensor) {
      (_sensor as MockHrSensor).simulateRelaxation();
      print('Simulating relaxation: HR -> 65 BPM, HRV -> 150 ms');
      _showSuccessSnackbar('Simulating relaxation...');
    }
  }
  
  Future<void> _resetToBaseline() async {
    print('Resetting to baseline...');
    
    // Reset meditation widget state (clears timers)
    _meditationWidgetKey.currentState?.resetMeditation();
    
    // Stop current sensor
    _hrSubscription?.cancel();
    _hrvSubscription?.cancel();
    _sensor?.dispose();
    
    // Reset to mock sensor
    _sensor = MockHrSensor();
    
    setState(() {
      _useMockSensor = true;
    });
    
    // Restart monitoring with mock sensor
    _startMonitoring();
    
    // Clear snooze and meditation timers from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('meditation_snooze_until');
    await prefs.remove('meditation_last_completion');
    await prefs.remove('meditation_scheduled_time');
    
    print('Reset complete! Back to mock sensor. _useMockSensor = $_useMockSensor');
    _showSuccessSnackbar('Reset to baseline (HR: 75, HRV: 120) and cleared all timers');
  }
  
  String _getActivityDescription(ActivityLevel level) {
    switch (level) {
      case ActivityLevel.resting:
        return '🧘 Resting (sitting/standing)';
      case ActivityLevel.light:
        return '🚶 Light movement (slow walking)';
      case ActivityLevel.moderate:
        return '🏃 Moderate activity (brisk walking)';
      case ActivityLevel.vigorous:
        return '💪 Vigorous exercise (running)';
      case ActivityLevel.intense:
        return '⚡ Intense exercise (sprinting)';
    }
  }
  
  Widget _buildDebugInfo() {
    String activityLevel = 'unknown';
    String activityDescription = 'Sensor does not support activity detection';
    
    if (_sensor is EarableHrSensor) {
      final earableSensor = _sensor as EarableHrSensor;
      activityLevel = earableSensor.activityLevel.name;
      
      switch (earableSensor.activityLevel) {
        case ActivityLevel.resting:
          activityDescription = 'Still (sitting/standing)';
          break;
        case ActivityLevel.light:
          activityDescription = 'Light movement (slow walking)';
          break;
        case ActivityLevel.moderate:
          activityDescription = 'Moderate activity (brisk walking)';
          break;
        case ActivityLevel.vigorous:
          activityDescription = 'Vigorous exercise (running)';
          break;
        case ActivityLevel.intense:
          activityDescription = 'Intense exercise (sprinting)';
          break;
      }
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.directions_run, size: 16, color: Colors.blueGrey[700]),
            SizedBox(width: 4),
            Text('Activity: ', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('$activityLevel'),
          ],
        ),
        Text('  $activityDescription', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.favorite, size: 16, color: Colors.red[300]),
            SizedBox(width: 4),
            Text('HR: ', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('${_currentHr.toStringAsFixed(1)} BPM'),
          ],
        ),
        SizedBox(height: 4),
        Row(
          children: [
            Icon(Icons.show_chart, size: 16, color: Colors.blue[300]),
            SizedBox(width: 4),
            Text('HRV (RMSSD): ', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(_currentHrv > 0 ? '${_currentHrv.toStringAsFixed(1)} ms' : 'measuring...'),
          ],
        ),
        if (_currentSdnn > 0) ...[
          SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.timeline, size: 16, color: Colors.green[300]),
              SizedBox(width: 4),
              Text('HRV (SDNN): ', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('${_currentSdnn.toStringAsFixed(1)} ms'),
            ],
          ),
        ],
        SizedBox(height: 8),
        Text('Measurement: ${_measurementDurationSeconds}s', 
             style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        if (_currentHrv > 0 && _currentHr > 40) ...[
          SizedBox(height: 4),
          Text('HRV is ${_hrvIsStable ? "STABLE" : "COLLECTING"} ($_hrvMeasurementCount readings)',
               style: TextStyle(fontSize: 12, 
                              color: _hrvIsStable ? Colors.green[700] : Colors.orange[700],
                              fontWeight: FontWeight.bold)),
        ],
      ],
    );
  }
  
  Future<void> _openProfileSettings() async {
    // Load current UserAccount
    final currentAccount = await UserAccount.load();
    
    if (mounted) {
      // Navigate to onboarding screen with existing account
      final updatedAccount = await Navigator.push<UserAccount>(
        context,
        MaterialPageRoute(
          builder: (context) => UserOnboardingScreen(existingAccount: currentAccount),
        ),
      );
      
      // If account was updated, update the meditation widget directly
      if (updatedAccount != null && mounted) {
        await _meditationWidgetKey.currentState?.updateSettings(updatedAccount);
        _showSuccessSnackbar('Settings saved! Voice and preferences updated.');
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: const Text('Meditation'),
        trailingActions: [
          PlatformIconButton(
            materialIcon: const Icon(Icons.settings, color: Colors.white),
            cupertinoIcon: Icon(PlatformIcons(context).settings),
            onPressed: _openProfileSettings,
          ),
        ],
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
            colors: [Color(0xFFF5F3FF), Color(0xFFEDE9FE), Color(0xFFDDD6FE)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          HrHrvDisplayNew(
                            hr: _currentHr,
                            hrv: _currentHrv,
                            sdnn: _currentSdnn,
                            stressLevel: _currentHrv > 0 ? _stressDetector.getStressCategory(_currentHr, _currentHrv) : 'normal',
                            isHrvStable: _hrvIsStable,
                            measurementDurationSeconds: _measurementDurationSeconds,
                            activityLevel: _sensor is EarableHrSensor ? (_sensor as EarableHrSensor).activityLevel.name : null,
                            activityDescription: _sensor is EarableHrSensor ? _getActivityDescription((_sensor as EarableHrSensor).activityLevel) : null,
                          ),
                          const SizedBox(height: 16),
                          
                          // AI-Powered Meditation (always active)
                          if (_sensor != null)
                            LlmMeditationWidget(
                              key: _meditationWidgetKey,
                              sensor: _sensor!,
                              onReset: _resetToBaseline,
                            ),
                          
                          const SizedBox(height: 16),
                          
                          // Development/Testing Controls (always visible for testing)
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: (widget.ppgSensor != null && _useMockSensor) 
                                      ? _switchToEarableSensor 
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _useMockSensor ? Colors.blue[100] : Colors.green[100],
                                    foregroundColor: _useMockSensor ? Colors.blue[900] : Colors.green[900],
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    disabledBackgroundColor: _useMockSensor ? Colors.grey[300] : Colors.green[100],
                                    disabledForegroundColor: _useMockSensor ? Colors.grey[600] : Colors.green[900],
                                  ),
                                  child: Text(_useMockSensor ? 'Use Earable' : '✓ Using Earable'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _useMockSensor && _sensor is MockHrSensor 
                                      ? _simulateStress
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange[100],
                                    foregroundColor: Colors.orange[900],
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    disabledBackgroundColor: Colors.grey[300],
                                    disabledForegroundColor: Colors.grey[600],
                                  ),
                                  child: const Text('Simulate Stress'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _resetToBaseline,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.grey[200],
                                    foregroundColor: Colors.grey[800],
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text('Reset'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _useMockSensor && _sensor is MockHrSensor 
                                      ? _simulateRelaxation
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green[100],
                                    foregroundColor: Colors.green[900],
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    disabledBackgroundColor: Colors.grey[300],
                                    disabledForegroundColor: Colors.grey[600],
                                  ),
                                  child: const Text('Simulate Relax'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }  @override
  void dispose() {
    _measurementTimer?.cancel();
    _hrSubscription?.cancel();
    _hrvSubscription?.cancel();
    _sensor?.dispose();
    // _audioPlayer.dispose(); // Removed
    super.dispose();
  }
}
