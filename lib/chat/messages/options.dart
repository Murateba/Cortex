import 'package:cortex/chat/messages/messages.dart';
import 'package:cortex/chat/select.dart';
import 'package:cortex/main.dart';
import 'package:cortex/notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../models/data.dart';
import '../theme.dart';
import 'chat.dart';
import 'report.dart';

/// Mesaj opsiyonlarını temsil eden enum.
enum MessageOption {
  copy,
  report,
  regenerate, // <--- YENİ EKLEDİK
  select,
  stop,
  changeModel,
  edit,
}

class AnimatedMessageOptionsPanel extends StatefulWidget {
  final String messageText;
  final ValueNotifier<String> messageNotifier;
  final List<MessageOption> options;
  final bool isReported;
  final VoidCallback? onReport;
  final VoidCallback onDismiss;
  final Offset position;
  final String? modelIdAndExtension;
  final VoidCallback? onRegenerate;
  final ValueChanged<String>? onChangeModel;
  final VoidCallback? onStop;
  final VoidCallback? onEdit;

  const AnimatedMessageOptionsPanel({
    Key? key,
    required this.messageText,
    required this.messageNotifier,
    required this.options,
    this.isReported = false,
    this.onReport,
    required this.onDismiss,
    required this.position,
    this.onRegenerate,
    this.onStop,
    required this.modelIdAndExtension,
    this.onChangeModel,
    this.onEdit,
  }) : super(key: key);

  @override
  _AnimatedMessageOptionsPanelState createState() =>
      _AnimatedMessageOptionsPanelState();
}

class _AnimatedMessageOptionsPanelState extends State<AnimatedMessageOptionsPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;


  List<MessageOption> get visibleOptions {
    return widget.options.where((option) {
      if (option == MessageOption.report && widget.isReported) {
        return false;
      }
      if (option == MessageOption.changeModel) {
        final baseId = _currentBaseSeries; // modelin ana id'sini alıyoruz.
        final modelData = _getModelDataFromId(baseId);
        if (modelData.isEmpty ||
            !modelData.containsKey('extensions') ||
            (modelData['extensions'] as Map).isEmpty) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  double get panelHeight {
    return visibleOptions.length * _optionHeight;
  }

  late double _panelWidth;
  late double _optionHeight;
  late String _currentModelIdAndExtension;

  @override
  void initState() {
    super.initState();
    _currentModelIdAndExtension = widget.modelIdAndExtension ?? 'default';
    _controller = AnimationController(
      duration: const Duration(milliseconds: 50),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward(); // Panel açılış animasyonu
  }

  void _dismissPanel() {
    _controller.reverse().then((value) {
      widget.onDismiss();
    });
  }

  void _handleOutsideTap() {
    _dismissPanel();
  }

  @override
  Widget build(BuildContext context) {
    // Ekran boyutlarını ve klavye yüksekliğini alıp dinamik değerleri hesaplıyoruz:
    final screenSize = MediaQuery.of(context).size;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    _panelWidth = screenSize.width * 0.4;  // Panel genişliğini ekran genişliğinin %40'ı olarak belirledik.
    _optionHeight = screenSize.height * 0.06; // Seçenek yüksekliğini ekran yüksekliğinin %6'sı olarak belirledik.

    final double calculatedPanelHeight = visibleOptions.length * _optionHeight;

    double left = widget.position.dx;
    double top = widget.position.dy;

    // Ekran kenarlarından taşmayı önlemek için yerleştirme hesapları (16.0 kenar boşluğu bırakılarak)
    if (left + _panelWidth > screenSize.width - 16.0) {
      left = widget.position.dx - _panelWidth;
      if (left < 16.0) left = 16.0;
    }
    // Klavye yüksekliğini göz önüne alarak, panelin ekran dışına taşmaması için düzenleme:
    if (top + calculatedPanelHeight > screenSize.height - 16.0 - keyboardHeight) {
      top = widget.position.dy - calculatedPanelHeight;
      if (top < 16.0) top = 16.0;
    }

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Dış alanı yakalayan katman: panel dışına tıklanınca panel kapanır.
          Positioned.fill(
            child: GestureDetector(
              onTap: _handleOutsideTap,
              child: Container(color: Colors.transparent),
            ),
          ),
          // Panelin kendisi: bu kısım tıklamaları yutar, dolayısıyla içerisindeki InkWell ve butonlar düzgün çalışır.
          Positioned(
            left: left,
            top: top,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                width: _panelWidth,
                decoration: BoxDecoration(
                  color: AppColors.secondaryColor,
                  borderRadius: BorderRadius.circular(8.0),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8.0,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: visibleOptions.map((option) {
                    switch (option) {
                      case MessageOption.copy:
                        return _buildCopyOption(context);
                      case MessageOption.report:
                        return _buildReportOption(context);
                      case MessageOption.regenerate:
                        return _buildRegenerateOption(context);
                      case MessageOption.select:
                        return _buildSelectOption(context);
                      case MessageOption.stop:
                        return _buildStopOption(context);
                      case MessageOption.changeModel:
                        return _buildChangeModelOption(context);
                      case MessageOption.edit:
                        return _buildEditOption(context);
                    }
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String formatModelId(String rawText) {
    final parts = rawText.split('-').map((segment) {
      if (segment.isEmpty) return segment;
      return segment[0].toUpperCase() + segment.substring(1);
    }).toList();

    return parts.join(' ');
  }

  Color darkenWithBlack(Color color, double factor) {
    assert(factor >= 0 && factor <= 1);
    final r = (color.red * (1.0 - factor)).round();
    final g = (color.green * (1.0 - factor)).round();
    final b = (color.blue * (1.0 - factor)).round();
    return Color.fromARGB(color.alpha, r, g, b);
  }

  Map<String, dynamic> _getModelDataFromId(String modelId) {
    final List<Map<String, dynamic>> models = ModelData.models(context);
    return models.firstWhere((model) => model['id'] == modelId, orElse: () => {});
  }

  String get _currentBaseSeries {
    if (widget.modelIdAndExtension != null && widget.modelIdAndExtension!.contains('-')) {
      return widget.modelIdAndExtension!.split('-').first;
    }
    return widget.modelIdAndExtension ?? 'default';
  }

  Future<String?> _showModelExtensionsDialog(BuildContext context) async {
    final modelData = _getModelDataFromId(_currentBaseSeries);
    List<Map<String, dynamic>> extensionsList;
    final themeSettings =
    AppColors.getSystemUIOverlayStyleForTheme(AppColors.currentTheme);
    Color navBarColor = themeSettings['navigationBarColor'] as Color;

    Color darkenedNavBarColor = darkenWithBlack(navBarColor, 0.5);

    Brightness iconBrightness =
    ThemeData.estimateBrightnessForColor(darkenedNavBarColor) == Brightness.dark
        ? Brightness.light
        : Brightness.dark;

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        systemNavigationBarColor: darkenedNavBarColor,
        systemNavigationBarIconBrightness: iconBrightness,
      ),
    );

    if (modelData.isNotEmpty && modelData.containsKey('extensions')) {
      final List<dynamic> extList = modelData['extensions'];
      extensionsList = extList.map((e) {
        return {
          'code': e.toString(),
          'name': '${formatModelId(_currentBaseSeries)} ${formatModelId(e.toString())}',
          'enabled': true,
        };
      }).toList();
    } else {
      extensionsList = [
        {'code': 'default', 'name': 'Default', 'enabled': true},
      ];
    }

    String currentExtension = '';
    if (widget.modelIdAndExtension != null && widget.modelIdAndExtension!.contains('-')) {
      currentExtension = widget.modelIdAndExtension!.split('-').sublist(1).join('-');
    }

    String tempSelectedExtension = currentExtension.isNotEmpty
        ? currentExtension
        : extensionsList.first['code'];
    print("Temp selected extension: $tempSelectedExtension");

    bool? confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'ModelExtensionSelection',
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(ctx).size.width * 0.70,
              decoration: BoxDecoration(
                color: AppColors.secondaryColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: StatefulBuilder(
                  builder: (innerCtx, setState) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: MediaQuery.of(innerCtx).size.height * 0.02,
                        ),
                        SvgPicture.asset(
                          'assets/extension.svg',
                          width: MediaQuery.of(innerCtx).size.width * 0.08,
                          height: MediaQuery.of(innerCtx).size.width * 0.08,
                          color: AppColors.primaryColor.inverted,
                        ),
                        SizedBox(
                          height: MediaQuery.of(innerCtx).size.height * 0.008,
                        ),
                        Text(
                          AppLocalizations.of(innerCtx)!.changeModel,
                          style: TextStyle(
                            fontSize: MediaQuery.of(innerCtx).size.width * 0.04,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryColor.inverted,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        Divider(
                          thickness: 0.5,
                          color: AppColors.border,
                        ),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight:
                            MediaQuery.of(innerCtx).size.height * 0.3,
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            itemCount: extensionsList.length,
                            separatorBuilder: (context, index) => SizedBox(
                              height: MediaQuery.of(innerCtx).size.height * 0.01,
                            ),
                            itemBuilder: (context, index) {
                              final extensionItem = extensionsList[index];
                              bool isEnabled =
                              extensionItem['enabled'] as bool;
                              Widget leadingWidget = isEnabled
                                  ? Radio<String>(
                                value: extensionItem['code'] as String,
                                groupValue: tempSelectedExtension,
                                onChanged: (value) {
                                  setState(() {
                                    tempSelectedExtension = value!;
                                  });
                                },
                              )
                                  : SvgPicture.asset(
                                'assets/lock.svg',
                                width:
                                MediaQuery.of(innerCtx).size.width *
                                    0.05,
                                height:
                                MediaQuery.of(innerCtx).size.width *
                                    0.05,
                                color: AppColors.primaryColor.inverted,
                              );
                              return GestureDetector(
                                onTap: isEnabled
                                    ? () {
                                  setState(() {
                                    tempSelectedExtension =
                                    extensionItem['code'] as String;
                                  });
                                }
                                    : null,
                                child: Container(
                                  height: MediaQuery.of(innerCtx).size.height *
                                      0.065,
                                  padding: EdgeInsets.symmetric(
                                    horizontal:
                                    MediaQuery.of(innerCtx).size.width *
                                        0.02,
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width:
                                        MediaQuery.of(innerCtx).size.width *
                                            0.1,
                                        child: Center(child: leadingWidget),
                                      ),
                                      SizedBox(
                                        width:
                                        MediaQuery.of(innerCtx).size.width *
                                            0.02,
                                      ),
                                      Expanded(
                                        child: Text(
                                          extensionItem['name'] as String,
                                          style: TextStyle(
                                            fontSize: MediaQuery.of(innerCtx)
                                                .size
                                                .width *
                                                0.035,
                                            color: AppColors.primaryColor.inverted,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            splashColor:
                            AppColors.senaryColor.withOpacity(0.1),
                            highlightColor:
                            AppColors.senaryColor.withOpacity(0.1),
                            onTap: () => Navigator.of(innerCtx).pop(true),
                            child: Container(
                              alignment: Alignment.center,
                              padding: EdgeInsets.symmetric(
                                vertical:
                                MediaQuery.of(innerCtx).size.height *
                                    0.016,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                    color: AppColors.border,
                                    width: 0.5,
                                  ),
                                ),
                              ),
                              child: Text(
                                AppLocalizations.of(innerCtx)!.changeModel,
                                style: TextStyle(
                                  fontSize:
                                  MediaQuery.of(innerCtx).size.width *
                                      0.035,
                                  color: AppColors.senaryColor,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
    );

    if (confirmed == true) {
      print("Selected model extension: $tempSelectedExtension");
      return tempSelectedExtension;
    }

    return null;
  }

  Widget _buildChangeModelOption(BuildContext context) {
    final themeSettings = AppColors.getSystemUIOverlayStyleForTheme(AppColors.currentTheme);
    final localizations = AppLocalizations.of(context)!;
    String displayText = localizations.changeModel;
    if (_currentModelIdAndExtension.trim().isNotEmpty) {
      displayText = formatModelId(_currentModelIdAndExtension.trim());
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8.0),
        splashColor: AppColors.primaryColor.inverted.withOpacity(0.1),
        onTap: () async {
          _dismissPanel();
          String? selectedExtension = await _showModelExtensionsDialog(context);
          SystemChrome.setSystemUIOverlayStyle(
            SystemUiOverlayStyle(
              systemNavigationBarColor: themeSettings['navigationBarColor'] as Color,
              systemNavigationBarIconBrightness: themeSettings['navigationBarIconBrightness'] as Brightness,
            ),
          );
          if (selectedExtension != null) {
            widget.onChangeModel?.call(selectedExtension);
            setState(() {
              String mainId = _currentModelIdAndExtension.contains('-')
                  ? _currentModelIdAndExtension.split('-').first
                  : _currentModelIdAndExtension;
              _currentModelIdAndExtension = "$mainId-${selectedExtension.toLowerCase()}";
            });
          }
        },
        child: Container(
          constraints: BoxConstraints(minHeight: _optionHeight),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          alignment: Alignment.centerLeft,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center, // İkon ve metni dikeyde ortala
              children: [
                SvgPicture.asset(
                  'assets/extension.svg',
                  color: AppColors.primaryColor.inverted,
                  width: 24,
                  height: 24,
                ),
                SizedBox(width: MediaQuery.of(context).size.width * 0.025),
                Expanded(
                  child: Text(
                    localizations.changeModel + ' ' + displayText,
                    style: TextStyle(
                      color: AppColors.primaryColor.inverted,
                    ),
                    softWrap: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStopOption(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final String? stopLabel = AppLocalizations.of(context)?.stop;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8.0),
        splashColor: AppColors.primaryColor.inverted.withOpacity(0.1),
        onTap: () {
          _dismissPanel();
          widget.onStop?.call();
        },
        child: Container(
          height: _optionHeight,
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              SvgPicture.asset(
                'assets/stop.svg',
                color: AppColors.primaryColor.inverted,
                width: 24,
                height: 24,
              ),
              SizedBox(width: screenWidth * 0.025),
              Expanded(
                child: Text(
                  stopLabel ?? "Stop",
                  style: TextStyle(
                    color: AppColors.primaryColor.inverted,
                  ),
                  softWrap: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCopyOption(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final localizations = AppLocalizations.of(context)!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8.0),
        splashColor: AppColors.primaryColor.inverted.withOpacity(0.1),
        onTap: () {
          Clipboard.setData(ClipboardData(text: widget.messageText));
          _dismissPanel();
        },
        child: Container(
          height: _optionHeight,
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              SvgPicture.asset(
                'assets/copy.svg',
                color: AppColors.primaryColor.inverted,
                width: 24,
                height: 24,
              ),
              SizedBox(width: screenWidth * 0.025),
              Expanded(
                child: Text(
                  localizations.copy,
                  style: TextStyle(
                    color: AppColors.primaryColor.inverted,
                  ),
                  softWrap: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReportOption(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final localizations = AppLocalizations.of(context)!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8.0),
        splashColor: AppColors.primaryColor.inverted.withOpacity(0.1),
        onTap: () {
          _dismissPanel();
          showDialog(
            context: context,
            builder: (context) {
              return ReportDialog(
                aiMessage: widget.messageText,
                modelId: '',
              );
            },
          );
        },
        child: Container(
          height: _optionHeight,
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          alignment: Alignment.centerLeft,
          child: Transform.translate(
            offset: Offset(-screenWidth * 0.01, 0),
            child: Row(
              children: [
                SvgPicture.asset(
                  'assets/report.svg',
                  color: AppColors.primaryColor.inverted,
                  width: 28,
                  height: 28,
                ),
                SizedBox(width: screenWidth * 0.025),
                Expanded(
                  child: Text(
                    localizations.report,
                    style: TextStyle(
                      color: AppColors.primaryColor.inverted,
                    ),
                    softWrap: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// YENİ: Regenerate butonu
  Widget _buildRegenerateOption(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final localizations = AppLocalizations.of(context)!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8.0),
        splashColor: AppColors.primaryColor.inverted.withOpacity(0.1),
        onTap: () {
          _dismissPanel();
          widget.onRegenerate?.call();
        },
        child: Container(
          height: _optionHeight,
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              SvgPicture.asset(
                'assets/regenerate.svg',
                color: AppColors.primaryColor.inverted,
                width: 24,
                height: 24,
              ),
              SizedBox(width: screenWidth * 0.025),
              Expanded(
                child: Text(
                  localizations.regenerate,
                  style: TextStyle(
                    color: AppColors.primaryColor.inverted,
                  ),
                  softWrap: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectOption(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final localizations = AppLocalizations.of(context)!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8.0),
        splashColor: AppColors.primaryColor.inverted.withOpacity(0.1),
        onTap: () {
          _dismissPanel();
          _navigateToScreen(
            context,
            SelectTextScreen(messageNotifier: widget.messageNotifier),
            direction: Offset(1.0, 0.0), // Sağdan sola geçiş için
          );
        },
        child: Container(
          height: _optionHeight,
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              SvgPicture.asset(
                'assets/select.svg',
                color: AppColors.primaryColor.inverted,
                width: 24,
                height: 24,
              ),
              SizedBox(width: screenWidth * 0.025),
              Expanded(
                child: Text(
                  localizations.selectText,
                  style: TextStyle(
                    color: AppColors.primaryColor.inverted,
                  ),
                  softWrap: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditOption(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final localizations = AppLocalizations.of(context)!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8.0),
        splashColor: AppColors.primaryColor.inverted.withOpacity(0.1),
        onTap: () {
          _dismissPanel();
          widget.onEdit?.call(); // Edit geri çağrısını tetikleyin.
        },
        child: Container(
          height: _optionHeight,
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              SvgPicture.asset(
                'assets/edit.svg',
                color: AppColors.primaryColor.inverted,
                width: 24,
                height: 24,
              ),
              SizedBox(width: screenWidth * 0.025),
              Expanded(
                child: Text(
                  localizations.edit,
                  style: TextStyle(
                    color: AppColors.primaryColor.inverted,
                  ),
                  softWrap: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToScreen(BuildContext context, Widget screen, {required Offset direction}) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => screen,
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          final tween = Tween(begin: direction, end: Offset.zero)
              .chain(CurveTween(curve: Curves.ease));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 150),
        reverseTransitionDuration: const Duration(milliseconds: 150),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

Future<void> showMessageOptions({
  required BuildContext context,
  required Offset tapPosition,
  required String messageText,
  ValueNotifier<String>? messageNotifier,
  required List<MessageOption> options,
  bool isReported = false,
  VoidCallback? onReport,
  VoidCallback? onRegenerate,
  VoidCallback? onStop,
  String? modelIdAndExtension,
  final ValueChanged<String>? onChangeModel,
  VoidCallback? onEdit,
}) async {
  final notifier = messageNotifier ?? ValueNotifier<String>(messageText);
  final overlay = Overlay.of(context);
  final overlayBox = overlay.context.findRenderObject() as RenderBox?;
  if (overlayBox == null) return;
  final localPosition = overlayBox.globalToLocal(tapPosition);

  OverlayEntry? entry;

  entry = OverlayEntry(
    builder: (context) {
      return AnimatedMessageOptionsPanel(
        messageText: messageText,
        messageNotifier: notifier,
        options: options,
        isReported: isReported,
        onReport: onReport,
        onDismiss: () {
          entry?.remove();
        },
        position: localPosition,
        onRegenerate: onRegenerate,
        onStop: onStop,
        modelIdAndExtension: modelIdAndExtension,
        onChangeModel: onChangeModel,
        onEdit: onEdit, // Geri çağrıyı ilet
      );
    },
  );

  overlay.insert(entry);
}
