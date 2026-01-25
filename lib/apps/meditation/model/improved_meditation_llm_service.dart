import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:logger/logger.dart';
import 'meditation_config.dart';
import 'user_account.dart';
import 'meditation_cache.dart';

final _logger = Logger();

/// LLM-powered meditation content generation service
///
/// Generates personalized, stress-adaptive meditation guidance using Google's Gemini.
/// Falls back to pre-generated personalized texts when API is unavailable.
///
/// Features:
/// - Real-time biosignal integration (current HR/HRV)
/// - Adaptive content based on stress levels
/// - User demographic personalization (age, preferences, style)
/// - Multi-segment sessions with natural progression
/// - Meditation style customization (calm, gentle, mindful)
/// - Environment imagery (nature, ocean, mountain, etc.)
///
/// Uses Gemini 2.0 Flash with custom system prompts for meditation guidance.
class ImprovedMeditationLLMService {
  late final GenerativeModel _model;
  ChatSession? _chatSession;
  int _iterationCount = 0;
  UserAccount? _userAccount;
  
  ImprovedMeditationLLMService() {
    _initializeModel();
  }
  
  void _initializeModel() {
    try {
      _model = GenerativeModel(
        model: 'gemini-2.0-flash-exp',
        apiKey: MeditationConfig.geminiApiKey,
        systemInstruction: Content.system(_getSystemPrompt()),
        generationConfig: GenerationConfig(
          temperature: 0.9,
          maxOutputTokens: 600,
        ),
      );
      _logger.i('✓ Improved Meditation LLM initialized');
    } catch (e) {
      _logger.e('Error initializing LLM: $e');
      rethrow;
    }
  }
  
  /// Set user account for deep personalization
  void setUserAccount(UserAccount? account) {
    _userAccount = account;
    _logger.i('User account set: ${_userAccount?.name ?? "default"}');
  }
  
  /// Get style-specific guidance for LLM
  String _getStyleGuidance(String style) {
    switch (style) {
      case 'calm and empathetic':
        return '''Your tone should be especially warm and understanding. Show deep compassion for their feelings.
Focus on emotional validation and gentle encouragement. Use phrases like "I understand", "you're safe here", "it's okay to feel this way".''';
      
      case 'gentle and soothing':
        return '''Your tone should be extra soft and nurturing, like a lullaby. Create maximum comfort and safety.
Use very slow pacing, longer pauses. Focus on creating a cocoon of peace. Emphasize softness, gentleness, and protection.''';
      
      case 'warm and compassionate':
        return '''Your tone should radiate kindness and care. Be like a supportive friend who truly understands.
Balance warmth with strength. Acknowledge challenges while building confidence. Use inclusive "we" language often.''';
      
      case 'peaceful and mindful':
        return '''Your tone should be centered and grounded. Emphasize present-moment awareness and acceptance.
Use mindfulness language: observe, notice, allow, let be. Focus on non-judgment and natural flow. Be neutral yet caring.''';
      
      default:
        return '''Your tone should be warm, empathetic, and professional.''';
    }
  }
  
  String _getSystemPrompt() {
    final userContext = _userAccount?.getLLMContext() ?? '';
    
    // Get meditation style guidance
    final style = _userAccount?.meditationStyle ?? 'calm and empathetic';
    final styleGuidance = _getStyleGuidance(style);
    
    return '''You are a highly empathetic, warm, and professional meditation guide with a naturally calming voice.
Your purpose is to lead personalized, adaptive meditations based on real-time biosignals (heart rate and HRV) and user demographics.

$userContext

MEDITATION STYLE: $style
$styleGuidance

CRITICAL GUIDELINES:
1. ALWAYS include specific breathing instructions in every segment:
   - "Breathe in slowly for 4 counts... and breathe out for 6 counts"
   - "Let's take a deep breath together... in through your nose... out through your mouth"
   - "Notice your breath... inhale deeply... exhale completely..."

2. Make it PERSONAL:
   - Use their name naturally (not every sentence, but occasionally)
   - Reference their specific stress triggers if mentioned
   - Use their preferred environment imagery
   - Adapt to their age and fitness level
   - Consider their gender when choosing imagery/language

3. This is a MULTI-SEGMENT meditation:
   - Each response is ONE segment in a longer session
   - Create natural transitions, not endings
   - Build on previous themes and progressions
   - End with gentle pauses that invite continuation
   - DO NOT say "the meditation is now over" unless explicitly asked

4. VARY your approach across segments:
   - Segment 1: Grounding, body awareness, breath focus
   - Segment 2: Progressive muscle relaxation, body scan
   - Segment 3: Calming visualization of their preferred environment
   - Segment 4+: Mix techniques, deepen relaxation, maintain engagement

5. VOICE QUALITY matters:
   - Speak slowly and clearly
   - Use soothing, descriptive language
   - Create natural pauses with ellipses (...)
   - Guide the breathing rhythm with your pacing

6. OUTPUT FORMAT:
   - Plain text only
   - No markdown, no meta-comments
   - Just the spoken meditation words
   - Approximately ${MeditationConfig.targetWordCount} words per segment

Remember: You're creating a calming, safe space for someone who is stressed. Be warm, patient, and genuinely caring.''';
  }
  
  /// Start a new meditation session
  void startNewSession() {
    _chatSession = _model.startChat();
    _iterationCount = 0;
    _logger.i('✓ New meditation session started');
  }
  
  /// Generate personalized welcome with actual biomarkers and user info
  Future<String> generatePersonalizedWelcome({
    required double currentHr,
    required double currentHrv,
    required double baselineHr,
    required double baselineHrv,
  }) async {
    try {
      final userName = _userAccount?.name ?? '';
      final nameGreeting = userName.isNotEmpty ? '$userName, ' : '';
      
      final prompt = '''Create a warm, empathetic welcome for a meditation session. 

User Info:
${_userAccount?.getLLMContext() ?? ''}

Current Biosignals:
- Heart rate: ${currentHr.toStringAsFixed(0)} BPM (baseline: ${baselineHr.toStringAsFixed(0)} BPM)
- Heart rate variability: ${currentHrv.toStringAsFixed(0)} ms (baseline: ${baselineHrv.toStringAsFixed(0)} ms)

The user is showing signs of stress. Acknowledge their current state warmly using these specific numbers. Reassure them that you'll guide them through a personalized meditation to help them find calm.

Use their name naturally if provided. Keep it under 100 words, warm and personal.''';

      final response = await _model.generateContent([Content.text(prompt)]);
      return response.text ?? "${nameGreeting}I notice your heart rate is elevated. Let's work together to bring you back to a state of calm.";
    } catch (e) {
      _logger.e('Error generating welcome: $e');
      return "Welcome. I'm here to guide you through a calming meditation. Let's begin together.";
    }
  }
  
  /// Generate adaptive meditation segment
  Future<String> generateMeditationSegment({
    required double currentHr,
    required double currentHrv,
    required double baselineHr,
    required double baselineHrv,
    required bool isStressed,
    required double stressLevel,
  }) async {
    _iterationCount++;
    
    // Try to get from cache first
    final cachedSegment = await MeditationCache.getCachedSegment(
      stressLevel: stressLevel,
      meditationStyle: _userAccount?.meditationStyle ?? 'calm and empathetic',
    );
    
    if (cachedSegment != null) {
      _logger.i('✓ Using cached segment #$_iterationCount (saves 1 API request)');
      return cachedSegment;
    }
    
    if (_chatSession == null) {
      startNewSession();
    }
    
    try {
      final prompt = _buildDetailedPrompt(
        iteration: _iterationCount,
        currentHr: currentHr,
        currentHrv: currentHrv,
        baselineHr: baselineHr,
        baselineHrv: baselineHrv,
        isStressed: isStressed,
        stressLevel: stressLevel,
      );
      
      _logger.i('Generating segment #$_iterationCount (Stress: ${stressLevel.toStringAsFixed(1)}%) - API REQUEST');
      
      final response = await _chatSession!.sendMessage(Content.text(prompt));
      final text = response.text ?? '';
      
      if (text.isEmpty) {
        throw Exception('Empty LLM response');
      }
      
      // Cache the generated segment
      await MeditationCache.cacheSegment(
        stressLevel: stressLevel,
        meditationStyle: _userAccount?.meditationStyle ?? 'calm and empathetic',
        text: text,
      );
      
      return text;
      
    } catch (e) {
      _logger.e('⚠️ LLM API Error: $e - Using personalized fallback text');
      // Use personalized fallback text when API fails
      final userName = _userAccount?.name != null && _userAccount!.name.isNotEmpty 
          ? _userAccount!.name 
          : null; // Don't use empty string - use null so greeting is omitted
      
      _logger.i('📝 FALLBACK TEXT - UserAccount.name="${_userAccount?.name}", userName=${userName ?? "(null)"}, env=${_userAccount?.preferredEnvironment}, style=${_userAccount?.meditationStyle}');
      
      final fallbackText = FallbackMeditationTexts.getRandomSegment(
        _iterationCount,
        name: userName,
        environment: _userAccount?.preferredEnvironment,
        style: _userAccount?.meditationStyle,
      );
      
      _logger.i('🎤 Generated fallback: "${fallbackText.substring(0, fallbackText.length > 100 ? 100 : fallbackText.length)}..."');
      
      return fallbackText;
    }
  }
  
  String _buildDetailedPrompt({
    required int iteration,
    required double currentHr,
    required double currentHrv,
    required double baselineHr,
    required double baselineHrv,
    required bool isStressed,
    required double stressLevel,
  }) {
    final hrChange = ((currentHr - baselineHr) / baselineHr * 100);
    final hrvChange = ((currentHrv - baselineHrv) / baselineHrv * 100);
    
    final userName = _userAccount?.name ?? '';
    final namePrefix = userName.isNotEmpty ? '$userName, ' : '';
    final age = _userAccount?.age ?? 30;
    final gender = _userAccount?.gender ?? 'other';
    final fitness = _userAccount?.fitnessLevel ?? 'moderate';
    
    // Segment focus based on iteration
    String focus = '';
    if (iteration == 1) {
      focus = '${namePrefix}start by helping them ground themselves in the present moment. Focus on breath awareness and body connection. Use calming ${_userAccount?.preferredEnvironment ?? "nature"} imagery.';
    } else if (iteration == 2) {
      focus = '${namePrefix}guide them through progressive muscle relaxation. Scan from head to toe, releasing tension. Incorporate soothing ${_userAccount?.preferredEnvironment ?? "nature"} sounds.';
    } else if (iteration == 3) {
      focus = '${namePrefix}lead them into a peaceful visualization. Create a vivid ${_userAccount?.preferredEnvironment ?? "nature"} scene that they can fully immerse in.';
    } else {
      focus = '${namePrefix}vary your techniques - breathing exercises, body awareness, peaceful imagery. Keep it fresh and engaging. Build on the relaxation you\'ve created.';
    }
    
    // Age-appropriate language
    String ageNote = '';
    if (age < 30) {
      ageNote = 'Use contemporary, relatable language.';
    } else if (age >= 60) {
      ageNote = 'Use gentle, respectful language appropriate for their life experience.';
    }
    
    return '''Meditation Segment #$iteration

User Demographics:
- Age: $age years old $ageNote
- Gender: $gender
- Fitness Level: $fitness

Current Biosignals:
- Heart Rate: ${currentHr.toStringAsFixed(0)} BPM (${hrChange >= 0 ? '+' : ''}${hrChange.toStringAsFixed(1)}% from baseline ${baselineHr.toStringAsFixed(0)} BPM)
- HRV (RMSSD): ${currentHrv.toStringAsFixed(0)} ms (${hrvChange >= 0 ? '+' : ''}${hrvChange.toStringAsFixed(1)}% from baseline ${baselineHrv.toStringAsFixed(0)} ms)
- Stress Level: ${stressLevel.toStringAsFixed(1)}%
- Status: ${isStressed ? 'Still experiencing stress - continue gentle guidance' : 'Starting to relax - maintain and deepen'}

$focus

${isStressed 
    ? 'The user needs continued support. Create a deeply calming segment with specific breathing guidance (count breaths, guide timing). Reference their elevated heart rate (${currentHr.toStringAsFixed(0)} BPM) to show you\'re aware of their state. Help them feel safe and supported.'
    : 'The user is relaxing! Acknowledge their progress. Continue with gentle breathing guidance to maintain and deepen this calm state. They\'re doing well.'}

Generate the next segment (approximately ${MeditationConfig.targetWordCount} words). MUST include specific breathing instructions. Create a natural pause at the end, not a complete ending. Make it personal and varied.''';
  }
  
  /// Generate completion message
  Future<String> generateCompletionText({
    required double startHr,
    required double startHrv,
    required double endHr,
    required double endHrv,
  }) async {
    try {
      final hrImprovement = ((startHr - endHr) / startHr * 100);
      final hrvImprovement = ((endHrv - startHrv) / startHrv * 100);
      
      final userName = _userAccount?.name ?? '';
      final namePrefix = userName.isNotEmpty ? '$userName, ' : '';
      
      final prompt = '''Create a warm, congratulatory closing message for a completed meditation session.

User: ${userName.isNotEmpty ? userName : 'the user'}

Results:
- Starting HR: ${startHr.toStringAsFixed(0)} BPM → Ending HR: ${endHr.toStringAsFixed(0)} BPM (${hrImprovement.toStringAsFixed(1)}% improvement)
- Starting HRV: ${startHrv.toStringAsFixed(0)} ms → Ending HRV: ${endHrv.toStringAsFixed(0)} ms (${hrvImprovement.toStringAsFixed(1)}% improvement)

Acknowledge their achievement, reference the specific improvements, and encourage them to carry this calm with them. Keep it under 80 words, warm and uplifting.''';

      final response = await _model.generateContent([Content.text(prompt)]);
      return response.text ?? "${namePrefix}wonderful work. You've successfully calmed your mind and body. Carry this peace with you.";
    } catch (e) {
      _logger.e('Error generating completion: $e');
      return MeditationConfig.completionText;
    }
  }
  
  String _getFallbackText(int iteration) {
    final fallbacks = [
      'Let\'s focus on your breath right now. Breathe in slowly for 4 counts... hold... and breathe out for 6 counts. Feel the tension melting away with each exhale. You\'re safe here.',
      'Notice where you feel tension in your body. Starting from your toes, consciously relax each muscle. Move up through your legs... your torso... your arms... all the way to your face. Release everything.',
      'Imagine yourself in the most peaceful place you can think of. Maybe it\'s a quiet beach, or a serene forest. Let yourself be completely present there. Breathe in the calm.',
      'You\'re doing wonderfully. Continue breathing naturally and deeply. With each breath, you\'re becoming more relaxed, more centered, more at peace. Just be here, in this moment.',
    ];
    return fallbacks[(iteration - 1) % fallbacks.length];
  }
  
  void reset() {
    _chatSession = null;
    _iterationCount = 0;
  }
  
  void dispose() {
    reset();
  }
}

