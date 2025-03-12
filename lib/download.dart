import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final SendPort? send = IsolateNameServer.lookupPortByName('downloader_send_port');
  send?.send([id, status, progress]);
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
            // Varsayılan bildirimler flutter_downloader tarafından gösterilecek.
          } else if (status == DownloadTaskStatus.complete) {
            prefs.setBool(spKeyDownloading, false);
            prefs.setBool(spKeyDownloaded, true);
            taskInfo.onDownloadCompleted(taskId);
            _tasks.remove(taskId);
          } else if (status == DownloadTaskStatus.paused) {
            prefs.setBool(spKeyDownloading, false);
            taskInfo.onDownloadPaused();
          } else if (status == DownloadTaskStatus.failed || status == DownloadTaskStatus.canceled) {
            debugPrint('Download failed or canceled for taskId: $taskId, status: $status');
            prefs.setBool(spKeyDownloading, false);
            prefs.setBool(spKeyDownloaded, false);
            if (!taskInfo.isCancelledByUser) {
              // Varsayılan bildirimler flutter_downloader tarafından gösterilecek.
            }
            taskInfo.onDownloadError(
                status == DownloadTaskStatus.failed ? 'Download failed' : 'Download canceled'
            );
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
        showNotification: true, // Varsayılan bildirimler aktif
        openFileFromNotification: true,
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