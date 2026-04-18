import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Service that generates quizzes from PDF documents.
///
/// PDF text extraction happens on the client (no need to upload the PDF).
/// The extracted text is sent to a Firebase Cloud Function that holds the
/// Gemini API key server-side, preventing client-side key exposure.
class GeminiService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

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

  /// Generates 10 MCQs from a given PDF's bytes.
  ///
  /// Extracts text locally, then calls the `generateQuiz` Cloud Function
  /// which proxies the Gemini API securely.
  Future<List<Map<String, dynamic>>?> generateQuizFromPdf(List<int> pdfBytes) async {
    final extractedText = _extractTextFromPdf(pdfBytes);

    if (extractedText.isEmpty) {
      throw Exception("Could not extract any text from the document.");
    }

    try {
      final callable = _functions.httpsCallable(
        'generateQuiz',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
      );

      final result = await callable.call<Map<String, dynamic>>({
        'text': extractedText,
      });

      final data = result.data;
      if (data['questions'] != null) {
        return (data['questions'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (e) {
      debugPrint("Error calling generateQuiz Cloud Function: $e");
      throw Exception("Failed to generate quiz: $e");
    }

    return null;
  }
}
