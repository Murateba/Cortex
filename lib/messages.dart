// lib/messages.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'chat.dart';
import 'notifications.dart';
import 'parser.dart';
import 'options.dart'; // Import to use MessageOption enum

// --------------------------------------------------
// Kullanıcı mesaj kutusu (UserMessageTile)
// --------------------------------------------------
class UserMessageTile extends StatefulWidget {
  final String text;
  final bool isDarkTheme;
  final bool shouldFadeOut;
  final VoidCallback? onFadeOutComplete;

  const UserMessageTile({
    Key? key,
    required this.text,
    required this.isDarkTheme,
    required this.shouldFadeOut,
    this.onFadeOutComplete,
  }) : super(key: key);

  @override
  _UserMessageTileState createState() => _UserMessageTileState();
}

class _UserMessageTileState extends State<UserMessageTile>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _isFadingOut = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 75),
      vsync: this,
    );
    _fadeAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(_fadeController);

    _fadeController.forward();
    _fadeController.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && _isFadingOut) {
        widget.onFadeOutComplete?.call();
      }
    });
  }

  @override
  void didUpdateWidget(UserMessageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shouldFadeOut && !_isFadingOut) {
      _isFadingOut = true;
      _fadeController.reverse(from: _fadeController.value);
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _handleLongPress(BuildContext context, Offset tapPosition) {
    showMessageOptions(
      context: context,
      tapPosition: tapPosition,
      messageText: widget.text,
      isDarkTheme: widget.isDarkTheme,
      options: [MessageOption.copy, MessageOption.select],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: RawGestureDetector(
        gestures: {
          ShortLongPressGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<ShortLongPressGestureRecognizer>(
                () => ShortLongPressGestureRecognizer(
              debugOwner: this,
              shortPressDuration: const Duration(milliseconds: 330),
            ),
                (instance) {
              instance.onLongPressStart = (details) {
                _handleLongPress(context, details.globalPosition);
              };
            },
          ),
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0), // Ekranın kenarından boşluk bırak
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end, // Mesajları sağa hizala
            children: [
              Material(
                color: Colors.transparent,
                child: Ink(
                  decoration: BoxDecoration(
                    color: widget.isDarkTheme
                        ? const Color(0xFF141414)
                        : Colors.grey[200],
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => FocusScope.of(context).unfocus(),
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.7,
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        widget.text,
                        style: TextStyle(
                          color: widget.isDarkTheme ? Colors.white : Colors.black,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------
// Yapay zekâ mesaj kutusu (AIMessageTile)
// --------------------------------------------------
class AIMessageTile extends StatefulWidget {
  final String text;
  final String imagePath;
  final bool isDarkTheme;
  final bool shouldFadeOut;
  final VoidCallback? onFadeOutComplete;
  final String modelId;
  final bool isReported;
  final VoidCallback? onReport;
  final VoidCallback? onRegenerate;
  final List<InlineSpan>? parsedSpans;

  const AIMessageTile({
    Key? key,
    required this.text,
    required this.imagePath,
    required this.isDarkTheme,
    required this.shouldFadeOut,
    required this.modelId,
    this.onFadeOutComplete,
    required this.isReported,
    this.onReport,
    this.onRegenerate,
    this.parsedSpans,
  }) : super(key: key);

  @override
  _AIMessageTileState createState() => _AIMessageTileState();
}

class _AIMessageTileState extends State<AIMessageTile>
    with TickerProviderStateMixin {
  late AnimationController _fadeOutController;
  late Animation<double> _fadeOutAnimation;
  bool _isFadingOut = false;

  // Gelen metnin parça parça animasyonu için:
  late AnimationController _chunkFadeInController;
  late Animation<double> _chunkFadeInAnimation;

  String _displayedText = '';
  List<InlineSpan> _displayedSpans = [];
  String _animatingChunk = '';
  List<InlineSpan> _animatingSpans = [];
  bool _isChunkAnimating = false;

  @override
  void initState() {
    super.initState();
    _fadeOutController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fadeOutAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(_fadeOutController);
    _fadeOutController.forward();

    _fadeOutController.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && _isFadingOut) {
        widget.onFadeOutComplete?.call();
      }
    });

    _chunkFadeInController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _chunkFadeInAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(_chunkFadeInController);

    // Başlangıç:
    _displayedText = widget.text;
    _displayedSpans =
        widget.parsedSpans ?? parseText(_displayedText, widget.isDarkTheme);

    if (widget.shouldFadeOut) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerFadeOut();
      });
    }
  }

  @override
  void didUpdateWidget(covariant AIMessageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final localizations = AppLocalizations.of(context)!;

    // Fade out tetiklendiyse
    if (widget.shouldFadeOut && !_isFadingOut) {
      _triggerFadeOut();
    }

    // Metin değiştiyse
    if (oldWidget.text != widget.text) {
      // "Düşünüyor..." → chunk güncelleme
      if (_displayedText == localizations.thinking &&
          widget.text != localizations.thinking) {
        // Sıfırla
        setState(() {
          _displayedText = '';
          _displayedSpans.clear();
        });
      }
      _handleIncomingTextChange(oldWidget.text, widget.text);
    }
  }

  void _handleIncomingTextChange(String oldText, String newText) {
    final localizations = AppLocalizations.of(context)!;
    if (_isFadingOut) return;

    // "Düşünüyor..." durumundan çıktığımızda
    if (oldText == localizations.thinking && newText != localizations.thinking) {
      oldText = '';
    }

    // Kısalma durumu (örnek: Regenerate ile metin sıfırlanabilir vs.)
    if (newText.length < oldText.length) {
      setState(() {
        _displayedText = newText;
        _displayedSpans = parseText(_displayedText, widget.isDarkTheme);
        _animatingChunk = '';
        _animatingSpans.clear();
        _chunkFadeInController.value = 1.0;
        _isChunkAnimating = false;
      });
      return;
    }

    // Kalan chunk:
    final chunk = newText.substring(oldText.length);
    if (chunk.isEmpty) return;

    if (_isChunkAnimating) {
      // Hâlâ animasyon devam ediyorsa chunk üzerine ekleyelim
      setState(() {
        _animatingChunk += chunk;
        _animatingSpans = parseText(_animatingChunk, widget.isDarkTheme);
      });
    } else {
      // Yeni chunk animasyonu
      _animatingChunk = chunk;
      _animatingSpans = parseText(_animatingChunk, widget.isDarkTheme);
      _isChunkAnimating = true;
      _chunkFadeInController.reset();
      _chunkFadeInController.forward().whenComplete(() {
        setState(() {
          _displayedText += _animatingChunk;
          _displayedSpans = parseText(_displayedText, widget.isDarkTheme);
          _animatingChunk = '';
          _animatingSpans.clear();
          _isChunkAnimating = false;
        });
      });
    }
  }

  void _triggerFadeOut() {
    if (!_isFadingOut) {
      _isFadingOut = true;
      _fadeOutController.reverse(from: _fadeOutController.value);
    }
  }

  @override
  void dispose() {
    _fadeOutController.dispose();
    _chunkFadeInController.dispose();
    super.dispose();
  }

  void _handleLongPress(BuildContext context, Offset tapPosition) {
    // Mesaj opsiyonları menüsünü açıyoruz
    showMessageOptions(
      context: context,
      tapPosition: tapPosition,
      messageText: widget.text,
      isDarkTheme: widget.isDarkTheme,
      options: [
        MessageOption.copy,
        MessageOption.report,
        MessageOption.regenerate,
        MessageOption.select,
      ],
      isReported: widget.isReported,
      onReport: widget.onReport,
      onRegenerate: widget.onRegenerate,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: widget.shouldFadeOut ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 200),
      onEnd: () {
        if (widget.shouldFadeOut) {
          widget.onFadeOutComplete?.call();
        }
      },
      child: RawGestureDetector(
        gestures: {
          ShortLongPressGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<ShortLongPressGestureRecognizer>(
                () => ShortLongPressGestureRecognizer(
              debugOwner: this,
              shortPressDuration: const Duration(milliseconds: 330),
            ),
                (instance) {
              instance.onLongPressStart = (details) {
                _handleLongPress(context, details.globalPosition);
              };
            },
          ),
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left side: avatar image
              if (widget.imagePath.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(15.0),
                  child: Image.asset(
                    widget.imagePath,
                    width: 30,
                    height: 30,
                    fit: BoxFit.cover,
                  ),
                )
              else
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: widget.isDarkTheme
                        ? Colors.grey[700]
                        : Colors.grey[300],
                    borderRadius: BorderRadius.circular(15.0),
                  ),
                  child: Icon(
                    Icons.person,
                    color: widget.isDarkTheme ? Colors.white : Colors.black,
                    size: 16,
                  ),
                ),
              const SizedBox(width: 16.0),
              // Message text content
              Expanded(
                // Pass _chunkFadeInAnimation.value as the required parameter
                child: _buildMessageContent(_chunkFadeInAnimation.value),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageContent(double chunkOpacity) {
    final localizations = AppLocalizations.of(context)!;

    // "Düşünüyor..." shimmer durumu
    if (_displayedText == localizations.thinking && !_isChunkAnimating) {
      return Shimmer.fromColors(
        baseColor: widget.isDarkTheme ? Colors.white : Colors.black,
        highlightColor:
        widget.isDarkTheme ? Colors.grey[400]! : Colors.grey[300]!,
        child: Text(
          localizations.thinking,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: widget.isDarkTheme ? Colors.white : Colors.black,
          ),
        ),
      );
    }

    // Fade out aşamasındaysak ek animasyona gerek yok
    if (_isFadingOut) {
      return RichText(
        text: TextSpan(
          children: parseText(widget.text, widget.isDarkTheme),
        ),
      );
    }

    // Aksi halde chunk animasyonunu birleştirerek göster
    final List<InlineSpan> finalSpans = [];
    finalSpans.addAll(_displayedSpans);

    if (_animatingChunk.isNotEmpty) {
      for (var span in _animatingSpans) {
        finalSpans.add(
          WidgetSpan(
            child: Opacity(
              opacity: chunkOpacity,
              child: (span is TextSpan)
                  ? RichText(text: TextSpan(children: [span]))
                  : (span is WidgetSpan ? span.child : const SizedBox.shrink()),
            ),
          ),
        );
      }
    }

    return RichText(text: TextSpan(children: finalSpans));
  }
}

class SelectTextScreen extends StatefulWidget {
  final String messageText;

  const SelectTextScreen({
    Key? key,
    required this.messageText,
  }) : super(key: key);

  @override
  _SelectTextScreenState createState() => _SelectTextScreenState();
}

class _SelectTextScreenState extends State<SelectTextScreen>
    with TickerProviderStateMixin {
  /// Indicates whether LaTeX and Markdown symbols are hidden.
  bool _hideSpecial = false;

  /// The currently displayed text (original or stripped).
  late String _displayedText;

  /// Controls the fade-out animation (200 ms).
  late AnimationController _fadeOutController;
  late Animation<double> _fadeOutAnimation;

  /// Controls the fade-in animation (200 ms).
  late AnimationController _fadeInController;
  late Animation<double> _fadeInAnimation;

  /// Tracks if an animation is in progress to prevent overlapping animations.
  bool _isSwitchingText = false;

  /// ScrollController to manage scrolling.
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _displayedText = widget.messageText;

    // Initialize fade-out controller.
    _fadeOutController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _fadeOutAnimation =
        Tween<double>(begin: 1.0, end: 0.0).animate(_fadeOutController);

    // Initialize fade-in controller.
    _fadeInController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _fadeInAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(_fadeInController);
  }

  @override
  void dispose() {
    _fadeOutController.dispose();
    _fadeInController.dispose();
    _scrollController.dispose(); // Dispose the controller
    super.dispose();
  }

  /// Toggles the visibility of LaTeX and Markdown symbols with a 400ms animation.
  void _toggleSpecialVisibility() async {
    if (_isSwitchingText) return; // Prevent overlapping animations.

    // Check if the user has scrolled away from the top
    if (_scrollController.hasClients && _scrollController.offset > 0) {
      // Animate scrolling to the top over 100 milliseconds
      await _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }

    setState(() => _isSwitchingText = true);
    print('Starting fade-out animation');

    // Start fade-out.
    await _fadeOutController.forward();

    // Toggle the visibility state and update displayed text.
    setState(() {
      _hideSpecial = !_hideSpecial;
      _displayedText =
      _hideSpecial ? _stripMarkup(widget.messageText) : widget.messageText;
      print('Toggled _hideSpecial to $_hideSpecial');
      print('Updated _displayedText: $_displayedText');
    });

    _fadeOutController.reset(); // Reset for future toggles.

    // Start fade-in.
    await _fadeInController.forward();
    _fadeInController.reset();

    setState(() => _isSwitchingText = false);
    print('Completed fade-in animation');
  }

  /// Copies the currently displayed text (original or stripped) to the clipboard.
  void _copyText(BuildContext context) {
    // Decide which text to copy based on whether LaTeX/Markdown is hidden
    final textToCopy = _hideSpecial
        ? _stripMarkup(widget.messageText)
        : widget.messageText;

    // Copy it to the clipboard
    Clipboard.setData(ClipboardData(text: textToCopy));

    // Show a toast / notification
    Provider.of<NotificationService>(context, listen: false).showNotification(
      message: AppLocalizations.of(context)!.messageCopied,
      isSuccess: true,
      bottomOffset: 0.01,
    );
  }

  /// Strips LaTeX and Markdown symbols from the text.
  ///
  /// - Specifically handles \frac{a}{b} by converting it to {a} / {b}.
  /// - Removes other LaTeX commands but preserves their content.
  /// - Preserves the content inside LaTeX and Markdown symbols.
  /// - Preserves newline characters.
  String _stripMarkup(String text) {
    // 1. Remove block LaTeX: $$...$$
    text = text.replaceAllMapped(
      RegExp(r'\$\$(.*?)\$\$', dotAll: true),
          (m) => m.group(1) ?? '',
    );

    // 2. Remove inline LaTeX: $...$
    text = text.replaceAllMapped(
      RegExp(r'\$(.*?)\$', dotAll: true),
          (m) => m.group(1) ?? '',
    );

    // 3. Handle \frac{a}{b} specifically
    text = text.replaceAllMapped(
      RegExp(r'\\frac\{([^{}]*)\}\{([^{}]*)\}'),
          (m) => '{${m.group(1)}} / {${m.group(2)}}',
    );

    // 4. Remove other LaTeX environments: \begin{env}...\end{env}
    text = text.replaceAllMapped(
      RegExp(r'\\begin\{.*?\}([\s\S]*?)\\end\{.*?\}', dotAll: true),
          (m) => m.group(1) ?? '',
    );

    // 5. Remove \(...\) and \[...\]
    text = text.replaceAllMapped(
      RegExp(r'\\\((.*?)\\\)', dotAll: true),
          (m) => m.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'\\\[(.*?)\\\]', dotAll: true),
          (m) => m.group(1) ?? '',
    );

    // 6. Remove code blocks: ```...```
    text = text.replaceAllMapped(
      RegExp(r'```([\s\S]*?)```', multiLine: true, dotAll: true),
          (m) => m.group(1) ?? '',
    );

    // 7. Remove Markdown headings: # Heading
    text = text.replaceAllMapped(
      RegExp(r'^(#{1,6})\s+(.*)', multiLine: true),
          (m) => m.group(2) ?? '',
    );

    // 8. Remove bold+italic: ***bold*** or ___italic___
    text = text.replaceAllMapped(
      RegExp(r'(\*\*\*)(.*?)\1', dotAll: true),
          (m) => m.group(2) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'(___)(.*?)\1', dotAll: true),
          (m) => m.group(2) ?? '',
    );

    // 9. Remove bold: **bold** or __bold__
    text = text.replaceAllMapped(
      RegExp(r'(\*\*)(.*?)\1', dotAll: true),
          (m) => m.group(2) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'(__)(.*?)\1', dotAll: true),
          (m) => m.group(2) ?? '',
    );

    // 10. Remove italic: *italic* or _italic_
    text = text.replaceAllMapped(
      RegExp(r'(\*)(.*?)\1', dotAll: true),
          (m) => m.group(2) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'(_)(.*?)\1', dotAll: true),
          (m) => m.group(2) ?? '',
    );

    // 11. Remove strikethrough: ~~strikethrough~~
    text = text.replaceAllMapped(
      RegExp(r'(~~)(.*?)\1', dotAll: true),
          (m) => m.group(2) ?? '',
    );

    // 12. Remove inline code: `code`
    text = text.replaceAllMapped(
      RegExp(r'(`)(.*?)\1', dotAll: true),
          (m) => m.group(2) ?? '',
    );

    // 13. Remove horizontal rules: ---
    text = text.replaceAllMapped(
      RegExp(r'^---$', multiLine: true),
          (m) => '',
    );

    // 14. Remove other LaTeX commands but preserve their content
    // This should be done after handling specific commands like \frac
    text = text.replaceAllMapped(
      RegExp(r'\\[a-zA-Z]+\{([^{}]*)\}', dotAll: true),
          (m) => '{${m.group(1)}}',
    );

    // 15. Remove standalone LaTeX commands like \alpha, \beta, etc.
    text = text.replaceAllMapped(
      RegExp(r'\\[a-zA-Z]+'),
          (m) => '',
    );

    // 16. Remove escaped braces \{ and \} by replacing them with { and }
    text = text.replaceAllMapped(
      RegExp(r'\\([{}])'),
          (m) => m.group(1) ?? '',
    );

    // 17. Replace multiple spaces and tabs with a single space, preserve newlines
    // First, replace spaces and tabs
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
    text = text.trim();

    return text;
  }

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final appBarColor =
    isDarkTheme ? const Color(0xFF090909) : const Color(0xFFFFFFFF);
    final scaffoldBackgroundColor =
    isDarkTheme ? const Color(0xFF090909) : const Color(0xFFFFFFFF);
    final appBarTextColor = isDarkTheme ? Colors.white : Colors.black;
    final iconColor = isDarkTheme ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: scaffoldBackgroundColor,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        title: Text(
          AppLocalizations.of(context)!.selectText,
          style: TextStyle(color: appBarTextColor),
        ),
        backgroundColor: appBarColor,
        iconTheme: IconThemeData(color: iconColor),
        actions: [
          // Visibility Toggle Button with AnimatedSwitcher
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: child,
              );
            },
            child: IconButton(
              key: ValueKey<bool>(_hideSpecial),
              icon: Icon(
                _hideSpecial ? Icons.visibility_off : Icons.visibility,
                color: iconColor,
                size: 24,
              ),
              onPressed:
              _isSwitchingText ? null : _toggleSpecialVisibility, // Disable button during animation
              tooltip: _hideSpecial
                  ? AppLocalizations.of(context)!.showLatex
                  : AppLocalizations.of(context)!.hideLatex,
            ),
          ),
          // Copy Button using SVG Asset
          IconButton(
            icon: SvgPicture.asset(
              'assets/copy.svg',
              color: iconColor,
              width: 24,
              height: 24,
            ),
            onPressed: () => _copyText(context),
            tooltip: AppLocalizations.of(context)!.copy,
          ),
        ],
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Stack(
          children: [
            // 1) Old text fading out
            if (_isSwitchingText)
              FadeTransition(
                opacity: _fadeOutAnimation,
                child: SingleChildScrollView(
                  controller: _scrollController, // Attach the controller
                  child: SelectableText(
                    _hideSpecial
                        ? _stripMarkup(widget.messageText)
                        : widget.messageText,
                    style: TextStyle(
                      color: isDarkTheme ? Colors.white : Colors.black,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),

            // 2) New text fading in
            if (_isSwitchingText)
              FadeTransition(
                opacity: _fadeInAnimation,
                child: SingleChildScrollView(
                  controller: _scrollController, // Attach the controller
                  child: SelectableText(
                    _displayedText,
                    style: TextStyle(
                      color: isDarkTheme ? Colors.white : Colors.black,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),

            // 3) Idle state: Show current text
            if (!_isSwitchingText)
              SingleChildScrollView(
                controller: _scrollController, // Attach the controller
                child: SelectableText(
                  _displayedText,
                  style: TextStyle(
                    color: isDarkTheme ? Colors.white : Colors.black,
                    fontSize: 16,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}