import 'package:cortex/main.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

import 'chat.dart';
import '../theme.dart';

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
  String _errorMessage = '';

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

    // Renk ve stil ayarları
    final backgroundColor = AppColors.background;
    final titleColor = AppColors.primaryColor.inverted;
    final subtitleColor = AppColors.tertiaryColor;
    final borderColor = AppColors.border;
    final fillColor = AppColors.background;

    // Butonlarla ilgili renk ayarları
    final closeButtonTextAndSplashColor = AppColors.senaryColor;      // "Kapat" butonu
    final submitButtonTextAndSplashColor = AppColors.septenaryColor;  // "Rapor Gönder" butonu

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Dialog(
        backgroundColor: backgroundColor,
        insetPadding: const EdgeInsets.all(16.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.deferToChild,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            child: SingleChildScrollView(
              // Ana kolon: üstte içerik (padding'li), altta çizgiler ve butonlar
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // İçerik kısmı: metin alanı, checkbox vb.
                  Padding(
                    // Alt padding’i 8 olarak değiştirdik.
                    padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Başlık
                        Text(
                          localizations.reportDialogTitle,
                          style: TextStyle(
                            color: titleColor,
                            fontSize: 20.0,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8.0),
                        // Açıklama TextField'i
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
                                color: titleColor,
                              ),
                            ),
                            counterStyle: TextStyle(color: subtitleColor),
                            alignLabelWithHint: true,
                            contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                          ),
                          style: TextStyle(color: titleColor),
                        ),
                        const SizedBox(height: 8.0),
                        // "Harmful" satırı - metin solda, checkbox sağda
                        _buildCheckRow(
                          label: localizations.reportHarmful,
                          value: _isHarmful,
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
                        ),
                        // "Not True" satırı - metin solda, checkbox sağda
                        _buildCheckRow(
                          label: localizations.reportNotTrue,
                          value: _isNotTrue,
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
                        ),
                        // "Not Helpful" satırı - metin solda, checkbox sağda
                        _buildCheckRow(
                          label: localizations.reportNotHelpful,
                          value: _isNotHelpful,
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
                        ),
                        const SizedBox(height: 8.0),
                        // Hata Mesajı (Animasyonlu)
                        AnimatedOpacity(
                          opacity: _showError ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 300),
                          child: _showError
                              ? Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Text(
                              _errorMessage,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 14.0,
                              ),
                            ),
                          )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    color: AppColors.quinaryColor,
                    thickness: 0.5,
                    height: 1,
                  ),
                  IntrinsicHeight(
                    child: Row(
                      children: [
                        // Kapat butonu
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              splashColor:
                              closeButtonTextAndSplashColor.withOpacity(0.1),
                              highlightColor:
                              closeButtonTextAndSplashColor.withOpacity(0.1),
                              onTap: () => Navigator.of(context).pop(),
                              child: Container(
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Text(
                                  localizations.closeButton,
                                  style: TextStyle(
                                    color: closeButtonTextAndSplashColor,
                                    fontSize: 16,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Dikey çizgi
                        VerticalDivider(
                          width: 1,
                          thickness: 0.5,
                          color: AppColors.quinaryColor,
                        ),

                        // Rapor Gönder butonu
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              splashColor:
                              submitButtonTextAndSplashColor.withOpacity(0.1),
                              highlightColor:
                              submitButtonTextAndSplashColor.withOpacity(0.1),
                              onTap: () async {
                                if (_selectedSubject == 0) {
                                  setState(() {
                                    _errorMessage =
                                        localizations.reportErrorMessage;
                                    _showError = true;
                                  });
                                } else {
                                  // İnternet bağlantısını kontrol et.
                                  bool hasConnection = await InternetConnection().hasInternetAccess;
                                  if (!hasConnection) {
                                    setState(() {
                                      _errorMessage = "İnternet bağlantısı yok";
                                      _showError = true;
                                    });
                                  } else {
                                    await _submitReport();
                                    Navigator.of(context).pop();
                                  }
                                }
                              },
                              child: Container(
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Text(
                                  localizations.submitButton,
                                  style: TextStyle(
                                    color: submitButtonTextAndSplashColor,
                                    fontSize: 16,
                                  ),
                                  textAlign: TextAlign.center,
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
      ),
    );
  }

  Widget _buildCheckRow({
    required String label,
    required bool value,
    required VoidCallback onTap,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: AppColors.tertiaryColor)),
        Checkbox(
          value: value,
          onChanged: (bool? newValue) {
            onTap();
          },
          activeColor: AppColors.primaryColor.inverted,
          checkColor: AppColors.primaryColor,
        ),
      ],
    );
  }


  Future<void> _submitReport() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final reporterUid = currentUser.uid;
    final description = _descriptionController.text.trim();
    final messageText = widget.aiMessage;
    final modelId = widget.modelId;
    final subject = _selectedSubject;

    await FirebaseFirestore.instance.collection('reports').add({
      'messageText': messageText,
      'reporterUid': reporterUid,
      'modelId': modelId,
      'description': description,
      'subject': subject,
      'timestamp': FieldValue.serverTimestamp(),
    });

    final chatState = context.findAncestorStateOfType<ChatScreenState>();
    if (chatState != null) {
      chatState.markMessageAsReported(messageText);
    }
  }
}
