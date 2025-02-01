// main.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'models.dart';
import 'download.dart';
import 'menu.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'locale_provider.dart';
import 'login.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'notifications.dart';
import 'theme.dart';
import 'dart:async';

// Bu key'i saklıyoruz (silmedik).
final GlobalKey<MainScreenState> mainScreenKey = GlobalKey<MainScreenState>();

// **ÖNEMLİ GÜNCELLEME**: Tekil (singleton) MainScreen örneğini tanımlıyoruz.
// Tüm projede sadece bu "mainScreen" kullanılacak.
final MainScreen mainScreen = MainScreen(key: mainScreenKey);

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class TabProvider with ChangeNotifier {
  int _selectedIndex = 0;

  int get selectedIndex => _selectedIndex;

  void setSelectedIndex(int index) {
    if (_selectedIndex != index) {
      _selectedIndex = index;
      notifyListeners();
    }
  }
}

Future<void> requestNotificationPermission() async {
  var status = await Permission.notification.status;

  if (!status.isGranted) {
    status = await Permission.notification.request();

    if (status.isGranted) {
      print('Bildirim izni verildi');
    } else {
      print('Bildirim izni reddedildi');
    }
  } else {
    print('Bildirim izni zaten verildi');
  }
}

Future<void> _checkAndUpdateSubscription() async {
  User? user = FirebaseAuth.instance.currentUser;
  if (user == null) return; // Kullanıcı giriş yapmamışsa, hiçbir şey yapma

  final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

  DocumentSnapshot userDoc = await userDocRef.get();

  if (!userDoc.exists) {
    print("User document does not exist. Skipping subscription update.");
    return;
  }

  Map<String, dynamic>? data = userDoc.data() as Map<String, dynamic>?;
  int currentSubscription = (data != null && data.containsKey('hasCortexSubscription'))
      ? data['hasCortexSubscription']
      : 0;

  final Stream<List<PurchaseDetails>> purchaseUpdated =
      InAppPurchase.instance.purchaseStream;

  purchaseUpdated.listen((purchases) async {
    int highestSubscriptionLevel = 0;

    for (var purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        int level = _getSubscriptionLevel(purchase.productID);
        if (level > highestSubscriptionLevel) {
          highestSubscriptionLevel = level;
        }
      }
    }

    if (highestSubscriptionLevel == 0) {
      if (currentSubscription == 4 || currentSubscription == 5 || currentSubscription == 6) {
        print('Mevcut abonelik seviyesi 4, 5 veya 6 olduğu için güncelleme yapılmıyor.');
        return;
      }
    }

    await userDocRef.update({'hasCortexSubscription': highestSubscriptionLevel});
    print('hasCortexSubscription güncellendi: $highestSubscriptionLevel');
  });

  await InAppPurchase.instance.restorePurchases();
}

int _getSubscriptionLevel(String productId) {
  if (productId == 'vertex_ai_monthly_sub' ||
      productId == 'vertex_ai_annual_sub') {
    return 1; // Plus
  } else if (productId == 'cortex_pro_monthly' ||
      productId == 'cortex_pro_annual') {
    return 2; // Pro
  } else if (productId == 'cortex_ultra_monthly' ||
      productId == 'cortex_ultra_annual') {
    return 3; // Ultra
  }
  return 0;
}

void main() async {
  await dotenv.load(fileName: ".env");
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await requestNotificationPermission();
  await FlutterDownloader.initialize();
  final fileDownloadHelper = FileDownloadHelper();
  final menuState = mainScreenKey.currentState?.menuScreenKey.currentState;
  if (menuState != null) {
    await menuState.applyPendingConversationsDecrement();
  }
  await _checkAndUpdateSubscription();

  final prefs = await SharedPreferences.getInstance();
  bool? isDarkTheme = prefs.getBool('isDarkTheme');
  if (isDarkTheme == null) {
    Brightness brightness = WidgetsBinding.instance.window.platformBrightness;
    isDarkTheme = brightness == Brightness.dark;
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => FileDownloadHelper()),
        ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(isDarkTheme!),
        ),
        ChangeNotifierProvider<LocaleProvider>(
          create: (_) => LocaleProvider(),
        ),
        ChangeNotifierProvider(create: (_) => TabProvider()),
      ],
      child: ChatApp(navigatorKey: navigatorKey),
    ),
  );
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key, required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        // Tema değişikliklerini ThemeProvider yönetiyor, bu yüzden burada ekstra bir şey yapmanıza gerek yok
        return MaterialApp(
          navigatorKey: navigatorKey,
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: Colors.black,
            colorScheme: const ColorScheme.light(
              primary: Colors.black,
              onPrimary: Colors.white,
              secondary: Colors.grey,
              onSecondary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
              error: Colors.red,
            ),
            textSelectionTheme: TextSelectionThemeData(
              cursorColor: Colors.black,
              selectionColor: Colors.grey[200],
            ),
            inputDecorationTheme: const InputDecorationTheme(
              focusColor: Colors.black,
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: Colors.white,
            colorScheme: ColorScheme.dark(
              primary: Colors.white,
              onPrimary: Colors.black,
              secondary: Colors.white,
              onSecondary: Colors.black,
              surface: Colors.black,
              onSurface: Colors.white,
              error: Colors.red[400]!,
            ),
            textSelectionTheme: TextSelectionThemeData(
              cursorColor: Colors.white,
              selectionColor: Colors.grey[200],
            ),
            inputDecorationTheme: const InputDecorationTheme(
              focusColor: Colors.white,
            ),
          ),
          themeMode:
          themeProvider.isDarkTheme ? ThemeMode.dark : ThemeMode.light,
          locale: Provider.of<LocaleProvider>(context).locale,
          supportedLocales: const [
            Locale('en'),
            Locale('tr'),
          ],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          localeResolutionCallback: (locale, supportedLocales) {
            final localeProvider =
            Provider.of<LocaleProvider>(context, listen: false);
            return localeProvider.locale;

            if (locale != null &&
                supportedLocales.any((supportedLocale) =>
                supportedLocale.languageCode == locale.languageCode)) {
              return locale;
            }
            return const Locale('en');
          },
          builder: (context, child) {
            return Provider<NotificationService>(
              create: (_) => NotificationService(navigatorKey: navigatorKey),
              child: child ?? const SizedBox(),
            );
          },
          home: const AuthWrapper(),
        );
      },
    );
  }
}


class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  Future<bool> _checkRememberMe() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    bool rememberMe = prefs.getBool('remember_me') ?? false;
    User? user = FirebaseAuth.instance.currentUser;
    return rememberMe && user != null;
  }

  Future<Widget> _decideScreen() async {
    // 1) Remember me ve user var mı?
    bool hasRememberAndUser = await _checkRememberMe();
    User? user = FirebaseAuth.instance.currentUser;
    if (!hasRememberAndUser || user == null) {
      return const LoginScreen();
    }

    // 2) Kullanıcı bilgisini yenileyelim
    try {
      await user.reload();
    } catch (e) {
      print("Kullanıcı bilgileri reload edilemedi: $e");
      // Eğer reload edilemiyorsa (örneğin offline durumdaysak) direkt ana ekrana gönderiyoruz.
      return mainScreen;
    }

    // 3) Firebase Auth üzerinden e-mail doğrulama durumunu kontrol edelim:
    if (user.emailVerified) {
      // Doğrulanmış hesaplar direkt ana ekrana yönlendirilecek.
      return mainScreen;
    } else {
      // Doğrulanmamış hesaplar için Firestore’daki kullanıcı belgesinden bazı bilgileri alıp,
      // EmailVerificationScreen’e yönlendiriyoruz.
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (!userDoc.exists) {
          return const LoginScreen();
        }

        final data = userDoc.data()!;
        return EmailVerificationScreen(
          email: data['email'] ?? '',
          username: data['username'] ?? '',
          userId: user.uid,
          password: '', // İhtiyaç duyuluyorsa bu alan doldurulabilir.
        );
      } catch (e) {
        print("Firestore sorgusunda hata oluştu: $e");
        return const LoginScreen();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return FutureBuilder<Widget>(
      future: _decideScreen(),
      builder: (context, snapshot) {
        // Future sonucu bekleniyorsa loading ekranı, tamamlandıysa ilgili ekran.
        Widget child;
        if (snapshot.connectionState == ConnectionState.waiting) {
          child = Container(
            key: const ValueKey('loading'),
            width: double.infinity,
            height: double.infinity,
            color: themeProvider.isDarkTheme
                ? const Color(0xFF090909)
                : const Color(0xFFFFFFFF),
          );
        } else {
          child = snapshot.hasData
              ? snapshot.data!
              : const LoginScreen(key: ValueKey('login'));
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeIn,
          switchOutCurve: Curves.easeOut,
          transitionBuilder: (widget, animation) => FadeTransition(
            opacity: animation,
            child: widget,
          ),
          child: child,
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  MainScreenState createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey<ChatScreenState> chatScreenKey = GlobalKey<ChatScreenState>();
  final GlobalKey<MenuScreenState> menuScreenKey = GlobalKey<MenuScreenState>();

  late final List<Widget> _screens;

  bool hideBottomAppBar = false;

  @override
  void initState() {
    super.initState();
    _screens = [
      ChatScreen(key: chatScreenKey),
      const ModelsScreen(key: ValueKey('Models')),
      MenuScreen(key: menuScreenKey),
    ];
  }

  void onItemTapped(int index) {
    final tabProvider = Provider.of<TabProvider>(context, listen: false);
    tabProvider.setSelectedIndex(index);
  }

  void updateBottomAppBarVisibility([bool value = false]) {
    setState(() {
      hideBottomAppBar = value;
    });

    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    themeProvider.updateSystemUIOverlayStyle(hideBottomAppBar: hideBottomAppBar);
  }

  void openConversation(ConversationManager manager) {
    final tabProvider = Provider.of<TabProvider>(context, listen: false);
    tabProvider.setSelectedIndex(0);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      chatScreenKey.currentState?.loadConversation(manager);
      chatScreenKey.currentState?.setState(() {
        chatScreenKey.currentState?.isModelSelected = true;
        chatScreenKey.currentState?.isModelLoaded = true;
      });

      // BottomAppBar'ın görünürlüğünü güncelle
      updateBottomAppBarVisibility(true);
    });
  }

  void startNewConversation() {
    final tabProvider = Provider.of<TabProvider>(context, listen: false);
    tabProvider.setSelectedIndex(0);
    chatScreenKey.currentState?.resetConversation();

    // BottomAppBar'ın görünürlüğünü güncelle
    updateBottomAppBarVisibility(false);
  }

  @override
  Widget build(BuildContext context) {
    final tabProvider = Provider.of<TabProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkTheme = themeProvider.isDarkTheme;
    final appLocalizations = AppLocalizations.of(context)!;
    final screenHeight = MediaQuery.of(context).size.height;

    // BottomAppBar'ın görünürlüğünü güncelle
    bool shouldHideBottomAppBar = false;
    if (tabProvider.selectedIndex == 0 && chatScreenKey.currentState != null) {
      shouldHideBottomAppBar = chatScreenKey.currentState!.isModelSelected;
    } else {
      shouldHideBottomAppBar = false;
    }

    if (hideBottomAppBar != shouldHideBottomAppBar) {
      updateBottomAppBarVisibility(shouldHideBottomAppBar);
    }

    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      },
      child: Scaffold(
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
          child: _screens[tabProvider.selectedIndex],
          switchInCurve: Curves.easeIn,
          switchOutCurve: Curves.easeOut,
        ),
        bottomNavigationBar: shouldHideBottomAppBar
            ? null
            : Container(
          decoration: BoxDecoration(
            color: isDarkTheme ? const Color(0xFF090909) : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16.0),
              topRight: Radius.circular(16.0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: BottomAppBar(
            color: Colors.transparent,
            elevation: 0,
            child: SizedBox(
              height: screenHeight * 0.09, // Dinamik yükseklik
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  // Inbox
                  Expanded(
                    child: BottomNavigationButton(
                      iconPath: 'assets/inbox.svg',
                      label: appLocalizations.chats,
                      isSelected: tabProvider.selectedIndex == 2,
                      onTap: tabProvider.selectedIndex == 2
                          ? null
                          : () {
                        onItemTapped(2);
                        ScaffoldMessenger.of(context)
                            .hideCurrentSnackBar();
                      },
                      baseSize: screenHeight * 0.028, // Dinamik boyut
                    ),
                  ),
                  // Chat
                  Expanded(
                    child: BottomNavigationButton(
                      iconPath: 'assets/main.svg',
                      label: appLocalizations.chat,
                      isSelected: tabProvider.selectedIndex == 0,
                      onTap: tabProvider.selectedIndex == 0
                          ? null
                          : () {
                        onItemTapped(0);
                        ScaffoldMessenger.of(context)
                            .hideCurrentSnackBar();
                      },
                      baseSize: screenHeight * 0.028, // Dinamik boyut
                    ),
                  ),
                  // Library
                  Expanded(
                    child: BottomNavigationButton(
                      iconPath: 'assets/models.svg',
                      label: appLocalizations.library,
                      isSelected: tabProvider.selectedIndex == 1,
                      onTap: tabProvider.selectedIndex == 1
                          ? null
                          : () {
                        onItemTapped(1);
                        ScaffoldMessenger.of(context)
                            .hideCurrentSnackBar();
                      },
                      baseSize: screenHeight * 0.022, // Dinamik boyut
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BottomNavigationButton extends StatelessWidget {
  final String iconPath;
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;
  final double baseSize;

  const BottomNavigationButton({
    Key? key,
    required this.iconPath,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.baseSize = 20.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Tema bilgisi
    final isDarkTheme = Provider.of<ThemeProvider>(context).isDarkTheme;

    // Seçili olup olmadığına göre ikon rengi ayarlama
    Color iconColor = isSelected
        ? (isDarkTheme ? Colors.white : Colors.black)
        : (isDarkTheme ? Colors.grey : Colors.grey[600]!);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque, // Tüm alanı tıklanabilir yapar
      child: Container(
        alignment: Alignment.center,
        // "Column" ile ikon ve yazıyı alt alta yerleştiriyoruz
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // İkon kısmı (AnimatedScale ile)
            SizedBox(
              width: baseSize * 1.2, // İkonu ve animasyonu rahat sığdırmak için
              height: baseSize * 1.2,
              child: Center(
                child: AnimatedScale(
                  scale: isSelected ? 1.2 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: SvgPicture.asset(
                    iconPath,
                    width: baseSize,
                    height: baseSize,
                    color: iconColor,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2.0),

            // Yazı kısmı (hem AnimatedDefaultTextStyle hem AnimatedScale)
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              style: GoogleFonts.roboto(
                fontSize: 10,
                color: iconColor,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
              ),
              child: AnimatedScale(
                scale: isSelected ? 1.1 : 1.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: Text(label),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
