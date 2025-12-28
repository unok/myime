// Check DLL dependencies
#include <windows.h>
#include <stdio.h>

bool file_exists(const char* path) {
    DWORD attrs = GetFileAttributesA(path);
    return (attrs != INVALID_FILE_ATTRIBUTES && !(attrs & FILE_ATTRIBUTE_DIRECTORY));
}

int main() {
    const char* base_path = "C:\\Program Files\\Mozc\\";
    const char* dlls[] = {
        "azookey-engine.dll",
        "swiftCore.dll",
        "swiftCRT.dll",
        "swiftDispatch.dll",
        "swift_Concurrency.dll",
        "swiftWinSDK.dll",
        "Foundation.dll",
        "FoundationEssentials.dll",
        "FoundationInternationalization.dll",
        "_FoundationICU.dll",
        "BlocksRuntime.dll",
        "dispatch.dll",
        "ggml.dll",
        "ggml-base.dll",
        "ggml-cpu.dll",
        "ggml-vulkan.dll",
        "llama.dll",
        "llava_shared.dll",
        "mtmd.dll",
        nullptr
    };

    printf("Checking DLLs in %s\n\n", base_path);

    for (int i = 0; dlls[i] != nullptr; i++) {
        char full_path[MAX_PATH];
        snprintf(full_path, MAX_PATH, "%s%s", base_path, dlls[i]);
        bool exists = file_exists(full_path);
        printf("[%s] %s\n", exists ? "OK" : "MISSING", dlls[i]);
    }

    printf("\n--- Trying to load DLL with detailed error ---\n");

    // Set DLL directory
    SetDllDirectoryA(base_path);

    // Try to load
    HMODULE hDll = LoadLibraryExA(
        "C:\\Program Files\\Mozc\\azookey-engine.dll",
        nullptr,
        0
    );

    if (hDll) {
        printf("DLL loaded successfully!\n");
        FreeLibrary(hDll);
    } else {
        DWORD error = GetLastError();
        printf("Failed to load DLL. Error code: %lu\n", error);

        // Format error message
        char* msg = nullptr;
        FormatMessageA(
            FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM,
            nullptr,
            error,
            0,
            (LPSTR)&msg,
            0,
            nullptr
        );
        if (msg) {
            printf("Error message: %s\n", msg);
            LocalFree(msg);
        }
    }

    return 0;
}
