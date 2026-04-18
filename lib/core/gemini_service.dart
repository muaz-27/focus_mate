import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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

  /// Extracts text from a PDF given its bytes
  String _extractTextFromPdf(List<int> bytes) {
    try {
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      final PdfTextExtractor extractor = PdfTextExtractor(document);
      final String text = extractor.extractText();
      document.dispose();
      return text;
    } catch (e) {
      debugPrint("Error extracting PDF text: $e");
      return "";
    }
  }

  /// Generates 10 MCQs from a given PDF's bytes using client-side Gemini AI.
  Future<List<Map<String, dynamic>>?> generateQuizFromPdf(List<int> pdfBytes) async {
    final extractedText = _extractTextFromPdf(pdfBytes);

    if (extractedText.isEmpty) {
      throw Exception("Could not extract any text from the document.");
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
      final content = [Content.text(prompt + extractedText)];
      final response = await _model.generateContent(content);
      
      final textResponse = response.text;
      if (textResponse == null) throw Exception("Empty response from Gemini.");

      // Strip potential markdown code blocks
      final cleanJson = textResponse.replaceAll('```json', '').replaceAll('```', '').trim();
      
      final Map<String, dynamic> data = jsonDecode(cleanJson);
      
      if (data['questions'] != null) {
        return (data['questions'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (e) {
      debugPrint("Error generating quiz with client Gemini: $e");
      throw Exception("Failed to generate quiz: $e");
    }

    return null;
  }
}
