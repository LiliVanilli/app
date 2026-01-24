import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:logger/logger.dart';

final _logger = Logger();

/// Cache for meditation segments and TTS audio to reduce API usage
class MeditationCache {
  static const String _segmentCacheKey = 'meditation_segments_cache';
  static const int _maxCachedSegments = 50;
  static const Duration _cacheExpiry = Duration(days: 7);
  
  /// Get cached meditation segment based on stress level
  static Future<String?> getCachedSegment({
    required double stressLevel,
    required String meditationStyle,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString(_segmentCacheKey);
      
      if (cacheJson == null) return null;
      
      final cache = jsonDecode(cacheJson) as Map<String, dynamic>;
      
      // Create key based on stress level bucket and style
      final stressBucket = (stressLevel / 10).floor() * 10; // Round to nearest 10
      final key = '${meditationStyle}_$stressBucket';
      
      if (cache.containsKey(key)) {
        final entry = cache[key] as Map<String, dynamic>;
        final timestamp = DateTime.parse(entry['timestamp']);
        
        // Check if expired
        if (DateTime.now().difference(timestamp) < _cacheExpiry) {
          _logger.i('✓ Using cached segment for stress ~$stressBucket%, style=$meditationStyle');
          return entry['text'] as String;
        }
      }
      
      return null;
    } catch (e) {
      _logger.w('Error reading segment cache: $e');
      return null;
    }
  }
  
  /// Cache a meditation segment
  static Future<void> cacheSegment({
    required double stressLevel,
    required String meditationStyle,
    required String text,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString(_segmentCacheKey);
      
      Map<String, dynamic> cache = {};
      if (cacheJson != null) {
        cache = jsonDecode(cacheJson) as Map<String, dynamic>;
      }
      
      // Create key based on stress level bucket and style
      final stressBucket = (stressLevel / 10).floor() * 10;
      final key = '${meditationStyle}_$stressBucket';
      
      cache[key] = {
        'text': text,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      // Limit cache size
      if (cache.length > _maxCachedSegments) {
        // Remove oldest entries
        final entries = cache.entries.toList();
        entries.sort((a, b) {
          final aTime = DateTime.parse(a.value['timestamp']);
          final bTime = DateTime.parse(b.value['timestamp']);
          return aTime.compareTo(bTime);
        });
        cache = Map.fromEntries(entries.skip(cache.length - _maxCachedSegments));
      }
      
      await prefs.setString(_segmentCacheKey, jsonEncode(cache));
      _logger.i('✓ Cached segment for stress ~$stressBucket%, style=$meditationStyle');
    } catch (e) {
      _logger.w('Error caching segment: $e');
    }
  }
  
  /// Get cached TTS audio file
  static Future<File?> getCachedAudio(String text) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/tts_cache');
      
      if (!await cacheDir.exists()) return null;
      
      // Use hash of text as filename
      final hash = text.hashCode.abs().toString();
      final file = File('${cacheDir.path}/$hash.mp3');
      
      if (await file.exists()) {
        final stat = await file.stat();
        // Check if file is less than 7 days old
        if (DateTime.now().difference(stat.modified) < _cacheExpiry) {
          _logger.i('✓ Using cached TTS audio (${text.length} chars)');
          return file;
        } else {
          // Delete expired file
          await file.delete();
        }
      }
      
      return null;
    } catch (e) {
      _logger.w('Error reading audio cache: $e');
      return null;
    }
  }
  
  /// Cache TTS audio file
  static Future<File?> cacheAudio(String text, List<int> audioBytes) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/tts_cache');
      
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      
      final hash = text.hashCode.abs().toString();
      final file = File('${cacheDir.path}/$hash.mp3');
      
      await file.writeAsBytes(audioBytes);
      _logger.i('✓ Cached TTS audio (${text.length} chars, ${audioBytes.length} bytes)');
      
      // Clean old cache files if directory is too large
      await _cleanOldCacheFiles(cacheDir);
      
      return file;
    } catch (e) {
      _logger.w('Error caching audio: $e');
      return null;
    }
  }
  
  static Future<void> _cleanOldCacheFiles(Directory cacheDir) async {
    try {
      final files = await cacheDir.list().toList();
      
      // If more than 100 files, delete oldest ones
      if (files.length > 100) {
        final fileStats = <File, DateTime>{};
        
        for (var entity in files) {
          if (entity is File) {
            final stat = await entity.stat();
            fileStats[entity] = stat.modified;
          }
        }
        
        // Sort by modification time
        final sortedFiles = fileStats.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        
        // Delete oldest 20 files
        for (var i = 0; i < 20 && i < sortedFiles.length; i++) {
          await sortedFiles[i].key.delete();
        }
        
        _logger.i('Cleaned ${20} old TTS cache files');
      }
    } catch (e) {
      _logger.w('Error cleaning cache: $e');
    }
  }
  
  /// Clear all caches
  static Future<void> clearAll() async {
    try {
      // Clear segment cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_segmentCacheKey);
      
      // Clear audio cache
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/tts_cache');
      
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
      
      _logger.i('✓ Cleared all meditation caches');
    } catch (e) {
      _logger.w('Error clearing caches: $e');
    }
  }
}

/// Fallback meditation texts when API is unavailable - fully personalized
class FallbackMeditationTexts {
  /// Generate personalized opening text
  static String getOpening({String? name, String? environment, String? style}) {
    final hasName = name != null && name.isNotEmpty;
    final env = _getEnvironmentDescription(environment);
    
    final openings = [
      "${hasName ? '$name, let\'s' : 'Let\'s'} begin by finding a comfortable position. ${env['settle']} Allow your body to relax and settle into this peaceful space.",
      "${hasName ? '$name, take' : 'Take'} a moment to arrive fully here. ${env['notice']} Notice how your body feels right now, supported and safe.",
      "${hasName ? '$name, welcome' : 'Welcome'} to this meditation. ${env['begin']} Let's start by taking a few deep breaths together.",
    ];
    
    return openings[DateTime.now().millisecond % openings.length];
  }
  
  /// Generate personalized breathing segment
  static String getBreathingSegment({String? name, String? environment, String? style}) {
    final env = _getEnvironmentDescription(environment);
    final styleGuidance = _getStyleBreathingGuidance(style);
    
    final segments = [
      "${styleGuidance['intro']} Breathe in slowly through your nose, ${env['breathIn']}. Hold for a moment. Now exhale gently, ${env['breathOut']}. Let's continue with this peaceful rhythm.",
      "${styleGuidance['focus']} Notice the natural flow of your breath. In and out. ${env['rhythm']} Each breath bringing you deeper into relaxation. There's nothing you need to do but breathe.",
      "Focus on your breathing. ${styleGuidance['feeling']} Feel the air entering your body, bringing calm energy. As you exhale, ${env['release']} let go of any stress or worry.",
    ];
    
    return segments[DateTime.now().millisecond % segments.length];
  }
  
  /// Generate personalized body relaxation segment
  static String getBodyRelaxationSegment({String? name, String? environment, String? style}) {
    final env = _getEnvironmentDescription(environment);
    final styleGuidance = _getStyleBodyGuidance(style);
    
    final segments = [
      "${styleGuidance['scan']} Scan your body from head to toe. Notice any areas of tension. ${env['melt']} As you breathe, imagine that tension melting away like snow in the sun.",
      "${styleGuidance['shoulders']} Relax your shoulders, they can drop down. Soften your jaw. ${env['heavy']} Let your entire body become heavy and relaxed, sinking deeper into comfort.",
      "Feel the support beneath you. ${styleGuidance['safe']} You are safe and grounded here. ${env['sink']} Allow yourself to sink deeper into this peaceful state.",
    ];
    
    return segments[DateTime.now().millisecond % segments.length];
  }
  
  /// Generate personalized mindfulness segment
  static String getMindfulnessSegment({String? name, String? environment, String? style}) {
    final env = _getEnvironmentDescription(environment);
    final styleGuidance = _getStyleMindfulnessGuidance(style);
    
    final segments = [
      "${styleGuidance['thoughts']} Thoughts may come and go, like ${env['metaphor']}. Observe them without judgment, then gently return to your breath.",
      "${styleGuidance['observer']} You are not your thoughts. You are the peaceful observer. ${env['calm']} Let your mind become as calm and clear as this space around you.",
      "${styleGuidance['present']} In this moment, there is nothing to fix or change. ${env['be']} Simply be present with yourself, exactly as you are.",
    ];
    
    return segments[DateTime.now().millisecond % segments.length];
  }
  
  /// Generate personalized closing text
  static String getClosing({String? name, String? environment, String? style}) {
    final namePrefix = name != null && name.isNotEmpty ? '$name, you' : 'You';
    final env = _getEnvironmentDescription(environment);
    final styleGuidance = _getStyleClosingGuidance(style);
    
    final closings = [
      "$namePrefix've done beautifully. ${styleGuidance['done']} ${env['return']} When you're ready, take a deep breath and slowly return to the present moment.",
      "${styleGuidance['thank']} Take a moment to thank yourself for this practice. ${env['transition']} Slowly begin to wiggle your fingers and toes, coming back gently.",
      "${styleGuidance['carry']} Carry this sense of calm with you. ${env['open']} Gently open your eyes when you're ready, bringing this peace into your day.",
    ];
    
    return closings[DateTime.now().millisecond % closings.length];
  }
  
  /// Get environment-specific descriptions
  static Map<String, String> _getEnvironmentDescription(String? environment) {
    switch (environment) {
      case 'calm ocean beach':
        return {
          'settle': 'Imagine the gentle waves lapping at the shore.',
          'notice': 'Feel the soft sand beneath you, the ocean breeze on your skin.',
          'begin': 'Picture yourself on a peaceful beach, the sound of waves all around.',
          'breathIn': 'filling your lungs with fresh ocean air',
          'breathOut': 'releasing tension like waves retreating from shore',
          'rhythm': 'Like the rhythmic tide,',
          'release': 'like the ocean releasing onto the shore,',
          'melt': 'Imagine the warm sun melting away all tension.',
          'heavy': 'sinking into the soft sand,',
          'sink': 'like settling into warm, soft sand',
          'metaphor': 'clouds drifting across the vast ocean sky',
          'calm': 'Let your mind become as calm as the sea at dawn.',
          'be': 'Rest here by the peaceful ocean.',
          'return': 'Hear the waves one last time.',
          'transition': 'feeling the warmth of the sun,',
          'open': 'Carry the ocean\'s peace with you.',
        };
      
      case 'quiet mountain':
        return {
          'settle': 'Imagine yourself on a serene mountaintop.',
          'notice': 'Feel the solid mountain beneath you, the crisp clean air.',
          'begin': 'Picture yourself in a quiet mountain sanctuary.',
          'breathIn': 'filling your lungs with pure mountain air',
          'breathOut': 'releasing tension down the mountainside',
          'rhythm': 'Like the steady mountain winds,',
          'release': 'like morning mist evaporating in mountain sunlight,',
          'melt': 'Like snow melting on sun-warmed rocks.',
          'heavy': 'grounded like the ancient mountain,',
          'sink': 'rooted and stable like the mountain itself',
          'metaphor': 'birds soaring past mountain peaks',
          'calm': 'Let your mind become as still as a mountain lake.',
          'be': 'Rest here in mountain serenity.',
          'return': 'Take in the mountain view one last time.',
          'transition': 'feeling the mountain\'s strength,',
          'open': 'Carry the mountain\'s calm strength with you.',
        };
      
      case 'serene forest':
        return {
          'settle': 'Imagine yourself in a peaceful forest clearing.',
          'notice': 'Feel the soft forest floor, hear the gentle rustling of leaves.',
          'begin': 'Picture yourself surrounded by calm, protective trees.',
          'breathIn': 'breathing in the fresh forest air',
          'breathOut': 'releasing like leaves floating to the ground',
          'rhythm': 'Like the gentle sway of trees,',
          'release': 'like leaves releasing from branches,',
          'melt': 'Like morning dew evaporating in dappled sunlight.',
          'heavy': 'settling like leaves on the forest floor,',
          'sink': 'surrounded by the forest\'s gentle embrace',
          'metaphor': 'leaves dancing in a gentle breeze',
          'calm': 'Let your mind become as peaceful as the forest.',
          'be': 'Rest here in the forest\'s protective calm.',
          'return': 'Listen to the forest sounds one last time.',
          'transition': 'feeling the forest\'s gentle energy,',
          'open': 'Carry the forest\'s tranquility with you.',
        };
      
      case 'gentle garden':
        return {
          'settle': 'Imagine yourself in a beautiful, peaceful garden.',
          'notice': 'Feel the soft grass, smell the gentle fragrance of flowers.',
          'begin': 'Picture yourself in a tranquil garden sanctuary.',
          'breathIn': 'breathing in the sweet scent of flowers',
          'breathOut': 'releasing like petals falling softly',
          'rhythm': 'Like flowers opening to the sun,',
          'release': 'like petals opening and releasing,',
          'melt': 'Like morning dew soaking into garden soil.',
          'heavy': 'settling into the garden\'s soft embrace,',
          'sink': 'cradled by the garden\'s gentle beauty',
          'metaphor': 'butterflies floating among blossoms',
          'calm': 'Let your mind bloom like a peaceful garden.',
          'be': 'Rest here in the garden\'s gentle care.',
          'return': 'Breathe in the garden scent one last time.',
          'transition': 'feeling the garden\'s nurturing warmth,',
          'open': 'Carry the garden\'s gentle beauty with you.',
        };
      
      default: // 'peaceful nature'
        return {
          'settle': 'Imagine yourself in a peaceful natural setting.',
          'notice': 'Feel the earth supporting you, the gentle air around you.',
          'begin': 'Picture yourself surrounded by nature\'s calm beauty.',
          'breathIn': 'filling your lungs with fresh, clean air',
          'breathOut': 'releasing tension back to the earth',
          'rhythm': 'Like nature\'s gentle rhythms,',
          'release': 'like nature releasing what it doesn\'t need,',
          'melt': 'Like ice melting into a peaceful stream.',
          'heavy': 'grounded by nature\'s support,',
          'sink': 'held gently by the natural world',
          'metaphor': 'clouds drifting across the sky',
          'calm': 'Let your mind become as peaceful as nature.',
          'be': 'Rest here in nature\'s embrace.',
          'return': 'Feel nature\'s presence one last time.',
          'transition': 'feeling nature\'s gentle energy,',
          'open': 'Carry nature\'s peace with you.',
        };
    }
  }
  
  /// Get style-specific breathing guidance
  static Map<String, String> _getStyleBreathingGuidance(String? style) {
    switch (style) {
      case 'gentle and soothing':
        return {
          'intro': 'Very gently and softly,',
          'focus': 'With the utmost gentleness,',
          'feeling': 'So softly and tenderly,',
        };
      case 'warm and compassionate':
        return {
          'intro': 'With kindness toward yourself,',
          'focus': 'Being gentle with yourself,',
          'feeling': 'With warmth and care,',
        };
      case 'peaceful and mindful':
        return {
          'intro': 'Simply observe and notice,',
          'focus': 'Without forcing or controlling,',
          'feeling': 'With mindful awareness,',
        };
      default: // 'calm and empathetic'
        return {
          'intro': 'Take a moment to simply breathe.',
          'focus': 'Let yourself settle into the breath.',
          'feeling': 'Breathe naturally and easily,',
        };
    }
  }
  
  /// Get style-specific body guidance
  static Map<String, String> _getStyleBodyGuidance(String? style) {
    switch (style) {
      case 'gentle and soothing':
        return {
          'scan': 'Very gently and lovingly,',
          'shoulders': 'With the softest touch,',
          'safe': 'You are completely safe and cared for.',
        };
      case 'warm and compassionate':
        return {
          'scan': 'With compassion for yourself,',
          'shoulders': 'Be kind to your body,',
          'safe': 'You deserve this rest and care.',
        };
      case 'peaceful and mindful':
        return {
          'scan': 'Simply observe your body,',
          'shoulders': 'Notice without judgment,',
          'safe': 'You are exactly where you need to be.',
        };
      default: // 'calm and empathetic'
        return {
          'scan': 'Gently and with care,',
          'shoulders': 'Allow your body to relax,',
          'safe': 'You are supported and at peace.',
        };
    }
  }
  
  /// Get style-specific mindfulness guidance
  static Map<String, String> _getStyleMindfulnessGuidance(String? style) {
    switch (style) {
      case 'gentle and soothing':
        return {
          'thoughts': 'Very gently,',
          'observer': 'You are safe within yourself.',
          'present': 'Everything is okay right now.',
        };
      case 'warm and compassionate':
        return {
          'thoughts': 'With kindness toward yourself,',
          'observer': 'You are doing wonderfully.',
          'present': 'You are enough, just as you are.',
        };
      case 'peaceful and mindful':
        return {
          'thoughts': 'Simply notice and observe,',
          'observer': 'Rest in pure awareness.',
          'present': 'This moment is complete.',
        };
      default: // 'calm and empathetic'
        return {
          'thoughts': 'Understand that',
          'observer': 'You have this inner calm.',
          'present': 'You can simply be.',
        };
    }
  }
  
  /// Get style-specific closing guidance
  static Map<String, String> _getStyleClosingGuidance(String? style) {
    switch (style) {
      case 'gentle and soothing':
        return {
          'done': 'You were so gentle with yourself.',
          'thank': 'You gave yourself a beautiful gift.',
          'carry': 'Keep this softness with you.',
        };
      case 'warm and compassionate':
        return {
          'done': 'You showed yourself such care.',
          'thank': 'Appreciate the time you gave yourself.',
          'carry': 'Remember how worthy you are of this peace.',
        };
      case 'peaceful and mindful':
        return {
          'done': 'You practiced with awareness.',
          'thank': 'Honor this moment of mindfulness.',
          'carry': 'This peace is always available to you.',
        };
      default: // 'calm and empathetic'
        return {
          'done': 'You gave yourself what you needed.',
          'thank': 'This time was well spent.',
          'carry': 'You can return to this calm anytime.',
        };
    }
  }
  
  /// Get random segment based on iteration - now fully personalized
  static String getRandomSegment(int iterationCount, {String? name, String? environment, String? style}) {
    if (iterationCount == 0) {
      return getOpening(name: name, environment: environment, style: style);
    } else if (iterationCount < 3) {
      return getBreathingSegment(name: name, environment: environment, style: style);
    } else if (iterationCount < 6) {
      return getBodyRelaxationSegment(name: name, environment: environment, style: style);
    } else if (iterationCount < 9) {
      return getMindfulnessSegment(name: name, environment: environment, style: style);
    } else {
      return getClosing(name: name, environment: environment, style: style);
    }
  }
}
