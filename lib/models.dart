// models.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'chart.dart';
import 'model.dart';
import 'notifications.dart';
import 'theme.dart';
import 'data.dart';
import 'download.dart';
import 'main.dart';
import 'system_info.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:shimmer/shimmer.dart';
import 'package:collection/collection.dart';

/// Model için sistemin yetersiz veya uyumlu olduğunu gösterir.
enum CompatibilityStatus {
  compatible,
  insufficientRAM,
  insufficientStorage,
}

/// Her modele ait indirilebilir durumları yönetir.
/// [isDownloading], [isPaused], [progress], [isDownloaded] gibi alanları tutar.
class DownloadManager extends ChangeNotifier {
  bool isDownloading = false;
  bool isPaused = false;
  bool isDownloaded = false;
  double progress = 0.0; // 0..100

  // Yardımcı fonksiyonlar
  void setDownloading(bool val) {
    isDownloading = val;
    notifyListeners();
  }

  void setPaused(bool val) {
    isPaused = val;
    notifyListeners();
  }

  void setDownloaded(bool val) {
    isDownloaded = val;
    notifyListeners();
  }

  void setProgress(double val) {
    progress = val;
    notifyListeners();
  }
}

/// İndirilen modelleri yöneten tekil (singleton) class.
class DownloadedModelsManager {
  static final DownloadedModelsManager _instance =
  DownloadedModelsManager._internal();
  factory DownloadedModelsManager() => _instance;
  DownloadedModelsManager._internal();

  List<DownloadedModel> downloadedModels = [];
}

/// İndirilen modelin basit verileri
class DownloadedModel {
  final String name;
  final String image;

  DownloadedModel({required this.name, required this.image});
}

class SearchResultItem extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration delay;
  final bool isExiting; // New flag to trigger exit animation

  const SearchResultItem({
    Key? key,
    required this.child,
    required this.index,
    required this.delay,
    this.isExiting = false,
  }) : super(key: key);

  @override
  _SearchResultItemState createState() => _SearchResultItemState();
}

class _SearchResultItemState extends State<SearchResultItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);

    if (!widget.isExiting) {
      // Enter animation
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    } else {
      // Start exit animation immediately
      _controller.value = 1.0;
      _controller.reverse();
    }
  }

  @override
  void didUpdateWidget(SearchResultItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExiting && !oldWidget.isExiting) {
      _controller.reverse();
    }
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
      child: widget.child,
    );
  }
}

class ModelsScreen extends StatefulWidget{
  const ModelsScreen({Key? key}) : super(key: key);

  @override
  _ModelsScreenState createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver  {
  final downloadedModelsManager = DownloadedModelsManager();

  // Key: model id, Value: DownloadManager (her modelin indirme durumunu izliyoruz)
  final Map<String, DownloadManager> _downloadManagers = {};

  // Her modelin disk üzerinde tam indirilmiş olup olmadığını tutar
  late Map<String, bool> _downloadCompleted;

  // İndirme task ID'lerini model ID'lerine göre saklar
  late Map<String, String> _downloadTaskIds;
  Map<String, List<GlobalKey>> columnKeysMap = {};
  Map<String, double> pageViewHeights = {};
  bool heightsMeasured = false;
  SystemInfoData? _systemInfo;
  String? _selectedModelTitle;

  late List<Map<String, dynamic>> _models;
  List<Map<String, dynamic>> _myModels = [];
  List<Map<String, dynamic>> _roleModels = [];

  late String _filesDirectoryPath;
  int _globalButtonClickCount = 0;
  bool _isGlobalButtonLocked = false;
  Timer? _resetClickCountTimer;

  bool _isLoading = true;

  static List<Map<String, dynamic>>? _cachedModels;
  static List<Map<String, dynamic>>? _cachedMyModels;

  TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  List<Map<String, dynamic>> _prevSearchResults = [];
  List<Map<String, dynamic>> _exitingItems = [];

  Timer? _downloadStatusTimer;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _downloadCompleted = {};
    _downloadTaskIds = {};

    // Arama metni dinleme
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });

    // Dizini başlatma
    _initializeDirectory().then((_) async {
      await _loadSystemInfo();
      await _loadSelectedModel();
      _initializeDownloadedModels();
      _checkDownloadStates();
      _checkDownloadingStates();

      // Model dosyalarının varlığını kontrol edelim (lokal modeller için)
      for (var model in _models) {
        if (!(model['isServerSide'] ?? false)) {
          _checkFileExists(model['id']);
        }
      }

      // Kullanıcı tarafından eklenen (custom) modelleri yükle
      await _initializeMyModels();

      // Tüm DownloadManager'ları başlat
      for (var model in _models) {
        String id = model['id'];
        if (!_downloadManagers.containsKey(id)) {
          _downloadManagers[id] = DownloadManager();
          _downloadManagers[id]!.isDownloaded = _downloadCompleted[id] ?? false;
        }
      }

      // Custom modeller için DownloadManager başlat
      for (var model in _myModels) {
        String id = model['id'];
        if (!_downloadManagers.containsKey(id)) {
          _downloadManagers[id] = DownloadManager();
          _downloadManagers[id]!.isDownloaded = _downloadCompleted[id] ?? false;
        }
      }

      // Yükseklik ölçümü
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!heightsMeasured) {
          _measureColumnHeights('localModels');
          _measureColumnHeights('serverSideModels');
          _measureColumnHeights('myModels');
          heightsMeasured = true;
        }
      });

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });

    _downloadStatusTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      _checkDownloadingStates();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Eğer sabit modeller daha önce yüklenmişse, cache’den alıyoruz.
    if (_cachedModels != null && _cachedModels!.isNotEmpty) {
      _models = _cachedModels!;
      _roleModels = _models.where((model) => model['category'] == 'roleplay').toList();
      // Cache varsa yükleme tamamlanmış kabul edelim.
      setState(() {
        _isLoading = false;
      });
    } else {
      // İlk defa yükleme: ModelData.models(context) çağırıyoruz.
      _models = ModelData.models(context);
      _cachedModels = _models;
      _roleModels = _models.where((model) => model['category'] == 'roleplay').toList();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _resetClickCountTimer?.cancel();
    _downloadStatusTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // On resume, refresh download states immediately
      _checkDownloadStates();
      _checkDownloadingStates();
    }
  }

  /// Uygulamanın doküman dizinini al
  Future<void> _initializeDirectory() async {
    Directory appDocDir = await getApplicationDocumentsDirectory();
    _filesDirectoryPath = appDocDir.path;
    debugPrint("Dosyalar $_filesDirectoryPath dizinine kaydedilecek.");
  }

  Future<void> _initializeMyModels() async {
    // Eğer custom modeller daha önce cache'e alındıysa, tekrar yüklemeye gerek yok.
    if (_cachedMyModels != null && _cachedMyModels!.isNotEmpty) {
      setState(() {
        _myModels = _cachedMyModels!;
      });
      return;
    }

    Directory dir = Directory(_filesDirectoryPath);
    List<FileSystemEntity> files = await dir.list().toList();
    List<File> ggufFiles = files
        .whereType<File>()
        .where((file) => file.path.endsWith('.gguf'))
        .toList();

    List<String> predefinedModelPaths =
    _models.map((model) => _getFilePathById(model['id'])).toList();

    setState(() {
      _myModels = ggufFiles
          .where((file) => !predefinedModelPaths.contains(file.path))
          .map((file) {
        String fileName = path.basename(file.path);
        String title = path.basenameWithoutExtension(fileName);
        String id = 'custom_$title';
        return {
          'id': id,
          'title': title,
          'description': AppLocalizations.of(context)!.myModelDescription,
          'size': '${(file.lengthSync() / 1024).toStringAsFixed(2)} KB',
          'image': 'assets/customai.png',
          'path': file.path,
        };
      }).toList();
    });

    _cachedMyModels = _myModels;
  }

  Future<void> _loadSystemInfo() async {
    try {
      final systemInfo = await SystemInfoProvider.fetchSystemInfo();
      if (mounted) {
        setState(() {
          _systemInfo = systemInfo;
        });
      }
    } catch (e) {
      debugPrint('Sistem bilgisi alınırken hata oluştu: $e');
    }
  }

  /// Kullanıcının en son seçtiği modeli hafızadan okur
  Future<void> _loadSelectedModel() async {
    final prefs = await SharedPreferences.getInstance();
    String? selectedModelId = prefs.getString('selected_model_id');
    String? selectedModelPath = prefs.getString('selected_model_path');
    if (selectedModelId != null && selectedModelPath != null) {
      if (mounted) {
        setState(() {
          _selectedModelTitle = _getTitleById(selectedModelId);
        });
      }
    }
  }

  /// Diskte indirilmiş modeller listesi
  void _initializeDownloadedModels() {
    downloadedModelsManager.downloadedModels.clear();
    for (var model in _models) {
      String id = model['id'];
      if ((_downloadCompleted[id] == true) || (model['isServerSide'] ?? false)) {
        downloadedModelsManager.downloadedModels.add(
          DownloadedModel(name: model['title'], image: model['image']),
        );
      }
    }
  }

  /// Gerekli RAM ve depolama durumunu kontrol eder
  CompatibilityStatus _getCompatibilityStatus(String title, String size) {
    if (_systemInfo == null) {
      return CompatibilityStatus.insufficientRAM;
    }
    final int requiredSizeMB = _parseSizeToMB(size);
    final int ramGB = (_systemInfo!.deviceMemory / 1024).floor();
    final bool isRAMSufficient;
    final bool isStorageSufficient =
        (_systemInfo!.freeStorage / 1024) >= (requiredSizeMB / 1024);

    // Basit bir RAM kontrolü
    if (ramGB <= 3) {
      isRAMSufficient = title == 'TinyLlama';
    } else if (ramGB <= 4) {
      isRAMSufficient = title == 'TinyLlama' || title == 'Phi-2-Instruct-v1';
    } else if (ramGB < 8) {
      isRAMSufficient = title == 'TinyLlama' ||
          title == 'Phi-2-Instruct-v1' ||
          title == 'Mistral-7B-Turkish' ||
          title == 'Gemma';
    } else {
      isRAMSufficient = true;
    }

    if (!isRAMSufficient) return CompatibilityStatus.insufficientRAM;
    if (!isStorageSufficient) return CompatibilityStatus.insufficientStorage;
    return CompatibilityStatus.compatible;
  }

  /// "2.5 GB" -> 2500 MB çevirir
  int _parseSizeToMB(String size) {
    final sizeParts = size.split(' ');
    if (sizeParts.length < 2) return 0;
    final sizeValue = double.tryParse(sizeParts[0].replaceAll(',', '')) ?? 0.0;
    final unit = sizeParts[1].toUpperCase();
    switch (unit) {
      case 'GB':
        return (sizeValue * 1024).toInt();
      case 'MB':
        return sizeValue.toInt();
      default:
        return 0;
    }
  }

  /// PageView içerisindeki kolonların yükseklik ölçümleri
  void _measureColumnHeights(String section) {
    List<GlobalKey>? keys = columnKeysMap[section];
    if (keys == null) return;

    double maxHeight = 0.0;
    for (GlobalKey key in keys) {
      final RenderBox? renderBox =
      key.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        double height = renderBox.size.height;
        if (height > maxHeight) {
          maxHeight = height;
        }
      }
    }
    setState(() {
      // İsterseniz buradaki `- 48` değerini kaldırabilir veya değiştirebilirsiniz
      pageViewHeights[section] = maxHeight - 48;
    });
  }

  /// Model ID'sine göre dosya adını belirler (yerelde nereye kaydedeceğiz)
  String _getFilePathById(String id) {
    String title = _getTitleById(id);
    String sanitizedTitle = title.replaceAll(' ', '_');
    return path.join(_filesDirectoryPath, '$sanitizedTitle.gguf');
  }

  /// Model ID'sine göre model başlığını döndürür
  String _getTitleById(String id) {
    if (id.startsWith('custom_')) {
      return id.substring(7);
    } else {
      return _models.firstWhere((model) => model['id'] == id)['title'];
    }
  }

  /// Kullanıcının Cortex abonelik seviyesini al
  Future<int> _getCortexSubscriptionLevel() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;
    try {
      DocumentSnapshot userDoc =
      await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        return userDoc.get('hasCortexSubscription') ?? 0;
      }
      return 0;
    } catch (e) {
      debugPrint("hasCortexSubscription kontrolü sırasında hata: $e");
      return 0;
    }
  }

  /// Abonelik seviyesine göre kullanıcıya verilecek mesaj limitini döndürür
  int getMessageLimit(int subscriptionLevel) {
    switch (subscriptionLevel) {
      case 1:
        return 15;
      case 2:
        return 30;
      case 3:
        return 50;
      default:
        return 5;
    }
  }

  /// Modele uzun basıldığında açılan menü
  void _showModelOptions(
      String id,
      bool isServerSide,
      bool isCustomModel,
      String? modelPath,
      ) {
    final localizations = AppLocalizations.of(context)!;

    showModalBottomSheet(
      context: context,
      backgroundColor:
      Provider.of<ThemeProvider>(context, listen: false).isDarkTheme
          ? const Color(0xFF101010)
          : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(MediaQuery.of(context).size.width * 0.05),
        ),
      ),
      builder: (context) {
        final isDarkTheme =
            Provider.of<ThemeProvider>(context, listen: false).isDarkTheme;

        Map<String, dynamic>? modelData;
        if (isCustomModel) {
          modelData = _myModels.firstWhere((m) => m['id'] == id);
        } else {
          modelData = _models.firstWhere((m) => m['id'] == id);
        }

        return Padding(
          padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.04),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                margin: EdgeInsets.symmetric(
                  vertical: MediaQuery.of(context).size.width * 0.02,
                ),
                decoration: BoxDecoration(
                  color: isDarkTheme ? const Color(0xFF181818) : Colors.grey[200],
                  borderRadius: BorderRadius.circular(
                      MediaQuery.of(context).size.width * 0.03),
                ),
                child: ListTile(
                  title: Text(
                    localizations.viewModelInformations,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDarkTheme ? Colors.white : Colors.black,
                      fontSize: MediaQuery.of(context).size.width * 0.04,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    if (modelData != null) {
                      String description = modelData['description'] ?? '';
                      String imagePath = modelData['image'] ?? '';
                      String size = (isServerSide || isCustomModel)
                          ? ''
                          : (modelData['size'] ?? '');
                      String ram = (isServerSide || isCustomModel)
                          ? ''
                          : (modelData['ram'] ?? '');
                      String producer = (isServerSide || isCustomModel)
                          ? ''
                          : (modelData['producer'] ?? '');
                      String? url = isServerSide ? null : modelData['url'];

                      bool isDownloaded = isCustomModel
                          ? true
                          : (_downloadCompleted[id] ?? false);
                      DownloadManager? manager = _downloadManagers[id];

                      if (manager == null) return;
                      bool isDownloading = manager.isDownloading;

                      CompatibilityStatus compatibilityStatus = isServerSide
                          ? CompatibilityStatus.compatible
                          : (isCustomModel
                          ? CompatibilityStatus.compatible
                          : _getCompatibilityStatus(_getTitleById(id), size));

                      _openModelDetail(
                        id,
                        description,
                        imagePath,
                        size,
                        ram,
                        producer,
                        isServerSide,
                        isDownloaded,
                        isDownloading,
                        compatibilityStatus,
                        url,
                        isCustomModel: isCustomModel,
                        modelPath: modelPath,
                      );
                    }
                  },
                ),
              ),
              Container(
                width: double.infinity,
                margin: EdgeInsets.symmetric(
                  vertical: MediaQuery.of(context).size.width * 0.02,
                ),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(
                      MediaQuery.of(context).size.width * 0.03),
                ),
                child: ListTile(
                  title: Text(
                    localizations.removeModel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: MediaQuery.of(context).size.width * 0.04,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _removeModel(
                      id,
                      isCustomModel: isCustomModel,
                      modelPath: modelPath,
                    );
                  },
                ),
              ),
              Container(
                width: double.infinity,
                margin: EdgeInsets.symmetric(
                  vertical: MediaQuery.of(context).size.width * 0.02,
                ),
                decoration: BoxDecoration(
                  color:
                  isDarkTheme ? const Color(0xFF222222) : Colors.grey[200],
                  borderRadius: BorderRadius.circular(
                      MediaQuery.of(context).size.width * 0.03),
                ),
                child: ListTile(
                  title: Text(
                    localizations.cancel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDarkTheme ? Colors.white : Colors.black,
                      fontSize: MediaQuery.of(context).size.width * 0.04,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Kullanıcının kendi model ekleme butonu
  void _onAddButtonPressed() async {
    final localizations = AppLocalizations.of(context)!;

    bool hasConnection = await InternetConnection().hasInternetAccess;
    if (!hasConnection) {
      final notificationService =
      Provider.of<NotificationService>(context, listen: false);
      notificationService.showNotification(
        message: localizations.noInternetConnection,
        isSuccess: false,
        bottomOffset: 80,
      );
      return;
    }

    int cortexSubscriptionLevel = await _getCortexSubscriptionLevel();
    if (cortexSubscriptionLevel >= 1) {
      _showUploadModelDialog();
    } else {
      final notificationService =
      Provider.of<NotificationService>(context, listen: false);
      notificationService.showNotification(
        message: localizations.purchaseVertexPlusToUpload,
        isSuccess: false,
        bottomOffset: 80,
      );
    }
  }

  /// Model kartını (tek bir satır) oluşturan fonksiyon
  Widget _buildModelTile(
      String id,
      String title,
      String shortDescription,
      String description,
      String? url,
      String? size,
      String imagePath,
      String? requirements,
      String producer,
      bool isServerSide,
      bool isDarkTheme, {
        bool isCustomModel = false,
        String? modelPath,
        bool isLastInColumn = false,
        bool isSeeAll = false,
      }) {
    final localizations = AppLocalizations.of(context)!;

    final manager = _downloadManagers.putIfAbsent(id, () => DownloadManager());

    // Determine screen dimensions
    double screenWidth = MediaQuery.of(context).size.width;

    // Create the image widget with consistent sizing and styling
    String extension = path.extension(imagePath).toLowerCase();

    // Calculate image dimensions based on screen width
    double imageWidth = screenWidth * 0.12;
    double imageHeight = imageWidth;

    // Model görselini sarmalayan widget
    Widget imageWidget = ClipRRect(
      borderRadius: BorderRadius.circular(
        extension == '.png'
            ? 0.04 * screenWidth
            : 0.03 * screenWidth,
      ),
      child: Image.asset(
        imagePath,
        fit: BoxFit.cover,
        width: imageWidth,
        height: imageHeight,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: imageWidth,
            height: imageHeight,
            color: isDarkTheme ? Colors.grey[800] : Colors.grey[200],
            child: Icon(
              Icons.broken_image,
              color: isDarkTheme ? Colors.white : Colors.black,
              size: imageWidth * 0.48,
            ),
          );
        },
      ),
    );

    if (extension == '.png') {
      imageWidget = Center(child: imageWidget);
    }

    // Outer container for the image with additional styling
    imageWidget = Container(
      width: imageWidth + screenWidth * 0.025,
      height: imageHeight + screenWidth * 0.025,
      decoration: BoxDecoration(
        color: isDarkTheme ? const Color(0xFF141414) : Colors.grey[200],
        borderRadius: BorderRadius.circular(
          extension == '.png'
              ? 0.04 * screenWidth
              : 0.03 * screenWidth,
        ),
      ),
      child: imageWidget,
    );

    // Determine compatibility status
    CompatibilityStatus compatibilityStatus =
    _getCompatibilityStatus(title, size ?? '');

    return RawGestureDetector(
      gestures: {
        LongPressGestureRecognizer:
        GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(
            duration: const Duration(milliseconds: 100),
          ),
              (instance) {
            instance.onLongPress =
            (manager.isDownloaded && !isServerSide && !isCustomModel)
                ? () => _showModelOptions(id, isServerSide, isCustomModel, modelPath)
                : null;
          },
        ),
      },
      child: GestureDetector(
        onTap: () => _openModelDetail(
          id,
          description,
          imagePath,
          size ?? '',
          requirements ?? '',
          producer,
          isServerSide,
          manager.isDownloaded,
          manager.isDownloading,
          compatibilityStatus,
          url,
          isCustomModel: isCustomModel,
          modelPath: modelPath,
        ),
        onLongPress:
        (manager.isDownloaded && !isServerSide && !isCustomModel)
            ? () => _showModelOptions(id, isServerSide, isCustomModel, modelPath)
            : null,
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: screenWidth * 0.008,
            horizontal: screenWidth * 0.005,
          ),
          child: Column(
            children: [
              AnimatedContainer(
                padding: EdgeInsets.all(
                  isSeeAll
                      ? screenWidth * 0.01
                      : screenWidth * 0.005,
                ),
                duration: const Duration(seconds: 1),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start, // Align to start for consistency
                  children: [
                    // Left Image
                    imageWidget,
                    SizedBox(width: screenWidth * 0.014),
                    // Title and Description
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title
                          Text(
                            title,
                            style: TextStyle(
                              color: isDarkTheme ? Colors.white : Colors.black,
                              fontSize: screenWidth * 0.04,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: screenWidth * 0.005),
                          // Fixed Height Description replaced with FittedBox
                          LayoutBuilder(
                            builder: (context, constraints) {
                              return FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: constraints.maxWidth,
                                  ),
                                  child: Text(
                                    shortDescription,
                                    // Remove maxLines and overflow to allow FittedBox to handle it
                                    style: TextStyle(
                                      color: isDarkTheme ? Colors.white70 : Colors.black87,
                                      fontSize: screenWidth * 0.029,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: screenWidth * 0.01),
                    // Download Info and Button
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Progress Text
                        SizedBox(
                          width: screenWidth * 0.18,
                          height: screenWidth * 0.04,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: AnimatedBuilder(
                              animation: manager,
                              builder: (context, _) {
                                Widget textWidget;
                                if (manager.isDownloading) {
                                  textWidget = FittedBox(
                                    key: const ValueKey<String>('downloading'),
                                    child: Text(
                                      manager.progress >= 95
                                          ? localizations.finalPreparation
                                          : localizations.downloaded(
                                        manager.progress.toStringAsFixed(0),
                                      ),
                                      style: TextStyle(
                                        color: isDarkTheme ? Colors.white : Colors.black,
                                        fontSize: screenWidth * 0.03,
                                      ),
                                    ),
                                  );
                                } else if (manager.isPaused) {
                                  textWidget = FittedBox(
                                    key: const ValueKey<String>('paused'),
                                    child: Text(
                                      localizations.downloadPaused,
                                      style: TextStyle(
                                        color: isDarkTheme ? Colors.white : Colors.black,
                                        fontSize: screenWidth * 0.03,
                                      ),
                                    ),
                                  );
                                } else {
                                  textWidget = const SizedBox(
                                    key: ValueKey<String>('empty'),
                                  );
                                }

                                return AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 300),
                                  transitionBuilder: (child, animation) => FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),
                                  child: textWidget,
                                );
                              },
                            ),
                          ),
                        ),
                        SizedBox(height: screenWidth * 0.005),
                        // Download Button
                        SizedBox(
                          width: screenWidth * 0.2,
                          height: screenWidth * 0.09,
                          child: AnimatedBuilder(
                            animation: manager,
                            builder: (context, _) {
                              return AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                transitionBuilder: (child, animation) => FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                                child: _buildButtonByState(
                                  id: id,
                                  manager: manager,
                                  isDarkTheme: isDarkTheme,
                                  isServerSide: isServerSide,
                                  isCustomModel: isCustomModel,
                                  compatibilityStatus: compatibilityStatus,
                                  url: url,
                                  title: title,
                                  modelPath: modelPath,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Ekstra boşluk eklemek için aşağıdaki SizedBox'ı kullanabilirsiniz
              // Özellikle listenin son elemanı değilse
              if (!isLastInColumn)
                SizedBox(height: screenWidth * 0.01),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButtonByState({
    required String id,
    required DownloadManager manager,
    required bool isDarkTheme,
    required bool isServerSide,
    required bool isCustomModel,
    required CompatibilityStatus compatibilityStatus,
    required String? url,
    required String title,
    required String? modelPath,
  }) {
    final localizations = AppLocalizations.of(context)!;
    double screenWidth = MediaQuery.of(context).size.width;

    // Common sizes
    double buttonHeight = screenWidth * 0.09;
    double buttonWidth = screenWidth * 0.25;
    double commonBorderRadius = screenWidth * 0.08;

    // If it’s already downloaded or a custom model => “Chat”
    if (manager.isDownloaded || isCustomModel) {
      return SizedBox(
        key: ValueKey('chatButton-$id'),
        width: buttonWidth,
        height: buttonHeight,
        child: ElevatedButton(
          onPressed: () => _startChatWithModel(
            id,
            isServerSide,
            isCustomModel: isCustomModel,
            modelPath: modelPath,
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: isDarkTheme ? const Color(0xFF0D31FE) : const Color(0xFF0D62FE),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(commonBorderRadius),
            ),
            padding: EdgeInsets.zero,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              localizations.chat,
              style: TextStyle(
                color: Colors.white,
                fontSize: screenWidth * 0.035,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }

    // If it’s a server-side model => also just “Chat”
    if (isServerSide) {
      return SizedBox(
        key: ValueKey('serverChat-$id'),
        width: buttonWidth,
        height: buttonHeight,
        child: ElevatedButton(
          onPressed: () => _startChatWithModel(id, isServerSide),
          style: ElevatedButton.styleFrom(
            backgroundColor: isDarkTheme ? const Color(0xFF0D31FE) : const Color(0xFF0D62FE),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(commonBorderRadius),
            ),
            padding: EdgeInsets.zero,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              localizations.chat,
              style: TextStyle(
                color: Colors.white,
                fontSize: screenWidth * 0.035,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }

    // If the model is currently downloading => “Cancel”
    if (manager.isDownloading) {
      return SizedBox(
        key: ValueKey('cancelButton-$id'),
        width: buttonWidth,
        height: buttonHeight,
        child: ElevatedButton(
          onPressed: () => _handleButtonPress(() => _cancelDownload(id), id),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(commonBorderRadius),
            ),
            padding: EdgeInsets.zero,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              localizations.cancel,
              style: TextStyle(
                color: Colors.white,
                fontSize: screenWidth * 0.035,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }

    // If the download is paused => “Resume”
    if (manager.isPaused) {
      return SizedBox(
        key: ValueKey('resumeButton-$id'),
        width: buttonWidth,
        height: buttonHeight,
        child: ElevatedButton(
          onPressed: () => _resumeDownload(id),
          style: ElevatedButton.styleFrom(
            backgroundColor: isDarkTheme ? const Color(0xFF0D31FE) : const Color(0xFF0D62FE),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(commonBorderRadius),
            ),
            padding: EdgeInsets.zero,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              localizations.resume,
              style: TextStyle(
                color: Colors.white,
                fontSize: screenWidth * 0.035,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }

    // Otherwise => “Download” or "Insufficient..."
    bool isCompatible = (compatibilityStatus == CompatibilityStatus.compatible);
    String text;
    Color bgColor;
    Color textColor;
    double fontSize = screenWidth * 0.035;

    if (!isCompatible) {
      if (compatibilityStatus == CompatibilityStatus.insufficientRAM) {
        text = localizations.insufficientRAM;
      } else {
        text = localizations.insufficientStorage;
      }
      bgColor = Colors.grey;
      textColor = Colors.black;
      fontSize = screenWidth * 0.025;
    } else {
      text = localizations.download;
      bgColor = isDarkTheme ? Colors.white : Colors.black;
      textColor = isDarkTheme ? Colors.black : Colors.white;
    }

    return SizedBox(
      key: ValueKey('downloadButton-$id'),
      width: buttonWidth,
      height: buttonHeight,
      child: ElevatedButton(
        onPressed: isCompatible
            ? () => _handleButtonPress(() => _downloadModel(id, url, title), id)
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(commonBorderRadius),
          ),
          padding: EdgeInsets.zero,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            style: TextStyle(
              color: textColor,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  void _startChatWithModel(
      String id,
      bool isServerSide, {
        bool isCustomModel = false,
        String? modelPath,
      }) async {
    final localizations = AppLocalizations.of(context)!;

    if (isServerSide) {
      bool hasConnection = await InternetConnection().hasInternetAccess;
      if (!hasConnection) {
        final notificationService = Provider.of<NotificationService>(context, listen: false);
        notificationService.showNotification(
          message: localizations.noInternetConnection,
          isSuccess: false,
        );
        return;
      }
    }

    // 1) Set the chosen model in SharedPreferences
    await _selectModel(
      id,
      isServerSide,
      isCustomModel: isCustomModel,
      modelPath: modelPath,
    );

    // 2) Go to the chat screen tab (index 0)
    mainScreenKey.currentState?.onItemTapped(0);

    // 3) Hide the BottomAppBar right away
    mainScreenKey.currentState?.updateBottomAppBarVisibility(false);

    // 4) Notify ChatScreen about the new model
    Future.delayed(const Duration(milliseconds: 500), () {
      mainScreenKey.currentState?.chatScreenKey.currentState?.updateModelData(
        id: id,
        title: _getTitleById(id),
        description: isCustomModel
            ? localizations.myModelDescription
            : _models.firstWhere((m) => m['id'] == id)['description'],
        imagePath: isCustomModel
            ? 'assets/customai.png'
            : _models.firstWhere((m) => m['id'] == id)['image'],
        producer: isCustomModel
            ? ''
            : _models.firstWhere((m) => m['id'] == id)['producer'],
        path: isServerSide
            ? null
            : (isCustomModel ? modelPath : _getFilePathById(id)),
        isServerSide: isServerSide,
      );
      mainScreenKey.currentState?.chatScreenKey.currentState
          ?.resetConversation(resetModel: false);
    });
  }

  /// Model detay sayfasını açar (ModelDetailPage)
  Future<void> _openModelDetail(
      String id,
      String description,
      String imagePath,
      String size,
      String ram,
      String producer,
      bool isServerSide,
      bool isDownloaded,
      bool isDownloading,
      CompatibilityStatus compatibilityStatus,
      String? url, {
        bool isCustomModel = false,
        String? modelPath,
      }) async {
    final localizations = AppLocalizations.of(context)!;
    final modelData = isCustomModel
        ? _myModels.firstWhere((m) => m['id'] == id)
        : _models.firstWhere((m) => m['id'] == id);

    final result = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => ModelDetailPage(
          id: id,
          title: _getTitleById(id),
          description: description,
          imagePath: imagePath,
          size: size,
          ram: ram,
          isDownloaded: isDownloaded,
          isDownloading: isDownloading,
          compatibilityStatus: compatibilityStatus,
          isServerSide: isServerSide,
          onDownloadPressed: () => _downloadModel(id, url, _getTitleById(id)),
          onRemovePressed: () async => await _removeModel(
            id,
            isCustomModel: isCustomModel,
            modelPath: modelPath,
          ),
          onChatPressed: () async {
            // Modeli seç
            await _selectModel(
              id,
              isServerSide,
              isCustomModel: isCustomModel,
              modelPath: modelPath,
            );
            mainScreenKey.currentState?.onItemTapped(0);

            Future.delayed(const Duration(milliseconds: 500), () {
              mainScreenKey.currentState?.chatScreenKey.currentState
                  ?.updateModelData(
                id: id,
                title: _getTitleById(id),
                description: isCustomModel
                    ? localizations.myModelDescription
                    : _models.firstWhere((m) => m['id'] == id)['description'],
                imagePath: isCustomModel
                    ? 'assets/customai.png'
                    : _models.firstWhere((m) => m['id'] == id)['image'],
                producer: isCustomModel
                    ? ''
                    : _models.firstWhere((m) => m['id'] == id)['producer'],
                path: isServerSide
                    ? null
                    : (isCustomModel ? modelPath : _getFilePathById(id)),
                isServerSide: isServerSide,
              );
              mainScreenKey.currentState?.chatScreenKey.currentState
                  ?.resetConversation(resetModel: false);
            });
            Navigator.pop(context);
          },
          onCancelPressed: () => _cancelDownload(id),
          downloadManager: _downloadManagers[id],
          stars: modelData['stars'] ?? '',
          features: modelData['features'] ?? '',
          category: modelData['category'] ?? '',
          canHandleImage: modelData['canHandleImage'] ?? false,
          producer: modelData['producer'] ?? '',
          parameters: modelData['parameters'] ?? '',
          context: modelData['context'] ?? '',
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.ease;
          var tween = Tween(begin: begin, end: end).chain(
            CurveTween(curve: curve),
          );
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );

    if (result == 'model_updated') {
      _checkDownloadStates();
      _checkDownloadingStates();
    }
  }

  Future<void> _downloadModel(String id, String? url, String title) async {
    final localizations = AppLocalizations.of(context)!;
    if (url == null) return;

    bool hasConnection = await InternetConnection().hasInternetAccess;
    if (!hasConnection) {
      final notificationService =
      Provider.of<NotificationService>(context, listen: false);
      notificationService.showNotification(
        message: localizations.noInternetConnection,
        isSuccess: false,
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final filePath = _getFilePathById(id);

    if (!_downloadManagers.containsKey(id)) {
      _downloadManagers[id] = DownloadManager();
    }
    final manager = _downloadManagers[id]!;

    manager.setDownloading(true);
    manager.setPaused(false);
    manager.setProgress(0.0);

    String? taskId = await FileDownloadHelper().downloadModel(
      id: id,
      url: url,
      filePath: filePath,
      title: title,
      onProgress: (fileName, progress) {
        manager.setDownloading(true);
        manager.setProgress(progress);
      },
      onDownloadCompleted: (path) async {
        prefs.setBool('is_downloaded_$id', true);
        manager.setDownloading(false);
        manager.setDownloaded(true);
        manager.setPaused(false);
        manager.setProgress(100.0);

        // Listeyi güncelle
        Future.microtask(() async {
          _initializeDownloadedModels();
          await _initializeMyModels();
        });

        // İNDİRME TAMAMLANDIĞINDA CHAT'E HABER VER
        // Bu satır -> chat.dart içindeki downloadHelper.addListener(_loadModels) tetiklenecek:
        Provider.of<FileDownloadHelper>(context, listen: false).notifyListeners();
      },
      onDownloadError: (error) async {
        if (error.contains('Download could not be started')) {
          final notificationService =
          Provider.of<NotificationService>(context, listen: false);
          notificationService.showNotification(
            message: localizations.noInternetConnection,
            isSuccess: false,
          );
        }
        manager.setDownloading(false);
        manager.setPaused(false);
        manager.setProgress(0.0);
        prefs.setBool('is_downloading_$id', false);
      },
      onDownloadPaused: () {
        manager.setDownloading(false);
        manager.setPaused(true);
      },
    );

    if (taskId != null) {
      _downloadTaskIds[id] = taskId;
      prefs.setString('download_task_id_$id', taskId);
      prefs.setBool('is_downloading_$id', true);
    }
  }

  /// Kullanıcı çok hızlı tıklamasın diye global buton kilitleme
  void _handleButtonPress(VoidCallback action, String id) {
    final localizations = AppLocalizations.of(context)!;
    if (_isGlobalButtonLocked) {
      final notificationService =
      Provider.of<NotificationService>(context, listen: false);
      notificationService.showNotification(
        message: localizations.pleaseWaitBeforeTryingAgain,
        isSuccess: false,
      );
      return;
    }
    action();

    _globalButtonClickCount++;
    if (_globalButtonClickCount == 1) {
      _resetClickCountTimer = Timer(const Duration(seconds: 4), () {
        setState(() {
          _globalButtonClickCount = 0;
        });
      });
    }
    if (_globalButtonClickCount >= 4) {
      setState(() {
        _isGlobalButtonLocked = true;
        _globalButtonClickCount = 0;
      });
      _resetClickCountTimer?.cancel();
      Timer(const Duration(seconds: 3), () {
        setState(() {
          _isGlobalButtonLocked = false;
        });
      });
    }
  }

  /// Model dosyasının tam olarak indirildiğini doğrulamak için dosya varlığını,
  /// beklenen boyut karşılaştırması yaparak kontrol ediyoruz.
  Future<void> _checkFileExists(String id) async {
    final filePath = _getFilePathById(id);
    final file = File(filePath);
    final prefs = await SharedPreferences.getInstance();
    // Dosyanın indirme aşamasında olup olmadığını SharedPreferences üzerinden kontrol ediyoruz.
    final bool isDownloading = prefs.getBool('is_downloading_$id') ?? false;
    bool fileExists = await file.exists();

    // Model verilerini alıp beklenen dosya boyutunu hesaplıyoruz.
    Map<String, dynamic>? modelData;
    try {
      modelData = _models.firstWhere((m) => m['id'] == id);
    } catch (e) {
      modelData = null;
    }

    bool isFileComplete = false;
    if (fileExists) {
      if (modelData != null &&
          modelData.containsKey('size') &&
          (modelData['size'] as String).isNotEmpty) {
        int expectedSizeMB = _parseSizeToMB(modelData['size']);
        int expectedBytes = expectedSizeMB * 1024 * 1024;
        int actualBytes = await file.length();
        if (expectedBytes > 0) {
          isFileComplete = actualBytes >= (expectedBytes * 0.9);
        } else {
          isFileComplete = actualBytes > 0;
        }
      } else {
        isFileComplete = (await file.length()) > 0;
      }
    }

    if (fileExists && isFileComplete && !isDownloading) {
      _downloadCompleted[id] = true;
      if (_downloadManagers.containsKey(id)) {
        _downloadManagers[id]!.setDownloaded(true);
      }
      prefs.setBool('is_downloaded_$id', true);
    } else {
      prefs.setBool('is_downloading_$id', false);
      prefs.setBool('is_downloaded_$id', false);
      _downloadCompleted[id] = false;
      if (_downloadManagers.containsKey(id)) {
        _downloadManagers[id]!.setDownloaded(false);
        _downloadManagers[id]!.setDownloading(false);
        _downloadManagers[id]!.setPaused(false);
        _downloadManagers[id]!.setProgress(0.0);
      }
      downloadedModelsManager.downloadedModels
          .removeWhere((model) => model.name == _getTitleById(id));
    }
  }

  /// SharedPreferences üzerinden, modele ait indirme durumlarını yükler
  void _checkDownloadStates() async {
    final prefs = await SharedPreferences.getInstance();
    for (var model in _models) {
      String id = model['id'];
      bool isServerSide = model['isServerSide'] ?? false;
      if (isServerSide) continue;

      bool isDown = prefs.getBool('is_downloaded_$id') ?? false;
      _downloadCompleted[id] = isDown;
      if (_downloadManagers.containsKey(id)) {
        _downloadManagers[id]!.setDownloaded(isDown);
      }
      await _checkFileExists(id);
    }
    _initializeDownloadedModels();
  }

  /// Flutter Downloader üzerinden aktif indirme görevlerini kontrol eder
  void _checkDownloadingStates() async {
    final prefs = await SharedPreferences.getInstance();
    final tasks = await FlutterDownloader.loadTasks();

    if (tasks == null) return;

    for (var model in _models) {
      String id = model['id'];
      bool isServerSide = model['isServerSide'] ?? false;
      if (isServerSide) continue;

      String? taskId = prefs.getString('download_task_id_$id');
      if (taskId != null) {
        DownloadTask? task = tasks.firstWhereOrNull((t) => t.taskId == taskId);

        if (!_downloadManagers.containsKey(id)) {
          _downloadManagers[id] = DownloadManager();
        }
        final manager = _downloadManagers[id]!;

        if (task != null) {
          if (task.status == DownloadTaskStatus.running ||
              task.status == DownloadTaskStatus.enqueued) {
            manager.setDownloading(true);
            manager.setPaused(false);
            manager.setProgress(task.progress.toDouble());
          } else if (task.status == DownloadTaskStatus.paused) {
            manager.setDownloading(false);
            manager.setPaused(true);
            manager.setProgress(task.progress.toDouble());
          } else if (task.status == DownloadTaskStatus.complete) {
            manager.setDownloading(false);
            manager.setPaused(false);
            manager.setDownloaded(true);
            manager.setProgress(100.0);
            prefs.setBool('is_downloaded_$id', true);
            prefs.setBool('is_downloading_$id', false);
            prefs.remove('download_task_id_$id');
          } else if (task.status == DownloadTaskStatus.failed) {
            manager.setDownloading(false);
            manager.setPaused(false);
            manager.setProgress(0.0);
            prefs.setBool('is_downloading_$id', false);
            prefs.remove('download_task_id_$id');
          } else {
            // canceled vs.
            manager.setDownloading(false);
            manager.setPaused(false);
          }
        } else {
          manager.setDownloading(false);
          manager.setPaused(false);
        }
      } else {
        if (_downloadManagers.containsKey(id)) {
          _downloadManagers[id]!.setDownloading(false);
          _downloadManagers[id]!.setPaused(false);
        }
      }
    }
  }

  /// Modeli ve yerel dosyasını siler
  Future<void> _removeModel(
      String id, {
        bool isCustomModel = false,
        String? modelPath,
      }) async {
    final localizations = AppLocalizations.of(context)!;
    final prefs = await SharedPreferences.getInstance();

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        final isDarkTheme = Provider.of<ThemeProvider>(context).isDarkTheme;
        return AlertDialog(
          title: Text(
            localizations.removeModel,
            style: TextStyle(
              color: isDarkTheme ? Colors.white : Colors.black,
            ),
          ),
          content: Text(
            localizations.confirmRemoveModel(_getTitleById(id)),
            style: TextStyle(
              color: isDarkTheme ? Colors.white : Colors.black,
            ),
          ),
          backgroundColor: isDarkTheme ? Colors.grey[900] : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                localizations.cancel,
                style: TextStyle(
                  color: isDarkTheme ? Colors.white : Colors.blue,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                localizations.remove,
                style: TextStyle(
                  color: isDarkTheme ? Colors.white : Colors.red,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    final actualPath = isCustomModel ? modelPath! : _getFilePathById(id);
    final file = File(actualPath);

    if (await file.exists()) {
      try {
        await file.delete();
        prefs.setBool('is_downloaded_$id', false);

        if (_selectedModelTitle == _getTitleById(id)) {
          await prefs.remove('selected_model_path');
          await prefs.remove('selected_model_id');
          setState(() {
            _selectedModelTitle = null;
          });
          Provider.of<FileDownloadHelper>(context, listen: false).notifyListeners();
          mainScreenKey.currentState?.chatScreenKey.currentState?.clearModelSelection();
          mainScreenKey.currentState?.chatScreenKey.currentState?.resetModelCacheAndReload();
        }

        if (!isCustomModel) {
          _downloadCompleted[id] = false;
          if (_downloadManagers.containsKey(id)) {
            _downloadManagers[id]!.setDownloaded(false);
            _downloadManagers[id]!.setDownloading(false);
            _downloadManagers[id]!.setPaused(false);
            _downloadManagers[id]!.setProgress(0.0);
          }
          downloadedModelsManager.downloadedModels
              .removeWhere((m) => m.name == _getTitleById(id));
        } else {
          // Custom model listeden çıkar
          setState(() {
            _myModels.removeWhere((m) => m['id'] == id);
          });
        }
      } catch (e) {
        debugPrint("Dosya silme hatası: $e");
      }
    } else {
      prefs.setBool('is_downloaded_$id', false);
      if (!isCustomModel) {
        _downloadCompleted[id] = false;
        if (_downloadManagers.containsKey(id)) {
          _downloadManagers[id]!.setDownloaded(false);
          _downloadManagers[id]!.setDownloading(false);
          _downloadManagers[id]!.setPaused(false);
          _downloadManagers[id]!.setProgress(0.0);
        }
        downloadedModelsManager.downloadedModels
            .removeWhere((m) => m.name == _getTitleById(id));
      } else {
        setState(() {
          _myModels.removeWhere((m) => m['id'] == id);
        });
      }
    }
  }

  /// Modeli seçer (SharedPreferences'a kaydeder)
  Future<void> _selectModel(
      String id,
      bool isServerSide, {
        bool isCustomModel = false,
        String? modelPath,
      }) async {
    final prefs = await SharedPreferences.getInstance();
    String? filePath =
    isServerSide ? null : (isCustomModel ? modelPath : _getFilePathById(id));
    if (!isServerSide && filePath == null) {
      filePath = _getFilePathById(id);
    }
    await prefs.setString('selected_model_id', id);
    if (filePath != null) {
      await prefs.setString('selected_model_path', filePath);
    } else {
      await prefs.remove('selected_model_path');
    }
    setState(() {
      _selectedModelTitle = _getTitleById(id);
    });

    // Chat ekranına model bilgisini gönder
    final localizations = AppLocalizations.of(context)!;
    mainScreenKey.currentState?.chatScreenKey.currentState?.updateModelData(
      id: id,
      title: _getTitleById(id),
      description: isCustomModel
          ? localizations.myModelDescription
          : _models.firstWhere((m) => m['id'] == id)['description'],
      imagePath: isCustomModel
          ? 'assets/customai.png'
          : _models.firstWhere((m) => m['id'] == id)['image'],
      producer: isCustomModel
          ? ''
          : _models.firstWhere((m) => m['id'] == id)['producer'],
      path: isServerSide
          ? null
          : (isCustomModel ? modelPath : _getFilePathById(id)),
      isServerSide: isServerSide,
    );
  }

  /// İndirmeyi iptal et
  void _cancelDownload(String id) async {
    final prefs = await SharedPreferences.getInstance();
    String? taskId = _downloadTaskIds[id];

    if (_downloadManagers.containsKey(id)) {
      _downloadManagers[id]!.setDownloading(false);
      _downloadManagers[id]!.setPaused(false);
      _downloadManagers[id]!.setProgress(0.0);
    }

    if (taskId != null) {
      await FileDownloadHelper().cancelDownload(taskId);
      _downloadTaskIds.remove(id);
      prefs.remove('download_task_id_$id');
    }
    prefs.setBool('is_downloading_$id', false);
  }

  /// İndirmeyi devam ettir
  void _resumeDownload(String id) async {
    String? taskId = _downloadTaskIds[id];
    if (taskId != null) {
      String? newTaskId = await FileDownloadHelper().resumeDownload(taskId);
      if (newTaskId != null) {
        _downloadTaskIds[id] = newTaskId;
        final prefs = await SharedPreferences.getInstance();
        prefs.setString('download_task_id_$id', newTaskId);
        if (_downloadManagers.containsKey(id)) {
          _downloadManagers[id]!.setPaused(false);
          _downloadManagers[id]!.setDownloading(true);
        }
      }
    }
  }

  /// Model dosyası seçme (kullanıcının kendi .gguf dosyası)
  void _pickModelFile() async {
    final localizations = AppLocalizations.of(context)!;

    Navigator.of(context).pop();
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gguf'],
      );

      if (result != null && result.files.single.path != null) {
        String filePath = result.files.single.path!;
        String fileName = result.files.single.name;
        if (path.extension(fileName).toLowerCase() != '.gguf') {
          return;
        }
        String newFilePath =
        _getFilePathById('custom_${path.basenameWithoutExtension(fileName)}');
        File file = File(filePath);

        if (await File(newFilePath).exists()) {
          return;
        }
        await file.copy(newFilePath);

        setState(() {
          String title = path.basenameWithoutExtension(fileName);
          String id = 'custom_$title';
          _myModels.add({
            'id': id,
            'title': title,
            'description': localizations.myModelDescription,
            'size': '${(file.lengthSync() / 1024).toStringAsFixed(2)} KB',
            'image': 'assets/customai.png',
            'path': newFilePath,
          });
        });

        final notificationService =
        Provider.of<NotificationService>(context, listen: false);
        notificationService.showNotification(
          message: localizations.modelUploadedSuccessfully,
          isSuccess: true,
        );
      }
    } catch (e) {
      debugPrint("Dosya seçme veya kopyalama hatası: $e");
    }
  }

  /// Model yükleme diyaloğu (kullanıcının kendi dosyasını seçmesi)
  void _showUploadModelDialog() {
    final isDarkTheme = Provider.of<ThemeProvider>(context, listen: false).isDarkTheme;
    final localizations = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Center(
            child: Text(
              localizations.uploadYourOwnModel,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDarkTheme ? Colors.white : Colors.black,
                fontSize: 18,
              ),
            ),
          ),
          content: GestureDetector(
            onTap: _pickModelFile,
            child: Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                color: isDarkTheme ? Colors.grey[800] : Colors.grey[200],
                border: Border.all(
                  color: Colors.white,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.upload_file,
                    size: 50,
                    color: isDarkTheme ? Colors.white : Colors.blue,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    localizations.selectGGUFFile,
                    style: TextStyle(
                      color: isDarkTheme ? Colors.white70 : Colors.black54,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
          backgroundColor: isDarkTheme ? const Color(0xFF121212) : Colors.white,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Colors.white, width: 1),
            borderRadius: BorderRadius.circular(12.0),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(
                Icons.close,
                color: isDarkTheme ? Colors.white : Colors.blue,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Model kolonlarını (PageView) inşa ediyor
  List<Widget> _buildModelColumns(
      List<Map<String, dynamic>> models,
      bool isDarkTheme,
      String section,
      double screenWidth,
      ) {
    List<Widget> columns = [];
    int modelsPerColumn = 3;
    int totalModels = models.length;
    int totalColumns = (totalModels / modelsPerColumn).ceil();

    double cardWidth = screenWidth - 2 * screenWidth * 0.04;
    List<GlobalKey> columnKeys = [];

    for (int i = 0; i < totalColumns; i++) {
      int startIndex = i * modelsPerColumn;
      int endIndex = startIndex + modelsPerColumn;
      if (endIndex > totalModels) endIndex = totalModels;

      List<Map<String, dynamic>> columnModels = models.sublist(startIndex, endIndex);
      GlobalKey key = GlobalKey();
      columnKeys.add(key);

      columns.add(
        Container(
          key: key,
          width: cardWidth,
          child: Column(
            children: columnModels.map((model) {
              bool isLastInColumn = model == columnModels.last;
              bool isServerSide = model['isServerSide'] ?? false;
              bool isCustomModel = section == 'myModels';
              String id = model['id'] ?? '';
              String? url = isServerSide ? null : model['url'];
              String? size = isServerSide ? null : model['size'];
              String? requirements = isServerSide ? null : model['ram'];
              String producer = isServerSide ? '' : (model['producer'] ?? '');

              return _buildModelTile(
                id,
                model['title'],
                model['shortDescription'] ?? '',
                model['description'] ?? '',
                url,
                size,
                model['image'] ?? '',
                requirements,
                producer,
                isServerSide,
                isDarkTheme,
                isCustomModel: isCustomModel,
                modelPath: model['path'],
                isLastInColumn: isLastInColumn,
              );
            }).toList(),
          ),
        ),
      );
    }

    columnKeysMap[section] = columnKeys;
    return columns;
  }

  /// Shimmer skeleton (yükleme aşamasında)
  Widget _buildShimmerSkeleton(bool isDarkTheme) {
    final localizations = AppLocalizations.of(context)!;
    final List<String> shimmerCategories = [
      localizations.localModels,
      localizations.serverSideModels,
      localizations.roleModels,
      localizations.myModels,
    ];

    int totalItems = 1 + shimmerCategories.length * 4;
    double screenWidth = MediaQuery.of(context).size.width;

    return Shimmer.fromColors(
      baseColor: isDarkTheme ? Colors.grey[800]! : Colors.grey[300]!,
      highlightColor: isDarkTheme ? Colors.grey[700]! : Colors.grey[100]!,
      child: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: totalItems,
        itemBuilder: (context, index) {
          if (index == 0) {
            // Arama Çubuğu Placeholder
            return Padding(
              padding: EdgeInsets.symmetric(
                vertical: screenWidth * 0.02,
              ),
              child: Container(
                width: double.infinity,
                height: screenWidth * 0.1,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(screenWidth * 0.05),
                ),
              ),
            );
          } else {
            int adjustedIndex = index - 1;
            int categoryIndex = adjustedIndex ~/ 4;
            int itemIndex = adjustedIndex % 4;

            if (categoryIndex >= shimmerCategories.length) {
              return const SizedBox.shrink();
            }

            if (itemIndex == 0) {
              // Kategori Başlığı Placeholder
              return Padding(
                padding: EdgeInsets.only(
                  top: screenWidth * 0.04,
                  bottom: screenWidth * 0.015,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: screenWidth * 0.3,
                      height: screenWidth * 0.06,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                    ),
                  ],
                ),
              );
            } else {
              // Model Placeholder
              return Padding(
                padding: EdgeInsets.symmetric(
                  vertical: screenWidth * 0.02,
                ),
                child: Row(
                  children: [
                    Container(
                      width: screenWidth * 0.12,
                      height: screenWidth * 0.12,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                    ),
                    SizedBox(width: screenWidth * 0.025),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            height: screenWidth * 0.04,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                          ),
                          SizedBox(height: screenWidth * 0.015),
                          Container(
                            width: double.infinity,
                            height: screenWidth * 0.03,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                          ),
                          SizedBox(height: screenWidth * 0.015),
                          Container(
                            width: screenWidth * 0.25,
                            height: screenWidth * 0.03,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: screenWidth * 0.025),
                    Container(
                      width: screenWidth * 0.18,
                      height: screenWidth * 0.07,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                    ),
                  ],
                ),
              );
            }
          }
        },
      ),
    );
  }

  /// Arama çubuğu
  Widget _buildSearchBar(double screenWidth) {
    final localizations = AppLocalizations.of(context)!;
    final isDarkTheme = Provider.of<ThemeProvider>(context).isDarkTheme;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.02,
        vertical: screenWidth * 0.01,
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: localizations.searchHint,
          prefixIcon: Icon(
            Icons.search,
            size: screenWidth * 0.06,
          ),
          filled: true,
          fillColor: isDarkTheme ? Colors.grey[900] : Colors.grey[200],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(screenWidth * 0.05),
            borderSide: BorderSide.none,
          ),
        ),
        style: TextStyle(
          fontSize: screenWidth * 0.04,
        ),
      ),
    );
  }

  /// Real content with fade transition between search results and normal models
  Widget _buildRealContent(double screenWidth, double screenHeight) {
    final localizations = AppLocalizations.of(context)!;
    final isDarkTheme = Provider.of<ThemeProvider>(context).isDarkTheme;

    final serverSideModels = _models.where((model) {
      return (model['isServerSide'] ?? false) && model['category'] != 'roleplay';
    }).toList();

    final localModels = _models.where((model) {
      return !(model['isServerSide'] ?? false) && model['category'] != 'roleplay';
    }).toList();

    List<Map<String, dynamic>> allModels = [
      ...localModels,
      ...serverSideModels,
      ..._roleModels,
      ..._myModels,
    ];

    List<Map<String, dynamic>> searchResults = [];
    if (_searchQuery.isNotEmpty) {
      searchResults = allModels.where((model) {
        String title = model['title'].toLowerCase();
        bool matches = title.startsWith(_searchQuery);
        return matches;
      }).toList();
    }

    return ListView(
      padding: EdgeInsets.only(
        left: screenWidth * 0.04,
        right: screenWidth * 0.04,
        top: screenWidth * 0.005,
        bottom: screenWidth * 0.04,
      ),
      children: [
        // Search Bar remains outside the AnimatedSwitcher
        _buildSearchBar(screenWidth),
        SizedBox(height: screenHeight * 0.01), // General spacing

        // AnimatedSwitcher for transitioning between search results and normal content
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: _isLoading
              ? _buildShimmerSkeleton(isDarkTheme)
              : _searchQuery.isNotEmpty
              ? _buildSearchResults(searchResults, isDarkTheme)
              : _buildNormalModelContent(
            localModels,
            serverSideModels,
            screenWidth,
            screenHeight,
            isDarkTheme,
          ),
        ),
      ],
    );
  }

  /// Builds the normal models content without search
  Widget _buildNormalModelContent(
      List<Map<String, dynamic>> localModels,
      List<Map<String, dynamic>> serverSideModels,
      double screenWidth,
      double screenHeight,
      bool isDarkTheme) {
    final localizations = AppLocalizations.of(context)!;

    return Column(
      key: ValueKey('normalContent'), // Unique key for AnimatedSwitcher
      children: [
        if (localModels.isNotEmpty) ...[
          _buildSectionHeader(localizations.localModels, isDarkTheme, 'localModels', localModels, screenWidth),
          SizedBox(
            height: screenHeight * 0.262, // Fixed height for consistency
            child: PageView(
              scrollDirection: Axis.horizontal,
              children: _buildModelColumns(localModels, isDarkTheme, 'localModels', screenWidth),
            ),
          ),
        ],
        if (serverSideModels.isNotEmpty) ...[
          _buildSectionHeader(localizations.serverSideModels, isDarkTheme, 'serverSideModels', serverSideModels, screenWidth),
          SizedBox(
            height: screenHeight * 0.262,
            child: PageView(
              scrollDirection: Axis.horizontal,
              children: _buildModelColumns(serverSideModels, isDarkTheme, 'serverSideModels', screenWidth),
            ),
          ),
        ],
        if (_roleModels.isNotEmpty) ...[
          _buildSectionHeader(localizations.roleModels, isDarkTheme, 'roleModels', _roleModels, screenWidth),
          SizedBox(
            height: screenHeight * 0.262,
            child: PageView(
              scrollDirection: Axis.horizontal,
              children: _buildModelColumns(_roleModels, isDarkTheme, 'roleModels', screenWidth),
            ),
          ),
          SizedBox(height: screenWidth * 0.01), // Reduced spacing between categories
        ],
        if (_myModels.isNotEmpty) ...[
          _buildSectionHeader(localizations.myModels, isDarkTheme, 'myModels', _myModels, screenWidth),
          SizedBox(
            height: screenHeight * 0.262,
            child: PageView(
              scrollDirection: Axis.horizontal,
              children: _buildModelColumns(_myModels, isDarkTheme, 'myModels', screenWidth),
            ),
          ),
        ],
        // System Information Section
        Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: screenWidth * 0.015),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  localizations.systemInfo,
                  style: TextStyle(
                    color: isDarkTheme ? Colors.white : Colors.black,
                    fontSize: screenWidth * 0.05, // Reduced font size
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_systemInfo != null)
          SystemInfoChart(
            totalStorage: _systemInfo!.totalStorage,
            usedStorage: (_systemInfo!.totalStorage - _systemInfo!.freeStorage),
            totalMemory: _systemInfo!.deviceMemory,
            usedMemory: _systemInfo!.usedMemory,
          )
      ],
    );
  }

  Widget _buildSearchResults(List<Map<String, dynamic>> searchResults, bool isDarkTheme) {
    final localizations = AppLocalizations.of(context)!;
    final screenWidth = MediaQuery.of(context).size.width;

    // Eski sonuçlar (çıkış yapan öğeler) belirleniyor
    final exitingItems = _prevSearchResults.where(
            (item) => !searchResults.any((element) => element['id'] == item['id'])
    ).toList();

    // Çıkış yapan öğeler animasyon süresinin sonunda kaldırılıyor
    if (exitingItems.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _exitingItems.removeWhere((item) => exitingItems.contains(item));
          });
        }
      });
    }

    // Durum güncelleniyor
    if (mounted) {
      setState(() {
        _exitingItems = [..._exitingItems, ...exitingItems];
        _prevSearchResults = searchResults;
      });
    }

    // Mevcut ve çıkış yapan öğeler birleştiriliyor
    final allItems = [...searchResults, ..._exitingItems];
    return Align(
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
          return Stack(
            alignment: Alignment.topCenter,
            children: <Widget>[
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          );
        },
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: allItems.isEmpty
            ? _buildNoResultsMessage(localizations.noMatchingModels, isDarkTheme, screenWidth)
            : ListView.builder(
          key: const ValueKey('searchResults'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: allItems.length,
          itemBuilder: (context, index) {
            final model = allItems[index];
            final isExiting = _exitingItems.contains(model);

            return SearchResultItem(
              index: index,
              delay: Duration(milliseconds: 100 * index),
              isExiting: isExiting,
              child: _buildModelTile(
                model['id'],
                model['title'],
                model['shortDescription'] ?? '',
                model['description'] ?? '',
                model['url'],
                model['size'],
                model['image'] ?? '',
                model['ram'],
                model['producer'] ?? '',
                model['isServerSide'] ?? false,
                isDarkTheme,
                isCustomModel: model['id'].startsWith('custom_'),
                modelPath: model['path'],
                isSeeAll: true,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildNoResultsMessage(String text, bool isDarkTheme, double screenWidth) {
    return Container(
      key: UniqueKey(), // Her oluşturulduğunda yeni key
      alignment: Alignment.topCenter,
      padding: EdgeInsets.all(screenWidth * 0.05),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: isDarkTheme ? Colors.white70 : Colors.black54,
          fontSize: screenWidth * 0.045,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }


  /// Kategori başlığı
  Widget _buildSectionHeader(
      String title,
      bool isDarkTheme,
      String section,
      List<Map<String, dynamic>> models,
      double screenWidth,
      ) {
    return Padding(
      padding: EdgeInsets.only(
        top: screenWidth * 0.02, // Üst boşluk azaltıldı
        bottom: screenWidth * 0.01, // Alt boşluk azaltıldı
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              color: isDarkTheme ? Colors.white : Colors.black,
              fontSize: screenWidth * 0.05, // Font boyutu azaltıldı
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final isDarkTheme = Provider.of<ThemeProvider>(context).isDarkTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: isDarkTheme ? const Color(0xFF090909) : Colors.white,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        title: Text(
          localizations.modelsTitle,
          style: TextStyle(
            fontFamily: 'Roboto',
            color: isDarkTheme ? Colors.white : Colors.black,
            fontSize: screenWidth * 0.07,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: isDarkTheme ? const Color(0xFF090909) : Colors.white,
        elevation: 0,
        actions: [
          Transform.translate(
            offset: Offset(-screenWidth * 0.02, 0),
            child: ElevatedButton(
              onPressed: _onAddButtonPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: isDarkTheme ? Colors.white : Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(screenWidth * 0.045),
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.03,
                  vertical: screenWidth * 0.015,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    localizations.addModel,
                    style: TextStyle(
                      color: isDarkTheme ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: screenWidth * 0.03,
                    ),
                  ),
                  SizedBox(width: screenWidth * 0.02),
                  Container(
                    width: screenWidth * 0.035,
                    height: screenWidth * 0.035,
                    decoration: BoxDecoration(
                      color: isDarkTheme ? Colors.black : Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.add,
                      color: isDarkTheme ? Colors.white : Colors.black,
                      size: screenWidth * 0.03,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: _isLoading
              ? _buildShimmerSkeleton(isDarkTheme)
              : _buildRealContent(screenWidth, screenHeight),
        ),
      ),
    );
  }
}