import 'package:cortex/chat/chat.dart';
import 'package:cortex/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../models/data.dart';

class Extensions {
  static List<String> currentExtensions = [];
  static bool extensionPanelIsClosing = false;
  static String selectedExtensionLabel = '';
  static String displayedExtensionLabel = "";

  static String formatExtension(String ext) {
    List<String> parts = ext.split('-');
    List<String> capitalizedParts = parts.map((s) {
      if (s.isEmpty) return s;
      return s[0].toUpperCase() + s.substring(1);
    }).toList();
    return capitalizedParts.join(" ");
  }

  static String formatModelTitle(String title) {
    if (title.toLowerCase() == "chatgpt") {
      return "GPT";
    }
    return title;
  }

  static Future<void> setLastSelectedExtension(String mainId, String extension) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("last_extension_$mainId", extension);
  }

  /// Artık ChatScreenState örneği oluşturmak yerine,
  /// [context] parametresinden model verilerine ulaşarak varsayılan uzantıyı döndürüyoruz.
  static String defaultExtensionFor(String mainId, BuildContext context) {
    final allModels = ModelData.models(context);
    final modelData = allModels.firstWhere(
          (model) => model['id'] == mainId,
      orElse: () => {},
    );
    if (modelData.isNotEmpty && modelData.containsKey('extensions')) {
      // extensions alanı Map şeklindeyse, anahtarlar listesini kullanıyoruz.
      final extData = modelData['extensions'];
      if (extData is Map<String, dynamic>) {
        List<String> extensions = extData.keys.toList();
        if (extensions.isNotEmpty) {
          return extensions.first;
        }
      }
      // Eğer extensions alanı liste şeklinde ise:
      else if (modelData['extensions'] is List) {
        List<String> extensions = List<String>.from(modelData['extensions']);
        if (extensions.isNotEmpty) return extensions.first;
      }
    }
    return "";
  }

  static Future<String> getLastSelectedExtension(String mainId, BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    String? savedExtension = prefs.getString("last_extension_$mainId");
    if (savedExtension == null || savedExtension.isEmpty) {
      savedExtension = defaultExtensionFor(mainId, context);
    }
    return savedExtension;
  }

  static late AnimationController extensionFadeOutController;
  static late AnimationController extensionFadeInController;
  static final GlobalKey extensionKey = GlobalKey();
  static String currentBaseSeries = '';
  static OverlayEntry? extensionOverlayEntry;
  static bool isExtensionPanelClosing = false;

  static Widget buildModelExtensionSelector() {
    if (currentBaseSeries.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      key: extensionKey, // for overlay positioning
      onTap: showModelExtensionPanel,
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          buildAnimatedArrowIcon(),
        ],
      ),
    );
  }

  static void showModelExtensionPanel() {
    if (extensionOverlayEntry != null) {
      isExtensionPanelClosing = true;
      return;
    }
    ChatScreenState().insertExtensionPanel();
  }

  static Widget buildAnimatedArrowIcon() {
    double arrowOpacity = 1.0;
    if (extensionFadeOutController.isAnimating) {
      arrowOpacity = 1.0 - extensionFadeOutController.value;
    } else if (extensionFadeInController.isAnimating) {
      arrowOpacity = extensionFadeInController.value;
    }
    return AnimatedOpacity(
      opacity: arrowOpacity,
      duration: const Duration(milliseconds: 50),
      child: Transform.rotate(
        angle: 4.7124,
        child: SvgPicture.asset(
          'assets/arrov.svg',
          color: (AppColors.primaryColor.inverted).withOpacity(arrowOpacity),
          width: 20,
          height: 20,
        ),
      ),
    );
  }

  static void removeExtensionOverlay() {
    if (extensionOverlayEntry != null) {
      extensionOverlayEntry!.remove();
      extensionOverlayEntry = null;
      extensionPanelIsClosing = false;
    }
  }

  Widget buildExtensionPanelWidget({
    required BuildContext context,
    required List<MapEntry<String, String>> options,
    required String selectedExtension,
    required String modelTitle,
    required VoidCallback onDismiss,
    required Function(MapEntry<String, String>) onSelect,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final panelMaxWidth = screenWidth * 0.9;
    final optionMinHeight = screenWidth * 0.12;
    final horizontalPadding = screenWidth * 0.04;
    final verticalPadding = screenWidth * 0.02;
    final iconSize = screenWidth * 0.04;
    final panelBorderRadius = screenWidth * 0.02;
    final itemRadius = screenWidth * 0.02;
    final textStyle = TextStyle(
      color: AppColors.primaryColor,
      fontSize: screenWidth * 0.04,
    );

    double maxTextWidth = 0;
    for (var entry in options) {
      final text = "${formatModelTitle(modelTitle)} ${formatExtension(entry.key)}";
      final TextPainter tp = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      if (tp.width > maxTextWidth) {
        maxTextWidth = tp.width;
      }
    }
    double contentWidth = maxTextWidth + iconSize + (horizontalPadding * 2.5);
    double desiredWidth = contentWidth + (screenWidth * 0.025);
    double finalWidth = desiredWidth > panelMaxWidth ? panelMaxWidth : desiredWidth;

    return Material(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(panelBorderRadius),
      ),
      clipBehavior: Clip.antiAlias,
      elevation: 4.0,
      shadowColor: Colors.black26,
      color: AppColors.secondaryColor,
      child: SizedBox(
        width: finalWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < options.length; i++) ...[
              _buildExtensionButtonRow(
                context: context,
                option: options[i],
                isSelected: options[i].key == selectedExtension,
                modelTitle: modelTitle,
                iconSize: iconSize,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding,
                minHeight: optionMinHeight,
                borderRadius: _getItemBorderRadius(i, options.length, itemRadius),
                textStyle: textStyle,
                onTap: () => onSelect(options[i]),
                showBottomBorder: (i < options.length - 1),
                screenWidth: screenWidth,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExtensionButtonRow({
    required BuildContext context,
    required MapEntry<String, String> option,
    required bool isSelected,
    required String modelTitle,
    required double iconSize,
    required double horizontalPadding,
    required double verticalPadding,
    required double minHeight,
    required BorderRadius borderRadius,
    required TextStyle textStyle,
    required VoidCallback onTap,
    required bool showBottomBorder,
    required double screenWidth,
  }) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(minHeight: minHeight),
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              color: isSelected
                  ? AppColors.quaternaryColor
                  : Colors.transparent,
              border: showBottomBorder
                  ? Border(
                bottom: BorderSide(
                  color: AppColors.secondaryColor,
                  width: screenWidth * 0.003,
                ),
              )
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Transform.scale(
                  scale: isSelected ? 1.2 : 1.0,
                  child: SvgPicture.asset(
                    'assets/extension.svg',
                    width: iconSize,
                    height: iconSize,
                    color: AppColors.primaryColor.inverted,
                  ),
                ),
                SizedBox(width: horizontalPadding * 0.5),
                Flexible(
                  child: Text(
                    "${formatModelTitle(modelTitle)} ${formatExtension(option.key)}",
                    style: textStyle.copyWith(
                      color: AppColors.primaryColor.inverted,
                      fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  BorderRadius _getItemBorderRadius(int index, int total, double radius) {
    if (total == 1) {
      return BorderRadius.circular(radius);
    } else if (index == 0) {
      return BorderRadius.only(
        topLeft: Radius.circular(radius),
        topRight: Radius.circular(radius),
      );
    } else if (index == total - 1) {
      return BorderRadius.only(
        bottomLeft: Radius.circular(radius),
        bottomRight: Radius.circular(radius),
      );
    } else {
      return BorderRadius.zero;
    }
  }
}