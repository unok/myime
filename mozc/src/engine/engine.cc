// Copyright 2010-2021, Google Inc.
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//     * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//     * Neither the name of Google Inc. nor the names of its
// contributors may be used to endorse or promote products derived from
// this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#include "engine/engine.h"

#include <cstdlib>
#include <cstring>
#include <memory>
#include <utility>

#include "absl/log/check.h"
#include "absl/log/log.h"

// Debug logging to file using Windows API
#ifdef _WIN32
#include <windows.h>
#endif

namespace {
void EngineDebugLog(const char* message) {
#ifdef _WIN32
  // Output to Windows debug output (viewable with DebugView)
  OutputDebugStringA("[MozcEngine] ");
  OutputDebugStringA(message);
  OutputDebugStringA("\n");

  // Also try to write to temp file
  char tempPath[MAX_PATH];
  if (GetTempPathA(MAX_PATH, tempPath) > 0) {
    strcat_s(tempPath, MAX_PATH, "azookey-engine-debug.log");
    HANDLE hFile = CreateFileA(
        tempPath,
        FILE_APPEND_DATA,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        NULL,
        OPEN_ALWAYS,
        FILE_ATTRIBUTE_NORMAL,
        NULL);
    if (hFile != INVALID_HANDLE_VALUE) {
      DWORD written;
      WriteFile(hFile, message, (DWORD)strlen(message), &written, NULL);
      WriteFile(hFile, "\r\n", 2, &written, NULL);
      CloseHandle(hFile);
    }
  }
#endif
}

void EngineDebugLog(const std::string& message) {
  EngineDebugLog(message.c_str());
}
}  // namespace
#include "absl/status/status.h"
#include "absl/status/statusor.h"
#include "absl/strings/string_view.h"
#include "converter/converter.h"
#include "converter/converter_interface.h"
#include "converter/immutable_converter.h"
#include "converter/immutable_converter_interface.h"
#include "converter/azookey_immutable_converter.h"
#include "converter/engine_config.h"
#include "data_manager/data_manager.h"
#include "dictionary/user_dictionary_session_handler.h"
#include "engine/data_loader.h"
#include "engine/minimal_converter.h"
#include "engine/modules.h"
#include "engine/supplemental_model_interface.h"
#include "prediction/predictor.h"
#include "protocol/engine_builder.pb.h"
#include "protocol/user_dictionary_storage.pb.h"
#include "rewriter/rewriter.h"
#include "rewriter/rewriter_interface.h"

namespace mozc {

absl::StatusOr<std::unique_ptr<Engine>> Engine::CreateEngine(
    std::unique_ptr<const DataManager> data_manager) {
  absl::StatusOr<std::unique_ptr<engine::Modules>> modules_status =
      engine::Modules::Create(std::move(data_manager));
  if (!modules_status.ok()) {
    return modules_status.status();
  }
  return CreateEngine(std::move(modules_status.value()));
}

absl::StatusOr<std::unique_ptr<Engine>> Engine::CreateEngine(
    std::unique_ptr<engine::Modules> modules) {
  auto engine = std::make_unique<Engine>();
  absl::Status engine_status = engine->Init(std::move(modules));
  if (!engine_status.ok()) {
    return engine_status;
  }
  return engine;
}

std::unique_ptr<Engine> Engine::CreateEngine() {
  return std::make_unique<Engine>();
}

Engine::Engine() : minimal_converter_(CreateMinimalConverter()) {}

absl::Status Engine::ReloadModules(std::unique_ptr<engine::Modules> modules) {
  ReloadAndWait();
  return Init(std::move(modules));
}

absl::Status Engine::Init(std::unique_ptr<engine::Modules> modules) {
  EngineDebugLog("=== Engine::Init called ===");

  // Select conversion engine based on configuration
  auto immutable_converter_factory = [](const engine::Modules& modules)
      -> std::unique_ptr<const ImmutableConverterInterface> {
    EngineDebugLog("immutable_converter_factory called");
    auto engine_type = GetConversionEngineType();
    EngineDebugLog(std::string("Engine type: ") +
                   (engine_type == ConversionEngineType::AZOOKEY ? "AZOOKEY" : "MOZC"));

    if (engine_type == ConversionEngineType::AZOOKEY) {
      EngineDebugLog("Attempting to create AzooKey converter");
      // Use AzooKey engine with Zenzai AI
      AzooKeyConfig config;
      config.dictionary_path = GetAzooKeyDictionaryPath();
      config.zenzai_enabled = IsZenzaiEnabled();
      config.zenzai_inference_limit = GetZenzaiInferenceLimit();
      config.zenzai_weight_path = GetZenzaiWeightPath();

      EngineDebugLog(std::string("Zenzai enabled: ") + (config.zenzai_enabled ? "true" : "false"));

      auto azookey_converter = CreateAzooKeyImmutableConverter(config);
      if (azookey_converter) {
        EngineDebugLog("AzooKey converter created successfully");
        LOG(INFO) << "Using AzooKey conversion engine with Zenzai="
                  << (config.zenzai_enabled ? "enabled" : "disabled");
        return azookey_converter;
      }
      EngineDebugLog("Failed to create AzooKey converter, falling back to Mozc");
      LOG(WARNING) << "Failed to create AzooKey converter, falling back to Mozc";
    }
    // Use standard Mozc engine
    EngineDebugLog("Using Mozc conversion engine");
    LOG(INFO) << "Using Mozc conversion engine";
    return std::make_unique<ImmutableConverter>(modules);
  };

  auto predictor_factory =
      [](const engine::Modules& modules, const ConverterInterface& converter,
         const ImmutableConverterInterface& immutable_converter) {
        return std::make_unique<prediction::Predictor>(modules, converter,
                                                       immutable_converter);
      };

  auto rewriter_factory = [](const engine::Modules& modules) {
    return std::make_unique<Rewriter>(modules);
  };

  auto converter = std::make_shared<converter::Converter>(
      std::move(modules), immutable_converter_factory, predictor_factory,
      rewriter_factory);

  if (!converter) {
    return absl::ResourceExhaustedError("engine.cc: converter_ is null");
  }

  converter_ = std::move(converter);

  return absl::OkStatus();
}

bool Engine::Reload() { return converter_ && converter_->Reload(); }

bool Engine::Sync() { return converter_ && converter_->Sync(); }

bool Engine::Wait() { return converter_ && converter_->Wait(); }

bool Engine::ReloadAndWait() { return Reload() && Wait(); }

bool Engine::ClearUserHistory() {
  if (converter_) {
    converter_->rewriter().Clear();
  }
  return true;
}

bool Engine::ClearUserPrediction() {
  return converter_ && converter_->predictor().ClearAllHistory();
}

bool Engine::ClearUnusedUserPrediction() {
  return converter_ && converter_->predictor().ClearUnusedHistory();
}

bool Engine::MaybeReloadEngine(EngineReloadResponse* response) {
  if (!converter_ || always_wait_for_testing_) {
    loader_.Wait();
  }

  if (loader_.IsRunning() || !loader_response_) {
    return false;
  }

  *response = std::move(loader_response_->response);

  const absl::Status reload_status =
      ReloadModules(std::move(loader_response_->modules));
  if (reload_status.ok()) {
    response->set_status(EngineReloadResponse::RELOADED);
  }
  loader_response_.reset();

  return reload_status.ok();
}

bool Engine::SendEngineReloadRequest(const EngineReloadRequest& request) {
  return loader_.StartNewDataBuildTask(
      request, [this](std::unique_ptr<DataLoader::Response> response) {
        loader_response_ = std::move(response);
        return absl::OkStatus();
      });
}

bool Engine::SendSupplementalModelReloadRequest(
    const EngineReloadRequest& request) {
  if (converter_) {
    converter_->modules().GetSupplementalModel().LoadAsync(request);
  }
  return true;
}

bool Engine::EvaluateUserDictionaryCommand(
    const user_dictionary::UserDictionaryCommand& command,
    user_dictionary::UserDictionaryCommandStatus* status) {
  return user_dictionary_session_handler_.Evaluate(command, status);
}

}  // namespace mozc
