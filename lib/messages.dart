// messages.dart

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
    return FadeTransition(
      opacity: _fadeOutAnimation,
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
        child: AnimatedBuilder(
          animation: _chunkFadeInController,
          builder: (context, child) {
            final chunkOpacity = _chunkFadeInAnimation.value;
            return Material(
              color: Colors.transparent,
              child: Ink(
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(26.0),
                ),
                child: InkWell(
                  onTap: () => FocusScope.of(context).unfocus(),
                  onLongPress: () => _handleLongPress(context, Offset.zero),
                  borderRadius: BorderRadius.circular(26.0),
                  splashColor: widget.isDarkTheme
                      ? Colors.white.withOpacity(0.1)
                      : Colors.black.withOpacity(0.1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 8.0, horizontal: 16.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Solda modelin küçük avatar resmi
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
                              color: widget.isDarkTheme
                                  ? Colors.white
                                  : Colors.black,
                              size: 16,
                            ),
                          ),
                        const SizedBox(width: 16.0),
                        // Metin içeriği
                        Expanded(
                          child: _buildMessageContent(chunkOpacity),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
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
  final ValueNotifier<String> messageNotifier;

  const SelectTextScreen({
    Key? key,
    required this.messageNotifier,
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

  /// The parsed spans for the currently displayed text.
  late List<InlineSpan> _displayedSpans;

  /// Controls the fade-out animation (100 ms).
  late AnimationController _fadeOutController;
  late Animation<double> _fadeOutAnimation;

  /// Controls the fade-in animation (100 ms).
  late AnimationController _fadeInController;
  late Animation<double> _fadeInAnimation;

  /// Tracks if an animation is in progress to prevent overlapping animations.
  bool _isSwitchingText = false;

  /// ScrollController to manage scrolling.
  final ScrollController _scrollController = ScrollController();

  // ----------- For new incoming token chunk animation -----------
  late AnimationController _chunkFadeInController;
  late Animation<double> _chunkFadeInAnimation;
  String _animatingChunk = '';
  bool _isChunkAnimating = false;
  // ----------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _displayedText = widget.messageNotifier.value;
    final bool isDark = WidgetsBinding.instance.window.platformBrightness == Brightness.dark;
    _displayedSpans = parseText(_displayedText, isDark);

    _fadeOutController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _fadeOutAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(_fadeOutController);

    _fadeInController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _fadeInAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_fadeInController);

    _chunkFadeInController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _chunkFadeInAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_chunkFadeInController);

    // Güncellenmiş notifier listener:
    widget.messageNotifier.addListener(() {
      final newVal = widget.messageNotifier.value;
      // Ekranda gösterilen metin + animasyon halinde eklenen chunk (varsa)
      final currentCombined = _displayedText + (_isChunkAnimating ? _animatingChunk : '');
      if (newVal != currentCombined) {
        _handleIncomingTextChange(currentCombined, newVal);
      }
    });
  }

  @override
  void didUpdateWidget(covariant SelectTextScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messageNotifier.value != oldWidget.messageNotifier.value) {
      _handleIncomingTextChange(oldWidget.messageNotifier.value, widget.messageNotifier.value);
    }
  }

  /// Processes the incoming text changes incrementally.
  void _handleIncomingTextChange(String oldText, String newText) {
    final bool isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final localizations = AppLocalizations.of(context)!;

    // If we are exiting the "thinking" state:
    if (oldText == localizations.thinking && newText != localizations.thinking) {
      oldText = '';
    }

    // If text has shortened (e.g. during regeneration), reset:
    if (newText.length < oldText.length) {
      setState(() {
        _displayedText = newText;
        _displayedSpans = parseText(_displayedText, isDarkTheme);
        _animatingChunk = '';
        _isChunkAnimating = false;
        _chunkFadeInController.value = 1.0;
      });
      return;
    }

    // Get the new chunk:
    String chunk = newText.substring(oldText.length);
    if (_hideSpecial) {
      chunk = _stripMarkup(chunk);
    }
    if (chunk.isEmpty) return;

    if (_isChunkAnimating) {
      // If animation is ongoing, append to the chunk.
      setState(() {
        _animatingChunk += chunk;
      });
    } else {
      // Start new chunk animation:
      _animatingChunk = chunk;
      _isChunkAnimating = true;
      _chunkFadeInController.reset();
      _chunkFadeInController.forward().whenComplete(() {
        setState(() {
          _displayedText += _animatingChunk;
          _displayedSpans = parseText(_displayedText, isDarkTheme);
          _animatingChunk = '';
          _isChunkAnimating = false;
        });
      });
    }
  }

  /// Toggles the visibility of LaTeX and Markdown symbols with a 400ms animation.
  void _toggleSpecialVisibility() async {
    if (_isSwitchingText) return; // Prevent overlapping animations.

    // If not at top, scroll up in 100 ms.
    if (_scrollController.hasClients && _scrollController.offset > 0) {
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

    // Toggle state and update _displayedText.
    setState(() {
      _hideSpecial = !_hideSpecial;
      _displayedText = _hideSpecial
          ? _stripMarkup(widget.messageNotifier.value)
          : widget.messageNotifier.value;
      print('Toggled _hideSpecial to $_hideSpecial');
      print('Updated _displayedText: $_displayedText');
      _displayedSpans = parseText(_displayedText, Theme.of(context).brightness == Brightness.dark);
    });

    _fadeOutController.reset();

    // Start fade-in.
    await _fadeInController.forward();
    _fadeInController.reset();

    setState(() => _isSwitchingText = false);
    print('Completed fade-in animation');
  }

  /// Copies the currently displayed text to the clipboard.
  void _copyText(BuildContext context) {
    final textToCopy = _hideSpecial
        ? _stripMarkup(widget.messageNotifier.value)
        : widget.messageNotifier.value;
    Clipboard.setData(ClipboardData(text: textToCopy));

    Provider.of<NotificationService>(context, listen: false).showNotification(
      message: AppLocalizations.of(context)!.messageCopied,
      isSuccess: true,
      bottomOffset: 0.01,
    );
  }

  /// Strips LaTeX and Markdown symbols from [text].
  String _stripMarkup(String text) {
    text = text.replaceAllMapped(
        RegExp(r'\$\$(.*?)\$\$', dotAll: true), (m) => m.group(1) ?? '');
    text = text.replaceAllMapped(
        RegExp(r'\$(.*?)\$', dotAll: true), (m) => m.group(1) ?? '');
    text = text.replaceAllMapped(
        RegExp(r'\\frac\{([^{}]*)\}\{([^{}]*)\}'), (m) => '{${m.group(1)}} / {${m.group(2)}}');
    text = text.replaceAllMapped(
        RegExp(r'\\begin\{.*?\}([\s\S]*?)\\end\{.*?\}', dotAll: true), (m) => m.group(1) ?? '');
    text = text.replaceAllMapped(
        RegExp(r'\\\((.*?)\\\)', dotAll: true), (m) => m.group(1) ?? '');
    text = text.replaceAllMapped(
        RegExp(r'\\\[(.*?)\\\]', dotAll: true), (m) => m.group(1) ?? '');
    text = text.replaceAllMapped(
        RegExp(r'```([\s\S]*?)```', multiLine: true, dotAll: true), (m) => m.group(1) ?? '');
    text = text.replaceAllMapped(
        RegExp(r'^(#{1,6})\s+(.*)', multiLine: true), (m) => m.group(2) ?? '');
    text = text.replaceAllMapped(
        RegExp(r'(\*\*\*)(.*?)\1', dotAll: true), (m) => m.group(2) ?? '');
    text = text.replaceAllMapped(
        RegExp(r'(___)(.*?)\1', dotAll: true), (m) => m.group(2) ?? '');
    text = text.replaceAllMapped(
        RegExp(r'(\*\*)(.*?)\1', dotAll: true), (m) => m.group(2) ?? '');
    text = text.replaceAllMapped(
        RegExp(r'(__)(.*?)\1', dotAll: true), (m) => m.group(2) ?? '');
    text = text.replaceAllMapped(
        RegExp(r'(\*)(.*?)\1', dotAll: true), (m) => m.group(2) ?? '');
    text = text.replaceAllMapped(
        RegExp(r'(_)(.*?)\1', dotAll: true), (m) => m.group(2) ?? '');
    text = text.replaceAllMapped(
        RegExp(r'(~~)(.*?)\1', dotAll: true), (m) => m.group(2) ?? '');
    text = text.replaceAllMapped(
        RegExp(r'(`)(.*?)\1', dotAll: true), (m) => m.group(2) ?? '');
    text = text.replaceAllMapped(
        RegExp(r'^---$', multiLine: true), (m) => '');
    text = text.replaceAllMapped(
        RegExp(r'\\[a-zA-Z]+\{([^{}]*)\}', dotAll: true), (m) => '{${m.group(1)}}');
    text = text.replaceAllMapped(
        RegExp(r'\\[a-zA-Z]+'), (m) => '');
    text = text.replaceAllMapped(
        RegExp(r'\\([{}])'), (m) => m.group(1) ?? '');
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
    return text.trim();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final appBarColor = isDarkTheme ? const Color(0xFF090909) : const Color(0xFFFFFFFF);
    final scaffoldBackgroundColor = isDarkTheme ? const Color(0xFF090909) : const Color(0xFFFFFFFF);
    final appBarTextColor = isDarkTheme ? Colors.white : Colors.black;
    final iconColor = isDarkTheme ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: scaffoldBackgroundColor,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        title: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            AppLocalizations.of(context)!.selectText,
            style: TextStyle(
              color: appBarTextColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        backgroundColor: appBarColor,
        iconTheme: IconThemeData(color: iconColor),
        actions: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: child,
            ),
            child: IconButton(
              key: ValueKey<bool>(_hideSpecial),
              icon: Icon(
                _hideSpecial ? Icons.visibility_off : Icons.visibility,
                color: iconColor,
                size: 24,
              ),
              onPressed: _isSwitchingText ? null : _toggleSpecialVisibility,
              tooltip: _hideSpecial
                  ? AppLocalizations.of(context)!.showLatex
                  : AppLocalizations.of(context)!.hideLatex,
            ),
          ),
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
            // Fade-out animation during toggle:
            if (_isSwitchingText)
              FadeTransition(
                opacity: _fadeOutAnimation,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: SelectableText(
                    _hideSpecial
                        ? _stripMarkup(widget.messageNotifier.value)
                        : widget.messageNotifier.value,
                    style: TextStyle(
                      color: isDarkTheme ? Colors.white : Colors.black,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            // Fade-in animation after toggle:
            if (_isSwitchingText)
              FadeTransition(
                opacity: _fadeInAnimation,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: SelectableText(
                    _displayedText,
                    style: TextStyle(
                      color: isDarkTheme ? Colors.white : Colors.black,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            // Normal state: _displayedText combined with new incoming chunk(s)
            if (!_isSwitchingText)
              AnimatedBuilder(
                animation: _chunkFadeInController,
                builder: (context, child) {
                  final chunkOpacity = _chunkFadeInAnimation.value;
                  return SingleChildScrollView(
                    controller: _scrollController,
                    child: SelectableText.rich(
                      TextSpan(
                        children: [
                          ..._displayedSpans,
                          if (_animatingChunk.isNotEmpty)
                            WidgetSpan(
                              child: Opacity(
                                opacity: chunkOpacity,
                                child: RichText(
                                  text: TextSpan(
                                    children: parseText(_animatingChunk, isDarkTheme),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      style: TextStyle(
                        color: isDarkTheme ? Colors.white : Colors.black,
                        fontSize: 16,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}