// model.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'models.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart'; // Localization
import 'package:provider/provider.dart'; // Provider
import 'notifications.dart';
import 'theme.dart'; // ThemeProvider
// For calculations
import 'package:shimmer/shimmer.dart'; // Shimmer

class ModelDetailPage extends StatefulWidget {
  final String id;
  final String title;
  final String description;
  final String imagePath;
  final String size;
  final String ram;
  final String producer;
  final bool isDownloaded;
  final bool isDownloading;
  final CompatibilityStatus compatibilityStatus;
  final bool isServerSide;

  // İNDİRME İŞLEMLERİ VE BUTONLAR
  final VoidCallback? onDownloadPressed;
  final Future<void> Function()? onRemovePressed;
  final VoidCallback? onChatPressed;
  final VoidCallback? onCancelPressed;

  // YENİ: DownloadManager örneğini de constructor'a ekliyoruz.
  final DownloadManager? downloadManager;

  // Ekstra alanlar
  final String stars;
  final String features;
  final String category;
  final bool canHandleImage;
  final String parameters;
  final String context;

  const ModelDetailPage({
    super.key,
    required this.id,
    required this.title,
    required this.description,
    required this.imagePath,
    required this.size,
    required this.ram,
    required this.producer,
    required this.isDownloaded,
    required this.isDownloading,
    required this.compatibilityStatus,
    required this.isServerSide,
    this.onDownloadPressed,
    this.onRemovePressed,
    this.onChatPressed,
    this.onCancelPressed,
    this.downloadManager, // <-- YENİ parametre
    required this.stars,
    required this.features,
    required this.category,
    required this.canHandleImage,
    this.parameters = '',
    this.context = '',
  });

  @override
  _ModelDetailPageState createState() => _ModelDetailPageState();
}

class _ModelDetailPageState extends State<ModelDetailPage> {
  late bool _isDownloaded;
  late bool _isDownloading;
  int _buttonClickCount = 0;
  bool _isButtonLocked = false;
  Timer? _resetClickCountTimer;
  List<String> _parsedFeatures = [];
  Map<int, int> _starCounts = {};
  double _averageRating = 0.0; // Ortalama puan
  bool _isLoading = true;      // Loading state

  @override
  void initState() {
    super.initState();
    _isDownloaded = widget.isDownloaded;
    _isDownloading = widget.isDownloading;

    _parseStarsData();
    _parseFeaturesData();

    // Simülasyon yerine direkt _isLoading false
    setState(() {
      _isLoading = false;
    });
  }

  /// Yıldız verilerini (örn. "5stars345/4stars200/...") ayrıştırır
  void _parseStarsData() {
    final parts = widget.stars.split('/');
    final Map<int, int> result = {};

    for (var part in parts) {
      final starIndex = part.indexOf("stars");
      if (starIndex > 0) {
        final starCount = int.tryParse(part.substring(0, starIndex)) ?? 0;
        final ratingNumber = int.tryParse(part.substring(starIndex + 5)) ?? 0;
        result[starCount] = ratingNumber;
      }
    }

    // Ortalama puan
    int totalStars = 0;
    int totalCount = 0;
    result.forEach((star, count) {
      totalStars += star * count;
      totalCount += count;
    });
    double average = totalCount > 0 ? totalStars / totalCount : 0.0;

    setState(() {
      _starCounts = result;
      _averageRating = double.parse(average.toStringAsFixed(1));
    });
  }

  /// Özellikler ("features") ayrıştırılır
  void _parseFeaturesData() {
    List<String> features = [];

    // widget.features string'ini parçala
    if (widget.features.isNotEmpty) {
      final parts = widget.features.split('/');
      features.addAll(
        parts.where((feature) => feature.toLowerCase() != 'offline'),
      );
    }

    // Roleplay ise
    if (widget.category.toLowerCase() == 'roleplay') {
      features.add('roleplay');
    }
    // Fotoğraf işleme özelliği varsa
    if (widget.canHandleImage) {
      features.add('photo');
    }
    // Lokal modelse "offline" ekle
    if (!widget.isServerSide) {
      features.add('offline');
    }

    setState(() {
      _parsedFeatures = features;
    });
  }

  /// Model silme
  Future<void> _removeModel() async {
    if (widget.onRemovePressed != null) {
      await widget.onRemovePressed!();
      if (mounted) {
        setState(() {
          _isDownloaded = false;
        });
      }
      Navigator.pop(context, 'model_updated');
    }
  }

  /// Chat başlatma
  void _startChatWithModel() {
    if (widget.onChatPressed != null) {
      widget.onChatPressed!();
    }
  }

  /// Çok hızlı tıklamaya karşı koruma
  void _handleButtonPress(VoidCallback action) {
    // Server-side modeli için
    if (widget.isServerSide) {
      action();
      return;
    }

    // Lokal model + global kilit varsa
    if (_isButtonLocked) {
      final notificationService =
      Provider.of<NotificationService>(context, listen: false);
      notificationService.showNotification(
        message: AppLocalizations.of(context)!.pleaseWaitBeforeTryingAgain,
        isSuccess: false,
        bottomOffset: 19,
        fontSize: 12,
      );
      return;
    }

    _buttonClickCount++;
    if (_buttonClickCount == 1) {
      _resetClickCountTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() {
            _buttonClickCount = 0;
          });
        }
      });
    }

    if (_buttonClickCount >= 4) {
      final notificationService =
      Provider.of<NotificationService>(context, listen: false);
      notificationService.showNotification(
        message: AppLocalizations.of(context)!.pleaseWaitBeforeTryingAgain,
        isSuccess: false,
        bottomOffset: 19,
        fontSize: 12,
      );

      if (mounted) {
        setState(() {
          _isButtonLocked = true;
          _buttonClickCount = 0;
        });
      }
      _resetClickCountTimer?.cancel();
      Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _isButtonLocked = false;
          });
        }
      });
      return;
    }

    action();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final isDarkTheme = Provider.of<ThemeProvider>(context).isDarkTheme;

    // Ekran boyutlarını al
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: isDarkTheme ? const Color(0xFF090909) : Colors.white,
      appBar: _buildAppBar(localizations, isDarkTheme, screenWidth),
      bottomNavigationBar: _buildBottomActionButtons(localizations, isDarkTheme, screenWidth, screenHeight),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: _isLoading
              ? _buildShimmerScreen(isDarkTheme, screenWidth, screenHeight, key: const ValueKey('shimmer'))
              : SingleChildScrollView(
            key: const ValueKey('content'),
            padding: EdgeInsets.all(screenWidth * 0.04), // %4 padding
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildModelHeader(localizations, isDarkTheme, screenWidth),
                SizedBox(height: screenHeight * 0.02), // %2 boşluk
                _buildDescriptionSection(localizations, isDarkTheme, screenWidth),
                SizedBox(height: screenHeight * 0.02),
                _buildRatingsSection(localizations, isDarkTheme, screenWidth),
                SizedBox(height: screenHeight * 0.02),
                _buildFeaturesSection(localizations, isDarkTheme, screenWidth),
                SizedBox(height: screenHeight * 0.02),
                Center(
                  child: Text(
                    localizations.allEvaluationsByTestTeam,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDarkTheme ? Colors.white70 : Colors.black87,
                      fontSize: screenWidth * 0.028, // %2.8 font
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

// -- UPDATED APP BAR --
  PreferredSizeWidget _buildAppBar(
      AppLocalizations localizations, bool isDarkTheme, double screenWidth) {
    return AppBar(
      scrolledUnderElevation: 0,
      title: widget.downloadManager == null
          ? Text(
        widget.title,
        style: TextStyle(
          fontFamily: 'Roboto',
          color: isDarkTheme ? Colors.white : Colors.black,
          fontSize: screenWidth * 0.055, // %5.5 font
          fontWeight: FontWeight.bold,
        ),
      )
          : AnimatedBuilder(
        animation: widget.downloadManager!,
        builder: (context, _) {
          String downloadStatus = '';
          if (widget.downloadManager!.isDownloading) {
            if (widget.downloadManager!.progress >= 95) {
              downloadStatus = localizations.finalPreparation;
            } else {
              downloadStatus =
                  localizations.downloaded(widget.downloadManager!.progress.toStringAsFixed(0));
            }
          } else if (widget.downloadManager!.isPaused) {
            downloadStatus = localizations.downloadPaused;
          }

          return Row(
            children: [
              // Model Başlığı
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    color: isDarkTheme ? Colors.white : Colors.black,
                    fontSize: screenWidth * 0.055, // %5.5 font
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // İndirme Durumu ile Fade Animasyonu ve Sabit Alan
              SizedBox(
                width: screenWidth * 0.25, // %25 genişlik
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: child,
                    );
                  },
                  child: downloadStatus.isNotEmpty
                      ? FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      downloadStatus,
                      key: ValueKey<String>(downloadStatus),
                      style: TextStyle(
                        color: isDarkTheme
                            ? Colors.white70
                            : Colors.black87,
                        fontSize: screenWidth * 0.035, // %3.5 font
                      ),
                      maxLines: 1, // Ensure single line
                      overflow: TextOverflow.ellipsis, // Ellipsis for overflow
                    ),
                  )
                      : Opacity(
                    key: const ValueKey('empty'),
                    opacity: 0.0,
                    child: Text(
                      '', // Boş metin
                      style: TextStyle(
                        fontSize: screenWidth * 0.035,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      backgroundColor: isDarkTheme ? const Color(0xFF090909) : Colors.white,
      elevation: 0,
      iconTheme: IconThemeData(
        color: isDarkTheme ? Colors.white : Colors.black,
        size: screenWidth * 0.07, // %7 icon size
      ),
      actions: const [],
    );
  }


  Widget _buildModelHeader(AppLocalizations localizations, bool isDarkTheme, double screenWidth) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sol kısım: Model görseli
        Expanded(
          flex: 3,
          child: AspectRatio(
            aspectRatio: 1, // Kare oranı korur
            child: Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(screenWidth * 0.04), // Dinamik border radius
                image: DecorationImage(
                  image: AssetImage(widget.imagePath),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: screenWidth * 0.05), // Dinamik aralık
        // Sağ kısım: Sadece Model adı + producer + vb.
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Model Başlığı
              Text(
                widget.title,
                style: GoogleFonts.poppins(
                  color: isDarkTheme ? Colors.white : Colors.black,
                  fontSize: screenWidth * 0.06, // %6 font
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: screenWidth * 0.01),
              // Producer
              Text(
                widget.producer,
                style: GoogleFonts.poppins(
                  color: isDarkTheme ? Colors.white70 : Colors.black87,
                  fontSize: screenWidth * 0.04, // %4 font
                ),
              ),
              SizedBox(height: screenWidth * 0.02),
              // Lokal model için size + ram / Server-side model için parameters + context
              if (!widget.isServerSide) ...[
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    children: [
                      SvgPicture.asset(
                        'assets/storage.svg',
                        width: screenWidth * 0.05,
                        height: screenWidth * 0.05,
                        color: isDarkTheme ? Colors.white70 : Colors.black54,
                      ),
                      SizedBox(width: screenWidth * 0.02),
                      Text(
                        '${localizations.storage}: ${widget.size}',
                        style: GoogleFonts.poppins(
                          color: isDarkTheme ? Colors.white70 : Colors.black87,
                          fontSize: screenWidth * 0.04, // %4 font
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: screenWidth * 0.02),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    children: [
                      SvgPicture.asset(
                        'assets/memory.svg',
                        width: screenWidth * 0.05,
                        height: screenWidth * 0.05,
                        color: isDarkTheme ? Colors.white70 : Colors.black54,
                      ),
                      SizedBox(width: screenWidth * 0.02),
                      Text(
                        '${localizations.ram}: ${widget.ram}',
                        style: GoogleFonts.poppins(
                          color: isDarkTheme ? Colors.white70 : Colors.black87,
                          fontSize: screenWidth * 0.04, // %4 font
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    children: [
                      SvgPicture.asset(
                        'assets/parameter.svg',
                        width: screenWidth * 0.05,
                        height: screenWidth * 0.05,
                        color: isDarkTheme ? Colors.white70 : Colors.black54,
                      ),
                      SizedBox(width: screenWidth * 0.02),
                      Text(
                        '${localizations.parameters}: ${widget.parameters}',
                        style: GoogleFonts.poppins(
                          color: isDarkTheme ? Colors.white70 : Colors.black87,
                          fontSize: screenWidth * 0.04, // %4 font
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: screenWidth * 0.02),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    children: [
                      SvgPicture.asset(
                        'assets/context.svg',
                        width: screenWidth * 0.05,
                        height: screenWidth * 0.05,
                        color: isDarkTheme ? Colors.white70 : Colors.black54,
                      ),
                      SizedBox(width: screenWidth * 0.02),
                      Text(
                        '${localizations.context}: ${widget.context}',
                        style: GoogleFonts.poppins(
                          color: isDarkTheme ? Colors.white70 : Colors.black87,
                          fontSize: screenWidth * 0.04, // %4 font
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // -- SHIMMER EKRANI --
  Widget _buildShimmerScreen(bool isDarkTheme, double screenWidth, double screenHeight, {required Key key}) {
    return SingleChildScrollView(
      key: key,
      padding: EdgeInsets.all(screenWidth * 0.04),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Model Header Placeholder
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image Placeholder
              Shimmer.fromColors(
                baseColor: isDarkTheme ? Colors.grey[800]! : Colors.grey[300]!,
                highlightColor:
                isDarkTheme ? Colors.grey[700]! : Colors.grey[100]!,
                child: Container(
                  width: screenWidth * 0.3, // %30 genişlik
                  height: screenWidth * 0.3, // Oran koruması
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(screenWidth * 0.04),
                  ),
                ),
              ),
              SizedBox(width: screenWidth * 0.05),
              // Text Placeholders
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title Placeholder
                    Shimmer.fromColors(
                      baseColor:
                      isDarkTheme ? Colors.grey[800]! : Colors.grey[300]!,
                      highlightColor:
                      isDarkTheme ? Colors.grey[700]! : Colors.grey[100]!,
                      child: Container(
                        width: screenWidth * 0.5,
                        height: screenWidth * 0.05,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    SizedBox(height: screenWidth * 0.02),
                    // Producer Placeholder
                    Shimmer.fromColors(
                      baseColor:
                      isDarkTheme ? Colors.grey[800]! : Colors.grey[300]!,
                      highlightColor:
                      isDarkTheme ? Colors.grey[700]! : Colors.grey[100]!,
                      child: Container(
                        width: screenWidth * 0.4,
                        height: screenWidth * 0.04,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    SizedBox(height: screenWidth * 0.02),
                    // Another line
                    Shimmer.fromColors(
                      baseColor:
                      isDarkTheme ? Colors.grey[800]! : Colors.grey[300]!,
                      highlightColor:
                      isDarkTheme ? Colors.grey[700]! : Colors.grey[100]!,
                      child: Container(
                        width: double.infinity,
                        height: screenWidth * 0.04,
                        margin: EdgeInsets.only(top: screenWidth * 0.02),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    SizedBox(height: screenWidth * 0.02),
                    Shimmer.fromColors(
                      baseColor:
                      isDarkTheme ? Colors.grey[800]! : Colors.grey[300]!,
                      highlightColor:
                      isDarkTheme ? Colors.grey[700]! : Colors.grey[100]!,
                      child: Container(
                        width: double.infinity,
                        height: screenWidth * 0.04,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: screenHeight * 0.02),

          // Description Placeholder
          _buildShimmerSectionPlaceholder(
            isDarkTheme: isDarkTheme,
            lineCount: 3,
            height: screenWidth * 0.04,
            screenWidth: screenWidth,
          ),
          SizedBox(height: screenHeight * 0.02),

          // Ratings Section Placeholder
          _buildShimmerSectionPlaceholder(
            isDarkTheme: isDarkTheme,
            title: true,
            lineCount: 1,
            height: screenWidth * 0.05,
            screenWidth: screenWidth,
          ),
          SizedBox(height: screenWidth * 0.02),

          // Features Section Placeholder
          _buildShimmerSectionPlaceholder(
            isDarkTheme: isDarkTheme,
            title: true,
            lineCount: 4,
            height: screenWidth * 0.04,
            screenWidth: screenWidth,
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerSectionPlaceholder({
    required bool isDarkTheme,
    bool title = false,
    int lineCount = 1,
    double height = 16.0,
    required double screenWidth,
  }) {
    List<Widget> children = [];

    if (title) {
      children.add(
        Shimmer.fromColors(
          baseColor: isDarkTheme ? Colors.grey[800]! : Colors.grey[300]!,
          highlightColor: isDarkTheme ? Colors.grey[700]! : Colors.grey[100]!,
          child: Container(
            width: screenWidth * 0.5,
            height: screenWidth * 0.05,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      );
      children.add(SizedBox(height: screenWidth * 0.02));
    }
    for (int i = 0; i < lineCount; i++) {
      children.add(
        Shimmer.fromColors(
          baseColor: isDarkTheme ? Colors.grey[800]! : Colors.grey[300]!,
          highlightColor: isDarkTheme ? Colors.grey[700]! : Colors.grey[100]!,
          child: Container(
            width: double.infinity,
            height: height,
            margin: EdgeInsets.only(top: screenWidth * 0.02),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      );
      children.add(SizedBox(height: screenWidth * 0.02));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  // -- BOTTOM ACTION BUTTONS --
  Widget _buildBottomActionButtons(
      AppLocalizations localizations, bool isDarkTheme, double screenWidth, double screenHeight) {
    // Eğer server-side model ise, tek buton "Chat" olacak
    if (widget.isServerSide) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: screenWidth * 0.03,
          vertical: screenHeight * 0.01,
        ),
        decoration: BoxDecoration(
          color: isDarkTheme ? const Color(0xFF1C1C1C) : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
              offset: const Offset(0, -2),
            )
          ],
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(screenWidth * 0.05),
            topRight: Radius.circular(screenWidth * 0.05),
          ),
        ),
        child: ElevatedButton(
          onPressed: widget.onChatPressed == null
              ? null
              : () => _handleButtonPress(_startChatWithModel),
          style: ElevatedButton.styleFrom(
            backgroundColor:
            isDarkTheme ? const Color(0xFF0D31FE) : const Color(0xFF0D62FE),
            padding: EdgeInsets.symmetric(vertical: screenHeight * 0.015),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(screenWidth * 0.03),
            ),
          ),
          child: Text(
            localizations.chat,
            style: TextStyle(
              color: Colors.white,
              fontSize: screenWidth * 0.04, // %4 font
            ),
          ),
        ),
      );
    }

    // Lokal model ise, "Download/Cancel" veya "Remove/Chat"
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.04,
        vertical: screenHeight * 0.01,
      ),
      decoration: BoxDecoration(
        color: isDarkTheme ? const Color(0xFF1C1C1C) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: const Offset(0, -2),
          )
        ],
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(screenWidth * 0.05),
          topRight: Radius.circular(screenWidth * 0.05),
        ),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          );
        },
        child: !_isDownloaded
            ? _buildDownloadOrCancelButtons(localizations, isDarkTheme, screenWidth, screenHeight)
            : _buildRemoveOrChatButtons(localizations, isDarkTheme, screenWidth),
      ),
    );
  }

  // -- DOWNLOAD or CANCEL --
  Widget _buildDownloadOrCancelButtons(
      AppLocalizations localizations, bool isDarkTheme, double screenWidth, double screenHeight) {
    return _isDownloading
        ? Row(
      key: const ValueKey('cancel'),
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: widget.onCancelPressed == null
                ? null
                : () {
              _handleButtonPress(() {
                widget.onCancelPressed!();
                setState(() {
                  _isDownloading = false;
                });
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              padding: EdgeInsets.symmetric(vertical: screenHeight * 0.015),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(screenWidth * 0.03),
              ),
            ),
            child: Text(
              localizations.cancel,
              style: TextStyle(
                color: Colors.white,
                fontSize: screenWidth * 0.04, // %4 font
              ),
            ),
          ),
        ),
      ],
    )
        : Row(
      key: const ValueKey('download'),
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: widget.compatibilityStatus !=
                CompatibilityStatus.compatible ||
                widget.onDownloadPressed == null
                ? null
                : () {
              _handleButtonPress(() {
                widget.onDownloadPressed!();
                setState(() {
                  _isDownloading = true;
                });
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor:
              isDarkTheme ? Colors.white : Colors.black,
              padding: EdgeInsets.symmetric(vertical: screenHeight * 0.015),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(screenWidth * 0.03),
              ),
            ),
            child: Text(
              widget.compatibilityStatus ==
                  CompatibilityStatus.insufficientRAM
                  ? localizations.insufficientRAM
                  : widget.compatibilityStatus ==
                  CompatibilityStatus.insufficientStorage
                  ? localizations.insufficientStorage
                  : localizations.download,
              style: TextStyle(
                color: isDarkTheme ? Colors.black : Colors.white,
                fontSize: screenWidth * 0.04, // %4 font
              ),
            ),
          ),
        ),
      ],
    );
  }

  // -- REMOVE ve CHAT butonları --
  Widget _buildRemoveOrChatButtons(
      AppLocalizations localizations, bool isDarkTheme, double screenWidth) {
    return Row(
      key: const ValueKey('removeAndChat'),
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: widget.onRemovePressed == null ? null : _removeModel,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              padding: EdgeInsets.symmetric(vertical: screenWidth * 0.04),
              minimumSize: Size(double.infinity, screenWidth * 0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(screenWidth * 0.03),
              ),
            ),
            child: Text(
              localizations.remove,
              style: TextStyle(
                color: Colors.white,
                fontSize: screenWidth * 0.04, // %4 font
              ),
            ),
          ),
        ),
        SizedBox(width: screenWidth * 0.04),
        Expanded(
          child: ElevatedButton(
            onPressed:
            widget.onChatPressed == null ? null : _startChatWithModel,
            style: ElevatedButton.styleFrom(
              backgroundColor:
              isDarkTheme ? const Color(0xFF0D31FE) : const Color(0xFF0D62FE),
              padding: EdgeInsets.symmetric(vertical: screenWidth * 0.04),
              minimumSize: Size(double.infinity, screenWidth * 0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(screenWidth * 0.03),
              ),
            ),
            child: Text(
              localizations.chat,
              style: TextStyle(
                color: Colors.white,
                fontSize: screenWidth * 0.04, // %4 font
              ),
            ),
          ),
        ),
      ],
    );
  }

  // -- AÇIKLAMA (DESCRIPTION) BÖLÜMÜ --
  Widget _buildDescriptionSection(
      AppLocalizations localizations, bool isDarkTheme, double screenWidth) {
    return _buildSectionContainer(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(localizations, 'descriptionSection', isDarkTheme, screenWidth),
          SizedBox(height: screenWidth * 0.02),
          Text(
            widget.description,
            style: TextStyle(
              color: isDarkTheme ? Colors.white70 : Colors.black87,
              fontSize: screenWidth * 0.04, // %4 font
              height: 1.6,
            ),
          ),
        ],
      ),
      isDarkTheme,
      screenWidth,
    );
  }

  // -- YILDIZLAR / PUANLAMA BÖLÜMÜ --
  Widget _buildRatingsSection(
      AppLocalizations localizations, bool isDarkTheme, double screenWidth) {
    return _buildSectionContainer(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSectionTitle(localizations, 'ratingSection', isDarkTheme, screenWidth),
            ],
          ),
          SizedBox(height: screenWidth * 0.02),
          _buildStarRatingChart(isDarkTheme, screenWidth),
        ],
      ),
      isDarkTheme,
      screenWidth,
    );
  }

  Widget _buildStarRatingChart(bool isDarkTheme, double screenWidth) {
    if (_starCounts.isEmpty) {
      return Text(
        AppLocalizations.of(context)!.noRatingDataFound,
        style: TextStyle(
          color: isDarkTheme ? Colors.white70 : Colors.black87,
          fontSize: screenWidth * 0.04, // %4 font
        ),
      );
    }
    final int totalCount = _starCounts.values.isNotEmpty
        ? _starCounts.values.reduce((a, b) => a + b)
        : 1;

    final List<int> starOrder = [5, 4, 3, 2, 1];
    return Column(
      children: starOrder.map((star) {
        final int count = _starCounts[star] ?? 0;
        final double ratio = totalCount > 0 ? count / totalCount : 0.0;
        return Padding(
          padding: EdgeInsets.symmetric(vertical: screenWidth * 0.01),
          child: Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SvgPicture.asset(
                    'assets/star.svg',
                    width: screenWidth * 0.06,
                    height: screenWidth * 0.06,
                    color: isDarkTheme ? Colors.white : Colors.black,
                  ),
                  Text(
                    '$star',
                    style: TextStyle(
                      color: isDarkTheme ? Colors.black : Colors.white,
                      fontSize: screenWidth * 0.03, // %3 font
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              SizedBox(width: screenWidth * 0.02),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(screenWidth * 0.02),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: screenWidth * 0.02, // %2 height
                    backgroundColor: isDarkTheme
                        ? Colors.white12
                        : Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isDarkTheme ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // -- ÖZELLİKLER BÖLÜMÜ --
  Widget _buildFeaturesSection(
      AppLocalizations localizations, bool isDarkTheme, double screenWidth) {
    if (_parsedFeatures.isEmpty) {
      return const SizedBox.shrink();
    }
    final Map<String, String> featureTitles = {
      'photo': localizations.featurePhotoTitle,
      'offline': localizations.featureOfflineTitle,
      'supermodel': localizations.featureSupermodelTitle,
      'roleplay': localizations.featureRoleplayTitle,
    };
    final Map<String, String> featureDescriptions = {
      'photo': localizations.featurePhotoDescription,
      'offline': localizations.featureOfflineDescription,
      'supermodel': localizations.featureSupermodelDescription,
      'roleplay': localizations.featureRoleplayDescription,
    };

    List<Widget> items = [];
    for (int i = 0; i < _parsedFeatures.length; i++) {
      final featureKey = _parsedFeatures[i];
      if (!featureTitles.containsKey(featureKey)) {
        continue;
      }
      items.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              featureTitles[featureKey] ?? '',
              style: TextStyle(
                color: isDarkTheme ? Colors.white : Colors.black,
                fontSize: screenWidth * 0.04, // %4 font
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: screenWidth * 0.01),
            Text(
              featureDescriptions[featureKey] ?? '',
              style: TextStyle(
                color: isDarkTheme ? Colors.white70 : Colors.black87,
                fontSize: screenWidth * 0.035, // %3.5 font
              ),
            ),
          ],
        ),
      );
      if (i < _parsedFeatures.length - 1) {
        items.add(SizedBox(height: screenWidth * 0.02));
        items.add(
          Divider(
            color: isDarkTheme ? Colors.grey[700] : Colors.grey[300],
            thickness: 1,
          ),
        );
        items.add(SizedBox(height: screenWidth * 0.02));
      } else {
        items.add(SizedBox(height: screenWidth * 0.02));
      }
    }

    return _buildSectionContainer(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(localizations, 'featuresSection', isDarkTheme, screenWidth),
          SizedBox(height: screenWidth * 0.02),
          ...items,
        ],
      ),
      isDarkTheme,
      screenWidth,
    );
  }

  Widget _buildSectionTitle(
      AppLocalizations localizations, String sectionKey, bool isDarkTheme, double screenWidth) {
    String sectionTitle;
    switch (sectionKey) {
      case 'descriptionSection':
        sectionTitle = localizations.descriptionSection;
        break;
      case 'ratingSection':
        sectionTitle = localizations.ratingsSection;
        break;
      case 'featuresSection':
        sectionTitle = localizations.capabilitiesSection;
        break;
      default:
        sectionTitle = '';
    }
    return Text(
      sectionTitle,
      style: TextStyle(
        color: isDarkTheme ? Colors.white : Colors.black,
        fontSize: screenWidth * 0.05, // %5 font
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildSectionContainer(Widget child, bool isDarkTheme, double screenWidth) {
    return Container(
      decoration: BoxDecoration(
        color: isDarkTheme ? const Color(0xFF1C1C1C) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(screenWidth * 0.04), // Dinamik border radius
      ),
      padding: EdgeInsets.all(screenWidth * 0.04), // %4 padding
      child: child,
    );
  }
}