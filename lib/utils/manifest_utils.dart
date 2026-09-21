import 'package:flutter/services.dart' show rootBundle;
import 'package:xml/xml.dart';

/// Helper utility to fetch the app name dynamically from AndroidManifest.xml
class ManifestUtils {
  static String? _cachedAppName;

  static Future<String> getAppName() async {
    if (_cachedAppName != null) {
      return _cachedAppName!;
    }
    try {
      final manifestContent = await rootBundle.loadString('android/app/src/main/AndroidManifest.xml');
      final document = XmlDocument.parse(manifestContent);
      
      // Find the <application> tag and its android:label attribute
      final applicationElement = document.findAllElements('application').first;
      final label = applicationElement.getAttribute('android:label');
      
      if (label != null) {
        // Remove @string/app_name reference or return raw string
        if (label.startsWith('@string/')) {
          // Fallback to name if it's a resource reference
          _cachedAppName = 'Passport Maker';
        } else {
          _cachedAppName = label;
        }
      } else {
        _cachedAppName = 'Passport Maker';
      }
    } catch (e) {
      _cachedAppName = 'Passport Maker';
    }
    return _cachedAppName!;
  }
}
