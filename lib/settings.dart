// settings.dart
import 'dart:async';

import 'package:cortex/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat/chat.dart';
import 'locale_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login.dart';
import 'package:shimmer/shimmer.dart'; // Updated import
import 'dart:math'; // For animation
import 'notifications.dart'; // Added for NotificationService
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart'; // Import for internet connection checker
import 'package:url_launcher/url_launcher.dart';

class ShakeWidget extends StatefulWidget {
  final Widget child;
  final AnimationController controller;

  const ShakeWidget({
    Key? key,
    required this.child,
    required this.controller,
  }) : super(key: key);

  @override
  _ShakeWidgetState createState() => _ShakeWidgetState();
}

class _ShakeWidgetState extends State<ShakeWidget> {
  late Animation<double> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _offsetAnimation = Tween<double>(begin: 0, end: 1)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(widget.controller);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offsetAnimation,
      builder: (context, child) {
        final dx =
            8 * (0.5 - 0.5 * (1 + (0.5 * _offsetAnimation.value)).abs());
        return Transform.translate(
          offset: Offset(dx, 0),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  _AccountScreenState createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen>
    with TickerProviderStateMixin {
  String _selectedLanguageCode = 'en';
  Map<String, dynamic>? _userData;
  int _hasCortexSubscription = 0;
  bool _isAlphaUser = false; // For alpha user
  bool _hasInternet = true;
  bool _isVerified = false;        // Kullanıcının doğrulanıp doğrulanmadığı
  bool _accountDeletionAttempted = false;
  int _verifyAttempts = 0;
  int _remainingSeconds = 0;         // Artık 24 saat - geçen zaman
  Timer? _countdownTimer;       // Account ekranındaki geri sayım Timer
// Firestore'dan çektiğimiz createdAt
  bool _isVerifiedByAuth = false;   // Firestore'daki verified yok, direkt Auth'tan alıyoruz

  // Animation controller for the animated border
  late AnimationController _animationController;
  late Animation<double> _animation;

  // For "Edit Profile" dialog (username)
  late AnimationController _editProfileShakeController;

  // For "Change Password" dialog
  late AnimationController _oldPasswordShakeController;
  late AnimationController _newPasswordShakeController;
  late AnimationController _confirmPasswordShakeController;

  // For "Delete Account" dialog
  late AnimationController _deleteAccountPasswordShakeController;

  // NotificationService instance
  late NotificationService _notificationService;

  /// Aynı kuralları burada da uygulamak için username regex'i ekliyoruz.
  /// * Sadece harfler (abcçdefgğhıijklmnoöprsştuüvyzxqw), nokta(.), tire(-) ve alt çizgi(_).
  /// * Uzunluk 3-16 karakter arasında.
  final RegExp _usernameRegExp = RegExp(
    r'^[abcçdefgğhıijklmnoöprsştuüvyzxqw\.\-_]{3,16}$',
    caseSensitive: false,
  );

  bool _isDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
    _checkInternetStatus(); // İnternet durumunu kontrol et

    _notificationService =
        Provider.of<NotificationService>(context, listen: false);

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _animation = Tween<double>(begin: 0, end: 2 * pi).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.linear),
    );

    final locale = Provider.of<LocaleProvider>(context, listen: false).locale;
    _selectedLanguageCode = locale.languageCode;

    const shakeDuration = Duration(milliseconds: 500);

    _editProfileShakeController =
        AnimationController(vsync: this, duration: shakeDuration);

    _oldPasswordShakeController =
        AnimationController(vsync: this, duration: shakeDuration);
    _newPasswordShakeController =
        AnimationController(vsync: this, duration: shakeDuration);
    _confirmPasswordShakeController =
        AnimationController(vsync: this, duration: shakeDuration);

    _deleteAccountPasswordShakeController =
        AnimationController(vsync: this, duration: shakeDuration);
  }

  Future<void> _checkInternetStatus() async {
    bool has = await _hasInternetConnection();
    setState(() {
      _hasInternet = has;
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _countdownTimer?.cancel();
    _editProfileShakeController.dispose();
    _oldPasswordShakeController.dispose();
    _newPasswordShakeController.dispose();
    _confirmPasswordShakeController.dispose();
    _deleteAccountPasswordShakeController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserData() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server));

      if (!userDoc.exists) {
        await FirebaseAuth.instance.signOut();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
        return;
      }

      final data = userDoc.data() as Map<String, dynamic>;
      final int verifyAttempts = data['verifyAttempts'] ?? 0; // Get server-side attempts

      await user.reload();
      final isVerifiedAuth = user.emailVerified;

      if (data['createdAt'] is Timestamp) {
        final createdAtTimestamp = data['createdAt'] as Timestamp;
        final serverNow = Timestamp.now();
        final diff = serverNow
            .toDate()
            .difference(createdAtTimestamp.toDate())
            .inSeconds;

        final totalSec = 86400 * (1 + verifyAttempts);
        final remain = totalSec - diff;

        setState(() {
          _userData = data; // Assign fetched data to _userData
          _verifyAttempts = verifyAttempts; // Assign to the class variable
          _remainingSeconds = remain > 0 ? remain : 0;
          _isVerified = isVerifiedAuth;
          _hasCortexSubscription = data['hasCortexSubscription'] ?? 0; // Update subscription
          _isAlphaUser = data['alphaUser'] ?? false; // Update alpha user status
        });
      } else {
        setState(() {
          _userData = data; // Assign fetched data to _userData
          _verifyAttempts = verifyAttempts;
          _remainingSeconds = 0;
          _isVerified = isVerifiedAuth;
          _hasCortexSubscription = data['hasCortexSubscription'] ?? 0;
          _isAlphaUser = data['alphaUser'] ?? false;
        });
      }

      if (_remainingSeconds > 0 && !_isVerified) {
        _startCountdownTimer();
      } else if (_remainingSeconds <= 0 && !_isVerified && !_accountDeletionAttempted) {
        _accountDeletionAttempted = true;
        await _deleteUnverifiedAccount();
      }
    } catch (e) {
      debugPrint("Error fetching user data: $e");
    }
  }

  // 3. **Modify the `_buildUnverifiedPanel` Widget:**
  Widget _buildUnverifiedPanel(AppLocalizations appLocalizations) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final timeStr = _formatRemainingTime(_remainingSeconds);

    return Container(
      margin: EdgeInsets.only(bottom: screenHeight * 0.02),
      padding: EdgeInsets.all(screenWidth * 0.04),
      decoration: BoxDecoration(
        color: AppColors.unverifiedPanelBackground,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: AppColors.warning, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            appLocalizations.unverifiedAccountHeader,
            style: TextStyle(
              fontSize: screenWidth * 0.045,
              fontWeight: FontWeight.bold,
              color: AppColors.opposedPrimaryColor,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: screenHeight * 0.01),
          Text(
            appLocalizations.unverifiedAccountWarning(timeStr),
            style: TextStyle(
              fontSize: screenWidth * 0.035,
              color: AppColors.quinaryColor,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: screenHeight * 0.015),
          AnimatedTime(
            time: timeStr,
            style: GoogleFonts.anaheim(
              textStyle: TextStyle(
                fontSize: screenWidth * 0.05,
                color: AppColors.opposedPrimaryColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(height: screenHeight * 0.015),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: Size.fromHeight(screenHeight * 0.06),
                backgroundColor: AppColors.senaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _verifyNow,
              child: Text(
                appLocalizations.verifyNow,
                style: TextStyle(
                  color: AppColors.opposedPrimaryColor,
                  fontSize: screenWidth * 0.04,
                ),
              ),
            ),
          ),
          SizedBox(height: screenHeight * 0.015),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: Size.fromHeight(screenHeight * 0.06),
                backgroundColor: AppColors.senaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _verifyAttempts >= 2 ? null : _resendVerificationEmailFromAccount,
              child: Text(
                appLocalizations.resendCode,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.opposedPrimaryColor,
                  fontSize: screenWidth * 0.04,
                ),
              ),
            ),
          ),
          if (_verifyAttempts >= 2)
            Padding(
              padding: EdgeInsets.only(top: screenHeight * 0.01),
              child: Center(
                child: Text(
                  appLocalizations.maxResendLimitReached,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.warning,
                    fontSize: screenWidth * 0.035,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 4. **Update the `_resendVerificationEmailFromAccount` Method:**
  Future<void> _resendVerificationEmailFromAccount() async {
    final appLocalizations = AppLocalizations.of(context)!;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final docSnapshot = await userDocRef.get();
      final int verifyAttempts = docSnapshot.data()?['verifyAttempts'] ?? 0;

      if (verifyAttempts >= 2) {
        _notificationService.showNotification(
          message: appLocalizations.maxResendLimitReached,
          isSuccess: false,
          bottomOffset: 0.02,
        );
        return;
      }

      await user.sendEmailVerification();
      await userDocRef.update({'verifyAttempts': FieldValue.increment(1)});

      // 4a. **Refresh the local `_verifyAttempts` by calling `_fetchUserData`:**
      await _fetchUserData();

      _notificationService.showNotification(
        message: appLocalizations.linkSent,
        isSuccess: true,
        bottomOffset: 0.02,
      );

    } catch (e) {
      debugPrint("Resend error: $e");
      _notificationService.showNotification(
        message: appLocalizations.authError,
        isSuccess: false,
        bottomOffset: 0.02,
      );
    }
  }

// Inside _AccountScreenState

  /// Starts the countdown timer to delete the account if not verified.
  void _startCountdownTimer() {
    // Cancel any existing timer
    _countdownTimer?.cancel();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_remainingSeconds <= 0) {
        timer.cancel();
        setState(() {
          _remainingSeconds = 0;
        });

        // Proceed to delete the account if not already attempted
        if (!_isVerified && !_accountDeletionAttempted) {
          _accountDeletionAttempted = true;
          await _deleteUnverifiedAccount();
        }
      } else {
        setState(() {
          _remainingSeconds--;
        });
      }
    });
  }

  Future<void> _deleteUnverifiedAccount() async {
    final appLocalizations = AppLocalizations.of(context)!;
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
        await user.delete();
        await FirebaseAuth.instance.signOut();
        _notificationService.showNotification(
          message: appLocalizations.accountDeleted,
          isSuccess: true,
          bottomOffset: 0.01,
        );
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      } else {
        _notificationService.showNotification(
          message: appLocalizations.accountDeleted,
          isSuccess: true,
          bottomOffset: 0.01,
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      debugPrint("FirebaseAuthException while deleting account: $e");
      await FirebaseAuth.instance.signOut();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
      _notificationService.showNotification(
        message: appLocalizations.accountDeleted,
        bottomOffset: 0.02,
        isSuccess: true,
      );
    }
  }

  /// Dili değiştirir
  void _changeLanguage(String languageCode) {
    final localeProvider = Provider.of<LocaleProvider>(context, listen: false);
    setState(() {
      _selectedLanguageCode = languageCode;
    });
    localeProvider.setLocale(Locale(languageCode));
    ChatScreenState.languageHasJustChanged = true;
  }

  /// İnternet bağlantısı var mı?
  Future<bool> _hasInternetConnection() async {
    return await InternetConnection().hasInternetAccess;
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context)!;
    final themeProvider = Provider.of<ThemeProvider>(context, listen: true);
    // Determine the display name and email remains the same…
    String displayName;
    String email;
    if (_userData != null && _userData!['username'] != null) {
      displayName = _userData!['username'];
    } else {
      displayName = FirebaseAuth.instance.currentUser?.email ?? '';
    }
    email = FirebaseAuth.instance.currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        title: Text(
          appLocalizations.settings,
          style: GoogleFonts.roboto(color: AppColors.opposedPrimaryColor),
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: IconThemeData(
          color: AppColors.opposedPrimaryColor,
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        child: _userData == null
            ? _buildSkeletonLoader()
            : _buildContent(displayName, email, appLocalizations),
      ),
    );
  }

  /// Kayıtları gelene kadar skeleton göstermek için
  Widget _buildSkeletonLoader() {
    return SkeletonLoaderShimmer();
  }

  Widget _buildContent(String displayName, String email, AppLocalizations appLocalizations) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return ListView(
      key: const ValueKey('content'),
      // Eskiden: padding: const EdgeInsets.all(16.0),
      padding: EdgeInsets.all(screenWidth * 0.04),
      children: [
        _buildProfileHeader(displayName, email),
        SizedBox(height: screenHeight * 0.02),

        // Eğer hesap doğrulanmamışsa VE internet varsa
        if (!_isVerified && _hasInternet)
          _buildUnverifiedPanel(appLocalizations),

        SizedBox(height: screenHeight * 0.01),
        _buildUserSection(appLocalizations),
        SizedBox(height: screenHeight * 0.03),
        _buildLanguageSelection(appLocalizations),
        SizedBox(height: screenHeight * 0.025),
        _buildThemeSelection(appLocalizations),
        SizedBox(height: screenHeight * 0.025),
        _buildSettingsSection(appLocalizations),
        SizedBox(height: screenHeight * 0.025),
        _buildDeleteSection(appLocalizations),
      ],
    );
  }

  Widget _buildProfileHeader(String displayName, String email) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    double avatarSize = screenWidth * 0.25;
    double fontSizeName = screenWidth * 0.06;
    double fontSizeEmail = screenWidth * 0.04;
    double spacing = screenWidth * 0.04;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_hasCortexSubscription >= 1)
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: AnimatedBorderPainter(
                      animationValue: _animation.value,
                    ),
                    child: Container(
                      width: avatarSize,
                      height: avatarSize,
                      padding: EdgeInsets.all(screenWidth * 0.01),
                      child: CircleAvatar(
                        radius: avatarSize / 2.2,
                        backgroundColor: AppColors.secondaryColor,
                        child: Text(
                          displayName.isNotEmpty ? displayName[0].toUpperCase() : '',
                          style: TextStyle(
                            fontSize: avatarSize / 2.5,
                            color: AppColors.opposedPrimaryColor,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              )
            else
              Container(
                width: avatarSize,
                height: avatarSize,
                padding: EdgeInsets.all(screenWidth * 0.01),
                child: CircleAvatar(
                  radius: avatarSize / 2.2,
                  backgroundColor: AppColors.secondaryColor,
                  child: Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : '',
                    style: TextStyle(
                      fontSize: avatarSize / 2.5,
                      color: AppColors.opposedPrimaryColor,
                    ),
                  ),
                ),
              ),
            SizedBox(width: spacing),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      displayName,
                      style: GoogleFonts.poppins(
                        color: AppColors.opposedPrimaryColor,
                        fontSize: fontSizeName,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      email,
                      style: GoogleFonts.poppins(
                        color: AppColors.quinaryColor,
                        fontSize: fontSizeEmail,
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.01),
                  Row(
                    children: [
                      if (_hasCortexSubscription >= 1)
                        _buildBadge(
                          Icons.star,
                          _getSubscriptionLabel(_hasCortexSubscription),
                        ),
                      if (_hasCortexSubscription >= 1 && _isAlphaUser)
                        SizedBox(width: screenWidth * 0.02),
                      if (_isAlphaUser)
                        _buildBadge(Icons.explore, "Alpha"),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _verifyNow() async {
    final appLocalizations = AppLocalizations.of(context)!;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await user.reload();
    if (user.emailVerified) {
      setState(() {
        _isVerifiedByAuth = true;
        _isVerified = true;
      });

      _notificationService.showNotification(
        message: AppLocalizations.of(context)!.accountVerified,
        bottomOffset: 0.02,
        isSuccess: true,
      );
    } else {
      _notificationService.showNotification(
        message: AppLocalizations.of(context)!.authError,
        bottomOffset: 0.02,
        isSuccess: false,
      );
    }
  }

  String _formatRemainingTime(int totalSeconds) {
    if (totalSeconds < 1) {
      return "00:00:00";
    }
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final hh = hours.toString().padLeft(2, '0');
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return "$hh:$mm:$ss";
  }

  Widget _buildUserSection(AppLocalizations appLocalizations) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appLocalizations.user,
          style: GoogleFonts.roboto(
            color: AppColors.opposedPrimaryColor,
            fontSize: screenWidth * 0.05,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: screenHeight * 0.01),
        Text(
          appLocalizations.manageProfileDescription,
          style: GoogleFonts.roboto(
            color: AppColors.quinaryColor,
            fontSize: screenWidth * 0.035,
          ),
        ),
        SizedBox(height: screenHeight * 0.02),
        _buildCenteredButton(
          context: context,
          text: appLocalizations.editProfile,
          icon: Icons.edit,
          onPressed: () async {
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              bool hasInternet = await _hasInternetConnection();
              if (hasInternet) {
                _showEditProfileDialog(user);
              } else {
                _notificationService.showNotification(
                  bottomOffset: 0.02,
                  isSuccess: false,
                  message: appLocalizations.noInternetConnection,
                );
              }
            }
          },
        ),
        SizedBox(height: screenHeight * 0.015),
        _buildCenteredButton(
          context: context,
          text: appLocalizations.changePassword,
          icon: Icons.lock,
          onPressed: () async {
            bool hasInternet = await _hasInternetConnection();
            if (hasInternet) {
              _showChangePasswordDialog();
            } else {
              _notificationService.showNotification(
                bottomOffset: 0.02,
                isSuccess: false,
                message: appLocalizations.noInternetConnection,
              );
            }
          },
        ),
        SizedBox(height: screenHeight * 0.015),
        _buildCenteredButton(
          context: context,
          text: appLocalizations.logout,
          icon: Icons.lock,
          onPressed: () async {
            bool hasInternet = await _hasInternetConnection();
            if (hasInternet) {
              _showLogoutConfirmationDialog(appLocalizations);
            } else {
              _notificationService.showNotification(
                bottomOffset: 0.02,
                message: appLocalizations.noInternetConnection,
              );
            }
          },
        ),
      ],
    );
  }

  Future<void> _showLogoutConfirmationDialog(AppLocalizations appLocalizations) async {
    if (_isDialogOpen) return;
    setState(() => _isDialogOpen = true);

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        systemNavigationBarColor: AppColors.background,
      ),
    );
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Logout',
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(ctx).size.width * 0.8,
              decoration: BoxDecoration(
                color: AppColors.dialogColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Text(
                            appLocalizations.logout,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.opposedPrimaryColor,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            appLocalizations.logoutConfirmationTitle,
                            style: TextStyle(
                              color: AppColors.opposedPrimaryColor.withOpacity(0.4),
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
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
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                splashColor: Colors.blue.withOpacity(0.3),
                                highlightColor: Colors.blue.withOpacity(0.1),
                                onTap: () => Navigator.of(ctx).pop(),
                                child: Container(
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  child: Text(
                                    appLocalizations.no,
                                    style: const TextStyle(
                                      color: Colors.blue,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          VerticalDivider(
                            width: 1,
                            thickness: 0.5,
                            color: AppColors.dialogDivider,
                          ),
                          Expanded(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                splashColor: Colors.red.withOpacity(0.3),
                                highlightColor: Colors.red.withOpacity(0.1),
                                onTap: () async {
                                  await FirebaseAuth.instance.signOut();
                                  Navigator.of(context).pushAndRemoveUntil(
                                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                                        (Route<dynamic> route) => false,
                                  );
                                },
                                child: Container(
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  child: const Text(
                                    'Yes',
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontSize: 16,
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
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    ).then((_) {
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(systemNavigationBarColor: AppColors.opposedPrimaryColor),
      );
      setState(() => _isDialogOpen = false);
    });
  }

  Future<void> _shareApp() async {
    try {
      final appLocalizations = AppLocalizations.of(context)!;
      await Share.share(
        appLocalizations.shareMessage,
        subject: appLocalizations.shareSubject,
      );
    } catch (e) {
      debugPrint("Error sharing app: $e");
      _notificationService.showNotification(
        message: AppLocalizations.of(context)!.shareFailed,
        isSuccess: false,
        bottomOffset: 0.02,
      );
    }
  }

  Future<void> _launchURL(String url) async {
    final Uri _url = Uri.parse(url);
    if (!await launchUrl(_url, mode: LaunchMode.externalApplication)) {
      throw 'Could not launch $url';
    }
  }

  void _launchRateUs() {
    _launchURL("https://play.google.com/store/apps/details?id=com.vertex.cortex");
  }

  void _launchHelp() {
    _launchURL("https://discord.gg/sK53fypPBZ");
  }

  void _showTermsOfUse(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final backgroundColor = AppColors.background;
    final textColor = AppColors.primaryColor;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      localizations.termsOfUse,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close,
                          color: textColor.withOpacity(0.6), size: 24),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: SingleChildScrollView(
                    child: RichText(
                      text: TextSpan(
                        children: localizations.termsOfUseContent.split(' ').map((word) {
                          if (word.startsWith('**') && word.endsWith('**')) {
                            return TextSpan(
                              text: word.replaceAll('**', '').toUpperCase() + ' ',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: textColor,
                              ),
                            );
                          } else if (word.startsWith('*') && word.endsWith('*')) {
                            return TextSpan(
                              text: word.replaceAll('*', '') + ' ',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            );
                          } else {
                            return TextSpan(
                              text: word + ' ',
                              style: TextStyle(
                                color: textColor,
                              ),
                            );
                          }
                        }).toList(),
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

  void _showPrivacyPolicy(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final backgroundColor = AppColors.background;
    final textColor = AppColors.primaryColor;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      localizations.privacyPolicy,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close,
                          color: textColor.withOpacity(0.6), size: 24),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      localizations.privacyPolicyContent,
                      style: TextStyle(
                        fontSize: 14,
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

  Widget _buildSettingsButton(
      String text,
      Widget icon,
      VoidCallback onPressed, {
        BorderRadius? customBorderRadius,
      }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Material(
      color: AppColors.secondaryColor,
      borderRadius: customBorderRadius ?? BorderRadius.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        borderRadius: customBorderRadius ?? BorderRadius.zero,
        splashColor: AppColors.opposedPrimaryColor.withOpacity(0.1),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: screenWidth * 0.04,
            vertical: screenHeight * 0.02,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  icon,
                  SizedBox(width: screenWidth * 0.04),
                  Text(
                    text,
                    style: GoogleFonts.roboto(
                      color: AppColors.opposedPrimaryColor,
                      fontSize: screenWidth * 0.04,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: AppColors.opposedPrimaryColor,
                size: screenWidth * 0.04,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsSection(AppLocalizations appLocalizations) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appLocalizations.settings,
          style: GoogleFonts.roboto(
            color: AppColors.opposedPrimaryColor,
            fontSize: screenWidth * 0.05,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: screenHeight * 0.01),
        Text(
          appLocalizations.accessSettingsDescription,
          style: GoogleFonts.roboto(
            color: AppColors.quinaryColor,
            fontSize: screenWidth * 0.035,
          ),
        ),
        SizedBox(height: screenHeight * 0.02),
        Column(
          children: [
            _buildSettingsButton(
              appLocalizations.help,
              Icon(
                Icons.help_outline,
                color: AppColors.opposedPrimaryColor,
                size: screenWidth * 0.05,
              ),
              _launchHelp,
              customBorderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            _buildDivider(),
            _buildSettingsButton(
              appLocalizations.shareApp,
              SvgPicture.asset(
                'assets/share.svg',
                width: screenWidth * 0.05,
                height: screenWidth * 0.05,
                color: AppColors.opposedPrimaryColor,
              ),
              _shareApp,
              customBorderRadius: BorderRadius.zero,
            ),
            _buildDivider(),
            _buildSettingsButton(
              appLocalizations.rateUs,
              SvgPicture.asset(
                'assets/star.svg',
                width: screenWidth * 0.05,
                height: screenWidth * 0.05,
                color: AppColors.opposedPrimaryColor,
              ),
              _launchRateUs,
              customBorderRadius: BorderRadius.zero,
            ),
            _buildDivider(),
            _buildSettingsButton(
              appLocalizations.termsOfUse,
              Icon(
                Icons.article,
                color: AppColors.opposedPrimaryColor,
                size: screenWidth * 0.05,
              ),
                  () => _showTermsOfUse(context),
              customBorderRadius: BorderRadius.zero,
            ),
            _buildDivider(),
            _buildSettingsButton(
              appLocalizations.privacyPolicy,
              Icon(
                Icons.privacy_tip,
                color: AppColors.opposedPrimaryColor,
                size: screenWidth * 0.05,
              ),
                  () => _showPrivacyPolicy(context),
            ),
            _buildDivider(),
            _buildSettingsButton(
              appLocalizations.copyrights,
              SvgPicture.asset(
                'assets/copyrights.svg',
                width: screenWidth * 0.05,
                height: screenWidth * 0.05,
                color: AppColors.opposedPrimaryColor,
              ),
                  () => _showComingSoonMessage(),
              customBorderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDivider() {
    final screenWidth = MediaQuery.of(context).size.width;
    return Divider(
      color: AppColors.dialogDivider,
      thickness: screenWidth * 0.002,
      height: screenWidth * 0.002,
    );
  }

  void _showComingSoonMessage() {
    final notificationService =
    Provider.of<NotificationService>(context, listen: false);

    notificationService.showNotification(
      message: AppLocalizations.of(context)!.comingSoon,
      bottomOffset: 0.01,
      duration: Duration(seconds: 1),
    );
  }

  Widget _buildCenteredButton({
    required BuildContext context,
    required String text,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Material(
      color: AppColors.secondaryColor,
      borderRadius: BorderRadius.circular(10.0),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10.0),
        splashColor: AppColors.shadow,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: screenWidth * 0.04,
            vertical: screenHeight * 0.02,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                text,
                style: GoogleFonts.roboto(
                  color: AppColors.opposedPrimaryColor,
                  fontSize: screenWidth * 0.041111,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: AppColors.opposedPrimaryColor,
                size: screenWidth * 0.04,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageSelection(AppLocalizations appLocalizations) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appLocalizations.language,
          style: GoogleFonts.roboto(
            color: AppColors.opposedPrimaryColor,
            fontSize: screenWidth * 0.05,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: screenHeight * 0.01),
        Text(
          appLocalizations.languageDescription,
          style: GoogleFonts.roboto(color: AppColors.quinaryColor, fontSize: screenWidth * 0.035),
        ),
        SizedBox(height: screenHeight * 0.02),
        Material(
          color: AppColors.secondaryColor,
          borderRadius: BorderRadius.circular(10.0),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _showLanguageSelectionDialog,
            borderRadius: BorderRadius.circular(10.0),
            splashColor: AppColors.shadow,
            child: Container(
              padding: EdgeInsets.symmetric(vertical: screenHeight * 0.015, horizontal: screenWidth * 0.04),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _selectedLanguageCode == 'en' ? appLocalizations.english : appLocalizations.turkish,
                    style: GoogleFonts.roboto(color: AppColors.opposedPrimaryColor, fontSize: screenWidth * 0.04),
                  ),
                  Icon(Icons.arrow_forward_ios, color: AppColors.opposedPrimaryColor, size: screenWidth * 0.04),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }


  Future<void> _showLanguageSelectionDialog() async {
    final appLocalizations = AppLocalizations.of(context)!;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final languages = [
      {'code': 'en', 'name': appLocalizations.english},
      {'code': 'tr', 'name': appLocalizations.turkish},
      {'code': 'zh', 'name': appLocalizations.chinese + " (Beta)"},
      {'code': 'fr', 'name': appLocalizations.french + " (Beta)"},
    ];

    String tempSelectedLanguageCode = _selectedLanguageCode;
    final double itemHeight = screenHeight * 0.07;
    final double maxListHeight = languages.length > 5 ? 5 * itemHeight : languages.length * itemHeight;

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(systemNavigationBarColor: AppColors.background),
    );
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'LanguageSelection',
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: screenWidth * 0.70,
              decoration: BoxDecoration(
                color: AppColors.dialogColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: StatefulBuilder(
                  builder: (ctx, setState) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(height: screenHeight * 0.02),
                        SvgPicture.asset(
                          'assets/language.svg',
                          width: screenWidth * 0.06,
                          height: screenWidth * 0.06,
                          color: AppColors.opposedPrimaryColor,
                        ),
                        SizedBox(height: screenHeight * 0.008),
                        Text(
                          appLocalizations.language,
                          style: TextStyle(
                            fontSize: screenWidth * 0.04,
                            fontWeight: FontWeight.bold,
                            color: AppColors.opposedPrimaryColor,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        Divider(thickness: 0.5, color: AppColors.dialogDivider),
                        Container(
                          constraints: BoxConstraints(maxHeight: maxListHeight),
                          child: ListView.builder(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            itemCount: languages.length,
                            itemBuilder: (context, index) {
                              final lang = languages[index];
                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    tempSelectedLanguageCode = lang['code']!;
                                  });
                                },
                                child: Container(
                                  color: Colors.transparent,
                                  padding: EdgeInsets.symmetric(vertical: screenHeight * 0.005),
                                  child: Row(
                                    children: [
                                      Radio<String>(
                                        value: lang['code']!,
                                        groupValue: tempSelectedLanguageCode,
                                        onChanged: (value) {
                                          setState(() {
                                            tempSelectedLanguageCode = value!;
                                          });
                                        },
                                      ),
                                      SizedBox(width: screenWidth * 0.02),
                                      Expanded(
                                        child: Text(
                                          lang['name']!,
                                          style: TextStyle(
                                            fontSize: screenWidth * 0.035,
                                            color: AppColors.opposedPrimaryColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        Divider(thickness: 0.5, color: AppColors.dialogDivider, height: 1),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            splashColor: AppColors.senaryColor.withOpacity(0.1),
                            highlightColor: AppColors.senaryColor.withOpacity(0.1),
                            onTap: () {
                              _changeLanguage(tempSelectedLanguageCode);
                              Navigator.of(context).pop();
                            },
                            child: Container(
                              height: screenHeight * 0.06,
                              alignment: Alignment.center,
                              child: Text(
                                appLocalizations.done,
                                style: TextStyle(fontSize: screenWidth * 0.035, color: AppColors.senaryColor),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    ).then((_) {
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(systemNavigationBarColor: AppColors.background),
      );
    });
  }


  Widget _buildThemeSelection(AppLocalizations appLocalizations) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appLocalizations.theme,
          style: GoogleFonts.roboto(
            color: AppColors.opposedPrimaryColor,
            fontSize: screenWidth * 0.05,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: screenHeight * 0.01),
        Text(
          appLocalizations.themeDescription,
          style: GoogleFonts.roboto(color: AppColors.quinaryColor, fontSize: screenWidth * 0.035),
        ),
        SizedBox(height: screenHeight * 0.02),
        Material(
          color: AppColors.secondaryColor,
          borderRadius: BorderRadius.circular(10.0),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              _showThemeSelectionDialog(appLocalizations);
            },
            borderRadius: BorderRadius.circular(10.0),
            splashColor: AppColors.shadow,
            child: Container(
              padding: EdgeInsets.symmetric(vertical: screenHeight * 0.015, horizontal: screenWidth * 0.04),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    AppColors.currentTheme == 'dark'
                        ? appLocalizations.dark
                        : AppColors.currentTheme == 'love'
                        ? appLocalizations.love
                        : appLocalizations.light,
                    style: GoogleFonts.roboto(color: AppColors.opposedPrimaryColor, fontSize: screenWidth * 0.04),
                  ),
                  Icon(Icons.arrow_forward_ios, color: AppColors.opposedPrimaryColor, size: screenWidth * 0.04),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showThemeSelectionDialog(AppLocalizations appLocalizations) async {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    bool loveThemeEnabled = (_hasCortexSubscription >= 1 && _hasCortexSubscription <= 6);

    final themes = [
      {'code': 'light', 'name': appLocalizations.light, 'enabled': true},
      {'code': 'dark', 'name': appLocalizations.dark, 'enabled': true},
      {'code': 'love', 'name': appLocalizations.love, 'enabled': loveThemeEnabled},
    ];

    String tempSelectedTheme =
        Provider.of<ThemeProvider>(context, listen: false).currentTheme;

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'ThemeSelection',
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: screenWidth * 0.70,
              decoration: BoxDecoration(
                color: AppColors.dialogColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: StatefulBuilder(
                  builder: (ctx, setState) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(height: screenHeight * 0.02),
                        SvgPicture.asset(
                          'assets/theme.svg',
                          width: screenWidth * 0.08,
                          height: screenWidth * 0.08,
                          color: AppColors.opposedPrimaryColor,
                        ),
                        SizedBox(height: screenHeight * 0.008),
                        Text(
                          appLocalizations.theme,
                          style: TextStyle(
                            fontSize: screenWidth * 0.04,
                            fontWeight: FontWeight.bold,
                            color: AppColors.opposedPrimaryColor,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        Divider(thickness: 0.5, color: AppColors.dialogDivider),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: screenHeight * 0.3),
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            itemCount: themes.length,
                            separatorBuilder: (context, index) =>
                                SizedBox(height: screenHeight * 0.01),
                            itemBuilder: (context, index) {
                              final theme = themes[index];
                              bool isEnabled = theme['enabled'] as bool;
                              bool isLoveTheme = (theme['code'] as String) == 'love';

                              Widget leadingWidget;
                              if (isLoveTheme && !isEnabled) {
                                leadingWidget = SvgPicture.asset(
                                  'assets/lock.svg',
                                  width: screenWidth * 0.05,
                                  height: screenWidth * 0.05,
                                  color: AppColors.opposedPrimaryColor,
                                );
                              } else {
                                leadingWidget = Radio<String>(
                                  value: theme['code'] as String,
                                  groupValue: tempSelectedTheme,
                                  onChanged: isEnabled
                                      ? (value) {
                                    setState(() {
                                      tempSelectedTheme = value!;
                                    });
                                  }
                                      : null,
                                );
                              }

                              return GestureDetector(
                                onTap: isEnabled
                                    ? () {
                                  setState(() {
                                    tempSelectedTheme = theme['code'] as String;
                                  });
                                }
                                    : null,
                                child: Container(
                                  height: screenHeight * 0.065,
                                  color: Colors.transparent,
                                  padding: EdgeInsets.only(
                                    left: screenWidth * 0.02,
                                    right: screenWidth * 0.04,
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: screenWidth * 0.1,
                                        child: Center(child: leadingWidget),
                                      ),
                                      SizedBox(width: screenWidth * 0.02),
                                      Expanded(
                                        child: Text(
                                          theme['name'] as String,
                                          style: TextStyle(
                                            fontSize: screenWidth * 0.035,
                                            color: AppColors.opposedPrimaryColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        Divider(thickness: 0.5, color: AppColors.dialogDivider, height: 1),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            splashColor: AppColors.senaryColor.withOpacity(0.1),
                            highlightColor: AppColors.senaryColor.withOpacity(0.1),
                            onTap: () {
                              if (tempSelectedTheme == 'love' && !loveThemeEnabled) return;
                              Provider.of<ThemeProvider>(context, listen: false)
                                  .changeTheme(tempSelectedTheme);
                              Navigator.of(context).pop();
                            },
                            child: Container(
                              height: screenHeight * 0.06,
                              alignment: Alignment.center,
                              child: Text(
                                appLocalizations.done,
                                style: TextStyle(
                                  fontSize: screenWidth * 0.035,
                                  color: AppColors.senaryColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }


  Widget _buildDeleteSection(AppLocalizations appLocalizations) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appLocalizations.delete,
          style: GoogleFonts.roboto(
            color: AppColors.opposedPrimaryColor,
            fontSize: screenWidth * 0.05,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: screenHeight * 0.01),
        Text(
          appLocalizations.deleteDescription,
          style: GoogleFonts.roboto(color: AppColors.quinaryColor, fontSize: screenWidth * 0.035),
        ),
        SizedBox(height: screenHeight * 0.02),
        _buildDeleteAllConversationsButton(appLocalizations),
        SizedBox(height: screenHeight * 0.015),
        _buildDeleteAccountButton(appLocalizations),
      ],
    );
  }

  Future<void> _showDeleteAllConversationsDialog(AppLocalizations appLocalizations) async {
    if (_isDialogOpen) return;
    setState(() => _isDialogOpen = true);

    final prefs = await SharedPreferences.getInstance();
    final TextEditingController confirmController = TextEditingController();
    String? confirmError;

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(systemNavigationBarColor: AppColors.background),
    );
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'DeleteAllConversations',
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(ctx).size.width * 0.8,
              decoration: BoxDecoration(
                color: AppColors.dialogColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: StatefulBuilder(
                  builder: (context, setState) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                appLocalizations.deleteAllConversationsConfirmTitle,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.opposedPrimaryColor,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                appLocalizations.deleteAllConversationsConfirmMessage,
                                style: TextStyle(
                                  color: AppColors.quinaryColor,
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ShakeWidget(
                                    controller: _deleteAccountPasswordShakeController,
                                    child: TextField(
                                      controller: confirmController,
                                      style: TextStyle(color: AppColors.opposedPrimaryColor),
                                      decoration: InputDecoration(
                                        labelText: appLocalizations.confirmWord,
                                        labelStyle: TextStyle(color: AppColors.opposedPrimaryColor),
                                        enabledBorder: OutlineInputBorder(
                                          borderSide: BorderSide(color: AppColors.dialogDivider),
                                          borderRadius: BorderRadius.circular(10.0),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderSide: BorderSide(color: AppColors.opposedPrimaryColor),
                                          borderRadius: BorderRadius.circular(10.0),
                                        ),
                                      ),
                                    ),
                                  ),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    child: confirmError != null
                                        ? Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text(
                                        confirmError!,
                                        style: const TextStyle(color: Colors.red),
                                        key: ValueKey(confirmError),
                                      ),
                                    )
                                        : const SizedBox.shrink(key: ValueKey("empty")),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Divider(color: AppColors.dialogDivider, thickness: 0.5, height: 1),
                        IntrinsicHeight(
                          child: Row(
                            children: [
                              Expanded(
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    splashColor: AppColors.senaryColor.withOpacity(0.1),
                                    highlightColor: AppColors.senaryColor.withOpacity(0.1),
                                    onTap: () => Navigator.of(ctx).pop(),
                                    child: Container(
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      child: Text(
                                        appLocalizations.cancel,
                                        style: const TextStyle(color: Colors.blue, fontSize: 16),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              VerticalDivider(width: 1, thickness: 0.5, color: AppColors.dialogDivider),
                              Expanded(
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    splashColor: Colors.red.withOpacity(0.3),
                                    highlightColor: Colors.red.withOpacity(0.1),
                                    onTap: () async {
                                      if (confirmController.text.trim() != "VERTEX") {
                                        setState(() {
                                          confirmError = appLocalizations.confirmWordError;
                                        });
                                        _deleteAccountPasswordShakeController.forward(from: 0);
                                        return;
                                      }
                                      Navigator.of(ctx).pop();
                                      final convList = prefs.getStringList('conversations') ?? [];
                                      for (final conv in convList) {
                                        final parts = conv.split('|');
                                        if (parts.isNotEmpty) {
                                          final conversationID = parts[0];
                                          await prefs.remove('is_starred_$conversationID');
                                          await prefs.remove(conversationID);
                                        }
                                      }
                                      await prefs.remove('conversations');
                                      _notificationService.showNotification(
                                        message: appLocalizations.allConversationsDeleted,
                                        isSuccess: true,
                                        bottomOffset: 0.02,
                                      );
                                    },
                                    child: Container(
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      child: Text(
                                        appLocalizations.deleteAll,
                                        style: const TextStyle(color: Colors.red, fontSize: 16),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    ).then((_) {
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(systemNavigationBarColor: AppColors.background),
      );
      setState(() => _isDialogOpen = false);
    });
  }

  Widget _buildDeleteAllConversationsButton(AppLocalizations appLocalizations) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Material(
      color: AppColors.warning,
      borderRadius: BorderRadius.circular(10.0),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _showDeleteAllConversationsDialog(appLocalizations);
        },
        borderRadius: BorderRadius.circular(10.0),
        splashColor: AppColors.shadow,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.04, vertical: screenHeight * 0.02),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                appLocalizations.deleteAllConversationsButton,
                style: GoogleFonts.roboto(
                  color: Colors.white,
                  fontSize: screenWidth * 0.04,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: Colors.white, size: screenWidth * 0.04),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeleteAccountButton(AppLocalizations appLocalizations) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Material(
      color: AppColors.warning,
      borderRadius: BorderRadius.circular(10.0),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _showDeleteAccountDialog(appLocalizations);
        },
        borderRadius: BorderRadius.circular(10.0),
        splashColor: AppColors.shadow,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.04, vertical: screenHeight * 0.02),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                appLocalizations.deleteAccountButton,
                style: GoogleFonts.roboto(
                  color: Colors.white,
                  fontSize: screenWidth * 0.04,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: Colors.white, size: screenWidth * 0.04),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDeleteAccountDialog(AppLocalizations appLocalizations) async {
    if (_isDialogOpen) return;
    setState(() => _isDialogOpen = true);

    final TextEditingController passwordController = TextEditingController();
    String? passwordError;

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(systemNavigationBarColor: AppColors.background),
    );
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'DeleteAccount',
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.8,
              decoration: BoxDecoration(
                color: AppColors.dialogColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: StatefulBuilder(
                  builder: (context, setState) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              Text(
                                appLocalizations.confirmDeleteAccount,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.opposedPrimaryColor,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                appLocalizations.enterPasswordToDelete,
                                style: TextStyle(
                                  color: AppColors.quinaryColor,
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ShakeWidget(
                                    controller: _deleteAccountPasswordShakeController,
                                    child: TextField(
                                      controller: passwordController,
                                      obscureText: true,
                                      style: TextStyle(color: AppColors.opposedPrimaryColor),
                                      decoration: InputDecoration(
                                        labelText: appLocalizations.password,
                                        labelStyle: TextStyle(color: AppColors.opposedPrimaryColor),
                                        enabledBorder: OutlineInputBorder(
                                          borderSide: BorderSide(color: AppColors.dialogDivider),
                                          borderRadius: BorderRadius.circular(10.0),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderSide: BorderSide(color: AppColors.opposedPrimaryColor),
                                          borderRadius: BorderRadius.circular(10.0),
                                        ),
                                      ),
                                    ),
                                  ),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    child: passwordError != null
                                        ? Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text(
                                        passwordError!,
                                        style: const TextStyle(color: Colors.red),
                                        key: ValueKey(passwordError),
                                      ),
                                    )
                                        : const SizedBox.shrink(key: ValueKey("empty")),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Divider(color: AppColors.dialogDivider, thickness: 0.5, height: 1),
                        IntrinsicHeight(
                          child: Row(
                            children: [
                              Expanded(
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    splashColor: AppColors.senaryColor.withOpacity(0.1),
                                    highlightColor: AppColors.senaryColor.withOpacity(0.1),
                                    onTap: () => Navigator.of(context).pop(),
                                    child: Container(
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      child: Text(
                                        appLocalizations.cancel,
                                        style: const TextStyle(color: Colors.blue, fontSize: 16),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              VerticalDivider(width: 1, thickness: 0.5, color: AppColors.dialogDivider),
                              Expanded(
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    splashColor: Colors.red.withOpacity(0.3),
                                    highlightColor: Colors.red.withOpacity(0.1),
                                    onTap: () async {
                                      final password = passwordController.text.trim();
                                      if (password.isEmpty) {
                                        setState(() {
                                          passwordError = appLocalizations.passwordRequired;
                                        });
                                        _deleteAccountPasswordShakeController.forward(from: 0);
                                        return;
                                      }
                                      final user = FirebaseAuth.instance.currentUser;
                                      if (user == null) {
                                        Navigator.of(context).pop();
                                        return;
                                      }
                                      try {
                                        final credential = EmailAuthProvider.credential(
                                          email: user.email!,
                                          password: password,
                                        );
                                        await user.reauthenticateWithCredential(credential);
                                        final batch = FirebaseFirestore.instance.batch();
                                        final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
                                        batch.delete(userDocRef);

                                        if (_userData?['username'] != null) {
                                          final username = _userData!['username'].toString().toLowerCase();
                                          final usernameDocRef = FirebaseFirestore.instance.collection('usernames').doc(username);
                                          batch.delete(usernameDocRef);
                                        }
                                        await batch.commit();
                                        await user.delete();
                                        await FirebaseAuth.instance.signOut();
                                        if (!mounted) return;
                                        Navigator.of(context).pushReplacement(
                                          MaterialPageRoute(builder: (context) => const LoginScreen()),
                                        );
                                      } catch (e) {
                                        debugPrint("Error deleting account: $e");
                                        setState(() {
                                          passwordError = appLocalizations.wrongPassword;
                                        });
                                        _deleteAccountPasswordShakeController.forward(from: 0);
                                      }
                                    },
                                    child: Container(
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      child: Text(
                                        appLocalizations.delete,
                                        style: const TextStyle(color: Colors.red, fontSize: 16),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    ).then((_) {
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(systemNavigationBarColor: AppColors.background),
      );
      setState(() => _isDialogOpen = false);
    });
  }

  void _showEditProfileDialog(User user) {
    if (_isDialogOpen) return;
    setState(() => _isDialogOpen = true);

    final appLocalizations = AppLocalizations.of(context)!;
    final TextEditingController nameController = TextEditingController(
      text: _userData != null && _userData!['username'] != null ? _userData!['username'] : '',
    );
    String? editUsernameError;

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(systemNavigationBarColor: AppColors.background),
    );
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'EditProfile',
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(ctx).size.width * 0.8,
              decoration: BoxDecoration(
                color: AppColors.dialogColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: StatefulBuilder(
                  builder: (ctx, setState) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              Text(
                                appLocalizations.editProfile,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.opposedPrimaryColor,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ShakeWidget(
                                    controller: _editProfileShakeController,
                                    child: TextField(
                                      controller: nameController,
                                      maxLength: 16,
                                      style: TextStyle(color: AppColors.opposedPrimaryColor),
                                      decoration: InputDecoration(
                                        labelText: appLocalizations.username,
                                        labelStyle: TextStyle(color: AppColors.opposedPrimaryColor),
                                        enabledBorder: OutlineInputBorder(
                                          borderSide: BorderSide(color: AppColors.dialogDivider),
                                          borderRadius: BorderRadius.circular(10.0),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderSide: BorderSide(color: AppColors.opposedPrimaryColor),
                                          borderRadius: BorderRadius.circular(10.0),
                                        ),
                                        counterText: '',
                                      ),
                                    ),
                                  ),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    child: editUsernameError != null
                                        ? Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text(
                                        editUsernameError!,
                                        style: const TextStyle(color: Colors.red),
                                        key: ValueKey(editUsernameError),
                                      ),
                                    )
                                        : const SizedBox.shrink(key: ValueKey("empty")),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Divider(color: AppColors.dialogDivider, thickness: 0.5, height: 1),
                        IntrinsicHeight(
                          child: Row(
                            children: [
                              Expanded(
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    splashColor: AppColors.senaryColor.withOpacity(0.1),
                                    highlightColor: AppColors.senaryColor.withOpacity(0.1),
                                    onTap: () => Navigator.of(ctx).pop(),
                                    child: Container(
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      child: Text(
                                        appLocalizations.cancel,
                                        style: const TextStyle(color: Colors.blue, fontSize: 16),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              VerticalDivider(width: 1, thickness: 0.5, color: AppColors.dialogDivider),
                              Expanded(
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    splashColor: AppColors.shadow,
                                    highlightColor: AppColors.shadow,
                                    onTap: () async {
                                      String newName = nameController.text.trim();
                                      if (newName.isEmpty) {
                                        setState(() {
                                          editUsernameError = appLocalizations.invalidUsername;
                                        });
                                        _editProfileShakeController.forward(from: 0);
                                        return;
                                      }
                                      if (!_usernameRegExp.hasMatch(newName)) {
                                        setState(() {
                                          editUsernameError = appLocalizations.invalidUsernameCharacters;
                                        });
                                        _editProfileShakeController.forward(from: 0);
                                        return;
                                      }
                                      try {
                                        bool isAvailable = await _isUsernameAvailable(newName);
                                        if (!isAvailable) {
                                          setState(() {
                                            editUsernameError = appLocalizations.usernameTaken;
                                          });
                                          _editProfileShakeController.forward(from: 0);
                                          return;
                                        }
                                        final batch = FirebaseFirestore.instance.batch();
                                        final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
                                        if (_userData != null && _userData!['username'] != null) {
                                          final oldUsernameDocRef = FirebaseFirestore.instance
                                              .collection('usernames')
                                              .doc(_userData!['username']);
                                          batch.delete(oldUsernameDocRef);
                                        }
                                        final newUsernameDocRef = FirebaseFirestore.instance
                                            .collection('usernames')
                                            .doc(newName.toLowerCase());
                                        batch.set(newUsernameDocRef, {'userId': user.uid});
                                        batch.update(userDocRef, {'username': newName.toLowerCase()});
                                        await batch.commit();
                                        await _fetchUserData();
                                        Navigator.of(ctx).pop();
                                      } catch (e) {
                                        debugPrint("Error updating username: $e");
                                        Navigator.of(ctx).pop();
                                      }
                                    },
                                    child: Container(
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      child: Text(
                                        appLocalizations.save,
                                        style: const TextStyle(color: Colors.blue, fontSize: 16),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    ).then((_) {
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(systemNavigationBarColor: AppColors.background),
      );
      setState(() => _isDialogOpen = false);
    });
  }

  /// Username'in müsaitliğini kontrol eder
  Future<bool> _isUsernameAvailable(String username) async {
    final result = await FirebaseFirestore.instance
        .collection('usernames')
        .doc(username.toLowerCase())
        .get();
    return !result.exists;
  }

  void _showChangePasswordDialog() {
    if (_isDialogOpen) return;
    setState(() => _isDialogOpen = true);

    final appLocalizations = AppLocalizations.of(context)!;
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    String? oldPasswordError;
    String? newPasswordError;
    String? confirmPasswordError;
    bool isLoading = false;

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(systemNavigationBarColor: AppColors.background),
    );
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'ChangePassword',
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(ctx).size.width * 0.8,
              decoration: BoxDecoration(
                color: AppColors.dialogColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: StatefulBuilder(
                  builder: (ctx, setState) {
                    Future<void> attemptChangePassword() async {
                      final oldPassword = oldPasswordController.text.trim();
                      final newPassword = newPasswordController.text.trim();
                      final confirmPassword = confirmPasswordController.text.trim();

                      if (oldPassword.isEmpty) {
                        setState(() {
                          oldPasswordError = appLocalizations.invalidPassword;
                        });
                        _oldPasswordShakeController.forward(from: 0);
                        return;
                      }
                      if (newPassword.isEmpty || newPassword.length < 6) {
                        setState(() {
                          newPasswordError = appLocalizations.invalidPassword;
                        });
                        _newPasswordShakeController.forward(from: 0);
                        return;
                      }
                      if (confirmPassword != newPassword) {
                        setState(() {
                          confirmPasswordError = appLocalizations.passwordsDoNotMatch;
                        });
                        _confirmPasswordShakeController.forward(from: 0);
                        return;
                      }

                      setState(() => isLoading = true);
                      try {
                        final user = FirebaseAuth.instance.currentUser;
                        if (user == null) {
                          Navigator.of(ctx).pop();
                          return;
                        }
                        final credential = EmailAuthProvider.credential(
                          email: user.email!,
                          password: oldPassword,
                        );
                        await user.reauthenticateWithCredential(credential);
                        await user.updatePassword(newPassword);
                        setState(() => isLoading = false);
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(appLocalizations.passwordUpdated), backgroundColor: Colors.green),
                        );
                      } on FirebaseAuthException catch (e) {
                        setState(() => isLoading = false);
                        if (e.code == 'wrong-password') {
                          setState(() {
                            oldPasswordError = appLocalizations.wrongPassword;
                          });
                          _oldPasswordShakeController.forward(from: 0);
                        } else if (e.code == 'weak-password') {
                          setState(() {
                            newPasswordError = appLocalizations.weakPassword;
                          });
                          _newPasswordShakeController.forward(from: 0);
                        } else {
                          setState(() {
                            oldPasswordError = e.message ?? appLocalizations.authError;
                          });
                          _oldPasswordShakeController.forward(from: 0);
                        }
                      } catch (e) {
                        setState(() => isLoading = false);
                        setState(() {
                          oldPasswordError = appLocalizations.updateFailed;
                        });
                        _oldPasswordShakeController.forward(from: 0);
                      }
                    }

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              Text(
                                appLocalizations.changePassword,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.opposedPrimaryColor,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ShakeWidget(
                                    controller: _oldPasswordShakeController,
                                    child: TextField(
                                      controller: oldPasswordController,
                                      obscureText: true,
                                      decoration: InputDecoration(
                                        labelText: appLocalizations.oldPassword,
                                        enabledBorder: OutlineInputBorder(
                                          borderSide: BorderSide(color: AppColors.dialogDivider),
                                          borderRadius: BorderRadius.circular(10.0),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderSide: BorderSide(color: AppColors.opposedPrimaryColor),
                                          borderRadius: BorderRadius.circular(10.0),
                                        ),
                                      ),
                                    ),
                                  ),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    child: oldPasswordError != null
                                        ? Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text(
                                        oldPasswordError!,
                                        style: const TextStyle(color: Colors.red),
                                        key: ValueKey(oldPasswordError),
                                      ),
                                    )
                                        : const SizedBox.shrink(key: ValueKey("empty")),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ShakeWidget(
                                    controller: _newPasswordShakeController,
                                    child: TextField(
                                      controller: newPasswordController,
                                      obscureText: true,
                                      decoration: InputDecoration(
                                        labelText: appLocalizations.newPassword,
                                        enabledBorder: OutlineInputBorder(
                                          borderSide: BorderSide(color: AppColors.dialogDivider),
                                          borderRadius: BorderRadius.circular(10.0),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderSide: BorderSide(color: AppColors.opposedPrimaryColor),
                                          borderRadius: BorderRadius.circular(10.0),
                                        ),
                                      ),
                                    ),
                                  ),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    child: newPasswordError != null
                                        ? Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text(
                                        newPasswordError!,
                                        style: const TextStyle(color: Colors.red),
                                        key: ValueKey(newPasswordError),
                                      ),
                                    )
                                        : const SizedBox.shrink(key: ValueKey("empty")),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ShakeWidget(
                                    controller: _confirmPasswordShakeController,
                                    child: TextField(
                                      controller: confirmPasswordController,
                                      obscureText: true,
                                      decoration: InputDecoration(
                                        labelText: appLocalizations.confirmPassword,
                                        enabledBorder: OutlineInputBorder(
                                          borderSide: BorderSide(color: AppColors.dialogDivider),
                                          borderRadius: BorderRadius.circular(10.0),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderSide: BorderSide(color: AppColors.opposedPrimaryColor),
                                          borderRadius: BorderRadius.circular(10.0),
                                        ),
                                      ),
                                    ),
                                  ),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    child: confirmPasswordError != null
                                        ? Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text(
                                        confirmPasswordError!,
                                        style: const TextStyle(color: Colors.red),
                                        key: ValueKey(confirmPasswordError),
                                      ),
                                    )
                                        : const SizedBox.shrink(key: ValueKey("empty")),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Divider(color: AppColors.dialogDivider, thickness: 0.5, height: 1),
                        IntrinsicHeight(
                          child: Row(
                            children: [
                              Expanded(
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    splashColor: AppColors.senaryColor.withOpacity(0.1),
                                    highlightColor: AppColors.senaryColor.withOpacity(0.1),
                                    onTap: isLoading ? null : () => Navigator.of(ctx).pop(),
                                    child: Container(
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      child: Text(
                                        appLocalizations.cancel,
                                        style: const TextStyle(color: Colors.blue, fontSize: 16),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              VerticalDivider(width: 1, thickness: 0.5, color: AppColors.dialogDivider),
                              Expanded(
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    splashColor: Colors.red.withOpacity(0.3),
                                    highlightColor: Colors.red.withOpacity(0.1),
                                    onTap: isLoading ? null : attemptChangePassword,
                                    child: Container(
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      child: isLoading
                                          ? SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.0,
                                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.opposedPrimaryColor),
                                        ),
                                      )
                                          : Text(
                                        appLocalizations.save,
                                        style: const TextStyle(color: Colors.red, fontSize: 16),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    ).then((_) {
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(systemNavigationBarColor: AppColors.background),
      );
      setState(() => _isDialogOpen = false);
    });
  }

  String _getSubscriptionLabel(int subscriptionLevel) {
    switch (subscriptionLevel) {
      case 1:
        return "Plus";
      case 2:
        return "Pro";
      case 3:
        return "Ultra";
      case 4:
        return "Plus";
      case 5:
        return "Pro";
      case 6:
        return "Ultra";
      default:
        return "";
    }
  }

  Widget _buildBadge(IconData icon, String label) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    double iconSize = screenWidth * 0.05;
    double fontSize = screenWidth * 0.035;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.03,
        vertical: screenHeight * 0.008,
      ),
      decoration: BoxDecoration(
        color: AppColors.badgeBackground,
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: AppColors.opposedPrimaryColor,
            size: iconSize,
          ),
          SizedBox(width: screenWidth * 0.02),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: AppColors.opposedPrimaryColor,
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// AnimatedBorderPainter artık AppColors kullanıyor:
class AnimatedBorderPainter extends CustomPainter {
  final double animationValue;

  AnimatedBorderPainter({
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    double strokeWidth = 2.0;
    Rect rect = Offset.zero & size;
    double radius = size.width / 2;

    Paint paint = Paint()
      ..shader = SweepGradient(
        colors: AppColors.animatedBorderGradientColors,
        startAngle: 0.0,
        endAngle: 2 * pi,
        transform: GradientRotation(animationValue),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(Offset(radius, radius), radius - strokeWidth / 2, paint);
  }

  @override
  bool shouldRepaint(covariant AnimatedBorderPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}

// SkeletonLoaderShimmer artık AppColors üzerinden shimmer renklerini kullanıyor:
class SkeletonLoaderShimmer extends StatelessWidget {
  const SkeletonLoaderShimmer({Key? key}) : super(key: key);

  Widget _buildCircle(double size) {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.skeletonContainer,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  Widget _buildSkeletonSection({
    required double width,
    required double height,
    double radius = 8.0,
  }) {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.skeletonContainer,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }

  Widget _buildSkeletonBadge(double iconSize, double textWidth, double textHeight) {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: iconSize * 0.6,
          vertical: iconSize * 0.3,
        ),
        decoration: BoxDecoration(
          color: AppColors.skeletonContainer,
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Row(
          children: [
            _buildSkeletonSection(
              width: iconSize,
              height: iconSize,
              radius: iconSize / 2,
            ),
            SizedBox(width: iconSize * 0.4),
            _buildSkeletonSection(
              width: textWidth,
              height: textHeight,
              radius: textHeight / 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonButton(double width, double height) {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: Container(
        width: width,
        height: height,
        margin: EdgeInsets.symmetric(vertical: height * 0.16),
        decoration: BoxDecoration(
          color: AppColors.skeletonContainer,
          borderRadius: BorderRadius.circular(12.0),
        ),
      ),
    );
  }

  Widget _buildSkeletonSettingsButton({
    required double iconSize,
    required double textWidth,
    required double textHeight,
    required double arrowSize,
    required double containerHeight,
    required double horizontalPadding,
    required double verticalPadding,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: () {},
          child: Shimmer.fromColors(
            baseColor: AppColors.shimmerBase,
            highlightColor: AppColors.shimmerHighlight,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: verticalPadding,
              ),
              decoration: BoxDecoration(
                color: AppColors.skeletonContainer,
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      _buildSkeletonSection(width: iconSize, height: iconSize),
                      SizedBox(width: horizontalPadding),
                      _buildSkeletonSection(width: textWidth, height: textHeight),
                    ],
                  ),
                  _buildSkeletonSection(width: arrowSize, height: arrowSize),
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: verticalPadding * 0.5),
        Divider(
          color: AppColors.dialogDivider,
          thickness: 1,
          height: 1,
        ),
        SizedBox(height: verticalPadding * 0.5),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final themeProvider = Provider.of<ThemeProvider>(context, listen: true);
    final double circleSize = screenWidth * 0.25;
    final double smallSpacing = screenHeight * 0.01;
    final double medSpacing = screenHeight * 0.02;
    final double largeSpacing = screenHeight * 0.03;

    return ListView(
      padding: EdgeInsets.all(screenWidth * 0.04),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCircle(circleSize),
            SizedBox(width: screenWidth * 0.04),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSkeletonSection(
                    width: screenWidth * 0.4,
                    height: screenHeight * 0.03,
                  ),
                  SizedBox(height: screenHeight * 0.01),
                  _buildSkeletonSection(
                    width: screenWidth * 0.5,
                    height: screenHeight * 0.02,
                  ),
                  SizedBox(height: screenHeight * 0.015),
                  Row(
                    children: [
                      _buildSkeletonBadge(
                        screenWidth * 0.05,
                        screenWidth * 0.1,
                        screenHeight * 0.02,
                      ),
                      SizedBox(width: screenWidth * 0.02),
                      _buildSkeletonBadge(
                        screenWidth * 0.05,
                        screenWidth * 0.1,
                        screenHeight * 0.02,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: largeSpacing),
        _buildSkeletonSection(
          width: screenWidth * 0.2,
          height: screenHeight * 0.03,
        ),
        SizedBox(height: smallSpacing),
        _buildSkeletonSection(
          width: screenWidth * 0.5,
          height: screenHeight * 0.02,
        ),
        SizedBox(height: smallSpacing),
        _buildSkeletonSection(
          width: screenWidth * 0.4,
          height: screenHeight * 0.02,
        ),
        SizedBox(height: medSpacing),
        _buildSkeletonButton(screenWidth, screenHeight * 0.06),
        _buildSkeletonButton(screenWidth, screenHeight * 0.06),
        _buildSkeletonButton(screenWidth, screenHeight * 0.06),
        SizedBox(height: largeSpacing),
        _buildSkeletonSection(
          width: screenWidth * 0.2,
          height: screenHeight * 0.03,
        ),
        SizedBox(height: smallSpacing),
        _buildSkeletonSection(
          width: screenWidth * 0.5,
          height: screenHeight * 0.02,
        ),
        SizedBox(height: smallSpacing),
        _buildSkeletonSection(
          width: screenWidth * 0.4,
          height: screenHeight * 0.02,
        ),
        SizedBox(height: smallSpacing),
        _buildSkeletonButton(screenWidth, screenHeight * 0.06),
        SizedBox(height: medSpacing),
        _buildSkeletonSection(
          width: screenWidth * 0.2,
          height: screenHeight * 0.03,
        ),
        SizedBox(height: smallSpacing),
        _buildSkeletonSection(
          width: screenWidth * 0.5,
          height: screenHeight * 0.02,
        ),
        SizedBox(height: smallSpacing),
        _buildSkeletonSection(
          width: screenWidth * 0.4,
          height: screenHeight * 0.02,
        ),
        SizedBox(height: smallSpacing),
        _buildSkeletonSection(
          width: screenWidth * 0.3,
          height: screenHeight * 0.02,
        ),
        SizedBox(height: medSpacing),
        _buildSkeletonButton(screenWidth, screenHeight * 0.06),
        SizedBox(height: largeSpacing),
        _buildSkeletonSection(
          width: screenWidth * 0.6,
          height: screenHeight * 0.03,
        ),
        SizedBox(height: smallSpacing),
        _buildSkeletonSection(
          width: screenWidth * 0.4,
          height: screenHeight * 0.02,
        ),
        SizedBox(height: smallSpacing),
        _buildSkeletonSection(
          width: screenWidth * 0.4,
          height: screenHeight * 0.02,
        ),
        SizedBox(height: medSpacing),
        _buildSkeletonSettingsButton(
          iconSize: screenWidth * 0.05,
          textWidth: screenWidth * 0.3,
          textHeight: screenHeight * 0.02,
          arrowSize: screenWidth * 0.03,
          containerHeight: screenHeight * 0.06,
          horizontalPadding: screenWidth * 0.04,
          verticalPadding: screenHeight * 0.01,
        ),
        _buildSkeletonSettingsButton(
          iconSize: screenWidth * 0.05,
          textWidth: screenWidth * 0.3,
          textHeight: screenHeight * 0.02,
          arrowSize: screenWidth * 0.03,
          containerHeight: screenHeight * 0.06,
          horizontalPadding: screenWidth * 0.04,
          verticalPadding: screenHeight * 0.01,
        ),
        _buildSkeletonSettingsButton(
          iconSize: screenWidth * 0.05,
          textWidth: screenWidth * 0.3,
          textHeight: screenHeight * 0.02,
          arrowSize: screenWidth * 0.03,
          containerHeight: screenHeight * 0.06,
          horizontalPadding: screenWidth * 0.04,
          verticalPadding: screenHeight * 0.01,
        ),
        _buildSkeletonSettingsButton(
          iconSize: screenWidth * 0.05,
          textWidth: screenWidth * 0.3,
          textHeight: screenHeight * 0.02,
          arrowSize: screenWidth * 0.03,
          containerHeight: screenHeight * 0.06,
          horizontalPadding: screenWidth * 0.04,
          verticalPadding: screenHeight * 0.01,
        ),
        _buildSkeletonSettingsButton(
          iconSize: screenWidth * 0.05,
          textWidth: screenWidth * 0.3,
          textHeight: screenHeight * 0.02,
          arrowSize: screenWidth * 0.03,
          containerHeight: screenHeight * 0.06,
          horizontalPadding: screenWidth * 0.04,
          verticalPadding: screenHeight * 0.01,
        ),
        _buildSkeletonSettingsButton(
          iconSize: screenWidth * 0.05,
          textWidth: screenWidth * 0.3,
          textHeight: screenHeight * 0.02,
          arrowSize: screenWidth * 0.03,
          containerHeight: screenHeight * 0.06,
          horizontalPadding: screenWidth * 0.04,
          verticalPadding: screenHeight * 0.01,
        ),
      ],
    );
  }
}
