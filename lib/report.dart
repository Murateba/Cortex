import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'chat.dart';
import 'theme.dart';

class ReportDialog extends StatefulWidget {
  final String aiMessage;
  final String modelId;

  const ReportDialog({
    Key? key,
    required this.aiMessage,
    required this.modelId,
  }) : super(key: key);

  @override
  _ReportDialogState createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog>
    with SingleTickerProviderStateMixin {
  final TextEditingController _descriptionController = TextEditingController();

  int _selectedSubject = 0; // 1 => harmful, 2 => not true, 3 => not helpful
  bool _isHarmful = false;
  bool _isNotTrue = false;
  bool _isNotHelpful = false;
  bool _showError = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // 200 ms'lik fade-in animasyonu ayarla.
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    // Animasyonu başlat
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final isDarkTheme = Provider.of<ThemeProvider>(context).isDarkTheme;

    // Temaya göre renkleri belirle
    final backgroundColor = isDarkTheme ? const Color(0xFF141414) : Colors.white;
    final titleColor = isDarkTheme ? Colors.white : Colors.black;
    final subtitleColor = isDarkTheme ? Colors.white70 : Colors.grey[800];
    final borderColor = isDarkTheme ? Colors.white54 : Colors.black26;
    final fillColor = isDarkTheme ? Colors.grey[900] : Colors.grey[100];
    final checkActiveColor = isDarkTheme ? Colors.white : Colors.black;
    final checkCheckColor = isDarkTheme ? Colors.black : Colors.white;
    final closeButtonColor =
    isDarkTheme ? Colors.grey[900]! : Colors.grey[200]!;
    final closeButtonTextColor = isDarkTheme ? Colors.white : Colors.black;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Dialog(
        backgroundColor: backgroundColor,
        insetPadding: const EdgeInsets.all(16.0),
        // Klavye kapatma işlemi için GestureDetector
        child: GestureDetector(
          onTap: () {
            FocusScope.of(context).unfocus();
          },
          behavior: HitTestBehavior.deferToChild,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title
                    Text(
                      localizations.reportDialogTitle,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 20.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12.0),
                    // Description TextField
                    TextField(
                      controller: _descriptionController,
                      maxLength: 150,
                      maxLines: 3,
                      textAlign: TextAlign.start,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: InputDecoration(
                        labelText: localizations.reportDescriptionLabel,
                        labelStyle: TextStyle(color: subtitleColor),
                        fillColor: fillColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          borderSide: BorderSide(
                            color: isDarkTheme ? Colors.white : Colors.black,
                          ),
                        ),
                        counterStyle: TextStyle(color: subtitleColor),
                        alignLabelWithHint: true,
                        contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      ),
                      style: TextStyle(color: titleColor),
                    ),
                    const SizedBox(height: 12.0),
                    // "Harmful" satırı - metin solda, checkbox sağda
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          localizations.reportHarmful,
                          style: TextStyle(color: subtitleColor),
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isHarmful = !_isHarmful;
                              if (_isHarmful) {
                                _isNotTrue = false;
                                _isNotHelpful = false;
                                _selectedSubject = 1;
                              } else {
                                _selectedSubject = 0;
                              }
                              _showError = false;
                            });
                          },
                          child: Checkbox(
                            value: _isHarmful,
                            onChanged: null,
                            activeColor: checkActiveColor,
                            checkColor: checkCheckColor,
                          ),
                        ),
                      ],
                    ),
                    // "Not True" satırı - metin solda, checkbox sağda
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          localizations.reportNotTrue,
                          style: TextStyle(color: subtitleColor),
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isNotTrue = !_isNotTrue;
                              if (_isNotTrue) {
                                _isHarmful = false;
                                _isNotHelpful = false;
                                _selectedSubject = 2;
                              } else {
                                _selectedSubject = 0;
                              }
                              _showError = false;
                            });
                          },
                          child: Checkbox(
                            value: _isNotTrue,
                            onChanged: null,
                            activeColor: checkActiveColor,
                            checkColor: checkCheckColor,
                          ),
                        ),
                      ],
                    ),
                    // "Not Helpful" satırı - metin solda, checkbox sağda
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          localizations.reportNotHelpful,
                          style: TextStyle(color: subtitleColor),
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isNotHelpful = !_isNotHelpful;
                              if (_isNotHelpful) {
                                _isHarmful = false;
                                _isNotTrue = false;
                                _selectedSubject = 3;
                              } else {
                                _selectedSubject = 0;
                              }
                              _showError = false;
                            });
                          },
                          child: Checkbox(
                            value: _isNotHelpful,
                            onChanged: null,
                            activeColor: checkActiveColor,
                            checkColor: checkCheckColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16.0),
                    // Animated Error Message
                    AnimatedOpacity(
                      opacity: _showError ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: _showError
                          ? Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          localizations.reportErrorMessage,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 14.0,
                          ),
                        ),
                      )
                          : const SizedBox.shrink(),
                    ),
                    // Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Close Button
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: closeButtonColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20.0),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 6.0,
                            ),
                            minimumSize: const Size(80, 36),
                          ).copyWith(
                            overlayColor:
                            MaterialStateProperty.all(Colors.transparent),
                            splashFactory: NoSplash.splashFactory,
                          ),
                          child: Text(
                            localizations.closeButton,
                            style: TextStyle(color: closeButtonTextColor),
                          ),
                        ),
                        const SizedBox(width: 8.0),
                        // Submit Button
                        ElevatedButton(
                          onPressed: () async {
                            if (_selectedSubject == 0) {
                              setState(() {
                                _showError = true;
                              });
                            } else {
                              await _submitReport();
                              Navigator.of(context).pop(); // Dialogu kapat
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                            isDarkTheme ? Colors.white : Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20.0),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 6.0,
                            ),
                            minimumSize: const Size(80, 36),
                          ).copyWith(
                            overlayColor:
                            MaterialStateProperty.all(Colors.transparent),
                            splashFactory: NoSplash.splashFactory,
                          ),
                          child: Text(
                            localizations.submitButton,
                            style: TextStyle(
                              color: isDarkTheme ? Colors.black : Colors.white,
                            ),
                          ),
                        ),
                      ],
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

  Future<void> _submitReport() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return;
    }

    final reporterUid = currentUser.uid;
    final description = _descriptionController.text.trim();
    final messageText = widget.aiMessage;
    final modelId = widget.modelId;
    final subject = _selectedSubject;

    // Firestore'a yaz
    await FirebaseFirestore.instance.collection('reports').add({
      'messageText': messageText,
      'reporterUid': reporterUid,
      'modelId': modelId,
      'description': description,
      'subject': subject,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // ChatScreenState bul ve isReported = true yap
    final chatState = context.findAncestorStateOfType<ChatScreenState>();
    if (chatState != null) {
      chatState.markMessageAsReported(messageText);
    }
  }
}
