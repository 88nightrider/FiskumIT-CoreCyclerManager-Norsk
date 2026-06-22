---
Formål: praktisk guide for å OPPDATERE prosessorstøtte-logikken (Assistert
undervolting sin CPU-deteksjon, og instruksjonssett-deteksjonen for vanlig
stabilitetstest) når nye CPU-generasjoner kommer, eller når noe i den eksisterende
logikken viser seg å være feil i praksis. Skrevet slik at en fremtidig
utviklingssesjon (med eller uten tilgang til denne samtalen) raskt kan orientere seg.
Se også: Utviklingslogg-Prosessorstotte.md (hvorfor det ble som det ble),
CoreCycler-Tilpasninger.md (motor-siden, ikke Manager-siden, av prosjektet) og
Utviklingslogg-UI-Stabilitet.md (separat logg for UI-/stabilitetsfikser, ikke
prosessorrelatert).
---

# Vedlikehold - prosessorstøtte

## Hvor logikken bor

Alt foregår i Manager-scriptet (`Manager/FiskumIT-CoreCyclerManager-vX.Y.ps1` - bytt
`vX.Y` med den versjonen du faktisk jobber i):

- **`Get-UndervoltStotteInfo`**: hovedfunksjonen. Oppdager CPU-vendor (AMD/Intel),
  generasjon, og returnerer et objekt med `Vendor`, `Stottet` (bool), `ConfigFil`,
  `MinVerdi`, `CpuNavn`, `Forklaring` (full, logges) og `KortStatus` (kort, vises i
  UI). Cachet i `$Script:UndervoltStotteCache` (må være `$null`-initialisert ved
  scriptets toppnivå pga. `Set-StrictMode` - IKKE lazy-initialiser inni funksjonen).
- **`Get-CpuInstruksjonssett`** / **`Test-StottetAvCpu`**: AVX/AVX2/AVX512-deteksjon
  for vanlig stabilitetstest (`testplan.json` sitt `kreverInstruksjonssett`-felt).
  Cachet i `$Script:CpuInstruksjonssettCache` (samme StrictMode-fallgruve som over).
- **`Activate-TestConfig`**: patcher `minValue` i den KOPIERTE config.ini basert på
  `Get-UndervoltStotteInfo` sin `MinVerdi`, ved aktivering av Assistert undervolting.
- UI: `Build-Ui`, søk etter `$undervoltStotte`/`$lblUndervoltStotte`/`$radioAssistert`.

## AMD - hvordan det fungerer i dag, og hva du må sjekke for en ny generasjon

**I dag**: leser CPUID Family fra `Win32_Processor.Description`/`Caption`
(`Family\s+(\d+)`, desimalt). Family ≥ 25 (19h) = Zen 3 eller nyere = Curve Optimizer
støttet. Family ≤ 24 = ikke støttet, UANSETT modellnummer (dette var nødvendig fordi
AMD har solgt Zen 2-silisium under 5000-/7000-serienumre i den bærbare U/H-serien -
se Utviklingslogg-Prosessorstotte.md punkt 5). Modellnummeret (fra CPU-navnet, regex
`Ryzen\s+\d\s+(?:PRO\s+)?(\d{4})([A-Z]*)`) brukes KUN for: (a) visning, og (b) å velge
mellom -30 (5000/6000-serien) og -50 (7000-serien og nyere) som `minValue`.

**Kjent, akseptert begrensning**: -30/-50-valget er FORTSATT basert på modellnummer,
ikke Family/Model. En sjelden ekte Zen 3-brikke markedsført i 7000-serien (f.eks.
"Barcelo-R", Ryzen 5 7430U/7530U) ville derfor kunne få -50 i stedet for korrekt -30.
Dette er bevisst SAMME forenkling som selve CoreCycler-motoren gjør for sin "Minimum"-
funksjon (regex `[7-9]\d{3}` på modellnavnet) - se CoreCycler-Tilpasninger.md. Hvis du
vil fjerne denne begrensningen: CPUID Model (ikke bare Family) kan i prinsippet skille
Zen 3 (~Model < 0x60 innenfor Family 19h) fra Zen 4 (~Model ≥ 0x60), men dette ble
IKKE implementert pga. lavere kildesikkerhet på de eksakte Model-grensene under
researchen som ligger til grunn for dagens kode - verifiser nøye før du bruker dette.

**IKKE verifisert på ekte AMD-maskinvare** (utviklingsmaskinen som bygget dette er
Intel) - kun isolert regex-/logikk-testing. Manager-scriptet logger ALLTID den rå,
avleste CPUID Family-verdien ved oppstart (`"AMD CPUID Family lest fra WMI: ..."`,
søk i `Write-ManagerLog`-kallene i `Get-UndervoltStotteInfo`). **Første gang dette
faktisk kjører på en AMD-maskin** (f.eks. WANJA-GAMER): sjekk denne logglinjen og
bekreft at Family-tallet stemmer med hva CPU-en faktisk er (Zen 3 Ryzen 5000 bør vise
Family 25) - hvis det IKKE stemmer, er sannsynligvis WMI sin tekstformatering
annerledes enn antatt (f.eks. hex i stedet for desimalt), og regex-en/grensa må rettes.

**Når en ny AMD-generasjon (Zen 6+) kommer**:
1. Finn den nye generasjonens CPUID Family-nummer (søk "[generasjonsnavn] CPUID
   family" - WikiChip og Wikipedias "List of AMD CPU microarchitectures" var gode
   kilder under researchen i juni 2026).
2. Den vil nesten garantert være ≥ 25, så `Stottet`-sjekken trenger sannsynligvis
   IKKE endres - men dobbeltsjekk likevel, spesielt om AMD skifter til en helt ny
   Family-rekke (de gjorde dette fra 17h til 19h ved Zen 3, og igjen til 1Ah ved Zen 5).
3. Sjekk om AMD igjen gjenbruker et serienummer for eldre silisium i en ny mobil-serie
   (dette har skjedd ved BÅDE 5000- og 7000-mobil-seriene - anta at det skjer igjen).
   Family-sjekken beskytter allerede mot dette automatisk, SÅ LENGE den nye
   "ekte" generasjonen også havner i riktig Family-rekke.
4. Vurder om minimumsverdien fortsatt bør være -50 for den nye generasjonen, eller om
   AMD/community har dokumentert en annen verdi - oppdater `if ($modellnummer -ge
   7000)`-grensen i `Get-UndervoltStotteInfo` og kommentaren i
   `AssistedUndervolting_Ryzen.ini` tilsvarende.
5. Oppdater README sin "CPU-støtte"-seksjon og denne filen.

## Intel - hvordan det fungerer i dag, og hva du må sjekke for en ny generasjon

**I dag**: leser generasjon fra modellnummeret i CPU-navnet (regex `Core\(TM\)\s+
i[3579]-(\d{4,5})([A-Z]*)`). VIKTIG fallgruve allerede løst: Intel bruker FØRSTE siffer
som generasjon for 4.-9. gen ("4770"→4, "9700"→9), men FØRSTE TO sifre fra 10. gen og
oppover, SELV i et 4-sifret nummer ("1065G7"→10, "1265U"→12, "1335U"→13). Koden
gjenkjenner dette ved at "modellnummeret begynner på 1" er et trygt signal om at det er
2-sifret koding (se kommentaren i `Get-UndervoltStotteInfo` for full begrunnelse).
Generasjon ≥ 4 (Haswell) = "støttet, men ikke garantert", med en generasjonsspesifikk
tillitsforklaring (se koden for de eksakte tekstene per generasjonsgruppe: 4-9, 10,
11, 12-14, 15+). Suffiks (U/Y/H/HX/G) brukes til å avgjøre bærbar vs. stasjonær for
tilleggsforbehold (bærbare er mer utsatt for BIOS-låsing).

**Når en ny Intel-generasjon (15.+/Arrow Lake/Panther Lake osv.) kommer**:
1. Sjekk om Intel FORTSATT bruker samme 2-sifret-generasjonskoding for det nye
   modellnummeret (f.eks. "15. generasjon" → forventet at modellnumre begynner på
   "15xx" eller "15xxx"). Intel HAR endret nummereringskonvensjon før (Core Ultra-
   navngivingen som kom med Meteor Lake er et eksempel på en STØRRE navnsendring -
   sjekk om dette i det hele tatt fortsatt matcher `i[3579]-`-regex-en, eller om en
   helt ny gren må legges til for "Core Ultra X"-stil-navn).
2. Finn ut om det finnes ny, konkret dokumentasjon om faktisk undervolt-/MSR
   0x150-støtte for den nye generasjonen (søk "[generasjon] undervolt CFG lock
   locked" eller lignende - ThrottleStop-fora, NotebookCheck og Overclock.net var
   nyttige kilder under researchen). Legg til en ny `elseif`-grein i
   `$tillitNotat`-switchen i `Get-UndervoltStotteInfo` med funnene.
3. Oppdater `AssistedUndervolting_Intel.ini` sin "GENERASJON-FOR-GENERASJON"-kommentar
   og README tilsvarende.

**Generelt forbehold som IKKE kan kodes bort**: Intel sin MSR 0x150-basert
spenningsjustering kan være BIOS-blokkert (Plundervolt-sikring) på en måte som ikke
kan oppdages av programvare i forveien - dette gjelder for ALLE Intel-generasjoner,
ikke bare fremtidige. Forvent at brukere av nyere Intel-maskiner (spesielt
OEM-bærbare) opplever at "Assistert undervolting" ikke fungerer i praksis selv når
UI'et sier den er "støttet" - dette er en ærlig begrensning, ikke en bug.

## Instruksjonssett-deteksjon (AVX/AVX2/AVX512) - lavt vedlikeholdsbehov

Denne bruker EKTE maskinvaredeteksjon (`IsProcessorFeaturePresent`), ikke gjetning fra
CPU-navn/generasjon - den krever IKKE oppdatering når nye CPU-generasjoner kommer.
Eneste grunn til å røre denne: hvis et NYTT instruksjonssett blir relevant for en
fremtidig test (f.eks. AVX10 eller APX), må:
1. Riktig `PF_*`-konstant for `IsProcessorFeaturePresent` slås opp (se
   `Get-CpuInstruksjonssett` for de eksisterende AVX/AVX2/AVX512-konstantene: 39/40/41).
2. En ny verdi legges til i `kreverInstruksjonssett` sitt sett av mulige verdier
   (`""`, `"AVX"`, `"AVX2"` i dag) og i `testplan.json` for de relevante testene.

## Hvordan teste endringer uten tilgang til ekte AMD/Intel-maskinvare for hver generasjon

Denne metoden er brukt gjennomgående under utviklingen og fungerer godt: kopier den
RELEVANTE regex-/logikk-blokken (ikke hele funksjonen) ut i et eget, frittstående
PowerShell-script eller -kommando, kjør den mot en LISTE av simulerte CPU-navn/
beskrivelser (ekte kjente modellnavn, inkludert kjente "vanskelige" tilfeller som
rebrand-feller), og verifiser hvert forventet resultat manuelt. Se
Utviklingslogg-Prosessorstotte.md punkt 4 og 5 for konkrete eksempler på testtabeller
som er brukt (Intel-generasjoner inkl. "1265U", AMD inkl. Lucienne/Mendocino).

Når koden FAKTISK kjøres på en maskin med den relevante CPU-en (f.eks. når dette
distribueres til WANJA-GAMER, som er AMD): sjekk Manager-loggen for
`"AMD CPUID Family lest fra WMI: ..."` og `"Assistert undervolting-stotte: ..."`-
linjene ved oppstart, og bekreft at de stemmer med hva CPU-en faktisk er, FØR du
stoler på at "Assistert undervolting" sin gråing/aktivering er korrekt for den
maskinen.

## Kilder brukt under researchen (juni 2026) - sjekk om disse har noe nyere

- WikiChip ("amd/cpuid", microarkitektur-sider per kodenavn)
- Wikipedia "List of AMD CPU microarchitectures", "List of AMD Ryzen processors"
- NotebookCheck ("Intel and OEMs have killed undervolting...", Lucienne/Cezanne-
  dekning)
- ThrottleStop-relaterte fora og guider (Overclock.net, MSI-forum, Tom's Hardware)
- Tom's Hardware ("AMD rebrands Ryzen 7035, 7020 series...")
- openSUSE Wiki "X86-64 microarchitecture levels" (baseline-instruksjonssett per
  x86-64-v1/v2/v3/v4-nivå)
- IntelVoltageControl sin egen `readme`/`.txt`-dokumentasjon (bundlet i
  `CoreCycler/tools/IntelVoltageControl/`)

Disse kildene var gode på researchtidspunktet, men er IKKE autoritative
spesifikasjoner - behandle dem som utgangspunkt for videre verifisering, ikke som
endelig sannhet, særlig for noe så raskt bevegelig som CPU-generasjoners
undervolt-/BIOS-låsestatus.
