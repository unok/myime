// Copyright 2024 AzooKey Project.
// All rights reserved.
//
// Engine configuration for switching between Mozc and AzooKey.

#ifndef MOZC_CONVERTER_ENGINE_CONFIG_H_
#define MOZC_CONVERTER_ENGINE_CONFIG_H_

#include <cstdlib>
#include <string>

namespace mozc {

// Engine type enumeration
enum class ConversionEngineType {
  MOZC = 0,     // Default Mozc engine
  AZOOKEY = 1,  // AzooKey engine with Zenzai AI
};

// Get the configured conversion engine type.
// Reads from environment variable MOZC_ENGINE:
//   - "mozc" or "0": Use Mozc engine
//   - "azookey" or "1": Use AzooKey engine (default)
inline ConversionEngineType GetConversionEngineType() {
  const char* engine_env = std::getenv("MOZC_ENGINE");
  if (engine_env != nullptr) {
    std::string engine(engine_env);
    if (engine == "mozc" || engine == "0") {
      return ConversionEngineType::MOZC;
    }
  }
  // Default: AzooKey engine
  return ConversionEngineType::AZOOKEY;
}

// Check if Zenzai AI is enabled for AzooKey engine.
// Reads from environment variable AZOOKEY_ZENZAI_ENABLED:
//   - "true" or "1": Enable Zenzai (default)
//   - "false" or "0": Disable Zenzai
inline bool IsZenzaiEnabled() {
  const char* zenzai_env = std::getenv("AZOOKEY_ZENZAI_ENABLED");
  if (zenzai_env != nullptr) {
    std::string value(zenzai_env);
    if (value == "false" || value == "0") {
      return false;
    }
  }
  // Default: Zenzai enabled
  return true;
}

// Get Zenzai inference limit.
// Reads from environment variable AZOOKEY_ZENZAI_LIMIT.
// Default: 10
inline int GetZenzaiInferenceLimit() {
  const char* limit_env = std::getenv("AZOOKEY_ZENZAI_LIMIT");
  if (limit_env != nullptr) {
    int limit = std::atoi(limit_env);
    if (limit > 0) {
      return limit;
    }
  }
  return 10;  // Default
}

// Get AzooKey dictionary path.
// Reads from environment variable AZOOKEY_DICTIONARY_PATH.
// Default: empty (use built-in dictionary)
inline std::string GetAzooKeyDictionaryPath() {
  const char* path = std::getenv("AZOOKEY_DICTIONARY_PATH");
  return path ? std::string(path) : "";
}

// Get Zenzai weight file path.
// Reads from environment variable AZOOKEY_ZENZAI_WEIGHT_PATH.
// Default: empty
inline std::string GetZenzaiWeightPath() {
  const char* path = std::getenv("AZOOKEY_ZENZAI_WEIGHT_PATH");
  return path ? std::string(path) : "";
}

}  // namespace mozc

#endif  // MOZC_CONVERTER_ENGINE_CONFIG_H_
