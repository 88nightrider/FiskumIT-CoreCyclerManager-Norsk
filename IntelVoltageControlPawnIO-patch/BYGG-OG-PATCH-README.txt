Fiskum IT - PawnIO-patch for IntelVoltageControl (v0.8.7.11)
============================================================

MERK OM PLASSERING: denne mappen ligger BEVISST i repo-roten, IKKE inni CoreCycler\
eller Manager\ - Installer.bat kopierer KUN de to mappene, sa denne mappen (kildekode/
byggedokumentasjon for patchen, ikke selve kjoretids-avhengigheten) blir AUTOMATISK
utelatt fra den faktiske installerte programvaren. De faktiske, kjorbare filene
(IntelVoltageControl.exe, PawnIOLib.dll, IntelMSR.bin) ligger i
CoreCycler\tools\IntelVoltageControl\ - IKKE i denne mappen.

STATUS: BYGGET OG TESTET PA EKTE INTEL-MASKINVARE (Dell Latitude E5470, Intel Core
i5-6300U, Skylake).

"show" bekreftet a fungere identisk med originalen (riktig "Plane N: X.X mV"-format).
"set --allow-overvolt --commit" bekreftet a sende riktig OC-mailbox-kommando til
MSR 0x150 UTEN feil (verken busy- eller feilbit i MSR-svaret) - men selve
spenningsendringen slo IKKE igjennom pa DENNE maskinen, fordi firmware/BIOS har
Plundervolt-laasen ("CFG Lock"/"Overclocking Lock") aktiv - se Plundervolt-avsnittet
i README.md i repo-roten, som allerede dokumenterer akkurat dette forbeholdet. Dette
er en BIOS/firmware-laas, IKKE en feil i PawnIO-porteringen - WinRing0 ville traff
akkurat samme laas pa denne maskinen. En reell ende-til-ende spenningsendring kan
forst bekreftes etter at CFG Lock/Overclocking Lock er deaktivert i BIOS (brukerens
eget valg - krever omstart inn i BIOS-oppsett).

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

GJORT I DENNE RUNDEN (Claude Code, 2026-06-27)
-----------------------------------------------
1. [FERDIG] Repoet var allerede klonet fra https://github.com/jamestut/IntelVoltageControl
   (MIT-lisens) - origin bekreftet a peke dit.
2. [FERDIG] I IntelVoltageControl.vcxproj/.filters:
   - WinRing0x64.lib fjernet fra AdditionalDependencies (var allerede gjort fra
     forrige runde), erstattet med PawnIOLib.lib.
   - OlsApiShim_PawnIO.cpp/.h og PawnIOLib.h lagt til som ClCompile/ClInclude.
   - WinRingRes.cpp/.h er IKKE fjernet fra prosjektet (de er originale jamestut-filer,
     ikke WinRing0-spesifikk kode i seg selv - bare en RAII-wrapper rundt
     InitializeOls/DeinitializeOls - og IntelVoltageControl.cpp bruker dem direkte.
     Fjerning ville knekt bygget. WinRingRes.cpp sin EGEN WinRing0-avhengighet
     (#include <OlsApi.h>) ble byttet til shimmen i forrige runde.)
   - VERIFISERT: OLS_DLL_*-konstantene i OlsApiShim_PawnIO.h matcher
     include/OlsDef.h i repoet byte for byte (kun whitespace-forskjell).
3. [FERDIG] PawnIOLib.dll/.lib bygget fra https://github.com/namazso/PawnIO
   (PawnIOLib-mappen). Toppniva-CMakeLists.txt krever WDK (Windows Driver Kit) selv
   for a bygge PawnIOLib (pga. find_package(WDK REQUIRED) tidlig i filen, for
   PawnIOLib-target defineres) - WDK var IKKE installert. Siden PawnIOLib.cpp i
   praksis IKKE har noen reell avhengighet til drivertargetet (kun en delt
   include-header), ble den kompilert direkte med cl.exe/link.exe/rc.exe, utenom
   CMake/WDK. Eksportene (pawnio_open/load/execute/close osv.) er bekreftet med
   dumpbin.
   IntelVoltageControl.exe er bygget og lenker na mot PawnIOLib.lib. Hele
   solution bygger uten advarsler/feil.
4. [FERDIG, MED FORBEHOLD] Bygget og testet PA EKTE INTEL-MASKINVARE (Dell Latitude
   E5470, Intel Core i5-6300U, Skylake - tilfredsstiller "Haswell eller nyere").
   PawnIO-driveren (offisiell, signert v2.2.0) ble installert og bekreftet kjorende.
   - "show" bekreftet a virke IDENTISK med originalen (riktig "Plane N: X.X mV").
   - "set --allow-overvolt --commit 0 -10" sendte riktig OC-mailbox-kommando til
     MSR 0x150 uten feil (bekreftet med en egen MSR-status-diagnose: ingen
     busy/feilbit i svaret) - men selve spenningsendringen slo IKKE igjennom pa
     DENNE maskinen. Arsak: Plundervolt-laasen ("CFG Lock"/"Overclocking Lock") er
     aktiv i BIOS/firmware her - se Plundervolt-avsnittet i README.md i repo-roten,
     som allerede dokumenterte akkurat dette forbeholdet. Dette er en BIOS-laas,
     IKKE en feil i porteringen - WinRing0 ville traff akkurat samme laas pa denne
     maskinen, siden begge bare leverer samme WRMSR-instruksjon.
   - En reell ende-til-ende spenningsendring (bekreftet med HWiNFO/ThrottleStop) kan
     forst testes etter at brukeren selv deaktiverer CFG Lock/Overclocking Lock i
     BIOS (krever omstart inn i BIOS-oppsett - brukerens eget valg, ikke gjort her).
5. [FERDIG] IntelVoltageControl.exe + PawnIOLib.dll + IntelMSR.bin er plassert i
   CoreCycler\tools\IntelVoltageControl\ (erstatter de gamle WinRing0-filene der) -
   pa brukerens eksplisitte bekreftelse, gitt at IOCTL/mailbox-rundtripen er
   bekreftet korrekt selv om selve laasen i punkt 4 ikke kunne testes fullt ut na.

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
- Ingen faktisk bekreftet spenningsendring (se forbehold i punkt 4 - CFG
  Lock/Overclocking Lock i BIOS pa testmaskinen blokkerte dette).
- Installer.bat er IKKE endret til a installere PawnIO-driveren - stille
  installasjonsflagg for PawnIO_setup.exe er fortsatt ikke verifisert/testet.
