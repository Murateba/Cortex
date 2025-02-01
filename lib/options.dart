import 'package:cortex/messages.dart';
import 'package:cortex/notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'chat.dart';
import 'report.dart';

/// Mesaj opsiyonlarını temsil eden enum.
enum MessageOption {
  copy,
  report,
  regenerate, // <--- YENİ EKLEDİK
  select,
}

class AnimatedMessageOptionsPanel extends StatefulWidget {
  final String messageText;
  final bool isDarkTheme;
  final List<MessageOption> options;
  final bool isReported;
  final VoidCallback? onReport;
  final VoidCallback onDismiss;
  final Offset position; // Panelin konumunu belirten Offset

  // Regenerate tıklanınca çalışacak callback:
  final VoidCallback? onRegenerate; // <--- YENİ

  const AnimatedMessageOptionsPanel({
    Key? key,
    required this.messageText,
    required this.isDarkTheme,
    required this.options,
    this.isReported = false,
    this.onReport,
    required this.onDismiss,
    required this.position,
    this.onRegenerate, // <--- YENİ
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
                    color:
                    widget.isDarkTheme ? const Color(0xFF202020) : Colors.white,
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
              color: widget.isDarkTheme ? Colors.white : Colors.black,
              width: 24,
              height: 24,
            ),
            const SizedBox(width: 10),
            Text(
              localizations.copy,
              style: TextStyle(
                color: widget.isDarkTheme ? Colors.white : Colors.black,
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
                color: widget.isDarkTheme ? Colors.white : Colors.black,
                width: 28,
                height: 28,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              localizations.report,
              style: TextStyle(
                color: widget.isDarkTheme ? Colors.white : Colors.black,
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
              color: widget.isDarkTheme ? Colors.white : Colors.black,
              width: 24,
              height: 24,
            ),
            const SizedBox(width: 10),
            Text(
              localizations.regenerate,
              style: TextStyle(
                color: widget.isDarkTheme ? Colors.white : Colors.black,
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
        // "Select Text" ekranını açıyoruz
        _navigateToScreen(
          context,
          SelectTextScreen(messageText: widget.messageText), // Mesaj metnini geçiriyoruz
          direction: Offset(1.0, 0.0), // Sağdan sola geçiş için Offset ayarı
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
              color: widget.isDarkTheme ? Colors.white : Colors.black,
              width: 24,
              height: 24,
            ),
            const SizedBox(width: 10),
            Text(
              localizations.selectText,
              style: TextStyle(
                color: widget.isDarkTheme ? Colors.white : Colors.black,
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

/// showMessageOptions fonksiyonu, animasyonlu paneli gösterir.
Future<void> showMessageOptions({
  required BuildContext context,
  required Offset tapPosition,
  required String messageText,
  required bool isDarkTheme,
  required List<MessageOption> options,
  bool isReported = false,
  VoidCallback? onReport,

  VoidCallback? onRegenerate,
}) async {
  final overlay = Overlay.of(context);
  final overlayBox = overlay.context.findRenderObject() as RenderBox?;
  if (overlayBox == null) return;

  // Global pozisyonu overlay'in yerel pozisyonuna dönüştür
  final localPosition = overlayBox.globalToLocal(tapPosition);

  OverlayEntry? entry;

  entry = OverlayEntry(
    builder: (context) {
      return AnimatedMessageOptionsPanel(
        messageText: messageText,
        isDarkTheme: isDarkTheme,
        options: options,
        isReported: isReported,
        onReport: onReport,
        onDismiss: () {
          entry?.remove();
        },
        position: localPosition,
        onRegenerate: onRegenerate, // <--- YENİ
      );
    },
  );

  overlay.insert(entry);
}