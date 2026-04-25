import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Top-level function for background isolate PDF extraction
String _extractTextIsolate(List<int> bytes) {
  try {
    final PdfDocument document = PdfDocument(inputBytes: bytes);
    final PdfTextExtractor extractor = PdfTextExtractor(document);
    
    StringBuffer textBuffer = StringBuffer();
    // Cap at 10 pages maximum to prevent slow extraction
    int maxPages = document.pages.count < 10 ? document.pages.count : 10;
    
    for (int i = 0; i < maxPages; i++) {
      textBuffer.write(extractor.extractText(startPageIndex: i, endPageIndex: i));
      if (textBuffer.length >= 15000) {
        break; // Stop extracting early if we have enough context
      }
    }
    
    document.dispose();
    return textBuffer.toString();
  } catch (e) {
    print("Error extracting PDF text: $e");
    return "";
  }
}

/// Service that generates quizzes from PDF documents using client-side Gemini AI.
class GeminiService {
  late final GenerativeModel _model;

  GeminiService() {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? "";
    _model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: apiKey,
    );
  }

  /// Generates 10 MCQs from a given PDF's bytes using client-side Gemini AI.
  Future<List<Map<String, dynamic>>?> generateQuizFromPdf(List<int> pdfBytes) async {
    final stopwatch = Stopwatch()..start();
    print("GeminiService: Starting PDF extraction...");
    
    // Extract text synchronously on the main thread.
    // We cap it at 10 pages so it won't freeze the UI for long, 
    // avoiding the silent crashes/deadlocks that can happen with compute.
    String extractedText = _extractTextIsolate(pdfBytes);

    print("GeminiService: PDF extraction took ${stopwatch.elapsedMilliseconds}ms. Extracted ${extractedText.length} chars.");

    if (extractedText.isEmpty) {
      throw Exception("Could not extract any text from the document.");
    }

    // Truncate text to significantly speed up network upload and Gemini processing time.
    if (extractedText.length > 15000) {
      extractedText = extractedText.substring(0, 15000);
      print("GeminiService: Truncated text to 15000 chars.");
    }

    const prompt = """
    You are an educational assistant. 
    Analyze the provided text and generate 10 multiple-choice questions (MCQs).
    Each question must have:
    1. 'question': The question text.
    2. 'options': A list of 4 possible answers.
    3. 'correctIndex': The 0-based index of the correct answer in the options list.

    Return the result ONLY as a valid JSON object with a single key 'questions'.
    Do not include markdown formatting or extra text.

    Text:
    """;

    try {
      print("GeminiService: Calling Gemini API...");
      final apiStopwatch = Stopwatch()..start();
      
      final content = [Content.text(prompt + extractedText)];
      final response = await _model.generateContent(content);
      
      print("GeminiService: Gemini API returned in ${apiStopwatch.elapsedMilliseconds}ms.");
      
      final textResponse = response.text;
      if (textResponse == null) throw Exception("Empty response from Gemini.");

      // Strip potential markdown code blocks
      final cleanJson = textResponse.replaceAll('```json', '').replaceAll('```', '').trim();
      
      print("GeminiService: Parsing JSON response...");
      final Map<String, dynamic> data = jsonDecode(cleanJson);
      
      if (data['questions'] != null) {
        print("GeminiService: Successfully generated ${((data['questions'] as List).length)} questions.");
        return (data['questions'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (e) {
      print("GeminiService: Error generating quiz with client Gemini: $e");
      throw Exception("Failed to generate quiz: $e");
    }

    return null;
  }
}
