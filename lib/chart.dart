import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'theme.dart'; // ThemeProvider'ınızı içe aktardığınızdan emin olun

class SystemInfoChart extends StatefulWidget {
  final int totalStorage; // MB cinsinden toplam depolama
  final int usedStorage;  // MB cinsinden kullanılan depolama
  final int totalMemory;  // MB cinsinden toplam bellek
  final int usedMemory;   // MB cinsinden kullanılan bellek

  const SystemInfoChart({
    Key? key,
    required this.totalStorage,
    required this.usedStorage,
    required this.totalMemory,
    required this.usedMemory,
  }) : super(key: key);

  @override
  _SystemInfoChartState createState() => _SystemInfoChartState();
}

class _SystemInfoChartState extends State<SystemInfoChart> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _storageAnimation;
  late Animation<double> _memoryAnimation;

  @override
  void initState() {
    super.initState();

    // AnimationController'ı başlat
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    // Depolama ve bellek için Tween'leri başlat
    _storageAnimation = Tween<double>(begin: 0, end: widget.usedStorage.toDouble())
        .animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));

    _memoryAnimation = Tween<double>(begin: 0, end: widget.usedMemory.toDouble())
        .animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));

    // Animasyonu başlat
    _animationController.forward();
  }

  @override
  void dispose() {
    // AnimationController'ı serbest bırak
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // ThemeProvider üzerinden mevcut temayı belirle
    final isDarkTheme = Provider.of<ThemeProvider>(context).isDarkTheme;

    final barUsedColor = isDarkTheme ? Color(0xFF0f90d1) : Color(0xFF0ACEF5);
    final barTotalColor = isDarkTheme ? Color(0xFFa0d0e8) : Color(0xFFABF1FF);
    final memoryUsedColor = isDarkTheme ? Color(0xFF0fba1c) : Color(0xFF2DF013);
    final memoryTotalColor = isDarkTheme ? Color(0xFF9fcfac) : Color(0xFFB7F7B9);
    final dividerColor = isDarkTheme ? Color(0xB3FFFFFF) : Color(0xFF212121);

    final labelColor = isDarkTheme ? Colors.white : Colors.black;

    // Çubuk boyutlarını tanımla
    final barHeight = screenHeight * 0.03; // Ekran yüksekliğine göre dinamik boyut

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // Tüm içeriği sola hizala
      children: [
        // Opsiyonel üst boşluk
        SizedBox(height: screenHeight * 0.02),

        // Etiketler ve çubuklar içeren özel yatay çubuk grafik
        IntrinsicHeight( // Bölücünün dinamik yüksekliğini sağlar
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start, // Çubukların en üste hizalanmasını sağlar
            children: [
              // Etiketler sütunu
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Kullanılan Depolama Etiketi (Satır başı için hizalama)
                  Transform.translate(
                    offset: const Offset(0, -8), // Etiketi yukarı taşı
                    child: Text(
                      localizations.usedStorage.split(' ').join('\n'), // Yerelleştirilmiş metin
                      style: TextStyle(
                        fontSize: 12, // Azaltılmış font boyutu
                        fontWeight: FontWeight.w600,
                        color: labelColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.03), // İkinci çubukla hizalamak için artırılmış boşluk
                  // Kullanılan Bellek Etiketi (Satır başı için hizalama)
                  Transform.translate(
                    offset: const Offset(0, -8), // Etiketi yukarı taşı
                    child: Text(
                      localizations.usedMemory.split(' ').join('\n'), // Yerelleştirilmiş metin
                      style: TextStyle(
                        fontSize: 12, // Azaltılmış font boyutu
                        fontWeight: FontWeight.w600,
                        color: labelColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),

              // Etiketler ve bölücü arasındaki yatay boşluk
              SizedBox(width: screenWidth * 0.015), // Dinamik boşluk

              // Yatay bölücü
              VerticalDivider(
                width: screenWidth * 0.012,
                thickness: 1,
                color: dividerColor,
              ),

              // Bölücü ve çubuklar arasındaki yatay boşluk
              SizedBox(width: screenWidth * 0.02), // Dinamik boşluk

              // Çubuklar sütunu
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start, // Çubukların üste hizalanmasını sağlar
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Depolama Çubuğu ile Animasyon
                    AnimatedBuilder(
                      animation: _animationController,
                      builder: (context, child) {
                        double animatedUsedStorage = _storageAnimation.value;
                        double usedWidthFactor = widget.totalStorage > 0
                            ? animatedUsedStorage / widget.totalStorage
                            : 0;

                        return _buildAnimatedHorizontalBar(
                          usedValue: animatedUsedStorage,
                          totalValue: widget.totalStorage.toDouble(),
                          maxValue: widget.totalStorage.toDouble(),
                          colorUsed: barUsedColor,
                          colorTotal: barTotalColor,
                          height: barHeight,
                          usedWidthFactor: usedWidthFactor,
                        );
                      },
                    ),
                    SizedBox(height: screenHeight * 0.015), // Dinamik boşluk
                    // Bellek Çubuğu ile Animasyon
                    AnimatedBuilder(
                      animation: _animationController,
                      builder: (context, child) {
                        double animatedUsedMemory = _memoryAnimation.value;
                        double usedWidthFactor = widget.totalMemory > 0
                            ? animatedUsedMemory / widget.totalMemory
                            : 0;

                        return _buildAnimatedHorizontalBar(
                          usedValue: animatedUsedMemory,
                          totalValue: widget.totalMemory.toDouble(),
                          maxValue: widget.totalMemory.toDouble(),
                          colorUsed: memoryUsedColor,
                          colorTotal: memoryTotalColor,
                          height: barHeight,
                          usedWidthFactor: usedWidthFactor,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Opsiyonel alt boşluk
        SizedBox(height: screenHeight * 0.02), // Dinamik boşluk
      ],
    );
  }

  Widget _buildAnimatedHorizontalBar({
    required double usedValue,
    required double totalValue,
    required double maxValue,
    required Color colorUsed,
    required Color colorTotal,
    required double height,
    required double usedWidthFactor,
  }) {
    double percentage = maxValue > 0 ? (usedValue / maxValue) * 100 : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Çubuk konteyneri ile animasyonlu genişlik
        Stack(
          children: [
            // Toplam Kapasite Arka Planı
            Container(
              width: double.infinity,
              height: height,
              decoration: BoxDecoration(
                color: colorTotal,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            // Kullanılan Kapasite Ön Planı ile animasyonlu genişlik
            FractionallySizedBox(
              widthFactor: usedWidthFactor.clamp(0.0, 1.0),
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  color: colorUsed,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: height * 0.166), // Dinamik boşluk (4/24 = 1/6)
        // Kullanılan değer dinamik gösterimi
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${usedValue.toInt()} | ${totalValue.toInt()} MB',
              style: TextStyle(
                fontSize: height * 0.416, // Dinamik font boyutu (10/24 ≈ 0.416)
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${percentage.toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: height * 0.416, // Dinamik font boyutu (10/24 ≈ 0.416)
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ],
    );
  }
}