import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'meditation_config.dart';
import 'meditation_cache.dart';

final _logger = Logger();

/// High-quality voice service with Google Cloud TTS
class MeditationVoiceService {
  final FlutterTts _flutterTts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  bool _isInitialized = false;
  bool _isSpeaking = false;
  
  // Google Cloud TTS - high quality female voice
  static const Map<String, String> _femaleVoice = {
    'name': 'en-US-Standard-C',
    'description': 'Warm, empathetic female voice'
  };
  
  // Style affects pitch and speaking rate
  static const Map<String, Map<String, double>> _styleSettings = {
    'calm and empathetic': {
      'pitch': -2.0,
      'speakingRate': 0.8,
    },
    'gentle and soothing': {
      'pitch': -3.0,
      'speakingRate': 0.75,
    },
    'warm and compassionate': {
      'pitch': -1.5,
      'speakingRate': 0.8,
    },
    'peaceful and mindful': {
      'pitch': -2.5,
      'speakingRate': 0.7,
    },
  };
  
  String _meditationStyle = 'calm and empathetic';
  
  Future<void> initialize({String voiceGender = 'female', String? meditationStyle}) async {
    _meditationStyle = meditationStyle ?? 'calm and empathetic';
    
    _logger.i('🎤 Initializing voice (style: $_meditationStyle)');
    
    await _initializeFlutterTts();
    
    _isInitialized = true;
    _logger.i('✓ Voice ready');
  }
  
  Future<void> _initializeFlutterTts() async {
    try {
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.5); // Much slower for meditation
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(0.85);
      
      final voices = await _flutterTts.getVoices;
      if (voices != null && voices.isNotEmpty) {
        final enVoices = voices.where((v) => 
          v['locale']?.toString().contains('en-US') ?? false
        ).toList();
        
        // Look for enhanced female voice
        for (var voice in enVoices) {
          final name = voice['name']?.toString().toLowerCase() ?? '';
          if (name.contains('female') && (name.contains('enhanced') || name.contains('premium'))) {
            await _flutterTts.setVoice({
              'name': voice['name'].toString(),
              'locale': voice['locale'].toString(),
            });
            _logger.i('✅ Flutter TTS fallback: ${voice['name']}');
            break;
          }
        }
      }
    } catch (e) {
      _logger.w('Error configuring Flutter TTS fallback: $e');
    }
  }
  
  /// Speak text with Google Cloud TTS (high quality)
  Future<void> speak(String text) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    if (_isSpeaking) {
      await Future.delayed(Duration(milliseconds: 500));
      if (_isSpeaking) return;
    }
    
    _isSpeaking = true;
    
    try {
      // Try Google Cloud TTS first for high quality
      final success = await _tryGoogleCloudTts(text);
      if (!success) {
        // Fallback to Flutter TTS
        await _speakWithFlutterTts(text);
      }
    } catch (e) {
      _logger.e('Error during speech: $e');
      await _speakWithFlutterTts(text);
    } finally {
      _isSpeaking = false;
    }
  }
  
  Future<bool> _tryGoogleCloudTts(String text) async {
    try {
      // Check cache first
      final cachedFile = await MeditationCache.getCachedAudio(text);
      if (cachedFile != null) {
        _logger.i('✓ Using cached TTS audio (saves 1 API request)');
        await _audioPlayer.play(DeviceFileSource(cachedFile.path));
        await _audioPlayer.onPlayerComplete.first;
        return true;
      }
      
      final voiceConfig = _femaleVoice;
      final styleSettings = _styleSettings[_meditationStyle] ?? _styleSettings['calm and empathetic']!;
      
      _logger.i('🎤 Google Cloud TTS: ${voiceConfig['name']} - API REQUEST');
      
      if (MeditationConfig.googleCloudTtsApiKey == 'NONE' || 
          MeditationConfig.googleCloudTtsApiKey == 'YOUR_TTS_API_KEY_HERE') {
        _logger.i('No API key configured → Using Flutter TTS fallback');
        return false;
      }
      
      final response = await http.post(
        Uri.parse('https://texttospeech.googleapis.com/v1/text:synthesize?key=${MeditationConfig.googleCloudTtsApiKey}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'input': {'text': text},
          'voice': {
            'languageCode': 'en-US',
            'name': voiceConfig['name'],
          },
          'audioConfig': {
            'audioEncoding': 'MP3',
            'pitch': styleSettings['pitch']!,
            'speakingRate': styleSettings['speakingRate']!,
            'volumeGainDb': 0.0,
            'effectsProfileId': ['headphone-class-device'],
          },
        }),
      ).timeout(const Duration(seconds: 15));
      
      if (response.statusCode != 200) {
        _logger.w('⚠️ Google TTS API error: ${response.statusCode} - Using fallback');
        return false;
      }
      
      final jsonResponse = jsonDecode(response.body);
      final audioContent = jsonResponse['audioContent'];
      
      if (audioContent == null) {
        _logger.w('No audio content in response');
        return false;
      }
      
      final audioBytes = base64Decode(audioContent);
      
      // Cache the audio for future use
      final cachedAudioFile = await MeditationCache.cacheAudio(text, audioBytes);
      
      // Play from cache if successfully cached, otherwise use temp file
      final playFile = cachedAudioFile ?? await _createTempFile(audioBytes);
      
      _logger.i('✓ Playing high-quality Google Cloud TTS audio');
      
      await _audioPlayer.play(DeviceFileSource(playFile.path));
      await _audioPlayer.onPlayerComplete.first;
      
      // Only delete if it was a temp file (not cached)
      if (cachedAudioFile == null) {
        try {
          await playFile.delete();
        } catch (e) {
          // Ignore cleanup errors
        }
      }
      
      _logger.i('✓ Google Cloud TTS playback complete');
      return true;
      
    } catch (e) {
      _logger.w('⚠️ Google Cloud TTS error: $e - Using fallback');
      return false;
    }
  }
  
  Future<File> _createTempFile(List<int> audioBytes) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/meditation_${DateTime.now().millisecondsSinceEpoch}.mp3');
    await tempFile.writeAsBytes(audioBytes);
    return tempFile;
  }
  
  Future<void> _speakWithFlutterTts(String text) async {
    _logger.i('Using Flutter TTS fallback');
    
    try {
      final completer = Completer<void>();
      
      _flutterTts.setCompletionHandler(() {
        if (!completer.isCompleted) completer.complete();
      });
      
      _flutterTts.setCancelHandler(() {
        if (!completer.isCompleted) completer.complete();
      });
      
      _flutterTts.setErrorHandler((msg) {
        _logger.e('Flutter TTS error: $msg');
        if (!completer.isCompleted) completer.complete();
      });

      await _flutterTts.speak(text);
      await completer.future.timeout(const Duration(seconds: 60));
      
    } catch (e) {
      _logger.e('Flutter TTS error: $e');
    }
  }
  
  Future<void> stop() async {
    _isSpeaking = false;
    await _flutterTts.stop();
    await _audioPlayer.stop();
  }
  
  Future<void> pause() async {
    await _flutterTts.pause();
    await _audioPlayer.pause();
  }
  
  Future<void> resume() async {
    await _audioPlayer.resume();
  }
  
  void setVoiceGender(String gender) {
    // Always female - ignore parameter
    _isInitialized = false;
  }
  
  Future<void> dispose() async {
    await stop();
    await _audioPlayer.dispose();
  }
  
  bool get isSpeaking => _isSpeaking;
  
  Future<void> testVoice() async {
    await speak('Welcome to your meditation session. I am here to guide you towards a state of calm and relaxation.');
  }
}
