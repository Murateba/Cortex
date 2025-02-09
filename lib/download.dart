// download.dart
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FileDownloadHelper extends ChangeNotifier {
  // Singleton örneği
  static final FileDownloadHelper _instance = FileDownloadHelper._internal();
  factory FileDownloadHelper() => _instance;
  FileDownloadHelper._internal() {
    _bindBackgroundIsolate();
    FlutterDownloader.registerCallback(_downloadCallback);
  }

  String _status = 'İndirilemedi';
  String get status => _status;

  final ReceivePort _port = ReceivePort();

  // Görevleri (tasks) takip ediyoruz.
  final Map<String, _DownloadTaskInfo> _tasks = {};

  /// Dışarıdan çağırarak provider dinleyicilerini tetiklemek için public refresh metodu.
  void refresh() {
    notifyListeners();
  }

  void _bindBackgroundIsolate() {
    // Var olan port mapping varsa kaldırıp yeniden kayıt yapıyoruz.
    if (IsolateNameServer.lookupPortByName('downloader_send_port') != null) {
      IsolateNameServer.removePortNameMapping('downloader_send_port');
    }
    IsolateNameServer.registerPortWithName(_port.sendPort, 'downloader_send_port');

    _port.listen((dynamic data) async {
      try {
        final String taskId = data[0];
        final int statusInt = data[1];
        final int progress = data[2];

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
          } else if (status == DownloadTaskStatus.complete) {
            prefs.setBool(spKeyDownloading, false);
            prefs.setBool(spKeyDownloaded, true);
          } else if (status == DownloadTaskStatus.paused) {
            prefs.setBool(spKeyDownloading, false);
          } else if (status == DownloadTaskStatus.failed || status == DownloadTaskStatus.canceled) {
            prefs.setBool(spKeyDownloading, false);
            prefs.setBool(spKeyDownloaded, false);
          }

          // Yerel callback’leri tetikliyoruz.
          if (status == DownloadTaskStatus.running) {
            taskInfo.onProgress(taskInfo.title, progress.toDouble());
          } else if (status == DownloadTaskStatus.complete) {
            taskInfo.onDownloadCompleted(taskInfo.filePath);
            _tasks.remove(taskId);
          } else if (status == DownloadTaskStatus.failed || status == DownloadTaskStatus.canceled) {
            // canceled durumunu da burada işliyoruz:
            final errorMessage = (status == DownloadTaskStatus.failed)
                ? 'Download failed'
                : 'Download canceled';
            taskInfo.onDownloadError(errorMessage);
            _tasks.remove(taskId);
          } else if (status == DownloadTaskStatus.paused) {
            taskInfo.onDownloadPaused();
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
    final SendPort? send =
    IsolateNameServer.lookupPortByName('downloader_send_port');
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
        return 'Durduruldu';
      case DownloadTaskStatus.complete:
        return 'İndirildi';
      case DownloadTaskStatus.canceled:
        return 'İptal Edildi';
      case DownloadTaskStatus.failed:
        return 'İndirilemedi';
      default:
        return 'Bilinmiyor';
    }
  }

  Future<String?> downloadModel({
    required String id, // modelin ID’si
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
        showNotification: true,
        openFileFromNotification: false,
      );

      if (taskId != null) {
        // İlgili bilgileri saklıyoruz.
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
    await FlutterDownloader.cancel(taskId: taskId);
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
  final String modelId; // SharedPreferences için anahtar
  final String taskId;
  final String title;
  final String filePath;
  final Function(String, double) onProgress;
  final Function(String) onDownloadCompleted;
  final Function(String) onDownloadError;
  final Function() onDownloadPaused;

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