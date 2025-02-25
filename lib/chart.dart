import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'theme.dart'; // AppColors ve ThemeProvider burada tanımlı

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

    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _storageAnimation = Tween<double>(begin: 0, end: widget.usedStorage.toDouble())
        .animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));

    _memoryAnimation = Tween<double>(begin: 0, end: widget.usedMemory.toDouble())
        .animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // ThemeProvider'dan mevcut temayı al ve AppColors.currentTheme değerini güncelle
    final themeProvider = Provider.of<ThemeProvider>(context);
    AppColors.currentTheme = themeProvider.currentTheme;

    // AppColors üzerinden sistem grafiği için renk değerlerini alıyoruz.
    final barUsedColor = AppColors.storageUsed;
    final barTotalColor = AppColors.storageTotal;
    final memoryUsedColor = AppColors.memoryUsed;
    final memoryTotalColor = AppColors.memoryTotal;
    final dividerColor = AppColors.quinaryColor;

    // Etiket yazılarının rengi, tema fark etmeksizin kontrast için belirlenebilir.
    final labelColor = AppColors.opposedPrimaryColor;
    final barHeight = screenHeight * 0.03;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: screenHeight * 0.02),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Etiketler sütunu
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Transform.translate(
                    offset: const Offset(0, -8),
                    child: Text(
                      localizations.usedStorage.split(' ').join('\n'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: labelColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.03),
                  Transform.translate(
                    offset: const Offset(0, -8),
                    child: Text(
                      localizations.usedMemory.split(' ').join('\n'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: labelColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              SizedBox(width: screenWidth * 0.015),
              VerticalDivider(
                width: screenWidth * 0.012,
                thickness: 1,
                color: dividerColor,
              ),
              SizedBox(width: screenWidth * 0.02),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Depolama çubuğu animasyonu
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
                    SizedBox(height: screenHeight * 0.015),
                    // Bellek çubuğu animasyonu
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
        SizedBox(height: screenHeight * 0.02),
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
        // Animasyonlu çubuk
        Stack(
          children: [
            Container(
              width: double.infinity,
              height: height,
              decoration: BoxDecoration(
                color: colorTotal,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
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
        SizedBox(height: height * 0.166),
        // Değer ve yüzde bilgisi
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${usedValue.toInt()} | ${totalValue.toInt()} MB',
              style: TextStyle(
                fontSize: height * 0.416,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${percentage.toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: height * 0.416,
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