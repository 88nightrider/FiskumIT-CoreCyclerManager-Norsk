Fiskum IT - PawnIO-patch for IntelVoltageControl (v0.8.7.10)
============================================================

STATUS: KILDEKODE FORBEREDT, IKKE BYGGET, IKKE TESTET PA EKTE MASKINVARE.

Dette er IKKE en fungerende erstatning ennaa - det er et forberedt utgangspunkt for
noen MED et C/C++-byggemiljo (Visual Studio) til a fullfore. Manageren bruker
fortsatt den eksisterende, fungerende WinRing0-baserte IntelVoltageControl.exe i
mappen over (..\IntelVoltageControl.exe) helt til denne patchen er bygget, testet
PA EKTE INTEL-MASKINVARE, og eksplisitt byttet inn.

HVORFOR
-------
WinRing0x64.sys blir flagget av Windows Defender og andre antivirus-produkter siden
mars 2025 (CVE-2020-14979) - dette traff ALLE store verktoy som bruker WinRing0
(LibreHardwareMonitor, HWiNFO, MSI Afterburner, FanControl, OpenRGB, osv), ikke bare
var bundlede kopi. LibreHardwareMonitor/FanControl/OpenRGB byttet i 2025 til PawnIO
(https://github.com/namazso/PawnIO) - en moderne, signert driver designet spesifikt
som en sikrere erstatning, som kjorer avgrensede, signerte "moduler" i stedet for a
eksponere ra Ring0-tilgang direkte.

HVA ER ALLEREDE GJORT
----------------------
1. IntelMSR.bin (i denne mappen) - den OFFISIELLE, ferdig-kompilerte PawnIO-modulen
   fra namazso/PawnIO.Modules (release 0.2.9). Bekreftet (mot kildekoden pa GitHub)
   at den tillater BADE lesing OG skriving av MSR 0x150 (MSR_OC_MAILBOX) - akkurat
   MSR-en IntelVoltageControl bruker for spenningsforskyvning. Lisens: LGPL-2.1, se
   IntelMSR.bin.LGPL-2.1-LICENSE.txt.
2. PawnIOLib.h (i denne mappen) - kopiert ORDRETT fra namazso/PawnIO (offisiell
   brukerland-API-header, LGPL-2.1). Definerer pawnio_open/pawnio_load/
   pawnio_execute/pawnio_close.
3. OlsApiShim_PawnIO.h/.cpp (i denne mappen, SKREVET AV Fiskum IT - IKKE kopiert fra
   jamestut sin kode) - implementerer InitializeOls()/DeinitializeOls()/Rdmsr()/
   Wrmsr()/GetDllStatus() med SAMME signaturer som det velkjente, offentlige OlsApi.h
   (WinRing0/OpenLibSys sitt API), men via PawnIO i stedet for WinRing0. Dette betyr
   IntelVoltageControl.cpp sin EGEN logikk (CLI-parsing, mV<->MSR-konvertering) skal
   IKKE matte endres i det hele tatt - bare HVILKEN implementasjon disse fire
   funksjonene kobles mot.

HVA SOM GJENSTAR (for noen med Visual Studio)
-----------------------------------------------
1. Klon https://github.com/jamestut/IntelVoltageControl (MIT-lisens).
2. I IntelVoltageControl.vcxproj:
   - Fjern referansen til WinRing0x64.lib og WinRingRes.cpp/.h.
   - Legg til OlsApiShim_PawnIO.cpp/.h og PawnIOLib.h fra denne mappen.
   - VERIFISER at OlsDef.h-konstantene i OlsApiShim_PawnIO.h (OLS_DLL_*) faktisk
     matcher det opprinnelige repoet sin include/OlsDef.h - de er skrevet fra
     velkjent offentlig kunnskap om WinRing0 sitt API, IKKE kopiert fra en sett fil,
     og kan derfor avvike i detaljer.
3. Bygg PawnIOLib.dll/.lib fra kildekoden i https://github.com/namazso/PawnIO
   (mappen "PawnIOLib") - det finnes INGEN ferdig-kompilert SDK-nedlasting fra
   prosjektet selv per na (kun en sluttbruker-installer, se under). Lenk
   IntelVoltageControl.exe mot PawnIOLib.lib i stedet for WinRing0x64.lib.
4. Bygg og test PA EKTE INTEL-MASKINVARE (4. generasjon Haswell eller nyere):
   - "IntelVoltageControl.exe show" skal vise "Plane 0: <tall>" etc., akkurat som i
     dag (Manageren sin Get-OffsetsFromIntelVoltageControl parser nettopp dette).
   - "IntelVoltageControl.exe set --allow-overvolt --commit 0 <verdi> 2 <verdi>" skal
     faktisk endre spenningsforskyvningen (bekreft f.eks. med HWiNFO/ThrottleStop).
5. Plasser den nybygde IntelVoltageControl.exe + PawnIOLib.dll + IntelMSR.bin i
   ..\ (samme mappe som den eksisterende .exe-en) FORST etter at punkt 4 er bekreftet
   - bytt IKKE ut den fungerende .exe-en for det er gjort.

SLUTTBRUKER-INSTALLASJON (separat fra selve patchen)
-----------------------------------------------------
PawnIO-DRIVEREN (ikke biblioteket) krever en EGEN, engangs installasjon pa
malmaskinen - i motsetning til WinRing0x64.sys, som bare matte ligge i samme mappe.
Offisiell installer: https://github.com/namazso/PawnIO.Setup (signert,
PawnIO_setup.exe). IKKE bekreftet om denne stotter et stille
kommandolinje-installasjonsflagg for automatisering i Installer.bat - matte
verifiseres/testes for det evt. bygges inn i installasjonsflyten var.

IKKE GJORT I DENNE RUNDEN
--------------------------
- Ingen bygging/kompilering (intet C/C++-byggemiljo tilgjengelig).
- Ingen testing pa ekte maskinvare.
- Installer.bat er IKKE endret til a installere PawnIO-driveren - avventer at
  patchen over faktisk er bygget og bekreftet fungerende forst.
