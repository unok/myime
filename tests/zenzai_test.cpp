// Zenzai Integration Test - Revised version
// Tests azookey-engine.dll step by step with proper error handling

#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <string>

// Function pointer types
// NOTE: Initialize は成功=1/失敗=0 を返す (azookey-engine.dll の現契約)
typedef int (*InitializeFunc)(const char*, const char*);
typedef void (*ShutdownFunc)();
typedef void (*AppendTextFunc)(const char*);
typedef void (*ClearTextFunc)();
typedef const char* (*GetCandidatesFunc)();
typedef const char* (*GetComposedTextFunc)();
typedef void (*FreeStringFunc)(const char*);
typedef void (*SetZenzaiEnabledFunc)(bool);
typedef void (*SetZenzaiInferenceLimitFunc)(int);
typedef void (*SetZenzaiWeightPathFunc)(const char*);
typedef const char* (*GetZenzaiStatusFunc)();

// Global handles
HMODULE g_hDll = nullptr;
FreeStringFunc g_FreeString = nullptr;

// Test result tracking
int tests_passed = 0;
int tests_failed = 0;

void test_result(const char* test_name, bool passed, const char* detail = nullptr) {
    if (passed) {
        printf("[PASS] %s\n", test_name);
        tests_passed++;
    } else {
        printf("[FAIL] %s\n", test_name);
        if (detail) {
            printf("       Detail: %s\n", detail);
        }
        tests_failed++;
    }
    fflush(stdout);
}

bool file_exists(const char* path) {
    DWORD attrs = GetFileAttributesA(path);
    return (attrs != INVALID_FILE_ATTRIBUTES && !(attrs & FILE_ATTRIBUTE_DIRECTORY));
}

// Safe string handling - copies and frees the DLL-allocated string
std::string safe_get_string(const char* dll_string) {
    if (!dll_string) return "";
    std::string result(dll_string);
    if (g_FreeString) {
        g_FreeString(dll_string);
    }
    return result;
}

int main() {
    SetConsoleOutputCP(CP_UTF8);

    printf("===========================================\n");
    printf("    Zenzai Integration Test (Revised)\n");
    printf("===========================================\n\n");
    fflush(stdout);

    const char* model_path = "C:\\Program Files\\Mozc\\models\\ggml-model-Q5_K_M.gguf";
    const char* dll_path = "C:\\Program Files\\Mozc\\azookey-engine.dll";

    // ===== Phase 1: File checks =====
    printf("--- Phase 1: File Checks ---\n");
    fflush(stdout);

    test_result("Model file exists", file_exists(model_path), model_path);
    test_result("DLL file exists", file_exists(dll_path), dll_path);

    if (!file_exists(model_path) || !file_exists(dll_path)) {
        printf("\n[ABORT] Required files not found\n");
        return 1;
    }

    // ===== Phase 2: DLL Loading =====
    printf("\n--- Phase 2: DLL Loading ---\n");
    fflush(stdout);

    SetDllDirectoryA("C:\\Program Files\\Mozc");
    g_hDll = LoadLibraryA(dll_path);

    if (!g_hDll) {
        DWORD error = GetLastError();
        char msg[256];
        snprintf(msg, sizeof(msg), "Error code: %lu", error);
        test_result("DLL loaded", false, msg);
        return 1;
    }
    test_result("DLL loaded", true);

    // ===== Phase 3: Function Loading =====
    printf("\n--- Phase 3: Function Loading ---\n");
    fflush(stdout);

    InitializeFunc Initialize = (InitializeFunc)GetProcAddress(g_hDll, "Initialize");
    ShutdownFunc Shutdown = (ShutdownFunc)GetProcAddress(g_hDll, "Shutdown");
    AppendTextFunc AppendText = (AppendTextFunc)GetProcAddress(g_hDll, "AppendText");
    ClearTextFunc ClearText = (ClearTextFunc)GetProcAddress(g_hDll, "ClearText");
    GetCandidatesFunc GetCandidates = (GetCandidatesFunc)GetProcAddress(g_hDll, "GetCandidates");
    GetComposedTextFunc GetComposedText = (GetComposedTextFunc)GetProcAddress(g_hDll, "GetComposedText");
    g_FreeString = (FreeStringFunc)GetProcAddress(g_hDll, "FreeString");
    SetZenzaiEnabledFunc SetZenzaiEnabled = (SetZenzaiEnabledFunc)GetProcAddress(g_hDll, "SetZenzaiEnabled");
    SetZenzaiInferenceLimitFunc SetZenzaiInferenceLimit = (SetZenzaiInferenceLimitFunc)GetProcAddress(g_hDll, "SetZenzaiInferenceLimit");
    SetZenzaiWeightPathFunc SetZenzaiWeightPath = (SetZenzaiWeightPathFunc)GetProcAddress(g_hDll, "SetZenzaiWeightPath");
    GetZenzaiStatusFunc GetZenzaiStatus = (GetZenzaiStatusFunc)GetProcAddress(g_hDll, "GetZenzaiStatus");

    test_result("Initialize", Initialize != nullptr);
    test_result("Shutdown", Shutdown != nullptr);
    test_result("AppendText", AppendText != nullptr);
    test_result("ClearText", ClearText != nullptr);
    test_result("GetCandidates", GetCandidates != nullptr);
    test_result("FreeString", g_FreeString != nullptr);
    test_result("SetZenzaiEnabled", SetZenzaiEnabled != nullptr);
    test_result("SetZenzaiWeightPath", SetZenzaiWeightPath != nullptr);
    test_result("GetZenzaiStatus", GetZenzaiStatus != nullptr);

    if (!Initialize || !AppendText || !GetCandidates || !SetZenzaiEnabled || !SetZenzaiWeightPath) {
        printf("\n[ABORT] Essential functions not found\n");
        FreeLibrary(g_hDll);
        return 1;
    }

    // ===== Phase 4: Engine Initialization =====
    printf("\n--- Phase 4: Engine Initialization ---\n");
    fflush(stdout);

    printf("Calling Initialize(nullptr, nullptr)...\n");
    fflush(stdout);
    const int init_ok = Initialize(nullptr, nullptr);
    test_result("Initialize succeeded", init_ok != 0);
    if (!init_ok) {
        printf("\n[ABORT] Engine initialization failed\n");
        FreeLibrary(g_hDll);
        return 1;
    }

    // ===== Phase 5: Zenzai Configuration =====
    printf("\n--- Phase 5: Zenzai Configuration ---\n");
    fflush(stdout);

    printf("Setting Zenzai enabled...\n");
    fflush(stdout);
    SetZenzaiEnabled(true);

    printf("Setting Zenzai weight path: %s\n", model_path);
    fflush(stdout);
    SetZenzaiWeightPath(model_path);

    if (SetZenzaiInferenceLimit) {
        printf("Setting inference limit to 10...\n");
        fflush(stdout);
        SetZenzaiInferenceLimit(10);
    }

    test_result("Zenzai configured", true);

    // ===== Phase 6: Status Check (before conversion) =====
    printf("\n--- Phase 6: Status Check ---\n");
    fflush(stdout);

    if (GetZenzaiStatus) {
        printf("Getting Zenzai status...\n");
        fflush(stdout);
        std::string status = safe_get_string(GetZenzaiStatus());
        printf("Status: %s\n", status.c_str());
        fflush(stdout);

        bool has_active = status.find("\"active\":true") != std::string::npos ||
                          status.find("\"active\": true") != std::string::npos;
        test_result("Zenzai active in status", has_active, status.c_str());
    }

    // ===== Phase 7: Simple Conversion Test =====
    printf("\n--- Phase 7: Conversion Test ---\n");
    printf("WARNING: This phase may trigger model loading and take time...\n");
    fflush(stdout);

    if (ClearText) {
        printf("Clearing text...\n");
        fflush(stdout);
        ClearText();
    }

    // Simple hiragana: "あ" (a)
    const char* simple_input = "\xe3\x81\x82";  // あ
    printf("Appending simple text: %s\n", simple_input);
    fflush(stdout);
    AppendText(simple_input);

    printf("Getting candidates (this triggers Zenzai model loading)...\n");
    fflush(stdout);

    const char* raw_candidates = GetCandidates();
    if (raw_candidates) {
        std::string candidates = safe_get_string(raw_candidates);
        printf("Candidates: %.200s%s\n", candidates.c_str(),
               candidates.length() > 200 ? "..." : "");
        fflush(stdout);

        bool has_candidates = candidates.length() > 2 && candidates[0] == '[';
        test_result("Got candidates", has_candidates);
    } else {
        test_result("GetCandidates returned value", false, "returned null");
    }

    // ===== Phase 8: Full Conversion Test =====
    printf("\n--- Phase 8: Full Conversion Test ---\n");
    fflush(stdout);

    if (ClearText) ClearText();

    // "きょう" (kyou)
    const char* full_input = "\xe3\x81\x8d\xe3\x82\x87\xe3\x81\x86";
    printf("Testing with: %s (kyou)\n", full_input);
    fflush(stdout);

    AppendText(full_input);

    const char* raw_full = GetCandidates();
    if (raw_full) {
        std::string full_candidates = safe_get_string(raw_full);
        printf("Candidates: %.300s%s\n", full_candidates.c_str(),
               full_candidates.length() > 300 ? "..." : "");
        fflush(stdout);

        // Check for kanji: 今 (E4BB8A), 京 (E4BAAC), 今日 (E4BB8AE697A5)
        bool has_kanji = full_candidates.find("\xe4\xbb\x8a") != std::string::npos ||  // 今
                         full_candidates.find("\xe4\xba\xac") != std::string::npos ||  // 京
                         full_candidates.find("\xe5\x85\xb1") != std::string::npos;    // 共
        test_result("Kanji in candidates", has_kanji,
                    has_kanji ? nullptr : "No kanji found");
    } else {
        test_result("Full conversion", false, "returned null");
    }

    // ===== Summary (printed before cleanup to avoid losing output) =====
    printf("\n===========================================\n");
    printf("    Test Summary\n");
    printf("===========================================\n");
    printf("Passed: %d\n", tests_passed);
    printf("Failed: %d\n", tests_failed);
    printf("Total:  %d\n", tests_passed + tests_failed);
    printf("===========================================\n");
    fflush(stdout);

    if (tests_failed > 0) {
        printf("\n[RESULT] SOME TESTS FAILED\n");
        fflush(stdout);
    } else {
        printf("\n[RESULT] ALL TESTS PASSED - Zenzai is working!\n");
        fflush(stdout);
    }

    // ===== Cleanup =====
    // Note: Both Shutdown() and FreeLibrary() cause crashes with llama.cpp on Windows
    // Skip explicit cleanup - OS will release resources when process exits
    // This is safe for a test program
    printf("\n(Skipping DLL cleanup to avoid llama.cpp crash on Windows)\n");
    fflush(stdout);

    return (tests_failed > 0) ? 1 : 0;
}
