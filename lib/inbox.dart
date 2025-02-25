// inbox.dart

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

/// MenuScreen: Sohbet listesini gösteren ana ekran.
class MenuScreen extends StatefulWidget {
  const MenuScreen({Key? key}) : super(key: key);

  @override
  MenuScreenState createState() => MenuScreenState();
}

class MenuScreenState extends State<MenuScreen> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
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

  final GlobalKey<AnimatedListState> _starredChatsListKey = GlobalKey<AnimatedListState>();
  // Starred sohbetleri tutacak liste
  List<String> _starredConversationIDs = [];

  TabController? _tabController;
  int _currentTabIndex = 0;

  late final AnimationController _fadeAnimationController;
  late Animation<double> _fadeAnimation;
  late NotificationService _notificationService;
  late StreamSubscription<InternetStatus> _internetSubscription;

  @override
  void initState() {
    super.initState();

    // Initialize AnimationController and other variables
    _fadeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 50),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeAnimationController,
      curve: Curves.easeInOut,
    );

    _tabController = TabController(length: 2, vsync: this);
    _tabController!.addListener(() {
      // Sekme geçişinde aktif index’i güncelleyelim
      if (!_tabController!.indexIsChanging) {
        setState(() {
          _currentTabIndex = _tabController!.index;
        });
      }
    });

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
        if (parts.length >= 5) {
          String convID = parts[0];
          String convTitle = parts[1];
          String modelId = parts[2];
          String lastMessageDateString = parts[3];
          String lastMessageText = parts[4];
          String lastMessagePhotoPath = parts.length >= 6 ? parts[5] : '';

          DateTime lastMessageDate =
              DateTime.tryParse(lastMessageDateString) ?? DateTime.now();

          Map<String, dynamic> modelData = _getModelDataFromId(modelId);
          bool isServerSide = modelData['isServerSide'] == true;
          bool isModelAvailable = await _isModelAvailable(modelId);
          bool isStarred = prefs.getBool('is_starred_$convID') ?? false;
          bool canHandleImage = modelData['canHandleImage'] ?? false;

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

    // ---------- YENİ EKLENEN: Starred sohbetleri de güncelle -----------
    _starredConversationIDs = _conversationIDsOrder
        .where((id) => _conversationManagers[id]?.isStarred == true)
        .toList();
    // ---------------------------------------------------------------------

    // Consistency check (değişiklik olmadan)
    for (String convID in _conversationIDsOrder) {
      if (!_conversationManagers.containsKey(convID)) {
        debugPrint(
            'Error: _conversationManagers missing entry for conversationID: $convID');
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

  Future<void> _deleteConversation(String conversationID) async {
    final prefs = await SharedPreferences.getInstance();
    final manager = _conversationManagers[conversationID];
    if (manager == null) {
      debugPrint('Warning: Attempted to delete non-existent conversationID: $conversationID');
      return;
    }

    // Silinecek sohbetin indeksini bulalım
    int removeIndex = _conversationIDsOrder.indexOf(conversationID);
    if (removeIndex < 0) {
      // Listede bulunamadıysa, yine de prefs temizleyelim.
      List<String> conversations = prefs.getStringList('conversations') ?? [];
      conversations.removeWhere((conv) => conv.startsWith('$conversationID|'));
      await prefs.setStringList('conversations', conversations);
      await prefs.remove('is_starred_$conversationID');
      await prefs.remove(conversationID);
      return;
    }

    // Silinecek yöneticiyi kaydedelim.
    final removedManager = manager;

    // Listedeki öğe sayısına göre farklı davranalım:
    final bool isLastItem = _conversationIDsOrder.length == 1;

    if (!isLastItem) {
      // 1. Durum: Birden fazla sohbet varsa
      // Veri modelinden (liste) hemen kaldırıyoruz:
      setState(() {
        _conversationIDsOrder.removeAt(removeIndex);
        _conversationManagers.remove(conversationID);
      });
    }

    // 2) AnimatedList'te animasyonlu kaldırma işlemini başlatıyoruz.
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

    if (isLastItem) {
      // 3) Eğer listede sadece tek öğe varsa, animasyonun tamamlanması için bekleyip sonra veri modelini güncelliyoruz.
      await Future.delayed(const Duration(milliseconds: 300));
      setState(() {
        _conversationIDsOrder.removeAt(removeIndex);
        _conversationManagers.remove(conversationID);
      });
    }

    // 4) SharedPreferences’dan da temizleme işlemlerini yapalım:
    List<String> conversations = prefs.getStringList('conversations') ?? [];
    conversations.removeWhere((conv) => conv.startsWith('$conversationID|'));
    await prefs.setStringList('conversations', conversations);
    await prefs.remove('is_starred_$conversationID');
    await prefs.remove(conversationID);

    // 5) Eğer bu sohbet ChatScreen'de aktifse, sıfırlayalım.
    if (mainScreenKey.currentState?.chatScreenKey.currentState?.conversationID == conversationID) {
      mainScreenKey.currentState?.chatScreenKey.currentState?.resetConversation();
    }

    // 6) Sunucu taraflı sohbetlerde Firestore güncellemesi:
    if (removedManager.isServerSide) {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          if (hasInternetConnection) {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .update({'conversations': FieldValue.increment(-1)});
          } else {
            int convMinus = prefs.getInt('conversationsMinus') ?? 0;
            convMinus += 1;
            await prefs.setInt('conversationsMinus', convMinus);
          }
        } catch (e) {
          debugPrint("Error decrementing conversations count in Firestore: $e");
          int convMinus = prefs.getInt('conversationsMinus') ?? 0;
          convMinus += 1;
          await prefs.setInt('conversationsMinus', convMinus);
        }
      }
    }

    // 7) Bildirimi gösterelim.
    _notificationService.showNotification(
      message: AppLocalizations.of(context)!.conversationDeleted,
      isSuccess: true,
    );
  }

  Map<String, dynamic> _getModelDataFromId(String modelId) {
    List<Map<String, dynamic>> allModels = ModelData.models(context);

    String mainId = modelId.contains('-') ? modelId.split('-')[0] : modelId;

    Map<String, dynamic> model = allModels.firstWhere(
          (m) => m['id'] == mainId,
      orElse: () => {
        'title': 'Unknown Model',
        'image': '',
        'description': '',
        'producer': '',
        'isServerSide': false,
        'canHandleImage': false,
      },
    );

    if (model['title'] == 'Unknown Model') {
      debugPrint('Error: No model found for modelId: $modelId (using mainId: $mainId)');
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

  Widget _buildAnimatedStarredRemovalItem(String conversationID, Animation<double> animation) {
    final manager = _conversationManagers[conversationID];
    if (manager == null) {
      debugPrint('Warning: ConversationManager for ID $conversationID is null.');
      return const SizedBox.shrink();
    }
    final curvedAnimation = CurvedAnimation(parent: animation, curve: Curves.easeInOut);
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
        manager: manager,
        hideWhenUnstarred: false,
        onDelete: () => _deleteConversation(conversationID),
        onEdit: (newTitle) => _editConversation(conversationID, newTitle),
        onToggleStar: () => _toggleStarredStatus(conversationID),
      ),
    );
  }

  Future<void> _toggleStarredStatus(String conversationID) async {
    final prefs = await SharedPreferences.getInstance();
    final manager = _conversationManagers[conversationID];
    if (manager == null) return;

    bool newVal = !manager.isStarred;

    // Eğer yıldızlı liste görünümündeysek ve sohbetin yıldızı kaldırılıyorsa:
    if (_currentTabIndex == 1 && !newVal) {
      int starredIndex = _starredConversationIDs.indexOf(conversationID);
      if (starredIndex != -1) {
        // Eğer listedeki öğe sayısı 1 ise (yani son öğe) farklı davranalım:
        bool isLastStarred = _starredConversationIDs.length == 1;
        if (!isLastStarred) {
          // Birden fazla öğe varsa: Önce listeden kaldır, sonra animasyon çalıştır.
          setState(() {
            _starredConversationIDs.removeAt(starredIndex);
          });
          _starredChatsListKey.currentState?.removeItem(
            starredIndex,
                (context, animation) =>
                _buildAnimatedStarredRemovalItem(conversationID, animation),
            duration: const Duration(milliseconds: 300),
          );
        } else {
          // Eğer listede yalnızca bir öğe varsa:
          // 1) AnimatedList üzerinden kaldırma animasyonunu başlatıyoruz.
          _starredChatsListKey.currentState?.removeItem(
            starredIndex,
                (context, animation) =>
                _buildAnimatedStarredRemovalItem(conversationID, animation),
            duration: const Duration(milliseconds: 300),
          );
          // 2) Animasyonun tamamlanması için bekliyoruz, ardından veri kaynağından kaldırıyoruz.
          await Future.delayed(const Duration(milliseconds: 300));
          setState(() {
            _starredConversationIDs.removeAt(starredIndex);
          });
        }
      }
    }

    // Durum güncellemesi ve prefs’e yazma:
    manager.setStarred(newVal);
    await prefs.setBool('is_starred_$conversationID', newVal);

    // Yıldızlı sohbetler listesini yeniden hesaplayalım:
    setState(() {
      _starredConversationIDs = _conversationIDsOrder
          .where((id) => _conversationManagers[id]?.isStarred == true)
          .toList();
    });

    // Eğer sohbet yeni yıldızlandıysa (insert animasyonu):
    if (_currentTabIndex == 1 && newVal) {
      int insertIndex = _starredConversationIDs.indexOf(conversationID);
      if (insertIndex == -1) {
        insertIndex = _starredConversationIDs.length;
      }
      _starredChatsListKey.currentState?.insertItem(
        insertIndex,
        duration: const Duration(milliseconds: 300),
      );
    }
  }

  Widget _buildAnimatedStarredListItem(
      String conversationID, Animation<double> animation) {
    final manager = _conversationManagers[conversationID];
    if (manager == null) {
      debugPrint('Warning: ConversationManager for ID $conversationID is null.');
      return const SizedBox.shrink();
    }
    final curvedAnimation =
    CurvedAnimation(parent: animation, curve: Curves.easeInOut);
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
        manager: manager,
        hideWhenUnstarred: false,
        onDelete: () => _deleteConversation(conversationID),
        onEdit: (newTitle) => _editConversation(conversationID, newTitle),
        onToggleStar: () => _toggleStarredStatus(conversationID),
      ),
    );
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

  Widget _buildConversationList({required bool showStarredOnly}) {
    final localizations = AppLocalizations.of(context)!;

    if (showStarredOnly) {
      // Yıldızlı sohbetler için dış katmanı AnimatedSwitcher ile sarmıyoruz.
      if (_isLoading) {
        return _SkeletonChatList(key: const ValueKey('skeleton'));
      } else if (_starredConversationIDs.isEmpty) {
        return TweenAnimationBuilder<double>(
          key: const ValueKey('empty'),
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 300),
          builder: (context, opacity, child) {
            return Opacity(opacity: opacity, child: child);
          },
          child: Align(
            alignment: Alignment.center,
            child: Padding(
              padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.04),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    localizations.noStarredChats,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      color: AppColors.opposedPrimaryColor,
                      fontSize: MediaQuery.of(context).size.width * 0.08,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.005),
                  Text(
                    localizations.noStarredChatsMessage,
                    style: TextStyle(
                      color: AppColors.tertiaryColor,
                      fontSize: MediaQuery.of(context).size.width * 0.04,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.01),
                  ElevatedButton(
                    onPressed: () {
                      DefaultTabController.of(context)?.animateTo(0);
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.opposedPrimaryColor,
                      padding: EdgeInsets.symmetric(
                        horizontal: MediaQuery.of(context).size.width * 0.08,
                        vertical: MediaQuery.of(context).size.height * 0.015,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(MediaQuery.of(context).size.width * 0.02),
                      ),
                    ),
                    child: Text(
                      localizations.goToChats,
                      style: TextStyle(
                        color: AppColors.primaryColor,
                        fontSize: MediaQuery.of(context).size.width * 0.04,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        return AnimatedList(
          key: _starredChatsListKey,
          initialItemCount: _starredConversationIDs.length,
          itemBuilder: (context, index, animation) {
            if (index >= _starredConversationIDs.length) return const SizedBox.shrink();
            final convID = _starredConversationIDs[index];
            return _buildAnimatedStarredListItem(convID, animation);
          },
        );
      }
    } else {
      // Normal sohbetler listesini oluştururken AnimatedSwitcher kullanmaya devam ediyoruz.
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: _isLoading
            ? _SkeletonChatList(key: const ValueKey('skeleton'))
            : (_conversationIDsOrder.isEmpty
            ? TweenAnimationBuilder<double>(
          key: const ValueKey('empty'),
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 300),
          builder: (context, opacity, child) {
            return Opacity(opacity: opacity, child: child);
          },
          child: Align(
            alignment: Alignment.center,
            child: Padding(
              padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.04),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    localizations.noChats,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      color: AppColors.opposedPrimaryColor,
                      fontSize: MediaQuery.of(context).size.width * 0.08,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.005),
                  Text(
                    localizations.noConversationsMessage,
                    style: TextStyle(
                      color: AppColors.tertiaryColor,
                      fontSize: MediaQuery.of(context).size.width * 0.04,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.01),
                  ElevatedButton(
                    onPressed: () {
                      mainScreenKey.currentState?.onItemTapped(0);
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.opposedPrimaryColor,
                      padding: EdgeInsets.symmetric(
                        horizontal: MediaQuery.of(context).size.width * 0.08,
                        vertical: MediaQuery.of(context).size.height * 0.015,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(MediaQuery.of(context).size.width * 0.02),
                      ),
                    ),
                    child: Text(
                      localizations.startChat,
                      style: TextStyle(
                        color: AppColors.primaryColor,
                        fontSize: MediaQuery.of(context).size.width * 0.04,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        )
            : AnimatedList(
          key: _allChatsListKey,
          initialItemCount: _conversationIDsOrder.length,
          itemBuilder: (context, index, animation) {
            final convID = _conversationIDsOrder[index];
            return _buildAnimatedListItem(convID, animation);
          },
        )),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    super.build(context);

    final localizations = AppLocalizations.of(context)!;
    final screenWidth = MediaQuery.of(context).size.width;

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
                  color: AppColors.opposedPrimaryColor,
                  fontSize: screenWidth * 0.06,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: AppColors.background,
              elevation: 0,
              actions: [
                IconButton(
                  icon: SvgPicture.asset(
                    'assets/chat.svg',
                    color: AppColors.primaryColor,
                    width: screenWidth * 0.055,
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
                      controller: _tabController, // Kendi oluşturduğunuz _tabController'ı kullanın.
                      isScrollable: false,
                      indicator: UnderlineTabIndicator(
                        borderSide: BorderSide(
                          width: screenWidth * 0.004,
                          color: AppColors.opposedPrimaryColor,
                        ),
                        insets: EdgeInsets.zero,
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: AppColors.opposedPrimaryColor,
                      unselectedLabelColor: Colors.grey,
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
            backgroundColor: AppColors.background,
            body: TabBarView(
              controller: _tabController, // Kendi _tabController'ınızı burada da geçin.
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
    with TickerProviderStateMixin {
  final GlobalKey _threeDotKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  late AnimationController _animationController;
  bool _isDisposed = false;

  Timer? _longPressTimer;
  bool _isLongPress = false;

  static _ConversationTileState? _currentlyOpenTileState;

  bool _isDialogOpen = false;

  String _displayedTitle = "";
  String _oldTitle = "";
  late AnimationController _fadeOutController;
  late AnimationController _fadeInController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _displayedTitle = widget.manager.conversationTitle;
    _fadeOutController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
      setState(() {});
    });
    _fadeInController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
      setState(() {});
    });
    widget.manager.addListener(_onManagerChanged);
  }

  void _onManagerChanged() {
    if (widget.manager.conversationTitle != _displayedTitle) {
      // Herhangi bir animasyon devam ediyorsa resetleyelim:
      _fadeOutController.reset();
      _fadeInController.reset();
      _oldTitle = _displayedTitle;
      // Eski başlığı fade-out ile soldan sağa (aslında metnin sonundan başa doğru) kaybettiriyoruz:
      _fadeOutController.forward(from: 0.0).whenComplete(() {
        setState(() {
          _displayedTitle = widget.manager.conversationTitle;
        });
        // Yeni başlık, soldan sağa doğru fade-in ile gelsin:
        _fadeInController.forward(from: 0.0);
      });
    }
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
    _fadeOutController.dispose();
    _fadeInController.dispose();
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

  /// Dinamik değerlerle ve sabit satır yüksekliğiyle animasyonlu başlık oluşturur.
  Widget _buildAnimatedTitle(String text, AnimationController controller, bool reverse) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Dinamik değerler: font boyutu ve satır yüksekliği
    final double fontSize = screenWidth * 0.045;
    final double lineHeight = 1.2;
    // Sabit yükseklik: fontSize * lineHeight
    final double fixedHeight = fontSize * lineHeight;

    int n = text.length;
    // Karakter sayısına göre delay değeri:
    double delayNormalized = n > 8 ? 0.8 / (n - 1) : 0.05;
    List<InlineSpan> spans = [];
    for (int i = 0; i < n; i++) {
      double start, end;
      if (reverse) {
        // Fade-out: metnin son karakterinden başa doğru
        int j = n - 1 - i;
        start = j * delayNormalized;
        end = start + 0.2; // 100ms/500ms = 0.2 normalized
      } else {
        // Fade-in: metnin başından sona doğru
        start = i * delayNormalized;
        end = start + 0.2;
      }
      double t = controller.value;
      double opacity;
      if (!reverse) {
        if (t < start)
          opacity = 0.0;
        else if (t > end)
          opacity = 1.0;
        else
          opacity = (t - start) / (end - start);
      } else {
        if (t < start)
          opacity = 1.0;
        else if (t > end)
          opacity = 0.0;
        else
          opacity = 1.0 - (t - start) / (end - start);
      }
      spans.add(TextSpan(
        text: text[i],
        style: GoogleFonts.poppins(
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
          height: lineHeight,
          color: (AppColors.primaryColor).withOpacity(opacity),
        ),
      ));
    }

    // Baseline metin; görünmez olmasına rağmen alanı tutar:
    final baseline = Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        height: lineHeight,
        color: (AppColors.opposedPrimaryColor),
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
    );

    return SizedBox(
      height: fixedHeight,
      child: Stack(
        alignment: Alignment.topLeft, // Üst sol hizalama
        children: [
          // Alanı sabit tutmak için görünmez baseline
          Opacity(
            opacity: 0.0,
            child: baseline,
          ),
          RichText(
            text: TextSpan(children: spans),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textHeightBehavior: const TextHeightBehavior(
              applyHeightToFirstAscent: false,
              applyHeightToLastDescent: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedTitleWidget() {
    final screenWidth = MediaQuery.of(context).size.width;
    TextStyle textStyle = GoogleFonts.poppins(
      fontSize: screenWidth * 0.045,
      fontWeight: FontWeight.w500,
      height: 1.2,
      color: AppColors.opposedPrimaryColor,
    );

    if (_fadeOutController.isAnimating) {
      return _buildAnimatedTitle(_oldTitle, _fadeOutController, true);
    }
    if (_fadeInController.isAnimating) {
      return _buildAnimatedTitle(_displayedTitle, _fadeInController, false);
    }
    return FadingOverflowText(
      text: _displayedTitle,
      style: textStyle,
      maxLines: 1,
      textAlign: TextAlign.start,
    );
  }

  void _showActionPanel() {
    if (_overlayEntry != null) return;

    if (_currentlyOpenTileState != null && _currentlyOpenTileState != this) {
      _currentlyOpenTileState?._removeOverlay(animate: false);
      _currentlyOpenTileState = null;
    }

    final loc = AppLocalizations.of(context)!;

    final renderBox = _threeDotKey.currentContext!.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    final double panelHeight = screenHeight * 0.2;
    final double panelWidth = screenWidth * 0.3;
    final bool openUpwards = (offset.dy + size.height + panelHeight + 20) > screenHeight;

    double panelTop = openUpwards ? (offset.dy - panelHeight) : (offset.dy + size.height);
    double panelRight = screenWidth - (offset.dx + size.width);


    final chatCardBackgroundColor = AppColors.quaternaryColor.withOpacity(0.85);

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
                          // Panelin arka plan rengi artık sohbet kartı ile aynı:
                          color: chatCardBackgroundColor,
                          borderRadius: BorderRadius.circular(screenWidth * 0.02),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.shadow,
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
                                  iconAsset: widget.manager.isStarred
                                      ? 'assets/star.svg'
                                      : 'assets/starBordered.svg',
                                  iconColor: widget.manager.isStarred
                                      ? Colors.amber
                                      : AppColors.opposedPrimaryColor,
                                  text: loc.starConversation,
                                  textColor: AppColors.opposedPrimaryColor,
                                  onPressed: () async {
                                    await _removeOverlayWithAnimation();
                                    widget.onToggleStar();
                                  },
                                ),
                                SizedBox(height: screenHeight * 0.01),
                                _ActionPanelButton(
                                  iconAsset: 'assets/editConversationTitle.svg',
                                  iconColor: AppColors.opposedPrimaryColor,
                                  text: loc.editConversationTitle,
                                  textColor: AppColors.opposedPrimaryColor,
                                  onPressed: () {
                                    _showEditDialog(loc);
                                    _removeOverlay();
                                  },
                                ),
                                SizedBox(height: screenHeight * 0.01),
                                _ActionPanelButton(
                                  iconAsset: 'assets/delete.svg',
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

// Updated _ConversationTileState._showEditDialog (signature updated)
  void _showEditDialog(AppLocalizations loc) {
    if (_isDialogOpen) return; // Prevent multiple dialogs
    _isDialogOpen = true;

    final TextEditingController controller = TextEditingController(
      text: widget.manager.conversationTitle,
    );
    final screenWidth = MediaQuery.of(context).size.width;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "EditConversationTitle",
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: screenWidth * 0.8,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(screenWidth * 0.03),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Üst kısım: Başlık ve input field
                  Padding(
                    padding: EdgeInsets.all(screenWidth * 0.04),
                    child: Column(
                      children: [
                        Text(
                          loc.editConversationTitle,
                          style: TextStyle(
                            color: AppColors.opposedPrimaryColor,
                            fontSize: screenWidth * 0.05,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: screenWidth * 0.04),
                        TextField(
                          controller: controller,
                          decoration: InputDecoration(
                            labelText: loc.newTitle,
                            labelStyle: TextStyle(
                              color: AppColors.opposedPrimaryColor,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: AppColors.textFieldBorder,
                              ),
                              borderRadius:
                              BorderRadius.circular(screenWidth * 0.02),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: AppColors.opposedPrimaryColor,
                              ),
                              borderRadius:
                              BorderRadius.circular(screenWidth * 0.02),
                            ),
                          ),
                          style: TextStyle(
                            color: AppColors.opposedPrimaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    color: AppColors.dialogDivider,
                    thickness: 0.5,
                    height: 1,
                  ),
                  IntrinsicHeight(
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                              padding: EdgeInsets.symmetric(
                                  vertical: screenWidth * 0.04),
                            ),
                            child: Text(
                              loc.cancel,
                              style:
                              TextStyle(fontSize: screenWidth * 0.035),
                            ),
                          ),
                        ),
                        VerticalDivider(
                          color: AppColors.dialogDivider,
                          thickness: 0.5,
                          width: 1,
                        ),
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              String newText = controller.text.trim();
                              if (newText.isNotEmpty) {
                                widget.onEdit(newText);
                              }
                              Navigator.of(ctx).pop();
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.blue,
                              padding: EdgeInsets.symmetric(
                                  vertical: screenWidth * 0.04),
                            ),
                            child: Text(
                              loc.save,
                              style:
                              TextStyle(fontSize: screenWidth * 0.035),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    ).then((_) {
      _isDialogOpen = false;
    });
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
    final screenWidth = MediaQuery.of(context).size.width;
    TextStyle messageStyle = TextStyle(
      color: AppColors.tertiaryColor,
      fontSize: screenWidth * 0.03,
    );

    if (lastPhotoPath.isNotEmpty) {
      if (lastMessageText.trim().isNotEmpty) {
        return Row(
          children: [
            SvgPicture.asset(
              'assets/photo.svg',
              width: screenWidth * 0.04,
              height: screenWidth * 0.04,
              color: AppColors.tertiaryColor,
            ),
            SizedBox(width: screenWidth * 0.01),
            Expanded(
              child: FadingOverflowText(
                text: lastMessageText,
                style: messageStyle,
                maxLines: 1,
                textAlign: TextAlign.start,
              ),
            ),
          ],
        );
      } else {
        return SvgPicture.asset(
          'assets/photo.svg',
          width: screenWidth * 0.04,
          height: screenWidth * 0.04,
          color: AppColors.tertiaryColor,
        );
      }
    } else {
      return FadingOverflowText(
        text: lastMessageText,
        style: messageStyle,
        maxLines: 1,
        textAlign: TextAlign.start,
      );
    }
  }

  void _navigateToChatScreen() {
    mainScreenKey.currentState?.openConversation(widget.manager);
  }

  String formatExtension(String ext) {
    List<String> parts = ext.split('-');
    List<String> capitalizedParts = parts.map((s) {
      if (s.isEmpty) return s;
      return s[0].toUpperCase() + s.substring(1);
    }).toList();
    return capitalizedParts.join(" ");
  }

// Updated _ConversationTileState.build
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final Color backgroundColor = AppColors.quaternaryColor;
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
          horizontal: screenWidth * 0.03,
          vertical: screenHeight * 0.01,
        ),
        padding: EdgeInsets.all(screenWidth * 0.04),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(screenWidth * 0.03),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow,
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
                  width: screenWidth * 0.15,
                  height: screenWidth * 0.15,
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
                    size: screenWidth * 0.075,
                  )
                      : null,
                ),
                SizedBox(width: screenWidth * 0.02),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Baseline(
                              baseline: screenWidth * 0.045 * 0.8,
                              baselineType: TextBaseline.alphabetic,
                              child: _buildAnimatedTitleWidget(),
                            ),
                          ),
                          SizedBox(width: screenWidth * 0.02),
                          Baseline(
                            baseline: screenWidth * 0.045 * 0.8,
                            baselineType: TextBaseline.alphabetic,
                            child: Text(
                              _formatDate(widget.manager.lastMessageDate),
                              style: TextStyle(
                                color: AppColors.tertiaryColor,
                                fontSize: screenWidth * 0.03,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.manager.modelTitle +
                                  (widget.manager.modelId.contains('-')
                                      ? " " +
                                      formatExtension(
                                        widget.manager.modelId
                                            .split('-')
                                            .sublist(1)
                                            .join('-'),
                                      )
                                      : ""),
                              style: GoogleFonts.poppins(
                                fontSize: screenWidth * 0.03,
                                fontWeight: FontWeight.w400,
                                color: AppColors.opposedPrimaryColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: screenHeight * 0.002),
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
    // Varsayılan kapsayıcı boyutu, örneğin diğer ikonlar için kullanılan boyut
    final double defaultIconContainerSize = screenWidth * 0.05;
    // Eğer star.svg veya starBordered.svg kullanılıyorsa, ikon boyutunu biraz küçülteceğiz;
    // ancak kapsayıcı boyutu defaultIconContainerSize olacak.
    final double iconSize = (iconAsset != null &&
        (iconAsset == 'assets/star.svg' || iconAsset == 'assets/starBordered.svg'))
        ? screenWidth * 0.04
        : defaultIconContainerSize;

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
        crossAxisAlignment: CrossAxisAlignment.center, // Dikeyde ortalamak için
        children: [
          if (iconAsset != null)
          // Kapsayıcıya sabit boyut veriyoruz; ikon, boyutu küçültülse bile container aynı kalır.
            Container(
              width: defaultIconContainerSize,
              height: defaultIconContainerSize,
              alignment: Alignment.center,
              child: SvgPicture.asset(
                iconAsset!,
                color: iconColor,
                width: iconSize,
                height: iconSize,
              ),
            ),
          if (icon != null)
            Container(
              width: defaultIconContainerSize,
              height: defaultIconContainerSize,
              alignment: Alignment.center,
              child: Icon(
                icon,
                color: iconColor,
                size: iconSize,
              ),
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


// Updated _SkeletonChatTile.build
class _SkeletonChatTile extends StatelessWidget {
  const _SkeletonChatTile({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Define padding similar to ConversationTile
    final horizontalPadding = screenWidth * 0.03;
    final verticalPadding = screenHeight * 0.01;

    // Calculate container width based on padding
    final containerWidth =
        screenWidth - 2 * (horizontalPadding + screenWidth * 0.04);

    // Define height based on image size and padding
    final imageSize = screenWidth * 0.15;
    final containerHeight = imageSize + 2 * (screenHeight * 0.02);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      child: Shimmer.fromColors(
        baseColor: AppColors.shimmerBase,
        highlightColor: AppColors.shimmerHighlight,
        child: Container(
          width: containerWidth,
          height: containerHeight,
          decoration: BoxDecoration(
            color: AppColors.tertiaryColor,
            borderRadius: BorderRadius.circular(screenWidth * 0.03),
          ),
        ),
      ),
    );
  }
}

class FadingOverflowText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final int maxLines;

  /// Varsayılan olarak son 4 karakteri fade'lemek isteriz
  final int fadeCharsCount;

  /// Son fade edilecek karakterlerin opaklıkları (soldan sağa).
  /// Örneğin [0.8, 0.6, 0.4, 0.2].
  final List<double> fadeOpacities;

  const FadingOverflowText({
    Key? key,
    required this.text,
    this.style,
    this.textAlign = TextAlign.start,
    this.maxLines = 1,
    this.fadeCharsCount = 4,
    this.fadeOpacities = const [0.8, 0.6, 0.4, 0.2],
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 1) Önce metnin "sığıp sığmadığını" ölçüyoruz.
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: maxLines,
      textDirection: Directionality.of(context),
    );

    // Bu ölçümü yaparken genişliği "sonsuz" alıyoruz,
    // bu durumda metin kesinlikle tek satıra sığmayabilir.
    textPainter.layout(minWidth: 0, maxWidth: double.infinity);

    bool isOverflowing = textPainter.didExceedMaxLines;

    // 2) Taşma yoksa direkt normal Text döndür
    if (!isOverflowing) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: TextOverflow.clip,
        textAlign: textAlign,
      );
    }

    // 3) Taşma varsa, "char by char fade" uyguluyoruz.
    final int n = text.length;

    // Eğer metin fadeCharsCount karakterden kısaysa, eldeki karakter kadar fade uyguluyoruz.
    final int actualFadeCount = (n < fadeCharsCount) ? n : fadeCharsCount;

    // Fade'e başlayacağımız index (örn. n - 4)
    final int fadeStartIndex = n - actualFadeCount;

    // Normal kısım: 0..(fadeStartIndex)
    final String normalPart = text.substring(0, fadeStartIndex);

    // Fade uygulanacak kısım: (fadeStartIndex..n)
    final String fadingPart = text.substring(fadeStartIndex);

    // Her karakterin opaklığını fadeOpacities dizisinden alıyoruz.
    List<double> opacitiesToUse = [];
    for (int i = 0; i < actualFadeCount; i++) {
      if (i < fadeOpacities.length) {
        opacitiesToUse.add(fadeOpacities[i]);
      } else {
        opacitiesToUse.add(fadeOpacities.last);
      }
    }

    // RichText kullanarak karakter karakter fade efekti uyguluyoruz:
    List<InlineSpan> spans = [];

    // Normal kısım (tam opak)
    if (normalPart.isNotEmpty) {
      spans.add(TextSpan(
        text: normalPart,
        style: style,
      ));
    }

    // Fade uygulanacak kısım: her karakter için opaklık ayarlanıyor.
    for (int i = 0; i < fadingPart.length; i++) {
      double fadeOpacity = (i < opacitiesToUse.length)
          ? opacitiesToUse[i]
          : opacitiesToUse.last;

      spans.add(TextSpan(
        text: fadingPart[i],
        style: style?.copyWith(
          color: style?.color?.withOpacity(fadeOpacity),
        ),
      ));
    }

    return RichText(
      maxLines: maxLines,
      overflow: TextOverflow.clip,
      textAlign: textAlign,
      text: TextSpan(children: spans),
    );
  }
}