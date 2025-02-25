// chat.dart

import 'dart:convert';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cortex/premium.dart';
import 'package:cortex/chat/viewer.dart';
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
import '../hexagons.dart';
import '../models.dart';
import '../settings.dart';
import '../data.dart';
import '../download.dart';
import '../main.dart';
import '../inbox.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../api.dart';
import 'messages.dart';
import '../notifications.dart';
import '../theme.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import '../system_info.dart';
import 'package:flutter/gestures.dart';
import 'package:share_plus/share_plus.dart';

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
  final ValueNotifier<String> notifier;  // <-- EKLENDİ

  Message({
    required this.text,
    required this.isUserMessage,
    this.shouldFadeOut = false,
    this.isReported = false,
    this.isPhotoUploading = false,
    this.photoPath,
    this.parsedSpans,
  }) : notifier = ValueNotifier(text);  // Başlangıç değeri
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

Widget buildChatActionButton(VoidCallback onPressed) {
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
          color: AppColors.opposedPrimaryColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          Icons.arrow_upward,
          color: AppColors.primaryColor,
          size: 24,
        ),
      ),
    ),
  );
}

class ExpandedInputScreen extends StatefulWidget {
  /// Mevcut metni ve controller’ı korumak için:
  final String initialText;
  final TextEditingController controller;

  /// Genişlemeden çıkarken güncellenmiş metni geri döndürmek için:
  final ValueChanged<String> onShrink;

  /// (Opsiyonel) Gönderme butonuna basıldığında mesaj gönderme işlemini tetiklemek için callback.
  final VoidCallback? onSend;

  const ExpandedInputScreen({
    Key? key,
    required this.initialText,
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
    final Color bgColor = AppColors.secondaryColor;
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: bgColor,
        body: SafeArea(
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
                              color: AppColors.opposedPrimaryColor,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 16,
                      right: 16,
                      child: GestureDetector(
                        onTap: _shrinkAndReturn,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 5.0),
                          child: Transform.rotate(
                            angle: -1.5708, // 90 derece sola döndür (yaklaşık -π/2)
                            child: SvgPicture.asset(
                              'assets/arrov.svg',
                              width: 20,
                              height: 20,
                              color: AppColors.opposedPrimaryColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      right: 10,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 100),
                        child: widget.controller.text.trim().isEmpty
                            ? const SizedBox(width: 0, height: 0)
                            : buildChatActionButton(_onActionButtonPressed),
                      ),
                    ),
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
    'chatgpt',
    'claude3haiku',
    'amazonnovalite',
    'deepseekv3',
  ];
  String? modelId;
  List<String> otherServerSideModels = [];
  bool _hasUserInitiatedConversation = false;
  bool responseStopped = false;
  bool _showInappropriateMessageWarning = false;

  late AnimationController _warningAnimationController;
  late Animation<Offset> _warningSlideAnimation;
  late Animation<double> _warningFadeAnimation;
  late VoidCallback _downloadedModelsListener;

  bool _showScrollDownButton = false;
  bool hasInternetConnection = true;
  late StreamSubscription<InternetStatus> _internetSubscription;

  int _hasCortexSubscription = 0;
  int _credits = 0;
  int _bonusCredits = 100;
  int get totalCredits => _credits + _bonusCredits;
  bool _showLimitReachedWarning = false;
  String _currentWarningMessage = '';
  bool _isLimitFadeOutApplied = false;
  late AnimationController _searchAnimationController;
  List<Animation<double>> _modelAnimations = [];
  Map<String, dynamic>? _userData;

  DateTime? _lastResetDate;
  Timer? chunkTimer;
  bool _isThinking = false;
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
  static Timer? _cacheClearTimer;
  bool _isInputExpanded = false;

  final GlobalKey _exitButtonKey = GlobalKey();
  final GlobalKey _accountButtonKey = GlobalKey();

  static const MethodChannel llamaChannel =
  MethodChannel('com.vertex.cortex/llama');

  final ScrollController _scrollController = ScrollController();

  int _serverSideConversationsCount = 0;
  int _serverSideConversationLimit = 25; // default for free
  bool _conversationLimitReached = false;
  int _getConversationLimit(int subValue) {
    // MATCHES the logic in daily bonus system:
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

  StreamSubscription<DocumentSnapshot>? _creditsSubscription;

  List<String> _currentExtensions = [];
  String _currentBaseSeries = '';
  String _selectedExtensionLabel = '';
  final GlobalKey _extensionKey = GlobalKey();
  String _displayedExtensionLabel = "";
  late AnimationController _extensionFadeOutController;
  late AnimationController _extensionFadeInController;

  bool _isExtensionPanelClosing = false; // Panelin kapanma animasyonunun tetiklenip tetiklenmediği

  bool _isTapInsideWidget(GlobalKey key, Offset globalPosition) {
    if (key.currentContext == null) return false;
    final RenderBox box = key.currentContext!.findRenderObject() as RenderBox;
    final Offset position = box.localToGlobal(Offset.zero);
    final Size size = box.size;
    return globalPosition.dx >= position.dx &&
        globalPosition.dx <= position.dx + size.width &&
        globalPosition.dy >= position.dy &&
        globalPosition.dy <= position.dy + size.height;
  }

// AppBar’daki exit ve hesap butonlarının alanlarını kontrol eden metot.
  bool _isTapInsideAppBarButtons(Offset globalPosition) {
    return _isTapInsideWidget(_exitButtonKey, globalPosition) ||
        _isTapInsideWidget(_accountButtonKey, globalPosition);
  }

  PreferredSizeWidget _buildAppBarWrapper(
      BuildContext context,
      AppLocalizations localizations,
      ) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (PointerDownEvent event) {
          if (_extensionOverlayEntry != null &&
              !_isTapInsideAppBarButtons(event.position)) {
            setState(() {
              _extensionPanelIsClosing = true;
            });
            _extensionOverlayEntry?.markNeedsBuild();
          }
        },
        child: _buildAppBar(context, localizations),
      ),
    );
  }


  DownloadedModelsManager? _downloadedModelsManager;

  @override
  void didChangeDependencies() {
    if (!_modelsLoaded) {
      _loadModels();
    }
    _downloadedModelsManager ??= Provider.of<DownloadedModelsManager>(context, listen: false);
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
    _cancelCacheClearTimer();
    if (cachedAllModels != null && cachedFilteredModels != null) {
      setState(() {
        _allModels = List.from(cachedAllModels!);
        _filteredModels = List.from(cachedFilteredModels!);
        _modelsLoaded = true;
      });
    } else {
      _modelsLoaded = false;
    }
    _fetchUserData();
    _updateInternetStatus();
    _textFieldFocusNode.addListener(() {
      setState(() {
        _isInputExpanded = _textFieldFocusNode.hasFocus;
      });
    });
    // Remove _loadModels() from here so we don’t call it before inherited widgets are ready.
    WidgetsBinding.instance.addObserver(this);
    _downloadedModelsListener = () {
      resetModelCacheAndReload();
    };
    Provider.of<DownloadedModelsManager>(context, listen: false)
        .addListener(_downloadedModelsListener);
    _searchAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _showScrollDownButton = false;

    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _creditsSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((doc) {
        setState(() {
          _credits = doc.get('credits') ?? 0;
        });
      });
    }

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

  void resetModelCacheAndReload() {
    cachedAllModels = null;
    cachedFilteredModels = null;
    _loadModels();
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

  /// Ekrana girildiğinde varsa daha önce başlatılmış zamanlayıcıyı iptal eder.
  void _cancelCacheClearTimer() {
    if (_cacheClearTimer != null) {
      _cacheClearTimer!.cancel();
      _cacheClearTimer = null;
      debugPrint("ChatScreen cache-clear timer canceled (screen re-entered).");
    }
  }

  /// Ekrandan çıkıldığında 2 dakikalık zamanlayıcı başlatarak cache verilerini temizler.
  void _startCacheClearTimer() {
    _cacheClearTimer = Timer(const Duration(minutes: 2), () {
      if (mounted) {
        setState(() {
          cachedAllModels = null;
          cachedFilteredModels = null;
        });
      } else {
        // Eğer widget tree'den kaldırılmışsa, setState() yapmadan temizleyelim.
        cachedAllModels = null;
        cachedFilteredModels = null;
      }
      debugPrint("ChatScreen cache cleared due to inactivity.");
    });
  }

  Future<void> _fetchUserData() async {
    final User? user = FirebaseAuth.instance.currentUser;
    bool isConnected = await InternetConnection().hasInternetAccess;
    if (!isConnected) {
      // İnternet yoksa, doğrudan cache’den verileri yükleyip çıkalım.
      await _loadCachedUserData();
      return;
    }

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
          _serverSideConversationsCount = _userData?['conversations'] ?? 0;
          _serverSideConversationLimit = _getConversationLimit(_hasCortexSubscription);
          _conversationLimitReached = _serverSideConversationsCount >= _serverSideConversationLimit;

          final lastResetTimestamp = _userData?['lastResetDate'];
          _lastResetDate = lastResetTimestamp != null ? (lastResetTimestamp as Timestamp).toDate() : null;
        });

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'cached_user_data',
          jsonEncode(_userData, toEncodable: (object) {
            if (object is Timestamp) {
              return object.toDate().toIso8601String();
            }
            return object;
          }),
        );

        // Günlük bonus kontrolü…
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
        // Hata durumunda cache’den yükle
        await _loadCachedUserData();
      }
    }
  }

  void _initializeModelExtensions(String mainId, String ext) {
    // Model verisini getiriyoruz:
    Map<String, dynamic> modelData = _getModelDataFromId(mainId);
    // Eğer model verisinde "extensions" varsa:
    if (modelData.isNotEmpty && modelData.containsKey('extensions')) {
      _currentExtensions = List<String>.from(modelData['extensions']);
    } else {
      // Uzantı desteği yoksa:
      _currentExtensions = [];
      setState(() {
        _currentBaseSeries = '';
        _selectedExtensionLabel = '';
        _displayedExtensionLabel = '';
      });
      return;
    }

    // Eğer ext boşsa, varsayılan olarak listenin ilk elemanını kullan:
    if (ext.isEmpty && _currentExtensions.isNotEmpty) {
      ext = _currentExtensions.first;
    }

    setState(() {
      _currentBaseSeries = mainId; // örn. "chatgpt" veya "llama"
      _selectedExtensionLabel = ext;
      _displayedExtensionLabel = ext;
    });

    // AnimationController'ları başlatma kısmı aynı kalıyor.
    _extensionFadeOutController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _extensionFadeInController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _extensionFadeOutController.addListener(() {
      setState(() {});
    });
    _extensionFadeInController.addListener(() {
      setState(() {});
    });
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
    if (!mounted) return; // Widget dispose edilmişse hemen çık
    try {
      final localizations = AppLocalizations.of(context)!;
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> allModelsData = ModelData.models(context);
      final Set<String> addedIds = {};
      List<ModelInfo> freshModels = [];

      // 1. Yerleşik modelleri yükle
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
          bool isDownloaded = prefs.getBool('is_downloaded_$id') ?? false;
          if (isDownloaded) {
            String modelFilePath = await _getModelFilePath(title);
            freshModels.add(ModelInfo(
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
          freshModels.add(ModelInfo(
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

      // 2. Özel modelleri yükle
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
            freshModels.add(ModelInfo(
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

      if (!mounted) return;
      setState(() {
        _allModels = freshModels;
        _filteredModels = List.from(_allModels);
        _modelsLoaded = true;
      });

      // Cache güncellemesi
      cachedAllModels = List.from(_allModels);
      cachedFilteredModels = List.from(_filteredModels);
    } catch (e) {
      debugPrint('Error in _loadModels: $e');
    }
  }

  Future<void> _loadCachedUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedData = prefs.getString('cached_user_data');
    if (cachedData != null) {
      try {
        final data = jsonDecode(cachedData);
        setState(() {
          _userData = data;
          _credits = data['credits'] ?? 0;
          _bonusCredits = data['bonusCredits'] ?? 0;
        });
      } catch (e) {
        print("Cache parse hatası: $e");
      }
    }
  }

  Future<void> loadModel() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedModelPath = modelPath ?? prefs.getString('selected_model_path');
    if (selectedModelPath != null && selectedModelPath.isNotEmpty) {
      try {
        await llamaChannel.invokeMethod('loadModel', {'path': selectedModelPath});
        if (!mounted) return;
        setState(() {
          isModelLoaded = true;
        });
        mainScreenKey.currentState?.updateBottomAppBarVisibility();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            FocusScope.of(context).requestFocus(_textFieldFocusNode);
          }
        });
      } catch (e) {
        print('Error loading model: $e');
        if (!mounted) return;
        setState(() {
          isModelLoaded = false;
        });
        mainScreenKey.currentState?.updateBottomAppBarVisibility();
      }
    } else {
      if (!mounted) return;
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
    for (var key in _specialServerSideModels) {
      if (modelId.startsWith(key)) return true;
    }
    for (var key in otherServerSideModels) {
      if (modelId.startsWith(key)) return true;
    }
    return false;
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
        messages.last.notifier.value = messages.last.text;
      });
      if (_isUserAtBottom()) {
        _scrollToBottom();
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
    _isProcessingChunks = false;

    if (!isServerSideModel(modelId)) {
      final localizations = AppLocalizations.of(context)!;
      if (messages.isNotEmpty &&
          !messages.last.isUserMessage &&
          messages.last.text.trim().isNotEmpty &&
          messages.last.text != localizations.thinking) {
        await _saveMessageToConversation(messages.last.text, false, isReported: false);
        await _updateConversationLastMessageText(messages.last.text, photoPath: messages.last.photoPath);
        await _updateConversationLastMessageDate(DateTime.now());
      }
    }
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
      _jumpToBottom();
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

  void _jumpToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
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

  String _buildFullContext() {
    final buffer = StringBuffer();
    for (var message in messages) {
      if (message.isUserMessage) {
        buffer.writeln("User: ${message.text}");
        if (message.photoPath != null && message.photoPath!.isNotEmpty) {
          buffer.writeln("User Photo: ${message.photoPath}");
        }
      } else {
        buffer.writeln("${message.text}");
        if (message.photoPath != null && message.photoPath!.isNotEmpty) {
          buffer.writeln("${message.photoPath}");
        }
      }
    }
    return buffer.toString().trim();
  }

  void loadConversation(ConversationManager manager) async {
    setState(() {
      widget.conversationID = manager.conversationID;
      widget.conversationTitle = manager.conversationTitle;
      conversationID = manager.conversationID;
      conversationTitle = manager.conversationTitle;
    });

    // Eğer manager.modelId uzantı içermiyorsa, tam modelId oluştur.
    if (!manager.modelId.contains('-')) {
      modelId = await buildFullModelId(manager.modelId);
    } else {
      modelId = manager.modelId;
    }

    // EK ÇÖZÜM: modelId belirlendiyse, ana kısım ve uzantıyı ayrıştırıp state’i güncelleyelim.
    if (modelId != null) {
      String lowerId = modelId!.toLowerCase();
      String mainId = lowerId.contains('-') ? lowerId.split('-')[0] : lowerId;
      String ext = lowerId.contains('-') ? lowerId.split('-')[1] : '';
      _initializeModelExtensions(mainId, ext);
    }

    setState(() {
      modelTitle = manager.modelTitle;
      modelImagePath = manager.modelImagePath;
      isModelSelected = true;
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

  Widget _buildModelExtensionSelector() {
    if (_currentBaseSeries.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      key: _extensionKey, // for overlay positioning
      onTap: _showModelExtensionPanel,
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          _buildAnimatedArrowIcon(),
        ],
      ),
    );
  }

  Widget _buildAnimatedArrowIcon() {
    double arrowOpacity = 1.0;
    if (_extensionFadeOutController.isAnimating) {
      arrowOpacity = 1.0 - _extensionFadeOutController.value;
    } else if (_extensionFadeInController.isAnimating) {
      arrowOpacity = _extensionFadeInController.value;
    }
    return AnimatedOpacity(
      opacity: arrowOpacity,
      duration: const Duration(milliseconds: 50),
      child: Transform.rotate(
        angle: 4.7124,
        child: SvgPicture.asset(
          'assets/arrov.svg',
          color: (AppColors.opposedPrimaryColor).withOpacity(arrowOpacity),
          width: 20,
          height: 20,
        ),
      ),
    );
  }

  void _animateExtensionChange(String newLabel) {
    if (_displayedExtensionLabel == newLabel) return;
    setState(() {
      _displayedExtensionLabel = newLabel;
      if (_currentBaseSeries.isNotEmpty) {
        modelId = '$_currentBaseSeries-${newLabel.replaceAll(' ', '').toLowerCase()}';
      } else {
        modelId = newLabel;
      }
    });
  }

  OverlayEntry? _extensionOverlayEntry;
  final GlobalKey _panelKey = GlobalKey();

  void _showModelExtensionPanel() {
    if (_extensionOverlayEntry != null) {
      setState(() {
        _isExtensionPanelClosing = true;
      });
      return;
    }
    _insertExtensionPanel();
  }

  String defaultExtensionFor(String mainId) {
    if (mainId.toLowerCase() == "chatgpt") {
      return "4o-mini";
    } else if (mainId.toLowerCase() == "llama") {
      return "3.3-70b";
    }
    // Diğer modeller için de default uzantı eklenebilir.
    return "";
  }

  Future<String> getLastSelectedExtension(String mainId) async {
    final prefs = await SharedPreferences.getInstance();
    String? savedExtension = prefs.getString("last_extension_$mainId");
    if (savedExtension == null || savedExtension.isEmpty) {
      savedExtension = defaultExtensionFor(mainId);
    }
    return savedExtension;
  }

  Future<void> setLastSelectedExtension(String mainId, String extension) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("last_extension_$mainId", extension);
  }

  Future<String> buildFullModelId(String mainId, [String? extension]) async {
    String ext = extension ?? await getLastSelectedExtension(mainId);
    if (ext.isNotEmpty) {
      return "$mainId-$ext";
    } else {
      return mainId;
    }
  }

  // Yardımcı fonksiyon: Uzantı adını biçimlendirir.
  String formatExtension(String ext) {
    List<String> parts = ext.split('-');
    List<String> capitalizedParts = parts.map((s) {
      if (s.isEmpty) return s;
      return s[0].toUpperCase() + s.substring(1);
    }).toList();
    return capitalizedParts.join(" ");
  }

  String _formatModelTitle(String title) {
    if (title.toLowerCase() == "chatgpt") {
      return "GPT";
    }
    return title;
  }

  bool _extensionPanelIsClosing = false;

  Widget _buildExtensionPanelWidget({
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

    // Panelin köşe yuvarlatma değeri
    final panelBorderRadius = screenWidth * 0.02;
    // Öğelerin köşe yuvarlatma değeri
    final itemRadius = screenWidth * 0.02;

    final textStyle = TextStyle(
      color: AppColors.primaryColor,
      fontSize: screenWidth * 0.04,
    );

    // Panelin genişliğini, içeriğe göre hesaplayalım
    double maxTextWidth = 0;
    for (var entry in options) {
      final text = "${_formatModelTitle(modelTitle)} ${formatExtension(entry.key)}";
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
              // Buton satırı
              _buildExtensionButtonRow(
                context: context,
                option: options[i],
                isSelected: options[i].key == selectedExtension,
                modelTitle: modelTitle,
                iconSize: iconSize,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding,
                minHeight: optionMinHeight,
                // İlk, son veya orta satıra göre farklı borderRadius
                borderRadius: _getItemBorderRadius(i, options.length, itemRadius),
                textStyle: textStyle,
                onTap: () => onSelect(options[i]),
                // Orta satırlara alt çizgi ekle (son satır hariç)
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
                  ? AppColors.quaternaryColor  // <-- Güncellendi: Seçili buton rengi
                  : Colors.transparent,
              border: showBottomBorder
                  ? Border(
                bottom: BorderSide(
                  color: AppColors.secondaryColor, // Panelin genel rengi
                  width: screenWidth * 0.003,
                ),
              )
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // İkon her durumda opposedPrimaryColor, seçili ise biraz daha büyük görünecek
                Transform.scale(
                  scale: isSelected ? 1.2 : 1.0,
                  child: SvgPicture.asset(
                    'assets/extension.svg',
                    width: iconSize,
                    height: iconSize,
                    color: AppColors.opposedPrimaryColor,
                  ),
                ),
                SizedBox(width: horizontalPadding * 0.5),
                Flexible(
                  child: Text(
                    "${_formatModelTitle(modelTitle)} ${formatExtension(option.key)}",
                    style: textStyle.copyWith(
                      color: AppColors.opposedPrimaryColor,
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

  /// İlk, son veya tek öğe durumuna göre farklı köşe yarıçapı veren metod
  BorderRadius _getItemBorderRadius(int index, int total, double radius) {
    if (total == 1) {
      // Tek öğe: tüm köşeler yuvarlak
      return BorderRadius.circular(radius);
    } else if (index == 0) {
      // İlk öğe: üst köşeler yuvarlak
      return BorderRadius.only(
        topLeft: Radius.circular(radius),
        topRight: Radius.circular(radius),
      );
    } else if (index == total - 1) {
      // Son öğe: alt köşeler yuvarlak
      return BorderRadius.only(
        bottomLeft: Radius.circular(radius),
        bottomRight: Radius.circular(radius),
      );
    } else {
      // Ortadaki öğeler: düz kenar
      return BorderRadius.zero;
    }
  }

  void _insertExtensionPanel() {
    if (_currentExtensions.isEmpty) return;
    // Panel açılırken kapanma bayrağını sıfırla:
    _extensionPanelIsClosing = false;

    final options = _currentExtensions.map((ext) => MapEntry(ext, ext)).toList();
    final overlay = Overlay.of(context);

    final RenderBox? renderBox =
    _extensionKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final Offset offset =
    renderBox.localToGlobal(Offset(0, renderBox.size.height + 12));

    OverlayEntry entry = OverlayEntry(
      builder: (BuildContext context) {
        final screenWidth = MediaQuery.of(context).size.width;
        final panelWidth = screenWidth * 0.9;
        final horizontalMargin = (screenWidth - panelWidth) / 2;
        // AppBar alt sınırı
        final double appBarBottom =
            MediaQuery.of(context).padding.top + kToolbarHeight;

        return StatefulBuilder(
          builder: (BuildContext context, setState) {
            return Stack(
              children: [
                // AppBar altındaki alan: onTap ile kapanmayı tetikleyelim.
                Positioned(
                  top: appBarBottom,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      setState(() {
                        _extensionPanelIsClosing = true;
                      });
                    },
                    child: Container(color: Colors.transparent),
                  ),
                ),
                // Uzantı paneli
                Positioned(
                  top: offset.dy,
                  left: horizontalMargin,
                  right: horizontalMargin,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: _extensionPanelIsClosing ? 1.0 : 0.4,
                      end: _extensionPanelIsClosing ? 0.4 : 1.0,
                    ),
                    duration: const Duration(milliseconds: 50),
                    curve: Curves.easeOut,
                    builder: (context, scale, child) {
                      return Transform.scale(
                        scale: scale,
                        alignment: Alignment.topCenter,
                        child: child,
                      );
                    },
                    onEnd: () {
                      if (_extensionPanelIsClosing) removeExtensionOverlay();
                    },
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: _buildExtensionPanelWidget(
                        context: context,
                        options: options,
                        selectedExtension: _displayedExtensionLabel,
                        modelTitle: modelTitle ?? "",
                        onDismiss: () {
                          setState(() {
                            _extensionPanelIsClosing = true;
                          });
                        },
                        onSelect: (selectedEntry) {
                          _animateExtensionChange(selectedEntry.key);
                          setState(() {
                            _extensionPanelIsClosing = true;
                          });
                        },
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    overlay.insert(entry);
    _extensionOverlayEntry = entry;
  }

  void removeExtensionOverlay() {
    if (_extensionOverlayEntry != null) {
      _extensionOverlayEntry!.remove();
      _extensionOverlayEntry = null;
      _extensionPanelIsClosing = false;
    }
  }

  void _selectModel(ModelInfo model) async {
    // Önce eski sohbeti temizleyin.
    await resetConversation();

    setState(() {
      modelId = model.id;
      modelTitle = model.title;
      modelDescription = model.description;
      modelImagePath = model.imagePath;
      modelProducer = model.producer;
      modelPath = model.path;
      role = model.role;
      canHandleImage = model.canHandleImage;
      // Konuşma ID'si ve başlık temiz bırakılıyor.
    });

    // Model id'sinde uzantı varsa parçalayalım.
    String mainId;
    String ext;
    if (model.id.contains('-')) {
      List<String> parts = model.id.split('-');
      mainId = parts[0];
      ext = parts[1];
    } else {
      mainId = model.id;
      ext = await getLastSelectedExtension(mainId);
    }

    // Şimdi uzantı panelini başlatın.
    _initializeModelExtensions(mainId, ext);

    modelId = await buildFullModelId(mainId, ext);

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

  Future<void> onExtensionSelected(String newExtension) async {
    // modelId'nin ana kısmını alın:
    String? mainId = modelId!.contains('-') ? modelId?.split('-')[0] : modelId;
    // Yeni tam model id oluşturun:
    String newFullModelId = "$mainId-$newExtension";
    // Kullanıcının seçimini kaydedin:
    await setLastSelectedExtension(mainId!, newExtension);
    // Yeni model id'yi state'e atayın:
    setState(() {
      modelId = newFullModelId;
    });
    // Eğer aktif bir sohbet varsa, conversation entry güncelleyin:
    if (conversationID != null) {
      await _updateConversationModelId(newFullModelId);
    }
  }

  /// Conversation entry içindeki modelId kısmını güncelleyen fonksiyon:
  Future<void> _updateConversationModelId(String newModelId) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> conversations = prefs.getStringList('conversations') ?? [];
    int index = conversations.indexWhere((c) => c.startsWith('$conversationID|'));
    if (index != -1) {
      List<String> parts = conversations[index].split('|');
      // modelId kısmı index 2'de saklanıyorsa:
      if (parts.length >= 3) {
        parts[2] = newModelId;
        String newEntry = parts.join('|');
        conversations[index] = newEntry;
        await prefs.setStringList('conversations', conversations);
      }
    }
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

    if (lastMessageText.trim().isEmpty && lastMessagePhotoPath.isNotEmpty) {
      lastMessageText = "PHOTO_ONLY";
    }
    String sanitizedLastMessageText = lastMessageText.replaceAll('|', ' ');
    String sanitizedLastMessagePhotoPath = lastMessagePhotoPath.replaceAll('|', ' ');

    // modelId'yi kaydederken; eğer modelId zaten tam kimlik (örneğin "chatgpt-4o-mini") içeriyorsa
    // direkt saklayın. Eğer sadece ana kısım ise, varsayılan uzantıyı ekleyin.
    String storedModelId = modelId ?? "";
    if (!storedModelId.contains('-')) {
      storedModelId = await buildFullModelId(storedModelId);
    }
    // Kaydı: conversationID|conversationTitle|modelIdWithExtension|tarih|mesaj|foto
    String conversationEntry =
        '$conversationID|$conversationName|$storedModelId|$lastMessageDateString|$sanitizedLastMessageText|$sanitizedLastMessagePhotoPath';

    if (!conversations.any((c) => c.startsWith('$conversationID|'))) {
      conversations.add(conversationEntry);
      await prefs.setStringList('conversations', conversations);
    }
  }

  bool _isUserAtBottom() {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    const double threshold = 100.0;
    return (maxScroll - currentScroll) <= threshold;
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

  Future<void> _updateModelDataFromId() async {
    if (modelId != null) {
      final lowerId = modelId!.toLowerCase();
      // Ana model id’sini alıyoruz:
      String mainId = lowerId.contains('-') ? lowerId.split('-')[0] : lowerId;
      // Eğer modelId uzantı içermiyorsa, SharedPreferences’ten son seçili uzantıyı alalım:
      String ext = lowerId.contains('-') ? lowerId.split('-')[1] : await getLastSelectedExtension(mainId);

      // Model verisini ana id üzerinden alalım:
      Map<String, dynamic> modelData = _getModelDataFromId(mainId);
      if (modelData.isNotEmpty) {
        setState(() {
          modelTitle = modelData['title'];
          modelDescription = modelData['description'];
          modelImagePath = modelData['image'];
          modelProducer = modelData['producer'];
          // Server-side modelde modelPath olmayabilir.
          modelPath = modelData['isServerSide'] == true ? null : modelPath;
        });
      }
      // Modelin ana serisini ve uzantısını ayarlayalım:
      _initializeModelExtensions(mainId, ext);
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
    String? regeneratePhotoPath,
  }) async {
    final localizations = AppLocalizations.of(context)!;
    final String text = textFromButton ?? _controller.text.trim();

    final bool hasNewPhoto = _selectedPhoto != null;
    if (!isRegenerate && text.isEmpty && !hasNewPhoto) return;

    FocusScope.of(context).unfocus();
    await _fetchUserData();

    int? userMessageIndex; // Track user message position
    int? aiMessageIndex;   // Track AI message position

    if (!isRegenerate && conversationID == null) {
      if (isServerSideModel(modelId)) {
        if (!hasInternetConnection) {
          _showInternetRequiredNotification();
          return;
        }
        if (_serverSideConversationsCount >= _serverSideConversationLimit) {
          Provider.of<NotificationService>(context, listen: false).showNotification(
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
                _conversationLimitReached = _serverSideConversationsCount >= _serverSideConversationLimit;
              });
            } catch (e) {
              print("Error incrementing conversation count: $e");
            }
          }
        }
        conversationID = uuid.v4();
        conversationTitle = (text.trim().isEmpty && hasNewPhoto) ? "🖼" : (text.length > 28 ? text.substring(0, 28) : text);
        await _saveConversationTitle(conversationTitle!);
        await _saveConversation(conversationTitle!);
        mainScreenKey.currentState?.menuScreenKey.currentState?.reloadConversations();

        setState(() {
          userMessageIndex = messages.length; // Record user message index
          messages.add(Message(
            text: text,
            isUserMessage: true,
            photoPath: hasNewPhoto ? _selectedPhoto!.path : null,
            isPhotoUploading: true,
          ));
          _controller.clear();
          isWaitingForResponse = true;
          _isSendButtonVisible = false;
          responseStopped = false;
          _creditsDeducted = false;
          _isThinking = true;
          aiMessageIndex = messages.length; // Record AI message index
          messages.add(Message(
            text: localizations.thinking,
            isUserMessage: false,
          ));
        });
        await _scrollToBottom(forceScroll: true);
        await _saveMessageToConversation(text, true, isReported: false, photoPath: hasNewPhoto ? _selectedPhoto!.path : null);
        await _updateConversationLastMessageText(text, photoPath: hasNewPhoto ? _selectedPhoto!.path : null);
        await _updateConversationLastMessageDate(DateTime.now());
      }
    } else if (isRegenerate && regenerateAiIndex != null) {
      setState(() {
        messages[regenerateAiIndex].text = localizations.thinking;
        isWaitingForResponse = true;
        _isSendButtonVisible = false;
        responseStopped = false;
        _creditsDeducted = false;
        _isThinking = true;
        aiMessageIndex = regenerateAiIndex; // Use existing AI message index
      });
    } else {
      setState(() {
        userMessageIndex = messages.length;
        messages.add(Message(
          text: text,
          isUserMessage: true,
          photoPath: hasNewPhoto ? _selectedPhoto!.path : null,
          isPhotoUploading: true,
        ));
        _controller.clear();
        isWaitingForResponse = true;
        _isSendButtonVisible = false;
        responseStopped = false;
        _creditsDeducted = false;
        _isThinking = true;
        aiMessageIndex = messages.length;
        messages.add(Message(
          text: localizations.thinking,
          isUserMessage: false,
        ));
      });
      await _saveMessageToConversation(text, true, isReported: false, photoPath: hasNewPhoto ? _selectedPhoto!.path : null);
      await _updateConversationLastMessageText(text, photoPath: hasNewPhoto ? _selectedPhoto!.path : null);
      await _updateConversationLastMessageDate(DateTime.now());
    }

    final String currentConversationId = conversationID ?? "";

    DateTime now = DateTime.now();
    String? photoPath;
    if (hasNewPhoto) {
      setState(() {
        photoPath = _selectedPhoto!.path;
        _selectedPhoto = null;
      });
      await Future.delayed(const Duration(milliseconds: 200));
    }
    if (isRegenerate && regeneratePhotoPath != null) {
      photoPath = regeneratePhotoPath;
    }

    try {
      if (!isServerSideModel(modelId)) {
        llamaChannel.invokeMethod('sendMessage', {
          'message': text,
          'photoPath': photoPath,
        });
        _startResponseTimeout();
      } else {
        final memory = _buildFullContext();
        bool hasReceivedFirstChunk = false;
        final partialBuffer = StringBuffer();
        chunkTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
          if (!mounted || responseStopped || (conversationID != currentConversationId)) {
            timer.cancel();
            return;
          }
          if (partialBuffer.isNotEmpty) {
            if (!hasReceivedFirstChunk) {
              if (isRegenerate && regenerateAiIndex != null) {
                setState(() {
                  messages[regenerateAiIndex].text = '';
                  _isThinking = false;
                });
              } else if (aiMessageIndex != null && aiMessageIndex! < messages.length) {
                setState(() {
                  messages[aiMessageIndex!].text = '';
                  _isThinking = false;
                });
              }
              hasReceivedFirstChunk = true;
            }
            setState(() {
              if (isRegenerate && regenerateAiIndex != null) {
                messages[regenerateAiIndex].text += partialBuffer.toString();
              } else if (aiMessageIndex != null && aiMessageIndex! < messages.length) {
                messages[aiMessageIndex!].text += partialBuffer.toString();
              }
              partialBuffer.clear();
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _attemptScrollToBottom();
            });
            if (_isUserAtBottom()) {
              _scrollToBottom();
            }
          }
        });
        String finalResponse = '';
        if (modelId != null) {
          if (modelId!.startsWith('gemini')) {
            finalResponse = await apiService.getGeminiResponse(
              text,
              memory,
              photoPath: photoPath,
              onStreamChunk: (chunk) => partialBuffer.write(chunk),
              model: modelId!,
            );
          } else if (modelId!.startsWith('llama')) {
            finalResponse = await apiService.getLlamaResponse(
              text,
              memory,
              photoPath: photoPath,
              onStreamChunk: (chunk) => partialBuffer.write(chunk),
              model: modelId!,
            );
          } else if (modelId!.startsWith('hermes')) {
            finalResponse = await apiService.getHermesResponse(
              text,
              memory,
              photoPath: photoPath,
              onStreamChunk: (chunk) => partialBuffer.write(chunk),
              model: modelId!,
            );
          } else if (modelId!.startsWith('chatgpt')) {
            finalResponse = await apiService.getChatGPTResponse(
              text,
              memory,
              photoPath: photoPath,
              onStreamChunk: (chunk) => partialBuffer.write(chunk),
              model: modelId!,
            );
          } else if (modelId!.startsWith('claude')) {
            finalResponse = await apiService.getClaudeResponse(
              text,
              memory,
              photoPath: photoPath,
              onStreamChunk: (chunk) => partialBuffer.write(chunk),
              model: modelId!,
            );
          } else if (modelId!.startsWith('nova')) {
            finalResponse = await apiService.getNovaResponse(
              text,
              memory,
              photoPath: photoPath,
              onStreamChunk: (chunk) => partialBuffer.write(chunk),
              model: modelId!,
            );
          } else if (modelId!.startsWith('deepseek')) {
            finalResponse = await apiService.getDeepseekResponse(
              text,
              memory,
              photoPath: photoPath,
              onStreamChunk: (chunk) => partialBuffer.write(chunk),
              model: modelId!,
            );
          } else {
            finalResponse = await apiService.getCharacterResponse(
              role: role ?? '',
              userInput: text,
              context: memory,
              photoPath: photoPath,
              onStreamChunk: (chunk) => partialBuffer.write(chunk),
            );
          }
        }

        chunkTimer?.cancel();
        chunkTimer = null;

        if (conversationID != currentConversationId) {
          return;
        }

        if (partialBuffer.isNotEmpty) {
          if (!hasReceivedFirstChunk) {
            if (isRegenerate && regenerateAiIndex != null) {
              setState(() {
                messages[regenerateAiIndex].text = '';
                _isThinking = false;
              });
            } else if (aiMessageIndex != null && aiMessageIndex! < messages.length) {
              setState(() {
                messages[aiMessageIndex!].text = '';
                _isThinking = false;
              });
            }
            hasReceivedFirstChunk = true;
          }
          setState(() {
            if (isRegenerate && regenerateAiIndex != null) {
              messages[regenerateAiIndex].text += partialBuffer.toString();
            } else if (aiMessageIndex != null && aiMessageIndex! < messages.length) {
              messages[aiMessageIndex!].text += partialBuffer.toString();
            }
            partialBuffer.clear();
          });
        }

        setState(() {
          isWaitingForResponse = false;
          _isSendButtonVisible = _controller.text.isNotEmpty;
          _isThinking = false;
        });

        if (isRegenerate && regenerateAiIndex != null) {
          if (messages[regenerateAiIndex].text.isEmpty) {
            messages[regenerateAiIndex].text = finalResponse;
          }
          if (messages[regenerateAiIndex].text != localizations.thinking) {
            await _saveRegeneratedMessageToConversation(
              finalResponse: messages[regenerateAiIndex].text,
              aiIndex: regenerateAiIndex,
            );
          }
        } else if (aiMessageIndex != null && aiMessageIndex! < messages.length) {
          if (messages[aiMessageIndex!].text.isEmpty) {
            messages[aiMessageIndex!].text = finalResponse;
          }
          if (messages[aiMessageIndex!].text != localizations.thinking) {
            await _saveMessageToConversation(messages[aiMessageIndex!].text, false, isReported: false);
            await _updateConversationLastMessageText(messages[aiMessageIndex!].text, photoPath: messages[aiMessageIndex!].photoPath);
            await _updateConversationLastMessageDate(DateTime.now());
            await _updateConversationModelId(modelId!);
          }
        }
        await _deductCredits(hadPhoto: photoPath != null);
      }
    } catch (e) {
      setState(() {
        isWaitingForResponse = false;
        _isThinking = false;
        if (isRegenerate && regenerateAiIndex != null) {
          messages[regenerateAiIndex].text = 'Error: $e';
        } else if (aiMessageIndex != null && aiMessageIndex! < messages.length) {
          messages[aiMessageIndex!].text = 'Error: $e';
        } else {
          messages.add(Message(text: 'Error: $e', isUserMessage: false));
        }
      });
    }
  }

  void _attemptScrollToBottom() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    const double threshold = 100.0;
    if ((maxScroll - currentScroll) < threshold) {
      _scrollToBottom(); // forceScroll: true yerine, kullanıcı alt bölgedeyse normal kaydır.
    }
  }

  Future<void> _stopResponse() async {
    if (responseStopped || !isWaitingForResponse) return;

    chunkTimer?.cancel();
    chunkTimer = null;

    setState(() {
      responseStopped = true;
      isWaitingForResponse = false;
      _isSendButtonVisible = _controller.text.isNotEmpty;
    });

    // Find the last AI message
    int lastAiIndex = messages.lastIndexWhere((m) => !m.isUserMessage);
    if (lastAiIndex == -1) return;

    if (_isThinking) {
      setState(() {
        messages[lastAiIndex].shouldFadeOut = true;
        _isThinking = false; // Reset thinking state immediately
      });
    }
  }

  Future<void> _deductCredits({bool hadPhoto = false}) async {
    if (!_creditsDeducted) {
      int baseDeduction = (role != null && role!.isNotEmpty) ? 10 : 20;
      int photoAddition = hadPhoto ? 50 : 0;
      int totalDeduction = baseDeduction + photoAddition;

      int remainingDeduction = totalDeduction;
      int updatedBonus = _bonusCredits;
      int updatedCredits = _credits;

      // Önce bonus krediden düşelim.
      if (updatedBonus >= remainingDeduction) {
        updatedBonus -= remainingDeduction;
        remainingDeduction = 0;
      } else {
        remainingDeduction -= updatedBonus;
        updatedBonus = 0;
      }

      // Hâlâ düşülecek kredi varsa normal kredilerden düşelim.
      if (remainingDeduction > 0) {
        updatedCredits -= remainingDeduction;
        if (updatedCredits < 0) {
          updatedCredits = 0;
        }
      }

      // Firebase üzerinde güncelleme yapıyoruz.
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
    setState(() {
      _showScrollDownButton = false;
    });

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
    Future.delayed(const Duration(milliseconds: 300), () {
      setState(() {
        _selectedPhoto = null;
      });
    });
  }

  Widget _buildActionButton() {
    final bool isEnabled = _isSendButtonEnabled;
    final bool isOffline = !hasInternetConnection;
    final bool isSendingState = isWaitingForResponse;
    final Duration currentDuration = isEnabled
        ? const Duration(milliseconds: 100)
        : const Duration(milliseconds: 200);

    Color backgroundColor;
    if (isSendingState || isEnabled) {
      backgroundColor = AppColors.opposedPrimaryColor;
    } else if (isOffline) {
      backgroundColor = AppColors.opposedPrimaryColor.withOpacity(0.1);
    } else {
      backgroundColor = AppColors.opposedPrimaryColor.withOpacity(0.06);
    }

    Color iconColor;
    if (isSendingState || isEnabled) {
      iconColor = AppColors.primaryColor;
    } else {
      iconColor = AppColors.tertiaryColor;
    }

    Widget sendButton = GestureDetector(
      key: const ValueKey('sendButton'),
      onTap: isEnabled ? _sendMessage : null,
      child: AnimatedContainer(
        duration: currentDuration,
        curve: Curves.easeOut,
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
        ),
        child: AnimatedOpacity(
          duration: currentDuration,
          opacity: (isSendingState || isEnabled) ? 1.0 : 0.5,
          curve: Curves.easeInOut,
          child: Icon(
            Icons.arrow_upward,
            color: iconColor,
            size: 24,
          ),
        ),
      ),
    );

    Widget stopButton = GestureDetector(
      key: const ValueKey('stopButton'),
      onTap: _stopResponse,
      child: AnimatedContainer(
        duration: currentDuration,
        curve: Curves.easeOut,
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.opposedPrimaryColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: SvgPicture.asset(
            'assets/stop.svg',
            width: 22,
            height: 22,
            color: AppColors.primaryColor,
          ),
        ),
      ),
    );

    Widget currentChild = isSendingState ? stopButton : sendButton;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) {
        return ScaleTransition(scale: animation, child: child);
      },
      child: currentChild,
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

  Widget _buildInputField(AppLocalizations localizations) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    if (!isModelSelected) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        border: Border(
          top: BorderSide(
            color: AppColors.border,
            width: 1.0,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
          Padding(
            padding: EdgeInsets.zero,
            child: Stack(
              children: [
                Row(
                  children: [
                    if (canHandleImage) ...[
                      Padding(
                        padding: EdgeInsets.only(left: screenWidth * 0.01),
                        child: GestureDetector(
                          onTap: _selectedPhoto == null && !_isPhotoLoading
                              ? _pickPhoto
                              : null,
                          child: Opacity(
                            opacity:
                            _selectedPhoto == null && !_isPhotoLoading ? 1.0 : 0.5,
                            child: Container(
                              padding: EdgeInsets.all(screenWidth * 0.02),
                              child: Icon(
                                Icons.add,
                                color: AppColors.opposedPrimaryColor,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    Expanded(
                      child: TextField(
                        cursorColor: AppColors.opposedPrimaryColor,
                        controller: _controller,
                        maxLength: 4000,
                        minLines: 1,
                        maxLines: 6,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: localizations.messageHint,
                          hintStyle: TextStyle(
                            color: Colors.grey[600],
                            fontSize: screenWidth * 0.04,
                          ),
                          border: InputBorder.none,
                          counterText: '',
                          contentPadding: EdgeInsets.only(
                            left: canHandleImage ? 0 : screenWidth * 0.02,
                            right: 0,
                            top: 0,
                            bottom: 0,
                          ),
                        ),
                        style: TextStyle(
                          color: AppColors.opposedPrimaryColor,
                          fontSize: screenWidth * 0.04,
                        ),
                        onChanged: _onTextChanged,
                        onSubmitted: (text) {
                          if (_isSendButtonEnabled) _sendMessage();
                        },
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(right: screenWidth * 0.02),
                      child: _buildActionButton(),
                    ),
                  ],
                ),
                Positioned(
                  top: screenHeight * 0.01,
                  right: screenWidth * 0.03,
                  child: IgnorePointer(
                    ignoring: _getInputLineCount(
                      _controller.text,
                      screenWidth - (screenWidth * 0.04),
                    ) <= 2,
                    child: AnimatedOpacity(
                      opacity: _getInputLineCount(
                        _controller.text,
                        screenWidth - (screenWidth * 0.04),
                      ) > 2
                          ? 1.0
                          : 0.0,
                      duration: const Duration(milliseconds: 100),
                      child: GestureDetector(
                        onTap: _expandInputField,
                        child: Transform.rotate(
                          angle: 1.5708, // 90 derece sağa döndür (yaklaşık π/2)
                          child: SvgPicture.asset(
                            'assets/arrov.svg',
                            width: screenWidth * 0.04,
                            height: screenWidth * 0.036,
                            color: AppColors.opposedPrimaryColor,
                          ),
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
    _downloadedModelsManager?.removeListener(_downloadedModelsListener);
    removeExtensionOverlay();
    WidgetsBinding.instance.removeObserver(this);
    _creditsSubscription?.cancel();
    _controller.dispose();
    _startCacheClearTimer();
    responseTimer?.cancel();
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _warningAnimationController.dispose();
    _searchAnimationController.dispose();
    llamaChannel.setMethodCallHandler(null);
    _internetSubscription.cancel();
    _textFieldFocusNode.unfocus();
    _textFieldFocusNode.dispose();
    _showScrollDownButton = false;
    _isProcessingChunks = false;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _updateInternetStatus();
      setState(() {
        _conversationLimitReached = _serverSideConversationsCount >= _serverSideConversationLimit;
      });
      _loadModels();
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final screenHeight = MediaQuery.of(context).size.height;

    if (_shouldHideImmediately) {
      return Container();
    }

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        extendBody: true,
        appBar: _buildAppBarWrapper(context, localizations),
        body: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                FocusScope.of(context).unfocus();
              },
              child: Container(
                color: AppColors.background,
                child: Column(
                  children: [
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 125),
                        transitionBuilder: (Widget child, Animation<double> animation) {
                          return FadeTransition(opacity: animation, child: child);
                        },
                        child: isModelSelected
                            ? _buildChatScreen(localizations)
                            : _buildModelSelectionScreen(localizations),
                      ),
                    ),
                    _buildInputField(localizations),
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
                        color: AppColors.warning,
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
        floatingActionButton: (isModelSelected && messages.isNotEmpty)
            ? AnimatedOpacity(
          opacity: _showScrollDownButton ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 100),
          child: AnimatedScale(
            scale: _showScrollDownButton ? 1.0 : 0.5,
            duration: const Duration(milliseconds: 100),
            child: IgnorePointer(
              ignoring: !_showScrollDownButton,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: _inputFieldHeight +
                      MediaQuery.of(context).size.height * 0.06,
                ),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: FloatingActionButton(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    elevation: 2.0,
                    backgroundColor: AppColors.background,
                    onPressed: () => _scrollToBottom(forceScroll: true),
                    child: SvgPicture.asset(
                      'assets/arrov.svg',
                      color: Colors.white,
                      width: 30,
                      height: 30,
                    ),
                  ),
                ),
              ),
            ),
          ),
        )
            : null,
      ),
    );
  }

  Widget _buildModelSelectionScreen(AppLocalizations localizations) {
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
                ? _buildModelGrid(localizations)
                : const SizedBox.shrink(),
          ),
          AnimatedOpacity(
            opacity: !_modelsLoaded ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 250),
            child: IgnorePointer(
              ignoring: _modelsLoaded,
              child: _buildSkeletonModelGrid(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelGrid(AppLocalizations localizations) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final notificationService = Provider.of<NotificationService>(context, listen: false);

    if (_allModels.isEmpty) {
      return Center(
        child: Text(
          localizations.noModelsDownloaded,
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: screenWidth * 0.04,
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(screenWidth * 0.02),
          child: _buildSearchBar(localizations),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: GridView.builder(
              key: ValueKey<List<ModelInfo>>(_filteredModels),
              padding: EdgeInsets.all(screenWidth * 0.02),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: screenWidth * 0.02,
                mainAxisSpacing: screenWidth * 0.02,
                childAspectRatio: 0.75,
              ),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _filteredModels.length,
              itemBuilder: (context, index) {
                final model = _filteredModels[index];
                bool isServerSide = isServerSideModel(model.id);
                bool shouldFade = isServerSide &&
                    (!hasInternetConnection || _conversationLimitReached);

                return GestureDetector(
                  onTap: () {
                    if (isServerSide) {
                      if (!hasInternetConnection) {
                        notificationService.showNotification(
                          message: localizations.internetRequired,
                          isSuccess: false,
                          fontSize: 0.032,
                        );
                        return;
                      }
                      if (_conversationLimitReached) {
                        notificationService.showNotification(
                          message: localizations.youReachedConversationLimit,
                          isSuccess: false,
                          fontSize: 0.032,
                        );
                        return;
                      }
                    }
                    _selectModel(model);
                    _scrollToBottom(forceScroll: true);
                  },
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: shouldFade ? 0.5 : 1.0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.quaternaryColor,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(2, 2),
                          ),
                        ],
                        border: Border.all(
                          color: AppColors.opposedPrimaryColor.withOpacity(0.3),
                        ),
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
                              color: AppColors.opposedPrimaryColor,
                              fontSize: screenWidth * 0.035,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: screenHeight * 0.005),
                          Text(
                            model.producer,
                            style: TextStyle(
                              color: AppColors.opposedPrimaryColor.withOpacity(0.6),
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
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSkeletonModelGrid() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(screenWidth * 0.02),
          child: Shimmer.fromColors(
            baseColor: AppColors.shimmerBase,
            highlightColor: AppColors.shimmerHighlight,
            child: Container(
              height: screenHeight * 0.06,
              decoration: BoxDecoration(
                color: AppColors.shimmerBase,
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
                baseColor: AppColors.shimmerBase,
                highlightColor: AppColors.shimmerHighlight,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.shimmerBase,
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

  Future<void> _updateInternetStatus() async {
    bool connection = await InternetConnection().hasInternetAccess;
    setState(() {
      hasInternetConnection = connection;
    });
  }

  Future<void> _updateChatErrorState() async {
    bool limitExceeded = _serverSideConversationsCount >= _serverSideConversationLimit;
  }

  void _showInternetRequiredNotification() {
    final localizations = AppLocalizations.of(context)!;

    final notificationService =
    Provider.of<NotificationService>(context, listen: false);

    notificationService.showNotification(
      message: localizations.internetRequired,
      isSuccess: false,
      fontSize: 0.032,
      duration: const Duration(seconds: 2),
    );
  }

  AppBar _buildAppBar(BuildContext context, AppLocalizations localizations) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return AppBar(
      toolbarHeight: screenHeight * 0.08,
      backgroundColor: AppColors.background,
      centerTitle: true,
      scrolledUnderElevation: 0,
      leading: isModelSelected
          ? IconButton(
        key: _exitButtonKey,
        icon: Icon(
          Icons.arrow_back,
          color: AppColors.opposedPrimaryColor,
          size: screenWidth * 0.06,
        ),
        onPressed: () async {
          if (_extensionOverlayEntry != null) {
            setState(() {
              _extensionPanelIsClosing = true;
            });
            await Future.delayed(const Duration(milliseconds: 300));
            removeExtensionOverlay();
          }
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
          : _buildCreditsHexagonRow(),
      title: GestureDetector(
        onTap: () {
          if (isModelSelected) {
            if (_extensionOverlayEntry == null) {
              _insertExtensionPanel();
            } else {
              setState(() {
                _extensionPanelIsClosing = true;
              });
            }
          }
        },
        child: isModelSelected
            ? LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth;
            final textStyle = GoogleFonts.heebo(
              fontSize: screenWidth * 0.055,
              color: AppColors.opposedPrimaryColor,
              fontWeight: FontWeight.w600,
            );
            final textSpan = TextSpan(
              text: modelTitle ?? '',
              style: textStyle,
            );
            final textPainter = TextPainter(
              text: textSpan,
              textDirection: TextDirection.ltr,
            )..layout();
            final textWidth = textPainter.width;
            final extensionLeftPosition =
                (maxWidth / 2) - (textWidth / 2) + textWidth;

            return Stack(
              children: [
                Center(child: Text(modelTitle ?? '', style: textStyle)),
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: extensionLeftPosition,
                  child: Align(
                    alignment: Alignment.center,
                    child: _buildModelExtensionSelector(),
                  ),
                ),
              ],
            );
          },
        )
            : Text(
          localizations.appTitle,
          style: GoogleFonts.mavenPro(
            color: AppColors.opposedPrimaryColor,
            fontSize: screenWidth * 0.08,
          ),
        ),
      ),
      actions: <Widget>[
        GestureDetector(
          key: _accountButtonKey,
          onTap: () async {
            _navigateToScreen(
              context,
              const AccountScreen(),
              direction: const Offset(1.0, 0.0));
          },
          behavior: HitTestBehavior.translucent,
          child: Container(
            width: 50,
            height: 50,
            alignment: Alignment.center,
            margin: const EdgeInsets.only(left: 5, bottom: 5),
            child: Transform.translate(
              offset: Offset(-screenWidth * 0.02, screenHeight * 0.005),
              child: Transform.translate(
            offset: Offset(-screenWidth * 0.0, screenHeight * 0.003),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.border,
                  width: 1.0,
                ),
              ),
              child: CircleAvatar(
                radius: screenWidth * 0.05,
                backgroundColor: AppColors.quaternaryColor,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  child: Text(
                    _userData != null &&
                        _userData!['username'] != null &&
                        (_userData!['username'] as String).isNotEmpty
                        ? (_userData!['username'] as String)[0].toUpperCase()
                        : '?',
                    key: ValueKey<String>(
                      _userData != null &&
                          _userData!['username'] != null &&
                          (_userData!['username'] as String).isNotEmpty
                          ? (_userData!['username'] as String)[0].toUpperCase()
                          : '?',
                    ),
                    style: TextStyle(
                      fontSize: screenWidth * 0.045,
                      color: AppColors.opposedPrimaryColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
            ),
          ),
        ),
      ],
      flexibleSpace: Container(),
    );
  }

// 7. _buildCreditsHexagonRow()
// Artık krediler için kullanılan arka plan ve kenarlık renkleri, AppColors.creditsBackground ve AppColors.border üzerinden ayarlanıyor.
  Widget _buildCreditsHexagonRow() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Padding(
      padding: EdgeInsets.only(top: screenHeight * 0.001),
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
                  color: AppColors.quaternaryColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.border,
                    width: 0.5,
                  ),
                ),
                child: Row(
                  children: [
                    const Spacer(),
                    Container(
                      padding: EdgeInsets.all(screenWidth * 0.01),
                      decoration: BoxDecoration(
                        color: AppColors.quaternaryColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: SvgPicture.asset(
                        'assets/credit.svg',
                        width: screenWidth * 0.05,
                        height: screenWidth * 0.05,
                        color: AppColors.opposedPrimaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: screenHeight * 0.0129,
              left: screenWidth * 0.02,
              child: _buildHexagonButton(),
            ),
            Positioned(
              top: screenHeight * 0.0129,
              left: screenWidth * 0.115,
              child: Container(
                width: screenWidth * 0.12,
                height: screenHeight * 0.045,
                child: Center(
                  child: Text(
                    '${_credits + _bonusCredits}',
                    style: TextStyle(
                      fontSize: screenWidth * 0.04,
                      fontWeight: FontWeight.bold,
                      color: AppColors.opposedPrimaryColor,
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

// 8. _buildHexagonButton()
// Butonun dolgu ve kenarlık rengi artık AppColors.hexagon ve AppColors.border üzerinden alınıyor.
  Widget _buildHexagonButton() {
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
              _navigateToScreen(context, PremiumScreen(), direction: const Offset(0.0, 1.0));
            },
            child: CustomPaint(
              painter: HexagonBorderPainter(
                fillColor: AppColors.quaternaryColor,
                borderColor: AppColors.border,
                strokeWidth: 1.5,
              ),
              child: Padding(
                padding: EdgeInsets.all(screenWidth * 0.02),
                child: SvgPicture.asset(
                  'assets/sparkle.svg',
                  color: AppColors.opposedPrimaryColor,
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

  Widget _buildChatScreen(AppLocalizations localizations) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    if (messages.isEmpty) {
      return Center(
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
                  style: GoogleFonts.heebo(
                    fontSize: screenWidth * 0.05,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              SizedBox(height: screenHeight * 0.02),
            ],
          ),
        ),
      );
    } else {
      return Column(
        children: [
          Expanded(child: _buildMessagesList()),
        ],
      );
    }
  }

  Widget _buildMessagesList() {
    final screenHeight = MediaQuery.of(context).size.height;

    return ListView.separated(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(vertical: screenHeight * 0.01),
      itemCount: messages.length,
      separatorBuilder: (context, index) {
        return SizedBox(height: screenHeight * 0.005);
      },
      itemBuilder: (context, index) {
        return _buildMessageTile(messages[index], index);
      },
    );
  }

  Widget _buildMessageTile(Message message, int index) {
    return message.isUserMessage
        ? _buildUserMessageTile(message, index)
        : _buildAIMessageTile(message, index);
  }

  Widget _buildUserMessageTile(Message message, int index) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final key = ValueKey<Message>(message);
    List<Widget> children = [];

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
                    return Shimmer.fromColors(
                      baseColor: AppColors.shimmerBase,
                      highlightColor: AppColors.shimmerHighlight,
                      child: Container(
                        width: screenWidth * 0.4,
                        height: screenWidth * 0.4,
                        color: Colors.white,
                      ),
                    );
                  } else {
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

    if (message.text.trim().isNotEmpty) {
      children.add(
        UserMessageTile(
          key: key,
          text: message.text,
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

  Widget _buildAIMessageTile(Message message, int index) {
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
          onStop: _stopResponse,
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

  Widget _buildSearchBar(AppLocalizations localizations) {
    final screenWidth = MediaQuery.of(context).size.width;
    return TextField(
      cursorColor: Colors.white,
      decoration: InputDecoration(
        hintText: localizations.searchHint,
        hintStyle: TextStyle(
          color: AppColors.opposedPrimaryColor,
          fontSize: screenWidth * 0.04,
        ),
        prefixIcon: Icon(
          Icons.search,
          color: AppColors.opposedPrimaryColor,
          size: screenWidth * 0.06,
        ),
        filled: true,
        fillColor: AppColors.quaternaryColor,
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
            color: AppColors.border,
          ),
        ),
        contentPadding: EdgeInsets.zero,
      ),
      style: TextStyle(
        color: Colors.white,
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
  final Duration fadeInDuration;

  const FadeInText({
    Key? key,
    required this.text,
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
          color: AppColors.opposedPrimaryColor,
          fontSize: 16,
        ),
      ),
    );
  }
}