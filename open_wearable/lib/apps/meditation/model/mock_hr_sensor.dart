import 'dart:async';
import 'dart:math';
import 'hr_sensor_interface.dart';

/// Mock sensor that simulates realistic HR/HRV data for testing without hardware.
/// 
/// Usage:
/// ```dart
/// final sensor = MockHrSensor();
/// sensor.hrStream.listen((hr) => print('HR: $hr BPM'));
/// sensor.hrvStream.listen((hrv) => print('HRV RMSSD: $hrv ms'));
/// 
/// // Simulate stress
/// sensor.simulateStress();
/// 
/// // Simulate relaxation
/// sensor.simulateRelaxation();
/// ```
class MockHrSensor implements HrSensorInterface {
  final StreamController<double> _hrController = StreamController<double>.broadcast();
  final StreamController<Map<String, double>> _hrvController = StreamController<Map<String, double>>.broadcast();
  
  Timer? _timer;
  double _currentHr = 75.0; // Baseline heart rate
  double _currentHrv = 40.0; // Baseline HRV (RMSSD)
  double _targetHr = 75.0;
  double _targetHrv = 40.0;
  bool _isActive = false;
  
  final Random _random = Random();
  
  /// Stream of heart rate values in BPM
  Stream<double> get hrStream => _hrController.stream;
  
  /// Stream of HRV metrics (SDNN, RMSSD, pNN50)
  Stream<Map<String, double>> get hrvStream => _hrvController.stream;
  
  /// Start generating mock data
  void start() {
    if (_isActive) return;
    _isActive = true;
    
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // Gradually move towards target HR and HRV
      _currentHr += (_targetHr - _currentHr) * 0.1;
      _currentHrv += (_targetHrv - _currentHrv) * 0.1;
      
      // Add realistic noise
      final hrNoise = _random.nextDouble() * 4 - 2; // +/- 2 BPM
      final hr = (_currentHr + hrNoise).clamp(50.0, 120.0);
      
      final hrvNoise = _random.nextDouble() * 4 - 2; // +/- 2 ms
      final hrv = (_currentHrv + hrvNoise).clamp(10.0, 80.0);
      
      _hrController.add(hr);
      
      // Generate mock HRV data with consistent values
      _hrvController.add({
        'HRV_SDNN': hrv * 1.2,  // SDNN typically 20% higher than RMSSD
        'HRV_RMSSD': hrv,       // Use our calculated HRV
        'HRV_pNN50': (hrv / 2).clamp(0.0, 40.0), // pNN50 correlates with HRV
      });
    });
  }
  
  /// Stop generating mock data
  void stop() {
    _isActive = false;
    _timer?.cancel();
    _timer = null;
  }
  
  /// Simulate stress (increase HR, decrease HRV)
  /// Triggers stress detection: HR > 95 OR HRV < 15
  void simulateStress() {
    _targetHr = 100.0;  // Well above 95 threshold
    _targetHrv = 12.0;  // Well below 15 threshold
  }
  
  /// Simulate relaxation (decrease HR, increase HRV)
  /// Triggers relaxation detection: HR < 75 AND HRV > 30
  void simulateRelaxation() {
    _targetHr = 65.0;   // Well below 75 threshold
    _targetHrv = 45.0;  // Well above 30 threshold
  }
  
  /// Reset to baseline
  void reset() {
    _targetHr = 75.0;
    _targetHrv = 40.0;
  }
  
  /// Dispose resources
  void dispose() {
    stop();
    _hrController.close();
    _hrvController.close();
  }
}
