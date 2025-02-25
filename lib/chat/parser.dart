// parser.dart

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import '../theme.dart';
import 'codeblocks.dart'; // CodeBlockWidget'ınızı içeren dosya

/// SafeMathTex widget'ı, LaTeX ifadelerini işlerken oluşan hataları yakalar
/// ve hata durumunda ham LaTeX metnini gösterir.
class SafeMathTex extends StatelessWidget {
  final String latex;
  final TextStyle textStyle;

  const SafeMathTex({
    required this.latex,
    required this.textStyle,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Math.tex(
        latex,
        textStyle: textStyle,
        onErrorFallback: (FlutterMathException error) {
          // Hata durumunda ham LaTeX metnini göster
          return Text(
            latex,
            style: textStyle,
          );
        },
      ),
    );
  }
}

/// parseText fonksiyonu, verilen metni analiz eder ve InlineSpan listesi döndürür.
/// Bu fonksiyon, LaTeX, kod blokları ve çeşitli markdown stillerini işler.
/// Hatalı LaTeX ifadeleri, SafeMathTex widget'ı tarafından ham metin olarak gösterilir.
List<InlineSpan> parseText(String text) {
  try {
    final latexPattern =
        r'(\\\[.+?\\\]|\\\(.+?\\\)|\$\$.+?\$\$|\$.+?\$|\\begin\{.*?\}[\s\S]*?\\end\{.*?\})';
    final String codeBlockPattern = r'```([\s\S]*?)```'; // Üçlü backtick'ler ile içerik

    final markdownPattern =
        r'(\*\*\*.+?\*\*\*|___.+?___|\*\*.+?\*\*|__.+?__|\*.+?\*|_.+?_|~~.+?~~|^#{1,6} .+?$)';
    final String horizontalRulePattern = r'^---$';
    final combinedPattern =
        '($horizontalRulePattern|$latexPattern|$codeBlockPattern|$markdownPattern)';

    // '.' karakterinin yeni satırları da eşlemesine izin vermek için dotAll etkinleştirildi
    RegExp regex = RegExp(combinedPattern, multiLine: true, dotAll: true);
    Iterable<RegExpMatch> matches = regex.allMatches(text);

    int currentIndex = 0;
    List<InlineSpan> spans = [];

    for (var match in matches) {
      try {
        if (match.start > currentIndex) {
          // Eşleşmeden önceki normal metni ekle
          spans.add(TextSpan(
            text: text.substring(currentIndex, match.start),
            style: TextStyle(
              color: AppColors.primaryColor,
              fontSize: 16,
            ),
          ));
        }

        String matchText = match.group(0)!;
        InlineSpan span;

        // ---------------------------------------------------
        // 1) LaTeX
        // ---------------------------------------------------
        if (RegExp(latexPattern, multiLine: true, dotAll: true)
            .hasMatch(matchText)) {
          // LaTeX'i temizle
          String latex =
          matchText.replaceAllMapped(RegExp(r'\\begin\{.*?\}'), (_) => '');
          latex =
              latex.replaceAllMapped(RegExp(r'\\end\{.*?\}'), (_) => '');
          if ((latex.startsWith('\$\$') && latex.endsWith('\$\$')) ||
              (latex.startsWith('\\[') && latex.endsWith('\\]'))) {
            latex = latex.substring(2, latex.length - 2);
          } else if ((latex.startsWith('\$') && latex.endsWith('\$')) ||
              (latex.startsWith('\\(') && latex.endsWith('\\)'))) {
            latex = latex.substring(1, latex.length - 1);
          }

          span = WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: SafeMathTex(
              latex: latex,
              textStyle: TextStyle(
                color: AppColors.primaryColor,
                fontSize: 16, // İhtiyacınıza göre font boyutunu ayarlayın
              ),
            ),
          );
        }

        // ---------------------------------------------------
        // 2) Code blocks (üçlü backtick)
        // ---------------------------------------------------
        else if (matchText.startsWith('```') && matchText.endsWith('```')) {
          if (matchText.length >= 6) {
            String content =
            matchText.substring(3, matchText.length - 3).trim();
            span = WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: CodeBlockWidget(code: content),
              ),
            );
          } else {
            span = TextSpan(
              text: matchText,
              style: TextStyle(
                color: AppColors.primaryColor,
                fontSize: 16,
              ),
            );
          }
        }

        // ---------------------------------------------------
        // 3) Markdown başlıkları (# ...)
        // ---------------------------------------------------
        else if (matchText.startsWith('#')) {
          int level = matchText.indexOf(' ');
          if (level > 0 && level <= 6) {
            String content = matchText.substring(level + 1);
            span = TextSpan(
              text: content + '\n',
              style: TextStyle(
                color: AppColors.primaryColor,
                fontSize: 22 - level.toDouble(),
                fontWeight: FontWeight.bold,
              ),
            );
          } else {
            span = TextSpan(
              text: matchText,
              style: TextStyle(
                color: AppColors.primaryColor,
                fontSize: 16,
              ),
            );
          }
        }

        // ---------------------------------------------------
        // 4) Kalın + İtalik (*** veya ___)
        // ---------------------------------------------------
        else if ((matchText.startsWith('***') && matchText.endsWith('***')) ||
            (matchText.startsWith('___') && matchText.endsWith('___'))) {
          if (matchText.length >= 6) {
            String content =
            matchText.substring(3, matchText.length - 3);
            span = TextSpan(
              text: content,
              style: TextStyle(
                color: AppColors.primaryColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontStyle: FontStyle.italic,
              ),
            );
          } else {
            span = TextSpan(
              text: matchText,
              style: TextStyle(
                color: AppColors.primaryColor,
                fontSize: 16,
              ),
            );
          }
        }

        // ---------------------------------------------------
        // 5) Kalın (** veya __)
        // ---------------------------------------------------
        else if ((matchText.startsWith('**') && matchText.endsWith('**')) ||
            (matchText.startsWith('__') && matchText.endsWith('__'))) {
          if (matchText.length >= 4) {
            String content =
            matchText.substring(2, matchText.length - 2);
            span = TextSpan(
              text: content,
              style: TextStyle(
                color: AppColors.primaryColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            );
          } else {
            span = TextSpan(
              text: matchText,
              style: TextStyle(
                color: AppColors.primaryColor,
                fontSize: 16,
              ),
            );
          }
        }

        // ---------------------------------------------------
        // 6) İtalik (* veya _)
        // ---------------------------------------------------
        else if ((matchText.startsWith('*') && matchText.endsWith('*')) ||
            (matchText.startsWith('_') && matchText.endsWith('_'))) {
          if (matchText.length >= 2) {
            String content =
            matchText.substring(1, matchText.length - 1);
            span = TextSpan(
              text: content,
              style: TextStyle(
                color: AppColors.primaryColor,
                fontSize: 16,
                fontStyle: FontStyle.italic,
              ),
            );
          } else {
            span = TextSpan(
              text: matchText,
              style: TextStyle(
                color: AppColors.primaryColor,
                fontSize: 16,
              ),
            );
          }
        }

        // ---------------------------------------------------
        // 7) Üstü Çizili (~~...)
        // ---------------------------------------------------
        else if (matchText.startsWith('~~') && matchText.endsWith('~~')) {
          if (matchText.length >= 4) {
            String content =
            matchText.substring(2, matchText.length - 2);
            span = TextSpan(
              text: content,
              style: TextStyle(
                color: AppColors.primaryColor,
                fontSize: 16,
                decoration: TextDecoration.lineThrough,
              ),
            );
          } else {
            span = TextSpan(
              text: matchText,
              style: TextStyle(
                color: AppColors.primaryColor,
                fontSize: 16,
              ),
            );
          }
        }

        // ---------------------------------------------------
        // 8) Inline kod (`...`)
        // ---------------------------------------------------
        else if (matchText.startsWith('`') && matchText.endsWith('`')) {
          if (matchText.length >= 2) {
            String content =
            matchText.substring(1, matchText.length - 1);
            span = TextSpan(
              text: content,
              style: TextStyle(
                color: AppColors.primaryColor,
                fontSize: 16,
                fontFamily: 'monospace',
                backgroundColor: AppColors.tertiaryColor,
              ),
            );
          } else {
            span = TextSpan(
              text: matchText,
              style: TextStyle(
                color: AppColors.primaryColor,
                fontSize: 16,
              ),
            );
          }
        }

        // ---------------------------------------------------
        // 9) Yatay Çizgi (---)
        // ---------------------------------------------------
        else if (RegExp(horizontalRulePattern, multiLine: true, dotAll: true)
            .hasMatch(matchText.trim())) {
          span = WidgetSpan(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: 8.0, horizontal: 20),
              child: Divider(
                color: Colors.grey,
                thickness: 1,
              ),
            ),
          );
        }

        // ---------------------------------------------------
        // 10) Düz metin
        // ---------------------------------------------------
        else {
          span = TextSpan(
            text: matchText,
            style: TextStyle(
              color: AppColors.primaryColor,
              fontSize: 16,
            ),
          );
        }

        spans.add(span);
        currentIndex = match.end;
      } catch (e) {
        // Beklenmeyen bir hata oluştuğunda, ham metni varsayılan stil ile ekle
        print('Parser unexpected error at position ${match.start}: $e');
        spans.add(TextSpan(
          text: match.group(0),
          style: TextStyle(
            color: AppColors.primaryColor,
            fontSize: 16,
          ),
        ));
        currentIndex = match.end;
      }
    }

    // İşlenmemiş kalan metni ekle
    if (currentIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(currentIndex),
        style: TextStyle(
          color: AppColors.primaryColor,
          fontSize: 16,
        ),
      ));
    }

    return spans;
  } catch (e) {
    // Fonksiyon genelinde bir hata oluştuğunda ham metni döndür
    print('parseText unexpected error: $e');
    return [
      TextSpan(
        text: text,
        style: TextStyle(
          color: AppColors.primaryColor,
          fontSize: 16,
        ),
      )
    ];
  }
}

/// A stateful widget that measures the width of a rendered Math.tex widget
/// and, if it overflows, scales it down just enough to fit.
class _FittingLatexWidget extends StatefulWidget {
  final String latex;
  final bool isDarkTheme;

  const _FittingLatexWidget({
    Key? key,
    required this.latex,
    required this.isDarkTheme,
  }) : super(key: key);

  @override
  State<_FittingLatexWidget> createState() => _FittingLatexWidgetState();
}

class _FittingLatexWidgetState extends State<_FittingLatexWidget> {
  final GlobalKey _renderKey = GlobalKey();
  double _scale = 1.0;

  @override
  void didUpdateWidget(covariant _FittingLatexWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the LaTeX changes, re-measure and possibly rescale
    if (oldWidget.latex != widget.latex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureWidth());
    }
  }

  @override
  void initState() {
    super.initState();
    // Measure after the first layout
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureWidth());
  }

  void _measureWidth() {
    final renderBox = _renderKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final childWidth = renderBox.size.width;
    final availableWidth = renderBox.constraints.maxWidth;

    if (childWidth > availableWidth && availableWidth > 0) {
      setState(() {
        _scale = availableWidth / childWidth;
      });
    } else {
      setState(() {
        _scale = 1.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Transform.scale(
          scale: _scale,
          alignment: Alignment.topLeft,
          child: Container(
            key: _renderKey,
            child: Math.tex(
              widget.latex,
              textStyle: TextStyle(
                color: AppColors.primaryColor,
                fontSize: 16,
              ),
            ),
          ),
        );
      },
    );
  }
}