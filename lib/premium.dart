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
import 'chat/chat.dart';
import 'notifications.dart';
import 'theme.dart';
import 'package:flutter/foundation.dart';

///------------------------------------------------------------------
/// Model: Kredi Paketi
///------------------------------------------------------------------
class CreditPackage {
  final int amount;
  final String productId;
  final String price;

  CreditPackage({
    required this.amount,
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
  final List<String> planTypes = ['plus', 'pro', 'ultra'];
  final GlobalKey<_CreditContentWidgetState> _creditKey = GlobalKey<_CreditContentWidgetState>();
  final bool _isTesting = !kReleaseMode;
  /// Kullanıcının seçtiği sensibler (yıllık/aylık vb.)
  Map<String, String> selectedOptions = {
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
    'credits_100',
    'credits_500',
    'credits_1000',
    'credits_2500',
    'credits_5000',
  ];

  /// Ürün ID'leri (örnek)
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

  String? _activeSubscriptionOption;

  /// Sayfalar arası geçiş (PageView)
  late PageController _pageController;
  int _currentPage = 1;

  /// Sorgulanan ürünler (abonelik planları için)
  List<ProductDetails> _subscriptions = [];

  /// Örnek (Mock) ürün listesi (Test amaçlı)
  List<ProductDetails> _mockSubscriptions = [
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
        // Eğer kredi ekranına (indeks 0) geçilmişse, default seçimi alalım.
        if (next == 0) {
          // GlobalKey kullanarak CreditContentWidget state'ine erişiyoruz.
          Future.microtask(() {
            if (_creditKey.currentState != null &&
                _creditKey.currentState!._creditPackages.isNotEmpty) {
              setState(() {
                _selectedCreditPackage = _creditKey.currentState!._creditPackages[0];
              });
            }
          });
        }
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
    } else if (_isTesting) {
      // Test modunda mock ürünleri
      setState(() {
        _subscriptions = _mockSubscriptions;
        _loading = false;
      });
    }

    User? user = _auth.currentUser;
    if (user != null) {
      try {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (userDoc.exists) {
          setState(() {
            _hasCortexSubscription = userDoc.get('hasCortexSubscription') ?? 0;
            _activeSubscriptionOption = userDoc.get('activeSubscriptionOption');

            // Eğer kullanıcının abonesi plus ise ve yıllık (annual) aktifse, doğrudan selectedOptions'ı güncelleyelim.
            if (_hasCortexSubscription == 1 && _activeSubscriptionOption == 'annual') {
              selectedOptions['plus'] = 'annual';
            } else if (_hasCortexSubscription == 2 && _activeSubscriptionOption == 'annual') {
              selectedOptions['pro'] = 'annual';
            } else if (_hasCortexSubscription == 3 && _activeSubscriptionOption == 'annual') {
              selectedOptions['ultra'] = 'annual';
            }
          });
        }
      } catch (e) {
        setState(() {
          _hasCortexSubscription = 0;
          _activeSubscriptionOption = null;
        });
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

        if (purchasedId == _annualSubscriptionPlus) {
          newSubscription = 1;
          _activeSubscriptionOption = 'annual';
        } else if (purchasedId == _monthlySubscriptionPlus) {
          newSubscription = 1;
          _activeSubscriptionOption = 'monthly';
        } else if (purchasedId == _annualSubscriptionPro) {
          newSubscription = 2;
          _activeSubscriptionOption = 'annual';
        } else if (purchasedId == _monthlySubscriptionPro) {
          newSubscription = 2;
          _activeSubscriptionOption = 'monthly';
        } else if (purchasedId == _annualSubscriptionUltra) {
          newSubscription = 3;
          _activeSubscriptionOption = 'annual';
        } else if (purchasedId == _monthlySubscriptionUltra) {
          newSubscription = 3;
          _activeSubscriptionOption = 'monthly';
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

        // Firestore güncellemesi: üretim modunda olduğu gibi
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'hasCortexSubscription': newSubscription,
          'activeSubscriptionOption': _activeSubscriptionOption,
        });

        setState(() {
          _hasCortexSubscription = newSubscription;
        });

        _showCustomNotification(
          message: AppLocalizations.of(context)!.purchaseSuccessful,
          isSuccess: true,
        );
      } catch (e) {
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

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: _errorOccurred
            ? _buildErrorScreen(context, localizations)
            : (_purchasePending || _loading)
            ? Container(
          key: const ValueKey('skeleton'),
          child: _buildSkeletonLoader(),
        )
            : Container(
          key: const ValueKey('content'),
          child: _buildPremiumContent(context, localizations),
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
      ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

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
                  color: AppColors.opposedPrimaryColor,
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
                      color: AppColors.warning,
                      size: screenWidth * 0.2,
                    ),
                    SizedBox(height: screenHeight * 0.05),
                    Text(
                      _errorMessage,
                      style: TextStyle(
                        fontSize: screenWidth * 0.045,
                        color: AppColors.opposedPrimaryColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: screenHeight * 0.075),
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
                        foregroundColor: AppColors.primaryColor,
                        backgroundColor: AppColors.opposedPrimaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(screenWidth * 0.075),
                        ),
                        padding: EdgeInsets.symmetric(
                          vertical: screenHeight * 0.04,
                          horizontal: screenWidth * 0.125,
                        ),
                      ),
                      child: Text(
                        localizations.retry,
                        style: TextStyle(
                          fontSize: screenWidth * 0.04,
                          fontWeight: FontWeight.bold,
                          color: AppColors.opposedPrimaryColor,
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
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      width: screenWidth,
      height: screenHeight,
      child: Shimmer.fromColors(
        baseColor: AppColors.shimmerBase,
        highlightColor: AppColors.shimmerHighlight,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: screenWidth * 0.04,
              vertical: screenHeight * 0.03,
            ),
            child: Column(
              children: [
                SizedBox(height: screenHeight * 0.01),
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: screenWidth * 0.06,
                    height: screenWidth * 0.07,
                    decoration: BoxDecoration(
                      color: AppColors.skeletonContainer,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                SizedBox(height: screenHeight * 0.001),
                Expanded(
                  child: PageView(
                    children: List.generate(4, (_) => _buildSkeletonPage()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonPage() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: screenHeight * 0.022),
          Container(
            width: screenWidth * 0.65,
            height: screenHeight * 0.05,
            decoration: BoxDecoration(
              color: AppColors.skeletonContainer,
              borderRadius: BorderRadius.circular(screenWidth * 0.02),
            ),
          ),
          SizedBox(height: screenHeight * 0.01),
          Container(
            width: screenWidth * 0.75,
            height: screenHeight * 0.025,
            decoration: BoxDecoration(
              color: AppColors.skeletonContainer,
              borderRadius: BorderRadius.circular(screenWidth * 0.015),
            ),
          ),
          SizedBox(height: screenHeight * 0.0016),
          Container(
            width: screenWidth * 0.65,
            height: screenHeight * 0.025,
            decoration: BoxDecoration(
              color: AppColors.skeletonContainer,
              borderRadius: BorderRadius.circular(screenWidth * 0.015),
            ),
          ),
          SizedBox(height: screenHeight * 0.01),
          Container(
            width: screenWidth * 0.25,
            height: screenWidth * 0.25,
            decoration: BoxDecoration(
              color: AppColors.skeletonContainer,
              borderRadius: BorderRadius.circular(screenWidth * 0.04),
            ),
          ),
          SizedBox(height: screenHeight * 0.005),
          Container(
            margin: EdgeInsets.symmetric(horizontal: screenWidth * 0.005),
            height: screenHeight * 0.1,
            decoration: BoxDecoration(
              color: AppColors.skeletonContainer,
              borderRadius: BorderRadius.circular(screenWidth * 0.035),
            ),
          ),
          SizedBox(height: screenHeight * 0.009),
          Container(
            margin: EdgeInsets.symmetric(horizontal: screenWidth * 0.005),
            height: screenHeight * 0.1,
            decoration: BoxDecoration(
              color: AppColors.skeletonContainer,
              borderRadius: BorderRadius.circular(screenWidth * 0.035),
            ),
          ),
          SizedBox(height: screenHeight * 0.024),
          Wrap(
            spacing: screenWidth * 0.012,
            runSpacing: screenWidth * 0.012,
            children: List.generate(6, (index) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: screenWidth * 0.05,
                    height: screenWidth * 0.05,
                    decoration: BoxDecoration(
                      color: AppColors.skeletonContainer,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: screenWidth * 0.01),
                  Container(
                    width: ((screenWidth - 2 * screenWidth * 0.04 - screenWidth * 0.024) / 2) -
                        (screenWidth * 0.05 + screenWidth * 0.01),
                    height: screenHeight * 0.03,
                    decoration: BoxDecoration(
                      color: AppColors.skeletonContainer,
                      borderRadius: BorderRadius.circular(screenWidth * 0.02),
                    ),
                  ),
                ],
              );
            }),
          ),
          SizedBox(height: screenHeight * 0.027),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (index) {
              return Container(
                margin: EdgeInsets.symmetric(horizontal: screenWidth * 0.004),
                width: screenWidth * 0.032,
                height: screenWidth * 0.032,
                decoration: BoxDecoration(
                  color: AppColors.skeletonContainer,
                  shape: BoxShape.circle,
                ),
              );
            }),
          ),
          SizedBox(height: screenHeight * 0.01),
          Container(
            width: screenWidth * 0.7,
            height: screenHeight * 0.07,
            decoration: BoxDecoration(
              color: AppColors.skeletonContainer,
              borderRadius: BorderRadius.circular(screenWidth * 0.075),
            ),
          ),
          SizedBox(height: screenHeight * 0.015),
          Column(
            children: List.generate(5, (index) {
              return Padding(
                padding: EdgeInsets.symmetric(vertical: screenHeight * 0.0012),
                child: Container(
                  width: index == 4 ? screenWidth * 0.6 : screenWidth * 0.9,
                  height: screenHeight * 0.014,
                  decoration: BoxDecoration(
                    color: AppColors.skeletonContainer,
                    borderRadius: BorderRadius.circular(screenWidth * 0.02),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumContent(
      BuildContext context,
      AppLocalizations localizations,
      ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    bool disablePurchaseButton = (_currentPage != 0 &&
        (_hasCortexSubscription == 4 ||
            _hasCortexSubscription == 5 ||
            _hasCortexSubscription == 6));

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: screenWidth * 0.04,
          vertical: screenHeight * 0.03,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Align(
              alignment: Alignment.center,
              child: IconButton(
                icon: Icon(
                  Icons.close,
                  color: AppColors.opposedPrimaryColor,
                  size: screenWidth * 0.07,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            SizedBox(height: screenHeight * 0.01),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                    if (index != 0) {
                      String currentPlan = planTypes[index - 1];
                      if ((_hasCortexSubscription == 1 && currentPlan == 'plus') ||
                          (_hasCortexSubscription == 2 && currentPlan == 'pro') ||
                          (_hasCortexSubscription == 3 && currentPlan == 'ultra')) {
                        if (_activeSubscriptionOption == 'annual') {
                          selectedOptions[currentPlan] = 'annual';
                        }
                      }
                    } else {
                      _selectedCreditPackage = _creditKey.currentState?._creditPackages.isNotEmpty == true
                          ? _creditKey.currentState!._creditPackages[0]
                          : null;
                    }
                  });
                },
                children: [
                  CreditContentWidget(
                    key: _creditKey,
                    onCreditPackageSelected: (CreditPackage package) {
                      setState(() {
                        _selectedCreditPackage = package;
                      });
                    },
                  ),
                  _buildPremiumPage(
                    context: context,
                    localizations: localizations,
                    planType: 'plus',
                  ),
                  _buildPremiumPage(
                    context: context,
                    localizations: localizations,
                    planType: 'pro',
                  ),
                  _buildPremiumPage(
                    context: context,
                    localizations: localizations,
                    planType: 'ultra',
                  ),
                ],
              ),
            ),
            SizedBox(height: screenHeight * 0.035),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (index) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: EdgeInsets.symmetric(horizontal: screenWidth * 0.01),
                  width: _currentPage == index ? screenWidth * 0.03 : screenWidth * 0.02,
                  height: screenWidth * 0.03,
                  decoration: BoxDecoration(
                    color: _currentPage == index ? AppColors.opposedPrimaryColor : AppColors.disabled,
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ),
            SizedBox(height: screenHeight * 0.01),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 500),
              opacity: (_currentPage == 0) ? 1.0 : (disablePurchaseButton ? 0.5 : 1.0),
              child: ElevatedButton(
                onPressed: disablePurchaseButton
                    ? null
                    : () {
                  if (_currentPage == 0) {
                    if (_selectedCreditPackage != null) {
                      _creditKey.currentState?.buyCreditPackage(_selectedCreditPackage!.productId);
                    }
                  } else {
                    int planIndex = _currentPage - 1;
                    String currentPlan = planTypes[planIndex];
                    if (_hasCortexSubscription == 0) {
                      _buySubscription(currentPlan);
                    } else {
                      if (_hasCortexSubscription == planIndex + 1) {
                        if (selectedOptions[currentPlan] == _activeSubscriptionOption) {
                          _cancelSubscription();
                        } else {
                          _buySubscription(currentPlan);
                        }
                      } else {
                        _buySubscription(currentPlan);
                      }
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  foregroundColor: AppColors.primaryColor,
                  backgroundColor: AppColors.opposedPrimaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(screenWidth * 0.075),
                  ),
                  padding: EdgeInsets.symmetric(
                    vertical: screenHeight * 0.02,
                    horizontal: screenWidth * 0.125,
                  ),
                ),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    switchInCurve: Curves.easeInOut,
                    switchOutCurve: Curves.easeInOut,
                    layoutBuilder: (currentChild, previousChildren) {
                      return Stack(
                        alignment: Alignment.center,
                        children: <Widget>[
                          ...previousChildren,
                          if (currentChild != null) currentChild,
                        ],
                      );
                    },
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: _currentPage == 0
                        ? Text(
                      _selectedCreditPackage != null
                          ? localizations.creditPackage(_selectedCreditPackage!.amount)
                          : localizations.buyCredit,
                      key: const ValueKey('credit'),
                      style: TextStyle(
                        fontSize: screenWidth * 0.04,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryColor,
                      ),
                    )
                        : () {
                      int planIndex = _currentPage - 1;
                      String currentPlan = planTypes[planIndex];
                      if (_hasCortexSubscription == 0) {
                        return Text(
                          selectedOptions[currentPlan] == 'annual'
                              ? localizations.startFreeTrial30Days
                              : localizations.startFreeTrial7Days,
                          key: ValueKey('${selectedOptions[currentPlan]}-$currentPlan'),
                          style: TextStyle(
                            fontSize: screenWidth * 0.04,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryColor,
                          ),
                        );
                      } else {
                        if (_hasCortexSubscription == planIndex + 1) {
                          if (selectedOptions[currentPlan] == _activeSubscriptionOption) {
                            return Text(
                              localizations.cancelSubscription,
                              key: ValueKey('cancel-$currentPlan'),
                              style: TextStyle(
                                fontSize: screenWidth * 0.04,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryColor,
                              ),
                            );
                          } else {
                            return Text(
                              localizations.upgradeSubscription,
                              key: ValueKey('upgrade-$currentPlan'),
                              style: TextStyle(
                                fontSize: screenWidth * 0.04,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryColor,
                              ),
                            );
                          }
                        } else {
                          return Text(
                            localizations.upgradeSubscription,
                            key: ValueKey('upgrade-$currentPlan'),
                            style: TextStyle(
                              fontSize: screenWidth * 0.04,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryColor,
                            ),
                          );
                        }
                      }
                    }(),
                  ),
                ),
              ),
            ),
            SizedBox(height: screenHeight * 0.01),
            TextButton(
              onPressed: () => _showTermsAndConditions(context),
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(screenWidth * 0.03),
                ),
              ),
              child: Text(
                localizations.termsOfServiceAndPrivacyPolicyWarning,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.tertiaryColor,
                  fontSize: screenWidth * 0.024,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumPage({
    required BuildContext context,
    required AppLocalizations localizations,
    required String planType,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    String purchaseKey;
    String descriptionKey;
    bool isBestValue;
    String logoPath;

    bool globalDisabled = (_hasCortexSubscription == 4 ||
        _hasCortexSubscription == 5 ||
        _hasCortexSubscription == 6);

    bool isActivePlan = false;
    if (planType == 'plus') {
      if (_hasCortexSubscription == 1 || _hasCortexSubscription == 4) {
        isActivePlan = true;
      }
    } else if (planType == 'pro') {
      if (_hasCortexSubscription == 2 || _hasCortexSubscription == 5) {
        isActivePlan = true;
      }
    } else if (planType == 'ultra') {
      if (_hasCortexSubscription == 3 || _hasCortexSubscription == 6) {
        isActivePlan = true;
      }
    }

    if (planType == 'pro') {
      purchaseKey = localizations.purchasePro;
      descriptionKey = localizations.proDescription;
      isBestValue = !globalDisabled;
      logoPath = AppColors.currentTheme == 'dark' ? 'assets/whitepro.png' : 'assets/prologo.png';
    } else if (planType == 'ultra') {
      purchaseKey = localizations.purchaseUltra;
      descriptionKey = localizations.ultraDescription;
      isBestValue = !globalDisabled;
      logoPath = AppColors.currentTheme == 'dark' ? 'assets/whiteultra.png' : 'assets/ultralogo.png';
    } else {
      purchaseKey = localizations.purchasePlus;
      descriptionKey = localizations.plusDescription;
      isBestValue = !globalDisabled;
      logoPath = AppColors.currentTheme == 'dark' ? 'assets/whiteplus.png' : 'assets/pluslogo.png';
    }

    Widget header = Text(
      purchaseKey,
      style: TextStyle(
        fontSize: screenWidth * 0.07,
        fontWeight: FontWeight.bold,
        color: AppColors.opposedPrimaryColor,
      ),
      textAlign: TextAlign.center,
    );

    return SingleChildScrollView(
      child: Column(
        children: [
          header,
          SizedBox(height: screenHeight * 0.01),
          Text(
            descriptionKey,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: screenWidth * 0.035,
              color: AppColors.tertiaryColor,
            ),
          ),
          SizedBox(height: screenHeight * 0.01),
          Image.asset(
            logoPath,
            height: screenWidth * 0.25,
          ),
          SizedBox(height: screenHeight * 0.01),
          _buildSubscriptionOption(
            context: context,
            localizations: localizations,
            option: 'annual',
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
            isSelected: selectedOptions[planType] == 'annual',
            isSubscribedPlan: isActivePlan,
            activeSubscriptionOption: _activeSubscriptionOption ?? '',
            globalDisabled: globalDisabled,
            onSelect: () => setState(() {
              if (!globalDisabled) selectedOptions[planType] = 'annual';
            }),
          ),
          SizedBox(height: screenHeight * 0.01),
          _buildSubscriptionOption(
            context: context,
            localizations: localizations,
            option: 'monthly',
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
            isSelected: selectedOptions[planType] == 'monthly',
            isSubscribedPlan: isActivePlan,
            activeSubscriptionOption: _activeSubscriptionOption ?? '',
            globalDisabled: globalDisabled,
            onSelect: () => setState(() {
              if (!globalDisabled) selectedOptions[planType] = 'monthly';
            }),
          ),
          SizedBox(height: screenHeight * 0.02),
          _buildBenefitsList(context, localizations, planType),
        ],
      ),
    );
  }

  Widget _buildSubscriptionOption({
    required BuildContext context,
    required AppLocalizations localizations,
    required String option,
    required String title,
    required String description,
    bool isBestValue = false,
    required bool isSelected,
    required bool isSubscribedPlan,
    required String activeSubscriptionOption,
    required bool globalDisabled,
    required VoidCallback onSelect,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final titleFontSize = screenWidth * 0.045;
    final descriptionFontSize = screenWidth * 0.04;

    double finalOpacity = 1.0;
    if (globalDisabled) {
      finalOpacity = 0.5;
    } else if (isSubscribedPlan &&
        activeSubscriptionOption == 'annual' &&
        option == 'monthly') {
      finalOpacity = 0.3; // Yıllık aboneyse aylık seçeneğini soldur
    }

    final bool showCheck = globalDisabled
        ? true
        : (isSubscribedPlan && (activeSubscriptionOption == option));

    // Aylık planın tıklanabilirliği (yıllık abone olmuşsa kapalı)
    bool disabled = globalDisabled ||
        (isSubscribedPlan &&
            activeSubscriptionOption == 'annual' &&
            option == 'monthly');

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 500),
      opacity: finalOpacity,
      child: GestureDetector(
        onTap: disabled ? null : onSelect,
        child: AnimatedContainer(
          width: screenWidth * 0.9,
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: AppColors.quaternaryColor,
            borderRadius: BorderRadius.circular(screenWidth * 0.04),
            border: Border.all(
              color: isSelected ? AppColors.opposedPrimaryColor : Colors.transparent,
              width: screenWidth * 0.003,
            ),
          ),
          padding: EdgeInsets.all(screenWidth * 0.035),
          child: Stack(
            children: [
              // Başlık + (En İyi Değer) + Açıklama
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Satır: Başlık ve En İyi Değer
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Başlık
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.bold,
                            color: AppColors.opposedPrimaryColor,
                          ),
                        ),
                      ),
                      // "En İyi Değer" etiketi (annual + isBestValue = true)
                      if (option == 'annual' && isBestValue)
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 500),
                          transitionBuilder: (child, animation) => FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                          child: showCheck
                              ? const SizedBox.shrink()
                              : Container(
                            key: const ValueKey('bestValueText'),
                            padding: EdgeInsets.symmetric(
                              vertical: screenWidth * 0.008,
                              horizontal: screenWidth * 0.015,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(screenWidth * 0.012),
                            ),
                            child: Text(
                              localizations.bestValue,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: screenWidth * 0.025,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: screenWidth * 0.012),
                  // 2. Satır: Açıklama inside a FittedBox for scaling down long text
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      description,
                      style: TextStyle(
                        fontSize: descriptionFontSize,
                        color: AppColors.opposedPrimaryColor,
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                bottom: screenWidth * 0.05,
                right: screenWidth * 0,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                  child: showCheck
                      ? SvgPicture.asset(
                    'assets/checkmark.svg',
                    key: const ValueKey('checkIcon'),
                    color: Colors.green,
                    width: screenWidth * 0.09,
                    height: screenWidth * 0.09,
                  )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBenefitsList(
      BuildContext context,
      AppLocalizations localizations,
      String planType,
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
        Color iconColor = questionMarkBenefits.contains(benefit) ? Colors.yellow : Colors.green;

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
                    color: AppColors.opposedPrimaryColor,
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
  /// _cancelSubscription
  ///------------------------------------------------------------------
  void _cancelSubscription() async {
    User? user = _auth.currentUser;
    if (_isTesting) {
      // Test modunda iptal edildiğinde abonelik sıfırlansın.
      setState(() {
        _hasCortexSubscription = 0;
        _activeSubscriptionOption = null;
      });
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'hasCortexSubscription': 0,
          'activeSubscriptionOption': null,
        });
      }
      _showCustomNotification(
        message: "Subscription cancelled (test mode).",
        isSuccess: true,
      );
      return;
    }

    // Üretim modunda, iptal işlemi için kullanıcı mağaza abonelik yönetimine yönlendirilir.
    Uri url;
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.android) {
      url = Uri.parse(
        'https://play.google.com/store/account/subscriptions?package=com.vertex.cortex',
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
        final screenWidth = MediaQuery.of(context).size.width;

        return AlertDialog(
          backgroundColor: AppColors.secondaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(screenWidth * 0.04),
          ),
          title: Text(
            localizations.upgradeSubscription,
            style: TextStyle(
              color: AppColors.opposedPrimaryColor,
              fontSize: screenWidth * 0.05,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            localizations.confirmUpgrade,
            style: TextStyle(
              color: AppColors.opposedPrimaryColor,
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
                backgroundColor: AppColors.opposedPrimaryColor,
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
                  color: AppColors.primaryColor,
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

  void _showTermsAndConditions(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(screenWidth * 0.05)),
      ),
      builder: (BuildContext context) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: screenHeight * 0.6,
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
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          localizations.termsOfServiceAndPrivacyPolicyTitle,
                          style: TextStyle(
                            fontSize: screenWidth * 0.05,
                            fontWeight: FontWeight.bold,
                            color: AppColors.opposedPrimaryColor,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: AppColors.opposedPrimaryColor.withOpacity(0.6),
                        size: screenWidth * 0.06,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                SizedBox(height: screenHeight * 0.02),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      localizations.termsOfServiceAndPrivacyPolicyContent,
                      style: TextStyle(
                        fontSize: screenWidth * 0.035,
                        color: AppColors.opposedPrimaryColor,
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
  static const String _productId100 = 'credits_100';
  static const String _productId500 = 'credits_500';
  static const String _productId1000 = 'credits_1000';
  static const String _productId2500 = 'credits_2500';
  static const String _productId5000 = 'credits_5000';

  /// Sorgulanan ürünler
  List<ProductDetails> _availableProducts = [];
  bool _isAvailable = false;
  bool _purchasePending = false;
  bool _loading = true;
  bool _errorOccurred = false;
  String _errorMessage = '';

  bool _isTesting = !kReleaseMode;


  @override
  void initState() {
    super.initState();
    _initializeCreditPackages();
    _selectedCardIndex = 0;
    // Varsayılan seçimi parent'a bildiriyoruz
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.onCreditPackageSelected != null && _creditPackages.isNotEmpty) {
        widget.onCreditPackageSelected!(_creditPackages[0]);
      }
    });

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
      CreditPackage(amount: 100, productId: _productId100, price: '\$0.99'),
      CreditPackage(amount: 500, productId: _productId500, price: '\$4.99'),
      CreditPackage(amount: 1000, productId: _productId1000, price: '\$9.99'),
      CreditPackage(amount: 2500, productId: _productId2500, price: '\$24.99'),
      CreditPackage(amount: 5000, productId: _productId5000, price: '\$49.99'),
    ];
  }

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
    } else if (_isTesting) {
      setState(() {
        _availableProducts = _creditPackages.map((cp) => ProductDetails(
          id: cp.productId,
          title: '${cp.amount} Credits',
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
        }
      } catch (e) {
      }
    }
  }

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

  /// TÜM KREDİ SATIN ALMA AKIŞINI YÖNETEN FONKSİYON
  /// PremiumScreen'deki buton, artık bu metodu çağıracak.
  void buyCreditPackage(String productId) {
    ProductDetails? product;
    try {
      product = _availableProducts.firstWhere((p) => p.id == productId);
    } catch (e) {
      product = null;
    }

    if (_isTesting) {
      // Test modunda; ürün bulunamazsa bile doğrudan teslimat simülasyonu yap
      _deliverCreditPurchase(
        PurchaseDetails(
          purchaseID: 'mock_purchase_id',
          productID: productId,
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
      if (product == null) {
        setState(() {
          _errorOccurred = true;
          _errorMessage = 'Kredi ürünü bulunamadı.';
        });
        _showCustomNotification(message: 'Kredi ürünü bulunamadı.', isSuccess: false);
        return;
      }
      final purchaseParam = PurchaseParam(productDetails: product);
      _localInAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
    }
  }

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
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'credits': FieldValue.increment(addedCredits)});

        _showCustomNotification(
          message: 'Krediler başarıyla eklendi!',
          isSuccess: true,
        );
      } catch (e) {
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

  void _showCustomNotification({required String message, required bool isSuccess}) {
    final notificationService = Provider.of<NotificationService>(context, listen: false);
    notificationService.showNotification(message: message, isSuccess: isSuccess);
  }

  @override
  Widget build(BuildContext context) {
    Widget child;

    if (_errorOccurred) {
      child = Center(
        key: const ValueKey('creditError'),
        child: Text(
          _errorMessage,
          style: TextStyle(color: AppColors.opposedPrimaryColor),
        ),
      );
    } else if (_purchasePending || _loading) {
      child = _buildCreditSkeleton(context);
    } else {
      child = _buildCreditContent(context);
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      child: child,
    );
  }

  Widget _buildCreditSkeleton(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: screenWidth * 0.6,
            height: screenHeight * 0.04,
            decoration: BoxDecoration(
              color: AppColors.skeletonContainer,
              borderRadius: BorderRadius.circular(screenWidth * 0.02),
            ),
          ),
          SizedBox(height: screenHeight * 0.005),
          Container(
            width: screenWidth * 0.9,
            height: screenHeight * 0.025,
            decoration: BoxDecoration(
              color: AppColors.skeletonContainer,
              borderRadius: BorderRadius.circular(screenWidth * 0.02),
            ),
          ),
          SizedBox(height: screenHeight * 0.002),
          Container(
            width: screenWidth * 0.6,
            height: screenHeight * 0.025,
            decoration: BoxDecoration(
              color: AppColors.skeletonContainer,
              borderRadius: BorderRadius.circular(screenWidth * 0.02),
            ),
          ),
          SizedBox(height: screenHeight * 0.005),
          Expanded(
            child: ListView.builder(
              itemCount: 5,
              itemBuilder: (context, index) {
                return Padding(
                  padding: EdgeInsets.only(
                    top: index == 0 ? 0 : screenHeight * 0.007,
                    bottom: screenHeight * 0.01,
                    left: screenWidth * 0.035,
                    right: screenWidth * 0.035,
                  ),
                  child: Container(
                    width: double.infinity,
                    height: screenHeight * 0.1,
                    decoration: BoxDecoration(
                      color: AppColors.skeletonContainer,
                      borderRadius: BorderRadius.circular(screenWidth * 0.02),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreditContent(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          localizations.buyCredits,
          style: TextStyle(
            fontSize: screenWidth * 0.06,
            fontWeight: FontWeight.bold,
            color: AppColors.opposedPrimaryColor,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: screenHeight * 0.001),
        Text(
          localizations.selectCreditPackageDescription,
          style: TextStyle(fontSize: screenWidth * 0.035, color: AppColors.tertiaryColor),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: screenHeight * 0.001),
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
                  duration: const Duration(milliseconds: 300),
                  margin: EdgeInsets.symmetric(
                    vertical: screenHeight * 0.01,
                    horizontal: screenWidth * 0.04,
                  ),
                  padding: EdgeInsets.all(screenWidth * 0.04),
                  decoration: BoxDecoration(
                    color: AppColors.quaternaryColor,
                    borderRadius: BorderRadius.circular(screenWidth * 0.03),
                    border: isSelected
                        ? Border.all(color: AppColors.opposedPrimaryColor, width: screenWidth * 0.003)
                        : Border.all(color: Colors.transparent, width: screenWidth * 0.003),
                  ),
                  child: Row(
                    children: [
                      SvgPicture.asset(
                        'assets/credit.svg',
                        width: screenWidth * 0.1,
                        height: screenWidth * 0.1,
                        color: AppColors.opposedPrimaryColor,
                      ),
                      SizedBox(width: screenWidth * 0.02),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              localizations.creditPackage(package.amount),
                              style: TextStyle(
                                fontSize: screenWidth * 0.045,
                                fontWeight: FontWeight.bold,
                                color: AppColors.opposedPrimaryColor,
                              ),
                            ),
                            Builder(
                              builder: (context) {
                                String displayedPrice = package.price;
                                for (var product in _availableProducts) {
                                  if (product.id == package.productId) {
                                    displayedPrice = product.price;
                                    break;
                                  }
                                }
                                return Text(
                                  displayedPrice,
                                  style: TextStyle(fontSize: screenWidth * 0.04, color: AppColors.tertiaryColor),
                                );
                              },
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
}
