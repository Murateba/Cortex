// model.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'models.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'notifications.dart';
import 'theme.dart';
import 'package:shimmer/shimmer.dart';

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
  final VoidCallback? onDownloadPressed;
  final Future<void> Function()? onRemovePressed;
  final VoidCallback? onChatPressed;
  final VoidCallback? onCancelPressed;
  final DownloadManager? downloadManager;
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
    this.downloadManager,
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
  double _averageRating = 0.0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _isDownloaded = widget.isDownloaded;
    _isDownloading = widget.isDownloading;
    _parseStarsData();
    _parseFeaturesData();
    // Simülasyon yerine direkt yüklemenin bittiğini bildiriyoruz.
    setState(() {
      _isLoading = false;
    });
  }

  /// Yıldız verilerini ayrıştırır (örn. "5stars345/4stars200/...")
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

  /// Özellikleri ayrıştırır
  void _parseFeaturesData() {
    List<String> features = [];

    if (widget.features.isNotEmpty) {
      final parts = widget.features.split('/');
      features.addAll(parts.where((feature) => feature.toLowerCase() != 'offline'));
    }
    if (widget.category.toLowerCase() == 'roleplay') {
      features.add('roleplay');
    }
    if (widget.canHandleImage) {
      features.add('photo');
    }
    if (!widget.isServerSide) {
      features.add('offline');
    }

    setState(() {
      _parsedFeatures = features;
    });
  }

  /// Model silme işlemi
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

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final bool isDarkTheme = AppColors.currentTheme == 'dark';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(localizations, isDarkTheme, screenWidth),
      bottomNavigationBar:
      _buildBottomActionButtons(localizations, isDarkTheme, screenWidth, screenHeight),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: _isLoading
              ? _buildShimmerScreen(screenWidth, screenHeight,
              isDarkTheme: isDarkTheme, key: const ValueKey('shimmer'))
              : SingleChildScrollView(
            key: const ValueKey('content'),
            padding: EdgeInsets.all(screenWidth * 0.04),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildModelHeader(localizations, isDarkTheme, screenWidth),
                SizedBox(height: screenHeight * 0.02),
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
                      color: AppColors.quinaryColor,
                      fontSize: screenWidth * 0.028,
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

  PreferredSizeWidget _buildAppBar(
      AppLocalizations localizations, bool isDarkTheme, double screenWidth) {
    return AppBar(
      scrolledUnderElevation: 0,
      title: widget.downloadManager == null
          ? Text(
        widget.title,
        style: TextStyle(
          fontFamily: 'Roboto',
          color: AppColors.opposedPrimaryColor,
          fontSize: screenWidth * 0.055,
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
              downloadStatus = localizations
                  .downloaded(widget.downloadManager!.progress.toStringAsFixed(0));
            }
          } else if (widget.downloadManager!.isPaused) {
            downloadStatus = localizations.downloadPaused;
          }
          return Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    color: AppColors.opposedPrimaryColor,
                    fontSize: screenWidth * 0.055,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: screenWidth * 0.25,
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
                        color: AppColors.quinaryColor,
                        fontSize: screenWidth * 0.035,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                      : Opacity(
                    key: const ValueKey('empty'),
                    opacity: 0.0,
                    child: Text(
                      '',
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
      backgroundColor: AppColors.background,
      elevation: 0,
      iconTheme: IconThemeData(
        color: AppColors.opposedPrimaryColor,
        size: screenWidth * 0.07,
      ),
      actions: const [],
    );
  }

  Widget _buildModelHeader(
      AppLocalizations localizations, bool isDarkTheme, double screenWidth) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Model görseli
        Expanded(
          flex: 3,
          child: AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(screenWidth * 0.04),
                image: DecorationImage(
                  image: AssetImage(widget.imagePath),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: screenWidth * 0.05),
        // Model bilgileri (başlık, producer, vs.)
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: GoogleFonts.poppins(
                  color: AppColors.opposedPrimaryColor,
                  fontSize: screenWidth * 0.06,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: screenWidth * 0.01),
              Text(
                widget.producer,
                style: GoogleFonts.poppins(
                  color: AppColors.quinaryColor,
                  fontSize: screenWidth * 0.04,
                ),
              ),
              SizedBox(height: screenWidth * 0.02),
              if (!widget.isServerSide) ...[
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    children: [
                      SvgPicture.asset(
                        'assets/storage.svg',
                        width: screenWidth * 0.05,
                        height: screenWidth * 0.05,
                        color: AppColors.quinaryColor,
                      ),
                      SizedBox(width: screenWidth * 0.02),
                      Text(
                        '${localizations.storage}: ${widget.size}',
                        style: GoogleFonts.poppins(
                          color: AppColors.quinaryColor,
                          fontSize: screenWidth * 0.04,
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
                        color: AppColors.quinaryColor,
                      ),
                      SizedBox(width: screenWidth * 0.02),
                      Text(
                        '${localizations.ram}: ${widget.ram}',
                        style: GoogleFonts.poppins(
                          color: AppColors.quinaryColor,
                          fontSize: screenWidth * 0.04,
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
                        color: AppColors.quinaryColor,
                      ),
                      SizedBox(width: screenWidth * 0.02),
                      Text(
                        '${localizations.parameters}: ${widget.parameters}',
                        style: GoogleFonts.poppins(
                          color: AppColors.quinaryColor,
                          fontSize: screenWidth * 0.04,
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
                        color: AppColors.quinaryColor,
                      ),
                      SizedBox(width: screenWidth * 0.02),
                      Text(
                        '${localizations.context}: ${widget.context}',
                        style: GoogleFonts.poppins(
                          color: AppColors.quinaryColor,
                          fontSize: screenWidth * 0.04,
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

  Widget _buildShimmerScreen(double screenWidth, double screenHeight,
      {required Key key, required bool isDarkTheme}) {
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
              Shimmer.fromColors(
                baseColor: AppColors.shimmerBase,
                highlightColor: AppColors.shimmerHighlight,
                child: Container(
                  width: screenWidth * 0.3,
                  height: screenWidth * 0.3,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(screenWidth * 0.04),
                  ),
                ),
              ),
              SizedBox(width: screenWidth * 0.05),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Shimmer.fromColors(
                      baseColor: AppColors.shimmerBase,
                      highlightColor: AppColors.shimmerHighlight,
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
                    Shimmer.fromColors(
                      baseColor: AppColors.shimmerBase,
                      highlightColor: AppColors.shimmerHighlight,
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
                    Shimmer.fromColors(
                      baseColor: AppColors.shimmerBase,
                      highlightColor: AppColors.shimmerHighlight,
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
                      baseColor: AppColors.shimmerBase,
                      highlightColor: AppColors.shimmerHighlight,
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
          _buildShimmerSectionPlaceholder(
            isDarkTheme: isDarkTheme,
            lineCount: 3,
            height: screenWidth * 0.04,
            screenWidth: screenWidth,
          ),
          SizedBox(height: screenHeight * 0.02),
          _buildShimmerSectionPlaceholder(
            isDarkTheme: isDarkTheme,
            title: true,
            lineCount: 1,
            height: screenWidth * 0.05,
            screenWidth: screenWidth,
          ),
          SizedBox(height: screenWidth * 0.02),
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
          baseColor: AppColors.shimmerBase,
          highlightColor: AppColors.shimmerHighlight,
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
          baseColor: AppColors.shimmerBase,
          highlightColor: AppColors.shimmerHighlight,
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

  Widget _buildBottomActionButtons(
      AppLocalizations localizations, bool isDarkTheme, double screenWidth, double screenHeight) {
    if (widget.isServerSide) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: screenWidth * 0.03,
          vertical: screenHeight * 0.01,
        ),
        decoration: BoxDecoration(
          color: AppColors.quaternaryColor, // Renk güncellendi
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
          onPressed: widget.onChatPressed == null ? null : () => _startChatWithModel(),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.senaryColor,
            padding: EdgeInsets.symmetric(vertical: screenHeight * 0.015),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(screenWidth * 0.03),
            ),
          ),
          child: Text(
            localizations.chat,
            style: TextStyle(
              color: Colors.white,
              fontSize: screenWidth * 0.04,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.04,
        vertical: screenHeight * 0.01,
      ),
      decoration: BoxDecoration(
        color: AppColors.quaternaryColor,
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
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
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

  Widget _buildDownloadOrCancelButtons(
      AppLocalizations localizations, bool isDarkTheme, double screenWidth, double screenHeight) {
    return Row(
      key: ValueKey(_isDownloading ? 'cancel' : 'download'),
      children: [
        Expanded(
          child: _isDownloading
              ? AnimatedCancelButton(
            key: const ValueKey('cancelButton'),
            onPressed: () {
              if (widget.onCancelPressed != null) {
                widget.onCancelPressed!();
                setState(() {
                  _isDownloading = false;
                });
              }
            },
            width: double.infinity,
            height: screenHeight * 0.058,
            borderRadius: screenWidth * 0.03,
            borderColor: AppColors.opposedPrimaryColor,
            text: localizations.cancel,
            fontSize: screenWidth * 0.04,
            strokeFactor: 0.004,
          )
              : ElevatedButton(
            onPressed: widget.compatibilityStatus != CompatibilityStatus.compatible ||
                widget.onDownloadPressed == null
                ? null
                : () {
              if (_isButtonLocked) return;
              setState(() {
                _isButtonLocked = true;
                _isDownloading = true;
              });
              widget.onDownloadPressed!();
              Future.delayed(const Duration(seconds: 1), () {
                if (mounted) {
                  setState(() {
                    _isButtonLocked = false;
                  });
                }
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.opposedPrimaryColor,
              padding: EdgeInsets.symmetric(vertical: screenHeight * 0.015),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(screenWidth * 0.03),
              ),
            ),
            child: Text(
              widget.compatibilityStatus == CompatibilityStatus.insufficientRAM
                  ? localizations.insufficientRAM
                  : widget.compatibilityStatus == CompatibilityStatus.insufficientStorage
                  ? localizations.insufficientStorage
                  : localizations.download,
              style: TextStyle(
                color: AppColors.primaryColor,
                fontSize: screenWidth * 0.04,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRemoveOrChatButtons(
      AppLocalizations localizations, bool isDarkTheme, double screenWidth) {
    return Row(
      key: const ValueKey('removeAndChat'),
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: widget.onRemovePressed == null ? null : _removeModel,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
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
                fontSize: screenWidth * 0.04,
              ),
            ),
          ),
        ),
        SizedBox(width: screenWidth * 0.04),
        Expanded(
          child: ElevatedButton(
            onPressed: widget.onChatPressed == null ? null : _startChatWithModel,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.senaryColor,
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
                fontSize: screenWidth * 0.04,
              ),
            ),
          ),
        ),
      ],
    );
  }

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
              color: AppColors.quinaryColor,
              fontSize: screenWidth * 0.04,
              height: 1.6,
            ),
          ),
        ],
      ),
      isDarkTheme,
      screenWidth,
    );
  }

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
          color: AppColors.quinaryColor,
          fontSize: screenWidth * 0.04,
        ),
      );
    }
    final int totalCount =
    _starCounts.values.isNotEmpty ? _starCounts.values.reduce((a, b) => a + b) : 1;
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
                    color: AppColors.opposedPrimaryColor,
                  ),
                  Text(
                    '$star',
                    style: TextStyle(
                      color: AppColors.primaryColor,
                      fontSize: screenWidth * 0.03,
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
                    minHeight: screenWidth * 0.02,
                    backgroundColor: AppColors.border,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.opposedPrimaryColor,
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
      if (!featureTitles.containsKey(featureKey)) continue;
      items.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              featureTitles[featureKey] ?? '',
              style: TextStyle(
                color: AppColors.opposedPrimaryColor,
                fontSize: screenWidth * 0.04,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: screenWidth * 0.01),
            Text(
              featureDescriptions[featureKey] ?? '',
              style: TextStyle(
                color: AppColors.quinaryColor,
                fontSize: screenWidth * 0.035,
              ),
            ),
          ],
        ),
      );
      if (i < _parsedFeatures.length - 1) {
        items.add(SizedBox(height: screenWidth * 0.02));
        items.add(
          Divider(
            color: AppColors.border,
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
        color: AppColors.opposedPrimaryColor,
        fontSize: screenWidth * 0.05,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildSectionContainer(Widget child, bool isDarkTheme, double screenWidth) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.quaternaryColor,
        borderRadius: BorderRadius.circular(screenWidth * 0.04),
      ),
      padding: EdgeInsets.all(screenWidth * 0.04),
      child: child,
    );
  }
}