import 'dart:math';

/// HRV Calculator - Port from python-backend/hrv_utils.py
/// 
/// Computes time-domain HRV metrics from RR intervals.
/// 
/// Usage:
/// ```dart
/// final calc = HrvCalculator();
/// final rrIntervals = [800.0, 820.0, 810.0, 805.0, 815.0]; // in ms
/// final hrv = calc.computeTimeHrv(rrIntervals);
/// 
/// print('SDNN: ${hrv['HRV_SDNN']}');
/// print('RMSSD: ${hrv['HRV_RMSSD']}');
/// print('pNN50: ${hrv['HRV_pNN50']}');
/// ```
class HrvCalculator {
  /// Compute basic time-domain HRV metrics from RR intervals in milliseconds.
  /// 
  /// Returns a map with:
  /// - HRV_SDNN: Standard deviation of NN intervals
  /// - HRV_RMSSD: Root mean square of successive differences
  /// - HRV_pNN50: Percentage of successive differences > 50ms
  /// - HRV_pNN20: Percentage of successive differences > 20ms
  Map<String, double> computeTimeHrv(List<double> rrIntervalsMs) {
    // Filter out NaN values
    final rr = rrIntervalsMs.where((x) => !x.isNaN).toList();
    
    // Default output
    final out = {
      'HRV_SDNN': double.nan,
      'HRV_RMSSD': double.nan,
      'HRV_pNN50': double.nan,
      'HRV_pNN20': double.nan,
    };
    
    // Edge cases
    if (rr.isEmpty) return out;
    
    if (rr.length == 1) {
      return {
        'HRV_SDNN': 0.0,
        'HRV_RMSSD': 0.0,
        'HRV_pNN50': 0.0,
        'HRV_pNN20': 0.0,
      };
    }
    
    // Compute successive differences
    final diffs = <double>[];
    for (int i = 1; i < rr.length; i++) {
      diffs.add(rr[i] - rr[i - 1]);
    }
    
    // SDNN: Standard deviation of RR intervals
    out['HRV_SDNN'] = _standardDeviation(rr);
    
    // RMSSD: Root mean square of successive differences
    out['HRV_RMSSD'] = _rmssd(diffs);
    
    // pNN50: Percentage of diffs > 50ms
    out['HRV_pNN50'] = _pnnX(diffs, 50.0);
    
    // pNN20: Percentage of diffs > 20ms
    out['HRV_pNN20'] = _pnnX(diffs, 20.0);
    
    return out;
  }
  
  /// Standard deviation (population, not sample - ddof=0 in numpy)
  double _standardDeviation(List<double> values) {
    if (values.isEmpty) return double.nan;
    
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values
        .map((x) => pow(x - mean, 2))
        .reduce((a, b) => a + b) / values.length;
    
    return sqrt(variance);
  }
  
  /// Root mean square of successive differences
  double _rmssd(List<double> diffs) {
    if (diffs.isEmpty) return double.nan;
    
    final squaredDiffs = diffs.map((x) => x * x);
    final meanSquared = squaredDiffs.reduce((a, b) => a + b) / diffs.length;
    
    return sqrt(meanSquared);
  }
  
  /// Percentage of successive differences > threshold
  double _pnnX(List<double> diffs, double threshold) {
    if (diffs.isEmpty) return 0.0;
    
    final count = diffs.where((x) => x.abs() > threshold).length;
    return 100.0 * count / diffs.length;
  }
}
