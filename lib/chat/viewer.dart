import 'dart:io';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../notifications.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:path/path.dart' as path;

class PhotoViewer extends StatelessWidget {
  final File imageFile;
  const PhotoViewer({Key? key, required this.imageFile}) : super(key: key);

  /// 50 ms açılma ve kapanma süresiyle geçiş yapan route metodu.
  static Route route(File imageFile) {
    return PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 50),
      reverseTransitionDuration: const Duration(milliseconds: 50),
      opaque: false,
      barrierDismissible: false,
      pageBuilder: (_, __, ___) => PhotoViewer(imageFile: imageFile),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final fadeAnim =
        Tween<double>(begin: 0.0, end: 1.0).animate(animation);
        final scaleAnim = Tween<double>(begin: 0.90, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOut),
        );
        return FadeTransition(
          opacity: fadeAnim,
          child: ScaleTransition(scale: scaleAnim, child: child),
        );
      },
      barrierColor: Colors.black.withOpacity(0.5),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final notificationService =
    Provider.of<NotificationService>(context, listen: false);
    final Size screenSize = MediaQuery.of(context).size;

    // Dinamik boyutlar (oranlar isteğe göre ayarlanabilir):
    final double horizontalMargin = screenSize.width * 0.05; // %5
    final double imageTopMargin = screenSize.height * 0.1;     // %10
    final double imageBottomMargin = screenSize.height * 0.1;  // %10

    final double availableWidth = screenSize.width - (horizontalMargin * 2);
    final double availableHeight =
        screenSize.height - imageTopMargin - imageBottomMargin;

    // Buton ve ikon boyutları:
    final double closeButtonSize = screenSize.width * 0.07;
    final double bottomRowVerticalMargin = screenSize.height * 0.02;
    final double iconSize = screenSize.width * 0.05;
    final double fontSize = screenSize.width * 0.03;

    // Gradient overlay yüksekliği: alt kısımda, fotoğrafın üzerinde görünecek.
    final double gradientHeight = screenSize.height * 0.2;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Arka planı bulanıklaştıran overlay (arka planda kalır)
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
              child: Container(color: Colors.black.withOpacity(0.2)),
            ),
          ),
          // Tüm içerikler SafeArea içinde; fotoğraf, gradient ve butonlar katman sırasına göre:
          SafeArea(
            child: Stack(
              children: [
                // Fotoğraf katmanı (arka planda)
                Center(
                  child: Container(
                    margin: EdgeInsets.only(
                      left: horizontalMargin,
                      right: horizontalMargin,
                      top: imageTopMargin,
                      bottom: imageBottomMargin,
                    ),
                    constraints: BoxConstraints(
                      maxWidth: availableWidth,
                      maxHeight: availableHeight,
                    ),
                    child: InteractiveViewer(
                      panEnabled: false,
                      scaleEnabled: true,
                      minScale: 1.0,
                      maxScale: 4.0,
                      boundaryMargin:
                      EdgeInsets.all(screenSize.width * 0.1),
                      clipBehavior: Clip.none,
                      child: ClipRRect(
                        borderRadius:
                        BorderRadius.circular(screenSize.width * 0.02),
                        child: Image.file(
                          imageFile,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
                // Gradient overlay: fotoğrafın üzerinde, alt kısımda görünür.
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: gradientHeight,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.5),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                // Üstte ortalanmış kapan (X) butonu
                Positioned(
                  top: screenSize.height * 0.02,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: IconButton(
                      icon: Icon(
                        Icons.close,
                        color: Colors.white,
                        size: closeButtonSize,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
                // Alt kısımda paylaşma ve indirme butonları
                Positioned(
                  bottom: bottomRowVerticalMargin,
                  left: 0,
                  right: 0,
                  child: Padding(
                    padding:
                    EdgeInsets.symmetric(horizontal: screenSize.width * 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Paylaş butonu
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              await Share.shareXFiles(
                                  [XFile(imageFile.path)]);
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SvgPicture.asset(
                                  'assets/share.svg',
                                  width: iconSize,
                                  height: iconSize,
                                  color: Colors.white,
                                ),
                                SizedBox(height: screenSize.height * 0.005),
                                Text(
                                  localizations.share,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: fontSize,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Dikey ayırıcı
                        Container(
                          width: screenSize.width * 0.002,
                          height: screenSize.height * 0.06,
                          color: Colors.white,
                        ),
                        // İndir butonu
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              try {
                                final tempDir = await getTemporaryDirectory();
                                final baseName = 'cortex';
                                const extension = '.jpg';
                                int i = 0;
                                late File localFile;
                                while (true) {
                                  final fileName = i == 0
                                      ? '$baseName$extension'
                                      : '$baseName-$i$extension';
                                  localFile =
                                      File(path.join(tempDir.path, fileName));
                                  if (!(await localFile.exists())) {
                                    break;
                                  }
                                  i++;
                                }
                                // Resmi geçici dizine kopyala
                                await imageFile.copy(localFile.path);
                                // Galeriye kaydet
                                final bool? success =
                                await GallerySaver.saveImage(localFile.path);
                                if (success == true) {
                                  notificationService.showNotification(
                                    message: localizations.downloadSuccess,
                                    isSuccess: true,
                                    bottomOffset: 0.1,
                                  );
                                } else {
                                  notificationService.showNotification(
                                    message: localizations.downloadFailed,
                                    isSuccess: false,
                                    bottomOffset: 0.1,
                                  );
                                }
                              } catch (e) {
                                notificationService.showNotification(
                                  message: localizations.downloadFailed,
                                  isSuccess: false,
                                  bottomOffset: 0.1,
                                );
                              }
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SvgPicture.asset(
                                  'assets/download.svg',
                                  width: iconSize,
                                  height: iconSize,
                                  color: Colors.white,
                                ),
                                SizedBox(height: screenSize.height * 0.005),
                                Text(
                                  localizations.download,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: fontSize,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
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
        ],
      ),
    );
  }
}