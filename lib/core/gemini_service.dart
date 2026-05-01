import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Top-level function for background isolate PDF extraction.
/// Must be a top-level or static function to work with compute().
String _extractTextIsolate(List<int> bytes) {
  try {
    final PdfDocument document = PdfDocument(inputBytes: bytes);
    final PdfTextExtractor extractor = PdfTextExtractor(document);

    final StringBuffer textBuffer = StringBuffer();
    // Cap at 6 pages — enough context, keeps payload small
    final int maxPages =
        document.pages.count < 6 ? document.pages.count : 6;

    for (int i = 0; i < maxPages; i++) {
      textBuffer
          .write(extractor.extractText(startPageIndex: i, endPageIndex: i));
      if (textBuffer.length >= 8000) break;
    }

    document.dispose();
    return textBuffer.toString();
  } catch (_) {
    return '';
  }
}

/// Robustly extracts a JSON object from a (possibly noisy or partial) string.
/// Scans for the first '{' and last matching '}' so stray text is ignored.
Map<String, dynamic>? _tryParseJson(String raw) {
  final String cleaned = raw
      .replaceAll('```json', '')
      .replaceAll('```', '')
      .trim();

  final int start = cleaned.indexOf('{');
  if (start == -1) return null;

  // Find the closing brace that matches the opening one
  int depth = 0;
  int end = -1;
  for (int i = start; i < cleaned.length; i++) {
    if (cleaned[i] == '{') {
      depth++;
    } else if (cleaned[i] == '}') {
      depth--;
      if (depth == 0) {
        end = i;
        break;
      }
    }
  }

  if (end == -1) return null;

  try {
    return jsonDecode(cleaned.substring(start, end + 1)) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

/// Service that generates quizzes from PDF documents using Gemini AI.
class GeminiService {
  late final GenerativeModel _model;

  GeminiService() {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
      // gemini-2.5-flash is a thinking model — it spends tokens on internal
      // reasoning before producing output. maxOutputTokens must be large
      // enough to cover BOTH the thinking budget AND the JSON answer.
      generationConfig: GenerationConfig(
        temperature: 0.3,
        maxOutputTokens: 8192,
      ),
    );
  }

  /// Generates MCQs from a given PDF's bytes using Gemini AI.
  /// PDF text extraction runs in a background isolate to avoid UI jank.
  Future<List<Map<String, dynamic>>?> generateQuizFromPdf(
    List<int> pdfBytes,
  ) async {
    // --- Step 1: Extract text in a background isolate (non-blocking) ---
    String extractedText;
    try {
      extractedText = await compute(_extractTextIsolate, pdfBytes);
    } catch (e) {
      throw Exception('Failed to read PDF: $e');
    }

    if (extractedText.trim().isEmpty) {
      throw Exception(
        'Could not extract any text from the document. '
        'Make sure the PDF contains selectable text (not a scanned image).',
      );
    }

    // Keep the prompt payload small → faster response, less truncation risk
    if (extractedText.length > 8000) {
      extractedText = extractedText.substring(0, 8000);
    }

    // --- Step 2: Call Gemini API ---
    // 5 questions keeps the output comfortably within the token budget.
    const prompt = '''
You are an educational assistant.
Analyze the provided text and generate exactly 5 multiple-choice questions (MCQs).
Each question must have:
1. "question": A concise question (max 20 words).
2. "options": A list of exactly 4 short answers (max 10 words each).
3. "correctIndex": The 0-based index of the correct answer.

CRITICAL: Return ONLY a raw JSON object. No markdown, no code fences, no explanation.
The response must start with { and end with }.

Example format:
{"questions":[{"question":"What is X?","options":["A","B","C","D"],"correctIndex":0}]}

Text:
''';

    try {
      final content = [Content.text(prompt + extractedText)];

      // 90-second timeout — thinking models take longer than standard ones
      final response = await _model
          .generateContent(content)
          .timeout(
            const Duration(seconds: 90),
            onTimeout: () =>
                throw Exception('Quiz generation timed out. Please try again.'),
          );

      final textResponse = response.text;
      if (textResponse == null || textResponse.trim().isEmpty) {
        throw Exception('Empty response from Gemini. Please try again.');
      }

      // Use robust brace-matching parser to handle any extra text/noise
      final data = _tryParseJson(textResponse);
      if (data == null) {
        throw Exception(
          'Could not parse the quiz response. Please try again.',
        );
      }

      if (data['questions'] is List && (data['questions'] as List).isNotEmpty) {
        return (data['questions'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }

      throw Exception('No questions found in Gemini response.');
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception('Failed to generate quiz: $e');
    }
  }
}
