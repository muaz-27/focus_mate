import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GeminiService {
  final GenerativeModel _model;

  GeminiService()
      : _model = GenerativeModel(
          model: 'gemini-2.5-flash',
          apiKey: dotenv.env['GEMINI_API_KEY'] ?? 'MISSING_API_KEY',
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
          ),
        );

  /// Extracts text from a PDF given its bytes
  String _extractTextFromPdf(List<int> bytes) {
    try {
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      final PdfTextExtractor extractor = PdfTextExtractor(document);
      final String text = extractor.extractText();
      document.dispose();
      return text;
    } catch (e) {
      print("Error extracting PDF text: $e");
      return "";
    }
  }

  /// Generates 10 MCQs from a given PDF's bytes
  Future<List<Map<String, dynamic>>?> generateQuizFromPdf(List<int> pdfBytes) async {
    final extractedText = _extractTextFromPdf(pdfBytes);
    
    if (extractedText.isEmpty) {
      throw Exception("Could not extract any text from the document.");
    }

    final prompt = '''
You are an expert educational quiz generator. Read the following text and generate exactly 10 multiple-choice questions (MCQs) based on the material.
Each question must have exactly 4 options. Mention the correct option index (0 to 3).

Return ONLY a JSON array, where each object looks exactly like this:
{
  "question": "The question text",
  "options": ["Option A", "Option B", "Option C", "Option D"],
  "correctIndex": 2
}

Text to analyze:
$extractedText
''';

    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      final rawText = response.text;
      
      if (rawText != null) {
        // Sometimes the API wraps json in markdown tags
        String jsonString = rawText;
        if (jsonString.startsWith('```json')) {
          jsonString = jsonString.split('```json')[1].split('```')[0].trim();
        } else if (jsonString.startsWith('```')) {
          jsonString = jsonString.split('```')[1].split('```')[0].trim();
        }
        
        final decoded = jsonDecode(jsonString);
        if (decoded is List) {
           return decoded.map((e) => e as Map<String, dynamic>).toList();
        } else if (decoded is Map && decoded.containsKey('questions')) {
           return (decoded['questions'] as List).map((e) => e as Map<String, dynamic>).toList();
        }
      }
    } catch (e) {
      print("Error calling Gemini API: $e");
      throw Exception("Failed to generate quiz: $e");
    }
    
    return null;
  }
}
