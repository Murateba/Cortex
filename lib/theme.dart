// theme_provider.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Sistem UI Overlay için gerekli

class ThemeProvider extends ChangeNotifier {
  bool _isDarkTheme;

  ThemeProvider(this._isDarkTheme) {
    updateSystemUIOverlayStyle(); // Başlangıçta doğru stili ayarla
  }

  bool get isDarkTheme => _isDarkTheme;

  void toggleTheme(bool isOn) {
    _isDarkTheme = isOn;
    updateSystemUIOverlayStyle(); // Tema değiştiğinde sistem UI'yi güncelle
    notifyListeners();
  }

  void updateSystemUIOverlayStyle({bool? hideBottomAppBar}) {
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        systemNavigationBarColor: (hideBottomAppBar == true && _isDarkTheme)
            ? const Color(0xFF090909) // #090909
            : (_isDarkTheme ? Colors.black : Colors.white),
        systemNavigationBarIconBrightness:
        _isDarkTheme ? Brightness.light : Brightness.dark,
        statusBarColor: Colors.transparent, // Durum çubuğu arka plan rengi
        statusBarIconBrightness:
        _isDarkTheme ? Brightness.light : Brightness.dark, // Durum çubuğu ikon parlaklığı
      ),
    );
  }
}