import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OCRService {
  OCRService._();
  static final OCRService instance = OCRService._();

  final _picker = ImagePicker();
  final _textRecognizer = TextRecognizer();

  /// Scan receipt from camera
  Future<ReceiptData?> scanFromCamera() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      
      if (image == null) return null;
      
      return await _processImage(image.path);
    } catch (e) {
      print('Error scanning from camera: $e');
      return null;
    }
  }

  /// Scan receipt from gallery
  Future<ReceiptData?> scanFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      
      if (image == null) return null;
      
      return await _processImage(image.path);
    } catch (e) {
      print('Error scanning from gallery: $e');
      return null;
    }
  }

  /// Process image and extract receipt data
  Future<ReceiptData> _processImage(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

    // Extract text lines
    final List<String> lines = [];
    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        lines.add(line.text.trim());
      }
    }

    // Parse receipt data
    return await _parseReceiptLines(lines, imagePath);
  }

  /// Parse text lines to extract receipt information
  Future<ReceiptData> _parseReceiptLines(List<String> lines, String imagePath) async {
    String? merchantName;
    String? date;
    double? totalAmount;
    final List<ReceiptItem> items = [];

    // Common patterns
    final amountPattern = RegExp(r'(?:Rp\.?\s*)?(\d{1,3}(?:[.,]\d{3})*(?:[.,]\d{2})?)');
    final datePattern = RegExp(r'(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})');
    
    // Keywords for identifying total
    final totalKeywords = ['total', 'grand total', 'sub total', 'jumlah', 'amount'];
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].toLowerCase();
      final originalLine = lines[i];

      // Extract merchant name (usually first non-empty line)
      if (merchantName == null && originalLine.length > 3 && !_isNumericLine(originalLine)) {
        merchantName = originalLine;
      }

      // Extract date
      if (date == null) {
        final dateMatch = datePattern.firstMatch(originalLine);
        if (dateMatch != null) {
          date = dateMatch.group(1);
        }
      }

      // Extract total amount
      if (totalAmount == null) {
        for (final keyword in totalKeywords) {
          if (line.contains(keyword)) {
            final amountMatch = amountPattern.firstMatch(originalLine);
            if (amountMatch != null) {
              final amountStr = amountMatch.group(1)!.replaceAll(RegExp(r'[.,]'), '');
              totalAmount = double.tryParse(amountStr);
              if (totalAmount != null && totalAmount > 100) {
                // Adjust for decimal places
                totalAmount = totalAmount / 100;
              }
              break;
            }
          }
        }
      }

      // Extract items (lines with both text and numbers)
      if (_looksLikeItem(originalLine)) {
        final amountMatch = amountPattern.firstMatch(originalLine);
        if (amountMatch != null) {
          final itemName = originalLine.substring(0, amountMatch.start).trim();
          final amountStr = amountMatch.group(1)!.replaceAll(RegExp(r'[.,]'), '');
          var amount = double.tryParse(amountStr);
          
          if (amount != null && itemName.isNotEmpty) {
            if (amount > 100) {
              amount = amount / 100;
            }
            items.add(ReceiptItem(name: itemName, price: amount));
          }
        }
      }
    }

    // If total not found but items exist, calculate from items
    if (totalAmount == null && items.isNotEmpty) {
      totalAmount = items.fold<double>(0, (sum, item) => sum + item.price);
    }

    // If total still not found, try to extract any large number
    if (totalAmount == null) {
      for (final line in lines.reversed) {
        final match = amountPattern.firstMatch(line);
        if (match != null) {
          final amountStr = match.group(1)!.replaceAll(RegExp(r'[.,]'), '');
          var amount = double.tryParse(amountStr);
          if (amount != null && amount > 1000) {
            totalAmount = amount / 100;
            break;
          }
        }
      }
    }

    return ReceiptData(
      merchantName: merchantName ?? 'Toko',
      date: date,
      totalAmount: totalAmount ?? 0,
      items: items,
      rawText: lines.join('\n'),
      imagePath: imagePath,
    );
  }

  bool _isNumericLine(String line) {
    return RegExp(r'^\d+[.,\d]*$').hasMatch(line.trim());
  }

  bool _looksLikeItem(String line) {
    // Item line usually has both text and numbers
    final hasText = RegExp(r'[a-zA-Z]{2,}').hasMatch(line);
    final hasNumber = RegExp(r'\d{3,}').hasMatch(line);
    return hasText && hasNumber;
  }

  void dispose() {
    _textRecognizer.close();
  }
}

class ReceiptData {
  final String merchantName;
  final String? date;
  final double totalAmount;
  final List<ReceiptItem> items;
  final String rawText;
  final String imagePath;

  ReceiptData({
    required this.merchantName,
    this.date,
    required this.totalAmount,
    this.items = const [],
    required this.rawText,
    required this.imagePath,
  });

  @override
  String toString() {
    return 'Receipt from $merchantName: Rp ${totalAmount.toStringAsFixed(0)} (${items.length} items)';
  }
}

class ReceiptItem {
  final String name;
  final double price;

  ReceiptItem({required this.name, required this.price});

  @override
  String toString() => '$name - Rp ${price.toStringAsFixed(0)}';
}
