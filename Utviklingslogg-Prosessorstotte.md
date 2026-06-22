---
Formål: kronologisk utviklingslogg for CPU/prosessor-støtte-arbeidet i Fiskum IT
CoreCycler Manager (instruksjonssett-deteksjon, Intel-støtte i Assistert undervolting,
AMD-generasjonsbevissthet). Skrevet for å kunne flyttes mellom flere
utviklingsmaskiner uten å være bundet til en bestemt mappe/stasjonsbokstav.
Se også: VEDLIKEHOLD-Prosessorstotte.md (fremtidsrettet "hvordan oppdatere"-guide),
CoreCycler-Tilpasninger.md (hva som er endret i selve motoren) og
Utviklingslogg-UI-Stabilitet.md (separat logg for UI-/stabilitetsfikser, ikke
prosessorrelatert).
---

# Utviklingslogg - prosessorstøtte

Dette er en logg over HVORFOR ting ble bygget som de ble, ikke en detaljert
endringslogg (den finnes i `README.txt` sin "Nyheter i vX.Y"-seksjon i hver
versjonsmappe). Tidligere, mer generelt UI-arbeid (mørkt tema, logg-integrasjon,
branding-fjerning) ligger før dette i prosjektets historie og er ikke gjentatt her.

## 1. Instruksjonssett-deteksjon (AVX/AVX2/AVX512)

**Problem**: testplanen inneholdt tester som krever AVX/AVX2 (Prime95 AVX-varianter,
Linpack Fast/Fastest), men det fantes ingen sjekk på om CPU-en faktisk støtter dette -
en gammel CPU uten AVX ville bare krasje på disse testene i stedet for å få dem
grået ut.

**Løsning**: `Add-Type` mot `kernel32.dll`s `IsProcessorFeaturePresent` (Windows sin
egen, innebygde maskinvare-funksjonssjekk - ikke en gjetning basert på CPU-navn/-alder).
Ny funksjon `Get-CpuInstruksjonssett` (cachet i `$Script:CpuInstruksjonssettCache`) og
`Test-StottetAvCpu -Krav <streng>`. `testplan.json` fikk et nytt felt
`kreverInstruksjonssett` på HVER av de 21 testene (tom streng = ingen krav - måtte være
eksplisitt til stede pa alle, ikke utelatt, pga. `Set-StrictMode` - se "Feller" under).

**Verifisert mot**: ekte maskinvare (utviklingsmaskinens CPU, Intel i5-6300U, Skylake-U
mobil) - kjente AVX=True, AVX2=True, AVX512=False stemmer med det som er offentlig kjent
om denne CPU-modellen.

## 2. Branding-fjerning + y-cruncher auto-modus

Fjernet "for AMD Ryzen 3000/5000" fra tittel/UI (siden Assistert undervolting på dette
tidspunktet fortsatt var AMD-only, men resten av Manageren - vanlig stabilitetstest -
alltid har fungert på alle CPU-er). Omdøpte `YCRUNCHER_19-ZN2_1/2` til
`YCRUNCHER_AUTO_1/2` og satte `mode = auto` i config-ene, slik at y-cruncher selv velger
riktig binær for prosessoren i stedet for en hardkodet Zen 2-spesifikk en.

## 3. Intel-støtte i Assistert undervolting - første runde

**Bestilling fra bruker**: kan Assistert undervolting (som da var rent AMD/Curve
Optimizer) også støtte Intel, med tydelig gråing/markering av hvilke CPU-er som
faktisk støttes, og generasjonsbevisste maks/min-grenser.

**Undersøkelse før implementasjon**: fant at selve CoreCycler-MOTOREN allerede hadde
fullverdig Intel-støtte innebygd (`IntelVoltageControl.exe`, MSR 0x150,
`$useIntelVoltageAdjustment`) - dette var IKKE noe som måtte bygges fra scratch, bare
kobles til fra Manager-siden. Brukeren fikk valget mellom "bare blokker Intel for nå,
bygg senere" og "bygg et ekte søk nå, med klare forbehold om at det kan være
BIOS-blokkert" - valgte sistnevnte explisitt.

**Bygget**:
- `Get-UndervoltStotteInfo` (Manager-scriptet): oppdager CPU-vendor og -generasjon,
  returnerer støtte/config-fil/min-verdi/forklaring, cachet.
- `AssistedUndervolting_Intel.ini`: ny profil, EN global spenningsverdi for hele CPU-en
  (Intel har ikke per-kjerne-kontroll som AMD), konservativ `minValue = -150` (ingen
  offisielt dokumentert grense finnes for Intel, i motsetning til AMD).
- `Get-OffsetsFromIntelVoltageControl` / `Set-OffsetViaIntelVoltageControl`: leser/
  skriver via det bundlede verktøyet, speiler motorens egne kommandoer/regex nøyaktig.
- `Format-OffsetRekke -ErGlobalVerdi`: ny visningsmåte for Intels global-verdi-modell
  (i stedet for AMDs per-kjerne-liste).
- Generasjonsbevisst `minValue` for AMD: fant via nettsøk at Curve Optimizer er en
  Zen 3 (Ryzen 5000)-funksjon, IKKE tilgjengelig på 1000/2000/3000/4000 - og at
  minimumsverdien er -30 for 5000/6000-serien, -50 for 7000-serien og nyere (dette
  tallet var allerede brukt av MOTOREN selv for dens "Minimum"-funksjon, men ikke av
  vår Manager-side `minValue`-patching, som var hardkodet til -30 uansett generasjon).
- UI: gråing/markering av "Assistert undervolting"-radioknappen pluss en ny
  statuslinje i "Modus"-panelet ("CPU oppdaget: ...").

**Verifisert**: AVX-deteksjon og den første (brede) Intel-generasjon-sjekken ble
verifisert på den ekte Intel-maskinvaren tilgjengelig (i5-6300U). AMD-siden kunne IKKE
verifiseres på ekte maskinvare (utviklingsmaskinen er Intel) - kun isolert
regex-/logikk-testing.

## 4. Grundigere Intel-forskning - generasjons- og bærbar-bevisst tillitsnivå

Brukeren ba om et MER grundig nettsøk på nøyaktig hvilke Intel-generasjoner som
faktisk støttes. Dette avdekket at "4. generasjon og nyere, ikke garantert" var en
for grov forenkling:

- Plundervolt (CVE-2019-11157, offentliggjort des. 2019) førte til at MANGE
  OEM-bærbare (spesielt fra ca. 10. generasjon/Ice Lake og senere) har fått MSR
  0x150 låst via BIOS-oppdateringer i ettertid - mobile Tiger Lake (11. gen) er
  ifølge flere kilder ofte låst helt av Intel selv.
- 12.-14. gen (Alder Lake/Raptor Lake) varierer sterkt per hovedkort, og det ble
  funnet at BIOS-intern spenningsforskyvning i praksis har blitt mer vanlig enn denne
  kjørende-Windows-metoden for disse generasjonene.
- 4.-9. gen forble historisk mest pålitelig.

**Reell bug funnet og fikset under dette arbeidet**: generasjons-regexen tolket
4-sifrede modellnumre som "1265U" som "1. generasjon" i stedet for korrekt
"12. generasjon" - Intel byttet til en TO-sifret generasjonskoding fra 10. generasjon
(Ice Lake) og oppover, selv i 4-sifrede modellnumre (f.eks. "1065G7" = 10. gen,
"1265U" = 12. gen), mens 4.-9. gen brukte ETT siffer ("4770" = 4. gen, "9700" = 9. gen).
Fikset ved å sjekke om modellnummeret begynner på "1" (et trygt signal siden ingen
ekte i3/i5/i7/i9 brukte denne notasjonen for "1.-3. generasjon" - de hadde en helt
annen 3-sifret navngiving den gangen).

**Også fikset**: den nye, mer detaljerte forklaringsteksten ble for lang for
UI-statuslinjen og overlappet panelet under på et faktisk skjermbilde - delte opp i en
kort `KortStatus` (UI) og full `Forklaring` (logg), og gjorde UI-etiketten robust mot
2 linjer (i stedet for å stole på at all fremtidig tekst alltid blir kort nok).

**Verifisert**: 11 simulerte CPU-navn (inkl. "1265U", "1035G1", "4770K" osv.) testet
isolert mot den fikse-de regex-logikken - alle korrekte. Skjermbilde av den ekte
i5-6300U bekreftet riktig "6. generasjon (bærbar)"-klassifisering og lesbar layout.

## 5. AMD-forskning - CPUID Family-basert fiks for rebrand-fellen

Brukeren ba om samme grundighet for AMD. Nettsøk avdekket en ANALOG felle til Intels
generasjonsnummerering, men av en annen art: AMD har solgt EKTE Zen 2-silisium
(ingen Curve Optimizer) under BÅDE "Ryzen 5000"- og "Ryzen 7000"-modellnumre i den
bærbare U/H-serien:
- "Lucienne" (Ryzen 3 5300U, Ryzen 5 5500U, Ryzen 7 5700U) = Zen 2, markedsført i
  "5000-serien" sammen med ekte Zen 3 "Cezanne" (5600U/5800U)
- "Mendocino" (Ryzen 3 7320U, Ryzen 5 7520U) = Zen 2, markedsført i "7000-serien"

Modellnummeret ALENE ("≥5000") ville feilaktig godkjenne disse. Løsning: lese CPUID
Family direkte fra Windows (`Win32_Processor.Description`/`Caption`, regex
`Family\s+(\d+)`) - Family 19h (25 desimalt) og oppover = ekte Zen 3/3+/4/5 = har
Curve Optimizer; Family 17h (23 desimalt) og under = Zen/Zen+/Zen 2 = har det ikke,
UANSETT modellnummer. Dette er den faktiske silisium-identiteten, immun mot AMDs
markedsføringsnavngivning. Modellnummeret brukes fortsatt for visning og for
-30/-50-grensevalget (se VEDLIKEHOLD-Prosessorstotte.md for en kjent, akseptert
begrensning ved dette valget).

Også undersøkt og AVKREFTET som et problem: at "Ryzen 5 5500" (stasjonær, uten "U")
skulle være en tilsvarende Zen 2-rebrand - bekreftet via nettsøk at denne faktisk ER
ekte Zen 3 "Cezanne"-silisium (samme die som 5600G med iGPU avskrudd), bare med
halvert L3-cache og PCIe 3.0 i stedet for 4.0 for å treffe en lavere pris. Stasjonære
Ryzen-modeller er ikke kjent rammet av navngivningsforvirringen - kun den bærbare
U/H-serien.

**Verifisert**: 9 simulerte CPU-beskrivelser (inkl. begge kjente rebrand-fellene, en
ekte Zen3/Zen4/Zen5-CPU hver, og et tilfelle med manglende Family-info for å teste
reserveløsningen) testet isolert - alle korrekte. IKKE verifisert på ekte AMD-
maskinvare (utviklingsmaskinen er Intel) - se VEDLIKEHOLD-Prosessorstotte.md for
hvordan dette bør sjekkes første gang det kjøres på en ekte AMD-maskin.

## 6. x86-64-historie - bekreftelse, ingen kodeendring

Brukeren spurte om "vanlig testing" (de 21 ordinære stabilitetstestene, IKKE Assistert
undervolting) faktisk fungerer korrekt for "alle x86-64-CPU-er fra år 2000 til nå".
Nettsøk bekreftet:
- x86-64 fantes ikke før 2003 (AMD)/2004 (Intel) - "år 2000" er i praksis "fra første
  x86-64-CPU", siden eldre rene 32-bits-CPU-er ikke kan kjøre 64-bits Windows/
  PowerShell som Manageren krever uansett.
- SSE2 er OBLIGATORISK i selve x86-64-spesifikasjonen (bekreftet via openSUSE sin
  "x86-64 microarchitecture levels"-dokumentasjon av baseline-kravene) - de vanlige
  testene krever aldri mer enn dette som minimum, og kjører derfor garantert på 100%
  av x86-64-CPU-er.
- AVX (2011)/AVX2 (2013 Intel, 2015-2017 AMD) sjekkes allerede med ekte
  maskinvaredeteksjon (se punkt 1), ikke en navn-/aldersbasert gjetning - dette gir
  riktig svar selv for spesialtilfeller som budsjett-CPU-er med AVX2 deaktivert i
  mikrokode.

Ingen kodeendring var nødvendig - dette var en verifisering av eksisterende logikk,
dokumentert i README sin "CPU-støtte"-seksjon for fremtidig referanse.
