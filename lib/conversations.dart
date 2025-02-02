// menu.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data.dart';
import 'main.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'theme.dart';
import 'package:cortex/notifications.dart';
import 'package:shimmer/shimmer.dart'; // Added Shimmer import

/// Her sohbeti yönetecek olan ChangeNotifier
class ConversationManager extends ChangeNotifier {
  final String conversationID;
  String conversationTitle;
  final String modelId;
  final String modelTitle;
  final String modelImagePath;
  final String modelDescription;
  final String modelProducer;
  final bool isServerSide;
  bool isStarred;
  DateTime lastMessageDate;
  String lastMessageText;
  bool isDeleted = false; // Artık AnimatedList kullandığımız için pek gerek yok.
  bool isModelAvailable;
  bool canHandleImage;

  // YENİ ALAN:
  String lastMessagePhotoPath; // Son mesajda fotoğraf varsa path burada tutulur

  ConversationManager({
    required this.conversationID,
    required this.conversationTitle,
    required this.modelId,
    required this.modelTitle,
    required this.modelImagePath,
    required this.modelDescription,
    required this.modelProducer,
    required this.isServerSide,
    required this.isStarred,
    required this.lastMessageDate,
    required this.lastMessageText,
    required this.isModelAvailable,
    this.lastMessagePhotoPath = '',
    this.canHandleImage = false, // Varsayılan olarak
  });

  void setTitle(String newTitle) {
    conversationTitle = newTitle;
    notifyListeners();
  }

  void setStarred(bool val) {
    isStarred = val;
    notifyListeners();
  }

  void setDeleted(bool val) {
    isDeleted = val;
    notifyListeners();
  }

  void setModelAvailable(bool val) {
    isModelAvailable = val;
    notifyListeners();
  }

  void updateLastMessageDate(DateTime date) {
    lastMessageDate = date;
    notifyListeners();
  }

  void updateLastMessageText(String text) {
    lastMessageText = text;
    notifyListeners();
  }

  void updateLastPhotoPath(String path) {
    lastMessagePhotoPath = path;
    notifyListeners();
  }
}

class ConversationData {
  /// Bu eski veri sınıfı. Artık ConversationManager içinde veriyi tutuyoruz.
  /// İsterseniz tamamen kaldırabilirsiniz de. Sadece "depo" amacıyla dursun.
}

/// MenuScreen: Sohbet listesini gösteren ana ekran.
class MenuScreen extends StatefulWidget {
  const MenuScreen({Key? key}) : super(key: key);

  @override
  MenuScreenState createState() => MenuScreenState();
}

class MenuScreenState extends State<MenuScreen> with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  /// Manager'larımız:
  final Map<String, ConversationManager> _conversationManagers = {};
  final ScrollController _listScrollController = ScrollController();
  /// Tüm konuşmaların ID'lerini tutan liste (önemli: AnimatedList index yönetimi için).
  List<String> _conversationIDsOrder = [];

  bool _isLoading = true;
  int _conversationsMinus = 0;
  bool hasInternetConnection = false;

  @override
  bool get wantKeepAlive => true;

  // "All Chats" sekmesi için AnimatedList kullanacağız:
  final GlobalKey<AnimatedListState> _allChatsListKey = GlobalKey<AnimatedListState>();

  late final AnimationController _fadeAnimationController;
  late Animation<double> _fadeAnimation;
  late NotificationService _notificationService;
  late StreamSubscription<InternetStatus> _internetSubscription;

  @override
  void initState() {
    super.initState();

    // Initialize AnimationController and other variables
    _fadeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeAnimationController,
      curve: Curves.easeInOut,
    );

    // Set up internet connectivity listener and assign to _internetSubscription
    _internetSubscription = InternetConnection().onStatusChange.listen((status) async {
      final hasConnection = status == InternetStatus.connected;
      setState(() {
        hasInternetConnection = hasConnection;
      });

      if (hasConnection) {
        await applyPendingConversationsDecrement();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _notificationService =
          Provider.of<NotificationService>(context, listen: false);
      await _loadConversations();
      await applyPendingConversationsDecrement(); // Apply pending decrements
    });

    _fadeAnimationController.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  Future<void> applyPendingConversationsDecrement() async {
    if (!hasInternetConnection) return;

    final prefs = await SharedPreferences.getInstance();
    _conversationsMinus = prefs.getInt('conversationsMinus') ?? 0;

    if (_conversationsMinus > 0) {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({'conversations': FieldValue.increment(-_conversationsMinus)});

          // Reset 'conversationsMinus'
          await prefs.setInt('conversationsMinus', 0);
          setState(() {
            _conversationsMinus = 0;
          });
        } catch (e) {
          print("Error applying pending conversations decrement: $e");
        }
      }
    }
  }


  @override
  void dispose() {
    _listScrollController.dispose();
    _fadeAnimationController.dispose();
    _internetSubscription.cancel();
    super.dispose();
  }

  Future<void> _loadConversations() async {
    final prefs = await SharedPreferences.getInstance();
    List<String>? conversations = prefs.getStringList('conversations');

    _conversationManagers.clear();
    _conversationIDsOrder.clear();

    if (conversations != null) {
      for (int i = 0; i < conversations.length; i++) {
        String conversationEntry = conversations[i];
        List<String> parts = conversationEntry.split('|');
        // Format: convID|convTitle|modelId|lastMessageDate|lastMessageText|lastMessagePhotoPath
        if (parts.length >= 5) {
          String convID = parts[0];
          String convTitle = parts[1];
          String modelId = parts[2];
          String lastMessageDateString = parts[3];
          String lastMessageText = parts[4];
          String lastMessagePhotoPath = parts.length >= 6 ? parts[5] : '';

          DateTime lastMessageDate =
              DateTime.tryParse(lastMessageDateString) ?? DateTime.now();

          // Model verisini al
          Map<String, dynamic> modelData = _getModelDataFromId(modelId);

          bool isServerSide = modelData['isServerSide'] == true;
          bool isModelAvailable = await _isModelAvailable(modelId);
          bool isStarred = prefs.getBool('is_starred_$convID') ?? false;

          // YENİ: Modelin resim alıp alamayacağı
          bool canHandleImage = modelData['canHandleImage'] ?? false;

          // Manager oluştur
          final manager = ConversationManager(
            conversationID: convID,
            conversationTitle: convTitle,
            modelId: modelId,
            modelTitle: modelData['title'] ?? 'Unknown Model',
            modelImagePath: modelData['image'] ?? '',
            modelDescription: modelData['description'] ?? '',
            modelProducer: modelData['producer'] ?? '',
            isServerSide: isServerSide,
            isStarred: isStarred,
            lastMessageDate: lastMessageDate,
            lastMessageText: lastMessageText,
            isModelAvailable: isModelAvailable,
            lastMessagePhotoPath: lastMessagePhotoPath,
            canHandleImage: canHandleImage,
          );

          _conversationManagers[convID] = manager;
          _conversationIDsOrder.add(convID);
        }
      }

      // Tarihe göre sıralama
      _conversationIDsOrder.sort((a, b) {
        final dateA = _conversationManagers[a]?.lastMessageDate ?? DateTime(0);
        final dateB = _conversationManagers[b]?.lastMessageDate ?? DateTime(0);
        return dateB.compareTo(dateA);
      });
    }

    // **Consistency Check**
    for (String convID in _conversationIDsOrder) {
      if (!_conversationManagers.containsKey(convID)) {
        debugPrint('Error: _conversationManagers missing entry for conversationID: $convID');
      }
    }

    setState(() {
      _isLoading = false;
    });
  }

  /// Model mevcut mu diye kontrol
  Future<bool> _isModelAvailable(String modelId) async {
    List<Map<String, dynamic>> models = ModelData.models(context);
    Map<String, dynamic>? model = models.firstWhere(
          (m) => m['id'] == modelId,
      orElse: () => {},
    );
    if (model.isEmpty) return false;
    if (model['isServerSide'] == true) {
      return true; // Sunucu taraflı her zaman var
    }
    final prefs = await SharedPreferences.getInstance();
    final isDownloaded = prefs.getBool('is_downloaded_${model['id']}') ?? false;
    return isDownloaded;
  }

  /// Tekrar yüklemek isterseniz
  Future<void> reloadConversations() async {
    setState(() {
      _isLoading = true;
    });
    _conversationManagers.clear();
    _conversationIDsOrder.clear();
    await _loadConversations();
  }

  Future<void> _triggerFadeOutLoadingAnimation() async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted) {
      setState(() {
      });
    }
    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteConversation(String conversationID) async {
    final prefs = await SharedPreferences.getInstance();
    final manager = _conversationManagers[conversationID];
    if (manager == null) {
      debugPrint('Warning: Attempted to delete non-existent conversationID: $conversationID');
      return;
    }

    // 1) Hangi index'te silineceğini bul
    int removeIndex = _conversationIDsOrder.indexOf(conversationID);
    if (removeIndex < 0) {
      // Listede bulamadıysak, yine de prefs temizleyelim
      List<String> conversations = prefs.getStringList('conversations') ?? [];
      conversations.removeWhere((conv) => conv.startsWith('$conversationID|'));
      await prefs.setStringList('conversations', conversations);
      await prefs.remove('is_starred_$conversationID');
      await prefs.remove(conversationID);
      return;
    }

    // 2) Silinecek ConversationManager'ı sakla
    final ConversationManager removedManager = manager;

    // 3) setState içinde model'den item'ı çıkar ve AnimatedList'e removeItem talimatı ver
    setState(() {
      // Önce asıl liste verimizden çıkaralım
      _conversationIDsOrder.removeAt(removeIndex);
      _conversationManagers.remove(conversationID);

      // Sonra AnimatedList'e animasyonlu kaldırma komutu
      _allChatsListKey.currentState?.removeItem(
        removeIndex,
            (context, animation) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOut,
          );
          return AnimatedBuilder(
            animation: curvedAnimation,
            builder: (context, child) {
              return SizeTransition(
                sizeFactor: curvedAnimation,
                child: FadeTransition(
                  opacity: curvedAnimation,
                  child: child,
                ),
              );
            },
            child: ConversationTile(
              key: ValueKey(conversationID),
              manager: removedManager,
              hideWhenUnstarred: false,
              onDelete: () {},
              onEdit: (_) {},
              onToggleStar: () {},
            ),
          );
        },
        duration: const Duration(milliseconds: 300),
      );
    });

    // 4) SharedPreferences’dan da temizleyelim
    List<String> conversations = prefs.getStringList('conversations') ?? [];
    conversations.removeWhere((conv) => conv.startsWith('$conversationID|'));
    await prefs.setStringList('conversations', conversations);
    await prefs.remove('is_starred_$conversationID');
    await prefs.remove(conversationID);

    // 5) Eğer bu sohbet şu an ChatScreen'de aktifse sıfırla
    if (mainScreenKey.currentState?.chatScreenKey.currentState?.conversationID == conversationID) {
      mainScreenKey.currentState?.chatScreenKey.currentState?.resetConversation();
    }

    // 6) Sunucu taraflı sohbetlerde güncelleme yap:
    //    • Eğer model sunucu taraflı ise, internet varsa Firestore'da decrement yap,
    //      internet yoksa pending decrement (conversationsMinus) kaydı ekle.
    //    • Sunucu taraflı olmayan sohbetlerde hiçbir güncelleme yapma.
    if (removedManager.isServerSide) {
      if (hasInternetConnection) {
        final User? user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          try {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .update({'conversations': FieldValue.increment(-1)});
          } catch (e) {
            print("Error decrementing conversations count in Firestore: $e");
            _conversationsMinus = prefs.getInt('conversationsMinus') ?? 0;
            _conversationsMinus += 1;
            await prefs.setInt('conversationsMinus', _conversationsMinus);
          }
        }
      } else {
        // Çevrimdışı durumdaysa ve sohbet sunucu taraflı ise pending decrement kaydını ekle
        _conversationsMinus = prefs.getInt('conversationsMinus') ?? 0;
        _conversationsMinus += 1;
        await prefs.setInt('conversationsMinus', _conversationsMinus);
      }
    }

    // 7) Bildirim göster
    _notificationService.showNotification(
      message: AppLocalizations.of(context)!.conversationDeleted,
      isSuccess: true,
    );
  }


  Map<String, dynamic> _getModelDataFromId(String modelId) {
    List<Map<String, dynamic>> allModels = ModelData.models(context);

    // Use a default map in orElse to ensure a non-null return value
    Map<String, dynamic> model = allModels.firstWhere(
          (model) => model['id'] == modelId,
      orElse: () => {
        'title': 'Unknown Model',
        'image': '',
        'description': '',
        'producer': '',
        'isServerSide': false,
        'canHandleImage': false,
      },
    );

    // Check if the returned model is the default one
    if (model['title'] == 'Unknown Model') {
      debugPrint('Error: No model found for modelId: $modelId');
    }

    return model;
  }



  /// Konuşma başlığını düzenle
  Future<void> _editConversation(String conversationID, String newTitle) async {
    final manager = _conversationManagers[conversationID];
    if (manager == null) return;

    final prefs = await SharedPreferences.getInstance();
    manager.setTitle(newTitle);

    List<String> conversations = prefs.getStringList('conversations') ?? [];
    String newEntry =
        '${manager.conversationID}|$newTitle|${manager.modelId}|${manager.lastMessageDate.toIso8601String()}|${manager.lastMessageText}|${manager.lastMessagePhotoPath}';

    conversations = conversations.map((conv) {
      if (conv.startsWith('${manager.conversationID}|')) {
        return newEntry;
      }
      return conv;
    }).toList();
    await prefs.setStringList('conversations', conversations);

    // Eğer ChatScreen bu sohbeti gösteriyorsa, orayı da güncelle
    if (mainScreenKey.currentState?.chatScreenKey.currentState?.conversationID ==
        manager.conversationID) {
      mainScreenKey.currentState?.chatScreenKey.currentState
          ?.updateConversationTitle(newTitle);
    }

    _notificationService.showNotification(
      message: AppLocalizations.of(context)!.conversationTitleUpdated,
      isSuccess: true,
    );
  }

  Future<void> _toggleStarredStatus(String conversationID) async {
    final prefs = await SharedPreferences.getInstance();
    final manager = _conversationManagers[conversationID];
    if (manager == null) return;

    bool newVal = !manager.isStarred;
    manager.setStarred(newVal);
    await prefs.setBool('is_starred_$conversationID', newVal);

    // Eğer sohbetin yıldızı kaldırılıyorsa ve yıldızlı sekmede listeleniyorsa,
    // orada da animasyonla kaldırmak isterseniz, yine benzer removeItem süreci gerekir.
    // Şimdilik "Starred Chats" sekmesi normal ListView olduğu için basitçe setState yetiyor.
    if (!newVal) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    setState(() {});
  }

  Widget _buildAnimatedListItem(String conversationID, Animation<double> animation) {
    final manager = _conversationManagers[conversationID];

    if (manager == null) {
      debugPrint('Warning: ConversationManager for ID $conversationID is null.');
      return SizedBox.shrink();
    }

    return ConversationTile(
      key: ValueKey(conversationID),
      manager: manager,
      hideWhenUnstarred: false,
      onDelete: () => _deleteConversation(conversationID),
      onEdit: (newTitle) => _editConversation(conversationID, newTitle),
      onToggleStar: () => _toggleStarredStatus(conversationID),
    );
  }

  Widget _buildConversationTile(String conversationID, {bool hideWhenUnstarred = false}) {
    final manager = _conversationManagers[conversationID];
    if (manager == null) {
      return const SizedBox.shrink();
    }

    return ConversationTile(
      key: ValueKey(conversationID),
      manager: manager,
      hideWhenUnstarred: hideWhenUnstarred,
      onDelete: () => _deleteConversation(conversationID),
      onEdit: (newTitle) => _editConversation(conversationID, newTitle),
      onToggleStar: () => _toggleStarredStatus(conversationID),
    );
  }

  Widget _buildConversationList({required bool showStarredOnly}) {
    final isDarkTheme = Provider.of<ThemeProvider>(context).isDarkTheme;
    final localizations = AppLocalizations.of(context)!;

    List<String> filteredIDs;
    if (showStarredOnly) {
      filteredIDs = _conversationIDsOrder
          .where((id) => _conversationManagers[id]?.isStarred == true)
          .toList();
    } else {
      filteredIDs = List<String>.from(_conversationIDsOrder);
    }

    if (_isLoading) {
      return _SkeletonChatList();
    }

    if (filteredIDs.isEmpty) {
      final screenWidth = MediaQuery.of(context).size.width;
      final screenHeight = MediaQuery.of(context).size.height;
      return TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 300),
        builder: (context, opacity, child) {
          return Opacity(
            opacity: opacity,
            child: child,
          );
        },
        child: Align(
          alignment: Alignment.center,
          child: Padding(
            padding: EdgeInsets.all(screenWidth * 0.04),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  showStarredOnly
                      ? localizations.noStarredChats
                      : localizations.noChats,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    color: isDarkTheme ? Colors.white : Colors.black,
                    fontSize: screenWidth * 0.08,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: screenHeight * 0.005),
                Text(
                  showStarredOnly
                      ? localizations.noStarredChatsMessage
                      : localizations.noConversationsMessage,
                  style: TextStyle(
                    color: isDarkTheme ? Colors.grey[400] : Colors.grey[700],
                    fontSize: screenWidth * 0.04,
                  ),
                ),
                SizedBox(height: screenHeight * 0.01),
                ElevatedButton(
                  onPressed: () {
                    if (showStarredOnly) {
                      DefaultTabController.of(context)?.animateTo(0);
                    } else {
                      mainScreenKey.currentState?.onItemTapped(0);
                    }
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                    isDarkTheme ? Colors.white : Colors.black,
                    padding: EdgeInsets.symmetric(
                      horizontal: screenWidth * 0.08,
                      vertical: screenHeight * 0.015,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(screenWidth * 0.02),
                    ),
                  ),
                  child: Text(
                    showStarredOnly
                        ? localizations.goToChats
                        : localizations.startChat,
                    style: TextStyle(
                      color: isDarkTheme ? Colors.black : Colors.white,
                      fontSize: screenWidth * 0.04,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (showStarredOnly) {
      return ListView.builder(
        key: const ValueKey('starredList'),
        itemCount: filteredIDs.length,
        itemBuilder: (context, index) {
          final convID = filteredIDs[index];
          return _buildConversationTile(convID, hideWhenUnstarred: true);
        },
      );
    } else {
      return AnimatedList(
        key: _allChatsListKey, // Use the same key as used in _deleteConversation.
        controller: _listScrollController,
        initialItemCount: filteredIDs.length,
        itemBuilder: (context, index, animation) {
          final convID = filteredIDs[index];
          return _buildAnimatedListItem(convID, animation);
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final localizations = AppLocalizations.of(context)!;
    final isDarkTheme = Provider.of<ThemeProvider>(context).isDarkTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    // We'll also use screenHeight if needed for the app bar sizing, etc.

    return FadeTransition(
      opacity: _fadeAnimation,
      child: GestureDetector(
        onTap: () {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
        },
        child: DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              scrolledUnderElevation: 0,
              title: Text(
                localizations.conversationsTitle,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  color: isDarkTheme ? Colors.white : Colors.black,
                  fontSize: screenWidth * 0.06,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: isDarkTheme ? const Color(0xFF090909) : Colors.white,
              elevation: 0,
              actions: [
                IconButton(
                  icon: SvgPicture.asset(
                    'assets/chat.svg',
                    color: isDarkTheme ? Colors.white : Colors.black,
                    width: screenWidth * 0.055,  // e.g., ~22px if screenWidth=400
                    height: screenWidth * 0.055,
                  ),
                  onPressed: () {
                    mainScreenKey.currentState?.onItemTapped(0);
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  },
                ),
              ],
              bottom: PreferredSize(
                preferredSize: Size.fromHeight(screenWidth * 0.12),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    splashColor: Colors.grey.withOpacity(0.3),
                    highlightColor: Colors.grey.withOpacity(0.1),
                  ),
                  child: Container(
                    width: double.infinity,
                    alignment: Alignment.center,
                    child: TabBar(
                      isScrollable: false,
                      indicator: UnderlineTabIndicator(
                        borderSide: BorderSide(
                          width: screenWidth * 0.004,
                          color: isDarkTheme ? Colors.white : Colors.black,
                        ),
                        insets: EdgeInsets.zero,
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: isDarkTheme ? Colors.white : Colors.black,
                      unselectedLabelColor: isDarkTheme ? Colors.grey : Colors.grey,
                      labelStyle: TextStyle(fontSize: screenWidth * 0.04),
                      tabs: [
                        Tab(
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(localizations.allChats),
                            ),
                          ),
                        ),
                        Tab(
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(localizations.starredChats),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            backgroundColor: isDarkTheme ? const Color(0xFF090909) : Colors.white,
            body: TabBarView(
              children: [
                _buildConversationList(showStarredOnly: false),
                _buildConversationList(showStarredOnly: true),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ConversationTile: Tek bir sohbet kartı.
class ConversationTile extends StatefulWidget {
  final ConversationManager manager;
  final VoidCallback onDelete;
  final ValueChanged<String> onEdit;
  final VoidCallback onToggleStar;
  final bool hideWhenUnstarred;

  const ConversationTile({
    Key? key,
    required this.manager,
    required this.onDelete,
    required this.onEdit,
    required this.onToggleStar,
    this.hideWhenUnstarred = false,
  }) : super(key: key);

  @override
  _ConversationTileState createState() => _ConversationTileState();
}

class _ConversationTileState extends State<ConversationTile>
    with SingleTickerProviderStateMixin {
  final GlobalKey _threeDotKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  late AnimationController _animationController;
  bool _isDisposed = false;

  Timer? _longPressTimer;
  bool _isLongPress = false;

  static _ConversationTileState? _currentlyOpenTileState;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    widget.manager.addListener(_onManagerChanged);
  }

  void _onManagerChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _isDisposed = true;
    _longPressTimer?.cancel();
    if (_currentlyOpenTileState == this) {
      _currentlyOpenTileState = null;
    }
    if (_overlayEntry != null) {
      _overlayEntry?.remove();
      _overlayEntry = null;
    }
    widget.manager.removeListener(_onManagerChanged);
    _animationController.dispose();
    super.dispose();
  }

  void _removeOverlay({bool animate = true}) {
    if (_overlayEntry != null) {
      if (animate && !_isDisposed) {
        _animationController.reverse().then((_) {
          if (mounted) {
            _overlayEntry?.remove();
            _overlayEntry = null;
          }
          if (_currentlyOpenTileState == this) {
            _currentlyOpenTileState = null;
          }
        });
      } else {
        _overlayEntry?.remove();
        _overlayEntry = null;
        if (_currentlyOpenTileState == this) {
          _currentlyOpenTileState = null;
        }
      }
    }
  }

  void _showActionPanel() {
    if (_overlayEntry != null) return;

    if (_currentlyOpenTileState != null && _currentlyOpenTileState != this) {
      _currentlyOpenTileState?._removeOverlay(animate: false);
      _currentlyOpenTileState = null;
    }

    final isDarkTheme = Provider.of<ThemeProvider>(context, listen: false).isDarkTheme;
    final loc = AppLocalizations.of(context)!;

    final renderBox = _threeDotKey.currentContext!.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    final double panelHeight = screenHeight * 0.2; // around 160px on 800px screen
    final double panelWidth = screenWidth * 0.3;  // around 120px if screenWidth=400
    final bool openUpwards = (offset.dy + size.height + panelHeight + 20) > screenHeight;

    double panelTop = openUpwards ? (offset.dy - panelHeight) : (offset.dy + size.height);
    double panelRight = screenWidth - (offset.dx + size.width);

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _removeOverlay,
          child: Stack(
            children: [
              Positioned(
                top: panelTop,
                right: panelRight,
                child: FadeTransition(
                  opacity: _animationController,
                  child: ScaleTransition(
                    scale: _animationController,
                    alignment: openUpwards ? Alignment.bottomRight : Alignment.topRight,
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          vertical: screenHeight * 0.01,
                          horizontal: screenWidth * 0.02,
                        ),
                        decoration: BoxDecoration(
                          color: isDarkTheme
                              ? const Color(0xFF121212)
                              : const Color(0xFFEDEDED),
                          borderRadius: BorderRadius.circular(screenWidth * 0.02),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: screenWidth * 0.015,
                              offset: Offset(0, screenHeight * 0.003),
                            ),
                          ],
                        ),
                        child: IntrinsicWidth(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minWidth: panelWidth),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _ActionPanelButton(
                                  icon: widget.manager.isStarred
                                      ? Icons.star
                                      : Icons.star_border,
                                  iconColor: widget.manager.isStarred
                                      ? Colors.amber
                                      : (isDarkTheme
                                      ? Colors.white
                                      : Colors.black),
                                  text: loc.starConversation,
                                  textColor:
                                  isDarkTheme ? Colors.white : Colors.black,
                                  onPressed: () async {
                                    await _removeOverlayWithAnimation();
                                    widget.onToggleStar();
                                  },
                                ),
                                SizedBox(height: screenHeight * 0.01),
                                _ActionPanelButton(
                                  iconAsset: 'assets/editConversationTitle.svg',
                                  iconColor:
                                  isDarkTheme ? Colors.white : Colors.black,
                                  text: loc.editConversationTitle,
                                  textColor:
                                  isDarkTheme ? Colors.white : Colors.black,
                                  onPressed: () {
                                    _showEditDialog(isDarkTheme, loc);
                                    _removeOverlay();
                                  },
                                ),
                                SizedBox(height: screenHeight * 0.01),
                                _ActionPanelButton(
                                  iconAsset: 'assets/deleteConversation.svg',
                                  iconColor: Colors.red,
                                  text: loc.remove,
                                  textColor: Colors.red,
                                  onPressed: () {
                                    widget.onDelete();
                                    _removeOverlay();
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
    _animationController.forward();
    _currentlyOpenTileState = this;
  }

  Future<void> _removeOverlayWithAnimation() async {
    if (_overlayEntry != null && !_isDisposed) {
      await _animationController.reverse();
      if (mounted) {
        _overlayEntry?.remove();
        _overlayEntry = null;
      }
      if (_currentlyOpenTileState == this) {
        _currentlyOpenTileState = null;
      }
    }
  }

  void _showEditDialog(bool isDarkTheme, AppLocalizations loc) {
    final TextEditingController controller = TextEditingController(
      text: widget.manager.conversationTitle,
    );

    final screenWidth = MediaQuery.of(context).size.width;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(screenWidth * 0.03),
          ),
          backgroundColor: isDarkTheme ? const Color(0xFF2D2F2E) : Colors.grey[200],
          title: Text(
            loc.editConversationTitle,
            style: TextStyle(
              color: isDarkTheme ? Colors.white : Colors.black,
            ),
          ),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: loc.newTitle,
              labelStyle: TextStyle(
                color: isDarkTheme ? Colors.white : Colors.black,
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: isDarkTheme ? Colors.white : Colors.black,
                ),
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: isDarkTheme ? Colors.white : Colors.black,
                ),
              ),
            ),
            style: TextStyle(
              color: isDarkTheme ? Colors.white : Colors.black,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                loc.cancel,
                style: TextStyle(
                  color: isDarkTheme ? Colors.white : Colors.black,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                String newText = controller.text.trim();
                if (newText.isNotEmpty) {
                  widget.onEdit(newText);
                }
                Navigator.of(dialogContext).pop();
              },
              child: Text(
                loc.save,
                style: TextStyle(
                  color: isDarkTheme ? Colors.white : Colors.black,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inHours <= 24) {
      return AppLocalizations.of(context)!.today;
    } else if (difference.inHours < 48) {
      return AppLocalizations.of(context)!.yesterday;
    } else {
      return DateFormat('MMM d, yyyy').format(date);
    }
  }

  Widget _getLastMessageSnippet(String lastMessageText, String lastPhotoPath) {
    final isDarkTheme = Provider.of<ThemeProvider>(context).isDarkTheme;

    if (lastPhotoPath.isNotEmpty) {
      if (lastMessageText.trim().isNotEmpty) {
        return Row(
          children: [
            SvgPicture.asset(
              'assets/photo.svg',
              width: MediaQuery.of(context).size.width * 0.04,
              height: MediaQuery.of(context).size.width * 0.04,
              color: isDarkTheme ? Colors.grey[300] : Colors.grey[800],
            ),
            SizedBox(width: MediaQuery.of(context).size.width * 0.01),
            Expanded(
              child: Text(
                lastMessageText,
                style: TextStyle(
                  color: isDarkTheme ? Colors.grey[300] : Colors.grey[800],
                  fontSize: MediaQuery.of(context).size.width * 0.03,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        );
      } else {
        return SvgPicture.asset(
          'assets/photo.svg',
          width: MediaQuery.of(context).size.width * 0.04,
          height: MediaQuery.of(context).size.width * 0.04,
          color: isDarkTheme ? Colors.grey[300] : Colors.grey[800],
        );
      }
    } else {
      return Text(
        lastMessageText,
        style: TextStyle(
          color: isDarkTheme ? Colors.grey[300] : Colors.grey[800],
          fontSize: MediaQuery.of(context).size.width * 0.03,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        softWrap: false,
      );
    }
  }

  void _navigateToChatScreen() {
    mainScreenKey.currentState?.openConversation(widget.manager);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hideWhenUnstarred && !widget.manager.isStarred) {
      return const SizedBox.shrink();
    }

    final isDarkTheme = Provider.of<ThemeProvider>(context).isDarkTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // A fallback background color
    Color backgroundColor = isDarkTheme ? Colors.grey[800]! : Colors.grey[300]!;

    // If model image is .png, use a slightly different background color
    if (widget.manager.modelImagePath.isNotEmpty &&
        widget.manager.modelImagePath.endsWith('.png')) {
      backgroundColor = isDarkTheme
          ? const Color(0xFF121212)
          : const Color(0xFFEDEDED);
    }

    // We'll base all spacing on screenWidth/screenHeight
    final double horizontalMargin = screenWidth * 0.03;
    final double verticalMargin = screenHeight * 0.01;
    final double tilePadding = screenWidth * 0.04;
    final double imageSize = screenWidth * 0.15;

    return GestureDetector(
      onTapDown: (_) {
        _isLongPress = false;
        _longPressTimer = Timer(const Duration(milliseconds: 100), () {
          setState(() {
            _isLongPress = true;
          });
          _showActionPanel();
        });
      },
      onTapUp: (_) {
        _longPressTimer?.cancel();
      },
      onTapCancel: () {
        _longPressTimer?.cancel();
      },
      onTap: () {
        if (!_isLongPress) {
          _navigateToChatScreen();
        }
      },
      child: Container(
        margin: EdgeInsets.symmetric(
          horizontal: horizontalMargin,
          vertical: verticalMargin,
        ),
        padding: EdgeInsets.all(tilePadding),
        decoration: BoxDecoration(
          color: isDarkTheme ? const Color(0xFF121212) : const Color(0xFFEDEDED),
          borderRadius: BorderRadius.circular(screenWidth * 0.03),
          boxShadow: [
            BoxShadow(
              color: isDarkTheme
                  ? Colors.black.withOpacity(0.2)
                  : Colors.grey.withOpacity(0.1),
              blurRadius: screenWidth * 0.015,
              offset: Offset(0, screenHeight * 0.003),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Üst bölüm: Resim + Title/Subtitle
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: imageSize,
                  height: imageSize,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(screenWidth * 0.02),
                    image: widget.manager.modelImagePath.isNotEmpty
                        ? DecorationImage(
                      image: AssetImage(widget.manager.modelImagePath),
                      fit: BoxFit.cover,
                    )
                        : null,
                    color: backgroundColor,
                  ),
                  child: widget.manager.modelImagePath.isEmpty
                      ? Icon(
                    Icons.image,
                    color: Colors.grey,
                    size: imageSize * 0.5,
                  )
                      : null,
                ),
                SizedBox(width: screenWidth * 0.03),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title + Date
                      Row(
                        children: [
                          Expanded(
                            child: FittedBox(
                              alignment: Alignment.centerLeft,
                              fit: BoxFit.scaleDown,
                              child: Text(
                                widget.manager.conversationTitle,
                                style: GoogleFonts.poppins(
                                  fontSize: screenWidth * 0.045,
                                  fontWeight: FontWeight.w500,
                                  color: isDarkTheme ? Colors.white : Colors.black,
                                ),
                                maxLines: 1,
                              ),
                            ),
                          ),
                          SizedBox(width: screenWidth * 0.02),
                          Text(
                            _formatDate(widget.manager.lastMessageDate),
                            style: TextStyle(
                              color: isDarkTheme ? Colors.grey : Colors.grey[600],
                              fontSize: screenWidth * 0.03,
                            ),
                          ),
                        ],
                      ),
                      // Model Title
                      Text(
                        widget.manager.modelTitle,
                        style: GoogleFonts.poppins(
                          fontSize: screenWidth * 0.03,
                          fontWeight: FontWeight.w400,
                          color: isDarkTheme ? Colors.white : Colors.black,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: screenHeight * 0.005),
                      // Last Message Snippet + 3-Dot
                      Row(
                        children: [
                          Expanded(
                            child: _getLastMessageSnippet(
                              widget.manager.lastMessageText,
                              widget.manager.lastMessagePhotoPath,
                            ),
                          ),
                          GestureDetector(
                            key: _threeDotKey,
                            onTap: _showActionPanel,
                            child: SizedBox(
                              width: screenWidth * 0.08,
                              child: Center(
                                child: Icon(
                                  Icons.more_horiz,
                                  size: screenWidth * 0.05,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Aksiyon panelindeki buton (Sil, Düzenle, vb.)
class _ActionPanelButton extends StatelessWidget {
  final IconData? icon;
  final String? iconAsset;
  final Color iconColor;
  final String text;
  final Color textColor;
  final VoidCallback onPressed;

  const _ActionPanelButton({
    Key? key,
    this.icon,
    this.iconAsset,
    required this.iconColor,
    required this.text,
    required this.textColor,
    required this.onPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final double iconSize = screenWidth * 0.06; // ~24px if screenWidth ~400

    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: EdgeInsets.symmetric(
          vertical: screenWidth * 0.03,
          horizontal: screenWidth * 0.03,
        ),
        minimumSize: Size(0, screenWidth * 0.1),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        alignment: Alignment.centerLeft,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(
              icon,
              color: iconColor,
              size: iconSize,
            ),
          if (iconAsset != null)
            SvgPicture.asset(
              iconAsset!,
              color: iconColor,
              width: iconSize,
              height: iconSize,
            ),
          SizedBox(width: screenWidth * 0.03),
          Text(
            text,
            style: TextStyle(
              color: textColor,
              fontSize: screenWidth * 0.035,
            ),
          ),
        ],
      ),
    );
  }
}

/// Updated _SkeletonChatTile with equalized sizes to match ConversationTile
class _SkeletonChatTile extends StatelessWidget {
  const _SkeletonChatTile({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Provider.of<ThemeProvider>(context).isDarkTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Define padding similar to ConversationTile
    final horizontalPadding = screenWidth * 0.03; // Matches ConversationTile's horizontal margin
    final verticalPadding = screenHeight * 0.01;  // Matches ConversationTile's vertical margin

    // Calculate container width based on padding
    final containerWidth = screenWidth - 2 * (horizontalPadding + screenWidth * 0.04);
    // screenWidth * 0.04 is the padding inside ConversationTile

    // Define height based on image size and padding
    final imageSize = screenWidth * 0.15; // Same as ConversationTile's image size
    final containerHeight = imageSize + 2 * (screenHeight * 0.02); // Image size plus vertical padding

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      child: Shimmer.fromColors(
        baseColor: isDarkTheme ? Colors.grey[900]! : Colors.grey[300]!,
        highlightColor: isDarkTheme ? Colors.grey[700]! : Colors.grey[100]!,
        child: Container(
          width: containerWidth,
          height: containerHeight,
          decoration: BoxDecoration(
            color: isDarkTheme ? Colors.grey[700] : Colors.grey[300],
            borderRadius: BorderRadius.circular(screenWidth * 0.03),
          ),
        ),
      ),
    );
  }
}

class _SkeletonChatList extends StatelessWidget {
  const _SkeletonChatList({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 10,
      itemBuilder: (context, index) {
        return const _SkeletonChatTile();
      },
    );
  }
}