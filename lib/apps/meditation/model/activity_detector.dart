import 'dart:async';
import 'dart:math';
import 'package:logger/logger.dart';

final _logger = Logger();

/// Detects physical activity from accelerometer and gyroscope data
/// Helps distinguish between exercise-induced HR increase vs. stress
class ActivityDetector {
  // Thresholds based on research (Gjoreski et al. 2016)
  static const double _restingAccelThreshold = 0.15; // g (gravity units)
  static const double _lightActivityAccelThreshold = 0.4; // g
  static const double _moderateActivityAccelThreshold = 0.8; // g
  static const double _vigorousActivityAccelThreshold = 1.5; // g
  
  static const double _restingGyroThreshold = 20.0; // degrees/second
  static const double _activeGyroThreshold = 50.0; // degrees/second
  
  // Moving average window
  final List<double> _accelMagnitudeHistory = [];
  final List<double> _gyroMagnitudeHistory = [];
  final int _windowSize = 30; // 30 samples ~3 seconds at 10Hz
  
  ActivityLevel _currentActivityLevel = ActivityLevel.resting;
  
  /// Add new accelerometer reading (x, y, z in m/s²)
  void addAccelReading(double x, double y, double z) {
    // Convert to g units (1g = 9.81 m/s²)
    final gX = x / 9.81;
    final gY = y / 9.81;
    final gZ = z / 9.81;
    
    // Calculate magnitude minus gravity (to get movement component)
    // Remove static gravity component
    final magnitude = sqrt(gX * gX + gY * gY + gZ * gZ) - 1.0;
    final absMovement = magnitude.abs();
    
    _accelMagnitudeHistory.add(absMovement);
    if (_accelMagnitudeHistory.length > _windowSize) {
      _accelMagnitudeHistory.removeAt(0);
    }
    
    _updateActivityLevel();
  }
  
  /// Add new gyroscope reading (x, y, z in rad/s)
  void addGyroReading(double x, double y, double z) {
    // Convert to degrees/second
    final degX = x * 57.2958; // rad to deg
    final degY = y * 57.2958;
    final degZ = z * 57.2958;
    
    // Calculate angular velocity magnitude
    final magnitude = sqrt(degX * degX + degY * degY + degZ * degZ);
    
    _gyroMagnitudeHistory.add(magnitude);
    if (_gyroMagnitudeHistory.length > _windowSize) {
      _gyroMagnitudeHistory.removeAt(0);
    }
    
    _updateActivityLevel();
  }
  
  void _updateActivityLevel() {
    if (_accelMagnitudeHistory.isEmpty) return;
    
    // Calculate moving average
    final avgAccel = _accelMagnitudeHistory.reduce((a, b) => a + b) / _accelMagnitudeHistory.length;
    final avgGyro = _gyroMagnitudeHistory.isNotEmpty 
        ? _gyroMagnitudeHistory.reduce((a, b) => a + b) / _gyroMagnitudeHistory.length
        : 0.0;
    
    // Determine activity level based on both sensors
    ActivityLevel newLevel;
    
    if (avgAccel < _restingAccelThreshold && avgGyro < _restingGyroThreshold) {
      newLevel = ActivityLevel.resting;
    } else if (avgAccel < _lightActivityAccelThreshold) {
      newLevel = ActivityLevel.light;
    } else if (avgAccel < _moderateActivityAccelThreshold) {
      newLevel = ActivityLevel.moderate;
    } else if (avgAccel < _vigorousActivityAccelThreshold) {
      newLevel = ActivityLevel.vigorous;
    } else {
      newLevel = ActivityLevel.intense;
    }
    
    // Update if changed
    if (newLevel != _currentActivityLevel) {
      _logger.i('Activity level changed: ${_currentActivityLevel.name} → ${newLevel.name} '
                '(accel=${avgAccel.toStringAsFixed(3)}g, gyro=${avgGyro.toStringAsFixed(1)}°/s)');
      _currentActivityLevel = newLevel;
    }
  }
  
  /// Get current activity level
  ActivityLevel get activityLevel => _currentActivityLevel;
  
  /// Check if user is currently resting (not exercising)
  bool get isResting => _currentActivityLevel == ActivityLevel.resting;
  
  /// Check if activity might explain elevated heart rate
  /// Returns true for moderate+ activity (user is likely exercising)
  bool get isExercising => _currentActivityLevel.index >= ActivityLevel.moderate.index;
  
  /// Get average acceleration over window (in g units)
  double get averageAcceleration {
    if (_accelMagnitudeHistory.isEmpty) return 0.0;
    return _accelMagnitudeHistory.reduce((a, b) => a + b) / _accelMagnitudeHistory.length;
  }
  
  /// Get average gyroscope magnitude over window (in degrees/second)
  double get averageGyroMagnitude {
    if (_gyroMagnitudeHistory.isEmpty) return 0.0;
    return _gyroMagnitudeHistory.reduce((a, b) => a + b) / _gyroMagnitudeHistory.length;
  }
  
  /// Reset detector
  void reset() {
    _accelMagnitudeHistory.clear();
    _gyroMagnitudeHistory.clear();
    _currentActivityLevel = ActivityLevel.resting;
  }
}

/// Activity levels based on accelerometer/gyroscope data
enum ActivityLevel {
  resting,   // Sitting, standing still
  light,     // Slow walking, gentle movement
  moderate,  // Brisk walking, light exercise
  vigorous,  // Running, active exercise
  intense,   // Sprinting, very intense exercise
}
