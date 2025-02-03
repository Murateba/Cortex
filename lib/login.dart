// login.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
// <-- SVG için
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:email_validator/email_validator.dart';
import 'dart:async';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'dart:math'; // Rastgele açı için

import 'main.dart';
import 'theme.dart';
import 'notifications.dart';

/// Basit bir “shake” animasyonu için kullanılan widget.
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

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

enum AuthMode { login, register }

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // İki ayrı form
  final _loginFormKey = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();

  // Animasyonlu geçiş için
  AuthMode _authMode = AuthMode.login;

  // Ortak alanlar
  String _email = '';
  String _password = '';
  String _confirmPassword = '';
  String _username = '';

  // Hata mesajları
  String? _loginEmailError;
  String? _loginPasswordError;

  String? _registerUsernameError;
  String? _registerEmailError;
  String? _registerPasswordError;
  String? _registerConfirmPasswordError;

  bool _isLoading = false;
  bool _rememberMe = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  // Animasyon Controller’larımız
  late AnimationController _mainAnimationController;
  late Animation<double> _animation;

  // Shake animasyonları
  late AnimationController _loginEmailShakeController;
  late AnimationController _loginPasswordShakeController;

  late AnimationController _registerUsernameShakeController;
  late AnimationController _registerEmailShakeController;
  late AnimationController _registerPasswordShakeController;
  late AnimationController _registerConfirmPasswordShakeController;

  late NotificationService _notificationService;

  bool _agreeToTerms = false;

  final TextEditingController _loginEmailController = TextEditingController();
  final TextEditingController _registerEmailController = TextEditingController();

  // Kullanıcı adı için regex
  final RegExp _usernameRegExp = RegExp(
    r'^[abcçdefgğhıijklmnoöprsştuüvyzxqw0-9\.\-_]{3,16}$',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificationService =
          Provider.of<NotificationService>(context, listen: false);
    });

    // Main animation controller
    _mainAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _mainAnimationController,
      curve: Curves.easeInOut,
    );

    // Shake animasyonları
    const shakeDuration = Duration(milliseconds: 500);
    _loginEmailShakeController =
        AnimationController(vsync: this, duration: shakeDuration);
    _loginPasswordShakeController =
        AnimationController(vsync: this, duration: shakeDuration);

    _registerUsernameShakeController =
        AnimationController(vsync: this, duration: shakeDuration);
    _registerEmailShakeController =
        AnimationController(vsync: this, duration: shakeDuration);
    _registerPasswordShakeController =
        AnimationController(vsync: this, duration: shakeDuration);
    _registerConfirmPasswordShakeController =
        AnimationController(vsync: this, duration: shakeDuration);
  }

  @override
  void dispose() {
    _loginEmailController.dispose();
    _registerEmailController.dispose();
    _mainAnimationController.dispose();
    // Shake controller’ları
    _loginEmailShakeController.dispose();
    _loginPasswordShakeController.dispose();
    _registerUsernameShakeController.dispose();
    _registerEmailShakeController.dispose();
    _registerPasswordShakeController.dispose();
    _registerConfirmPasswordShakeController.dispose();
    super.dispose();
  }

  Future<void> _saveUserEmail() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setBool('remember_me', true);
      await prefs.setString('email', _email);
    } else {
      await prefs.setBool('remember_me', false);
      await prefs.remove('email');
    }
  }

  Future<bool> _isUsernameAvailable(String username) async {
    // Firestore'a yazmak için önce kontrol
    final doc = await FirebaseFirestore.instance
        .collection('usernames')
        .doc(username.toLowerCase())
        .get();
    return !doc.exists;
  }

  void _switchAuthMode() {
    setState(() {
      // Mod değişirken mevcut form alanlarını resetleyelim.
      _loginFormKey.currentState?.reset();
      _registerFormKey.currentState?.reset();
      _loginEmailController.clear();
      _registerEmailController.clear();
      _loginEmailError = null;
      _loginPasswordError = null;
      _registerUsernameError = null;
      _registerEmailError = null;
      _registerPasswordError = null;
      _registerConfirmPasswordError = null;

      if (_authMode == AuthMode.login) {
        _authMode = AuthMode.register;
        _mainAnimationController.forward();
      } else {
        _authMode = AuthMode.login;
        _mainAnimationController.reverse();
      }
    });
  }

  void _showComingSoonMessage() {
    final notificationService =
    Provider.of<NotificationService>(context, listen: false);
    final isDarkTheme =
        Provider
            .of<ThemeProvider>(context, listen: false)
            .isDarkTheme;

    notificationService.showNotification(
      message: AppLocalizations.of(context)!.comingSoon,
      bottomOffset: 0.02,
      duration: Duration(seconds: 1),
    );
  }

  Future<void> _submit() async {
    final appLocalizations = AppLocalizations.of(context)!;

    FocusScope.of(context).unfocus();

    bool hasConnection = await InternetConnection().hasInternetAccess;
    if (!hasConnection) {
      _notificationService.showNotification(
        message: appLocalizations.noInternetConnection,
        bottomOffset: 0.02,
        isSuccess: false,
      );
      return;
    }

    final form = _authMode == AuthMode.login
        ? _loginFormKey.currentState
        : _registerFormKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    form.save();

    // Register modunda şifreler eşleşmiyor ise hata verelim.
    if (_authMode == AuthMode.register && _password != _confirmPassword) {
      setState(() {
        _registerConfirmPasswordError = appLocalizations.passwordsDoNotMatch;
      });
      _registerConfirmPasswordShakeController.forward(from: 0);
      _registerFormKey.currentState!.validate();
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (_authMode == AuthMode.login) {
        // Giriş yapılıyor
        final userCredential = await _auth.signInWithEmailAndPassword(
          email: _email,
          password: _password,
        );
        final user = userCredential.user;
        if (user == null) {
          throw FirebaseAuthException(
            code: 'unknown',
            message: appLocalizations.authError,
          );
        }

        await user.reload();
        if (!user.emailVerified) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) =>
                  EmailVerificationScreen(
                    email: _email,
                    username: _username,
                    userId: user.uid,
                    password: _password,
                  ),
            ),
          );
          return;
        }

        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (!userDoc.exists) {
          throw Exception(appLocalizations.authError);
        }

        await _saveUserEmail();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => mainScreen),
        );
      } else {
        final isAvailable = await _isUsernameAvailable(_username);
        if (!isAvailable) {
          setState(() {
            _registerUsernameError = appLocalizations.usernameTaken;
            _isLoading = false;
          });
          _registerUsernameShakeController.forward(from: 0);
          _registerFormKey.currentState!.validate();
          return;
        }

        final userCredential = await _auth.createUserWithEmailAndPassword(
          email: _email,
          password: _password,
        );

        try {
          await FirebaseFirestore.instance
              .collection('usernames')
              .doc(_username.toLowerCase())
              .set({'userId': userCredential.user!.uid});

          await FirebaseFirestore.instance
              .collection('users')
              .doc(userCredential.user!.uid)
              .set({
            'username': _username.toLowerCase(),
            'email': _email,
            'hasCortexSubscription': 0,
            'alphaUser': true,
            'createdAt': FieldValue.serverTimestamp(),
            'verifyAttempts': 0,
          });
        } catch (e) {
          debugPrint('Firestore yazma hatası: $e');
        }

        // Doğrulama maili gönderiyoruz.
        await userCredential.user?.sendEmailVerification();

        // Kayıt işlemi tamamlandıktan sonra EmailVerificationScreen'e yönlendiriyoruz.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) =>
                EmailVerificationScreen(
                  email: _email,
                  username: _username,
                  userId: userCredential.user!.uid,
                  password: _password,
                ),
          ),
        );
      }
    } on FirebaseAuthException catch (error) {
      // Hata durumlarında ilgili hata mesajlarını ve shake animasyonlarını tetikleyebilirsiniz.
      final code = error.code;
      switch (code) {
        case 'user-not-found':
        case 'invalid-email':
          setState(() {
            if (_authMode == AuthMode.login) {
              _loginEmailError = appLocalizations.userNotFound;
              _loginFormKey.currentState!.validate();
              _loginEmailShakeController.forward(from: 0);
            } else {
              _registerEmailError = appLocalizations.invalidEmail;
              _registerFormKey.currentState!.validate();
              _registerEmailShakeController.forward(from: 0);
            }
          });
          break;
        case 'wrong-password':
          setState(() {
            if (_authMode == AuthMode.login) {
              _loginPasswordError = appLocalizations.wrongPassword;
              _loginFormKey.currentState!.validate();
              _loginPasswordShakeController.forward(from: 0);
            } else {
              _registerPasswordError = appLocalizations.invalidPassword;
              _registerFormKey.currentState!.validate();
              _registerPasswordShakeController.forward(from: 0);
            }
          });
          break;
        case 'email-already-in-use':
          setState(() {
            _registerEmailError = appLocalizations.emailAlreadyInUse;
          });
          _registerEmailShakeController.forward(from: 0);
          _registerFormKey.currentState!.validate();
          break;
        case 'weak-password':
          setState(() {
            _registerPasswordError = appLocalizations.weakPassword;
          });
          _registerPasswordShakeController.forward(from: 0);
          _registerFormKey.currentState!.validate();
          break;
        default:
          final fallback = '${appLocalizations.authError}: ${error.message}';
          setState(() {
            if (_authMode == AuthMode.login) {
              _loginEmailError = fallback;
              _loginFormKey.currentState!.validate();
              _loginEmailShakeController.forward(from: 0);
            } else {
              _registerEmailError = fallback;
              _registerFormKey.currentState!.validate();
              _registerEmailShakeController.forward(from: 0);
            }
          });
      }
    } catch (error) {
      final fallback = '${appLocalizations.authError}: $error';
      setState(() {
        if (_authMode == AuthMode.login) {
          _loginEmailError = fallback;
          _loginFormKey.currentState!.validate();
          _loginEmailShakeController.forward(from: 0);
        } else {
          _registerEmailError = fallback;
          _registerFormKey.currentState!.validate();
          _registerEmailShakeController.forward(from: 0);
        }
      });
    } finally {
      // İşlem sonucu ne olursa olsun loading durumunu sıfırlıyoruz.
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildAuthForm() {
    final appLocalizations = AppLocalizations.of(context)!;
    final isDarkTheme = Provider.of<ThemeProvider>(context).isDarkTheme;

    // Ekran boyutlarını alıyoruz
    final deviceWidth = MediaQuery.of(context).size.width;
    final deviceHeight = MediaQuery.of(context).size.height;

    // LOGIN FORM
    final loginForm = Form(
      key: _loginFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            appLocalizations.loginToYourAccount,
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.titleLarge?.color,
            ),
          ),
          SizedBox(height: deviceHeight * 0.05), // Dinamik (önceden 40)
          // Email
          ShakeWidget(
            controller: _loginEmailShakeController,
            child: TextFormField(
              controller: _loginEmailController,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor:
                isDarkTheme ? const Color(0xFF1b1b1b) : Colors.grey[200],
                labelText: appLocalizations.email,
                labelStyle: TextStyle(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
                prefixIcon: Icon(
                  Icons.email,
                  color: Theme.of(context).iconTheme.color,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                counterText: '',
                errorMaxLines: 3,
              ),
              keyboardType: TextInputType.emailAddress,
              maxLength: 42,
              validator: (value) {
                if (_loginEmailError != null) {
                  final temp = _loginEmailError;
                  _loginEmailError = null;
                  return temp;
                }
                if (value == null || value.isEmpty) {
                  return appLocalizations.invalidEmail;
                }
                if (value.length > 30) {
                  return appLocalizations.emailTooLong;
                }
                if (!EmailValidator.validate(value.trim())) {
                  return appLocalizations.invalidEmail;
                }
                return null;
              },
              onSaved: (value) {
                _email = value!.trim();
              },
            ),
          ),
          SizedBox(height: deviceHeight * 0.02), // Dinamik (önceden 16)
          // Password
          ShakeWidget(
            controller: _loginPasswordShakeController,
            child: TextFormField(
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor:
                isDarkTheme ? const Color(0xFF1b1b1b) : Colors.grey[200],
                labelText: appLocalizations.password,
                labelStyle: TextStyle(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
                prefixIcon: Icon(
                  Icons.lock_outline,
                  color: Theme.of(context).iconTheme.color,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isPasswordVisible
                        ? Icons.visibility
                        : Icons.visibility_off,
                    color: Theme.of(context).iconTheme.color,
                  ),
                  onPressed: () {
                    setState(() {
                      _isPasswordVisible = !_isPasswordVisible;
                    });
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                counterText: '',
                errorMaxLines: 3,
              ),
              obscureText: !_isPasswordVisible,
              maxLength: 64,
              validator: (value) {
                if (_loginPasswordError != null) {
                  final temp = _loginPasswordError;
                  _loginPasswordError = null;
                  return temp;
                }
                if (value == null || value.isEmpty || value.length < 6) {
                  return appLocalizations.invalidPassword;
                }
                if (value.length > 64) {
                  return appLocalizations.passwordTooLong;
                }
                return null;
              },
              onSaved: (value) {
                _password = value!.trim();
              },
            ),
          ),
          SizedBox(height: deviceHeight * 0.02), // Dinamik (önceden 16)
          // Remember me
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Checkbox(
                value: _rememberMe,
                onChanged: (value) {
                  setState(() {
                    _rememberMe = value ?? false;
                  });
                },
                checkColor: isDarkTheme ? Colors.black : Colors.white,
                activeColor: isDarkTheme ? Colors.white : Colors.black,
              ),
              Text(
                appLocalizations.rememberMe,
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
            ],
          ),
          SizedBox(height: deviceHeight * 0.03), // Dinamik (önceden 24)
          // Login butonu
          AnimatedOpacity(
            opacity: _isLoading ? 0.6 : 1.0,
            duration: const Duration(milliseconds: 300),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDarkTheme ? Colors.white : Colors.black,
                  padding: EdgeInsets.symmetric(vertical: deviceHeight * 0.02),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _isLoading ? null : _submit,
                child: Text(
                  appLocalizations.logIn,
                  style: TextStyle(
                    fontSize: 18,
                    color: isDarkTheme ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // REGISTER FORM
    final registerForm = Form(
      key: _registerFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            appLocalizations.createYourAccount,
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.titleLarge?.color,
            ),
          ),
          SizedBox(height: deviceHeight * 0.05), // Dinamik (önceden 40)
          // Username
          ShakeWidget(
            controller: _registerUsernameShakeController,
            child: TextFormField(
              controller: _registerEmailController,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor:
                isDarkTheme ? const Color(0xFF1b1b1b) : Colors.grey[200],
                labelText: appLocalizations.username,
                labelStyle: TextStyle(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
                prefixIcon: Icon(
                  Icons.person,
                  color: Theme.of(context).iconTheme.color,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                counterText: '',
                errorMaxLines: 3,
              ),
              maxLength: 16,
              validator: (value) {
                if (_registerUsernameError != null) {
                  final temp = _registerUsernameError;
                  _registerUsernameError = null;
                  return temp;
                }
                if (value == null || value.isEmpty) {
                  return appLocalizations.invalidUsername;
                }
                if (value.length < 3) {
                  return appLocalizations.usernameTooShort;
                }
                if (value.length > 16) {
                  return appLocalizations.usernameTooLong;
                }
                if (!_usernameRegExp.hasMatch(value.trim())) {
                  return appLocalizations.invalidUsernameCharacters;
                }
                return null;
              },
              onSaved: (value) {
                _username = value!.trim().toLowerCase();
              },
            ),
          ),
          SizedBox(height: deviceHeight * 0.02), // Dinamik (önceden 16)
          // Email
          ShakeWidget(
            controller: _registerEmailShakeController,
            child: TextFormField(
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor:
                isDarkTheme ? const Color(0xFF1b1b1b) : Colors.grey[200],
                labelText: appLocalizations.email,
                labelStyle: TextStyle(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
                prefixIcon: Icon(
                  Icons.email,
                  color: Theme.of(context).iconTheme.color,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                counterText: '',
                errorMaxLines: 3,
              ),
              maxLength: 42,
              validator: (value) {
                if (_registerEmailError != null) {
                  final temp = _registerEmailError;
                  _registerEmailError = null;
                  return temp;
                }
                if (value == null || value.isEmpty) {
                  return appLocalizations.invalidEmail;
                }
                if (value.length > 30) {
                  return appLocalizations.emailTooLong;
                }
                if (!EmailValidator.validate(value.trim())) {
                  return appLocalizations.invalidEmail;
                }
                return null;
              },
              onSaved: (value) {
                _email = value!.trim();
              },
            ),
          ),
          SizedBox(height: deviceHeight * 0.02), // Dinamik (önceden 16)
          // Password
          ShakeWidget(
            controller: _registerPasswordShakeController,
            child: TextFormField(
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor:
                isDarkTheme ? const Color(0xFF1b1b1b) : Colors.grey[200],
                labelText: appLocalizations.password,
                labelStyle: TextStyle(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
                prefixIcon: Icon(
                  Icons.lock_outline,
                  color: Theme.of(context).iconTheme.color,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isPasswordVisible
                        ? Icons.visibility
                        : Icons.visibility_off,
                    color: Theme.of(context).iconTheme.color,
                  ),
                  onPressed: () {
                    setState(() {
                      _isPasswordVisible = !_isPasswordVisible;
                    });
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                counterText: '',
                errorMaxLines: 3,
              ),
              obscureText: !_isPasswordVisible,
              maxLength: 64,
              validator: (value) {
                if (_registerPasswordError != null) {
                  final temp = _registerPasswordError;
                  _registerPasswordError = null;
                  return temp;
                }
                if (value == null || value.isEmpty || value.length < 6) {
                  return appLocalizations.invalidPassword;
                }
                if (value.length > 64) {
                  return appLocalizations.passwordTooLong;
                }
                return null;
              },
              onSaved: (value) {
                _password = value!.trim();
              },
            ),
          ),
          SizedBox(height: deviceHeight * 0.02), // Dinamik (önceden 16)
          // Confirm password
          ShakeWidget(
            controller: _registerConfirmPasswordShakeController,
            child: TextFormField(
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor:
                isDarkTheme ? const Color(0xFF1b1b1b) : Colors.grey[200],
                labelText: appLocalizations.confirmPassword,
                labelStyle: TextStyle(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
                prefixIcon: Icon(
                  Icons.lock_outline,
                  color: Theme.of(context).iconTheme.color,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isConfirmPasswordVisible
                        ? Icons.visibility
                        : Icons.visibility_off,
                    color: Theme.of(context).iconTheme.color,
                  ),
                  onPressed: () {
                    setState(() {
                      _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                    });
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                counterText: '',
                errorMaxLines: 3,
              ),
              obscureText: !_isConfirmPasswordVisible,
              maxLength: 64,
              validator: (value) {
                if (_registerConfirmPasswordError != null) {
                  final temp = _registerConfirmPasswordError;
                  _registerConfirmPasswordError = null;
                  return temp;
                }
                if (value == null || value.isEmpty || value.length < 6) {
                  return appLocalizations.invalidPassword;
                }
                if (value.length > 64) {
                  return appLocalizations.passwordTooLong;
                }
                return null;
              },
              onSaved: (value) {
                _confirmPassword = value!.trim();
              },
            ),
          ),
          SizedBox(height: deviceHeight * 0.03), // Dinamik (önceden 24)
          // Sign Up butonu
          AnimatedOpacity(
            opacity: _isLoading ? 0.6 : (_agreeToTerms ? 1.0 : 0.6),
            duration: const Duration(milliseconds: 200),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDarkTheme ? Colors.white : Colors.black,
                  padding: EdgeInsets.symmetric(vertical: deviceHeight * 0.02),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: (_isLoading || !_agreeToTerms) ? null : _submit,
                child: Text(
                  appLocalizations.signUp,
                  style: TextStyle(
                    fontSize: 18,
                    color: isDarkTheme ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // Cross-fade
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        switchInCurve: Curves.easeIn,
        switchOutCurve: Curves.easeOut,
        child: _authMode == AuthMode.login ? loginForm : registerForm,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Ekran boyutlarını alıyoruz
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final fontScale = screenWidth / 375; // Font ölçeklendirme faktörü

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16 * screenWidth / 375), // Dinamik padding
          child: Column(
            children: [
              _buildAuthForm(),
              SizedBox(height: 16 * screenHeight / 812), // Dinamik yükseklik

              // Divider with "or" text
              Row(
                children: [
                  Expanded(
                    child: Divider(
                      color: Theme.of(context).dividerColor,
                      thickness: 1 * screenWidth / 375, // Dinamik kalınlık
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8 * screenWidth / 375), // Dinamik padding
                    child: Text(
                      AppLocalizations.of(context)!.or,
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                        fontSize: 16 * fontScale, // Dinamik font boyutu
                      ),
                    ),
                  ),
                  Expanded(
                    child: Divider(
                      color: Theme.of(context).dividerColor,
                      thickness: 1 * screenWidth / 375, // Dinamik kalınlık
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16 * screenHeight / 812), // Dinamik yükseklik

              // Continue with Google button
              AnimatedOpacity(
                opacity: _isLoading
                    ? 0.6
                    : (_authMode == AuthMode.register && !_agreeToTerms ? 0.6 : 1.0),
                duration: const Duration(milliseconds: 200),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Provider.of<ThemeProvider>(context).isDarkTheme
                          ? Colors.white
                          : Colors.black,
                      padding: EdgeInsets.symmetric(vertical: 16 * screenHeight / 812), // Dinamik padding
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10 * fontScale),
                      ),
                    ),
                    onPressed: (_isLoading ||
                        (_authMode == AuthMode.register && !_agreeToTerms))
                        ? null
                        : () {
                      FocusScope.of(context).unfocus();
                      Future.delayed(const Duration(milliseconds: 150), () {
                        _showComingSoonMessage();
                      });
                    },
                    icon: Icon(
                      Icons.g_mobiledata,
                      color: Provider.of<ThemeProvider>(context).isDarkTheme
                          ? Colors.black
                          : Colors.white,
                      size: 24 * fontScale, // Dinamik ikon boyutu
                    ),
                    label: Text(
                      AppLocalizations.of(context)!.continueWithGoogle,
                      style: TextStyle(
                        color: Provider.of<ThemeProvider>(context).isDarkTheme
                            ? Colors.black
                            : Colors.white,
                        fontSize: 16 * fontScale, // Dinamik font boyutu
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 16 * screenHeight / 812), // Dinamik yükseklik

// Replace the existing Row inside the AnimatedOpacity with the following:

              AnimatedOpacity(
                opacity: _authMode == AuthMode.register ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeInOut,
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeInOut,
                  child: _authMode == AuthMode.register
                      ? Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 20.0 * MediaQuery.of(context).size.width / 375,
                    ), // Adjusted padding
                    child: Row(
                      children: [
                        // Expanded FittedBox for text to ensure single line
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _showTermsOfUse(context),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                AppLocalizations.of(context)!.iHaveReadAndAgree,
                                style: TextStyle(
                                  color: Theme.of(context).textTheme.bodyLarge?.color,
                                  fontSize: 14 * (MediaQuery.of(context).size.width / 375), // Dynamic font size
                                ),
                                maxLines: 1, // Ensure single line
                                overflow: TextOverflow.ellipsis, // Add ellipsis if text is too long
                              ),
                            ),
                          ),
                        ),
                        // Checkbox on the right
                        Checkbox(
                          value: _agreeToTerms,
                          onChanged: (bool? value) {
                            setState(() {
                              _agreeToTerms = value ?? false;
                            });
                          },
                          checkColor: Provider.of<ThemeProvider>(context).isDarkTheme
                              ? Colors.black
                              : Colors.white,
                          activeColor: Provider.of<ThemeProvider>(context).isDarkTheme
                              ? Colors.white
                              : Colors.black,
                        ),
                      ],
                    ),
                  )
                      : SizedBox.shrink(),
                ),
              ),
              SizedBox(height: 4 * screenHeight / 812), // Dinamik yükseklik

              // Switch Auth mode TextButton
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () {
                      // Reset _agreeToTerms when switching modes
                      setState(() {
                        _switchAuthMode();
                        if (_authMode == AuthMode.login) {
                          _agreeToTerms = false;
                        }
                      });
                    },
                    child: Text(
                      _authMode == AuthMode.login
                          ? AppLocalizations.of(context)!.dontHaveAccount
                          : AppLocalizations.of(context)!.alreadyHaveAccount,
                      style: TextStyle(
                        fontSize: 16 * fontScale, // Dinamik font boyutu
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTermsOfUse(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final isDarkTheme =
        Provider.of<ThemeProvider>(context, listen: false).isDarkTheme;
    final backgroundColor = isDarkTheme ? const Color(0xFF121212) : Colors.white;
    final textColor = isDarkTheme ? Colors.white : Colors.black;

    // Ekran boyutlarını alıyoruz
    final deviceWidth = MediaQuery.of(context).size.width;
    final deviceHeight = MediaQuery.of(context).size.height;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(deviceWidth * 0.05), // Dinamik
        ),
      ),
      builder: (BuildContext context) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: deviceHeight * 0.6,
          ),
          child: Padding(
            // const EdgeInsets.all(16.0) yerine dinamik
            padding: EdgeInsets.all(deviceWidth * 0.04),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Başlık ve Kapat Butonu
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      localizations.termsOfServiceAndPrivacyPolicyTitle,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: textColor.withOpacity(0.6),
                        size: 24,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                SizedBox(height: deviceHeight * 0.0125), // Dinamik (önceden 10)
                // İçerik
                Expanded(
                  child: SingleChildScrollView(
                    child: RichText(
                      text: TextSpan(
                        children: localizations
                            .termsOfServiceAndPrivacyPolicyContent
                            .split(' ')
                            .map((word) {
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
}

class EmailVerificationScreen extends StatefulWidget {
  final String email;
  final String username;
  final String userId;
  final String password;

  const EmailVerificationScreen({
    Key? key,
    required this.email,
    required this.username,
    required this.userId,
    required this.password,
  }) : super(key: key);

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  late NotificationService _notificationService;
  static const int totalVerificationDuration = 86400; // 24 saat
  int _remainingSeconds = totalVerificationDuration;
  Timer? _timer;
  bool _isVerified = false;
  bool _isResendLoading = false;

  @override
  void initState() {
    super.initState();
    _notificationService =
        Provider.of<NotificationService>(context, listen: false);
    _initializeRemainingTime();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

// Güncellenmiş _initializeRemainingTime fonksiyonu:
  Future<void> _initializeRemainingTime() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      if (doc.exists && doc.data() != null && doc.data()!['createdAt'] != null) {
        final data = doc.data()!;
        final Timestamp createdAtTimestamp = data['createdAt'];
        final DateTime createdAt = createdAtTimestamp.toDate();

        // Sunucu tarafındaki verifyAttempts değerini kullanıyoruz:
        final int verifyAttempts = data['verifyAttempts'] ?? 0;
        final serverNow = Timestamp.now().toDate();
        final int elapsedSeconds = serverNow.difference(createdAt).inSeconds;

        final totalSeconds = 86400 * (1 + verifyAttempts);
        final remaining = totalSeconds - elapsedSeconds;
        setState(() {
          _remainingSeconds = remaining > 0 ? remaining : 0;
        });
      }
    } catch (e) {
      debugPrint('Kayıt tarihini alırken hata: $e');
      setState(() {
        _remainingSeconds = totalVerificationDuration;
      });
    }
    _startTimer();
  }

// Güncellenmiş _resendVerificationEmail fonksiyonu:
  Future<void> _resendVerificationEmail() async {
    final appLocalizations = AppLocalizations.of(context)!;
    setState(() {
      _isResendLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Firestore’daki kullanıcı verisini getir ve verifyAttempts değerine bak:
        final userDocRef =
        FirebaseFirestore.instance.collection('users').doc(widget.userId);
        final docSnapshot = await userDocRef.get();
        final int verifyAttempts =
        docSnapshot.exists ? (docSnapshot.data()?['verifyAttempts'] ?? 0) : 0;

        if (verifyAttempts >= 2) {
          _notificationService.showNotification(
            message: appLocalizations.maxResendLimitReached,
            bottomOffset: 0.02,
            isSuccess: false,
          );
          return;
        }

        // VerifyAttempts alanını sunucuda 1 artır:
        await userDocRef.update({'verifyAttempts': FieldValue.increment(1)});

        // Doğrulama mailini gönder:
        await user.sendEmailVerification();

        // Kalan süreyi güncellemek için yeniden başlat:
        await _initializeRemainingTime();

        _notificationService.showNotification(
          message: appLocalizations.linkSent,
          isSuccess: true,
          bottomOffset: 0.02,
        );
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('Doğrulama maili yeniden gönderilirken hata');
      if (e.code == 'too-many-requests') {
        _notificationService.showNotification(
          message: appLocalizations.tooManyRequests,
          isSuccess: false,
          bottomOffset: 0.02,
        );
      } else {
        _notificationService.showNotification(
          message: appLocalizations.authError,
          isSuccess: false,
          bottomOffset: 0.02,
        );
      }
    } catch (e) {
      debugPrint('Bilinmeyen hata');
      _notificationService.showNotification(
        message: appLocalizations.authError,
        isSuccess: false,
        bottomOffset: 0.02,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isResendLoading = false;
        });
      }
    }
  }


  void _startTimer() {
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      await _checkVerification();

      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_remainingSeconds <= 0) {
        timer.cancel();
        await _deleteAccountAndRedirect();
      } else {
        setState(() {
          _remainingSeconds--;
        });
      }
    });
  }

  Future<void> _checkVerification() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await user.reload();
    if (!mounted) return;

    if (user.emailVerified) {
      setState(() {
        _isVerified = true;
      });
      _timer?.cancel();

      // No Firestore "verified" field update needed.
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const AuthWrapper()),
      );
    }
  }

  Future<void> _deleteAccountAndRedirect() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .delete();

        await FirebaseFirestore.instance
            .collection('usernames')
            .doc(widget.username.toLowerCase())
            .delete();

        await user.delete();
      }
    } catch (e) {
      debugPrint('Hesap silinirken hata: $e');
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const AuthWrapper()),
    );
  }

  String _formatTime(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final secs = totalSeconds % 60;
    final hh = hours.toString().padLeft(2, '0');
    final mm = minutes.toString().padLeft(2, '0');
    final ss = secs.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context)!;
    final isDarkTheme = Provider.of<ThemeProvider>(context).isDarkTheme;

    // Ekran boyutlarını alıyoruz
    final deviceWidth = MediaQuery.of(context).size.width;
    final deviceHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(height: deviceHeight * 0.125), // Dinamik (önceden 100)
            // "Stack" for the background shape + image
            Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  // top: -98, left: -30 => dinamik örnek
                  top: -deviceHeight * 0.21,
                  left: -deviceWidth * 0.2,
                  child: Transform.rotate(
                    angle: -80 * pi / 180,
                    child: Container(
                      // width: 400, height: 400 => dinamik örnek
                      width: deviceWidth * 1.2,
                      height: deviceWidth * 1.2,
                      decoration: BoxDecoration(
                        color: Colors.lightBlue.shade100,
                        borderRadius: BorderRadius.circular(
                          deviceWidth * 0.15,
                        ),
                      ),
                    ),
                  ),
                ),
                // Image.asset('assets/verification.png', width: 320, height: 300)
                SizedBox(
                  width: deviceWidth * 0.8,
                  height: deviceWidth * 0.75,
                  child: Image.asset('assets/verification.png'),
                ),
              ],
            ),
            SizedBox(height: deviceHeight * 0.025), // Dinamik (önceden 20)
            Text(
              appLocalizations.verifyYourEmail,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: deviceHeight * 0.0125), // Dinamik (önceden 10)
            Text(
              appLocalizations.pleaseCheckYourEmail,
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: deviceHeight * 0.025), // Dinamik (önceden 20)
            if (!_isVerified) ...[
              SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: deviceWidth * 0.1),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDarkTheme
                          ? const Color(0xFF0D31FE)
                          : const Color(0xFF0D62FE),
                      padding: EdgeInsets.symmetric(vertical: deviceHeight * 0.022),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _isResendLoading ? null : _resendVerificationEmail,
                    child: FittedBox(
                      child: Text(
                        appLocalizations.resendCode,
                        maxLines: 1,
                        style: TextStyle(
                          color: isDarkTheme ? Colors.black : Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: deviceHeight * 0.01), // Dinamik (önceden 8)
              // Continue without verification butonu
              Padding(
                padding: EdgeInsets.symmetric(horizontal: deviceWidth * 0.1),
                child: TextButton(
                  onPressed: () {
                    _timer?.cancel();
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (context) => mainScreen),
                    );
                  },
                  child: Text(
                    appLocalizations
                        .verificationScreenContinueWithoutVerification,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDarkTheme ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              ),
              SizedBox(height: deviceHeight * 0.01), // Dinamik (önceden 8)
              Padding(
                padding: EdgeInsets.only(top: deviceHeight * 0.01),
                child: Text(
                  appLocalizations.verificationScreenWarning,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDarkTheme ? Colors.white : Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(height: deviceHeight * 0.025), // Dinamik (önceden 20)
              // Kalan süre
              AnimatedTime(
                time: _formatTime(_remainingSeconds),
                style: GoogleFonts.anaheim(
                  textStyle: TextStyle(
                    fontSize: 20,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AnimatedDigit extends StatelessWidget {
  final String digit;
  final TextStyle? style;

  const AnimatedDigit({Key? key, required this.digit, this.style})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      child: Text(
        digit,
        key: ValueKey<String>(digit),
        style: style,
      ),
    );
  }
}

class AnimatedTime extends StatelessWidget {
  final String time; // "HH:MM:SS"
  final TextStyle? style;

  const AnimatedTime({Key? key, required this.time, this.style})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: time.split('').map((char) {
        if (char.contains(RegExp(r'\d'))) {
          return AnimatedDigit(digit: char, style: style);
        } else {
          return Text(char, style: style);
        }
      }).toList(),
    );
  }
}