import 'package:cortex/chat/parser.dart';
import 'package:cortex/main.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';

import '../notifications.dart';
import '../theme.dart';

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
    _displayedSpans = parseText(_displayedText);

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    setState(() {
      _displayedSpans = parseText(_displayedText);
    });
  }

  /// Processes the incoming text changes incrementally.
  void _handleIncomingTextChange(String oldText, String newText) {
    final localizations = AppLocalizations.of(context)!;

    // If we are exiting the "thinking" state:
    if (oldText == localizations.thinking && newText != localizations.thinking) {
      oldText = '';
    }

    // If text has shortened (e.g. during regeneration), reset:
    if (newText.length < oldText.length) {
      setState(() {
        _displayedText = newText;
        _displayedSpans = parseText(_displayedText);
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
          _displayedSpans = parseText(_displayedText);
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
      _displayedSpans = parseText(_displayedText);
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
    final appBarColor = AppColors.background;
    final scaffoldBackgroundColor = AppColors.background;
    final appBarTextColor = AppColors.primaryColor.inverted;
    final iconColor = AppColors.primaryColor.inverted;

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
                      color: AppColors.primaryColor.inverted,
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
                      color: AppColors.primaryColor.inverted,
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
                                    children: parseText(_animatingChunk),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      style: TextStyle(
                        color: AppColors.primaryColor.inverted,
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