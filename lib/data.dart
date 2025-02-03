// model_data.dart
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class ModelData {
  static List<Map<String, dynamic>> models(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context)!;

    return [
      {
        'id': 'tinyllama',
        'title': appLocalizations.modelTinyLlamaTitle,
        'description': appLocalizations.modelTinyLlamaDescription,
        'shortDescription': appLocalizations.modelTinyLlamaShortDescription,
        'url':
        'https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q8_0.gguf?download=true',
        'size': appLocalizations.modelTinyLlamaSize,
        'image': 'assets/tinyllama.png',
        'ram': appLocalizations.modelTinyLlamaRam,
        'producer': appLocalizations.modelTinyLlamaProducer,
        'isServerSide': false,
        'canHandleImage': false,
        'stars': '5stars6/4stars3/3stars4/2stars2/1stars1',
        'features': 'offline'
      },
      {
        'id': 'phi',
        'title': appLocalizations.modelPhiTitle,
        'description': appLocalizations.modelPhiDescription,
        'shortDescription': appLocalizations.modelPhiShortDescription,
        'url':
        'https://huggingface.co/timothyckl/phi-2-instruct-v1/resolve/23d6e417677bc32b1fb4947615acbb616556142a/ggml-model-q4km.gguf?download=true',
        'size': appLocalizations.modelPhiSize,
        'image': 'assets/phi.png',
        'ram': appLocalizations.modelPhiRam,
        'producer': appLocalizations.modelPhiProducer,
        'isServerSide': false,
        'canHandleImage': false,
        'stars': '5stars6/4stars4/3stars2/2stars1/1stars2'
      },
      {
        'id': 'qwen',
        'title': appLocalizations.modelQwen2AudioTitle,
        'description': appLocalizations.modelQwen2AudioDescription,
        'shortDescription': appLocalizations.modelQwen2AudioShortDescription,
        'url':
        'https://huggingface.co/NexaAIDev/Qwen2-Audio-7B-GGUF/resolve/main/qwen2-audio-7b.Q4_K.gguf?download=true',
        'size': '4.5 GB',
        'image': 'assets/qwen.png',
        'ram': '6 GB RAM',
        'producer': 'Nexa AI',
        'isServerSide': false,
        'canHandleImage': false,
        'canHandleMusic': true,
        'stars': '5stars8/4stars5/3stars2/2stars1/1stars4'
      },
      {
        'id': 'mistral',
        'title': appLocalizations.modelMistralTitle,
        'description': appLocalizations.modelMistralDescription,
        'shortDescription': appLocalizations.modelMistralShortDescription,
        'url':
        'https://huggingface.co/sayhan/Mistral-7B-Instruct-v0.2-turkish-GGUF/resolve/main/mistral-7b-instruct-v0.2-turkish.Q5_K_M.gguf?download=true',
        'size': appLocalizations.modelMistralSize,
        'image': 'assets/mistral.png',
        'ram': appLocalizations.modelMistralRam,
        'producer': appLocalizations.modelMistralProducer,
        'isServerSide': false,
        'canHandleImage': false,
        'stars': '5stars6/4stars5/3stars4/2stars4/1stars2'
      },
      {
        'id': 'gemma',
        'title': appLocalizations.modelGemmaTitle,
        'description': appLocalizations.modelGemmaDescription,
        'shortDescription': appLocalizations.modelGemmaShortDescription,
        'url':
        'https://huggingface.co/ggml-org/gemma-1.1-7b-it-Q4_K_M-GGUF/resolve/main/gemma-1.1-7b-it.Q4_K_M.gguf?download=true',
        'size': appLocalizations.modelGemmaSize,
        'image': 'assets/gemma.png',
        'ram': appLocalizations.modelGemmaRam,
        'producer': appLocalizations.modelGemmaProducer,
        'isServerSide': false,
        'canHandleImage': false,
        'stars': '5stars7/4stars3/3stars2/2stars1/1stars3'
      },
      {
        'id': 'gptneox',
        'title': appLocalizations.modelGPTNeoXTitle,
        'description': appLocalizations.modelGPTNeoXDescription,
        'shortDescription': appLocalizations.modelGPTNeoXShortDescription,
        'url':
        'https://huggingface.co/zhentaoyu/gpt-neox-20b-Q4_0-GGUF/resolve/main/gpt-neox-20b-q4_0.gguf',
        'size': appLocalizations.modelGPTNeoXSize,
        'image': 'assets/gptneox.jpg',
        'ram': appLocalizations.modelGPTNeoXRam,
        'producer': appLocalizations.modelGPTNeoXProducer,
        'isServerSide': false,
        'canHandleImage': false,
        'features': 'supermodel',
        'stars': '5stars8/4stars6/3stars2/2stars3/1stars3',
        },
        {
        'id': 'gemini',
        'title': 'Gemini',
        'description': appLocalizations.modelGeminiDescription,
        'shortDescription': appLocalizations.modelGeminiShortDescription,
        'image': 'assets/gemini.png',
        'producer': 'Google',
        'isServerSide': true,
        'canHandleImage': false,
        'features': 'supermodel',
        'parameters': '100 ${appLocalizations.billions}',
        'context': '2 ${appLocalizations.millions}',
        'stars': '5stars10/4stars8/3stars2/2stars1/1stars2'
        },
      {
        'id': 'llama',
        'title': 'Llama',
        'description': appLocalizations.modelLlamaDescription,
        'shortDescription': appLocalizations.modelLlamaShortDescription,
        'image': 'assets/llama.png',
        'producer': 'Meta',
        'isServerSide': true,
        'canHandleImage': false,
        'features': 'supermodel',
        'parameters': '70 ${appLocalizations.billions}',
        'context': '4096',
        'stars': '5stars150/4stars120/3stars20/2stars5/1stars2'
      },
      {
        'id': 'hermes',
        'title': 'Hermes',
        'description': appLocalizations.modelHermesDescription,
        'shortDescription': appLocalizations.modelHermesShortDescription,
        'image': 'assets/hermes.jpg',
        'producer': 'Nous Research',
        'isServerSide': true,
        'features': 'supermodel',
        'parameters': '50 ${appLocalizations.billions}',
        'context': '131 ${appLocalizations.thousand}',
        'stars': '5stars135/4stars105/3stars25/2stars10/1stars4',
        'canHandleImage': true,
      },
      {
        'id': 'chatgpt4omini',
        'title': 'GPT 4o-Mini',
        'description': appLocalizations.modelChatGPT4oMiniDescription,
        'shortDescription': appLocalizations.modelChatGPT4oMiniShortDescription,
        'image': 'assets/chatgpt.jpg',
        'producer': 'OpenAI',
        'isServerSide': true,
        'stars': '5stars10/4stars8/3stars2/2stars1/1stars1',
        'features': 'photo/supermodel',
        'canHandleImage': true,
        'parameters': '2 ${appLocalizations.trillions}',
        'context': '128 ${appLocalizations.thousand}', // Estimated
      },
      {
        'id': 'claude3haiku',
        'title': 'Claude 3 Haiku',
        'description': appLocalizations.modelClaude3HaikuDescription,
        'shortDescription': appLocalizations.modelClaude3HaikuShortDescription,
        'image': 'assets/claude.jpg',
        'producer': 'Anthropic',
        'isServerSide': true,
        'canHandleImage': false,
        'features': 'supermodel',
        'parameters': '52 ${appLocalizations.billions}',
        'context': '200 ${appLocalizations.thousand}', // Estimated
        'stars': '5stars10/4stars6/3stars1/2stars2/1stars3'
      },
      {
        'id': 'amazonnovalite',
        'title': 'Nova Lite',
        'description': appLocalizations.modelAmazonNovaLiteDescription,
        'shortDescription': appLocalizations.modelAmazonNovaLiteShortDescription,
        'image': 'assets/nova.jpg',
        'producer': 'Amazon',
        'isServerSide': true,
        'canHandleImage': false,
        'features': 'supermodel',
        'parameters': '50 ${appLocalizations.billions}',
        'context': '300 ${appLocalizations.thousand}', // Estimated
        'stars': '5stars120/4stars100/3stars20/2stars8/1stars3'
      },
      {
        'id': 'teacher',
        'title': appLocalizations.modelTeacherTitle,
        'shortDescription': appLocalizations.modelTeacherShortDescription,
        'description': appLocalizations.modelTeacherDescription,
        'image': 'assets/teacher.png',
        'producer': 'Vertex',
        'role': appLocalizations.modelTeacherRole,
        'isServerSide': true,
        'category': 'roleplay',
        'parameters': '20 ${appLocalizations.billions}',
        'context': '4096',
        'stars': '5stars95/4stars85/3stars50/2stars20/1stars10'
      },
      {
        'id': 'doctor',
        'title': appLocalizations.modelDoctorTitle,
        'shortDescription': appLocalizations.modelDoctorShortDescription,
        'description': appLocalizations.modelDoctorDescription,
        'image': 'assets/doctor.png',
        'producer': 'Vertex',
        'role': appLocalizations.modelDoctorRole,
        'isServerSide': true,
        'category': 'roleplay',
        'parameters': '20 ${appLocalizations.billions}',
        'context': '4096',
        'stars': '5stars115/4stars95/3stars40/2stars15/1stars5'
      },
      {
        'id': 'animegirl',
        'title': appLocalizations.modelAnimeGirlTitle,
        'shortDescription': appLocalizations.modelAnimeGirlShortDescription,
        'description': appLocalizations.modelAnimeGirlDescription,
        'image': 'assets/animegirl.jpg',
        'producer': 'Vertex',
        'role': appLocalizations.modelAnimeGirlRole,
        'isServerSide': true,
        'category': 'roleplay',
        'parameters': '20 ${appLocalizations.billions}',
        'context': '4096',
        'stars': '5stars110/4stars100/3stars30/2stars10/1stars3'
      },
      {
        'id': 'shaver',
        'title': appLocalizations.modelShaverTitle,
        'shortDescription': appLocalizations.modelShaverShortDescription,
        'description': appLocalizations.modelShaverDescription,
        'image': 'assets/shaver.png',
        'producer': 'Vertex',
        'role': appLocalizations.modelShaverRole,
        'isServerSide': true,
        'category': 'roleplay',
        'parameters': '20 ${appLocalizations.billions}',
        'context': '4096', // Estimated
        'stars': '5stars100/4stars85/3stars35/2stars10/1stars5'
      },
      {
        'id': 'psychologist',
        'title': appLocalizations.modelPsychologistTitle,
        'shortDescription': appLocalizations.modelPsychologistShortDescription,
        'description': appLocalizations.modelPsychologistDescription,
        'image': 'assets/psychologist.png',
        'producer': 'Vertex',
        'role': appLocalizations.modelPsychologistRole,
        'isServerSide': true,
        'category': 'roleplay',
        'parameters': '20 ${appLocalizations.billions}',
        'context': '4096', // Estimated
        'stars': '5stars125/4stars105/3stars20/2stars8/1stars3'
      },
      {
        'id': 'mrbeast',
        'title': appLocalizations.modelMrBeastTitle,
        'shortDescription': appLocalizations.modelMrBeastShortDescription,
        'description': appLocalizations.modelMrBeastDescription,
        'image': 'assets/mrbeast.jpg',
        'producer': 'Vertex',
        'role': appLocalizations.modelMrBeastRole,
        'isServerSide': true,
        'category': 'roleplay',
        'parameters': '20 ${appLocalizations.billions}',
        'context': '4096', // Estimated
        'stars': '5stars140/4stars120/3stars10/2stars3/1stars1'
      },
    ];
  }
}