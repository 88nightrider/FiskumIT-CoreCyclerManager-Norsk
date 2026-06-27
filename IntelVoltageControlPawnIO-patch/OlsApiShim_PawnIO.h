// Fiskum IT (v0.8.7.10, UFERDIG/UTESTET - se BYGG-OG-PATCH-README.txt): drop-in-erstatning
// for de fire OlsApi.h-funksjonene IntelVoltageControl.cpp faktisk bruker
// (InitializeOls/DeinitializeOls/Rdmsr/Wrmsr), med SAMME signaturer som originalen -
// slik at IntelVoltageControl.cpp sin egen logikk (CLI-parsing, mV<->MSR-konvertering)
// kan forbli HELT uendret. Eneste forskjell: disse er implementert mot PawnIO + den
// offisielle "IntelMSR"-modulen (se IntelMSR.bin i denne mappen) i stedet for mot
// WinRing0x64.dll/.sys.
//
// IKKE bygget/testet av Fiskum IT i denne runden (intet C/C++-byggemiljo tilgjengelig) -
// se BYGG-OG-PATCH-README.txt for hva som gjenstar.

#pragma once

#include <windows.h>

BOOL WINAPI InitializeOls();
VOID WINAPI DeinitializeOls();
BOOL WINAPI Rdmsr(DWORD index, PDWORD eax, PDWORD edx);
BOOL WINAPI Wrmsr(DWORD index, DWORD eax, DWORD edx);

// Fiskum IT: samme verdier som den velkjente, offentlige OlsDef.h (OpenLibSys/WinRing0) -
// tatt med i tilfelle IntelVoltageControl.cpp ogsa kaller GetDllStatus() for
// feilmeldinger. VERIFISER mot den faktiske OlsDef.h i jamestut sitt repo for exakt match
// for du bygger - disse er skrevet fra velkjent offentlig kunnskap om WinRing0 sitt
// API, IKKE kopiert fra en sett kildefil.
#define OLS_DLL_NO_ERROR                     0
#define OLS_DLL_UNSUPPORTED_PLATFORM         1
#define OLS_DLL_DRIVER_NOT_LOADED            2
#define OLS_DLL_DRIVER_NOT_FOUND             3
#define OLS_DLL_DRIVER_UNLOADED              4
#define OLS_DLL_DRIVER_NOT_LOADED_ON_NETWORK 5
#define OLS_DLL_UNKNOWN_ERROR                9

DWORD WINAPI GetDllStatus();
