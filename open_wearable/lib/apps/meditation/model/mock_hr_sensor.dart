import 'dart:async';
import 'dart:math';

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
class MockHrSensor {
  final StreamController<double> _hrController = StreamController<double>.broadcast();
  final StreamController<Map<String, double>> _hrvController = StreamController<Map<String, double>>.broadcast();
  
  Timer? _timer;
  double _currentHr = 75.0; // Baseline heart rate
  double _targetHr = 75.0;
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
      // Gradually move towards target HR
      _currentHr += (_targetHr - _currentHr) * 0.1;
      
      // Add realistic noise
      final noise = _random.nextDouble() * 4 - 2; // +/- 2 BPM
      final hr = _currentHr + noise;
      
      _hrController.add(hr.clamp(50.0, 120.0));
      
      // Generate mock HRV data
      // Lower HRV = more stress
      final baseHrv = 50.0;
      final stressFactor = (hr - 70) / 30; // Higher HR = more stress
      final rmssd = (baseHrv - (stressFactor * 30)).clamp(10.0, 60.0);
      
      _hrvController.add({
        'HRV_SDNN': rmssd * 0.8,
        'HRV_RMSSD': rmssd,
        'HRV_pNN50': (50 - stressFactor * 30).clamp(0.0, 60.0),
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
  void simulateStress() {
    _targetHr = 95.0;
  }
  
  /// Simulate relaxation (decrease HR, increase HRV)
  void simulateRelaxation() {
    _targetHr = 70.0;
  }
  
  /// Reset to baseline
  void reset() {
    _targetHr = 75.0;
  }
  
  /// Dispose resources
  void dispose() {
    stop();
    _hrController.close();
    _hrvController.close();
  }
}
