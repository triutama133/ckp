FastText Flutter integration notes

What I added
- `lib/services/fasttext_service.dart` - Dart front‑end for download + platform channel to native inference.
- `android/.../FastTextStub.kt` - Android Kotlin stub that registers the `ckp/fasttext` channel and exposes `loadModel` and `predict` methods. Stub returns a dummy prediction until native fastText is implemented.
- `ios/Runner/FastTextStub.swift` - iOS Swift stub for the platform channel.

How to finish native implementation
1) Android
 - Add C++ fastText lib or use JNI wrapper to load `fasttext_model.bin` and call predict.
 - Initialize `FastTextStub` from `MainActivity` by passing application context and binding messenger.
 - Return List<Map<String,Object>> for predictions.

2) iOS
 - Add fastText C++ sources and compile into iOS library, or port predictions to a small Swift model.
 - Initialize `FastTextStub` in AppDelegate and wire messenger.

Flutter usage (example)

```dart
await FastTextService.instance.downloadModel(url, onProgress: (r,t){ print('$r/$t'); });
await FastTextService.instance.loadModel();
final preds = await FastTextService.instance.predict('Transfer 20000 to savings', k:3);
print(preds);
```

Notes
- The approach keeps APK small: model is downloaded on demand, stored in app documents.
- For Android use AAR JNI or NDK to call fastText C++ model. There are community wrappers; evaluate security and license before bundling.
- Alternatively: convert fastText model to a TFLite classifier if you prefer purely Dart/TFLite runtime.
