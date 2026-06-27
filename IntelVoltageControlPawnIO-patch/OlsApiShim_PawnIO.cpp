// Fiskum IT (v0.8.7.10, UFERDIG/UTESTET - se BYGG-OG-PATCH-README.txt).
//
// Implementerer InitializeOls/DeinitializeOls/Rdmsr/Wrmsr (samme signaturer som
// OlsApi.h) via PawnIO (https://github.com/namazso/PawnIO) + den offisielle,
// ferdig-kompilerte "IntelMSR"-modulen (IntelMSR.bin, fra namazso/PawnIO.Modules,
// LGPL-2.1 - se IntelMSR.bin.LGPL-2.1-LICENSE.txt). Den modulen har MSR 0x150
// (MSR_OC_MAILBOX - akkurat den IntelVoltageControl bruker for spenningsforskyvning)
// pa BADE les- og skrive-tillatelseslisten - bekreftet mot modulens kildekode pa
// GitHub for denne patchen ble skrevet.
//
// IntelMSR.bin lastes fra SAMME mappe som .exe-filen kjorer fra - se
// GetIntelMsrBinPath() under.

#include "OlsApiShim_PawnIO.h"
#include "PawnIOLib.h"

#include <fstream>
#include <vector>
#include <string>

static HANDLE g_pawnioHandle = NULL;
static DWORD  g_lastStatus   = OLS_DLL_DRIVER_NOT_LOADED;

static std::wstring GetIntelMsrBinPath()
{
    wchar_t exePath[MAX_PATH];
    DWORD len = GetModuleFileNameW(NULL, exePath, MAX_PATH);

    if (len == 0 || len >= MAX_PATH) {
        return L"IntelMSR.bin";
    }

    std::wstring path(exePath, len);
    size_t pos = path.find_last_of(L"\\/");
    path = (pos == std::wstring::npos) ? L"" : path.substr(0, pos + 1);
    path += L"IntelMSR.bin";
    return path;
}

BOOL WINAPI InitializeOls()
{
    if (g_pawnioHandle) {
        g_lastStatus = OLS_DLL_NO_ERROR;
        return TRUE;
    }

    HRESULT hr = pawnio_open(&g_pawnioHandle);
    if (FAILED(hr) || !g_pawnioHandle) {
        // Fiskum IT: mest sannsynlig arsak - PawnIO-driveren er ikke installert
        // (PawnIO_setup.exe er ikke kjort) - se BYGG-OG-PATCH-README.txt
        g_lastStatus  = OLS_DLL_DRIVER_NOT_LOADED;
        g_pawnioHandle = NULL;
        return FALSE;
    }

    std::ifstream file(GetIntelMsrBinPath(), std::ios::binary | std::ios::ate);
    if (!file.is_open()) {
        g_lastStatus = OLS_DLL_DRIVER_NOT_FOUND;
        pawnio_close(g_pawnioHandle);
        g_pawnioHandle = NULL;
        return FALSE;
    }

    std::streamsize size = file.tellg();
    file.seekg(0, std::ios::beg);

    std::vector<UCHAR> blob(static_cast<size_t>(size));
    if (size <= 0 || !file.read(reinterpret_cast<char*>(blob.data()), size)) {
        g_lastStatus = OLS_DLL_DRIVER_NOT_FOUND;
        pawnio_close(g_pawnioHandle);
        g_pawnioHandle = NULL;
        return FALSE;
    }

    hr = pawnio_load(g_pawnioHandle, blob.data(), blob.size());
    if (FAILED(hr)) {
        g_lastStatus = OLS_DLL_UNSUPPORTED_PLATFORM;
        pawnio_close(g_pawnioHandle);
        g_pawnioHandle = NULL;
        return FALSE;
    }

    g_lastStatus = OLS_DLL_NO_ERROR;
    return TRUE;
}

VOID WINAPI DeinitializeOls()
{
    if (g_pawnioHandle) {
        pawnio_close(g_pawnioHandle);
        g_pawnioHandle = NULL;
    }
}

BOOL WINAPI Rdmsr(DWORD index, PDWORD eax, PDWORD edx)
{
    if (!g_pawnioHandle || !eax || !edx) {
        return FALSE;
    }

    ULONG64 in  = index;
    ULONG64 out = 0;
    SIZE_T  returnSize = 0;

    HRESULT hr = pawnio_execute(g_pawnioHandle, "ioctl_read_msr", &in, 1, &out, 1, &returnSize);
    if (FAILED(hr) || returnSize < 1) {
        return FALSE;
    }

    *eax = static_cast<DWORD>(out & 0xFFFFFFFFULL);
    *edx = static_cast<DWORD>((out >> 32) & 0xFFFFFFFFULL);
    return TRUE;
}

BOOL WINAPI Wrmsr(DWORD index, DWORD eax, DWORD edx)
{
    if (!g_pawnioHandle) {
        return FALSE;
    }

    ULONG64 in[2];
    in[0] = index;
    in[1] = (static_cast<ULONG64>(edx) << 32) | static_cast<ULONG64>(eax);

    SIZE_T returnSize = 0;
    HRESULT hr = pawnio_execute(g_pawnioHandle, "ioctl_write_msr", in, 2, NULL, 0, &returnSize);
    return SUCCEEDED(hr);
}

DWORD WINAPI GetDllStatus()
{
    return g_lastStatus;
}
