// messages.dart

import 'package:cortex/main.dart';
import 'package:cortex/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'chat.dart';
import 'parser.dart';
import 'options.dart';

class Message {
  String text;
  final bool isUserMessage;
  bool shouldFadeOut;
  bool shouldFadeIn;
  bool isReported;
  bool isError;
  String? photoPath;
  bool isPhotoUploading;
  List<InlineSpan>? parsedSpans;
  final ValueNotifier<String> notifier;
  bool includeInContext;
  String? model;

  Message({
    required this.text,
    required this.isUserMessage,
    this.shouldFadeOut = false,
    this.shouldFadeIn = false,
    this.isReported = false,
    this.isError = false,
    this.isPhotoUploading = false,
    this.photoPath,
    this.parsedSpans,
    this.includeInContext = true,
    this.model,
  }) : notifier = ValueNotifier(text);
}

// --------------------------------------------------
// Kullanıcı mesaj kutusu (UserMessageTile)
// --------------------------------------------------
class UserMessageTile extends StatefulWidget {
  final String text;
  final bool shouldFadeOut;
  final bool shouldFadeIn;
  final VoidCallback? onFadeOutComplete;
  final VoidCallback? onEdit;

  const UserMessageTile({
    Key? key,
    required this.text,
    required this.shouldFadeOut,
    required this.shouldFadeIn,
    this.onFadeOutComplete,
    this.onEdit,
  }) : super(key: key);

  @override
  _UserMessageTileState createState() => _UserMessageTileState();
}

class _UserMessageTileState extends State<UserMessageTile>
    with TickerProviderStateMixin {
  late AnimationController _fadeOutController;
  late Animation<double> _fadeOutAnimation;
  late AnimationController _fadeInController;
  late Animation<double> _fadeInAnimation;
  bool _isFadingOut = false;
  bool _isFadingIn = false;

  @override
  void initState() {
    super.initState();

    // Fade-out animasyon kontrolcüsü
    _fadeOutController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fadeOutAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(_fadeOutController);
    _fadeOutController.value = 0.0;
    _fadeOutController.forward();

    _fadeInController = AnimationController(
      duration: const Duration(milliseconds: 75),
      vsync: this,
    );
    _fadeInAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(_fadeInController);
    _isFadingIn = true;
    _fadeInController.forward().whenComplete(() {
      if (mounted) {
        setState(() {
          _isFadingIn = false;
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fadeInController.forward();
    });
  }

  @override
  void didUpdateWidget(UserMessageTile oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Fade-out tetiklendiğinde
    if (widget.shouldFadeOut && !_isFadingOut) {
      _isFadingOut = true;
      _fadeOutController.reverse(from: _fadeOutController.value);
    }

    // shouldFadeIn değiştiğinde (örneğin, düzenleme sonrası) fade-in’i yeniden tetikle
    if (widget.shouldFadeIn && !oldWidget.shouldFadeIn && !_isFadingIn) {
      _isFadingIn = true;
      _fadeInController.reset();
      _fadeInController.forward().whenComplete(() {
        if (mounted) {
          setState(() {
            _isFadingIn = false;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _fadeOutController.dispose();
    _fadeInController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: widget.shouldFadeOut
          ? _fadeOutAnimation
          : (widget.shouldFadeIn && _isFadingIn
          ? _fadeInAnimation
          : AlwaysStoppedAnimation(1.0)),
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
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Material(
                color: Colors.transparent,
                child: Ink(
                  decoration: BoxDecoration(
                    color: AppColors.secondaryColor,
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
                          color: AppColors.primaryColor.inverted,
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

  void _handleLongPress(BuildContext context, Offset tapPosition) {
    showMessageOptions(
      context: context,
      tapPosition: tapPosition,
      messageText: widget.text,
      options: [MessageOption.copy, MessageOption.edit, MessageOption.select],
      onEdit: () => widget.onEdit?.call(),
    );
  }
}

// --------------------------------------------------
// Yapay zekâ mesaj kutusu (AIMessageTile)
// --------------------------------------------------
class AIMessageTile extends StatefulWidget {
  final String text;
  final String imagePath;
  final bool shouldFadeOut;
  final bool shouldFadeIn;
  final bool isError;
  final VoidCallback? onFadeOutComplete;
  final String modelId;
  final bool isReported;
  final VoidCallback? onReport;
  final VoidCallback? onRegenerate;
  final List<InlineSpan>? parsedSpans;
  final VoidCallback? onStop;
  final ValueChanged<String>? onChangeModel;

  const AIMessageTile({
    Key? key,
    required this.text,
    required this.imagePath,
    required this.shouldFadeOut,
    required this.shouldFadeIn,
    required this.modelId,
    this.isError = false,
    this.onFadeOutComplete,
    required this.isReported,
    this.onReport,
    this.onRegenerate,
    this.parsedSpans,
    this.onChangeModel,
    this.onStop,
  }) : super(key: key);

  @override
  _AIMessageTileState createState() => _AIMessageTileState();
}

class _AIMessageTileState extends State<AIMessageTile>
    with TickerProviderStateMixin {
  late AnimationController _fadeOutController;
  late Animation<double> _fadeOutAnimation;
  late AnimationController _fadeInController;
  late Animation<double> _fadeInAnimation;
  bool _isFadingOut = false;
  bool _isFadingIn = false;
  late String _currentModelId;
  // Gelen metnin parça parça animasyonu için:
  late AnimationController _chunkFadeInController;
  late Animation<double> _chunkFadeInAnimation;

  String _displayedText = '';
  List<InlineSpan> _displayedSpans = [];
  String _animatingChunk = '';
  List<InlineSpan> _animatingSpans = [];
  bool _isChunkAnimating = false;

  // Error durumunda slide animasyonu:
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _currentModelId = widget.modelId;
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutQuad),
    );
    _fadeOutController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fadeOutAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(_fadeOutController);
    _fadeOutController.value = 0.0;
    _fadeOutController.forward();

    _fadeOutController.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && _isFadingOut) {
        widget.onFadeOutComplete?.call();
      }
    });

    _fadeInController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fadeInAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(_fadeInController);

    _chunkFadeInController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _chunkFadeInAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(_chunkFadeInController);

    // Başlangıç:
    _displayedText = widget.text;
    _displayedSpans =
        widget.parsedSpans ?? parseText(_displayedText);

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
    if (oldWidget.modelId != widget.modelId) {
      _currentModelId = widget.modelId; // Model değiştiğinde güncelle
    }
    if (oldWidget.text != widget.text) {
      if (widget.text == localizations.thinking) {
        // Yeni metin "düşünüyor" ise, fade-in animasyonu tetikleniyor:
        _isFadingOut = false;
        _fadeOutController.value = 0.0;
        _fadeOutController.forward();
        setState(() {
          _displayedText = widget.text;
          _displayedSpans = parseText(widget.text);
        });
      } else {
        if (_displayedText == localizations.thinking && widget.text != localizations.thinking) {
          setState(() {
            _displayedText = '';
            _displayedSpans.clear();
          });
        }
        _handleIncomingTextChange(oldWidget.text, widget.text);
      }
    }

    // Eğer shouldFadeOut true olup, "düşünüyor" metni dışındaki bir durumda fade-out tetikleniyor.
    if (widget.shouldFadeOut && !_isFadingOut && widget.text != localizations.thinking) {
      _triggerFadeOut();
    }
    if (widget.shouldFadeIn && !_isFadingIn) {
      _isFadingIn = true;
      _fadeInController.reset();
      _fadeInController.forward().whenComplete(() {
        setState(() {
          _isFadingIn = false;
        });
      });
    }
  }

  void _handleIncomingTextChange(String oldText, String newText) {
    final localizations = AppLocalizations.of(context)!;
    if (_isFadingOut) return;

    if (oldText == localizations.thinking && newText != localizations.thinking) {
      oldText = '';
    }

    if (newText.length < oldText.length) {
      setState(() {
        _displayedText = newText;
        _displayedSpans = parseText(_displayedText);
        _animatingChunk = '';
        _animatingSpans.clear();
        _chunkFadeInController.value = 1.0;
        _isChunkAnimating = false;
      });
      return;
    }

    final chunk = newText.substring(oldText.length);
    if (chunk.isEmpty) return;

    if (_isChunkAnimating) {
      setState(() {
        _animatingChunk += chunk;
        _animatingSpans = parseText(_animatingChunk);
      });
    } else {
      _animatingChunk = chunk;
      _animatingSpans = parseText(_animatingChunk);
      _isChunkAnimating = true;
      _chunkFadeInController.reset();
      _chunkFadeInController.forward().whenComplete(() {
        setState(() {
          _displayedText += _animatingChunk;
          _displayedSpans = parseText(_displayedText);
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
    _fadeInController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  void _handleLongPress(BuildContext context, Offset tapPosition) {
    final localizations = AppLocalizations.of(context)!;
    List<MessageOption> options = [
      MessageOption.copy,
      MessageOption.report,
      MessageOption.regenerate,
      MessageOption.select,
      MessageOption.changeModel,
    ];
    if (widget.onStop != null && widget.text == localizations.thinking) {
      options.add(MessageOption.stop);
    }
    showMessageOptions(
      context: context,
      tapPosition: tapPosition,
      messageText: widget.text,
      options: options,
      isReported: widget.isReported,
      onReport: widget.onReport,
      onRegenerate: widget.onRegenerate,
      onStop: widget.onStop,
      onChangeModel: widget.onChangeModel,
      modelIdAndExtension: _currentModelId,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Hata durumu kontrolü ayrı bir branşta ele alındığı için,
    // normal mesaj için aşağıdaki FadeTransition kullanılıyor.
    return FadeTransition(
      // Eğer shouldFadeOut aktifse _fadeOutAnimation,
      // aksi halde, shouldFadeIn true ise _fadeInAnimation, yoksa opaklık sabit (1.0)
      opacity: widget.shouldFadeOut
          ? _fadeOutAnimation
          : (widget.shouldFadeIn ? _fadeInAnimation : AlwaysStoppedAnimation(1.0)),
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
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6.0),
              child: Material(
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
                    splashColor: AppColors.primaryColor.inverted.withOpacity(0.1),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6.0, 8.0, 6.0, 0.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                                color: AppColors.tertiaryColor,
                                borderRadius: BorderRadius.circular(15.0),
                              ),
                              child: Icon(
                                Icons.person,
                                color: AppColors.primaryColor,
                                size: 16,
                              ),
                            ),
                          const SizedBox(width: 16.0),
                          Expanded(
                            child: _buildMessageContent(chunkOpacity),
                          ),
                        ],
                      ),
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

  List<InlineSpan> _overrideTextColor(
      List<InlineSpan> originalSpans,
      Color forcedColor,
      ) {
    return originalSpans.map((span) {
      if (span is TextSpan) {
        final newChildren = span.children != null
            ? _overrideTextColor(span.children!, forcedColor)
            : null;

        return TextSpan(
          text: span.text,
          style: (span.style ?? const TextStyle()).copyWith(color: forcedColor),
          children: newChildren,
          recognizer: span.recognizer,
        );
      } else {
        return span;
      }
    }).toList();
  }

  Widget _buildMessageContent(double chunkOpacity) {
    final localizations = AppLocalizations.of(context)!;

    if (_displayedText == localizations.thinking && !_isChunkAnimating) {
      return Shimmer.fromColors(
        baseColor: AppColors.primaryColor.inverted,
        highlightColor: AppColors.quaternaryColor,
        child: Text(
          localizations.thinking,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryColor.inverted,
          ),
        ),
      );
    }

    if (_isFadingOut) {
      final forcedSpans = _overrideTextColor(
        parseText(widget.text),
        AppColors.primaryColor.inverted,
      );
      return RichText(
        text: TextSpan(
          style: TextStyle(
            color: AppColors.primaryColor.inverted,
            fontSize: 16,
          ),
          children: forcedSpans,
        ),
      );
    }

    final forcedDisplayed = _overrideTextColor(_displayedSpans, AppColors.primaryColor.inverted);
    final forcedAnimating = _overrideTextColor(_animatingSpans, AppColors.primaryColor.inverted);

    final List<InlineSpan> finalSpans = [];
    finalSpans.addAll(forcedDisplayed);

    if (_animatingChunk.isNotEmpty) {
      for (var span in forcedAnimating) {
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

    return RichText(
      text: TextSpan(
        style: TextStyle(
          color: AppColors.primaryColor.inverted,
          fontSize: 16,
        ),
        children: finalSpans,
      ),
    );
  }
}