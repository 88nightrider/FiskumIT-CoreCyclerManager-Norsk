---
Formål: forklare ALT som er endret i CoreCycler-motoren (script-corecycler.ps1 +
configs/default.config.ini) sammenlignet med sp00n sin originalversjon, slik at det
går å hente en ny versjon fra GitHub og flytte over Fiskum IT-tilpasningene uten å
måtte gjette eller miste noe.
Sist verifisert mot: https://github.com/sp00n/corecycler (master-branch), commit som
hadde $version = '0.11.0.4' - se "Hvordan verifisere" under for hvordan dette ble
gjort i praksis (ekte nedlasting + funksjonsinventar-diff, ikke fra hukommelse).
Se også: Utviklingslogg-Prosessorstotte.md og Vedlikehold-Prosessorstotte.md
(Manager-siden av prosessorstøtte) og Utviklingslogg-UI-Stabilitet.md
(Manager-siden av UI-/stabilitetsfikser) - denne filen dekker KUN selve motoren.
---

# CoreCycler-tilpasninger (Fiskum IT vs. original sp00n)

## Kilden

Original CoreCycler: https://github.com/sp00n/corecycler (CC BY-NC-SA-lisens av sp00n).
Vi bruker `CoreCycler/script-corecycler.ps1` og `CoreCycler/configs/default.config.ini`
fra dette repoet, MED tilpasninger. Resten av `CoreCycler/`-mappa (Prime95/y-cruncher/
Linpack-binærer, `tools/`, `configs/*.ini`-eksempler osv.) er uendret fra originalen.

**Viktig prinsipp**: vi endrer IKKE sp00n sin logikk eller fjerner noe - vi legger KUN
til nytt (nye funksjoner, nye config-nøkler, eller et par dokumenterte bugfikser).
Alt som er lagt til er kommentert med `Fiskum IT` i selve koden. Dette gjør det mulig
å finne ALT som er tilpasset med et enkelt søk - se under.

## Hvordan finne alle endringene selv (den autoritative metoden)

```powershell
Select-String 'Fiskum IT' 'CoreCycler\script-corecycler.ps1'
Select-String 'Fiskum IT' 'CoreCycler\configs\default.config.ini'
```

Dette er den autoritative kilden - denne filen er en MENNESKELIG OPPSUMMERING av
det søket, skrevet for å gi kontekst og "hvorfor", men hvis denne filen og koden
noen gang er i utakt, er KODEN (og "Fiskum IT"-søket) alltid sannheten.

## Hvordan verifisere at denne oppsummeringen er komplett (gjort 2026-06-21)

1. Lastet ned den ekte originalfilen direkte fra GitHub (`raw.githubusercontent.com/
   sp00n/corecycler/master/script-corecycler.ps1`) - IKKE stolt på web-sok/hukommelse.
2. Bekreftet at original og lokal fil har SAMME `$version`-streng (`0.11.0.4`), slik
   at sammenligningen er mot riktig, matchende versjon (ikke en eldre/nyere original).
3. Sammenlignet listen over `function`-definisjoner i original vs. lokal (mer robust
   enn en linje-for-linje-diff på en 15 000+ linjers fil, som lett mistolkes når
   linjenumre forskyver seg). Resultat: 0 funksjoner fjernet, 4 nye funksjoner lagt
   til - nøyaktig de 4 som er beskrevet under.
4. Krysset dette mot et fullt `Select-String 'Fiskum IT'`-søk (34 treff på tidspunktet
   dette ble skrevet) for å bekrefte at hver kodeendring faktisk er kommentert.

Hvis du gjør dette på nytt med en nyere sp00n-versjon: bruk SAMME metode (last ned
ekte filen, sammenlign funksjonslister, søk etter "Fiskum IT") i stedet for å anta at
denne lista fortsatt er 100% komplett - sp00n kan ha endret noe som gjør en av
tilpasningene under irrelevant, eller vi kan ha lagt til mer siden sist.

---

## De 5 tilpasningene

### 1. Branding (kosmetisk, ingen funksjonell endring)

`script-corecycler.ps1`, ca. linje 42 og 47: vindustittel og oppstartsbanner i
konsollvinduet har fått en ekstra linje/tillegg som nevner Fiskum IT og lenker til
sp00n sitt repo. sp00n sin egen `$version`-variabel er IKKE endret.

**Ved oppdatering**: trivielt å gjenskape - bare legg de samme to tekstlige tilleggene
inn i den nye filens ekvivalente linjer (søk etter `WindowTitle` og `Press CTRL+C`).

### 2. Alltid-på "offset snapshot"-fil (den viktigste tilpasningen)

**Hvorfor**: sp00n sin motor bruker `setVoltageOnlyForTestedCore = 1`, som betyr at
KUN den kjernen som testes akkurat nå har en faktisk avlest Curve Optimizer/spennings-
verdi på selve silisiumet - alle andre kjerner står på 0 i øyeblikket. Å lese
"nåværende verdier" rett fra CPU-en (sp00n sin opprinnelige metode) ville derfor KUN
se riktig verdi for den ene kjernen som nylig ble testet, og 0 (feil!) for alle andre.
FiskumIT-CoreCyclerManager-UI'et trenger derimot den fulle, korrekte per-kjerne-
rekken hele tiden (for visning OG for å gjenoppta riktig etter krasj/stopp).

**Hva som er lagt til**:
- To nye modulvariabler nær toppen: `$coreOffsetSnapshotFile` og
  `$coreOffsetSnapshotFileTemp` (peker til `CoreCycler/logs/fiskumit-offset-
  snapshot.json` og en `-temp`-variant for atomisk skriving).
- Tre nye funksjoner: `Set-CoreOffsetSnapshot`, `Remove-CoreOffsetSnapshot`,
  `Get-FiskumOffsetSnapshotValues` (søk etter disse navnene for å finne dem - se
  koden selv for full implementasjon, den er kommentert i detalj der).
- `Set-CoreOffsetSnapshot` kalles hver gang en kjerne/verdi endres (i
  `Test-AutomaticTestModeIncrease` OG den nye `Test-AutomaticTestModeDecrease`,
  se under).
- `Get-FiskumOffsetSnapshotValues` foretrekkes FØR `startValues` fra config-en ved
  oppstart/gjenopptak (men ETTER sp00n sin egen `.automode`-fil, som fortsatt har
  første prioritet når den finnes - se ca. linje 5600).
- `Remove-CoreOffsetSnapshot` kalles ved (a) start av et nytt Automatic Test Mode-
  kjøring, (b) hvis automatisk justering er deaktivert, (c) ved en fatal feil -
  men **IKKE** ved en normal, ren avslutning (se punkt 5 under for hvorfor).
- Bugfiks inni `Set-CoreOffsetSnapshot`: `Rename-Item -Force` overskriver IKKE en
  eksisterende destinasjonsfil i PowerShell (`-Force` der gjelder bare skrivebeskyttede/
  skjulte filer) - måtte fjerne den gamle filen explisitt først, akkurat som sp00n sin
  egen `Set-AutoModeFile` allerede gjør.

**Ved oppdatering**: dette er den STØRSTE og viktigste tilpasningen å gjenskape riktig.
Sjekk at de 3 funksjonene fortsatt eksisterer i den nye filen (de vil ikke gjøre det,
siden de er Fiskum IT-only) - kopier dem inn omtrent der de var (nær `Set-AutoModeFile`/
`Get-AutoModeFile`/`Remove-AutoModeFile`, som er deres sp00n-ekvivalenter og gode
ankerpunkter å søke etter i den nye filen). Sjekk at ALLE call-steder er gjenskapt:
søk den GAMLE lokale filen etter `Set-CoreOffsetSnapshot -ActiveCore` og
`Get-FiskumOffsetSnapshotValues` for å finne nøyaktig hvor.

### 3. `searchDirection = Decreasing` (Assistert undervolting-søkemotoren)

**Hvorfor**: sp00n sin motor har KUN `Test-AutomaticTestModeIncrease` - den starter på
en aggressiv verdi og blir MINDRE aggressiv (øker verdien) hver gang en kjerne feiler.
Det finnes ingen innebygd "bli MER aggressiv ved suksess"-logikk, som er nøyaktig det
"Assistert undervolting" (finn grensen automatisk per kjerne) trenger.

**Hva som er lagt til**:
- Ny config-nøkkel `[AutomaticTestMode] searchDirection` (`Increasing` = original
  oppførsel/default, `Decreasing` = ny oppførsel), dokumentert i
  `configs/default.config.ini` (søk "Fiskum IT addition: the search direction").
- Ny funksjon `Test-AutomaticTestModeDecrease` - motstykket til
  `Test-AutomaticTestModeIncrease`. Når en kjerne BESTÅR testen og
  `searchDirection = Decreasing`: gjør verdien ett `incrementBy`-hakk mer aggressiv og
  gjenta SAMME kjerne (ved å sette den inn på nytt i `coreTestOrderArray` og dekrementere
  `coreIndex`). Når kjernen senere FEILER, tar sp00n sin EKSISTERENDE
  `Test-AutomaticTestModeIncrease` over som vanlig (ingen endring der) og låser verdien
  (gitt `repeatCoreOnError = 0`).
- 3 kalle-steder, ett per stress-test-program-grein (Prime95/y-cruncher/Linpack sin
  "denne kjernen fullførte uten feil"-kode) - søk `Test-AutomaticTestModeDecrease
  -actualCoreNumber` for å finne alle tre.

**Ved oppdatering**: kopier funksjonen inn rett etter/før
`Test-AutomaticTestModeIncrease` i den nye filen (god ankerplassering). Legg til
config-nøkkelen i `default.config.ini`. Finn de 3 "fullført uten feil"-greinene i den
NYE filen (de kan se annerledes ut hvis sp00n har refaktorert testløkken) og legg inn
samme kall. **Risiko å sjekke spesielt**: hvis sp00n endrer SIN egen
`Test-AutomaticTestModeIncrease`-signatur eller låse-/repeat-logikk, må
`Test-AutomaticTestModeDecrease` sannsynligvis speile den endringen.

### 4. `minValue` sikkerhetsgrense for Decreasing-søket

**Hvorfor**: uten en nedre grense kunne et søk i prinsippet presse en kjerne til en
ekstremt aggressiv verdi som gir stille datakorrupsjon i stedet for en synlig feil/
WHEA-hendelse, hvis CPU-en/BIOS-en ikke rapporterer feil tydelig ved ekstreme verdier.

**Hva som er lagt til**: ny config-nøkkel `[AutomaticTestMode] minValue`, dokumentert i
`default.config.ini` (søk "the lower SAFETY LIMIT"). Brukt inni
`Test-AutomaticTestModeDecrease`: hvis kjernens nåværende verdi allerede er på/forbi
denne grensen når den består en test, låses den der i stedet for å gå enda lavere.
Faller tilbake til "ingen grense" (`[Int]::MinValue`) hvis nøkkelen mangler (f.eks. en
eldre config-fil fra før dette ble lagt til), for bakoverkompatibilitet.

**Ved oppdatering**: legg til config-nøkkelen og bruk den samme `if ($oldValue -le
$minValue)`-sjekken i den nye `Test-AutomaticTestModeDecrease`-kopien.

Merk: FiskumIT-CoreCyclerManager (Manager-scriptet, IKKE denne motorfilen) patcher
selve VERDIEN av `minValue` automatisk per CPU-generasjon (-30/-50 for AMD, ingen fast
verdi for Intel) ved aktivering - se `Aktivate-TestConfig` og `Get-UndervoltStotteInfo`
i Manager-scriptet, og `VEDLIKEHOLD-Prosessorstotte.md`. Det er IKKE noe å gjenskape
her i motoren - motoren bare LESER verdien som allerede er satt i den kopierte
config.ini-filen.

### 5. Snapshot-filen overlever nå en ren avslutning

**Hvorfor**: slik at neste test i en sekvens (neste test i "Vanlig stabilitetstest",
eller overgangen fra "Assistert undervolting" til "Vanlig stabilitetstest") kan starte
med de allerede oppdagede verdiene i stedet for å starte på nytt fra null.

**Hva som er lagt til**: sp00n sin opprinnelige avslutningskode fjernet/ryddet opp
diverse tilstandsfiler uforbeholdent ved avslutning. Det tilsvarende kallet til
`Remove-CoreOffsetSnapshot` er bevisst IKKE lagt til i denne ene avslutnings-grenen
(søk "do NOT remove the offset snapshot here anymore" for å finne nøyaktig hvor) -
filen ryddes fortsatt opp ved START av neste kjøring og ved fatale feil (se punkt 2).

**Ved oppdatering**: dette er den letteste tilpasningen å glemme, siden det er en
UNNLATELSE (et kall som IKKE er der) snarere enn synlig ny kode. Sjekk at den nye
filens ekvivalente avslutningskode ikke har fått tilbake et automatisk
`Remove-CoreOffsetSnapshot`-kall der.

### (Liten bugfiks, ikke en funksjonell tilpasning)

`script-corecycler.ps1`, ca. linje 6009, i `Set-CurveOptimizerValues`: `$msg`-variabelen
ble brukt med `+=` uten å være initialisert først. Under `Set-StrictMode -Version 3.0`
(som sp00n allerede bruker) gir dette en forvirrende "variable has not been set"-feil
i stedet for den faktiske CLI-feilmeldingen fra `ryzen-smu-cli`/`IntelVoltageControl`.
Fikset med `$msg = $null` før bruk. Rapporter dette gjerne oppstrøms til sp00n - det er
en ren bugfiks, ikke en Fiskum IT-spesifikk funksjon, så det kan godt allerede være
fikset i en nyere sp00n-versjon (sjekk om denne tilpasningen fortsatt er nødvendig).

---

## Sjekkliste etter å ha hentet en ny CoreCycler-versjon

1. Last ned den nye `script-corecycler.ps1` og `configs/default.config.ini` fra GitHub.
2. Sammenlign funksjonslister (se "Hvordan verifisere" over) mot DENNE (gamle, tilpassede)
   lokale filen for å se hva sp00n har endret/lagt til siden sist - les gjennom dette
   FØR du går videre, i tilfelle noe er relevant (f.eks. om sp00n selv legger til en
   lignende "decreasing search" eller en bedre Intel-løsning, som kan gjøre en eller
   flere av tilpasningene over overflødige).
3. Bekreft at punkt 6009-bugfiksen fortsatt er nødvendig (sjekk om `$msg` initialiseres
   i den nye filen).
4. Gjenskap tilpasning 1-5 over i den nye filen, i den rekkefølgen de står (2 og 3 er
   mest arbeidskrevende, 1 og 5 er trivielle/lette å glemme).
5. Kopier den nye filen inn i `CoreCycler/script-corecycler.ps1` (og `default.config.ini`
   tilsvarende), oppdater `$version`-referansen IKKE - sp00n sin egen versjonsstreng
   skal stå som den er i deres fil.
6. Kjør AST-syntaksverifisering:
   `[System.Management.Automation.Language.Parser]::ParseFile(...)`.
7. Kjør verifiseringsstegene fra utviklingsplanen (krasjsimulering, gjenopptak, osv. -
   se eldre plan-/devlog-materiale for den fulle listen) på en faktisk testmaskin,
   IKKE bare syntaksjekk - dette er motorlogikk som styrer faktisk
   spenningsjustering, og bør verifiseres i praksis før det tas i bruk.
8. Oppdater "Sist verifisert mot"-linja i toppen av DENNE filen med den nye versjonen.
