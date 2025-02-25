import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final SendPort? send = IsolateNameServer.lookupPortByName('downloader_send_port');
  send?.send([id, status, progress]);
}

class NotificationStrings {
  static String downloadingTitle = 'Downloading';
  static String downloadCompletedTitle = 'Download Completed';
  static String downloadPausedTitle = 'Download Paused';
  static String downloadErrorTitle = 'Download Error';
  static String cancelButtonText = 'Cancel';

  static void init(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    downloadingTitle = localizations.downloadingTitle;
    downloadCompletedTitle = localizations.downloadCompletedTitle;
    downloadPausedTitle = localizations.downloadPausedTitle;
    downloadErrorTitle = localizations.downloadErrorTitle;
    cancelButtonText = localizations.cancelButtonText;
  }
}

class LocalNotificationService {
  static final LocalNotificationService instance = LocalNotificationService._internal();
  LocalNotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> initNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        debugPrint('Notification response: actionId=${response.actionId}, payload=${response.payload}');
        if (response.actionId == 'CANCEL_ACTION' && response.payload != null) {
          debugPrint('Cancelling download for taskId: ${response.payload}');
          await FileDownloadHelper().cancelDownload(response.payload!);
        }
      },
    );
  }

  Future<void> showDownloadProgressNotification({
    required int notificationId,
    required String title,
    required double progressPercent,
    String? body,
    String? payload,
    bool ongoing = true,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'download_channel_id',
      'İndirme İşlemleri',
      channelDescription: 'Büyük dosya indirme bildirimleri',
      importance: Importance.max,
      priority: Priority.high,
      onlyAlertOnce: true,
      ongoing: ongoing,
      showProgress: true,
      maxProgress: 100,
      progress: progressPercent.toInt(),
      actions: [
        AndroidNotificationAction(
          'CANCEL_ACTION',
          NotificationStrings.cancelButtonText,
          cancelNotification: true, // Bildirimi otomatik kapatma
          showsUserInterface: false, // UI ile etkileşim gerekmez
        ),
      ],
    );

    final notificationDetails = NotificationDetails(android: androidDetails);
    debugPrint('Showing notification: id=$notificationId, payload=$payload');
    await _flutterLocalNotificationsPlugin.show(
      notificationId,
      NotificationStrings.downloadingTitle,
      body ?? '',
      notificationDetails,
      payload: payload, // taskId olduğundan emin olun
    );
  }

  Future<void> showSimpleNotification({
    required int notificationId,
    required String title,
    required String body,
    String? payload,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'download_channel_id',
      'İndirme İşlemleri',
      channelDescription: 'Büyük dosya indirme bildirimleri',
      importance: Importance.max,
      priority: Priority.high,
    );

    final notificationDetails = NotificationDetails(android: androidDetails);
    await _flutterLocalNotificationsPlugin.show(
      notificationId,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  Future<void> cancelNotification(int notificationId) async {
    await _flutterLocalNotificationsPlugin.cancel(notificationId);
  }
}

class FileDownloadHelper extends ChangeNotifier {
  static final FileDownloadHelper _instance = FileDownloadHelper._internal();
  factory FileDownloadHelper() => _instance;

  FileDownloadHelper._internal() {
    _bindBackgroundIsolate();
    FlutterDownloader.registerCallback(_downloadCallback);
  }

  String _status = 'İndirilemedi';
  String get status => _status;

  final ReceivePort _port = ReceivePort();
  final Map<String, _DownloadTaskInfo> _tasks = {};

  void refresh() {
    notifyListeners();
  }

  void _bindBackgroundIsolate() {
    if (IsolateNameServer.lookupPortByName('downloader_send_port') != null) {
      IsolateNameServer.removePortNameMapping('downloader_send_port');
    }
    IsolateNameServer.registerPortWithName(_port.sendPort, 'downloader_send_port');

    _port.listen((dynamic data) async {
      try {
        final String taskId = data[0];
        final int statusInt = data[1];
        final int progress = data[2];
        debugPrint('Download callback received: taskId=$taskId, status=$statusInt, progress=$progress');
        final DownloadTaskStatus status = DownloadTaskStatus.values[statusInt];
        _status = _statusFromDownloadStatus(status);
        refresh();

        final taskInfo = _tasks[taskId];
        if (taskInfo != null) {
          final prefs = await SharedPreferences.getInstance();
          final String spKeyDownloading = 'is_downloading_${taskInfo.modelId}';
          final String spKeyDownloaded = 'is_downloaded_${taskInfo.modelId}';

          if (status == DownloadTaskStatus.running || status == DownloadTaskStatus.enqueued) {
            prefs.setBool(spKeyDownloading, true);
            prefs.setBool(spKeyDownloaded, false);
            final notificationId = taskId.hashCode;
            LocalNotificationService.instance.showDownloadProgressNotification(
              notificationId: notificationId,
              title: taskInfo.title,
              progressPercent: progress.toDouble(),
              body: 'Progress: $progress%',
              payload: taskId,
            );
          } else if (status == DownloadTaskStatus.complete) {
            // ... mevcut kod
          } else if (status == DownloadTaskStatus.paused) {
            // ... mevcut kod
          } else if (status == DownloadTaskStatus.failed || status == DownloadTaskStatus.canceled) {
            debugPrint('Download failed or canceled for taskId: $taskId, status: $status');
            prefs.setBool(spKeyDownloading, false);
            prefs.setBool(spKeyDownloaded, false);
            if (!taskInfo.isCancelledByUser) {
              final errorMessage = (status == DownloadTaskStatus.failed) ? 'Download failed' : 'Download canceled';
              final notificationId = taskId.hashCode;
              LocalNotificationService.instance.showSimpleNotification(
                notificationId: notificationId,
                title: NotificationStrings.downloadErrorTitle,
                body: '$errorMessage: ${taskInfo.title}',
                payload: taskId,
              );
            }
            taskInfo.onDownloadError(status == DownloadTaskStatus.failed ? 'Download failed' : 'Download canceled');
            _tasks.remove(taskId);
          }
        }
      } catch (e) {
        debugPrint('Download callback error: $e');
      }
    });
  }

  @override
  void dispose() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    super.dispose();
  }

  static void _downloadCallback(String id, int status, int progress) {
    final SendPort? send = IsolateNameServer.lookupPortByName('downloader_send_port');
    send?.send([id, status, progress]);
  }

  String _statusFromDownloadStatus(DownloadTaskStatus status) {
    switch (status) {
      case DownloadTaskStatus.undefined:
        return 'Tanımsız';
      case DownloadTaskStatus.enqueued:
        return 'Sıraya Alındı';
      case DownloadTaskStatus.running:
        return 'İndiriliyor';
      case DownloadTaskStatus.paused:
        return 'Duraklatıldı';
      case DownloadTaskStatus.complete:
        return 'Tamamlandı';
      case DownloadTaskStatus.canceled:
        return 'İptal Edildi';
      case DownloadTaskStatus.failed:
        return 'İndirilemedi';
      default:
        return 'Bilinmiyor';
    }
  }

  Future<String?> downloadModel({
    required String id,
    required String url,
    required String filePath,
    required String title,
    required Function(String, double) onProgress,
    required Function(String) onDownloadCompleted,
    required Function(String) onDownloadError,
    required Function() onDownloadPaused,
  }) async {
    try {
      _status = 'İndiriliyor';
      refresh();

      final file = File(filePath);
      final savedDir = file.parent.path;
      final fileName = file.uri.pathSegments.last;

      final savedDirPath = Directory(savedDir);
      if (!savedDirPath.existsSync()) {
        savedDirPath.createSync(recursive: true);
      }

      final taskId = await FlutterDownloader.enqueue(
        url: url,
        savedDir: savedDir,
        fileName: fileName,
        showNotification: false,
        openFileFromNotification: false,
      );

      if (taskId != null) {
        _tasks[taskId] = _DownloadTaskInfo(
          modelId: id,
          taskId: taskId,
          title: title,
          filePath: filePath,
          onProgress: onProgress,
          onDownloadCompleted: onDownloadCompleted,
          onDownloadError: onDownloadError,
          onDownloadPaused: onDownloadPaused,
        );
      } else {
        onDownloadError('Download could not be started.');
      }
      return taskId;
    } catch (e) {
      _status = 'İndirilemedi';
      refresh();
      onDownloadError('An error occurred: $e');
      return null;
    }
  }

  Future<void> cancelDownload(String taskId) async {
    debugPrint('Cancelling download for taskId: $taskId');
    try {
      final taskInfo = _tasks[taskId];
      if (taskInfo != null) {
        debugPrint('Task found for taskId: $taskId, modelId: ${taskInfo.modelId}');
        taskInfo.isCancelledByUser = true;
        await FlutterDownloader.cancel(taskId: taskId);
        debugPrint('FlutterDownloader.cancel called for taskId: $taskId');
        LocalNotificationService.instance.cancelNotification(taskId.hashCode);
        final file = File(taskInfo.filePath);
        if (await file.exists()) {
          await file.delete();
        }
        taskInfo.onDownloadError('Download canceled');
        _tasks.remove(taskId);
      } else {
        debugPrint('Task not found for taskId: $taskId');
      }
    } catch (e) {
      debugPrint("İndirme iptal hatası: $e");
    }
  }

  Future<void> removeDownload(String taskId) async {
    try {
      await FlutterDownloader.remove(taskId: taskId, shouldDeleteContent: false);
    } catch (e) {
      debugPrint("Görev kaldırma hatası: $e");
    }
  }

  Future<String?> resumeDownload(String taskId) async {
    final newTaskId = await FlutterDownloader.resume(taskId: taskId);
    if (newTaskId != null) {
      final oldInfo = _tasks.remove(taskId);
      if (oldInfo != null) {
        _tasks[newTaskId] = _DownloadTaskInfo(
          modelId: oldInfo.modelId,
          taskId: newTaskId,
          title: oldInfo.title,
          filePath: oldInfo.filePath,
          onProgress: oldInfo.onProgress,
          onDownloadCompleted: oldInfo.onDownloadCompleted,
          onDownloadError: oldInfo.onDownloadError,
          onDownloadPaused: oldInfo.onDownloadPaused,
        );
      }
      return newTaskId;
    }
    return null;
  }
}

class _DownloadTaskInfo {
  final String modelId;
  final String taskId;
  final String title;
  final String filePath;
  final Function(String, double) onProgress;
  final Function(String) onDownloadCompleted;
  final Function(String) onDownloadError;
  final Function() onDownloadPaused;
  bool isCancelledByUser = false;

  _DownloadTaskInfo({
    required this.modelId,
    required this.taskId,
    required this.title,
    required this.filePath,
    required this.onProgress,
    required this.onDownloadCompleted,
    required this.onDownloadError,
    required this.onDownloadPaused,
  });
}