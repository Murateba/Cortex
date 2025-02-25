// ================ api.dart ================
import 'dart:convert';
import 'dart:async';
import 'dart:io'; // For File operations
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:mime/mime.dart'; // For determining MIME types

class QuotaExceededException implements Exception {
  final String message;
  QuotaExceededException(this.message);

  @override
  String toString() => message;
}

class ApiService {
  final String openRouterApiKey = dotenv.env['API_KEY'] ?? '';
  final AppLocalizations localizations;

  bool _isCancelled = false;
  http.Client? _client;

  ApiService({required this.localizations});

  void cancelRequests() {
    _isCancelled = true;
    _client?.close();
    _client = null;
  }

  Future<String?> _getMimeType(String filePath) async {
    final mimeType = lookupMimeType(filePath);
    if (mimeType == null) return null;

    const supportedTypes = ['image/png', 'image/jpeg', 'image/webp'];
    return supportedTypes.contains(mimeType) ? mimeType : null;
  }

  Future<String?> formatBase64Image(String photoPath) async {
    try {
      File imageFile = File(photoPath);
      if (await imageFile.exists()) {
        List<int> imageBytes = await imageFile.readAsBytes();
        String base64Image = base64Encode(imageBytes);
        String? mimeType = await _getMimeType(photoPath);
        if (mimeType == null) {
          print("Unsupported image type for file: $photoPath");
          return null;
        }
        return 'data:$mimeType;base64,$base64Image';
      } else {
        print("Photo file does not exist at path: $photoPath");
        return null;
      }
    } catch (e) {
      print("Error reading photo file: $e");
      return null;
    }
  }

  Future<String> getResponse({
    required String userInput,
    required String context,
    required String model,
    String? photoPath,
    Function(String chunk)? onStreamChunk,
    int maxRetries = 1,
  }) async {
    const String url = "https://openrouter.ai/api/v1/chat/completions";

    // Mesaj içeriğini liste halinde oluşturuyoruz.
    List<Map<String, dynamic>> contentList = [];

    // Context (örneğin, önceki konuşma) metni:
    if (context.isNotEmpty) {
      contentList.add({
        "type": "text",
        "text": context,
      });
    }

    // Kullanıcının mevcut girişi:
    if (userInput.isNotEmpty) {
      contentList.add({
        "type": "text",
        "text": userInput,
      });
    }

    // Eğer fotoğraf varsa, doğru görsel mesaj formatında ekleyelim.
    if (photoPath != null) {
      String? formattedBase64Image = await formatBase64Image(photoPath);
      if (formattedBase64Image != null) {
        contentList.add({
          "type": "image_url",
          "image_url": {"url": formattedBase64Image},
        });
      }
    }

    // Mesajlar listesini oluştururken "content" artık bir liste:
    List<Map<String, dynamic>> messages = [
      {
        "role": "user",
        "content": contentList,
      }
    ];

    _isCancelled = false;
    String finalContent = '';

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      if (_isCancelled) {
        print("API request was cancelled before sending.");
        return localizations.errorResponseNotReceived;
      }

      try {
        _client = http.Client();
        final request = http.Request('POST', Uri.parse(url));
        request.headers.addAll({
          "Authorization": "Bearer $openRouterApiKey",
          "Content-Type": "application/json",
          "Accept": "text/event-stream", // for SSE streaming
        });

        Map<String, dynamic> requestBody = {
          "model": model,
          "stream": true, // SSE streaming enabled
          "messages": messages,
        };

        request.body = jsonEncode(requestBody);
        final streamedResponse = await _client!.send(request);
        print(localizations.openRouterResponseStatus(streamedResponse.statusCode));

        if (streamedResponse.statusCode == 200) {
          final lines = streamedResponse.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter());

          finalContent = '';
          await for (var line in lines) {
            if (_isCancelled) {
              print("API request was cancelled mid-stream.");
              return localizations.errorResponseNotReceived;
            }
            if (line.startsWith("data: ")) {
              final jsonString = line.substring(6).trim();
              if (jsonString == "[DONE]") {
                break; // End of streaming
              }
              try {
                final Map<String, dynamic> event = jsonDecode(jsonString);
                var content = event['choices']?[0]['delta']?['content'];
                if (content != null && content is String) {
                  finalContent += content;
                  if (onStreamChunk != null) {
                    onStreamChunk(content);
                  }
                }
              } catch (e) {
                print("Stream JSON parse error: $e");
              }
            }
          }

          if (finalContent.isNotEmpty) {
            return finalContent;
          } else {
            throw Exception(localizations.responseStructureUnexpectedMessageContentMissing);
          }
        } else if (streamedResponse.statusCode == 429) {
          final decodedBody = await streamedResponse.stream.bytesToString();
          throw QuotaExceededException(
            localizations.openRouterQuotaExceeded(streamedResponse.statusCode, decodedBody),
          );
        } else {
          final decodedBody = await streamedResponse.stream.bytesToString();
          throw Exception(
            localizations.openRouterApiRequestFailed(streamedResponse.statusCode, decodedBody),
          );
        }
      } catch (e) {
        if (_isCancelled) {
          print("API request cancelled in catch block.");
          return localizations.errorResponseNotReceived;
        }
        if (attempt == maxRetries) {
          throw Exception(
            localizations.openRouterApiRequestFailedAfterAttempts(maxRetries, e.toString()),
          );
        }
        await Future.delayed(const Duration(seconds: 2));
      } finally {
        _client?.close();
        _client = null;
      }
    }

    return localizations.errorResponseNotReceived;
  }


  /// Attempts to use a free model first, and if it fails (e.g., due to quota), switches to a paid model.
  ///
  /// If [photoPath] is provided, it's passed to the [getResponse] method.
  Future<String> tryFreeThenPaidModel({
    required String freeModel,
    required String paidModel,
    required String userInput,
    required String context,
    String? photoPath, // Added photoPath
    Function(String chunk)? onStreamChunk,
  }) async {
    try {
      return await getResponse(
        userInput: userInput,
        context: context,
        model: freeModel,
        photoPath: photoPath,
        onStreamChunk: onStreamChunk,
        maxRetries: 1, // One attempt for free model
      );
    } catch (error) {
      print("Free model failed: $error");
      for (int attempt = 1; attempt <= 2; attempt++) { // Two attempts for paid models
        if (_isCancelled) {
          print("API request was cancelled.");
          return localizations.errorResponseNotReceived;
        }
        try {
          print("Attempting with paid model, attempt $attempt...");
          return await getResponse(
            userInput: userInput,
            context: context,
            model: paidModel,
            photoPath: photoPath,
            onStreamChunk: onStreamChunk,
            // maxRetries can remain default or be adjusted as needed
          );
        } catch (paidError) {
          print("Paid model attempt $attempt failed: $paidError");
          if (attempt == 2) {
            throw Exception(
              localizations.openRouterApiRequestFailedAfterPaidAttempts(2, paidError.toString()),
            );
          }
        }
      }
    }
    throw Exception(localizations.errorResponseNotReceived);
  }

  /// Gets a response from a character-based model.
  Future<String> getCharacterResponse({
    required String role,
    required String userInput,
    required String context,
    String? photoPath, // Added photoPath
    Function(String chunk)? onStreamChunk,
  }) {
    return tryFreeThenPaidModel(
      freeModel: "google/gemini-2.0-flash-exp:free",
      paidModel: "google/gemini-2.0-flash-001",
      userInput: "$role: $userInput",
      context: context,
      photoPath: photoPath, // Pass photoPath
      onStreamChunk: onStreamChunk,
    );
  }

  Future<String> getGeminiResponse(
      String userInput,
      String context, {
        String? photoPath,
        Function(String chunk)? onStreamChunk,
        required String model,
      }) {
    if (model.toLowerCase() == 'gemini-flash-2.0') {
      return tryFreeThenPaidModel(
        freeModel: 'google/gemini-2.0-flash-exp:free',
        paidModel: 'google/gemini-2.0-flash-001',
        userInput: userInput,
        context: context,
        photoPath: photoPath,
        onStreamChunk: onStreamChunk,
      );
    } else if (model.toLowerCase() == 'gemini-flash-1.5') {
      return tryFreeThenPaidModel(
        freeModel: 'google/gemini-flash-1.5-8b-exp',
        paidModel: 'google/gemini-flash-1.5',
        userInput: userInput,
        context: context,
        photoPath: photoPath,
        onStreamChunk: onStreamChunk,
      );
    } else {
      return getResponse(
        userInput: userInput,
        context: context,
        model: 'google/gemini-pro-vision',
        photoPath: photoPath,
        onStreamChunk: onStreamChunk,
      );
    }
  }

  Future<String> getLlamaResponse(
      String userInput,
      String context, {
        String? photoPath,
        Function(String chunk)? onStreamChunk,
        required String model,
      }) {
    if (model.toLowerCase() == 'llama-3.1-405b') {
      return getResponse(
        userInput: userInput,
        context: context,
        model: 'meta-llama/llama-3.1-405b-instruct',
        photoPath: photoPath,
        onStreamChunk: onStreamChunk,
      );
    } else if (model.toLowerCase() == 'llama-3.2-11b-vision') {
      return tryFreeThenPaidModel(
        freeModel: 'meta-llama/llama-3.2-11b-vision-instruct:free',
        paidModel: 'meta-llama/llama-3.2-11b-vision-instruct',
        userInput: userInput,
        context: context,
        photoPath: photoPath,
        onStreamChunk: onStreamChunk,
      );
    } else {
      return tryFreeThenPaidModel(
        freeModel: 'meta-llama/llama-3.3-70b-instruct:free',
        paidModel: 'meta-llama/llama-3.3-70b-instruct',
        userInput: userInput,
        context: context,
        photoPath: photoPath,
        onStreamChunk: onStreamChunk,
      );
    }
  }

  /// Gets a response from the Hermes model.
  Future<String> getHermesResponse(
      String userInput,
      String context, {
        String? photoPath,
        Function(String chunk)? onStreamChunk,
        required String model,
      }) {
    if (model.toLowerCase() == 'hermes-3-70b') {
      return getResponse(
        userInput: userInput,
        context: context,
        model: 'nousresearch/hermes-3-llama-3.1-70b',
        photoPath: photoPath,
        onStreamChunk: onStreamChunk,
      );
    } else {
      return getResponse(
        userInput: userInput,
        context: context,
        model: 'nnousresearch/hermes-3-llama-3.1-405b',
        photoPath: photoPath,
        onStreamChunk: onStreamChunk,
      );
    }
  }

  Future<String> getChatGPTResponse(
      String userInput,
      String context, {
        String? photoPath, // Resim yolu (opsiyonel)
        Function(String chunk)? onStreamChunk,
        required String model,
      }) {
    String targetModel = model.toLowerCase() == 'chatgpt-4o-mini'
        ? 'openai/gpt-4o-mini'
        : model.toLowerCase() == 'chatgpt-3.5-turbo'
        ? 'openai/gpt-3.5-turbo'
        : model;

    return getResponse(
      userInput: userInput,
      context: context,
      model: targetModel,
      photoPath: photoPath,
      onStreamChunk: onStreamChunk,
    );
  }

  /// Gets a response from the Claude model.
  Future<String> getClaudeResponse(
      String userInput,
      String context, {
        String? photoPath,
        Function(String chunk)? onStreamChunk,
        required String model,
      }) {
    if (model.toLowerCase() == 'claude-3.5-haiku') {
      return getResponse(
        userInput: userInput,
        context: context,
        model: 'anthropic/claude-3.5-haiku-20241022',
        photoPath: photoPath,
        onStreamChunk: onStreamChunk,
      );
    } else {
      return getResponse(
        userInput: userInput,
        context: context,
        model: 'anthropic/claude-3.5-haiku-20241022',
        photoPath: photoPath,
        onStreamChunk: onStreamChunk,
      );
    }
  }

  /// Gets a response from the Nova model.
  Future<String> getNovaResponse(
      String userInput,
      String context, {
        String? photoPath,
        Function(String chunk)? onStreamChunk,
        required String model,
      }) {
    if (model.toLowerCase() == 'lite-1.0') {
      return getResponse(
        userInput: userInput,
        context: context,
        model: 'amazon/nova-lite-v1',
        photoPath: photoPath,
        onStreamChunk: onStreamChunk,
      );
    }
    else if (model.toLowerCase() == 'micro-1.0') {
      return getResponse(
        userInput: userInput,
        context: context,
        model: 'amazon/nova-micro-v1',
        photoPath: photoPath,
        onStreamChunk: onStreamChunk,
      );
    } else {
      return getResponse(
        userInput: userInput,
        context: context,
        model: 'amazon/nova-pro-v1',
        photoPath: photoPath,
        onStreamChunk: onStreamChunk,
      );
    }
  }

  Future<String> getDeepseekResponse(
      String userInput,
      String context, {
        String? photoPath,
        Function(String chunk)? onStreamChunk,
        required String model,
      }) {
    if (model.toLowerCase() == 'deepseek-v3') {
      return tryFreeThenPaidModel(
        freeModel: 'meta-llama/llama-3.3-70b-instruct:free',
        paidModel: 'meta-llama/llama-3.3-70b-instruct',
        userInput: userInput,
        context: context,
        photoPath: photoPath,
        onStreamChunk: onStreamChunk,
      );
    } else {
      return tryFreeThenPaidModel(
        freeModel: 'meta-llama/llama-3.3-70b-instruct:free',
        paidModel: 'meta-llama/llama-3.3-70b-instruct',
        userInput: userInput,
        context: context,
        photoPath: photoPath,
        onStreamChunk: onStreamChunk,
      );
    }
  }

  Future<String> getGrokResponse(
      String userInput,
      String context, {
        String? photoPath,
        Function(String chunk)? onStreamChunk,
        required String model,
      }) {
    if (model.toLowerCase() == 'grok-2') {
      return getResponse(
        userInput: userInput,
        context: context,
        model: 'x-ai/grok-2',
        photoPath: photoPath,
        onStreamChunk: onStreamChunk,
      );
    } else {
      return getResponse(
        userInput: userInput,
        context: context,
        model: 'x-ai/grok-2',
        photoPath: photoPath,
        onStreamChunk: onStreamChunk,
      );
    }
  }

  Future<String> getQwenResponse(
      String userInput,
      String context, {
        String? photoPath,
        Function(String chunk)? onStreamChunk,
        required String model,
      }) {
    if (model.toLowerCase() == 'ԛwen-turbo') {
      return getResponse(
        userInput: userInput,
        context: context,
        model: 'qwen/qwen-turbo',
        photoPath: photoPath,
        onStreamChunk: onStreamChunk,
      );
    }
    else if (model.toLowerCase() == '2-vl-72b') {
      return getResponse(
        userInput: userInput,
        context: context,
        model: 'qwen/qwen-2-vl-72b-instruct',
        photoPath: photoPath,
        onStreamChunk: onStreamChunk,
      );
    }
    else if (model.toLowerCase() == 'ԛwen-plus') {
      return getResponse(
        userInput: userInput,
        context: context,
        model: 'qwen/qwen-plus',
        photoPath: photoPath,
        onStreamChunk: onStreamChunk,
      );
    } else {
      return getResponse(
        userInput: userInput,
        context: context,
        model: 'qwen/qvq-72b-preview',
        photoPath: photoPath,
        onStreamChunk: onStreamChunk,
      );
    }
  }
}