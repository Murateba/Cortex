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

  /// (1) This client will be used to make requests.
  http.Client? _client;

  ApiService({required this.localizations});

  /// Cancels any ongoing API requests by closing the underlying [http.Client].
  void cancelRequests() {
    _isCancelled = true;
    // (2) Close the client if it exists
    _client?.close();
    _client = null;
  }

  /// Helper method to get MIME type and validate supported types
  Future<String?> _getMimeType(String filePath) async {
    final mimeType = lookupMimeType(filePath);
    if (mimeType == null) return null;

    const supportedTypes = ['image/png', 'image/jpeg', 'image/webp'];
    if (supportedTypes.contains(mimeType)) {
      return mimeType;
    }
    return null;
  }

  /// Helper method to format base64 image with content-type prefix
  Future<String?> _formatBase64Image(String photoPath) async {
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
    List<Map<String, dynamic>> messages = [];

    // Initialize content list
    List<Map<String, dynamic>> contentList = [];

    if (context.isNotEmpty) {
      contentList.add({
        "type": "text",
        "text": context,
      });
    }

    if (userInput.isNotEmpty) {
      contentList.add({
        "type": "text",
        "text": userInput,
      });
    }

    String? formattedBase64Image;
    if (photoPath != null) {
      formattedBase64Image = await _formatBase64Image(photoPath);
      if (formattedBase64Image != null) {
        contentList.add({
          "type": "image_url",
          "image_url": {
            "url": formattedBase64Image,
          },
        });
      }
    }

    // Add the message with content as a list
    messages.add({
      "role": "user",
      "content": contentList,
    });

    // Reset the cancellation flag before starting a new request
    _isCancelled = false;
    String finalContent = '';

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      if (_isCancelled) {
        print("API request was cancelled before sending.");
        return localizations.errorResponseNotReceived;
      }

      try {
        // (3) Create a new Client for each attempt
        _client = http.Client();

        final request = http.Request('POST', Uri.parse(url));
        request.headers.addAll({
          "Authorization": "Bearer $openRouterApiKey",
          "Content-Type": "application/json",
          "Accept": "text/event-stream", // for SSE streaming
        });

        Map<String, dynamic> requestBody = {
          "model": model,
          "stream": true, // SSE (Server-Sent Events) streaming
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
            // (4) Check for cancellation during streaming
            if (_isCancelled) {
              print("API request was cancelled mid-stream.");
              return localizations.errorResponseNotReceived;
            }
            if (line.startsWith("data: ")) {
              final jsonString = line.substring(6).trim();
              if (jsonString == "[DONE]") {
                break; // done streaming
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
        // Check for cancellation
        if (_isCancelled) {
          print("API request cancelled in catch block.");
          return localizations.errorResponseNotReceived;
        }
        // Retry logic
        if (attempt == maxRetries) {
          throw Exception(
            localizations.openRouterApiRequestFailedAfterAttempts(maxRetries, e.toString()),
          );
        }
        // Small delay before retrying
        await Future.delayed(const Duration(seconds: 2));
      } finally {
        // (5) Close the client after each attempt
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
      freeModel: "meta-llama/llama-3.2-3b-instruct:free",
      paidModel: "meta-llama/llama-3.2-3b-instruct",
      userInput: "$role: $userInput",
      context: context,
      photoPath: photoPath, // Pass photoPath
      onStreamChunk: onStreamChunk,
    );
  }

  /// Gets a response from the Gemini model.
  Future<String> getGeminiResponse(
      String userInput,
      String context, {
        String? photoPath, // Added photoPath
        Function(String chunk)? onStreamChunk,
      }) {
    return tryFreeThenPaidModel(
      freeModel: "google/gemini-flash-1.5-exp",
      paidModel: "google/gemini-flash-1.5",
      userInput: userInput,
      context: context,
      photoPath: photoPath, // Pass photoPath
      onStreamChunk: onStreamChunk,
    );
  }

  /// Gets a response from the Llama model.
  Future<String> getLlamaResponse(
      String userInput,
      String context, {
        String? photoPath, // Added photoPath
        Function(String chunk)? onStreamChunk,
      }) {
    return tryFreeThenPaidModel(
      freeModel: "meta-llama/llama-3.1-70b-instruct:free",
      paidModel: "meta-llama/llama-3.3-70b-instruct",
      userInput: userInput,
      context: context,
      photoPath: photoPath, // Pass photoPath
      onStreamChunk: onStreamChunk,
    );
  }

  /// Gets a response from the Hermes model.
  Future<String> getHermesResponse(
      String userInput,
      String context, {
        String? photoPath, // Added photoPath
        Function(String chunk)? onStreamChunk,
      }) {
    return tryFreeThenPaidModel(
      freeModel: "meta-llama/llama-3.1-405b-instruct:free",
      paidModel: "nousresearch/hermes-2-pro-llama-3-8b",
      userInput: userInput,
      context: context,
      photoPath: photoPath, // Pass photoPath
      onStreamChunk: onStreamChunk,
    );
  }

  /// Gets a response from the ChatGPT model.
  Future<String> getChatGPTResponse(
      String userInput,
      String context, {
        String? photoPath, // Added photoPath
        Function(String chunk)? onStreamChunk,
      }) {
    return getResponse(
      userInput: userInput,
      context: context,
      model: "openai/gpt-4o-mini-2024-07-18",
      photoPath: photoPath, // Pass photoPath
      onStreamChunk: onStreamChunk,
      // maxRetries can remain default or be adjusted as needed
    );
  }

  /// Gets a response from the Claude model.
  Future<String> getClaudeResponse(
      String userInput,
      String context, {
        String? photoPath, // Added photoPath
        Function(String chunk)? onStreamChunk,
      }) {
    return getResponse(
      userInput: userInput,
      context: context,
      model: "anthropic/claude-3-haiku",
      photoPath: photoPath, // Pass photoPath
      onStreamChunk: onStreamChunk,
      // maxRetries can remain default or be adjusted as needed
    );
  }

  /// Gets a response from the Nova model.
  Future<String> getNovaResponse(
      String userInput,
      String context, {
        String? photoPath, // Added photoPath
        Function(String chunk)? onStreamChunk,
      }) {
    return getResponse(
      userInput: userInput,
      context: context,
      model: "amazon/nova-lite-v1",
      photoPath: photoPath, // Pass photoPath
      onStreamChunk: onStreamChunk,
    );
  }
}