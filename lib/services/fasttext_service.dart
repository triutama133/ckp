import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class FastTextService {
  static const MethodChannel _channel = MethodChannel('ckp/fasttext');

  // Singleton
  FastTextService._();
  static final FastTextService instance = FastTextService._();

  Future<Directory> _appDir() async {
    return await getApplicationDocumentsDirectory();
  }

  Future<String> modelPath() async {
    final dir = await _appDir();
    return '${dir.path}/fasttext_model.bin';
  }

  Future<bool> isModelPresent() async {
    final p = await modelPath();
    return File(p).exists();
  }

  Future<void> downloadModel(String url, {Function(int, int)? onProgress}) async {
    final res = await http.Client().send(http.Request('GET', Uri.parse(url)));
    final total = res.contentLength ?? 0;
    final path = await modelPath();
    final file = File(path);
    final sink = file.openWrite();
    int received = 0;
    await for (final chunk in res.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (onProgress != null) onProgress(received, total);
    }
    await sink.close();
  }

  // Ask native side to load the model and run predict
  Future<List<Map<String, dynamic>>> predict(String text, {int k = 1}) async {
    final res = await _channel.invokeMethod('predict', {'text': text, 'k': k});
    // expected res: List<Map<String, dynamic>> with keys label & score
    final List out = res as List;
    return out.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> loadModel() async {
    final path = await modelPath();
    await _channel.invokeMethod('loadModel', {'path': path});
  }
}
