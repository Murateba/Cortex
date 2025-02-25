import 'package:cortex/chat/messages.dart';
import 'package:cortex/notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
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
}

class AnimatedMessageOptionsPanel extends StatefulWidget {
  final String messageText;
  final ValueNotifier<String> messageNotifier; // EKLENDİ
  final List<MessageOption> options;
  final bool isReported;
  final VoidCallback? onReport;
  final VoidCallback onDismiss;
  final Offset position; // Panelin konumunu belirten Offset

  // Regenerate tıklanınca çalışacak callback:
  final VoidCallback? onRegenerate; // <--- YENİ

  // <-- Yeni: onStop callback for stopping answer generation
  final VoidCallback? onStop;

  const AnimatedMessageOptionsPanel({
    Key? key,
    required this.messageText,
    required this.messageNotifier, // EKLENDİ
    required this.options,
    this.isReported = false,
    this.onReport,
    required this.onDismiss,
    required this.position,
    this.onRegenerate, // <--- YENİ
    this.onStop,       // <-- Yeni: added parameter
  }) : super(key: key);

  @override
  _AnimatedMessageOptionsPanelState createState() =>
      _AnimatedMessageOptionsPanelState();
}

class _AnimatedMessageOptionsPanelState
    extends State<AnimatedMessageOptionsPanel> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  final double panelWidth = 150.0;
  final double optionHeight = 48.0;

  // Yalnızca gerçekten görüntülenecek butonları filtreleyelim (report ise raporlanmış vs.)
  List<MessageOption> get visibleOptions {
    // Eğer mesaj raporlanmışsa, MessageOption.report'ı listeden çıkarıyoruz.
    return widget.options.where((option) {
      if (option == MessageOption.report && widget.isReported) {
        return false;
      }
      return true;
    }).toList();
  }

  double get panelHeight => visibleOptions.length * optionHeight;

  @override
  void initState() {
    super.initState();
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
    final screenSize = MediaQuery.of(context).size;

    double left = widget.position.dx;
    double top = widget.position.dy;

    // Ekran kenarlarından taşmayı önlemek için yerleştirme hesapları
    if (left + panelWidth > screenSize.width - 16.0) {
      left = widget.position.dx - panelWidth;
      if (left < 16.0) left = 16.0;
    }
    if (top + panelHeight > screenSize.height - 16.0) {
      top = widget.position.dy - panelHeight;
      if (top < 16.0) top = 16.0;
    }

    return GestureDetector(
      onTap: _handleOutsideTap,
      behavior: HitTestBehavior.translucent,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: panelWidth,
                  height: panelHeight,
                  decoration: BoxDecoration(
                    color: AppColors.primaryColor,
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
                          return _buildRegenerateOption(context); // <--- YENİ
                        case MessageOption.select:
                          return _buildSelectOption(context);
                        case MessageOption.stop:
                          return _buildStopOption(context);
                      }
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStopOption(BuildContext context) {
    final String? stopLabel = AppLocalizations.of(context)?.stop;
    return InkWell(
      onTap: () {
        _dismissPanel();
        widget.onStop?.call();
      },
      child: Container(
        height: optionHeight,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            SvgPicture.asset(
              'assets/stop.svg',
              color: AppColors.opposedPrimaryColor,
              width: 24,
              height: 24,
            ),
            const SizedBox(width: 10),
            Text(
              stopLabel ?? "Stop",
              style: TextStyle(
                color: AppColors.opposedPrimaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCopyOption(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: widget.messageText));
        _dismissPanel();
      },
      child: Container(
        height: optionHeight,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            SvgPicture.asset(
              'assets/copy.svg',
              color: AppColors.opposedPrimaryColor,
              width: 24,
              height: 24,
            ),
            const SizedBox(width: 10),
            Text(
              localizations.copy,
              style: TextStyle(
                color: AppColors.opposedPrimaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportOption(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return InkWell(
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
        height: optionHeight,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Transform.translate(
              offset: const Offset(-2, 0),
              child: SvgPicture.asset(
                'assets/report.svg',
                color: AppColors.opposedPrimaryColor,
                width: 28,
                height: 28,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              localizations.report,
              style: TextStyle(
                color: AppColors.opposedPrimaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// YENİ: Regenerate butonu
  Widget _buildRegenerateOption(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return InkWell(
      onTap: () {
        _dismissPanel();
        // Burada ChatScreen'e kadar giden callback'i çağırıyoruz:
        widget.onRegenerate?.call();
      },
      child: Container(
        height: optionHeight,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            SvgPicture.asset(
              'assets/regenerate.svg',
              color: AppColors.opposedPrimaryColor,
              width: 24,
              height: 24,
            ),
            const SizedBox(width: 10),
            Text(
              localizations.regenerate,
              style: TextStyle(
                color: AppColors.opposedPrimaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectOption(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return InkWell(
      onTap: () {
        _dismissPanel();
        _navigateToScreen(
          context,
          SelectTextScreen(messageNotifier: widget.messageNotifier),
          direction: Offset(1.0, 0.0), // Sağdan sola geçiş için
        );
      },
      child: Container(
        height: optionHeight,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            SvgPicture.asset(
              'assets/select.svg',
              color: AppColors.opposedPrimaryColor,
              width: 24,
              height: 24,
            ),
            const SizedBox(width: 10),
            Text(
              localizations.selectText,
              style: TextStyle(
                color: AppColors.opposedPrimaryColor,
              ),
            ),
          ],
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
  ValueNotifier<String>? messageNotifier, // Opsiyonel: varsa gerçek notifier, yoksa oluşturulacak
  required List<MessageOption> options,
  bool isReported = false,
  VoidCallback? onReport,
  VoidCallback? onRegenerate,
  VoidCallback? onStop, // <-- Add this parameter
}) async {
  // If no notifier is provided, create one wrapping the messageText.
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
        onStop: onStop, // <-- Forward the onStop callback
      );
    },
  );

  overlay.insert(entry);
}
