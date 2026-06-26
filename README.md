# Fiskum IT CoreCycler Manager (Norsk)

Et norsk grensesnitt og automatiseringslag rundt [sp00n sin CoreCycler](https://github.com/sp00n/corecycler) - et verktøy for å finne stabile, undervoltede Curve Optimizer-/spenningsforskyvningsverdier per CPU-kjerne (AMD Ryzen) eller en global verdi (Intel), og for å stabilitetsteste en CPU generelt.

CoreCycler selv er et rent kommandolinje-/konsoll-script. Denne Manageren legger på:

- Et grafisk grensesnitt (WinForms) på norsk, med mørkt fargetema
- To driftsmoduser: **Assistert undervolting** (automatisk søk etter stabile per-kjerne-verdier) og **Vanlig stabilitetstest** (kjører et kuratert eller selvvalgt sett med stresstester)
- Automatisk gjenoppretting etter krasj/BSOD (autostart ved innlogging, auto-restart av maskinen, Windows-autologon - alt valgfritt og reversibelt)
- En "bekreftelsesrunde" som verifiserer de anbefalte verdiene med en lengre, fast stabilitetstest etter at et søk er fullført
- En enkelt, lesbar loggfil på skrivebordet i stedet for å måtte tolke CoreCycler sin egen konsolltekst

> **Status:** se [Releases](https://github.com/88nightrider/FiskumIT-CoreCyclerManager-Norsk/releases) for siste versjon, eller [README.txt](README.txt) for full endringslogg per versjon. Manageren har en innebygd "Sjekk etter oppdatering"-knapp som sjekker direkte mot dette repoet.

## Krav

- Windows 10/11 (64-bit) - 32-bits Windows støttes ikke
- Windows PowerShell 5.1 - følger med Windows som standard, ingen separat installasjon nødvendig
- **.NET Framework** (kreves av PowerShell sitt WinForms-grensesnitt) - er normalt allerede installert på en oppdatert Windows 10/11-maskin. Mangler det (f.eks. en svært minimal/Server Core-installasjon), kan det lastes ned fra [Microsofts offisielle nedlastingsside](https://dotnet.microsoft.com/en-us/download/dotnet-framework)

## Hvorfor dette finnes

CoreCycler er et kraftig verktøy, men er bygget for et engelsktalende, teknisk publikum som er komfortable med å lese rå konsolltekst og redigere `.ini`-filer manuelt. Fiskum IT bygde denne Manageren for å gjøre samme verktøy trygt brukbart for norske brukere uten den tekniske bakgrunnen - med fornuftige standardvalg, tydelige norske forklaringer i UI-et, og automatisk gjenoppretting hvis en undervoltet verdi skulle vise seg ustabil og krasje maskinen midt i en test.

## Hovedfunksjoner

- **Assistert undervolting** - søker automatisk etter den mest aggressive stabile Curve Optimizer-verdien per kjerne (AMD Ryzen 5000-serien/Zen 3 og nyere) eller en global spenningsforskyvning (Intel, 4. generasjon/Haswell og nyere, via det bundlede IntelVoltageControl-verktøyet)
- **Vanlig stabilitetstest** - kjører et CPU-tilpasset, kuratert standardsett av tester (Prime95 SSE/AVX/AVX2, y-cruncher, AVX512 der støttet), eller et fullt selvvalgt sett via "Avansert..."-dialogen
- **CPU-gjenkjenning** - oppdager faktisk maskinvarestøtte for AVX/AVX2/AVX512 og AMD/Intel-generasjon direkte fra Windows, og skjuler/grår ut tester og funksjoner som ikke er relevante for den aktuelle CPU-en
- **Automatisk gjenoppretting** - valgfri autostart ved innlogging, automatisk restart av maskinen ved et oppdaget krasj (med nedtellingsdialog du kan avbryte), og automatisk, reversibel Windows-autologon når det er nødvendig for at gjenopptak skal fungere
- **Bekreftelsesrunde** - etter et fullført søk kan du bekrefte de anbefalte (sikkerhetsmargin-justerte) verdiene med en lengre, fast kjøring uten nytt søk
- **Diagnostikkverktøy** ([Collect-FiskumITDiagnostics.ps1](Collect-FiskumITDiagnostics.ps1)) for enkel feilsøking/feilrapportering
- **Et lett Pester-testsett** for de mest risikofylte logikkfunksjonene (CPU-gjenkjenning, sikkerhetsmargin-beregning)

## Kom i gang

1. Last ned/klon dette repoet.
2. Dobbeltklikk `Installer.bat` i repo-roten (krever administrator-godkjenning).
3. Filene installeres til `C:\FiskumIT\CoreCyclerManager`, og en snarvei legges på skrivebordet.
4. Start via snarveien, velg modus, og trykk «Start / Gjenoppta».

CoreCycler-motoren (med Fiskum IT sine tilpasninger) følger allerede med i `CoreCycler\`-undermappen - ingen separat nedlasting nødvendig.

Full installasjons- og bruksveiledning, krav til CPU/Windows, og en detaljert endringslogg per versjon finner du i [`README.txt`](README.txt).

## ⚠️ Viktig om undervolting

Å sette en for aggressiv (for negativ) spenningsforskyvning kan gjøre systemet ustabilt - i verste fall vedvarende oppstartsproblemer (selv om dette normalt løses med en enkel CMOS-reset/strømtap, siden Curve Optimizer/MSR-verdier ikke er permanente maskinvareendringer). Manageren er bygget med flere lag med sikkerhetsnett (krasjgjenoppretting, konservative sikkerhetsmarginer, bekreftelsesrunde), men **bruk på egen risiko**. Ingen av sikkerhetsmarginene som vises er offisielle AMD- eller Intel-verdier - de er Fiskum IT sine egne, dokumenterte og forklarte tommelfingerregler.

## Mappestruktur

```
Manager/                            Selve GUI-scriptet og konfigurasjon
CoreCycler/                         sp00n sin CoreCycler-motor + Fiskum IT-tilpasninger
Installer.bat                       Installerer til C:\FiskumIT\CoreCyclerManager
README.txt                          Detaljert endringslogg per versjon
Collect-FiskumITDiagnostics.ps1/.bat Diagnostikkverktøy for feilrapportering
CoreCycler-Tilpasninger.md          Hva som er endret i selve CoreCycler-motoren vs. original
Utviklingslogg-Prosessorstotte.md   Utviklingslogg: CPU-/prosessorstøtte-arbeidet
Utviklingslogg-UI-Stabilitet.md     Utviklingslogg: UI- og stabilitetsfikser
Vedlikehold-Prosessorstotte.md      Guide for å oppdatere prosessorstøtte-logikken senere
```

Strukturen er flat og versjonsuavhengig - selve versjonsnummeret følges via git-tags/[Releases](https://github.com/88nightrider/FiskumIT-CoreCyclerManager-Norsk/releases), ikke mappenavn. De fire `.md`-filene i roten er interne utviklerlogger/-guider (på norsk), skrevet for at fremtidig videreutvikling - med eller uten tilgang til tidligere samtaler/kontekst - raskt skal kunne orientere seg i hvorfor ting er løst som de er.

## Kreditering og lisens

- **CoreCycler-motoren** er skrevet av [sp00n](https://github.com/sp00n/corecycler) og er lisensiert under **Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0)** - se [`CoreCycler/LICENSE`](CoreCycler/LICENSE). Fiskum IT sine endringer i motorscriptet er tydelig dokumentert i en egen `.MODIFICATIONS`-seksjon i toppen av [`script-corecycler.ps1`](CoreCycler/script-corecycler.ps1), og sp00n sitt opprinnelige forfatterskap/lisens er uendret.
- **IntelVoltageControl** (bundlet i `CoreCycler/tools/`) har sin egen lisens, se [`LICENSE.txt`](CoreCycler/tools/IntelVoltageControl/LICENSE.txt) i samme mappe.
- **Manager-koden** (GUI, automatisering, norsk oversettelse) er skrevet av Fiskum IT, som et derivat av/tillegg til CoreCycler. Siden CC BY-NC-SA 4.0 er en *ShareAlike*-lisens, distribueres Manager-koden under de samme vilkårene: ikke-kommersiell bruk, navngi opphavsperson, del videre under samme lisens.

Dette er **ikke** et offisielt Fiskum IT-produkt i kommersiell forstand - det er et internt verktøy delt åpent for andre som kan ha nytte av en norsk, automatisert CoreCycler-opplevelse.

## Testmaskiner

Manageren er utviklet og verifisert i praksis på AMD Ryzen 5000/7000-serien (Zen 3/Zen 4, ingen AVX512). Intel- og AVX512-støtte er bygget fra dokumentasjon/nettsøk, men kan ikke maskinvareverifiseres av Fiskum IT i dag - se README.txt for fulle forbehold per funksjon.
