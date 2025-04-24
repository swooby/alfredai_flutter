import 'package:flutter_dotenv/flutter_dotenv.dart';

class BuildConfig {
  static final String DANGEROUS_OPENAI_API_KEY = dotenv.get('DANGEROUS_OPENAI_API_KEY', fallback: '');
}
