import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Firebase / In-App / Diğer importlar
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'notifications.dart';
import 'theme.dart';

///------------------------------------------------------------------
/// Model: Kredi Paketi
///------------------------------------------------------------------
class CreditPackage {
  final String credits;
  final String productId;
  final String price;

  CreditPackage({
    required this.credits,
    required this.productId,
    required this.price,
  });
}

///------------------------------------------------------------------
/// Premium Ekranı (Ana Ekran)
///------------------------------------------------------------------
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  _PremiumScreenState createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen>
    with SingleTickerProviderStateMixin {
  /// Abonelik planları
  final List<String> planTypes = ['new', 'plus', 'pro', 'ultra'];

  /// Kullanıcının seçtiği seçenekler (yıllık/aylık vb.)
  Map<String, String> selectedOptions = {
    'new': 'monthly',
    'plus': 'monthly',
    'pro': 'monthly',
    'ultra': 'monthly',
  };

  /// In-App Purchase ve Firebase değişkenleri
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  CreditPackage? _selectedCreditPackage;
  /// Kredi ürün ID'leri
  static const List<String> _creditProductIds = [
    'credit_100',
    'credit_500',
    'credit_1000',
    'credit_2500',
    'credit_5000',
  ];

  /// Ürün ID'leri (örnek)
  static const String _monthlySubscriptionNew = 'new_plan_monthly';
  static const String _annualSubscriptionNew = 'new_plan_annual';
  static const String _monthlySubscriptionPlus = 'vertex_ai_monthly_sub';
  static const String _annualSubscriptionPlus = 'vertex_ai_annual_sub';
  static const String _monthlySubscriptionPro = 'cortex_pro_monthly';
  static const String _annualSubscriptionPro = 'cortex_pro_annual';
  static const String _monthlySubscriptionUltra = 'cortex_ultra_monthly';
  static const String _annualSubscriptionUltra = 'cortex_ultra_annual';

  /// Mağaza, abonelik, kullanıcı durumu
  bool _isAvailable = false;
  bool _purchasePending = false;
  bool _loading = true;
  bool _errorOccurred = false;
  String _errorMessage = '';

  /// Kullanıcının mevcut abonelik seviyesi
  int _hasCortexSubscription = 0;

  /// Sayfalar arası geçiş (PageView)
  late PageController _pageController;
  int _currentPage = 1; // 0 => new, 1 => plus, 2 => pro, 3 => ultra

  /// Test modu bayrağı
  bool _isTesting = true;

  /// Sorgulanan ürünler (abonelik planları için)
  List<ProductDetails> _subscriptions = [];

  /// Örnek (Mock) ürün listesi (Test amaçlı)
  List<ProductDetails> _mockSubscriptions = [
    ProductDetails(
      id: 'new_plan_monthly',
      title: 'New Monthly',
      description: 'Access all New features on a monthly basis.',
      price: '\$2.99',
      currencyCode: 'USD',
      rawPrice: 2.99,
    ),
    ProductDetails(
      id: 'new_plan_annual',
      title: 'New Annual',
      description: 'Access all New features on an annual basis.',
      price: '\$29.99',
      currencyCode: 'USD',
      rawPrice: 29.99,
    ),
    ProductDetails(
      id: 'vertex_ai_monthly_sub',
      title: 'Plus Monthly',
      description: 'Access all Plus features on a monthly basis.',
      price: '\$4.99',
      currencyCode: 'USD',
      rawPrice: 4.99,
    ),
    ProductDetails(
      id: 'vertex_ai_annual_sub',
      title: 'Plus Annual',
      description: 'Access all Plus features on an annual basis.',
      price: '\$49.99',
      currencyCode: 'USD',
      rawPrice: 49.99,
    ),
    ProductDetails(
      id: 'cortex_pro_monthly',
      title: 'Pro Monthly',
      description: 'Access all Pro features on a monthly basis.',
      price: '\$9.99',
      currencyCode: 'USD',
      rawPrice: 9.99,
    ),
    ProductDetails(
      id: 'cortex_pro_annual',
      title: 'Pro Annual',
      description: 'Access all Pro features on an annual basis.',
      price: '\$99.99',
      currencyCode: 'USD',
      rawPrice: 99.99,
    ),
    ProductDetails(
      id: 'cortex_ultra_monthly',
      title: 'Ultra Monthly',
      description: 'Access all Ultra features on a monthly basis.',
      price: '\$19.99',
      currencyCode: 'USD',
      rawPrice: 19.99,
    ),
    ProductDetails(
      id: 'cortex_ultra_annual',
      title: 'Ultra Annual',
      description: 'Access all Ultra features on an annual basis.',
      price: '\$199.99',
      currencyCode: 'USD',
      rawPrice: 199.99,
    ),
  ];

  ///------------------------------------------------------------------
  /// initState
  ///------------------------------------------------------------------
  @override
  void initState() {
    super.initState();

    _pageController = PageController(initialPage: _currentPage);
    _pageController.addListener(() {
      int next = _pageController.page!.round();
      if (_currentPage != next) {
        setState(() {
          _currentPage = next;
          _selectedCreditPackage = null;
        });
      }
    });

    // InAppPurchase subscription
    _subscription = _inAppPurchase.purchaseStream.listen(
      _onPurchaseUpdated,
      onError: (error) {
        setState(() {
          _errorOccurred = true;
          _errorMessage = AppLocalizations.of(context)!.purchaseStreamError;
        });
        _showCustomNotification(
          message: AppLocalizations.of(context)!.purchaseError,
          isSuccess: false,
        );
      },
    );

    // Mağaza başlat
    _initializeStore();
  }

  ///------------------------------------------------------------------
  /// dispose
  ///------------------------------------------------------------------
  @override
  void dispose() {
    _pageController.dispose();
    _subscription.cancel();
    super.dispose();
  }

  Future<void> _initializeStore() async {
    _isAvailable = await _inAppPurchase.isAvailable();

    if (!_isAvailable && !_isTesting) {
      setState(() {
        _loading = false;
        _errorOccurred = true;
        _errorMessage = AppLocalizations.of(context)!.storeUnavailable;
      });
      return;
    }

    // Sorgulanacak ürün ID'leri
    const Set<String> kIds = <String>{
      _monthlySubscriptionNew,
      _annualSubscriptionNew,
      _monthlySubscriptionPlus,
      _annualSubscriptionPlus,
      _monthlySubscriptionPro,
      _annualSubscriptionPro,
      _monthlySubscriptionUltra,
      _annualSubscriptionUltra,
    };

    if (_isAvailable) {
      final response = await _inAppPurchase.queryProductDetails(kIds);

      if (response.error != null && !_isTesting) {
        setState(() {
          _loading = false;
          _errorOccurred = true;
          _errorMessage = AppLocalizations.of(context)!.productDetailsError;
        });
        return;
      }

      if (response.productDetails.isEmpty && !_isTesting) {
        setState(() {
          _loading = false;
          _errorOccurred = true;
          _errorMessage = AppLocalizations.of(context)!.noProductsFound;
        });
        return;
      }

      setState(() {
        _subscriptions = response.productDetails;
        _loading = false;
      });
    }
    else if (_isTesting) {
      // Test modunda mock ürünleri
      setState(() {
        _subscriptions = _mockSubscriptions;
        _loading = false;
      });
    }

    // Kullanıcının abonelik seviyesini Firestore'dan al
    User? user = _auth.currentUser;
    if (user != null) {
      try {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (userDoc.exists) {
          _hasCortexSubscription = userDoc.get('hasCortexSubscription') ?? 0;
          // (Örneğin max 4 ya da 6 diyorsanız kontrol edebilirsiniz)
        }
      } catch (e) {
        _hasCortexSubscription = 0;
      }
    }
  }

  ///------------------------------------------------------------------
  /// Satın Alma Akışı
  ///------------------------------------------------------------------
  void _onPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) async {
    try {
      for (var purchaseDetails in purchaseDetailsList) {
        if (purchaseDetails.status == PurchaseStatus.pending) {
          setState(() => _purchasePending = true);
        } else {
          if (purchaseDetails.status == PurchaseStatus.error) {
            setState(() => _purchasePending = false);
            _showCustomNotification(
              message: AppLocalizations.of(context)!.purchaseFailed,
              isSuccess: false,
            );
          }
          else if (purchaseDetails.status == PurchaseStatus.purchased ||
              purchaseDetails.status == PurchaseStatus.restored) {
            await _deliverProduct(purchaseDetails);
          }

          if (purchaseDetails.pendingCompletePurchase) {
            await _inAppPurchase.completePurchase(purchaseDetails);
          }
        }
      }
    }
    catch (e) {
      _showCustomNotification(
        message: AppLocalizations.of(context)!.purchaseFailed,
        isSuccess: false,
      );
    }
  }

  void _buySubscription(String planType) {
    final selectedOption = selectedOptions[planType] ?? 'monthly';
    String subscriptionId;

    if (planType == 'pro') {
      subscriptionId = (selectedOption == 'annual')
          ? _annualSubscriptionPro
          : _monthlySubscriptionPro;
    } else if (planType == 'ultra') {
      subscriptionId = (selectedOption == 'annual')
          ? _annualSubscriptionUltra
          : _monthlySubscriptionUltra;
    } else if (planType == 'new') {
      // Yeni plan (placeholder); isterseniz satın almayı aktifleştirebilirsiniz
      subscriptionId = (selectedOption == 'annual')
          ? _annualSubscriptionNew
          : _monthlySubscriptionNew;

      // Örnek: Şimdilik “kullanıma hazır değil” diyelim
      _showCustomNotification(
        message: "Yeni plan henüz kullanıma hazır değil.",
        isSuccess: false,
      );
      return;
    }
    else {
      // 'plus'
      subscriptionId = (selectedOption == 'annual')
          ? _annualSubscriptionPlus
          : _monthlySubscriptionPlus;
    }

    // Ürün bul
    ProductDetails? subscription;
    for (var sub in _subscriptions) {
      if (sub.id == subscriptionId) {
        subscription = sub;
        break;
      }
    }

    if (subscription == null) {
      setState(() {
        _errorOccurred = true;
        _errorMessage = AppLocalizations.of(context)!.productNotFound;
      });
      _showCustomNotification(
        message: AppLocalizations.of(context)!.productNotFound,
        isSuccess: false,
      );
      return;
    }

    if (_isTesting) {
      // Test modunda mock satın alma
      _deliverProduct(
        PurchaseDetails(
          purchaseID: 'mock_purchase_id',
          productID: subscription.id,
          status: PurchaseStatus.purchased,
          transactionDate: DateTime.now().toIso8601String(),
          verificationData: PurchaseVerificationData(
            localVerificationData: 'mock_verification',
            serverVerificationData: 'mock_server_verification',
            source: 'mock_source',
          ),
        ),
      );
    }
    else {
      final purchaseParam = PurchaseParam(productDetails: subscription);
      _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
    }
  }

  Future<void> _deliverProduct(PurchaseDetails purchaseDetails) async {
    setState(() => _purchasePending = false);

    User? user = _auth.currentUser;
    if (user != null) {
      try {
        final purchasedId = purchaseDetails.productID;
        int newSubscription = 0;

        if (purchasedId == _monthlySubscriptionPlus ||
            purchasedId == _annualSubscriptionPlus) {
          newSubscription = 1;
        } else if (purchasedId == _monthlySubscriptionPro ||
            purchasedId == _annualSubscriptionPro) {
          newSubscription = 2;
        } else if (purchasedId == _monthlySubscriptionUltra ||
            purchasedId == _annualSubscriptionUltra) {
          newSubscription = 3;
        } else if (purchasedId == _monthlySubscriptionNew ||
            purchasedId == _annualSubscriptionNew) {
          newSubscription = 4;
        }

        if (newSubscription == 0) {
          setState(() {
            _errorOccurred = true;
            _errorMessage = AppLocalizations.of(context)!.invalidPurchase;
          });
          _showCustomNotification(
            message: AppLocalizations.of(context)!.invalidPurchase,
            isSuccess: false,
          );
          return;
        }

        // Firestore güncelle
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'hasCortexSubscription': newSubscription});

        setState(() {
          _hasCortexSubscription = newSubscription;
        });

        _showCustomNotification(
          message: AppLocalizations.of(context)!.purchaseSuccessful,
          isSuccess: true,
        );
      }
      catch (e) {
        setState(() {
          _errorOccurred = true;
          _errorMessage = AppLocalizations.of(context)!.updateFailed;
        });
        _showCustomNotification(
          message: AppLocalizations.of(context)!.updateFailed,
          isSuccess: false,
        );
      }
    }
  }

  ///------------------------------------------------------------------
  /// build
  ///------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final isDarkTheme = Provider.of<ThemeProvider>(context).isDarkTheme;

    return Scaffold(
      backgroundColor: isDarkTheme ? const Color(0xFF090909) : Colors.white,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: _errorOccurred
            ? _buildErrorScreen(context, localizations, isDarkTheme)
            : (_purchasePending || _loading)
            ? Container(
          key: const ValueKey('skeleton'),
          child: _buildSkeletonLoader(),
        )
            : Container(
          key: const ValueKey('content'),
          child: _buildPremiumContent(context, localizations, isDarkTheme),
        ),
      ),
    );
  }

  ///------------------------------------------------------------------
  /// _buildErrorScreen
  ///------------------------------------------------------------------
  Widget _buildErrorScreen(
      BuildContext context,
      AppLocalizations localizations,
      bool isDarkTheme
      ) {
    final screenWidth = MediaQuery.of(context).size.width;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(screenWidth * 0.04),
        child: Column(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: IconButton(
                icon: Icon(
                  Icons.close,
                  color: isDarkTheme ? Colors.white : Colors.black,
                  size: screenWidth * 0.07,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: screenWidth * 0.2,
                    ),
                    SizedBox(height: screenWidth * 0.05),
                    Text(
                      _errorMessage,
                      style: TextStyle(
                        fontSize: screenWidth * 0.045,
                        color: isDarkTheme ? Colors.white : Colors.black,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: screenWidth * 0.075),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _loading = true;
                          _errorOccurred = false;
                          _errorMessage = '';
                        });
                        _initializeStore();
                      },
                      style: ElevatedButton.styleFrom(
                        foregroundColor:
                        isDarkTheme ? Colors.black : Colors.white,
                        backgroundColor:
                        isDarkTheme ? Colors.white : Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                          BorderRadius.circular(screenWidth * 0.075),
                        ),
                        padding: EdgeInsets.symmetric(
                          vertical: screenWidth * 0.04,
                          horizontal: screenWidth * 0.125,
                        ),
                      ),
                      child: Text(
                        localizations.retry,
                        style: TextStyle(
                          fontSize: screenWidth * 0.04,
                          fontWeight: FontWeight.bold,
                          color: isDarkTheme ? Colors.black : Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  ///------------------------------------------------------------------
  /// _buildSkeletonLoader (Shimmer)
  ///------------------------------------------------------------------
  Widget _buildSkeletonLoader() {
    final isDarkTheme = Provider.of<ThemeProvider>(context).isDarkTheme;
    final screenWidth = MediaQuery.of(context).size.width;

    return Shimmer.fromColors(
      baseColor: isDarkTheme ? Colors.grey[700]! : Colors.grey[300]!,
      highlightColor: isDarkTheme ? Colors.grey[500]! : Colors.grey[100]!,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: screenWidth * 0.04,
            vertical: screenWidth * 0.03,
          ),
          child: Column(
            children: [
              SizedBox(height: screenWidth * 0.035),
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: screenWidth * 0.07,
                  height: screenWidth * 0.07,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              SizedBox(height: screenWidth * 0.025),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: PageView(
                        children: [
                          _buildSkeletonPage(isDarkTheme),
                          _buildSkeletonPage(isDarkTheme),
                          _buildSkeletonPage(isDarkTheme),
                          _buildSkeletonPage(isDarkTheme),
                        ],
                      ),
                    ),
                    SizedBox(height: screenWidth * 0.03),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(planTypes.length, (_) {
                        return Container(
                          margin: EdgeInsets.symmetric(
                              horizontal: screenWidth * 0.01
                          ),
                          width: 12.0,
                          height: 12.0,
                          decoration: const BoxDecoration(
                            color: Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        );
                      }),
                    ),
                    SizedBox(height: screenWidth * 0.06),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ///------------------------------------------------------------------
  /// _buildSkeletonPage
  ///------------------------------------------------------------------
  Widget _buildSkeletonPage(bool isDarkTheme) {
    final screenWidth = MediaQuery.of(context).size.width;

    return SingleChildScrollView(
      child: Column(
        children: [
          SizedBox(height: screenWidth * 0.025),
          Container(
            width: screenWidth * 0.55,
            height: screenWidth * 0.12,
            decoration: BoxDecoration(
              color: Colors.grey,
              borderRadius: BorderRadius.circular(screenWidth * 0.02),
            ),
          ),
          SizedBox(height: screenWidth * 0.025),
          Container(
            width: screenWidth * 0.85,
            height: screenWidth * 0.04,
            decoration: BoxDecoration(
              color: Colors.grey,
              borderRadius: BorderRadius.circular(screenWidth * 0.015),
            ),
          ),
          SizedBox(height: screenWidth * 0.01),
          Container(
            width: screenWidth * 0.7,
            height: screenWidth * 0.04,
            decoration: BoxDecoration(
              color: Colors.grey,
              borderRadius: BorderRadius.circular(screenWidth * 0.015),
            ),
          ),
          SizedBox(height: screenWidth * 0.05),
          Container(
            width: screenWidth * 0.25,
            height: screenWidth * 0.25,
            decoration: BoxDecoration(
              color: Colors.grey,
              borderRadius: BorderRadius.circular(screenWidth * 0.04),
            ),
          ),
          SizedBox(height: screenWidth * 0.05),
          Container(
            margin: EdgeInsets.symmetric(horizontal: screenWidth * 0.005),
            height: screenWidth * 0.15,
            decoration: BoxDecoration(
              color: Colors.grey,
              borderRadius: BorderRadius.circular(screenWidth * 0.035),
            ),
          ),
          SizedBox(height: screenWidth * 0.03),
          Container(
            margin: EdgeInsets.symmetric(horizontal: screenWidth * 0.005),
            height: screenWidth * 0.15,
            decoration: BoxDecoration(
              color: Colors.grey,
              borderRadius: BorderRadius.circular(screenWidth * 0.035),
            ),
          ),
          SizedBox(height: screenWidth * 0.06),
        ],
      ),
    );
  }

  ///------------------------------------------------------------------
  /// _buildPremiumContent
  ///------------------------------------------------------------------
  Widget _buildPremiumContent(
      BuildContext context,
      AppLocalizations localizations,
      bool isDarkTheme,
      ) {
    final screenWidth = MediaQuery.of(context).size.width;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: screenWidth * 0.04,
          vertical: screenWidth * 0.03,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Align(
              alignment: Alignment.center,
              child: IconButton(
                icon: Icon(
                  Icons.close,
                  color: isDarkTheme ? Colors.white : Colors.black,
                  size: screenWidth * 0.07,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            SizedBox(height: screenWidth * 0.01),
            Expanded(
              child: _hasCortexSubscription > 0
                  ? _buildSubscribedContent(context, localizations, isDarkTheme)
                  : Column(
                children: [
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      children: [
                        // Kredi Paketi Sayfası
                        CreditContentWidget(
                          onCreditPackageSelected: (CreditPackage package) {
                            setState(() {
                              _selectedCreditPackage = package;
                              _currentPage = -1; // Özel bir değer ile kredi sayfasında olduğunu belirtin
                            });
                          },
                        ),

                        // Abonelik Planları
                        _buildPremiumPage(
                          context: context,
                          localizations: localizations,
                          isDarkTheme: isDarkTheme,
                          planType: 'plus',
                        ),
                        _buildPremiumPage(
                          context: context,
                          localizations: localizations,
                          isDarkTheme: isDarkTheme,
                          planType: 'pro',
                        ),
                        _buildPremiumPage(
                          context: context,
                          localizations: localizations,
                          isDarkTheme: isDarkTheme,
                          planType: 'ultra',
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: screenWidth * 0.035),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(planTypes.length, (index) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: EdgeInsets.symmetric(
                            horizontal: screenWidth * 0.01),
                        width: _currentPage == index
                            ? screenWidth * 0.03
                            : screenWidth * 0.02,
                        height: screenWidth * 0.03,
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? (isDarkTheme ? Colors.white : Colors.black)
                              : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      );
                    }),
                  ),
                  SizedBox(height: screenWidth * 0.02),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.help_outline,
                        size: screenWidth * 0.04,
                        color: Colors.grey,
                      ),
                      SizedBox(width: screenWidth * 0.01),
                      Text(
                        localizations.comingSoon,
                        style: TextStyle(
                          fontSize: screenWidth * 0.03,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: screenWidth * 0.02),
                  ElevatedButton(
                    onPressed: (_subscriptions.isNotEmpty || _selectedCreditPackage != null)
                        ? () {
                      if (_selectedCreditPackage != null) {
                        _buyCreditPackage(_selectedCreditPackage!.productId);
                      } else {
                        String currentPlanType = planTypes[_currentPage];
                        _buySubscription(currentPlanType);
                      }
                    }
                        : null,
                    style: ElevatedButton.styleFrom(
                      foregroundColor: isDarkTheme ? Colors.black : Colors.white,
                      backgroundColor: isDarkTheme ? Colors.white : Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(screenWidth * 0.075),
                      ),
                      padding: EdgeInsets.symmetric(
                        vertical: screenWidth * 0.05,
                        horizontal: screenWidth * 0.125,
                      ),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          child: child,
                          opacity: animation,
                        );
                      },
                      child: _selectedCreditPackage != null
                          ? Text(
                        '${_selectedCreditPackage!.credits} Al',
                        key: ValueKey<String>('credit-${_selectedCreditPackage!.productId}'),
                        style: TextStyle(
                          fontSize: screenWidth * 0.04,
                          fontWeight: FontWeight.bold,
                          color: isDarkTheme ? Colors.black : Colors.white,
                        ),
                      )
                          : Text(
                        selectedOptions[planTypes[_currentPage]] == 'annual'
                            ? localizations.startFreeTrial30Days
                            : localizations.startFreeTrial7Days,
                        key: ValueKey<String>(
                          '${selectedOptions[planTypes[_currentPage]]}-${planTypes[_currentPage]}',
                        ),
                        style: TextStyle(
                          fontSize: screenWidth * 0.04,
                          fontWeight: FontWeight.bold,
                          color: isDarkTheme ? Colors.black : Colors.white,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: screenWidth * 0.025),
                  TextButton(
                    onPressed: () => _showTermsAndConditions(context),
                    style: TextButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                            screenWidth * 0.03),
                      ),
                    ),
                    child: Text(
                      localizations.termsOfServiceAndPrivacyPolicyWarning,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: screenWidth * 0.025,
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

  ///------------------------------------------------------------------
  /// Kredi satın almayı başlatan fonksiyon (Satır 4)
  ///------------------------------------------------------------------
  void _buyCreditPackage(String productId) {
    // Abonelik ürünleri gibi, bu da _subscriptions listesinde olmalı.
    // Aksi hâlde orElse ile bir Exception atabilirsiniz.
    final product = _subscriptions.firstWhere(
          (p) => p.id == productId,
      orElse: () => throw Exception('Kredi ürünü bulunamadı.'),
    );

    if (_isTesting) {
      // Test modunda mock satın alma
      _deliverProduct(
        PurchaseDetails(
          purchaseID: 'mock_purchase_id',
          productID: product.id,
          status: PurchaseStatus.purchased,
          transactionDate: DateTime.now().toIso8601String(),
          verificationData: PurchaseVerificationData(
            localVerificationData: 'mock_verification',
            serverVerificationData: 'mock_server_verification',
            source: 'mock_source',
          ),
        ),
      );
    } else {
      final purchaseParam = PurchaseParam(productDetails: product);
      _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
    }
  }

  ///------------------------------------------------------------------
  /// _buildPremiumPage (plus/pro/ultra)
  ///------------------------------------------------------------------
  Widget _buildPremiumPage({
    required BuildContext context,
    required AppLocalizations localizations,
    required bool isDarkTheme,
    required String planType,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;

    String purchaseKey;
    String descriptionKey;
    bool isBestValue;
    String logoPath;

    if (planType == 'pro') {
      purchaseKey = localizations.purchasePro;
      descriptionKey = localizations.proDescription;
      isBestValue = _hasCortexSubscription < 2;
      logoPath = isDarkTheme ? 'assets/whitepro.png' : 'assets/prologo.png';
    } else if (planType == 'ultra') {
      purchaseKey = localizations.purchaseUltra;
      descriptionKey = localizations.ultraDescription;
      isBestValue = _hasCortexSubscription < 3;
      logoPath = isDarkTheme ? 'assets/whiteultra.png' : 'assets/ultralogo.png';
    } else {
      // plus
      purchaseKey = localizations.purchasePlus;
      descriptionKey = localizations.plusDescription;
      isBestValue = _hasCortexSubscription < 1;
      logoPath = isDarkTheme ? 'assets/whiteplus.png' : 'assets/pluslogo.png';
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          Text(
            purchaseKey,
            style: TextStyle(
              fontSize: screenWidth * 0.07,
              fontWeight: FontWeight.bold,
              color: isDarkTheme ? Colors.white : Colors.black,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: screenWidth * 0.025),
          Text(
            descriptionKey,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: screenWidth * 0.035,
              color: isDarkTheme ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          SizedBox(height: screenWidth * 0.05),
          Image.asset(
            logoPath,
            height: screenWidth * 0.25,
          ),
          SizedBox(height: screenWidth * 0.05),

          /// Yıllık abonelik seçeneği
          _buildSubscriptionOption(
            context: context,
            localizations: localizations,
            title: planType == 'pro'
                ? localizations.annualPro
                : planType == 'ultra'
                ? localizations.annualUltra
                : localizations.annualPlus,
            description: planType == 'pro'
                ? '${localizations.annualProDescription} ${_getPriceForId(_annualSubscriptionPro)}'
                : planType == 'ultra'
                ? '${localizations.annualUltraDescription} ${_getPriceForId(_annualSubscriptionUltra)}'
                : '${localizations.annualPlusDescription} ${_getPriceForId(_annualSubscriptionPlus)}',
            isBestValue: isBestValue,
            isDarkTheme: isDarkTheme,
            isSelected: selectedOptions[planType] == 'annual',
            onSelect: () => setState(() {
              selectedOptions[planType] = 'annual';
            }),
          ),
          SizedBox(height: screenWidth * 0.03),

          /// Aylık abonelik seçeneği
          _buildSubscriptionOption(
            context: context,
            localizations: localizations,
            title: planType == 'pro'
                ? localizations.monthlyPro
                : planType == 'ultra'
                ? localizations.monthlyUltra
                : localizations.monthlyPlus,
            description: planType == 'pro'
                ? '${localizations.monthlyProDescription} ${_getPriceForId(_monthlySubscriptionPro)}'
                : planType == 'ultra'
                ? '${localizations.monthlyUltraDescription} ${_getPriceForId(_monthlySubscriptionUltra)}'
                : '${localizations.monthlyPlusDescription} ${_getPriceForId(_monthlySubscriptionPlus)}',
            isBestValue: false,
            isDarkTheme: isDarkTheme,
            isSelected: selectedOptions[planType] == 'monthly',
            onSelect: () => setState(() {
              selectedOptions[planType] = 'monthly';
            }),
          ),
          SizedBox(height: screenWidth * 0.06),

          // Avantaj listesi
          _buildBenefitsList(localizations, isDarkTheme, planType),
        ],
      ),
    );
  }

  Widget _buildSubscriptionOption({
    required BuildContext context,
    required AppLocalizations localizations,
    required String title,
    required String description,
    bool isBestValue = false,
    required bool isDarkTheme,
    required bool isSelected,
    required VoidCallback onSelect,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;

    final cardWidth = min(screenWidth * 0.9, 350.0);

    // Metin boyutlarını ekran genişliğine göre dinamik olarak ayarlayın
    final titleFontSize = screenWidth > 600 ? 20.0 : 18.0;
    final descriptionFontSize = screenWidth > 600 ? 16.0 : 14.0;

    return Center(
      child: GestureDetector(
        onTap: onSelect,
        child: AnimatedContainer(
          width: cardWidth,
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: isDarkTheme ? const Color(0xFF1B1B1B) : Colors.grey[200],
            borderRadius: BorderRadius.circular(14),
            border: isSelected
                ? Border.all(
              color: isDarkTheme ? Colors.white : Colors.black,
              width: 2,
            )
                : Border.all(color: Colors.transparent, width: 2),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: titleFontSize,
                        fontWeight: FontWeight.bold,
                        color: isDarkTheme ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                  if (isBestValue)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
                      child: Text(
                        localizations.bestValue,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                description,
                style: TextStyle(
                  fontSize: descriptionFontSize,
                  color: isDarkTheme ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ///------------------------------------------------------------------
  /// _buildBenefitsList
  ///------------------------------------------------------------------
  Widget _buildBenefitsList(
      AppLocalizations localizations,
      bool isDarkTheme,
      String planType
      ) {
    List<String> benefits = [];
    if (planType == 'plus') {
      benefits = [
        localizations.benefit1,
        localizations.benefit2,
        localizations.benefit3,
        localizations.benefit4,
        localizations.benefit7,
        localizations.benefit9,
      ];
    } else if (planType == 'pro') {
      benefits = [
        localizations.oldBenefits,
        localizations.benefit10,
        localizations.benefit5,
        localizations.benefit6,
      ];
    } else if (planType == 'ultra') {
      benefits = [
        localizations.oldBenefits,
        localizations.benefit8,
      ];
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final questionMarkBenefits = [
      localizations.benefit5,
      localizations.benefit7,
      localizations.benefit8,
      localizations.benefit9,
      localizations.benefit10,
    ];

    return Wrap(
      spacing: screenWidth * 0.012,
      runSpacing: screenWidth * 0.012,
      children: benefits.map((benefit) {
        IconData iconData = questionMarkBenefits.contains(benefit)
            ? Icons.help_outline
            : Icons.check;
        Color iconColor =
        questionMarkBenefits.contains(benefit) ? Colors.yellow : Colors.green;

        return SizedBox(
          width: (screenWidth - 2 * screenWidth * 0.04 - screenWidth * 0.024) / 2,
          child: Row(
            children: [
              Icon(
                iconData,
                color: iconColor,
                size: screenWidth * 0.05,
              ),
              SizedBox(width: screenWidth * 0.015),
              Expanded(
                child: Text(
                  benefit,
                  style: TextStyle(
                    fontSize: screenWidth * 0.035,
                    color: isDarkTheme ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  ///------------------------------------------------------------------
  /// _buildSubscribedContent
  ///------------------------------------------------------------------
  Widget _buildSubscribedContent(
      BuildContext context,
      AppLocalizations localizations,
      bool isDarkTheme
      ) {
    final screenWidth = MediaQuery.of(context).size.width;

    String subscriptionMessage;
    String subscriptionDetailMessage;

    // Burada _hasCortexSubscription == 4 (yeni plan) vb. eklenebilir
    if (_hasCortexSubscription == 3) {
      subscriptionMessage = localizations.alreadySubscribed;
      subscriptionDetailMessage = localizations.alreadySubscribed;
    } else if (_hasCortexSubscription == 2) {
      subscriptionMessage = localizations.alreadySubscribed;
      subscriptionDetailMessage = localizations.alreadySubscribed;
    } else if (_hasCortexSubscription == 1) {
      subscriptionMessage = localizations.alreadySubscribedPlus;
      subscriptionDetailMessage = localizations.alreadySubscribed;
    } else {
      subscriptionMessage = localizations.noSubscription;
      subscriptionDetailMessage = localizations.noSubscriptionMessage;
    }

    IconData iconData;
    Color iconColor;
    if (_hasCortexSubscription > 0) {
      iconData = Icons.check_circle_outline;
      iconColor = Colors.green;
    } else {
      iconData = Icons.info_outline;
      iconColor = Colors.orange;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            subscriptionMessage,
            style: TextStyle(
              fontSize: screenWidth * 0.06,
              fontWeight: FontWeight.bold,
              color: isDarkTheme ? Colors.white : Colors.black,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: screenWidth * 0.05),
          Icon(
            iconData,
            color: iconColor,
            size: screenWidth * 0.25,
          ),
          SizedBox(height: screenWidth * 0.05),
          Container(
            constraints: BoxConstraints(
              maxWidth: screenWidth * 0.9,
            ),
            child: Text(
              subscriptionDetailMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: screenWidth * 0.04,
                color: isDarkTheme ? Colors.white : Colors.black,
              ),
            ),
          ),
          SizedBox(height: screenWidth * 0.075),
          ElevatedButton(
            onPressed: _hasCortexSubscription < 4
                ? () {
              String currentPlanType;
              if (_hasCortexSubscription == 1) {
                currentPlanType = 'plus';
              } else if (_hasCortexSubscription == 2) {
                currentPlanType = 'pro';
              } else if (_hasCortexSubscription == 3) {
                currentPlanType = 'ultra';
              } else {
                currentPlanType = 'new';
              }
              _upgradeSubscription(currentPlanType);
            }
                : null,
            style: ElevatedButton.styleFrom(
              foregroundColor: isDarkTheme ? Colors.black : Colors.white,
              backgroundColor: isDarkTheme ? Colors.white : Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(screenWidth * 0.075),
              ),
              padding: EdgeInsets.symmetric(
                vertical: screenWidth * 0.04,
                horizontal: screenWidth * 0.125,
              ),
            ),
            child: Text(
              localizations.upgradeSubscription,
              style: TextStyle(
                fontSize: screenWidth * 0.04,
                fontWeight: FontWeight.bold,
                color: isDarkTheme ? Colors.black : Colors.white,
              ),
            ),
          ),
          SizedBox(height: screenWidth * 0.035),
          TextButton(
            onPressed: _cancelSubscription,
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(screenWidth * 0.03),
              ),
            ),
            child: Text(
              localizations.cancelSubscription,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.red,
                fontSize: screenWidth * 0.035,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  ///------------------------------------------------------------------
  /// _cancelSubscription
  ///------------------------------------------------------------------
  void _cancelSubscription() async {
    Uri url;
    final platform = Theme.of(context).platform;

    if (platform == TargetPlatform.android) {
      url = Uri.parse(
          'https://play.google.com/store/account/subscriptions?package=com.vertex.cortex'
      );
    } else if (platform == TargetPlatform.iOS) {
      url = Uri.parse('https://apps.apple.com/account/subscriptions');
    } else {
      setState(() {
        _errorOccurred = true;
        _errorMessage = AppLocalizations.of(context)!.unsupportedPlatform;
      });
      _showCustomNotification(
        message: AppLocalizations.of(context)!.unsupportedPlatform,
        isSuccess: false,
      );
      return;
    }

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      setState(() {
        _errorOccurred = true;
        _errorMessage = AppLocalizations.of(context)!.unableToOpenSubscription;
      });
      _showCustomNotification(
        message: AppLocalizations.of(context)!.unableToOpenSubscription,
        isSuccess: false,
      );
    }
  }

  ///------------------------------------------------------------------
  /// _upgradeSubscription
  ///------------------------------------------------------------------
  void _upgradeSubscription(String currentPlanType) async {
    String newPlanType;
    if (currentPlanType == 'plus') {
      newPlanType = 'pro';
    } else if (currentPlanType == 'pro') {
      newPlanType = 'ultra';
    } else if (currentPlanType == 'ultra') {
      newPlanType = 'new';
    } else {
      setState(() {
        _errorOccurred = true;
        _errorMessage = AppLocalizations.of(context)!.alreadyAtHighestPlan;
      });
      _showCustomNotification(
        message: AppLocalizations.of(context)!.alreadyAtHighestPlan,
        isSuccess: false,
      );
      return;
    }

    bool? confirmUpgrade = await showDialog<bool>(
      context: context,
      builder: (context) {
        final localizations = AppLocalizations.of(context)!;
        final isDarkTheme =
            Provider.of<ThemeProvider>(context, listen: false).isDarkTheme;
        final screenWidth = MediaQuery.of(context).size.width;

        return AlertDialog(
          backgroundColor: isDarkTheme ? const Color(0xFF1B1B1B) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(screenWidth * 0.04),
          ),
          title: Text(
            localizations.upgradeSubscription,
            style: TextStyle(
              color: isDarkTheme ? Colors.white : Colors.black,
              fontSize: screenWidth * 0.05,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            localizations.confirmUpgrade,
            style: TextStyle(
              color: isDarkTheme ? Colors.white : Colors.black,
              fontSize: screenWidth * 0.04,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                localizations.cancel,
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: screenWidth * 0.04,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDarkTheme ? Colors.white : Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(screenWidth * 0.03),
                ),
                padding: EdgeInsets.symmetric(
                  vertical: screenWidth * 0.03,
                  horizontal: screenWidth * 0.06,
                ),
              ),
              child: Text(
                localizations.confirm,
                style: TextStyle(
                  color: isDarkTheme ? Colors.black : Colors.white,
                  fontSize: screenWidth * 0.04,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmUpgrade != true) {
      return;
    }

    _buySubscription(newPlanType);
  }

  ///------------------------------------------------------------------
  /// _showTermsAndConditions
  ///------------------------------------------------------------------
  void _showTermsAndConditions(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final isDarkTheme = Provider.of<ThemeProvider>(context, listen: false).isDarkTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final backgroundColor = isDarkTheme ? const Color(0xFF090909) : Colors.white;
    final textColor = isDarkTheme ? Colors.white : Colors.black;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(screenWidth * 0.05)),
      ),
      builder: (BuildContext context) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: Padding(
            padding: EdgeInsets.all(screenWidth * 0.04),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      localizations.termsOfServiceAndPrivacyPolicyTitle,
                      style: TextStyle(
                        fontSize: screenWidth * 0.05,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: textColor.withOpacity(0.6),
                        size: screenWidth * 0.06,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                SizedBox(height: screenWidth * 0.02),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      localizations.termsOfServiceAndPrivacyPolicyContent,
                      style: TextStyle(
                        fontSize: screenWidth * 0.035,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  ///------------------------------------------------------------------
  /// _showCustomNotification
  ///------------------------------------------------------------------
  void _showCustomNotification({
    required String message,
    required bool isSuccess,
  }) {
    final notificationService =
    Provider.of<NotificationService>(context, listen: false);
    notificationService.showNotification(
        message: message,
        isSuccess: isSuccess
    );
  }

  ///------------------------------------------------------------------
  /// _getPriceForId (Ürün fiyatlarını almak için)
  ///------------------------------------------------------------------
  String _getPriceForId(String id) {
    try {
      final product = _subscriptions.firstWhere((p) => p.id == id);
      return product.price;
    } catch (e) {
      return 'No Informations';
    }
  }
}

class CreditContentWidget extends StatefulWidget {
  final ValueChanged<CreditPackage>? onCreditPackageSelected;

  const CreditContentWidget({
    Key? key,
    this.onCreditPackageSelected,
  }) : super(key: key);

  @override
  State<CreditContentWidget> createState() => _CreditContentWidgetState();
}

class _CreditContentWidgetState extends State<CreditContentWidget> {
  /// Seçili kart indeksi
  int? _selectedCardIndex;

  /// Kredi paketleri
  List<CreditPackage> _creditPackages = [];

  /// Kendi In-App Purchase akışımız
  final InAppPurchase _localInAppPurchase = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _localSubscription;

  /// Firestore / Auth
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Ürün ID'leri (kredi paketleri)
  static const String _productId100 = 'credit_100';
  static const String _productId500 = 'credit_500';
  static const String _productId1000 = 'credit_1000';
  static const String _productId2500 = 'credit_2500';
  static const String _productId5000 = 'credit_5000';

  /// Sorgulanan ürünler
  List<ProductDetails> _availableProducts = [];
  bool _isAvailable = false;
  bool _purchasePending = false;
  bool _loading = true;
  bool _errorOccurred = false;
  String _errorMessage = '';

  bool _isTesting = true;

  /// Kullanıcının mevcut kredisi
  int _currentCredits = 0;

  @override
  void initState() {
    super.initState();
    _initializeCreditPackages();

    // Kendi purchase stream dinleyicimiz
    _localSubscription = _localInAppPurchase.purchaseStream.listen(
      _onPurchaseUpdated,
      onError: (error) {
        setState(() {
          _errorOccurred = true;
          _errorMessage = 'Purchase Stream Error!';
        });
        _showCustomNotification(
          message: 'Satın alma hatası oluştu!',
          isSuccess: false,
        );
      },
    );

    _initializeStore();
  }

  @override
  void dispose() {
    _localSubscription.cancel();
    super.dispose();
  }

  void _initializeCreditPackages() {
    _creditPackages = [
      CreditPackage(
        credits: '100 Kredi',
        productId: _productId100,
        price: '\$0.99',
      ),
      CreditPackage(
        credits: '500 Kredi',
        productId: _productId500,
        price: '\$4.99',
      ),
      CreditPackage(
        credits: '1000 Kredi',
        productId: _productId1000,
        price: '\$9.99',
      ),
      CreditPackage(
        credits: '2500 Kredi',
        productId: _productId2500,
        price: '\$24.99',
      ),
    ];
  }

  ///------------------------------------------------------------------
  /// Mağaza hazırlığı (kredi paketleri)
  ///------------------------------------------------------------------
  Future<void> _initializeStore() async {
    _isAvailable = await _localInAppPurchase.isAvailable();
    if (!_isAvailable && !_isTesting) {
      setState(() {
        _loading = false;
        _errorOccurred = true;
        _errorMessage = 'Mağaza kullanılabilir değil.';
      });
      return;
    }

    const Set<String> _kIds = {
      _productId100,
      _productId500,
      _productId1000,
      _productId2500,
      _productId5000,
    };

    if (_isAvailable) {
      final response = await _localInAppPurchase.queryProductDetails(_kIds);

      if (response.error != null && !_isTesting) {
        setState(() {
          _loading = false;
          _errorOccurred = true;
          _errorMessage = 'Ürün detayları alınırken hata oluştu.';
        });
        return;
      }

      if (response.productDetails.isEmpty && !_isTesting) {
        setState(() {
          _loading = false;
          _errorOccurred = true;
          _errorMessage = 'Ürün bulunamadı.';
        });
        return;
      }

      setState(() {
        _availableProducts = response.productDetails;
        _loading = false;
      });
    }
    else if (_isTesting) {
      // Test modunda mock ürünleri kullan
      setState(() {
        _availableProducts = _creditPackages.map((cp) => ProductDetails(
          id: cp.productId,
          title: cp.credits,
          description: 'Test kredileri',
          price: cp.price,
          currencyCode: 'USD',
          rawPrice: double.parse(cp.price.replaceAll('\$', '')),
        )).toList();
        _loading = false;
      });
    }

    // Kullanıcının mevcut kredisini Firestore'dan al
    User? user = _auth.currentUser;
    if (user != null) {
      try {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (userDoc.exists) {
          _currentCredits = userDoc.get('currentCredits') ?? 0;
        }
      }
      catch (e) {
        _currentCredits = 0;
      }
    }
  }

  ///------------------------------------------------------------------
  /// Satın Alma Akışı
  ///------------------------------------------------------------------
  void _onPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) async {
    try {
      for (final purchaseDetails in purchaseDetailsList) {
        if (purchaseDetails.status == PurchaseStatus.pending) {
          setState(() => _purchasePending = true);
        } else {
          if (purchaseDetails.status == PurchaseStatus.error) {
            setState(() => _purchasePending = false);
            _showCustomNotification(
              message: 'Satın alma başarısız.',
              isSuccess: false,
            );
          } else if (purchaseDetails.status == PurchaseStatus.purchased ||
              purchaseDetails.status == PurchaseStatus.restored) {
            // Satın alma başarılıysa burada teslimat (deliver) işlemini yapın
            await _deliverCreditPurchase(purchaseDetails);
          }

          if (purchaseDetails.pendingCompletePurchase) {
            await _localInAppPurchase.completePurchase(purchaseDetails);
          }
        }
      }
    } catch (e) {
      _showCustomNotification(
        message: 'Satın alma hatası oluştu',
        isSuccess: false,
      );
    }
  }

  ///------------------------------------------------------------------
  /// Kredi satın almayı başlatan fonksiyon
  ///------------------------------------------------------------------
  void _buyCreditPackage(String productId) {
    // Abonelik ürünleri gibi, bu da _availableProducts listesinde olmalı.
    // Aksi hâlde orElse ile bir Exception atabilirsiniz.
    final product = _availableProducts.firstWhere(
          (p) => p.id == productId,
      orElse: () => throw Exception('Kredi ürünü bulunamadı.'),
    );

    if (_isTesting) {
      // Test modunda mock satın alma
      _deliverCreditPurchase(
        PurchaseDetails(
          purchaseID: 'mock_purchase_id',
          productID: product.id,
          status: PurchaseStatus.purchased,
          transactionDate: DateTime.now().toIso8601String(),
          verificationData: PurchaseVerificationData(
            localVerificationData: 'mock_verification',
            serverVerificationData: 'mock_server_verification',
            source: 'mock_source',
          ),
        ),
      );
    } else {
      final purchaseParam = PurchaseParam(productDetails: product);
      _localInAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
    }
  }

  ///------------------------------------------------------------------
  /// Kredi satın alındıktan sonra krediyi Firestore'a ekleyen fonksiyon
  ///------------------------------------------------------------------
  Future<void> _deliverCreditPurchase(PurchaseDetails purchaseDetails) async {
    setState(() => _purchasePending = false);

    User? user = _auth.currentUser;
    if (user != null) {
      try {
        final purchasedId = purchaseDetails.productID;
        int addedCredits = 0;

        switch (purchasedId) {
          case _productId100:
            addedCredits = 100;
            break;
          case _productId500:
            addedCredits = 500;
            break;
          case _productId1000:
            addedCredits = 1000;
            break;
          case _productId2500:
            addedCredits = 2500;
            break;
          case _productId5000:
            addedCredits = 5000;
            break;
          default:
            throw Exception('Geçersiz ürün.');
        }

        // Firestore güncelle
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'currentCredits': FieldValue.increment(addedCredits)});

        setState(() {
          _currentCredits += addedCredits;
        });

        _showCustomNotification(
          message: 'Krediler başarıyla eklendi!',
          isSuccess: true,
        );
      }
      catch (e) {
        setState(() {
          _errorOccurred = true;
          _errorMessage = 'Kredi ekleme başarısız oldu.';
        });
        _showCustomNotification(
          message: 'Kredi ekleme başarısız oldu.',
          isSuccess: false,
        );
      }
    }
  }


  ///------------------------------------------------------------------
  /// build
  ///------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Provider.of<ThemeProvider>(context).isDarkTheme;

    if (_errorOccurred) {
      return Center(
        child: Text(
          _errorMessage,
          style: TextStyle(color: isDarkTheme ? Colors.white : Colors.black),
        ),
      );
    }

    if (_purchasePending || _loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return _buildCreditContent(context, isDarkTheme);
  }

  Widget _buildCreditContent(BuildContext context, bool isDarkTheme) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Kredi Satın Al',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: isDarkTheme ? Colors.white : Colors.black,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 8),
        // Açıklama
        Text(
          'İhtiyacınıza uygun kredi paketini seçin ve uygulamamızı daha fazla kullanın.',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 16),
        Expanded(
          child: ListView.builder(
            itemCount: _creditPackages.length,
            itemBuilder: (context, index) {
              final package = _creditPackages[index];
              final isSelected = _selectedCardIndex == index;

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedCardIndex = index;
                  });
                  widget.onCreditPackageSelected?.call(package);
                },
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 300),
                  margin: EdgeInsets.symmetric(vertical: 8, horizontal: screenWidth * 0.04),
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDarkTheme ? Colors.grey[800] : Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected
                        ? Border.all(
                      color: isDarkTheme ? Colors.white : Colors.black,
                      width: 2,
                    )
                        : Border.all(
                      color: Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      // credit.svg İkonu
                      SvgPicture.asset(
                        'assets/credit.svg',
                        width: 36,
                        height: 36,
                        color: isDarkTheme ? Colors.white : Colors.black,
                      ),
                      SizedBox(width: 12),
                      // Kredi Bilgisi
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              package.credits,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDarkTheme ? Colors.white : Colors.black,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              package.price,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showCustomNotification({
    required String message,
    required bool isSuccess,
  }) {
    final notificationService =
    Provider.of<NotificationService>(context, listen: false);
    notificationService.showNotification(
        message: message,
        isSuccess: isSuccess
    );
  }
}