// Copyright 2024 AzooKey Project.
// All rights reserved.
//
// Stub implementations for AzooKey Swift engine C API.
// These stubs allow building Mozc without the actual Swift DLL.
// At runtime, the real Swift DLL should be loaded dynamically.

#include <cstdlib>
#include <cstring>

// Stub implementations for AzooKey C API
// These will be replaced by the actual Swift DLL at runtime

extern "C" {

// Legacy API (for reference)
void* azookey_create(const char* /*config_json*/) {
  // Return a dummy handle
  return reinterpret_cast<void*>(0x1);
}

void azookey_destroy(void* /*engine*/) {
  // No-op
}

const char* azookey_convert(void* /*engine*/, const char* input) {
  // Return the input as-is (no conversion)
  if (input == nullptr) return nullptr;
  size_t len = strlen(input);
  char* result = static_cast<char*>(malloc(len + 3));
  if (result) {
    result[0] = '[';
    result[1] = '"';
    // Copy input without quotes for now
    memcpy(result + 2, input, len);
    // This is a simplified stub - real implementation would return proper JSON
  }
  return input;  // Just return input for stub
}

void azookey_free_string(const char* /*str*/) {
  // No-op for stub (we're returning static strings)
}

// Fine-grained API - stub implementations
void Initialize(const char* /*dictionary_path*/, const char* /*memory_path*/) {
  // Stub: no-op
}

void Shutdown() {
  // Stub: no-op
}

void AppendText(const char* /*input*/) {
  // Stub: no-op
}

void ClearText() {
  // Stub: no-op
}

static const char* stub_candidates = "[]";

const char* GetCandidates() {
  // Stub: return empty array
  return stub_candidates;
}

const char* GetComposition() {
  // Stub: return empty string
  return "";
}

void FreeString(const char* /*str*/) {
  // Stub: no-op (we're returning static strings)
}

void SelectCandidate(int /*index*/) {
  // Stub: no-op
}

void Confirm() {
  // Stub: no-op
}

void SetZenzaiEnabled(bool /*enabled*/) {
  // Stub: no-op
}

void SetZenzaiInferenceLimit(int /*limit*/) {
  // Stub: no-op
}

bool IsZenzaiAvailable() {
  // Stub: return false
  return false;
}

}  // extern "C"
