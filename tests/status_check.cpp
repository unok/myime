// Simple Zenzai Status Check - no conversion, just status
#include <windows.h>
#include <stdio.h>

int main() {
    SetConsoleOutputCP(CP_UTF8);

    printf("=== Zenzai Status Check ===\n\n");

    // Set DLL directory
    SetDllDirectoryA("C:\\Program Files\\Mozc");

    HMODULE hDll = LoadLibraryA("C:\\Program Files\\Mozc\\azookey-engine.dll");
    if (!hDll) {
        printf("[ERROR] Failed to load DLL. Error: %lu\n", GetLastError());
        return 1;
    }
    printf("[OK] DLL loaded\n");

    // Get status function only
    typedef const char* (*GetZenzaiStatusFunc)();
    typedef void (*FreeStringFunc)(const char*);

    GetZenzaiStatusFunc GetZenzaiStatus = (GetZenzaiStatusFunc)GetProcAddress(hDll, "GetZenzaiStatus");
    FreeStringFunc FreeString = (FreeStringFunc)GetProcAddress(hDll, "FreeString");

    if (!GetZenzaiStatus) {
        printf("[ERROR] GetZenzaiStatus not found\n");
        FreeLibrary(hDll);
        return 1;
    }

    printf("[OK] GetZenzaiStatus function loaded\n\n");

    // Call status - this should NOT trigger model loading
    const char* status = GetZenzaiStatus();
    if (status) {
        printf("Zenzai Status:\n%s\n", status);
        if (FreeString) FreeString(status);
    } else {
        printf("[ERROR] GetZenzaiStatus returned null\n");
    }

    FreeLibrary(hDll);
    return 0;
}
