Fiskum IT - PawnIO-patch for IntelVoltageControl (v0.8.7.11)
============================================================

STATUS: BYGGET OG BEKREFTET FUNGERENDE PA EKTE INTEL-MASKINVARE.

Dette er na den AKTIVE, default-bundlede IntelVoltageControl.exe (se
..\IntelVoltageControl.exe, ..\PawnIOLib.dll, ..\IntelMSR.bin) - WinRing0 brukes
IKKE lenger. Denne mappen inneholder kun KILDEKODEN/dokumentasjonen for hvordan
patchen ble gjort, til referanse/fremtidig vedlikehold.

Verifisert (2026-06-27, Intel Core i5-6300U, 6. generasjon):
- "IntelVoltageControl.exe show" - exit code 0, output
  "Plane 0: 0.0 mV" / "Plane 1: 0.0 mV" / osv - SAMME format som forventet av
  Manageren sin Get-OffsetsFromIntelVoltageControl (ingen endring der nodvendig).
- "IntelVoltageControl.exe set --allow-overvolt --commit 0 0 2 0" - exit code 0,
  output "Set offset plane 0 to 0.0 mV" / "Set offset plane 2 to 0.0 mV".
- Bade les- (Rdmsr) og skrive-veien (Wrmsr) via PawnIO + den offisielle
  IntelMSR-modulen fungerer altsa bekreftet korrekt.

HVORFOR
-------
WinRing0x64.sys ble flagget av Windows Defender og andre antivirus-produkter
siden mars 2025 (CVE-2020-14979) - dette traff ALLE store verktoy som bruker
WinRing0 (LibreHardwareMonitor, HWiNFO, MSI Afterburner, FanControl, OpenRGB,
osv), ikke bare var bundlede kopi. De store verktoyene byttet i 2025 til PawnIO
(https://github.com/namazso/PawnIO) - en moderne, signert driver designet
spesifikt som en sikrere erstatning, som kjorer avgrensede, signerte "moduler"
i stedet for a eksponere ra Ring0-tilgang direkte.

HVA PATCHEN BESTAR AV
----------------------
1. IntelMSR.bin (na i ..\IntelMSR.bin) - den OFFISIELLE, ferdig-kompilerte
   PawnIO-modulen fra namazso/PawnIO.Modules (release 0.2.9). Tillater bade
   lesing OG skriving av MSR 0x150 (MSR_OC_MAILBOX) - akkurat MSR-en
   IntelVoltageControl bruker for spenningsforskyvning. Lisens: LGPL-2.1.
2. PawnIOLib.h (i denne mappen) / PawnIOLib.dll (na i ..\PawnIOLib.dll) -
   namazso/PawnIO sitt offisielle brukerland-API (LGPL-2.1).
3. OlsApiShim_PawnIO.h/.cpp (i denne mappen, SKREVET AV Fiskum IT - IKKE
   kopiert fra jamestut sin kode) - implementerer InitializeOls()/
   DeinitializeOls()/Rdmsr()/Wrmsr()/GetDllStatus() med SAMME signaturer som
   det velkjente, offentlige OlsApi.h (WinRing0/OpenLibSys sitt API), men via
   PawnIO i stedet for WinRing0. IntelVoltageControl.cpp sin EGEN logikk
   (CLI-parsing, mV<->MSR-konvertering) matte derfor IKKE endres.

SLUTTBRUKER-INSTALLASJON
--------------------------
PawnIO-DRIVEREN (ikke biblioteket) krever en EGEN, engangs installasjon pa
malmaskinen - i motsetning til WinRing0x64.sys, som bare matte ligge i samme
mappe. Offisiell installer: ligger i ..\..\PawnIO\PawnIO_setup.exe (bundlet med
Manageren). Installer.bat starter denne automatisk (IKKE-blokkerende) for
Intel-CPUer hvis driveren ikke allerede er installert.

BEKREFTET: denne installeren stotter INGEN stille/automatisert
installasjonsflagg (grundig testet: /quiet, /passive, /silent, /S, /s,
--quiet - alle gir samme generiske feil umiddelbart). Selv FanControl, som
ogsa bruker PawnIO, krever manuell GUI-installasjon - dette er ikke en
begrensning unik for var integrasjon. Brukeren ma klikke gjennom
installasjonsvinduet selv (en gang, deretter virker det for alle
PawnIO-baserte verktoy pa maskinen).

IKKE GJORT
----------
- Testet KUN pa en enkelt fysisk maskin (i5-6300U, 6. generasjon, baerbar).
  IKKE bekreftet pa andre Intel-generasjoner/desktop-CPUer.
- IKKE testet en reell, ikke-null spenningsforskyvning (kun verdi 0, for a
  unnga risiko under verifisering) - selve skrive-mekanismen er bekreftet,
  men en faktisk negativ undervolt-verdi via denne veien er IKKE separat
  bekreftet a fungere/gi forventet effekt.
