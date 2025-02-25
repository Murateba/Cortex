import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  String _currentTheme;

  ThemeProvider(this._currentTheme) {
    AppColors.currentTheme = _currentTheme;
    updateSystemUIOverlayStyle();
  }

  String get currentTheme => _currentTheme;

  void changeTheme(String theme) async {
    _currentTheme = theme;
    AppColors.currentTheme = theme;
    updateSystemUIOverlayStyle();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedTheme', theme);
  }

  void updateSystemUIOverlayStyle() {
    final themeSettings = AppColors.getSystemUIOverlayStyleForTheme(_currentTheme);

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        systemNavigationBarColor: themeSettings['navigationBarColor'] as Color,
        statusBarColor: themeSettings['statusBarColor'] as Color,
        systemNavigationBarIconBrightness: themeSettings['navigationBarIconBrightness'] as Brightness,
        statusBarIconBrightness: themeSettings['statusBarIconBrightness'] as Brightness,
      ),
    );
  }
}

class AppColors {
  static String currentTheme = '';

  static Map<String, dynamic> getSystemUIOverlayStyleForTheme(String theme) {
    switch (theme) {
      case 'dark':
        return {
          'navigationBarColor': const Color(0xFF090909),
          'statusBarColor': const Color(0xFF090909),
          'navigationBarIconBrightness': Brightness.light,
          'statusBarIconBrightness': Brightness.light,
        };
      case 'love':
        return {
          'navigationBarColor': AppColors.background,
          'statusBarColor': Colors.transparent,
          'navigationBarIconBrightness': Brightness.dark,
          'statusBarIconBrightness': Brightness.dark,
        };
      case 'light':
      default:
        return {
          'navigationBarColor': Colors.white,
          'statusBarColor': Colors.transparent,
          'navigationBarIconBrightness': Brightness.dark,
          'statusBarIconBrightness': Brightness.dark,
        };
    }
  }

  static Color get primaryColor => _getColorForTheme(
    dark: Colors.black,
    light: Colors.white,
    love: Colors.white,
  );

  static Color get opposedPrimaryColor => _getColorForTheme(
    dark: Colors.white,
    light: Colors.black,
    love: Colors.black,
  );

  static Color get secondaryColor => _getColorForTheme(
    dark: const Color(0xFF181818),
    light: const Color(0xFFF3F3F3),
    love: const Color(0xFFEAB4C3),
  );

  static Color get opposedSecondaryColor => _getColorForTheme(
    dark: const Color(0xFFEBEBEB),
    light: const Color(0xFF202020),
    love: const Color(0xFFFFF0F5),
  );

  static Color get tertiaryColor => _getColorForTheme(
    dark: const Color(0xFFE0E0E0),
    light: const Color(0xFF616161),
    love: const Color(0xFFFFE0E6),
  );

  static Color get quaternaryColor => _getColorForTheme(
    dark: const Color(0xFF141414),
    light: const Color(0xFFEBEBEB),
    love: const Color(0xFFFFDFDF),
  );

  static Color get opposedQuaternaryColor => _getColorForTheme(
    dark: const Color(0xFFEBEBEB),
    light: const Color(0xFF141414),
    love: const Color(0xFFEBEBEB),
  );

  static Color get quinaryColor => _getColorForTheme(
    dark: Colors.white70,
    light: Colors.black87,
    love: Colors.white70,
  );

  static Color get senaryColor => _getColorForTheme(
    dark: const Color(0xFF0D31FE),
    light: const Color(0xFF0D62FE),
    love: const Color(0xFFFF69B4),
  );

  static Color get background => _getColorForTheme(
    dark: const Color(0xFF090909),
    light: Colors.white,
    love: const Color(0xFFFFE0E6),
  );

  static Color get baseHighlight => _getColorForTheme(
    dark: const Color(0xFF161616),
    light: const Color(0xFFE0E0E0),
    love: const Color(0xFFFFF0F5),
  );

  static Color get dialogColor => _getColorForTheme(
    dark: const Color(0xFF161616),
    light: const Color(0xFFFFFFFF),
    love: const Color(0xFFFFF0F5),
  );

  static Color get border => _getColorForTheme(
    dark: const Color(0xFF303030),
    light: Colors.black,
    love: Colors.pink,
  );

  static Color get disabled => _getColorForTheme(
    dark: const Color(0xFF202020),
    light: const Color(0xFFEEEEEE),
    love: const Color(0xFFFFDAB9),
  );

  static Color get shimmerBase => _getColorForTheme(
    dark: const Color(0xFF424242),
    light: const Color(0xFFE0E0E0),
    love: const Color(0xFFFFC0CB),
  );
  
  static Color get shimmerHighlight => _getColorForTheme(
    dark: const Color(0xFF616161),
    light: const Color(0xFFF5F5F5),
    love: const Color(0xFFFFE4E1),
  );

  static Color get warning => _getColorForTheme(
    dark: const Color(0xFFD32F2F),
    light: Colors.red,
    love: Colors.redAccent,
  );

  static Color get uploadDialogBackground => _getColorForTheme(
    dark: const Color(0xFF424242),
    light: const Color(0xFFEEEEEE),
    love: const Color(0xFFFFE4E1),
  );

  static Color get storageUsed => _getColorForTheme(
    dark: const Color(0xFF1E88E5),
    light: const Color(0xFF42A5F5),
    love: const Color(0xFFFF69B4),
  );

  static Color get storageTotal => _getColorForTheme(
    dark: const Color(0xFFBBDEFB),
    light: const Color(0xFFE3F2FD),
    love: const Color(0xFFFFE0F0),
  );

  static Color get memoryUsed => _getColorForTheme(
    dark: const Color(0xFF43A047),
    light: const Color(0xFF66BB6A),
    love: const Color(0xFFFF69B4),
  );

  static Color get memoryTotal => _getColorForTheme(
    dark: const Color(0xFFC8E6C9),
    light: const Color(0xFFE8F5E9),
    love: const Color(0xFFFFE0F0),
  );

  static Color get unselectedIcon => _getColorForTheme(
    dark: Colors.grey,
    light: Colors.grey[600]!,
    love: Colors.grey,
  );

  static Color get shadow => _getColorForTheme(
    dark: Colors.black.withOpacity(0.3),
    light: Colors.black.withOpacity(0.1),
    love: Colors.black.withOpacity(0.1),
  );

  static Color get dialogBorder => _getColorForTheme(
    dark: Colors.white54,
    light: Colors.black26,
    love: Colors.pinkAccent,
  );

  static Color get dialogFill => _getColorForTheme(
    dark: Colors.grey[900]!,
    light: Colors.grey[100]!,
    love: Colors.pink[50] ?? Colors.pinkAccent.withOpacity(0.1),
  );

  static Color get dialogCloseButtonBackground => _getColorForTheme(
    dark: Colors.grey[900]!,
    light: Colors.grey[200]!,
    love: Colors.pink[100] ?? Colors.pinkAccent.withOpacity(0.2),
  );

  static Color get dialogDivider => _getColorForTheme(
    dark: Colors.white30,
    light: Colors.black26,
    love: Colors.pinkAccent,
  );

  static Color get textFieldBorder => _getColorForTheme(
    dark: Colors.white54,
    light: Colors.black54,
    love: Colors.pink,
  );

  static Color get skeletonContainer => _getColorForTheme(
    dark: const Color(0xFF2C2C2C),
    light: const Color(0xFFF0F0F0),
    love: const Color(0xFFFFF0F5),
  );

  static Color get dialogActionCancelText => _getColorForTheme(
    dark: Colors.white,
    light: Colors.blue,
    love: Colors.blue,
  );

  static Color get dialogActionRemoveText => _getColorForTheme(
    dark: Colors.white,
    light: Colors.red,
    love: Colors.red,
  );

  static Color get unverifiedPanelBackground => _getColorForTheme(
    dark: Colors.grey.shade900,
    light: Colors.grey.shade200,
    love: Colors.pink.shade100,
  );

  static Color get badgeBackground => _getColorForTheme(
    dark: Colors.grey.shade900,
    light: Colors.grey.shade200,
    love: Colors.pink.shade50,
  );

  static List<Color> get animatedBorderGradientColors => [
    Colors.red,
    Colors.orange,
    Colors.yellow,
    Colors.green,
    Colors.blue,
    Colors.indigo,
    Colors.purple,
    Colors.red,
  ];

  static Color _getColorForTheme({
    required Color dark,
    required Color light,
    required Color love,
  }) {
    switch (currentTheme) {
      case 'dark':
        return dark;
      case 'love':
        return love;
      case 'light':
      default:
        return light;
    }
  }
}