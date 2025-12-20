import 'dart:async';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/apps/meditation/model/ppg_filter_meditation.dart';
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
  StreamSubscription<List<double>>? _rrIntervalSubscription;
  Timer? _hrvTimer;
  bool _isActive = false;
  
  final List<double> _rrIntervals = [];
  final int _maxRrIntervals = 50; // Keep last 50 RR intervals for HRV calculation
  final int _minRrIntervalsForStableHrv = 20; // Need at least 20 intervals for stable HRV (~20-30 seconds)
  final int _minRrIntervalsForSdnn = 300; // SDNN needs ~300 intervals (5 minutes) for reliable measurement
  final List<double> _longTermRrIntervals = []; // Store all RR intervals for long-term SDNN calculation
  
  // History for charts
  final List<double> _hrHistory = [];
  final List<double> _hrvHistory = [];
  final int _maxHistorySize = 3600; // Keep up to 1 hour of history
  
  final HrvCalculator _hrvCalculator = HrvCalculator();
  bool _hrvIsStable = false; // Flag to track if HRV measurements are stable
  
  /// Stream of heart rate values in BPM
  Stream<double> get hrStream => _hrController.stream;
  
  /// Stream of HRV metrics (SDNN, RMSSD, pNN50)
  Stream<Map<String, double>> get hrvStream => _hrvController.stream;
  
  /// Get HR history for charts
  List<double> get hrHistory => List.unmodifiable(_hrHistory);
  
  /// Get HRV history for charts
  List<double> get hrvHistory => List.unmodifiable(_hrvHistory);
  
  EarableHrSensor({
    required this.ppgSensor,
    required this.sampleFreq,
  });
  
  /// Start generating real data from the earable device
  void start() {
    if (_isActive) return;
    _isActive = true;
    
    _logger.i('Starting EarableHrSensor with sample frequency: $sampleFreq Hz');
    
    // Create PPG filter to extract heart rate AND RR intervals
    final ppgFilter = PpgFilterMeditation(
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
        
        // Add to history
        _hrHistory.add(hr);
        if (_hrHistory.length > _maxHistorySize) {
          _hrHistory.removeAt(0);
        }
      } else {
        _logger.w('Invalid HR: $hr BPM (out of range 40-200)');
      }
    }, onError: (error) {
      _logger.e('Error in heart rate stream: $error');
    });
    
    // Listen to RR interval stream for accurate HRV calculation
    _rrIntervalSubscription = ppgFilter.rrIntervalStream.listen((rrIntervals) {
      // Add to short-term buffer for RMSSD
      _rrIntervals.addAll(rrIntervals);
      
      // Add to long-term buffer for SDNN
      _longTermRrIntervals.addAll(rrIntervals);
      
      // Keep only the last N intervals in short-term buffer (efficient approach)
      if (_rrIntervals.length > _maxRrIntervals) {
        // Remove excess from front efficiently
        final excess = _rrIntervals.length - _maxRrIntervals;
        _rrIntervals.removeRange(0, excess);
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
    }, onError: (error) {
      _logger.e('Error in RR interval stream: $error');
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
    
    // Filter artifacts for short-term RMSSD calculation
    final cleanedRR = _filterArtifacts(_rrIntervals);
    
    if (cleanedRR.length < 5) {
      _logger.w('Too many artifacts removed, only ${cleanedRR.length} intervals remain');
      return;
    }
    
    // Calculate RMSSD (always available with short-term data)
    final hrvMetrics = _hrvCalculator.computeTimeHrv(cleanedRR);
    
    // Calculate SDNN only if we have enough long-term data (5+ minutes)
    double? sdnnValue;
    if (_longTermRrIntervals.length >= _minRrIntervalsForSdnn) {
      final cleanedLongTerm = _filterArtifacts(_longTermRrIntervals);
      if (cleanedLongTerm.length >= _minRrIntervalsForSdnn) {
        final longTermMetrics = _hrvCalculator.computeTimeHrv(cleanedLongTerm);
        sdnnValue = longTermMetrics['HRV_SDNN'];
        _logger.d('Long-term SDNN calculated from ${cleanedLongTerm.length} intervals (5+ minutes): ${sdnnValue?.toStringAsFixed(1)}ms');
      }
    } else {
      _logger.d('SDNN pending: ${_longTermRrIntervals.length}/$_minRrIntervalsForSdnn intervals (need 5 minutes)');
    }
    
    // Emit HRV metrics with SDNN only if available
    final metricsToEmit = Map<String, double>.from(hrvMetrics);
    if (sdnnValue != null && sdnnValue.isFinite) {
      metricsToEmit['HRV_SDNN'] = sdnnValue;
    } else {
      metricsToEmit['HRV_SDNN'] = -1.0; // Signal that SDNN is not yet available
    }
    
    if (hrvMetrics['HRV_RMSSD']!.isFinite) {
      _hrvController.add(metricsToEmit);
      
      // Add to history
      _hrvHistory.add(hrvMetrics['HRV_RMSSD']!);
      if (_hrvHistory.length > _maxHistorySize) {
        _hrvHistory.removeAt(0);
      }
      
      final artifactsRemoved = _rrIntervals.length - cleanedRR.length;
      _logger.d('HRV calculated from ${cleanedRR.length} clean RR intervals (${artifactsRemoved} artifacts removed): '
                'RMSSD=${hrvMetrics['HRV_RMSSD']?.toStringAsFixed(1)}ms, '
                'SDNN=${sdnnValue?.toStringAsFixed(1) ?? "pending"}ms, '
                'Mean=${hrvMetrics['HRV_MEAN']?.toStringAsFixed(1)}ms');
      
      // DEBUG: Print buffer state to verify rotation
      _logger.d('Buffer: ${_rrIntervals.length} raw intervals → ${cleanedRR.length} clean. '
                'First 5 RR: ${cleanedRR.take(5).map((v) => v.toStringAsFixed(1)).join(", ")}, '
                'Last 5 RR: ${cleanedRR.skip(cleanedRR.length - 5).map((v) => v.toStringAsFixed(1)).join(", ")}');
    }
  }
  
  /// Filter artifacts from RR intervals
  /// Removes physiologically impossible values and statistical outliers
  List<double> _filterArtifacts(List<double> rrIntervals) {
    // Step 1: Remove physiologically impossible values
    // Normal HR range: 30-200 BPM → RR range: 300-2000ms
    var filtered = rrIntervals.where((rr) => rr >= 300 && rr <= 2000).toList();
    
    if (filtered.length < 5) return filtered; // Need at least 5 values for statistics
    
    // Step 2: Calculate median
    final sorted = List<double>.from(filtered)..sort();
    final median = sorted[sorted.length ~/ 2];
    
    // Step 3: Remove statistical outliers (>30% deviation from median)
    final threshold = median * 0.3;
    filtered = filtered.where((rr) => (rr - median).abs() <= threshold).toList();
    
    return filtered;
  }
  
  /// Stop generating real data
  void stop() {
    _isActive = false;
    _hrSubscription?.cancel();
    _hrSubscription = null;
    _rrIntervalSubscription?.cancel();
    _rrIntervalSubscription = null;
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
