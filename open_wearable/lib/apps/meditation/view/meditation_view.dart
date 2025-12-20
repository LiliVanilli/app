import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import '../model/mock_hr_sensor.dart';
import '../model/earable_hr_sensor.dart';
import '../model/hr_sensor_interface.dart';
import '../model/stress_detector.dart';
import 'stress_prompt_dialog.dart';
import 'snooze_dialog.dart';
import 'success_dialog.dart';
import '../widgets/hr_hrv_display_new.dart';
import '../widgets/breathing_animation.dart';
import '../widgets/hr_hrv_chart.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';

class MeditationView extends StatefulWidget {
  final Sensor? ppgSensor;
  final SensorConfigurationProvider? sensorConfigProvider;
  
  const MeditationView({
    super.key,
    this.ppgSensor,
    this.sensorConfigProvider,
  });
  
  @override
  State<MeditationView> createState() => _MeditationViewState();
}

class _MeditationViewState extends State<MeditationView> {
  HrSensorInterface? _sensor;
  bool _useMockSensor = true;
  final StressDetector _detector = StressDetector();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  double _currentHr = 75.0;
  double _currentHrv = -1.0; // -1 means no data yet (RMSSD)
  double _currentSdnn = -1.0; // -1 means no data yet (SDNN - comparable to Apple Health)
  bool _hrvIsStable = false; // Track if HRV measurements are reliable
  int _hrvMeasurementCount = 0; // Count HRV measurements received
  int _measurementDurationSeconds = 0; // Track how long we've been measuring
  Timer? _measurementTimer; // Timer to track measurement duration
  double _hrBeforeMeditation = 75.0;
  double _hrvBeforeMeditation = -1.0; // RMSSD before meditation
  double _sdnnBeforeMeditation = -1.0; // SDNN before meditation
  bool _isMeditating = false;
  bool _dialogShown = false;
  
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
      if (_hrvIsStable) {
        _checkStress();
        _checkRelaxationDuringMeditation();
      }
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
  
  void _checkStress() {
    if (_isMeditating || _dialogShown) return;
    
    // Don't check stress if HRV is not yet stable or still loading
    if (!_hrvIsStable || _currentHrv < 0) return;
    
    if (_detector.isStressed(_currentHr, _currentHrv)) {
      _checkSnoozeAndShowDialog();
    }
  }
  
  void _checkRelaxationDuringMeditation() {
    if (!_isMeditating) return;
    final isRelaxed = _detector.isRelaxed(_currentHr, _currentHrv);
    
    // Stop meditation if relaxed - regardless if was stressed before or just testing
    if (isRelaxed) {
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
        onSnoozeToday: _snoozeUntilEndOfDay,
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
    print('Resetting to baseline...');
    
    // Stop current sensor
    _hrSubscription?.cancel();
    _hrvSubscription?.cancel();
    _sensor?.dispose();
    
    // Reset to mock sensor
    _sensor = MockHrSensor();
    
    setState(() {
      _useMockSensor = true;
      _dialogShown = false;
    });
    
    // Restart monitoring with mock sensor
    _startMonitoring();
    
    // Clear snooze
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('meditation_snooze_until');
    
    print('Reset complete! Back to mock sensor. _useMockSensor = $_useMockSensor');
    _showSuccessSnackbar('Reset to simulated data');
  }
  
  void _startMeditation() async {
    setState(() {
      _hrBeforeMeditation = _currentHr;
      _hrvBeforeMeditation = _currentHrv;
      _sdnnBeforeMeditation = _currentSdnn;
      _isMeditating = true;
    });
    try {
      await _audioPlayer.setSource(AssetSource('meditation_sound.mp3'));
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.resume();
    } catch (e) {
      print('Audio error: \$e');
    }
  }
  
  void _stopMeditation() {
    if (!_isMeditating) return;
    final bool isRelaxed = _detector.isRelaxed(_currentHr, _currentHrv);
    setState(() {
      _isMeditating = false;
      _dialogShown = false;
    });
    _audioPlayer.stop();
    if (isRelaxed) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _showSuccessMessage();
      });
    }
  }
  
  void _showSuccessMessage() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SuccessDialog(
        hrBefore: _hrBeforeMeditation,
        hrvRmssdBefore: _hrvBeforeMeditation,
        hrvSdnnBefore: _sdnnBeforeMeditation,
        hrAfter: _currentHr,
        hrvRmssdAfter: _currentHrv,
        hrvSdnnAfter: _currentSdnn,
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
                            stressLevel: _detector.getStressCategory(_currentHr, _currentHrv),
                            isHrvStable: _hrvIsStable,
                            measurementDurationSeconds: _measurementDurationSeconds,
                          ),
                          const SizedBox(height: 16),
                          // Show Chart Button when using real earable data
                          if (!_useMockSensor && !_isMeditating) ...[
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _openLiveChart,
                                icon: const Icon(Icons.show_chart, size: 20),
                                label: const Text('View Live Chart'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6366F1),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 3,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (_isMeditating) ...[
                            const SizedBox(height: 8),
                            Center(child: BreathingAnimation(isActive: _isMeditating)),
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
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            // Simulate Relax button during meditation (for testing)
                            if (_useMockSensor && _sensor is MockHrSensor) ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: (_sensor as MockHrSensor).simulateRelaxation,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green[100],
                                    foregroundColor: Colors.green[900],
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text('Simulate Relax'),
                                ),
                              ),
                            ],
                          ],
                          // Spacer to push buttons down
                          if (!_isMeditating) 
                            const Spacer(),
                          // 4 BUTTONS IN 2x2 GRID
                          if (!_isMeditating) ...[
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
                                        ? (_sensor as MockHrSensor).simulateStress 
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
                                        ? (_sensor as MockHrSensor).simulateRelaxation 
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
    _audioPlayer.dispose();
    super.dispose();
  }
}
