import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';

class HrHrvChart extends StatefulWidget {
  final Stream<double> hrStream;
  final Stream<Map<String, double>> hrvStream;

  const HrHrvChart({
    super.key,
    required this.hrStream,
    required this.hrvStream,
  });

  @override
  State<HrHrvChart> createState() => _HrHrvChartState();
}

class _HrHrvChartState extends State<HrHrvChart> with SingleTickerProviderStateMixin {
  final List<double> _hrHistory = [];
  final List<double> _hrvHistory = [];
  final int _maxDataPoints = 3600; // Keep up to 1 hour of data (~1 data point per second)
  
  double _currentHr = 75.0;
  double _currentHrv = -1.0; // -1 means no data yet
  
  StreamSubscription<double>? _hrSubscription;
  StreamSubscription<Map<String, double>>? _hrvSubscription;
  
  late AnimationController _heartBeatController;
  
  @override
  void initState() {
    super.initState();
    
    _heartBeatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    
    // Start repeating animation
    _heartBeatController.repeat();
    
    _hrSubscription = widget.hrStream.listen((hr) {
      setState(() {
        _currentHr = hr;
        _hrHistory.add(hr);
        if (_hrHistory.length > _maxDataPoints) {
          _hrHistory.removeAt(0);
        }
      });
      
      // Update animation speed based on heart rate
      final bpm = hr.clamp(40.0, 200.0);
      final durationMs = (60000 / bpm).round();
      _heartBeatController.duration = Duration(milliseconds: durationMs);
    });
    
    _hrvSubscription = widget.hrvStream.listen((hrv) {
      final rmssd = hrv['HRV_RMSSD'] ?? 40.0;
      setState(() {
        _currentHrv = rmssd;
        _hrvHistory.add(rmssd);
        if (_hrvHistory.length > _maxDataPoints) {
          _hrvHistory.removeAt(0);
        }
      });
    });
  }
  
  @override
  void dispose() {
    _hrSubscription?.cancel();
    _hrvSubscription?.cancel();
    _heartBeatController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: const Text('Live Heart Data'),
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Animated Heart with Current HR
                _buildAnimatedHeartSection(),
                
                const SizedBox(height: 24),
                
                // Current Values Card
                _buildCurrentValuesCard(),
                
                const SizedBox(height: 24),
                
                // HR Chart
                _buildChartCard(
                  title: 'Heart Rate (BPM)',
                  data: _hrHistory,
                  color: Colors.red,
                  minValue: 50.0,
                  maxValue: 120.0,
                  icon: Icons.favorite,
                ),
                
                const SizedBox(height: 16),
                
                // HRV Chart
                _buildChartCard(
                  title: 'HRV RMSSD (ms)',
                  data: _hrvHistory,
                  color: Colors.blue,
                  minValue: 0.0,
                  maxValue: 80.0,
                  icon: Icons.show_chart,
                ),
                
                const SizedBox(height: 24),
                
                // Close Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    label: const Text('Close'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildAnimatedHeartSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Animated Heart Icon
            AnimatedBuilder(
              animation: _heartBeatController,
              builder: (context, child) {
                final scale = 1.0 + (_heartBeatController.value * 0.3);
                return Transform.scale(
                  scale: scale,
                  child: Icon(
                    Icons.favorite,
                    size: 80,
                    color: Color.lerp(
                      Colors.red[300],
                      Colors.red[700],
                      _heartBeatController.value,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Text(
              '${_currentHr.toStringAsFixed(0)} BPM',
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Color(0xFF6366F1),
              ),
            ),
            const Text(
              'Current Heart Rate',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCurrentValuesCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _buildStatItem(
                icon: Icons.favorite,
                label: 'Heart Rate',
                value: '${_currentHr.toStringAsFixed(0)} BPM',
                color: Colors.red,
              ),
            ),
            Container(
              width: 1,
              height: 60,
              color: Colors.grey[300],
            ),
            Expanded(
              child: _buildStatItem(
                icon: Icons.show_chart,
                label: 'HRV RMSSD',
                value: _currentHrv < 0 ? 'Loading...' : '${_currentHrv.toStringAsFixed(1)} ms',
                color: Colors.blue,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
  
  Widget _buildChartCard({
    required String title,
    required List<double> data,
    required Color color,
    required double minValue,
    required double maxValue,
    required IconData icon,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 150,
              child: data.isEmpty
                  ? Center(
                      child: Text(
                        'Collecting data...',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    )
                  : CustomPaint(
                      painter: LineChartPainter(
                        data: data,
                        color: color,
                        minValue: minValue,
                        maxValue: maxValue,
                      ),
                      size: Size.infinite,
                    ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Min: ${data.isEmpty ? "--" : data.reduce(min).toStringAsFixed(1)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  'Max: ${data.isEmpty ? "--" : data.reduce(max).toStringAsFixed(1)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  'Avg: ${data.isEmpty ? "--" : (data.reduce((a, b) => a + b) / data.length).toStringAsFixed(1)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class LineChartPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final double minValue;
  final double maxValue;

  LineChartPainter({
    required this.data,
    required this.color,
    required this.minValue,
    required this.maxValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = color.withOpacity(0.8)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withOpacity(0.3),
          color.withOpacity(0.05),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();
    final fillPath = Path();

    final stepX = size.width / (data.length - 1).clamp(1, double.infinity);
    
    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final normalizedValue = ((data[i] - minValue) / (maxValue - minValue)).clamp(0.0, 1.0);
      final y = size.height - (normalizedValue * size.height);

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    // Complete the fill path
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    // Draw fill
    canvas.drawPath(fillPath, fillPaint);

    // Draw line
    canvas.drawPath(path, paint);

    // Draw dots
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final normalizedValue = ((data[i] - minValue) / (maxValue - minValue)).clamp(0.0, 1.0);
      final y = size.height - (normalizedValue * size.height);

      canvas.drawCircle(Offset(x, y), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(LineChartPainter oldDelegate) {
    return oldDelegate.data != data;
  }
}
