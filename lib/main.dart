// main.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat/chat.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'models.dart';
import 'download.dart';
import 'inbox.dart';
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

// Global key yalnızca MainScreen için tanımlanıyor.
final GlobalKey<MainScreenState> mainScreenKey = GlobalKey<MainScreenState>();
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

Future<void> main() async {
  await dotenv.load(fileName: ".env");
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await requestNotificationPermission();
  await FlutterDownloader.initialize();
  await LocalNotificationService.instance.initNotifications();
  await _checkAndUpdateSubscription();

  // SharedPreferences'ten tema ayarını string olarak alıyoruz
  final prefs = await SharedPreferences.getInstance();
  String? savedTheme = prefs.getString('selectedTheme');
  String initialTheme;
  if (savedTheme == null) {
    // İlk defa açılıyorsa, cihazın temasını kontrol ediyoruz
    Brightness brightness = WidgetsBinding.instance.window.platformBrightness;
    initialTheme = brightness == Brightness.dark ? 'dark' : 'light';
    await prefs.setString('selectedTheme', initialTheme);
  } else {
    initialTheme = savedTheme;
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => FileDownloadHelper()),
        // ThemeProvider'ı string olarak belirlenen initialTheme ile başlatıyoruz
        ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(initialTheme),
        ),
        ChangeNotifierProvider<LocaleProvider>(
          create: (_) => LocaleProvider(),
        ),
        ChangeNotifierProvider<DownloadedModelsManager>(
          create: (_) => DownloadedModelsManager(),
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

  ThemeData _buildTheme(String currentTheme) {
    final bool isDark = currentTheme == 'dark';
    final baseTheme = isDark ? ThemeData.dark() : ThemeData.light();

    return baseTheme.copyWith(
      primaryColor: AppColors.background,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: baseTheme.colorScheme.copyWith(
        primary: AppColors.opposedPrimaryColor,
        onPrimary: AppColors.primaryColor,
        secondary: AppColors.border,
        onSecondary: AppColors.quaternaryColor,
        surface: AppColors.background,
        onSurface: AppColors.border,
        error: AppColors.warning,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.opposedPrimaryColor,
        selectionColor: AppColors.opposedQuaternaryColor,
      ),
      inputDecorationTheme: InputDecorationTheme(
        focusColor: AppColors.opposedPrimaryColor,
        hintStyle: TextStyle(color: AppColors.tertiaryColor),
        labelStyle:TextStyle(color: AppColors.tertiaryColor),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          theme: _buildTheme(themeProvider.currentTheme),
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
            final localeProvider = Provider.of<LocaleProvider>(context, listen: false);
            return localeProvider.locale;
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
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      return true;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    bool rememberMe = prefs.getBool('remember_me') ?? false;
    return rememberMe;
  }

  Future<Widget> _decideScreen() async {
    bool isConnected = await InternetConnection().hasInternetAccess;
    if (!isConnected) {
      bool hasRemember = await _checkRememberMe();
      if (hasRemember) {
        return MainScreen(key: mainScreenKey);
      } else {
        return const LoginScreen();
      }
    }

    bool hasRememberAndUser = await _checkRememberMe();
    User? user = FirebaseAuth.instance.currentUser;
    if (!hasRememberAndUser || user == null) {
      return const LoginScreen();
    }

    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (!userDoc.exists) {
        return const LoginScreen();
      }
    } catch (e) {
      print("Firestore sorgusunda hata oluştu: $e");
      return const LoginScreen();
    }

    try {
      await user.reload();
    } catch (e) {
      print("Kullanıcı bilgileri reload edilemedi: $e");
      return MainScreen(key: mainScreenKey);
    }

    if (user.emailVerified) {
      return MainScreen(key: mainScreenKey);
    } else {
      try {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (!userDoc.exists) {
          return const LoginScreen();
        }
        final data = userDoc.data()!;
        return EmailVerificationScreen(
          email: data['email'] ?? '',
          username: data['username'] ?? '',
          userId: user.uid,
          password: '',
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
        Widget child;
        if (snapshot.connectionState == ConnectionState.waiting) {
          child = Container(
            key: const ValueKey('loading'),
            width: double.infinity,
            height: double.infinity,
            color: AppColors.background,
          );
        } else {
          child = snapshot.hasData ? snapshot.data! : const LoginScreen(key: ValueKey('login'));
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

class MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  // GlobalKey'leri yalnızca MainScreen içinde kullanıyoruz.
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
      MenuScreen(key: const ValueKey('MenuScreen')),
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
    themeProvider.updateSystemUIOverlayStyle();
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
      updateBottomAppBarVisibility(true);
    });
  }

  void startNewConversation() {
    final tabProvider = Provider.of<TabProvider>(context, listen: false);
    tabProvider.setSelectedIndex(0);
    chatScreenKey.currentState?.resetConversation();
    updateBottomAppBarVisibility(false);
  }

// Updated build method in MainScreenState
  @override
  Widget build(BuildContext context) {
    final tabProvider = Provider.of<TabProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final appLocalizations = AppLocalizations.of(context)!;
    final screenHeight = MediaQuery.of(context).size.height;

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
            color: AppColors.background,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16.0),
              topRight: Radius.circular(16.0),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: BottomAppBar(
            color: Colors.transparent,
            elevation: 0,
            child: SizedBox(
              height: screenHeight * 0.09,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: BottomNavigationButton(
                      iconPath: 'assets/inbox.svg',
                      label: appLocalizations.chats,
                      isSelected: tabProvider.selectedIndex == 2,
                      onTap: tabProvider.selectedIndex == 2
                          ? null
                          : () {
                        onItemTapped(2);
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      },
                      baseSize: screenHeight * 0.028,
                    ),
                  ),
                  Expanded(
                    child: BottomNavigationButton(
                      iconPath: 'assets/main.svg',
                      label: appLocalizations.chat,
                      isSelected: tabProvider.selectedIndex == 0,
                      onTap: tabProvider.selectedIndex == 0
                          ? null
                          : () {
                        onItemTapped(0);
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      },
                      baseSize: screenHeight * 0.028,
                    ),
                  ),
                  Expanded(
                    child: BottomNavigationButton(
                      iconPath: 'assets/models.svg',
                      label: appLocalizations.library,
                      isSelected: tabProvider.selectedIndex == 1,
                      onTap: tabProvider.selectedIndex == 1
                          ? null
                          : () {
                        onItemTapped(1);
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      },
                      baseSize: screenHeight * 0.022,
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

// Updated build method in BottomNavigationButton
  @override
  Widget build(BuildContext context) {
    Color iconColor = isSelected ? AppColors.opposedPrimaryColor : AppColors.unselectedIcon;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: baseSize * 1.2,
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