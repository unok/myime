#ifndef FFI_H
#define FFI_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Configuration and initialization
void LoadConfig(const char* configPath);
void Initialize(const char* dictionaryPath, const char* memoryPath);
void Shutdown(void);

// Text composition
void AppendText(const char* input);
void RemoveText(int count);
void MoveCursor(int offset);
void ClearText(void);

// Conversion
const char* GetComposedText(void);
const char* GetCandidates(void);
void SelectCandidate(int index);
void ShrinkText(void);
void ExpandText(void);

// Context
void SetContext(const char* precedingText);

// Zenzai (AI) settings
void SetZenzaiEnabled(bool enabled);
void SetZenzaiInferenceLimit(int limit);

// Memory management
void FreeString(const char* str);

#ifdef __cplusplus
}
#endif

#endif // FFI_H
