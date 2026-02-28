import 'dart:convert';
import 'package:http/http.dart' as http;

Future<void> main() async {
  const apiKey = 'AIzaSyA7-di1lvW9OTIJ2PD2OejEKV1Mm9-qFk4';
  
  try {
    final response = await http.get(
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=' + apiKey),
    );
    
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final models = json['models'] as List;
      print('--- Available Models ---');
      for (var model in models) {
        if (model['name'].contains('gemini')) {
          print(model['name']);
        }
      }
    } else {
      print('Failed: ' + response.statusCode.toString() + ' ' + response.body);
    }
  } catch (e) {
    print('Error: ' + e.toString());
  }
}
