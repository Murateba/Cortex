import 'dart:convert';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';
import 'package:uuid/uuid.dart';
import 'settings.dart';
import 'data.dart';
import 'download.dart';
import 'main.dart';
import 'conversations.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'api.dart';
import 'messages.dart';
import 'notifications.dart';
import 'theme.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'system_info.dart';
import 'package:flutter/gestures.dart';
import 'package:share_plus/share_plus.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';

class ShortLongPressGestureRecognizer extends LongPressGestureRecognizer {
  ShortLongPressGestureRecognizer({
    required Object debugOwner,
    this.shortPressDuration = const Duration(milliseconds: 50),
  }) : super(debugOwner: debugOwner);

  final Duration shortPressDuration;

  @override
  Duration get deadline => shortPressDuration;
}

class Message {
  String text; // Mutable text
  final bool isUserMessage;
  bool shouldFadeOut;
  bool isReported;
  String? photoPath; // Yeni field for photo path
  bool isPhotoUploading;

  List<InlineSpan>? parsedSpans;

  Message({
    required this.text,
    required this.isUserMessage,
    this.shouldFadeOut = false,
    this.isReported = false,
    this.isPhotoUploading = false,
    this.photoPath,
    this.parsedSpans,
  });
}

class PhotoViewer extends StatelessWidget {
  final File imageFile;
  const PhotoViewer({Key? key, required this.imageFile}) : super(key: key);

  /// 50 ms açılma ve kapanma süresi
  static Route route(File imageFile) {
    return PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 50),
      reverseTransitionDuration: const Duration(milliseconds: 50),
      opaque: false, // Arka planın görünmesini sağlar
      barrierDismissible: false,
      pageBuilder: (_, __, ___) => PhotoViewer(imageFile: imageFile),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(animation);
        final scaleAnim = Tween<double>(begin: 0.90, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOut),
        );
        return FadeTransition(
          opacity: fadeAnim,
          child: ScaleTransition(scale: scaleAnim, child: child),
        );
      },
      barrierColor: Colors.black.withOpacity(0.5),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final _notificationService = Provider.of<NotificationService>(context, listen: false);

    return Scaffold(
      backgroundColor: Colors.transparent,
      // Tüm ekranı kapsaması için doğrudan Stack kullanıyoruz.
      body: Stack(
        children: [
          // Tüm ekranı kaplayan blur ve overlay
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
              child: Container(
                color: Colors.black.withOpacity(0.3),
              ),
            ),
          ),
          // Diğer içerikleri SafeArea içine alıyoruz.
          SafeArea(
            child: Stack(
              children: [
                // Resim: Ortalanmış, sadece ölçeklendirilebilsin (pan devre dışı)
                Center(
                  child: InteractiveViewer(
                    panEnabled: false,
                    scaleEnabled: true,
                    // Artık küçültme yapılmasın, sadece büyütme mümkün olsun:
                    minScale: 1.0,
                    maxScale: 4.0,
                    boundaryMargin: const EdgeInsets.all(1000),
                    clipBehavior: Clip.none,
                    // Resmi biraz iç kenarlardan geçiriyoruz ve köşeleri yuvarlatıyoruz
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30), // yatay margin
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20), // köşe yuvarlama
                        child: Image.file(
                          imageFile,
                          fit: BoxFit.contain, // resmin orantısının korunması için
                        ),
                      ),
                    ),
                  ),
                ),
                // Kapat (X) butonu
                Positioned(
                  top: 10,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
                // Paylaş ve İndir butonları
                Positioned(
                  bottom: 15,
                  left: 70,
                  right: 70,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // PAYLAŞ butonu
                      GestureDetector(
                        onTap: () async {
                          await Share.shareXFiles([XFile(imageFile.path)]);
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SvgPicture.asset(
                              'assets/share.svg',
                              width: 20,
                              height: 20,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              localizations.share,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 90),
                        height: 50,
                        width: 0.4,
                        color: Colors.white,
                      ),
                      // İNDİR butonu (GallerySaver Plus kullanımı)
                      GestureDetector(
                        onTap: () async {
                          try {
                            final tempDir = await getTemporaryDirectory();
                            final baseName = 'cortex';
                            const extension = '.jpg';
                            int i = 0;
                            late File localFile;

                            while (true) {
                              final fileName = i == 0
                                  ? '$baseName$extension'
                                  : '$baseName-$i$extension';
                              localFile = File(path.join(tempDir.path, fileName));
                              if (!(await localFile.exists())) {
                                break;
                              }
                              i++;
                            }

                            // Resmi geçici dizine kopyala
                            await imageFile.copy(localFile.path);

                            // Galeriye kaydet
                            final bool? success = await GallerySaver.saveImage(localFile.path);

                            if (success == true) {
                              _notificationService.showNotification(
                                message: localizations.downloadSuccess,
                                isSuccess: true,
                                bottomOffset: 0.1,
                              );
                            } else {
                              _notificationService.showNotification(
                                message: localizations.downloadFailed,
                                isSuccess: false,
                                bottomOffset: 0.1,
                              );
                            }
                          } catch (e) {
                            _notificationService.showNotification(
                              message: localizations.downloadFailed,
                              isSuccess: false,
                              bottomOffset: 0.1,
                            );
                          }
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SvgPicture.asset(
                              'assets/download.svg',
                              width: 20,
                              height: 20,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              localizations.download,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
                color: widget.isDarkTheme ? Colors.white : Colors.black,
                fontSize: 16,
              ),
            ),
          ),
        );
      },
    );
  }
}

class ModelInfo {
  final String id;
  final String title;
  final String description;
  final String imagePath;
  final String producer;
  final String? path;
  final String? role;
  final bool canHandleImage;

  ModelInfo({
    required this.id,
    required this.title,
    required this.description,
    required this.imagePath,
    required this.producer,
    this.path,
    this.role,
    this.canHandleImage = false,
  });
}

class HexagonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    double width = size.width;
    double height = size.height;
    double centerHeight = height / 2;

    Path path = Path();
    path.moveTo(width * 0.25, 0); // Top-left
    path.lineTo(width * 0.75, 0); // Top-right
    path.lineTo(width, centerHeight); // Middle-right
    path.lineTo(width * 0.75, height); // Bottom-right
    path.lineTo(width * 0.25, height); // Bottom-left
    path.lineTo(0, centerHeight); // Middle-left
    path.close();

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class HexagonBorderPainter extends CustomPainter {
  final Color fillColor;   // eklendi
  final Color borderColor;
  final double strokeWidth;

  HexagonBorderPainter({
    required this.fillColor,   // eklendi
    required this.borderColor,
    this.strokeWidth = 1.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Altıgen path oluştur
    final double width = size.width;
    final double height = size.height;
    final double centerHeight = height / 2;

    Path path = Path()
      ..moveTo(width * 0.25, 0)       // Top-left
      ..lineTo(width * 0.75, 0)       // Top-right
      ..lineTo(width, centerHeight)   // Right-center
      ..lineTo(width * 0.75, height)  // Bottom-right
      ..lineTo(width * 0.25, height)  // Bottom-left
      ..lineTo(0, centerHeight)       // Left-center
      ..close();

    // 1) Önce dolguyu boya
    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // 2) Sonra dış çizgiyi (stroke) boya
    final strokePaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant HexagonBorderPainter oldDelegate) {
    return oldDelegate.fillColor != fillColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}


Widget buildChatActionButton(bool isDarkTheme, VoidCallback onPressed) {
  return AnimatedSwitcher(
    duration: const Duration(milliseconds: 100),
    transitionBuilder: (Widget child, Animation<double> animation) {
      return ScaleTransition(scale: animation, child: child);
    },
    child: GestureDetector(
      key: const ValueKey('sendButton'),
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: isDarkTheme ? Colors.white : Colors.black,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          Icons.arrow_upward,
          color: isDarkTheme ? Colors.black : Colors.white,
          size: 24,
        ),
      ),
    ),
  );
}

class ExpandedInputScreen extends StatefulWidget {
  /// Mevcut metni ve controller’ı korumak için:
  final String initialText;
  final bool isDarkTheme;
  final TextEditingController controller;

  /// Genişlemeden çıkarken güncellenmiş metni geri döndürmek için:
  final ValueChanged<String> onShrink;

  /// (Opsiyonel) Gönderme butonuna basıldığında mesaj gönderme işlemini tetiklemek için callback.
  final VoidCallback? onSend;

  const ExpandedInputScreen({
    Key? key,
    required this.initialText,
    required this.isDarkTheme,
    required this.controller,
    required this.onShrink,
    this.onSend,
  }) : super(key: key);

  @override
  _ExpandedInputScreenState createState() => _ExpandedInputScreenState();
}

class _ExpandedInputScreenState extends State<ExpandedInputScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    // 200 ms’lik animasyon controller’ı
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 50),
    );

    // Hafif büyüme: 0.9'dan 1.0'a
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    // Fade in: opaklık 0’dan 1’e
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    _animationController.forward();

    // Her değişimde ekranı yeniden çiz
    widget.controller.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// Bu metot, ekran kapanınca onShrink callback’ini tetikler.
  Future<void> _shrinkAndReturn() async {
    await _animationController.reverse();
    widget.onShrink(widget.controller.text);
    Navigator.of(context).pop();
  }

  /// Action butonuna basıldığında: önce klavye kapatılır, 100 ms sonra ekran kapanır,
  /// kapanma tamamlandığında (Navigator.pop sonrası) varsa onSend callback’i tetiklenir.
  void _onActionButtonPressed() {
    FocusScope.of(context).unfocus();
    Future.delayed(const Duration(milliseconds: 100), () {
      _shrinkAndReturn().then((_) {
        if (widget.onSend != null) {
          widget.onSend!();
        }
      });
    });
  }

  /// Fiziksel geri tuşuna basıldığında:
  /// Eğer klavye açıksa yalnızca kapat, kapalıysa ekranı kapat.
  Future<bool> _onWillPop() async {
    if (MediaQuery.of(context).viewInsets.bottom > 0) {
      FocusScope.of(context).unfocus();
      return false;
    } else {
      _shrinkAndReturn();
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    // Arka plan rengi; koyu temada InputField ve SafeArea'nın arka planı için
    final Color bgColor = widget.isDarkTheme ? const Color(0xFF161616) : Colors.grey[300]!;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        // extendBody kullanmadığımız için telefonun üst paneli korunur.
        resizeToAvoidBottomInset: true,
        backgroundColor: bgColor,
        body: SafeArea(
          // SafeArea'nın arka planı da bgColor
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                width: size.width,
                height: size.height,
                constraints: const BoxConstraints.expand(),
                child: Stack(
                  children: [
                    // Geniş moddaki input alanı; tüm ekranı kaplar.
                    Positioned.fill(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(0),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SingleChildScrollView(
                          child: TextField(
                            controller: widget.controller,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            maxLines: null,
                            maxLength: 4000,
                            autofocus: true,
                            decoration: InputDecoration(
                              hintText: AppLocalizations.of(context)?.messageHint,
                              counterText: "",
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.only(
                                  left: 10, top: 10, bottom: 10, right: 60),
                            ),
                            style: TextStyle(
                              color: widget.isDarkTheme ? Colors.white : Colors.black,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Shrink butonu: Sağ üstte, ikon boyutu 20x20; ikon ile metin arasında 5px alt boşluk.
                    Positioned(
                      top: 16,
                      right: 16,
                      child: GestureDetector(
                        onTap: _shrinkAndReturn,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 5.0),
                          child: SvgPicture.asset(
                            'assets/shrink.svg',
                            width: 20,
                            height: 20,
                            // Açık tema: siyah, koyu tema: beyaz.
                            color: widget.isDarkTheme ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                    ),
                    // Gönderme (action) butonu: Sağ alt köşede, ChatScreen'deki action button stilinde.
                    // Buton yalnızca TextField’de en az 1 karakter varsa gösteriliyor.
                    Positioned(
                      bottom: 10,
                      right: 10,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 100),
                        child: widget.controller.text.trim().isEmpty
                            ? const SizedBox(width: 0, height: 0)
                            : buildChatActionButton(
                            widget.isDarkTheme, _onActionButtonPressed),
                      ),
                    ),
                    // Yatayda sağdan en az 20 px boşluk bırakmak için ek Container.
                    const Positioned(
                      top: 0,
                      bottom: 0,
                      right: 0,
                      width: 20,
                      child: SizedBox(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  String? conversationID;
  String? conversationTitle;

  // Yeni model parametreleri
  final String? modelTitle;
  final String? modelDescription;
  final String? modelImagePath;
  final String? modelProducer;
  final String? modelPath;
  final String? role;
  final String? modelId;

  ChatScreen({
    super.key,
    this.conversationID,
    this.conversationTitle,
    this.modelId,
    this.modelTitle,
    this.modelDescription,
    this.modelImagePath,
    this.modelProducer,
    this.modelPath,
    this.role,
  });

  @override
  ChatScreenState createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  List<Message> messages = [];
  final TextEditingController _controller = TextEditingController();
  bool isModelLoaded = false;
  bool isWaitingForResponse = false;
  Timer? responseTimer;
  final uuid = const Uuid();
  String? conversationID;
  String? conversationTitle;
  final FocusNode _textFieldFocusNode = FocusNode();
  bool _isSendButtonVisible = false;
  bool _isSending = false;
  bool canHandleImage = false;
  bool _creditsDeducted = false;
  final List<String> _specialServerSideModels = [
    'gemini',
    'llama',
    'hermes',
    'chatgpt4omini',
    'claude3haiku',
    'amazonnovalite'
  ];
  String? modelId;
  List<String> otherServerSideModels = [];
  bool _hasUserInitiatedConversation = false;
  bool responseStopped = false;
  bool _showInappropriateMessageWarning = false;

  late AnimationController _warningAnimationController;
  late Animation<Offset> _warningSlideAnimation;
  late Animation<double> _warningFadeAnimation;

  bool _showScrollDownButton = false;
  bool hasInternetConnection = true;
  late StreamSubscription<InternetStatus> _internetSubscription;

  int _hasCortexSubscription = 0;
  int _credits = 0;
  int _bonusCredits = 0;
  int get totalCredits => _credits + _bonusCredits;
  bool _showLimitReachedWarning = false;
  String _currentWarningMessage = '';
  bool _isLimitFadeOutApplied = false;
  late AnimationController _searchAnimationController;
  List<Animation<double>> _modelAnimations = [];
  Map<String, dynamic>? _userData;

  DateTime? _lastResetDate;

  bool _shouldShowLimitWarningAfterFadeOut = false;
  int _fadeOutCount = 0;
  final List<String> _responseChunksQueue = [];
  bool _isProcessingChunks = false;

  bool _isApiServiceInitialized = false;
  late ApiService apiService;

  bool isModelSelected = false;
  bool _modelsLoaded = false;

  List<ModelInfo> _allModels = [];
  List<ModelInfo> _filteredModels = [];

  // Statik cache değişkenleri
  static List<ModelInfo>? cachedAllModels;
  static List<ModelInfo>? cachedFilteredModels;

  String _searchQuery = '';

  bool isStorageSufficient = true;
  static const int requiredSizeMB = 1024; // 1GB in MB
  SystemInfoData? _systemInfo;

  String? modelTitle;
  String? modelDescription;
  String? modelImagePath;
  String? modelProducer;
  String? modelPath;
  String? role;
  static bool languageHasJustChanged = false;
  File? _selectedPhoto;
  bool _isPhotoLoading = false;
  final ImagePicker _imagePicker = ImagePicker();
  bool _showPhotoContent = false;

  static const MethodChannel llamaChannel =
  MethodChannel('com.vertex.cortex/llama');

  final ScrollController _scrollController = ScrollController();

  int _serverSideConversationsCount = 0;
  int _serverSideConversationLimit = 25; // default for free
  bool _conversationLimitReached = false;
  int _getConversationLimit(int subValue) {
    // MATCHES the logic in your daily bonus system:
    //   - free =>  25
    //   - plus =>  1 or 4 => 50
    //   - pro  =>  2 or 5 => 75
    //   - ultra => 3 or 6 => 100
    if (subValue == 1 || subValue == 4) {
      return 50;
    } else if (subValue == 2 || subValue == 5) {
      return 75;
    } else if (subValue == 3 || subValue == 6) {
      return 100;
    } else {
      return 25; // free
    }
  }

  bool _openedFromMenu = false;
  bool _shouldHideImmediately = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (languageHasJustChanged) {
      // Force a reload if user changed language:
      languageHasJustChanged = false;
      cachedAllModels = null;
      cachedFilteredModels = null;
      _modelsLoaded = false;
      _loadModels();
    }

    if (!_isApiServiceInitialized) {
      final localizations = AppLocalizations.of(context)!;
      apiService = ApiService(localizations: localizations);
      _isApiServiceInitialized = true;
      _updateModelDataFromId();
    }

    if (widget.conversationID != null && isServerSideModel(modelId)) {
      setState(() {
        isModelSelected = true;
        isModelLoaded = true;
      });
    }

    otherServerSideModels = [
      'teacher','doctor','animegirl','shaver','psychologist','mrbeast',
    ];
  }

  @override
  void initState() {
    super.initState();

    if (cachedAllModels != null && cachedAllModels!.isNotEmpty) {
      _allModels = List.from(cachedAllModels!);
      _filteredModels = cachedFilteredModels ?? List.from(_allModels);
      _modelsLoaded = true;
    } else {
      // 2) Otherwise, load fresh:
      _loadModels();
    }

    WidgetsBinding.instance.addObserver(this);

    _searchAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _showScrollDownButton = false;

    _fetchSystemInfo();
    _fetchUserData();
    modelTitle = widget.modelTitle;
    modelDescription = widget.modelDescription;
    modelImagePath = widget.modelImagePath;
    modelProducer = widget.modelProducer;
    modelPath = widget.modelPath;
    modelId = widget.modelId;
    role = widget.role;

    _warningAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _warningSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1.0),
      end: const Offset(0, 0),
    ).animate(
      CurvedAnimation(
        parent: _warningAnimationController,
        curve: Curves.easeInOut,
      ),
    );
    _warningFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _warningAnimationController,
        curve: Curves.easeIn,
      ),
    );

    _warningAnimationController.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        setState(() {
          _showInappropriateMessageWarning = false;
          _showLimitReachedWarning = false;
        });
      }
    });

    if (isServerSideModel(modelId)) {
      isModelSelected = true;
      isModelLoaded = true;
    } else if (modelPath != null && modelPath!.isNotEmpty) {
      isModelSelected = true;
      loadModel();
    }

    llamaChannel.setMethodCallHandler(_methodCallHandler);

    if (widget.conversationID != null) {
      _loadPreviousMessages(widget.conversationID!);
      conversationID = widget.conversationID;
      conversationTitle = widget.conversationTitle;
    }

    final downloadHelper = Provider.of<FileDownloadHelper>(context, listen: false);
    downloadHelper.addListener(_loadModels);

    _scrollController.addListener(_scrollListener);

    _internetSubscription =
        InternetConnection().onStatusChange.listen((status) {
          final hasConnection = status == InternetStatus.connected;
          setState(() {
            hasInternetConnection = hasConnection;
          });
        });
  }

  Future<void> _fetchSystemInfo() async {
    try {
      SystemInfoData info = await SystemInfoProvider.fetchSystemInfo();
      setState(() {
        _systemInfo = info;
        isStorageSufficient = _systemInfo!.freeStorage >= requiredSizeMB;
      });
    } catch (e) {
      print("Error fetching system info: $e");
      setState(() {
        isStorageSufficient = false;
      });
    }
  }

// ---------------------------------------------------
// 1) _fetchUserData() -- now also loads 'conversations' count
// ---------------------------------------------------
  Future<void> _fetchUserData() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        setState(() {
          _userData = userDoc.data();
          _credits = _userData?['credits'] ?? 0;
          _bonusCredits = _userData?['bonusCredits'] ?? 0;
          _hasCortexSubscription = _userData?['hasCortexSubscription'] ?? 0;

          // <-- NEW: get server-side conversations count from Firestore
          // (assumes the field is named "conversations" on the user doc)
          _serverSideConversationsCount = _userData?['conversations'] ?? 0;

          // figure out the user’s conversation limit
          _serverSideConversationLimit = _getConversationLimit(_hasCortexSubscription);

          // check if user already hit or exceeded the limit
          _conversationLimitReached = _serverSideConversationsCount >= _serverSideConversationLimit;

          final lastResetTimestamp = _userData?['lastResetDate'];
          if (lastResetTimestamp != null) {
            _lastResetDate = (lastResetTimestamp as Timestamp).toDate();
          } else {
            _lastResetDate = null;
          }
        });

        // The daily bonus logic below is unchanged from your snippet:
        if (_lastResetDate == null ||
            DateTime.now().difference(_lastResetDate!).inDays >= 1) {
          int bonus;
          if (_hasCortexSubscription == 1 || _hasCortexSubscription == 4) {
            bonus = 250;
          } else if (_hasCortexSubscription == 2 || _hasCortexSubscription == 5) {
            bonus = 450;
          } else if (_hasCortexSubscription == 3 || _hasCortexSubscription == 6) {
            bonus = 900;
          } else {
            bonus = 100;
          }

          await _updateCreditsOnFirebase(
            newCredits: _credits,
            newBonusCredits: bonus,
            setLastResetDate: true,
          );
          setState(() {
            _bonusCredits = bonus;
            _lastResetDate = DateTime.now();
          });
        }
      } catch (e) {
        print("Error fetching user data: $e");
      }
    }
  }

  Future<void> _updateCreditsOnFirebase({
    int? newCredits,
    int? newBonusCredits,
    bool setLastResetDate = false,
  }) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    Map<String, dynamic> dataToUpdate = {};

    if (newCredits != null) {
      dataToUpdate['credits'] = newCredits;
    }
    if (newBonusCredits != null) {
      dataToUpdate['bonusCredits'] = newBonusCredits;
    }
    if (setLastResetDate) {
      dataToUpdate['lastResetDate'] = FieldValue.serverTimestamp();
    }

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .update(dataToUpdate);

    // Local state de güncellenmeli:
    setState(() {
      if (newCredits != null) {
        _credits = newCredits;
      }
      if (newBonusCredits != null) {
        _bonusCredits = newBonusCredits;
      }
      if (setLastResetDate) {
        _lastResetDate = DateTime.now();
      }
    });
  }

  void _scrollListener() {
    if (!_scrollController.hasClients) return;
    if (!_isUserAtBottom() && messages.length > 1) {
      if (!_showScrollDownButton) {
        setState(() {
          _showScrollDownButton = true;
        });
      }
    } else {
      if (_showScrollDownButton) {
        setState(() {
          _showScrollDownButton = false;
        });
      }
    }
  }

  double _inputFieldHeight = 0.0;
  final GlobalKey _inputFieldKey = GlobalKey();

  void clearModelSelection() {
    setState(() {
      isModelSelected = false;
      modelTitle = null;
      modelDescription = null;
      modelImagePath = null;
      modelProducer = null;
      modelPath = null;
      role = null;
      isModelLoaded = false;
    });
  }

  Future<void> _loadModels() async {
    if (_modelsLoaded) return;

    // Clear existing model lists
    _allModels.clear();
    _filteredModels.clear();

    // Try to load from cache first
    if (cachedAllModels != null && cachedAllModels!.isNotEmpty) {
      _allModels = List.from(cachedAllModels!);
      _filteredModels = cachedFilteredModels ?? List.from(_allModels);
      setState(() => _modelsLoaded = true);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final localizations = AppLocalizations.of(context)!;
    final List<Map<String, dynamic>> allModelsData = ModelData.models(context);
    final Set<String> addedIds = {};

    // 1. Load built-in local/server-side models
    for (var model in allModelsData) {
      String id = model['id'];
      bool isServerSide = model['isServerSide'] ?? false;
      String title = model['title'];
      String description = model['description'];
      String image = model['image'];
      String producer = model['producer'];
      String? role = model['role'];
      bool canHandleImage = model['canHandleImage'] ?? false;

      if (addedIds.contains(id)) continue;

      if (!isServerSide) {
        // Check if local model is downloaded
        bool isDownloaded = prefs.getBool('is_downloaded_$id') ?? false;
        if (isDownloaded) {
          String modelFilePath = await _getModelFilePath(title);
          _allModels.add(ModelInfo(
            id: id,
            title: title,
            description: description,
            imagePath: image,
            producer: producer,
            path: modelFilePath,
            role: role,
            canHandleImage: canHandleImage,
          ));
          addedIds.add(id);
        }
      } else {
        // Add server-side models directly
        _allModels.add(ModelInfo(
          id: id,
          title: title,
          description: description,
          imagePath: image,
          producer: producer,
          path: null,
          role: role,
          canHandleImage: canHandleImage,
        ));
        addedIds.add(id);
      }
    }

    // 2. Load custom models
    Directory dir = await getApplicationDocumentsDirectory();
    List<FileSystemEntity> files = await dir.list().toList();
    List<File> ggufFiles = files
        .whereType<File>()
        .where((file) => file.path.endsWith('.gguf'))
        .toList();

    final Set<String> predefinedModelPaths = {};
    for (var model in allModelsData) {
      if (!(model['isServerSide'] ?? false)) {
        String modelFilePath = await _getModelFilePath(model['title']);
        predefinedModelPaths.add(modelFilePath);
      }
    }

    for (var file in ggufFiles) {
      if (!predefinedModelPaths.contains(file.path)) {
        String title = path.basenameWithoutExtension(file.path);
        String id = 'custom_$title';
        if (addedIds.contains(id)) continue;
        bool isDownloaded = prefs.getBool('is_downloaded_$title') ?? false;
        if (isDownloaded) {
          _allModels.add(ModelInfo(
            id: id,
            title: title,
            description: localizations.myModelDescription,
            imagePath: 'assets/customai.png',
            producer: 'User',
            path: file.path,
            role: null,
            canHandleImage: false,
          ));
          addedIds.add(id);
        }
      }
    }

    // Update filtered models FIRST
    _filteredModels = List.from(_allModels);

    // Then update cache
    cachedAllModels = List.from(_allModels);
    cachedFilteredModels = List.from(_filteredModels);

    setState(() => _modelsLoaded = true);
  }

  void resetModelCacheAndReload() {
    cachedAllModels = null;
    cachedFilteredModels = null;
    _loadModels();
  }

  Future<void> loadModel() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedModelPath =
        modelPath ?? prefs.getString('selected_model_path');
    if (selectedModelPath != null && selectedModelPath.isNotEmpty) {
      try {
        await llamaChannel
            .invokeMethod('loadModel', {'path': selectedModelPath});
        setState(() {
          isModelLoaded = true;
        });
        mainScreenKey.currentState?.updateBottomAppBarVisibility();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          FocusScope.of(context).requestFocus(_textFieldFocusNode);
        });
      } catch (e) {
        print('Error loading model: $e');
        setState(() {
          isModelLoaded = false;
        });
        mainScreenKey.currentState?.updateBottomAppBarVisibility();
      }
    } else {
      setState(() {
        isModelLoaded = false;
      });
      mainScreenKey.currentState?.updateBottomAppBarVisibility();
    }
  }

  Future<void> _methodCallHandler(MethodCall call) async {
    if (call.method == 'onMessageResponse') {
      if (isLocalModel(modelTitle)) {
        _onMessageResponse(call.arguments as String);
      } else if (isServerSideModel(modelId)) {
        final data = call.arguments;
        String decodedMessage;
        if (data is Uint8List) {
          decodedMessage = utf8.decode(data);
        } else if (data is String) {
          decodedMessage = data;
        } else {
          decodedMessage = '';
        }
        _onMessageResponse(decodedMessage);
      }
    } else if (call.method == 'onMessageComplete') {
      _stopResponse();
    } else if (call.method == 'onModelLoaded') {
      setState(() => isModelLoaded = true);
    }
  }

  bool isLocalModel(String? modelId) {
    return !isServerSideModel(modelId);
  }

  bool isServerSideModel(String? modelId) {
    if (modelId == null) return false;
    return _specialServerSideModels.contains(modelId) ||
        otherServerSideModels.contains(modelId);
  }

  Future<String> _getModelFilePath(String title) async {
    Directory appDocDir = await getApplicationDocumentsDirectory();
    String filesDirectoryPath = appDocDir.path;
    String sanitizedTitle = title.replaceAll(' ', '_');
    return path.join(filesDirectoryPath, '$sanitizedTitle.gguf');
  }

  Future<void> _processResponseChunks() async {
    _isProcessingChunks = true;
    while (_responseChunksQueue.isNotEmpty && isWaitingForResponse) {
      String chunk = _responseChunksQueue.removeAt(0);
      setState(() {
        messages.last.text += chunk;
      });
      _scrollToBottom(forceScroll: true);
      await Future.delayed(const Duration(milliseconds: 300));
    }
    _isProcessingChunks = false;
  }


  void _onMessageResponse(String token) {
    if (isWaitingForResponse &&
        messages.isNotEmpty &&
        !messages.last.isUserMessage) {
      _responseChunksQueue.add(token);
      if (!_isProcessingChunks) {
        _processResponseChunks();
      }
    }
  }

  void _startResponseTimeout() {
    responseTimer?.cancel();
    responseTimer = Timer(const Duration(seconds: 5), _stopResponse);
  }

  Future<void> _loadPreviousMessages(String conversationID) async {
    final prefs = await SharedPreferences.getInstance();
    final String? messagesJson = prefs.getString(conversationID);
    if (messagesJson == null) return;

    try {
      final List<dynamic> storedMessages = jsonDecode(messagesJson);
      messages.clear();
      for (var item in storedMessages) {
        messages.add(Message(
          text: item["text"] ?? "",
          isUserMessage: item["isUserMessage"] ?? false,
          shouldFadeOut: item["shouldFadeOut"] ?? false,
          isReported: item["isReported"] ?? false,
          photoPath: item["photoPath"],
        ));
      }
    } catch (e) {
      print("JSON parse error: $e");
    }

    if (messages.isNotEmpty) {
      Message lastMessage = messages.last;
      if (!lastMessage.isUserMessage &&
          lastMessage.text.trim().isEmpty &&
          (lastMessage.photoPath == null || lastMessage.photoPath!.isEmpty)) {
        messages.removeLast();
      }
    }

    if (!messages.any((m) => m.isUserMessage)) {
      messages.removeWhere((m) => !m.isUserMessage);
    }

    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollToBottom(forceScroll: true);
      });
    });
  }

  Future<void> _saveConversationTitle(String title) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_conversation_title', title);
  }

  Future<void> _saveMessageToConversation(
      String message,
      bool isUserMessage, {
        bool isReported = false,
        String? photoPath,
      }) async {
    if (conversationID == null) return;

    final prefs = await SharedPreferences.getInstance();
    final String? messagesJson = prefs.getString(conversationID!);
    List<dynamic> storedMessages = [];
    if (messagesJson != null) {
      try {
        storedMessages = jsonDecode(messagesJson);
      } catch (e) {
        print("JSON parse error: $e");
        storedMessages = [];
      }
    }

    Map<String, dynamic> messageData = {
      "text": message,
      "isUserMessage": isUserMessage,
      "shouldFadeOut": false,
      "isReported": isReported,
    };
    if (photoPath != null) {
      messageData["photoPath"] = photoPath;
    }
    storedMessages.add(messageData);

    await prefs.setString(conversationID!, jsonEncode(storedMessages));
  }

  Future<void> _updateConversationLastMessageText(
      String message, {
        String? photoPath,
      }) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> conversations = prefs.getStringList('conversations') ?? [];

    if (conversationID == null) return;

    int index = conversations.indexWhere((c) => c.startsWith('$conversationID|'));
    if (index == -1) {
      return;
    }

    String conversationEntry = conversations[index];
    List<String> parts = conversationEntry.split('|');

    // Mesaj boş ama foto var ise "PHOTO_ONLY"
    String sanitizedMessage = message.replaceAll('|', ' ');
    if (sanitizedMessage.trim().isEmpty && (photoPath?.isNotEmpty ?? false)) {
      sanitizedMessage = 'PHOTO_ONLY';
    }

    if (parts.length >= 6) {
      parts[4] = sanitizedMessage;
      parts[5] = photoPath ?? '';
    } else {
      // parts yetersizse tamamla
      while (parts.length < 5) {
        parts.add('');
      }
      parts[4] = sanitizedMessage;
      parts.add(photoPath ?? '');
    }

    String newConversationEntry = parts.join('|');
    conversations[index] = newConversationEntry;
    await prefs.setStringList('conversations', conversations);

    mainScreenKey.currentState?.menuScreenKey.currentState?.reloadConversations();
  }

  Future<void> _updateConversationLastMessageDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> conversations = prefs.getStringList('conversations') ?? [];

    if (conversationID == null) return;

    int index =
    conversations.indexWhere((c) => c.startsWith('$conversationID|'));
    if (index == -1) {
      return;
    }

    String conversationEntry = conversations[index];
    List<String> parts = conversationEntry.split('|');

    String lastMessageDateString = date.toIso8601String();
    if (parts.length >= 4) {
      parts[3] = lastMessageDateString;
    } else {
      while (parts.length < 4) {
        parts.add('');
      }
      parts[3] = lastMessageDateString;
    }

    String newConversationEntry = parts.join('|');
    conversations[index] = newConversationEntry;
    await prefs.setStringList('conversations', conversations);
  }

  String _buildMemory() {
    String memory = '';
    for (var message in messages.reversed) {
      if (message.isUserMessage) {
        String newMemory = message.text + ' ' + memory;
        if (newMemory.length > 500) {
          memory = newMemory.substring(newMemory.length - 500);
          break;
        } else {
          memory = newMemory;
        }
      }
    }
    return memory.trim();
  }

  void loadConversation(ConversationManager manager) {
    setState(() {
      widget.conversationID = manager.conversationID;
      widget.conversationTitle = manager.conversationTitle;
      conversationID = manager.conversationID;
      conversationTitle = manager.conversationTitle;
      modelId = manager.modelId;
      modelTitle = manager.modelTitle;
      modelImagePath = manager.modelImagePath;
      isModelSelected = true;
      // Bu durumda sohbetin menüden açıldığını belirtiyoruz:
      _openedFromMenu = true;
      isModelLoaded = manager.isModelAvailable
          ? (isServerSideModel(modelId) ? true : false)
          : false;
      messages.clear();
      responseStopped = false;
      canHandleImage = manager.canHandleImage;
    });

    _loadPreviousMessages(manager.conversationID);

    if (isServerSideModel(modelId)) {
      setState(() {
        isModelSelected = true;
        isModelLoaded = true;
      });
    } else {
      isModelSelected = true;
      loadModel();
    }
    mainScreenKey.currentState?.updateBottomAppBarVisibility();
  }

  void updateConversationTitle(String newTitle) {
    setState(() {
      conversationTitle = newTitle;
    });
  }

  void updateModelData({
    String? id,
    String? title,
    String? description,
    String? imagePath,
    String? producer,
    String? path,
    String? role,
    required bool isServerSide,
  }) {
    setState(() {
      modelId = id;
      modelTitle = title ?? modelTitle;
      modelDescription = description ?? modelDescription;
      modelImagePath = imagePath ?? modelImagePath;
      modelProducer = producer ?? modelProducer;
      modelPath = path ?? modelPath;
      this.role = role ?? this.role;
      isModelSelected = true;
      isModelLoaded = isServerSide ? true : false;
      mainScreenKey.currentState?.updateBottomAppBarVisibility();
      resetConversation(resetModel: false);
    });
  }

  void _selectModel(ModelInfo model) async {
    // Yeni sohbet başlamadan önce eski verileri temizle:
    await resetConversation(); // conversationID, widget.conversationID, conversationTitle, messages vs. sıfırlanır

    setState(() {
      modelId = model.id;
      modelTitle = model.title;
      modelDescription = model.description;
      modelImagePath = model.imagePath;
      modelProducer = model.producer;
      modelPath = model.path;
      role = model.role;
      canHandleImage = model.canHandleImage;
      // Burada conversationID ve conversationTitle sıfırlı kalmalıdır.
    });

    if (isServerSideModel(model.id)) {
      setState(() {
        isModelLoaded = true;
      });
    } else {
      loadModel();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        mainScreenKey.currentState?.updateBottomAppBarVisibility();
        isModelSelected = true;
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 160), () {
        FocusScope.of(context).requestFocus(_textFieldFocusNode);
      });
    });
  }

  Future<void> resetConversation({bool resetModel = false}) async {
    setState(() {
      messages.clear();
      conversationID = null;
      conversationTitle = null;
      widget.conversationID = null;
      widget.conversationTitle = null;
      isWaitingForResponse = false;
      _isSendButtonVisible = false;
      responseStopped = false;
      _fadeOutCount = 0;
      if (resetModel) {
        isModelSelected = false;
        isModelLoaded = false;
      }
    });
    mainScreenKey.currentState?.menuScreenKey.currentState?.reloadConversations();
  }

  Future<void> _saveConversation(String conversationName) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> conversations = prefs.getStringList('conversations') ?? [];

    // Sohbet başlığı boş ise "🖼" ikonu kullan
    if (conversationName.trim().isEmpty) {
      conversationName = "🖼";
    }

    String lastMessageDateString = DateTime.now().toIso8601String();
    String lastMessageText = '';
    String lastMessagePhotoPath = '';

    if (messages.isNotEmpty) {
      lastMessageText = messages.last.text;
      lastMessagePhotoPath = messages.last.photoPath ?? '';
    }

    // Son mesaj yalnızca fotoğraftan ibaretse "PHOTO_ONLY" olarak kaydet
    if (lastMessageText.trim().isEmpty && lastMessagePhotoPath.isNotEmpty) {
      lastMessageText = "PHOTO_ONLY";
    }

    String sanitizedLastMessageText = lastMessageText.replaceAll('|', ' ');
    String sanitizedLastMessagePhotoPath =
    lastMessagePhotoPath.replaceAll('|', ' ');

    String conversationEntry =
        '$conversationID|$conversationName|$modelId|$lastMessageDateString|$sanitizedLastMessageText|$sanitizedLastMessagePhotoPath';

    // Aynı conversationID daha önce yoksa ekle:
    if (!conversations.any((c) => c.startsWith('$conversationID|'))) {
      conversations.add(conversationEntry);
      await prefs.setStringList('conversations', conversations);
    }
  }

  bool _isUserAtBottom() {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return (maxScroll - currentScroll) <= 10;
  }

  Future<void> _scrollToBottom({bool forceScroll = false}) async {
    if (!_scrollController.hasClients) return;
    if (forceScroll || _isUserAtBottom()) {
      await _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      if (forceScroll) {
        setState(() {
          _showScrollDownButton = false;
        });
      }
    }
  }

  Map<String, dynamic> _getModelDataFromId(String modelId) {
    List<Map<String, dynamic>> allModels = ModelData.models(context);
    return allModels.firstWhere((model) => model['id'] == modelId,
        orElse: () => {});
  }

  void _updateModelDataFromId() {
    if (modelId != null) {
      Map<String, dynamic> modelData = _getModelDataFromId(modelId!);
      if (modelData.isNotEmpty) {
        setState(() {
          modelTitle = modelData['title'];
          modelDescription = modelData['description'];
          modelImagePath = modelData['image'];
          modelProducer = modelData['producer'];
          modelPath = modelData['isServerSide'] == true ? null : modelPath;
        });
      }
    }
  }


  Future<void> _onRegenerate(int modelIndex) async {
    // 1) Stop any ongoing response
    await _stopResponse();

    // 2) Fade out and remove any messages after the chosen AI message
    for (int i = modelIndex + 1; i < messages.length; i++) {
      messages[i].shouldFadeOut = true;
    }
    setState(() {});
    await Future.delayed(const Duration(milliseconds: 400));
    setState(() {
      if (modelIndex + 1 < messages.length) {
        messages.removeRange(modelIndex + 1, messages.length);
      }
    });

    // Also remove these messages from local storage
    if (conversationID != null) {
      final prefs = await SharedPreferences.getInstance();
      final messagesJson = prefs.getString(conversationID!);
      if (messagesJson != null) {
        final List<dynamic> storedMessages = jsonDecode(messagesJson);
        if (modelIndex + 1 < storedMessages.length) {
          storedMessages.removeRange(modelIndex + 1, storedMessages.length);
          await prefs.setString(conversationID!, jsonEncode(storedMessages));
        }
      }
    }

    // 3) Clear the AI message text we are regenerating
    setState(() {
      messages[modelIndex].text = '';
      messages[modelIndex].shouldFadeOut = false;
    });

    // Also clear it in local storage
    if (conversationID != null) {
      final prefs = await SharedPreferences.getInstance();
      final messagesJson = prefs.getString(conversationID!);
      if (messagesJson != null) {
        final List<dynamic> storedMessages = jsonDecode(messagesJson);
        if (modelIndex >= 0 && modelIndex < storedMessages.length) {
          storedMessages[modelIndex]["text"] = "";
          await prefs.setString(conversationID!, jsonEncode(storedMessages));
        }
      }
    }

    // 4) Find the preceding user message (the "trigger")
    final int triggerUserIndex = modelIndex - 1;
    if (triggerUserIndex < 0 || triggerUserIndex >= messages.length) {
      return;
    }

    final String triggerUserMessage = messages[triggerUserIndex].text.trim();
    final bool userMessageWasPhotoOnly =
        messages[triggerUserIndex].photoPath != null && triggerUserMessage.isEmpty;

    // 5) Call _sendMessage again, but pass an empty space if it was photo-only
    await _sendMessage(
      textFromButton: userMessageWasPhotoOnly ? ' ' : triggerUserMessage,
      isRegenerate: true,
      regenerateAiIndex: modelIndex,
      // Pass the original photo path if the user message had a photo only
      regeneratePhotoPath: userMessageWasPhotoOnly
          ? messages[triggerUserIndex].photoPath
          : null,
    );
  }

  /// [2] Regenerate edilen AI mesajını kaydetme metodu
  Future<void> _saveRegeneratedMessageToConversation({
    required String finalResponse,
    required int aiIndex,
  }) async {
    if (conversationID == null) return;

    final prefs = await SharedPreferences.getInstance();
    final messagesJson = prefs.getString(conversationID!);
    if (messagesJson == null) return;

    List<dynamic> storedMessages;
    try {
      storedMessages = jsonDecode(messagesJson);
    } catch (e) {
      print("JSON parse error: $e");
      return;
    }
    if (aiIndex < 0 || aiIndex >= storedMessages.length) {
      return;
    }

    storedMessages[aiIndex]["text"] = finalResponse;
    storedMessages[aiIndex]["isReported"] = false;

    await prefs.setString(conversationID!, jsonEncode(storedMessages));
    await _updateConversationLastMessageText(finalResponse);
    await _updateConversationLastMessageDate(DateTime.now());
  }

  Future<void> _sendMessage({
    String? textFromButton,
    bool isRegenerate = false,
    int? regenerateAiIndex,
    // Eğer orijinal kullanıcı mesajı yalnızca fotoğraf ise
    String? regeneratePhotoPath,
  }) async {
    final localizations = AppLocalizations.of(context)!;
    final String text = textFromButton ?? _controller.text.trim();

    // 1) Eğer bu bir regenerasyon isteği değilse ve kullanıcı hiçbir şey yazmamış + fotoğraf yoksa => çık.
    final hasNewPhoto = _selectedPhoto != null;
    if (!isRegenerate && text.isEmpty && !hasNewPhoto) {
      return;
    }

    // 2) Güncel kullanıcı verilerini getir ve server-side model kullanıyorsa kredi kontrolü yap.
    FocusScope.of(context).unfocus();
    await _fetchUserData(); // _credits vb. güncelleniyor

    if (isServerSideModel(modelId)) {
      bool hadPhoto = hasNewPhoto || (regeneratePhotoPath != null);
      int cost = otherServerSideModels.contains(modelId) ? 10 : 20;
      if (hadPhoto) {
        cost = 30; // örneğin, fotoğraf gönderimi daha pahalı
      }
      int totalUserCredits = _credits + _bonusCredits;
      if (totalUserCredits < cost) {
        final notificationService =
        Provider.of<NotificationService>(context, listen: false);
        final screenHeight = MediaQuery.of(context).size.height;
        notificationService.showNotification(
          message: localizations.notEnoughCredits,
          isSuccess: false,
          fontSize: 0.032,
          oneLine: false,
          bottomOffset: 0.08,
        );
        return; // Yetersiz kredi olduğundan gönderme iptal ediliyor.
      }
    }

    // 3) Fotoğraf seçimini işle
    DateTime now = DateTime.now();
    String? photoPath;
    if (_selectedPhoto != null) {
      setState(() {
        photoPath = _selectedPhoto!.path;
        _selectedPhoto = null;
      });
      // UI için küçük bir gecikme
      await Future.delayed(const Duration(milliseconds: 200));
    }
    if (isRegenerate && regeneratePhotoPath != null) {
      // Fotoğraf-only kullanıcı mesajı regenerasyonu için
      photoPath = regeneratePhotoPath;
    }

    // 4) Eğer mevcut konuşma yoksa (conversationID == null) yeni bir konuşma oluştur.
    if (!isRegenerate && conversationID == null) {
      if (isServerSideModel(modelId)) {
        if (_serverSideConversationsCount >= _serverSideConversationLimit) {
          final notificationService =
          Provider.of<NotificationService>(context, listen: false);
          notificationService.showNotification(
            message: localizations.youReachedConversationLimit,
            isSuccess: false,
            fontSize: 0.032,
          );
          return;
        } else {
          final User? user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            try {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .update({'conversations': FieldValue.increment(1)});
              setState(() {
                _serverSideConversationsCount += 1;
                _conversationLimitReached =
                    _serverSideConversationsCount >= _serverSideConversationLimit;
              });
            } catch (e) {
              print("Error incrementing conversation count: $e");
            }
          }
        }
      }

      conversationID = uuid.v4();
      conversationTitle =
      (text.trim().isEmpty && photoPath != null) ? "🖼" : (text.length > 28 ? text.substring(0, 28) : text);

      await _saveConversationTitle(conversationTitle!);
      await _saveConversation(conversationTitle!);
      mainScreenKey.currentState
          ?.menuScreenKey
          .currentState
          ?.reloadConversations();

      // Kullanıcının mesajını UI’ya ekle ve kaydet
      setState(() {
        messages.add(Message(
          text: text,
          isUserMessage: true,
          photoPath: photoPath,
          isPhotoUploading: true,
        ));
        _controller.clear();
        isWaitingForResponse = true;
        _isSendButtonVisible = false;
        responseStopped = false;
        _creditsDeducted = false;
      });
      await _scrollToBottom(forceScroll: true);
      await _saveMessageToConversation(text, true,
          isReported: false, photoPath: photoPath);
      await _updateConversationLastMessageText(text, photoPath: photoPath);
      await _updateConversationLastMessageDate(now);

      // AI placeholder mesajı (“düşünüyor”) ekle – bu mesaj henüz kaydedilmiyor.
      setState(() {
        messages.add(Message(
          text: isServerSideModel(modelId) ? localizations.thinking : '',
          isUserMessage: false,
        ));
      });
    }
    // 5) Regenerasyon isteğinde mevcut AI mesajını “düşünüyor” olarak ayarla.
    else if (isRegenerate && regenerateAiIndex != null) {
      setState(() {
        messages[regenerateAiIndex].text = localizations.thinking;
        isWaitingForResponse = true;
        _isSendButtonVisible = false;
        responseStopped = false;
        _creditsDeducted = false;
      });
    }
    // 6) Mevcut konuşmada kullanıcı yeni mesaj gönderiyorsa.
    else {
      setState(() {
        messages.add(Message(
          text: text,
          isUserMessage: true,
          photoPath: photoPath,
          isPhotoUploading: true,
        ));
        _controller.clear();
        isWaitingForResponse = true;
        _isSendButtonVisible = false;
        responseStopped = false;
        _creditsDeducted = false;
      });
      await _saveMessageToConversation(text, true,
          isReported: false, photoPath: photoPath);
      await _updateConversationLastMessageText(text, photoPath: photoPath);
      await _updateConversationLastMessageDate(now);
      setState(() {
        messages.add(Message(
          text: isServerSideModel(modelId) ? localizations.thinking : '',
          isUserMessage: false,
        ));
      });
    }

    // Kullanıcının ekranda en altta olup olmadığı takip ediliyor.
    bool autoScrollOnResponse = _isUserAtBottom();

    // 7) Mesajı modele gönder: yerel model ya da server-side model.
    try {
      // 7a) Yerel (cihaz içi) model ise:
      if (!isServerSideModel(modelId)) {
        llamaChannel.invokeMethod('sendMessage', {
          'message': text,
          'photoPath': photoPath,
        });
        _startResponseTimeout();
      }
      // 7b) Server-side model ise; streaming chunk’lar ile.
      else {
        final memory = _buildMemory();
        bool hasReceivedFirstChunk = false;
        final partialBuffer = StringBuffer();
        Timer? chunkTimer;

        chunkTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
          if (!mounted || responseStopped) return;
          if (partialBuffer.isNotEmpty) {
            // İlk chunk’da placeholder (“düşünüyor”) temizleniyor.
            if (!hasReceivedFirstChunk) {
              if (isRegenerate && regenerateAiIndex != null) {
                setState(() {
                  messages[regenerateAiIndex].text = '';
                });
              } else {
                setState(() {
                  messages.last.text = '';
                });
              }
              hasReceivedFirstChunk = true;
            }
            setState(() {
              if (isRegenerate && regenerateAiIndex != null) {
                messages[regenerateAiIndex].text += partialBuffer.toString();
              } else {
                messages.last.text += partialBuffer.toString();
              }
              partialBuffer.clear();
            });
            if (autoScrollOnResponse) {
              _scrollToBottom(forceScroll: true);
            }
          }
        });

        String finalResponse = '';
        switch (modelId) {
          case 'gemini':
            finalResponse = await apiService.getGeminiResponse(
              text,
              memory,
              photoPath: photoPath,
              onStreamChunk: (chunk) => partialBuffer.write(chunk),
            );
            break;
          case 'llama':
            finalResponse = await apiService.getLlamaResponse(
              text,
              memory,
              photoPath: photoPath,
              onStreamChunk: (chunk) => partialBuffer.write(chunk),
            );
            break;
          default:
            finalResponse = await apiService.getCharacterResponse(
              role: role ?? '',
              userInput: text,
              context: memory,
              photoPath: photoPath,
              onStreamChunk: (chunk) => partialBuffer.write(chunk),
            );
        }

        chunkTimer.cancel();

        // Kalan partial chunk verisi ekleniyor.
        if (partialBuffer.isNotEmpty) {
          if (!hasReceivedFirstChunk) {
            setState(() {
              if (isRegenerate && regenerateAiIndex != null) {
                messages[regenerateAiIndex].text = '';
              } else {
                messages.last.text = '';
              }
            });
            hasReceivedFirstChunk = true;
          }
          setState(() {
            if (isRegenerate && regenerateAiIndex != null) {
              messages[regenerateAiIndex].text += partialBuffer.toString();
            } else {
              messages.last.text += partialBuffer.toString();
            }
            partialBuffer.clear();
          });
        }

        setState(() {
          isWaitingForResponse = false;
          _isSendButtonVisible = _controller.text.isNotEmpty;
        });

        // Regenerasyon durumu:
        if (isRegenerate && regenerateAiIndex != null) {
          if (messages[regenerateAiIndex].text.isEmpty) {
            messages[regenerateAiIndex].text = finalResponse;
          }
          // Eğer mesaj hâlâ “düşünüyor” ise (placeholder) kaydetme.
          if (messages[regenerateAiIndex].text != localizations.thinking) {
            await _saveRegeneratedMessageToConversation(
              finalResponse: messages[regenerateAiIndex].text,
              aiIndex: regenerateAiIndex,
            );
          }
        }
        // Normal yeni AI mesajı durumu:
        else {
          if (messages.isNotEmpty && !messages.last.isUserMessage) {
            if (messages.last.text.isEmpty) {
              messages.last.text = finalResponse;
            }
            if (messages.last.text != localizations.thinking) {
              await _saveMessageToConversation(
                messages.last.text,
                false,
                isReported: false,
              );
              await _updateConversationLastMessageText(
                messages.last.text,
                photoPath: messages.last.photoPath,
              );
              await _updateConversationLastMessageDate(DateTime.now());
            }
          }
        }

        // Server-side kullanımında kredi düşümü gerçekleştiriliyor.
        await _deductCredits(hadPhoto: photoPath != null);
      }
    } catch (e) {
      setState(() {
        isWaitingForResponse = false;
        if (isRegenerate && regenerateAiIndex != null) {
          messages[regenerateAiIndex].text = 'Error: $e';
        } else {
          if (messages.isNotEmpty && !messages.last.isUserMessage) {
            messages.last.text = 'Error: $e';
          } else {
            messages.add(Message(text: 'Error: $e', isUserMessage: false));
          }
        }
      });
    }
  }

  Future<void> _stopResponse() async {
    final localizations = AppLocalizations.of(context)!;

    // Eğer zaten durdurulmuşsa, çık.
    if (responseStopped) return;

    // Streaming isteğini iptal et
    apiService.cancelRequests();

    // Server-side model kullanılıyorsa, henüz düşüm yapılmadıysa kredileri düş
    if (isServerSideModel(modelId)) {
      await _deductCredits(hadPhoto: false);
    }

    if (isWaitingForResponse) {
      setState(() {
        responseStopped = true;
        isWaitingForResponse = false;
        _isSendButtonVisible = _controller.text.isNotEmpty;
      });
      responseTimer?.cancel();

      // Son AI mesajı boş veya "düşünüyor" ise fade-out tetikleyelim.
      if (messages.isNotEmpty) {
        final int lastAiIndex = messages.lastIndexWhere((m) => !m.isUserMessage);
        if (lastAiIndex != -1) {
          final msg = messages[lastAiIndex];
          final lastText = msg.text.trim();
          if (lastText.isEmpty || lastText == localizations.thinking) {
            // Mesajın shouldFadeOut alanını true yapıp, AIMessageTile'dan
            // onFadeOutComplete callback’i bekleyelim.
            setState(() {
              msg.shouldFadeOut = true;
            });
            // Not: Mesajı burada remove etmiyoruz, onun widget’ı
            // fade-out animasyonu tamamlandığında onFadeOutComplete tetiklenecek.
          }
        }
      }
    } else {
      // Eğer response beklenmiyorsa sadece durdur.
      setState(() {
        isWaitingForResponse = false;
        _isSendButtonVisible = _controller.text.isNotEmpty;
      });
      responseTimer?.cancel();
    }
  }

  Future<void> _deductCredits({bool hadPhoto = false}) async {
    // Sunucu tarafı bir model kullanıyorsak ve henüz düşüm yapılmadıysa:
    if (isServerSideModel(modelId) && !_creditsDeducted) {
      // Her modele göre farklı cost
      int deduction;
      if (otherServerSideModels.contains(modelId)) {
        deduction = 10;
      } else {
        deduction = hadPhoto ? 30 : 20;
      }

      int remainingDeduction = deduction;

      // Önce bonusCredits'ten düş
      int updatedBonus = _bonusCredits;
      int updatedCredits = _credits;

      if (updatedBonus >= remainingDeduction) {
        updatedBonus -= remainingDeduction;
        remainingDeduction = 0;
      } else {
        remainingDeduction -= updatedBonus;
        updatedBonus = 0;
      }

      // Hâlâ varsa, normal credits’ten devam et
      if (remainingDeduction > 0) {
        updatedCredits -= remainingDeduction;
        if (updatedCredits < 0) {
          updatedCredits = 0; // negatif olmasın
        }
      }

      // Firestore’a yaz
      await _updateCreditsOnFirebase(
        newCredits: updatedCredits,
        newBonusCredits: updatedBonus,
      );

      _creditsDeducted = true;
    }
  }

  void markMessageAsReported(String aiMessage) {
    final index = messages.indexWhere((m) => !m.isUserMessage && m.text == aiMessage);
    if (index == -1) return;
    setState(() {
      messages[index].isReported = true;
    });
    _updateStoredMessage(messages[index], index);
  }

  bool _isMessageAppropriate(String text) {
    List<String> inappropriateWords = [
      'seks', 'sikiş', 'porno', 'yarak', 'pussy', 'yarrak',
      'salak','aptal','orospu','göt','intihar','ölmek',
      'çocuk pornosu','sex','amk','motherfucker','fuck',
      'porn','child porn','suicide','sik','siksem','sikmek','sakso','blowjob','handjob','asshole'
    ];
    final lowerText = text.toLowerCase();
    for (var word in inappropriateWords) {
      final pattern = RegExp(r'\b' + RegExp.escape(word) + r'\b');
      if (pattern.hasMatch(lowerText)) {
        setState(() {
          _showInappropriateMessageWarning = true;
        });
        _warningAnimationController.forward();
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            _warningAnimationController.reverse();
          }
        });
        return false;
      }
    }
    return true;
  }

  Future<bool> _onWillPop() async {
    if (isWaitingForResponse) {
      await _stopResponse();
    }

    // Menüden geldiysek:
    if (_openedFromMenu) {
      // Konuşma sıfırlansın ki ID temizlensin
      await resetConversation();
      // Ekranı kapatıp tekrar menüye dön
      mainScreenKey.currentState?.onItemTapped(2);
      return false;
    }
    // Model seçiliyse (yeni bir sohbete başlamışsak ama yine back tuşuna basmışsak):
    else if (isModelSelected) {
      // Konuşmayı sıfırlıyoruz
      await resetConversation();
      setState(() {
        // Model verisini de temizleyebilirsiniz.
        isModelSelected = false;
        modelTitle = null;
        modelDescription = null;
        modelImagePath = null;
        modelProducer = null;
        modelPath = null;
        role = null;
        isModelLoaded = false;
      });
      mainScreenKey.currentState?.updateBottomAppBarVisibility(true);
      return false;
    }

    // Aksi halde pop normal şekilde devam etsin
    return true;
  }

  void _hideNotification() {
    if (_showInappropriateMessageWarning || _showLimitReachedWarning) {
      _warningAnimationController.reverse();
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        setState(() {
          _selectedPhoto = File(pickedFile.path);
          _showPhotoContent = false; // İlk başta içerik görünmesin.
        });
        // Panelin açılma animasyonu süresi kadar (300 ms) bekleyip,
        // fotoğrafın fade-in ile görünmesini tetikliyoruz.
        Future.delayed(const Duration(milliseconds: 300), () {
          if (_selectedPhoto != null) {
            setState(() {
              _showPhotoContent = true;
            });
          }
        });
        setState(() {
          _isSendButtonVisible = true;
        });
      }
    } catch (e) {
      print("Fotoğraf seçilirken hata oluştu: $e");
    }
  }

  void _removeSelectedPhoto() {
    setState(() {
      _showPhotoContent = false;
    });
    // Eğer panelin kapanma animasyonunda AnimatedSwitcher'ın fade-out
    // efekti ile kaybolmasını isterseniz bir miktar gecikme ekleyebilirsiniz.
    Future.delayed(const Duration(milliseconds: 300), () {
      setState(() {
        _selectedPhoto = null;
      });
    });
  }

  Widget _buildActionButton(bool isDarkTheme) {
    final screenWidth = MediaQuery.of(context).size.width;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 100),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return ScaleTransition(scale: animation, child: child);
      },
      child: _isSending
          ? GestureDetector(
        key: const ValueKey('sendButtonOpacity'),
        onTap: null,
        child: Opacity(
          opacity: 0.5,
          child: Container(
            width: screenWidth * 0.09,
            height: screenWidth * 0.09,
            decoration: BoxDecoration(
              color: isDarkTheme ? Colors.white : Colors.black,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.arrow_upward,
              color: isDarkTheme ? Colors.black : Colors.white,
              size: screenWidth * 0.06,
            ),
          ),
        ),
      )
          : isWaitingForResponse
          ? GestureDetector(
        key: const ValueKey('stopButton'),
        onTap: _stopResponse,
        child: Container(
          width: screenWidth * 0.09,
          height: screenWidth * 0.09,
          decoration: BoxDecoration(
            color: isDarkTheme ? Colors.white : Colors.black,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            Icons.stop,
            color: isDarkTheme ? Colors.black : Colors.white,
            size: screenWidth * 0.06,
          ),
        ),
      )
          : (!_isInputEmpty || _selectedPhoto != null)
          ? GestureDetector(
        key: const ValueKey('sendButton'),
        onTap: _isSendButtonEnabled ? _sendMessage : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: screenWidth * 0.09,
          height: screenWidth * 0.09,
          decoration: BoxDecoration(
            color: _isSendButtonEnabled
                ? (isDarkTheme ? Colors.white : Colors.black)
                : (isDarkTheme
                ? Colors.white.withOpacity(0.5)
                : Colors.black.withOpacity(0.5)),
            borderRadius: BorderRadius.circular(
                _isSendButtonEnabled ? 20 : 17),
          ),
          child: Icon(
            Icons.arrow_upward,
            color: isDarkTheme ? Colors.black : Colors.white,
            size: screenWidth * 0.06,
          ),
        ),
      )
          : const SizedBox.shrink(),
    );
  }

  bool get _isInputEmpty => _controller.text.trim().isEmpty;

  bool get _isSendButtonEnabled {
    if (_isSending) return false;
    if (isWaitingForResponse) return false;
    if (_isInputEmpty && _selectedPhoto == null) return false;
    if (isServerSideModel(modelId) && !hasInternetConnection) return false;
    if (!isStorageSufficient) return false;

    return true;
  }

  void _onTextChanged(String text) {
    setState(() {
      _isSendButtonVisible = text.isNotEmpty || _selectedPhoto != null;
    });
  }

  int _getInputLineCount(String text, double maxWidth) {
    // Kullanılacak metin stili; TextField’da kullanılan fontSize vs. burada tanımlanmalı.
    final textStyle = const TextStyle(fontSize: 16);
    final textSpan = TextSpan(text: text, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      maxLines: null, // Sınırsız sayıda satır hesaplanabilsin.
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: maxWidth);
    return textPainter.computeLineMetrics().length;
  }

  Widget _buildInputField(AppLocalizations localizations, bool isDarkTheme) {
    // Henüz model seçilmediyse hiçbir şey göstermiyoruz.
    if (!isModelSelected) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Padding(
      // Genel padding ayarları
      padding: EdgeInsets.fromLTRB(
        screenWidth * 0.02,
        0.0,
        screenWidth * 0.02,
        screenHeight * 0.005, // Alt boşluk azaltıldı.
      ),
      child: Container(
        decoration: BoxDecoration(
          color: isDarkTheme ? const Color(0xFF161616) : Colors.grey[300],
          borderRadius: BorderRadius.circular(25),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Fotoğraf paneli (AnimatedSize + AnimatedSwitcher ile geçişli)
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: _selectedPhoto != null
                    ? Padding(
                  key: const ValueKey('photoPanel'),
                  padding: EdgeInsets.all(screenWidth * 0.03),
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8.0),
                          child: Image.file(
                            _selectedPhoto!,
                            width: screenWidth * 0.25,
                            height: screenWidth * 0.25,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _removeSelectedPhoto,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black87,
                              shape: BoxShape.circle,
                            ),
                            padding: EdgeInsets.all(screenWidth * 0.01),
                            child: Icon(
                              Icons.close,
                              size: screenWidth * 0.045,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
                    : const SizedBox.shrink(),
              ),
            ),
            // Metin girişi ve aksiyon butonlarının bulunduğu alan.
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: screenWidth * 0.03,
                vertical: screenHeight * 0.001,
              ),
              child: Stack(
                children: [
                  Row(
                    children: [
                      if (canHandleImage) ...[
                        GestureDetector(
                          onTap: _selectedPhoto == null && !_isPhotoLoading
                              ? _pickPhoto
                              : null,
                          child: Opacity(
                            opacity:
                            _selectedPhoto == null && !_isPhotoLoading ? 1.0 : 0.5,
                            child: Icon(
                              Icons.add,
                              color: isDarkTheme ? Colors.white : Colors.black,
                              size: screenWidth * 0.06,
                            ),
                          ),
                        ),
                        SizedBox(width: screenWidth * 0.02),
                      ],
                      // Metin girişi
                      Expanded(
                        child: TextField(
                          cursorColor: isDarkTheme ? Colors.white : Colors.black,
                          controller: _controller,
                          maxLength: 4000,
                          minLines: 1,
                          maxLines: 6,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          decoration: InputDecoration(
                            hintText: localizations.messageHint,
                            hintStyle: TextStyle(
                              color: isDarkTheme ? Colors.grey[500] : Colors.grey[600],
                              fontSize: screenWidth * 0.04,
                            ),
                            border: InputBorder.none,
                            counterText: '',
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: TextStyle(
                            color: isDarkTheme ? Colors.white : Colors.black,
                            fontSize: screenWidth * 0.04,
                          ),
                          onChanged: _onTextChanged,
                          onSubmitted: (text) {
                            if (_isSendButtonEnabled) _sendMessage();
                          },
                        ),
                      ),
                      SizedBox(width: screenWidth * 0.02),
                      _buildActionButton(isDarkTheme),
                    ],
                  ),
                  Positioned(
                    top: screenHeight * 0.01,
                    right: screenWidth * 0.03,
                    child: IgnorePointer(
                      ignoring: _getInputLineCount(
                        _controller.text,
                        screenWidth - (screenWidth * 0.04),
                      ) <=
                          2,
                      child: AnimatedOpacity(
                        opacity: _getInputLineCount(
                          _controller.text,
                          screenWidth - (screenWidth * 0.04),
                        ) >
                            2
                            ? 1.0
                            : 0.0,
                        duration: const Duration(milliseconds: 100),
                        child: GestureDetector(
                          onTap: _expandInputField,
                          child: SvgPicture.asset(
                            'assets/expand.svg',
                            width: screenWidth * 0.04,
                            height: screenWidth * 0.036,
                            color: isDarkTheme ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _expandInputField() async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, animation, secondaryAnimation) {
          return ExpandedInputScreen(
            initialText: _controller.text,
            isDarkTheme: Provider.of<ThemeProvider>(context, listen: false).isDarkTheme,
            controller: _controller,
            onShrink: (updatedText) {
              setState(() {
                _controller.text = updatedText;
              });
            },
            onSend: () {
              _sendMessage();
            },
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: animation,
              child: child,
            ),
          );
        },
      ),
    );
  }


  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    responseTimer?.cancel();
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _warningAnimationController.dispose();
    _searchAnimationController.dispose();
    llamaChannel.setMethodCallHandler(null);
    _internetSubscription.cancel();
    _textFieldFocusNode.dispose();
    _showScrollDownButton = false;
    _isProcessingChunks = false;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Reload model list so the “downloading” item updates
      _loadModels();
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final isDarkTheme = Provider.of<ThemeProvider>(context).isDarkTheme;
    final screenHeight = MediaQuery.of(context).size.height;

    if (_shouldHideImmediately) {
      return Container();
    }

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        // BU SATIRI EKLEYİN:
        extendBody: true,
        appBar: _buildAppBar(context, localizations, isDarkTheme),
        body: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                FocusScope.of(context).unfocus();
              },
              child: Container(
                color: isDarkTheme ? const Color(0xFF090909) : Colors.white,
                child: Column(
                  children: [
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 125),
                        transitionBuilder: (Widget child, Animation<double> animation) {
                          return FadeTransition(opacity: animation, child: child);
                        },
                        child: isModelSelected
                            ? _buildChatScreen(localizations, isDarkTheme)
                            : _buildModelSelectionScreen(localizations, isDarkTheme),
                      ),
                    ),
                    _buildInputField(localizations, isDarkTheme),
                  ],
                ),
              ),
            ),
            if (_showInappropriateMessageWarning || _showLimitReachedWarning)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _hideNotification,
                ),
              ),
            if (_showInappropriateMessageWarning || _showLimitReachedWarning)
              Positioned(
                bottom: _inputFieldHeight + 12,
                left: 16,
                right: 16,
                child: SlideTransition(
                  position: _warningSlideAnimation,
                  child: FadeTransition(
                    opacity: _warningFadeAnimation,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12.0, horizontal: 20.0),
                      decoration: BoxDecoration(
                        color: isDarkTheme ? Colors.red[700]! : Colors.red,
                        borderRadius: BorderRadius.circular(8.0),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 12.0),
                          Expanded(
                            child: Text(
                              _showInappropriateMessageWarning
                                  ? localizations.inappropriateMessageWarning
                                  : _currentWarningMessage,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        floatingActionButton: AnimatedOpacity(
          opacity: _showScrollDownButton ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 150),
          child: IgnorePointer(
            ignoring: !_showScrollDownButton,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: _inputFieldHeight + screenHeight * 0.06,
              ),
              // Use a SizedBox to define custom width/height:
              child: SizedBox(
                width: 40,   // Customize size
                height: 40,  // Customize size
                child: FloatingActionButton(
                  // Use a custom shape and border radius:
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22), // Customize radius
                  ),
                  elevation: 2.0,
                  backgroundColor: isDarkTheme ? const Color(0xFF212121) : Colors.black,
                  onPressed: () => _scrollToBottom(forceScroll: true),
                  child: Icon(
                    Icons.arrow_downward,
                    color: isDarkTheme ? Colors.white : Colors.white,
                    size: 20, // Customize icon size
                  ),
                ),
              ),
            ),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }

  Widget _buildModelSelectionScreen(AppLocalizations localizations, bool isDarkTheme) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Stack(
        children: [
          AnimatedOpacity(
            opacity: _modelsLoaded ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: _modelsLoaded
                ? _buildModelGrid(localizations, isDarkTheme)
                : const SizedBox.shrink(),
          ),
          AnimatedOpacity(
            opacity: !_modelsLoaded ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 250),
            child: IgnorePointer(
              ignoring: _modelsLoaded,
              child: _buildSkeletonModelGrid(isDarkTheme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelGrid(AppLocalizations localizations, bool isDarkTheme) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final notificationService =
    Provider.of<NotificationService>(context, listen: false);

    return _allModels.isNotEmpty
        ? Column(
      children: [
        Padding(
          padding: EdgeInsets.all(screenWidth * 0.02),
          child: _buildSearchBar(localizations, isDarkTheme),
        ),
        Expanded(
          child: _filteredModels.isNotEmpty
              ? GridView.builder(
            padding: EdgeInsets.all(screenWidth * 0.02),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: screenWidth * 0.02,
              mainAxisSpacing: screenWidth * 0.02,
              childAspectRatio: 0.75,
            ),
            itemCount: _filteredModels.length,
            physics: const AlwaysScrollableScrollPhysics(),
            itemBuilder: (context, index) {
              final model = _filteredModels[index];
              bool isServerSide = isServerSideModel(model.id);

              // Updated isDisabled condition: applies only to server-side models
              bool isDisabled = isServerSide &&
                  (_conversationLimitReached ||
                      !hasInternetConnection);

              return GestureDetector(
                onTap: () {
                  if (isDisabled) {
                    // Show warning only for server-side models when disabled
                    notificationService.showNotification(
                      message: localizations
                          .youReachedConversationLimit, // Ensure this string exists in your localization files
                      isSuccess: false,
                      fontSize: 0.032,
                    );
                  } else {
                    _selectModel(model);
                    _scrollToBottom(forceScroll: true);
                  }
                },
                child: Opacity(
                  // Apply opacity only if the server-side model is disabled
                  opacity: isServerSide && isDisabled ? 0.5 : 1.0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDarkTheme
                          ? const Color(0xFF1B1B1B)
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(2, 2),
                        ),
                      ],
                      border: Border.all(
                          color: isDarkTheme
                              ? Colors.grey[700]!
                              : Colors.grey[300]!),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Padding(
                          padding: EdgeInsets.all(screenWidth * 0.02),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8.0),
                            child: Image.asset(
                              model.imagePath,
                              height: screenHeight * 0.1,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        SizedBox(height: screenHeight * 0.01),
                        Text(
                          model.title,
                          style: TextStyle(
                            color: isDarkTheme
                                ? Colors.white
                                : Colors.black,
                            fontSize: screenWidth * 0.035,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: screenHeight * 0.005),
                        Text(
                          model.producer,
                          style: TextStyle(
                            color: isDarkTheme
                                ? Colors.grey[400]
                                : Colors.grey[600],
                            fontSize: screenWidth * 0.03,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          )
              : Center(
            child: Text(
              localizations.noMatchingModels,
              style: TextStyle(
                color:
                isDarkTheme ? Colors.white70 : Colors.black54,
                fontSize: screenWidth * 0.04,
              ),
            ),
          ),
        ),
      ],
    )
        : Center(
      child: Text(
        localizations.noModelsDownloaded,
        style: TextStyle(
          color: isDarkTheme ? Colors.white70 : Colors.black54,
          fontSize: screenWidth * 0.04,
        ),
      ),
    );
  }

  Widget _buildSkeletonModelGrid(bool isDarkTheme) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(screenWidth * 0.02),
          child: Shimmer.fromColors(
            baseColor: isDarkTheme ? Colors.grey[800]! : Colors.grey[300]!,
            highlightColor:
            isDarkTheme ? Colors.grey[700]! : Colors.grey[100]!,
            child: Container(
              height: screenHeight * 0.06,
              decoration: BoxDecoration(
                color: isDarkTheme ? Colors.grey[800] : Colors.grey[300],
                borderRadius: BorderRadius.circular(12.0),
              ),
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: EdgeInsets.all(screenWidth * 0.01),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: screenWidth * 0.02,
              mainAxisSpacing: screenWidth * 0.02,
              childAspectRatio: 0.75,
            ),
            itemCount: 12,
            itemBuilder: (context, index) {
              return Shimmer.fromColors(
                baseColor:
                isDarkTheme ? Colors.grey[800]! : Colors.grey[300]!,
                highlightColor:
                isDarkTheme ? Colors.grey[700]! : Colors.grey[100]!,
                child: Container(
                  decoration: BoxDecoration(
                    color: isDarkTheme ? Colors.grey[800] : Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showInternetRequiredNotification() {
    final localizations = AppLocalizations.of(context)!;
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final isDarkTheme = themeProvider.isDarkTheme;
    final notificationService =
    Provider.of<NotificationService>(context, listen: false);

    notificationService.showNotification(
      message: localizations.internetRequired,
      isSuccess: false,
      fontSize: 0.032,
      duration: const Duration(seconds: 2),
    );
  }

  AppBar _buildAppBar(BuildContext context, AppLocalizations localizations, bool isDarkTheme) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return AppBar(
      toolbarHeight: screenHeight * 0.08,
      backgroundColor: isDarkTheme ? const Color(0xFF090909) : Colors.white,
      centerTitle: true,
      scrolledUnderElevation: 0,
      leading: isModelSelected
          ? IconButton(
        icon: Icon(
          Icons.arrow_back,
          color: isDarkTheme ? Colors.white : Colors.black,
          size: screenWidth * 0.06,
        ),
        onPressed: () async {
          if (isWaitingForResponse) {
            await _stopResponse();
          }
          if (_openedFromMenu) {
            setState(() {
              _shouldHideImmediately = true;
            });
            mainScreenKey.currentState?.onItemTapped(2);
            mainScreenKey.currentState?.updateBottomAppBarVisibility(true);
            return;
          } else {
            mainScreenKey.currentState?.updateBottomAppBarVisibility(true);
            await resetConversation();
            setState(() {
              isModelSelected = false;
              modelTitle = null;
              modelDescription = null;
              modelImagePath = null;
              modelProducer = null;
              modelPath = null;
              role = null;
              isModelLoaded = false;
            });
          }
        },
      )
          : _buildCreditsHexagonRow(isDarkTheme),
      title: isModelSelected
          ? FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          modelTitle ?? '',
          style: GoogleFonts.poppins(
            fontSize: screenWidth * 0.055,
            color: isDarkTheme ? Colors.white : Colors.black,
            fontWeight: FontWeight.w500,
          ),
        ),
      )
          : Text(
        localizations.appTitle,
        style: GoogleFonts.play(
          color: isDarkTheme ? Colors.white : Colors.black,
          fontSize: screenWidth * 0.08,
        ),
      ),
      actions: <Widget>[
        GestureDetector(
          onTap: () => _navigateToScreen(
            context,
            const AccountScreen(),
            direction: const Offset(1.0, 0.0),
          ),
          child: Transform.translate(
            offset: Offset(-screenWidth * 0.02, screenHeight * 0.0015),
            child: CircleAvatar(
              radius: screenWidth * 0.05,
              backgroundColor: isDarkTheme ? Colors.grey[800] : Colors.grey[300],
              child: Text(
                _userData != null &&
                    _userData!['username'] != null &&
                    (_userData!['username'] as String).isNotEmpty
                    ? (_userData!['username'] as String)[0].toUpperCase()
                    : (FirebaseAuth.instance.currentUser?.email?.isNotEmpty ?? false)
                    ? FirebaseAuth.instance.currentUser!.email![0].toUpperCase()
                    : '?',
                style: TextStyle(
                  fontSize: screenWidth * 0.045,
                  color: isDarkTheme ? Colors.white : Colors.black,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCreditsHexagonRow(bool isDarkTheme) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Toplam kredi = satın alınan + bonus
    int totalCredits = _credits + _bonusCredits;

    return Padding(
      padding: EdgeInsets.only(top: screenHeight * 0.005),
      child: SizedBox(
        width: screenWidth * 0.37,
        height: screenHeight * 0.1,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topLeft,
          children: [
            Positioned(
              top: screenHeight * 0.0129,
              left: screenWidth * 0.05,
              child: Container(
                width: screenWidth * 0.26,
                height: screenHeight * 0.045,
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.016,
                  vertical: screenHeight * 0.005,
                ),
                decoration: BoxDecoration(
                  color: isDarkTheme
                      ? const Color(0xFF181818)
                      : Colors.grey[300],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDarkTheme ? Colors.white : Colors.black,
                    width: 0.5,
                  ),
                ),
                child: Row(
                  children: [
                    const Spacer(),
                    Container(
                      padding: EdgeInsets.all(screenWidth * 0.01),
                      decoration: BoxDecoration(
                        color: isDarkTheme
                            ? const Color(0xFF181818)
                            : Colors.grey[300],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: SvgPicture.asset(
                        'assets/credit.svg',
                        width: screenWidth * 0.05,
                        height: screenWidth * 0.05,
                        color: isDarkTheme ? Colors.white : Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // -------------------------------
            Positioned(
              top: screenHeight * 0.0129,
              left: screenWidth * 0.02,
              child: _buildHexagonButton(isDarkTheme),
            ),
            Positioned(
              top: screenHeight * 0.0129,
              left: screenWidth * 0.115,
              // Our “invisible square” is 0.12 wide, matching the bar’s height
              child: Container(
                width: screenWidth * 0.12,
                height: screenHeight * 0.045,
                // center horizontally + FittedBox ensures variable-length text
                child: Center(
                  child: FittedBox(
                    child: Text(
                      '$totalCredits',
                      style: TextStyle(
                        fontSize: screenWidth * 0.04,
                        fontWeight: FontWeight.bold,
                        color: isDarkTheme ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHexagonButton(bool isDarkTheme) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return ClipPath(
      clipper: HexagonClipper(),
      child: SizedBox(
        width: screenWidth * 0.1,
        height: screenHeight * 0.045,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              _showComingSoonMessage();
            },
            child: CustomPaint(
              painter: HexagonBorderPainter(
                fillColor: isDarkTheme ? Colors.grey[900]! : Colors.grey[300]!,
                borderColor: isDarkTheme ? Colors.white : Colors.black,
                strokeWidth: 1.5,
              ),
              child: Padding(
                padding: EdgeInsets.all(screenWidth * 0.02),
                child: SvgPicture.asset(
                  'assets/sparkle.svg',
                  color: isDarkTheme ? Colors.white : Colors.black,
                  width: screenWidth * 0.05,
                  height: screenWidth * 0.05,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showComingSoonMessage() {
    final notificationService =
    Provider.of<NotificationService>(context, listen: false);

    notificationService.showNotification(
      message: AppLocalizations.of(context)!.comingSoon,
      bottomOffset: 0.1,
      fontSize: 0.038,
      duration: Duration(seconds: 2),
    );
  }

  void _navigateToScreen(BuildContext context, Widget screen, {required Offset direction}) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => screen,
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          final end = Offset.zero;
          final curve = Curves.ease;
          final tween = Tween(begin: direction, end: end)
              .chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  Widget _buildChatScreen(AppLocalizations localizations, bool isDarkTheme) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (modelImagePath != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(15.0),
                      child: Image.asset(
                        modelImagePath!,
                        height: screenWidth * 0.25,
                        width: screenWidth * 0.25,
                        fit: BoxFit.contain,
                      ),
                    ),
                  SizedBox(height: screenHeight * 0.02),
                  if (modelTitle != null)
                    Text(
                      modelTitle!,
                      style: GoogleFonts.poppins(
                        fontSize: screenWidth * 0.05,
                        color: isDarkTheme ? Colors.white : Colors.black,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  SizedBox(height: screenHeight * 0.02),
                ],
              ),
            ),
          )
              : _buildMessagesList(isDarkTheme),
        ),
      ],
    );
  }

  Widget _buildMessagesList(bool isDarkTheme) {
    final screenHeight = MediaQuery.of(context).size.height;

    return ListView.separated(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(vertical: screenHeight * 0.01),
      itemCount: messages.length,
      separatorBuilder: (context, index) {
        return SizedBox(height: screenHeight * 0.005);
      },
      itemBuilder: (context, index) {
        return _buildMessageTile(messages[index], index, isDarkTheme);
      },
    );
  }

  Widget _buildMessageTile(Message message, int index, bool isDarkTheme) {
    return message.isUserMessage
        ? _buildUserMessageTile(message, index, isDarkTheme)
        : _buildAIMessageTile(message, index, isDarkTheme);
  }

  Widget _buildUserMessageTile(Message message, int index, bool isDarkTheme) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final key = ValueKey<Message>(message);
    List<Widget> children = [];

    // Fotoğraf varsa -> Shimmer + Fade animasyonu
    if (message.photoPath != null) {
      children.add(
        Padding(
          padding: EdgeInsets.only(
            right: screenWidth * 0.04,
            bottom: screenHeight * 0.006,
          ),
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                PhotoViewer.route(File(message.photoPath!)),
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8.0),
              child: Image.file(
                File(message.photoPath!),
                frameBuilder: (BuildContext ctx, Widget child, int? frame, bool wasSyncLoaded) {
                  if (frame == null) {
                    // Henüz decode edilmedi -> Shimmer
                    return Shimmer.fromColors(
                      baseColor: isDarkTheme ? Colors.grey[800]! : Colors.grey[300]!,
                      highlightColor: isDarkTheme ? Colors.grey[700]! : Colors.grey[100]!,
                      child: Container(
                        width: screenWidth * 0.4,
                        height: screenWidth * 0.4,
                        color: Colors.white,
                      ),
                    );
                  } else {
                    // Decode geldi -> Fade animasyonu
                    return AnimatedOpacity(
                      opacity: 1.0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                      child: child,
                    );
                  }
                },
                width: screenWidth * 0.4,
                height: screenWidth * 0.4,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      );
    }

    // Metin varsa
    if (message.text.trim().isNotEmpty) {
      children.add(
        UserMessageTile(
          key: key,
          text: message.text,
          isDarkTheme: isDarkTheme,
          shouldFadeOut: message.shouldFadeOut,
          onFadeOutComplete: () {
            setState(() {
              messages.remove(message);
            });
            _fadeOutCount++;
          },
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: children,
    );
  }

  Widget _buildAIMessageTile(Message message, int index, bool isDarkTheme) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final key = ValueKey<Message>(message);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message.photoPath != null)
          Padding(
            padding: EdgeInsets.only(
              left: screenWidth * 0.04,
              bottom: screenHeight * 0.006,
            ),
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  PhotoViewer.route(File(message.photoPath!)),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: Image.file(
                  File(message.photoPath!),
                  width: screenWidth * 0.4,
                  height: screenWidth * 0.4,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        AIMessageTile(
          key: key,
          text: message.text,
          imagePath: modelImagePath ?? '',
          isDarkTheme: isDarkTheme,
          shouldFadeOut: message.shouldFadeOut,
          modelId: modelId ?? '',
          isReported: message.isReported,
          onReport: () async {
            setState(() {
              message.isReported = true;
            });
            await _updateStoredMessage(message, index);
          },
          onRegenerate: () => _onRegenerate(index),
          onFadeOutComplete: () async {
            setState(() {
              messages.removeAt(index);
            });
            if (conversationID != null) {
              final prefs = await SharedPreferences.getInstance();
              final messagesJson = prefs.getString(conversationID!);
              if (messagesJson != null) {
                final List<dynamic> storedMessages = jsonDecode(messagesJson);
                if (index < storedMessages.length) {
                  storedMessages.removeAt(index);
                  await prefs.setString(conversationID!, jsonEncode(storedMessages));
                }
              }
            }
          },
          parsedSpans: message.parsedSpans,
        ),
      ],
    );
  }

  Future<void> _updateStoredMessage(Message message, int index) async {
    if (conversationID == null) return;
    final prefs = await SharedPreferences.getInstance();
    final String? messagesJson = prefs.getString(conversationID!);
    if (messagesJson == null) return;

    List<dynamic> storedMessages;
    try {
      storedMessages = jsonDecode(messagesJson);
    } catch (e) {
      print("JSON parse error: $e");
      return;
    }
    if (index < 0 || index >= storedMessages.length) {
      return;
    }
    storedMessages[index]["isReported"] = true;
    await prefs.setString(conversationID!, jsonEncode(storedMessages));
  }

  Widget _buildSearchBar(AppLocalizations localizations, bool isDarkTheme) {
    final screenWidth = MediaQuery.of(context).size.width;

    return TextField(
      cursorColor: isDarkTheme ? Colors.white : Colors.black,
      decoration: InputDecoration(
        hintText: localizations.searchHint,
        hintStyle: TextStyle(
          color: isDarkTheme ? Colors.grey[400] : Colors.grey[600],
          fontSize: screenWidth * 0.04,
        ),
        prefixIcon: Icon(
          Icons.search,
          color: isDarkTheme ? Colors.white : Colors.black,
          size: screenWidth * 0.06,
        ),
        filled: true,
        fillColor: isDarkTheme ? Colors.grey[900] : Colors.grey[200],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDarkTheme ? Colors.white : Colors.black,
          ),
        ),
        contentPadding: EdgeInsets.zero,
      ),
      style: TextStyle(
        color: isDarkTheme ? Colors.white : Colors.black,
        fontSize: screenWidth * 0.04,
      ),
      onChanged: _onSearchChanged,
    );
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      _filteredModels = _allModels.where((model) {
        return model.title.toLowerCase().startsWith(_searchQuery);
      }).toList();
    });

    if (query.isNotEmpty) {
      final total = _filteredModels.length;
      _modelAnimations = _filteredModels.asMap().entries.map((entry) {
        int index = entry.key;
        double start = total > 0 ? index / total : 0.0;
        double end = total > 0 ? (index + 1) / total : 1.0;
        return Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _searchAnimationController,
            curve: Interval(
              start.clamp(0.0, 1.0),
              end.clamp(0.0, 1.0),
              curve: Curves.easeIn,
            ),
          ),
        );
      }).toList();

      _searchAnimationController.reset();
      _searchAnimationController.forward();
    } else {
      setState(() {
        _modelAnimations = _filteredModels
            .map((model) => AlwaysStoppedAnimation(1.0))
            .toList();
      });
    }
  }
}

class FadeInText extends StatefulWidget {
  final String text;
  final bool isDarkTheme;
  final Duration fadeInDuration;

  const FadeInText({
    Key? key,
    required this.text,
    required this.isDarkTheme,
    this.fadeInDuration = const Duration(milliseconds: 300),
  }) : super(key: key);

  @override
  _FadeInTextState createState() => _FadeInTextState();
}

class _FadeInTextState extends State<FadeInText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.fadeInDuration,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Text(
        widget.text,
        style: TextStyle(
          color: widget.isDarkTheme ? Colors.white : Colors.black,
          fontSize: 16,
        ),
      ),
    );
  }
}