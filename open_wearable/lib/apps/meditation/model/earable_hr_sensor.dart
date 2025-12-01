import 'dart:async';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/apps/heart_tracker/model/ppg_filter.dart';
import 'package:open_wearable/apps/meditation/model/hrv_calculator.dart';
import 'package:logger/logger.dart';
import 'hr_sensor_interface.dart';

final _logger = Logger();

/// Real sensor that connects to the OpenEarable device and computes HR/HRV from PPG data.
class EarableHrSensor implements HrSensorInterface {
  final Sensor ppgSensor;
  final double sampleFreq;
  
  final StreamController<double> _hrController = StreamController<double>.broadcast();
  final StreamController<Map<String, double>> _hrvController = StreamController<Map<String, double>>.broadcast();
  
  StreamSubscription<double>? _hrSubscription;
  Timer? _hrvTimer;
  bool _isActive = false;
  
  final List<double> _rrIntervals = [];
  final int _maxRrIntervals = 50; // Keep last 50 RR intervals for HRV calculation
  final int _minRrIntervalsForStableHrv = 20; // Need at least 20 intervals for stable HRV (~20-30 seconds)
  
  final HrvCalculator _hrvCalculator = HrvCalculator();
  bool _hrvIsStable = false; // Flag to track if HRV measurements are stable
  
  /// Stream of heart rate values in BPM
  Stream<double> get hrStream => _hrController.stream;
  
  /// Stream of HRV metrics (SDNN, RMSSD, pNN50)
  Stream<Map<String, double>> get hrvStream => _hrvController.stream;
  
  EarableHrSensor({
    required this.ppgSensor,
    required this.sampleFreq,
  });
  
  /// Start generating real data from the earable device
  void start() {
    if (_isActive) return;
    _isActive = true;
    
    _logger.i('Starting EarableHrSensor with sample frequency: $sampleFreq Hz');
    
    // Create PPG filter to extract heart rate
    final ppgFilter = PpgFilter(
      inputStream: ppgSensor.sensorStream.asyncMap((data) {
        SensorDoubleValue sensorData = data as SensorDoubleValue;
        return (
          sensorData.timestamp,
          -(sensorData.values[2] + sensorData.values[3])
        );
      }).asBroadcastStream(),
      sampleFreq: sampleFreq,
      timestampExponent: ppgSensor.timestampExponent,
    );
    
    // Listen to heart rate stream
    _hrSubscription = ppgFilter.heartRateStream.listen((hr) {
      if (hr.isFinite && hr > 40 && hr < 200) {
        _hrController.add(hr);
        
        // Calculate RR interval from heart rate
        // This is an approximation: RR = 60000 / HR
        final rrInterval = 60000.0 / hr;
        _rrIntervals.add(rrInterval);
        
        // Keep only the last N intervals
        if (_rrIntervals.length > _maxRrIntervals) {
          _rrIntervals.removeAt(0);
        }
        
        // Wait for stable HRV measurements
        if (_rrIntervals.length >= _minRrIntervalsForStableHrv) {
          if (!_hrvIsStable) {
            _hrvIsStable = true;
            _logger.i('HRV measurements now stable (${_rrIntervals.length} intervals collected)');
          }
          _calculateAndEmitHrv();
        } else {
          _logger.d('Collecting initial data for stable HRV (${_rrIntervals.length}/$_minRrIntervalsForStableHrv)');
        }
      } else {
        _logger.w('Invalid HR: $hr BPM (out of range 40-200)');
      }
    }, onError: (error) {
      _logger.e('Error in heart rate stream: $error');
    });
    
    _logger.i('EarableHrSensor started successfully');
  }
  
  
  /// Calculate and emit HRV metrics
  void _calculateAndEmitHrv() {
    if (_rrIntervals.length < _minRrIntervalsForStableHrv) {
      // Not enough data yet for stable measurements
      _logger.d('Not enough RR intervals for stable HRV: ${_rrIntervals.length}/$_minRrIntervalsForStableHrv');
      return;
    }
    
    final hrvMetrics = _hrvCalculator.computeTimeHrv(_rrIntervals);
    
    if (hrvMetrics['HRV_RMSSD']!.isFinite) {
      _hrvController.add(hrvMetrics);
      _logger.d('HRV calculated: RMSSD=${hrvMetrics['HRV_RMSSD']?.toStringAsFixed(1)}, '
                'SDNN=${hrvMetrics['HRV_SDNN']?.toStringAsFixed(1)}');
    }
  }
  
  /// Stop generating real data
  void stop() {
    _isActive = false;
    _hrSubscription?.cancel();
    _hrSubscription = null;
    _hrvTimer?.cancel();
    _hrvTimer = null;
  }
  
  /// Reset (no-op for real sensor, but kept for interface compatibility)
  void reset() {
    _rrIntervals.clear();
    _hrvIsStable = false;
  }
  
  /// Dispose resources
  void dispose() {
    stop();
    _hrController.close();
    _hrvController.close();
  }
}
