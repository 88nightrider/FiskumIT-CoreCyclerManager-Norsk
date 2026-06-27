# IntelVoltageControl - Utviklingslogg (PawnIO-migrering)

Dette dokumentet loggfører arbeidet med å migrere `IntelVoltageControl` (klonet fra
[jamestut/IntelVoltageControl](https://github.com/jamestut/IntelVoltageControl), MIT-lisens)
fra WinRing0 til [PawnIO](https://github.com/namazso/PawnIO) som MSR-tilgangs-backend.

## Bakgrunn / hvorfor

`WinRing0x64.sys` (brukt av originalverktøyet) blir flagget av Windows Defender og andre
antivirus-produkter siden mars 2025 (CVE-2020-14979). Dette traff alle store verktøy som
bruker WinRing0 (LibreHardwareMonitor, HWiNFO, MSI Afterburner, FanControl, OpenRGB osv.),
ikke bare vår bundlede kopi. Flere av disse byttet i 2025 til PawnIO - en moderne, signert
driver designet som en sikrere erstatning, som kjører avgrensede, signerte "moduler" i
stedet for å eksponere rå Ring0-tilgang direkte.

Målet: bytte ut WinRing0-avhengigheten med PawnIO + den offisielle "IntelMSR"-modulen,
**uten** å endre `IntelVoltageControl.cpp` sin egen logikk (CLI-parsing, mV↔MSR-konvertering).

## Runde 1 (tidligere session) - forberedelse, ikke bygget/testet

Utført uten tilgjengelig C/C++-byggemiljø - kun kildekode-forberedelse:

- `PawnIO-patch/IntelMSR.bin` - den offisielle, ferdig-kompilerte PawnIO-modulen fra
  namazso/PawnIO.Modules (release 0.2.9). Bekreftet mot kildekoden på GitHub at den
  tillater både lesing og skriving av MSR `0x150` (MSR_OC_MAILBOX), som
  `IntelVoltageControl` bruker for spenningsforskyvning. Lisens: LGPL-2.1.
- `PawnIO-patch/PawnIOLib.h` - kopiert ordrett fra namazso/PawnIO (offentlig
  brukerland-API-header, LGPL-2.1).
- `PawnIO-patch/OlsApiShim_PawnIO.h/.cpp` - egenskrevet shim som implementerer
  `InitializeOls()` / `DeinitializeOls()` / `Rdmsr()` / `Wrmsr()` / `IsMsr()` /
  `GetDllStatus()` med **samme signaturer** som det offentlige `OlsApi.h`
  (WinRing0/OpenLibSys), men via PawnIO i stedet for WinRing0.
- `WinRingRes.cpp` ble patchet til å inkludere `OlsApiShim_PawnIO.h` i stedet for
  `<OlsApi.h>`.
- `IntelVoltageControl.vcxproj` ble delvis patchet: `PlatformToolset` endret til
  `v145`, og `AdditionalDependencies` endret fra `WinRing0x64.lib` til
  `PawnIOLib.lib`.
- Skrev `PawnIO-patch/BYGG-OG-PATCH-README.txt` med gjenstående steg.

Status etter runde 1: kildekode forberedt, ingenting bygget eller testet.

## Runde 2 (denne sessionen) - bygging, kobling og test på ekte maskinvare

### 1. Verifisering av OLS_DLL_*-konstanter

Sammenlignet `OLS_DLL_*`-konstantene i `OlsApiShim_PawnIO.h` direkte mot den faktiske
`IntelVoltageControl/include/OlsDef.h` i det klonede repoet. Verdiene stemmer nøyaktig
(kun forskjell i whitespace/innrykk). Ingen endring nødvendig.

### 2. Ferdigstilling av IntelVoltageControl.vcxproj / .vcxproj.filters

- La til `OlsApiShim_PawnIO.cpp` (ClCompile) og `OlsApiShim_PawnIO.h` + `PawnIOLib.h`
  (ClInclude) i prosjektet og filter-filen.
- **Valgte å IKKE fjerne `WinRingRes.cpp/.h` fra prosjektet**, til forskjell fra den
  opprinnelige planen. Begrunnelse: disse er originale jamestut-filer (ikke
  WinRing0-spesifikk kode i seg selv - bare en RAII-wrapper rundt
  `InitializeOls`/`DeinitializeOls`), og `IntelVoltageControl.cpp` bruker dem direkte
  via `InitializeWinRingRes()`. Å slette dem ville knekt bygget. Den faktiske
  WinRing0-avhengigheten i `WinRingRes.cpp` (`#include <OlsApi.h>`) var allerede byttet
  til shim-headeren i runde 1.
- `IntelVoltageControl.cpp` selv ble **ikke endret** - den inkluderer fortsatt
  `<OlsApi.h>`/`<OlsDef.h>` (de originale WinRing0-headerne i `include/`), men siden
  disse bare er funksjonsdeklarasjoner uten egen lenkning, løses kallene til
  `InitializeOls`/`Rdmsr`/`Wrmsr`/`GetDllStatus` korrekt mot symbolene definert i
  `OlsApiShim_PawnIO.cpp` ved lenketid (samme kalkonvensjon/signatur → samme
  C++-mangling).
- La `PawnIOLib.lib` (se under) i `IntelVoltageControl/lib/`.

### 3. Bygging av PawnIOLib.dll/.lib fra namazso/PawnIO

`PawnIO`-repoet var allerede klonet lokalt (`PawnIO/`), inkludert en delvis forberedt
CMake-konfigurasjon (`PawnIO/build/`).

**Problem:** toppnivå-`CMakeLists.txt` i PawnIO kjører `find_package(WDK REQUIRED)`
ubetinget, *før* `PawnIOLib`-targetet defineres - selv om man bare vil bygge
`PawnIOLib` (brukermodus-DLL), tvinger CMake-konfigurasjonen et fullt Windows Driver
Kit-oppsett (kun nødvendig for selve kjernedriveren `PawnIO.sys`). WDK var ikke
installert på maskinen, og å installere hele WDK (flere GB) bare for å bygge en liten
DLL ble vurdert som unødvendig.

**Løsning:** `PawnIOLib/PawnIOLib.cpp` har i praksis ingen reell avhengighet til selve
driver-targetet (kun delt include-header `pawnio_um.h` for IOCTL-koder, samt
`ntdll.lib`/`kernel32.lib`). Den ble derfor kompilert direkte med `cl.exe`/`rc.exe`/
`link.exe`, utenfor CMake, ved å:
- Sette opp MSVC-miljøet manuelt (INCLUDE/LIB/PATH mot
  `VC\Tools\MSVC\14.51.36231` og Windows Kits 10.0.26100.0 - `vcvars64.bat` selv var
  upraktisk å kjøre fra automatiserte verktøy pga. miljøvariabel-fangst, så stiene ble
  satt direkte).
- Kompilere `PawnIOLib.cpp` med riktige `/D`-makroer
  (`PawnIOLib_EXPORTS`, `PAWNIO_NAME`, `PAWNIO_VERSION_STRING` osv. - normalt satt av
  toppnivå-CMakeLists).
- Kompilere `resource.rc` med `rc.exe` (krevde `--%`-stop-parsing-triks i PowerShell
  for at anførselstegn i `/D`-verdier skulle overleve riktig).
- Lenke til `PawnIOLib.dll`/`.lib` mot `ntdll.lib` og `kernel32.lib`.

Eksportene ble verifisert med `dumpbin /exports`: `pawnio_open`, `pawnio_load`,
`pawnio_execute`, `pawnio_close` (og `_win32`/`_nt`-variantene) er alle til stede -
nøyaktig det `OlsApiShim_PawnIO.cpp` kaller.

Artefakter: `PawnIO/build_lib/PawnIOLib.dll` og `PawnIOLib.lib`.

### 4. Full bygg av IntelVoltageControl.exe

Bygget med MSBuild (`Release|x64`) mot VS 2026 (v18)-verktøykjeden. Bygget uten
advarsler eller feil - bekrefter at symbolene fra `OlsApiShim_PawnIO.cpp` matcher
nøyaktig det `IntelVoltageControl.cpp`/`WinRingRes.cpp` forventer via de originale
WinRing0-headerne.

### 5. Test på ekte maskinvare

Maskinen ble bekreftet å være ekte fysisk Intel-maskinvare (ikke VM):
**Dell Latitude E5470, Intel Core i5-6300U (Skylake, 6. gen.)** - tilfredsstiller
kravet om 4. gen. Haswell eller nyere.

Fremgangsmåte:
1. Hentet offisiell, signert PawnIO-installer v2.2.0 fra GitHub-releases
   (`namazso/PawnIO.Setup`), verifiserte Authenticode-signatur
   (`E=admin@namazso.eu, CN=namazso.eu`) før kjøring.
2. Installerte PawnIO-driveren (krevde UAC-elevering). Bekreftet kjørende med
   `sc query PawnIO` (`STATE: RUNNING`).
3. Kjørte `IntelVoltageControl.exe show` (elevert, siden MSR-tilgang krever
   administratorrettigheter) - output:
   ```
   Plane 0: 0.0 mV
   Plane 1: 0.0 mV
   Plane 2: 0.0 mV
   Plane 3: 0.0 mV
   Plane 4: 0.0 mV
   ```
   Format identisk med det opprinnelige WinRing0-baserte verktøyet.
4. Kjørte `IntelVoltageControl.exe set --allow-overvolt --commit 0 -10` (konservativ
   testverdi valgt i samråd med bruker) - ingen feilmelding, men `show` etterpå viste
   fortsatt `Plane 0: 0.0 mV` (endringen slo ikke igjennom).
5. Bygget et eget lite diagnoseprogram (`diag.cpp`, mot samme shim/PawnIOLib) for å
   lese MSR-statusordet direkte: skriving til MSR `0x150` mailbox fullføres uten
   busy-/feilbit i svaret (`eax=0x0, edx=0x0` ved tilbakelesing) - kommandoen blir
   altså akseptert av maskinvaren/firmware, men selve spenningsverdien endres ikke.

**Konklusjon:** Dette stemmer med et forbehold som allerede var dokumentert i
`README.md` i repo-roten: Skylake-firmware med Plundervolt-mitigering aktiv kan låse
spenningsforskyvning via "CFG Lock"/"Overclocking Lock" i BIOS. Dette er en
maskinvare-/firmware-låsing, **ikke** en feil i PawnIO-porteringen - WinRing0 ville
truffet akkurat samme lås på denne maskinen, siden begge til syvende og sist bare
utfører samme `WRMSR`-instruksjon. En reell ende-til-ende-bekreftelse av faktisk
spenningsendring (f.eks. med HWiNFO/ThrottleStop) krever at brukeren selv deaktiverer
CFG Lock/Overclocking Lock i BIOS og reboot - ikke gjort i denne runden, da det er et
brukervalg.

### 6. Utplassering

Etter eksplisitt bekreftelse fra bruker (gitt at lese/skrive-veien gjennom
PawnIO-mailboxen var bevist korrekt, selv om selve BIOS-låsen forhindret en full
spenningsbekreftelse), ble følgende plassert i repo-roten (`..\` sett fra
`PawnIO-patch/`):
- `IntelVoltageControl.exe`
- `PawnIOLib.dll`
- `IntelMSR.bin`

Det fantes ingen eksisterende `.exe` i repo-roten å ta vare på.

`PawnIO-patch/BYGG-OG-PATCH-README.txt` ble oppdatert til å reflektere fullført
status og forbeholdet rundt BIOS-låsen.

## Filoversikt (etter runde 2)

| Fil | Status |
|---|---|
| `IntelVoltageControl.exe` (repo-rot) | Bygget i denne runden, PawnIO-basert |
| `PawnIOLib.dll` (repo-rot) | Bygget fra namazso/PawnIO-kildekode |
| `IntelMSR.bin` (repo-rot) | Kopiert fra `PawnIO-patch/`, offisiell modul |
| `IntelVoltageControl/OlsApiShim_PawnIO.cpp/.h` | Fra runde 1, lagt til i .vcxproj i runde 2 |
| `IntelVoltageControl/PawnIOLib.h` | Fra runde 1, lagt til i .vcxproj i runde 2 |
| `IntelVoltageControl/lib/PawnIOLib.lib` | Lagt til i runde 2 (egenbygget) |
| `IntelVoltageControl/lib/WinRing0x64.lib` | Ikke fjernet fra disk, men ikke lenger referert i .vcxproj |
| `IntelVoltageControl/WinRingRes.cpp/.h` | Beholdt (se begrunnelse over) |
| `PawnIO/build_lib/` | Scratch-mappe med manuell cl.exe/link.exe-bygg av PawnIOLib |
| `PawnIO-patch/BYGG-OG-PATCH-README.txt` | Oppdatert med fullført status |

## Gjenstående arbeid

- **Bekrefte faktisk spenningsendring** på denne (eller annen) maskinvare etter at
  CFG Lock/Overclocking Lock er deaktivert i BIOS.
- `Installer.bat` er **ikke** endret til å installere PawnIO-driveren automatisk -
  stille kommandolinje-installasjonsflagg for `PawnIO_setup.exe` er ikke
  verifisert/testet.
- Vurdere om `WinRing0x64.lib`/`.sys` og de originale WinRing0-headerne
  (`include/OlsApi.h`, `include/OlsDef.h`) bør fjernes fra repoet helt, nå som de
  ikke lenger er en kjøretidsavhengighet (headerne brukes fortsatt som
  funksjonsdeklarasjoner av `IntelVoltageControl.cpp`, se punkt 2 over).
- `PawnIO/build/` (CMake-konfigurasjonen som krever WDK) er fortsatt ufullstendig
  konfigurert og ubrukt - kan fjernes eller fullføres med ekte WDK-installasjon hvis
  man senere også vil bygge selve PawnIO-driveren fra kildekode i stedet for å bruke
  den offisielle signerte installeren.
