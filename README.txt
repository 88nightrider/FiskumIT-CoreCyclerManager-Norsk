Fiskum IT CoreCycler Manager v0.8.7.1
============================================================

Nyheter i v0.8.7.1
-------------------
- Installer.bat legger na automatisk til et Windows Defender-unntak
  for "C:\FiskumIT" under installasjon. Dette reduserer risikoen for
  at CoreCycler-motorens DLL-injeksjonsteknikk (brukt til a lese
  y-cruncher sin konsoll-output ved automatisk binaervalg) blir
  blokkert (sett pa TEST-01 i v0.8.7). Feiler stille med kun en
  advarsel hvis Defender ikke er tilgjengelig/aktivt

Nyheter i v0.8.7
----------------
- Rettet at autologon ALDRI fungerte pa kontoer uten passord (sett pa
  WANJA-GAMER): et forsok pa a lagre et tomt passord ble feilaktig
  tolket som en feilet sletting av en LSA-secret som aldri har
  eksistert. Hopper na ogsa over selve passord-prompten helt nar
  kontoen bekreftet ikke har passord
- Rettet at sluttrapport-popup/bekreftelsesrunde-sporsmal kom for
  tidlig, og at autologon/autostart ble fjernet for tidlig, nar
  "Aggressivt undervolt-sok" automatisk gikk videre til
  "Stabilitetstest (auto-juster ved feil)" (sett pa NR-GAMER)
- Rettet at Avansert-dialogen avhuket ALLE CPU-stottede tester fra
  start pa en fersk installasjon - na er kun de stjernemerkede
  (anbefalte) testene avhuket fra start
- Rettet at tittelen i selve vinduet viste en hardkodet, utdatert
  versjon. Versjonsnummeret er na flyttet til en liten, nedtonet
  etikett i ovre hoyre hjorne
- Rettet en UI-bug (sett pa NR-GAMER, 1440p) der en gra "blokk" la seg
  nederst i vinduet etter at det ble krympet fra en lagret, storre
  hoyde. "Siste CoreCycler-logg" blir na ogsa hoyere nar vinduet har
  plass til det
- Rettet at samling av loggfiler (Collect-FiskumITDiagnostics.ps1)
  kunne feile med "samlingen hadde en fast storrelse"
- Skjuler na cmd.exe-vinduet som tidligere dukket opp ved et
  automatisk gjenopptak etter restart (kunne lukkes ved et uhell, og
  dermed avslutte hele programmet)
- "Handlinger" har na en "Verktoy..."-knapp (apne siste logg, apne
  skrivebordsrapport, nullstill state, apne config-mappe, deaktiver
  autologon) og en "Hjelp"-knapp med en innebygd bruksveiledning
- "Automatisk gjenoppretting" har na "Aktiver"/"Deaktiver"-knapper i
  stedet for to avhukinger
- Testmodusene er omdopt for a vaere mer beskrivende: "Assistert
  undervolting" -> "Aggressivt undervolt-sok", "Vanlig
  stabilitetstest" -> "Stabilitetstest (auto-juster ved feil)"
- CoreCyclers automatiske gjenopprettingspunkt (hver 24. time) heter
  na "Fiskum IT - Automatic Test Mode" i stedet for "CoreCycler
  Automatic Test Mode"

Nyheter i v0.8.6
----------------
- Alle test-configene i Manager\config (alle Prime95/y-cruncher/Linpack-
  varianter + AssistedUndervolting_Intel/Ryzen) har na beepOnError = 0
  og flashOnError = 0 i stedet for 1 - ingen pip/skjermblink ved en
  oppdaget feil under testing

Nyheter i v0.8.5
----------------
- Rettet en "Fremdrift"-bug (sett pa WANJA-GAMER, fortsatt pa v0.8.2,
  2026-06-23): viste absurde tall som "7/5 tester (100%)" under en
  kuratert standardtest-kjoring. Rotarsak: fremdriften brukte den rA
  test-ID-en fra testplan.json direkte som "antall fullforte tester" -
  riktig kun nar testplanen er ALLE tester i rekkefolge, men feil sa
  snart planen er et filtrert delsett (kuratert standardsett/Avansert-
  valg/CPU-stotte) der ID-ene ikke er sammenhengende fra 1. Teller na i
  stedet faktisk POSISJON i den aktive testplanen. Ny regresjonstest lagt
  til i Pester-settet

Nyheter i v0.8.4
----------------
- Den automatiske oppdateringssjekken ved oppstart viser na ogsa en popup
  ("Ny versjon tilgjengelig: vX.Y.Z" + lenke til nedlastingssiden) hvis en
  nyere versjon blir funnet - ikke bare en endret knappetekst pa "Sjekk
  etter oppdatering"-knappen, som var lett a overse. Sjekken (og en
  eventuell popup) kjores na ETTER at hovedvinduet er synlig, ikke for

Nyheter i v0.8.3
----------------
- Ny popup-varsling nar en hel testplan/sok er fullfort: viser anbefalt
  sikkerhetsmargin (hvis relevant) og henviser til den fullstendige
  rapporten pa skrivebordet. Tidligere ble en fullfort "Vanlig
  stabilitetstest" kun logget, uten synlig varsling i UI'et
- Passordsporsmalet for Windows-autologon (auto-restart ved krasj/feil)
  kommer na nar du trykker "Start" (eller F5) - ikke forst nar en feil
  faktisk oppstar, som gjorde det upraktisk hvis du ikke sitter ved
  maskinen. Ny forklarende tekst i UI'et og i selve passord-dialogen
- Rettet noen steder der "ø" og "a" var feilstavet som vanlig "o"/"a" i
  Avansert-dialogen og CPU-stotte-statusen (f.eks. "stotter" -> "støtter")
- "Download ZIP" og kildekode-zip pa GitHub Releases inneholder na kun de
  faktiske programfilene (samme sett som distribueres lokalt), ikke
  repo-metadata/utvikler-dokumentasjon (.gitattributes export-ignore)

Nyheter i v0.8.2
----------------
- Ny logging av ressursbruk: RAM-prosent og navnet/minnebruken til den ene prosessen
  som bruker mest RAM, logget ca. hvert 60. sekund i Manager-loggen. Bygget direkte
  som svar på et reelt systemkrasj (minneuttømming) på NR-GAMER 2026-06-21, der ingen
  logg viste opptrappingen underveis - kun de endelige feilmeldingene da det allerede
  var for sent
- To nye valg i UI'et, i en ny gruppe "Automatisk gjenoppretting":
  - "Autostart Manageren ved innlogging" - gjør den eksisterende, tidligere alltid
    aktive Scheduled Task-funksjonen til et eksplisitt valg (default AV)
  - "Auto-restart datamaskinen ved krasj/feil" - ved en oppdaget feil (status "Feil",
    inkl. et krasj oppdaget ved oppstart) restarter Manageren nå datamaskinen helt
    automatisk, med en 60 sekunders nedtelling/avbryt-mulighet på skjermen først.
    Krever (og aktiverer selv) "Autostart". Stopper automatisk etter 3 påfølgende
    restarts uten en fullført test mellom dem, for å unngå en uendelig reboot-løkke
  - Nytt tallfelt: "Minutter å vente etter restart før gjenopptak" (standard 5) - gir
    Windows tid til å bli stabilt etter oppstart før testen presses videre
- Windows-autologon konfigureres nå automatisk ved behov når "Auto-restart" er i bruk
  (du blir bedt om å bekrefte passordet ditt) - kun hvis det IKKE allerede er satt opp.
  Passordet lagres ALDRI i klartekst: det skrives som et LSA "secret" (samme teknikk
  som Microsofts eget Sysinternals "Autologon"-verktøy bruker), ikke i
  HKLM\...\Winlogon\DefaultPassword. Alt Manageren selv setter opp (både
  Scheduled Task og autologon) fjernes automatisk igjen når en test fullføres eller
  stoppes bevisst - og hvis autologon allerede var konfigurert av noe ANNET enn
  Manageren, røres den aldri, verken ved oppsett eller opprydding
- Collect-FiskumITDiagnostics.ps1 rapporterer nå også om AutoStart-Scheduled-Task og
  Windows-autologon er aktivert (kun status, aldri passord), for lettere feilsøking
  av en fremtidig "gjenopptok ikke automatisk"-sak
- Sikkerhetsfiks: brukernavnet ble tidligere logget 4 steder (3 i Manager-loggen ved
  autologon-oppsett, 1 i diagnostikk-rapporten) - fjernet helt. Passordet har aldri
  blitt logget noe sted
- script-corecycler.ps1 (motorscriptet) har nå en egen "MODIFICATIONS"-seksjon i
  header-kommentaren som lister opp hva Fiskum IT faktisk har endret der (offset-
  snapshot-systemet, "Decreasing"-søkeretningen, et par bugfikser) - sp00n sin
  opprinnelige forfatterskap/lisens er uendret
- Ny test: "y-cruncher AVX512 1 thread" - tilgjengelig for CPUer som faktisk støtter
  AVX512 (vises automatisk i "Avansert...", gråtonet ut på andre CPUer). For AMD
  Zen4/Zen5 velges automatisk riktig y-cruncher-modus ved teststart; kan ikke
  maskinvaretestes av Fiskum IT (ingen tilgjengelig AVX512-maskin)
- "Vanlig stabilitetstest" sin STANDARD er nå et kuratert, CPU-tilpasset sett på 5-6
  tester (ett representativt valg per instruksjonssett-nivå: SSE/AVX/AVX2×2/AVX512,
  pluss y-cruncher auto) i stedet for alle CPU-støttede tester (kunne være 20+).
  Samme instruksjonssett-filter som før sørger for at også eldre CPUer automatisk får
  et fornuftig standardvalg. Disse testene kjører nå også 2 runder hver i stedet for
  1 (flere kjøres allerede med 2 fra tidligere) - alle andre tester er fortsatt
  tilgjengelige via "Avansert...". Berører ikke en eksisterende, lagret "Avansert..."
  -velg - kun helt ferske installasjoner/brukere som aldri har åpnet dialogen
- UI-vinduet er gjort lavere og skalerbart: "Modus", "Automatisk gjenoppretting",
  "Fremdrift" og "Siste CoreCycler-logg" sitter nå i et rullbart felt under en fast
  topp-sone (Status/Handlinger er alltid synlig). Standardstørrelse redusert fra
  1260×1208 til 1260×900 (passer komfortabelt på en 1080p-skjerm med oppgavelinjen),
  og vinduet kan nå skaleres ned til 1260×540 for bruk på mindre skjermer (ned mot
  720p) - innhold som ikke får plass scroller i stedet for å klippes
- Anbefalt-margin i sluttrapporten tar nå også høyde for hvor grundig søket faktisk
  var (total tid brukt delt på antall testede kjerner) - et uvanlig raskt søk (under
  8 minutter/kjerne i snitt) får automatisk 2 ekstra i margin, med forklaring i
  rapporten. Fiskum IT sin egen tommelfingerregel, ikke en offisiell AMD/Intel-verdi
- Ny "bekreftelsesrunde": etter et fullført Assistert undervolting-søk spør
  Manageren nå om du vil bekrefte de anbefalte (margin-justerte) verdiene med en
  lengre "Vanlig stabilitetstest"-kjøring som bruker de faste verdiene direkte
  (ikke et nytt søk). Svarer du Ja, fjernes motorens offset-snapshot automatisk
  først (ellers ville den gamle, mer aggressive søkeverdien blitt brukt i stedet)
- Sluttrapporten arkiveres nå også tidsstemplet i Manager\logs\ (skrivebordsfilen
  inneholder fortsatt kun siste kjøring, men historikken går ikke tapt)
- "Avansert..."-dialogen markerer nå de kuraterte standardtestene med ★ og fet
  skrift, slik at det er synlig hvilke som faktisk brukes av "Vanlig stabilitetstest"
  sin standard
- Vindusstørrelse og -posisjon lagres nå ved lukking og gjenopprettes ved neste
  oppstart
- Nytt, lett Pester-testsett (Manager\Tests\Manager.Tests.ps1) for de mest
  risikable/rene logikkfunksjonene (CPU-gjenkjenning, margin-beregning) - kjøres
  med Invoke-Pester, ikke en del av selve installasjonen

Nyheter i v0.8.1
----------------
- Rettet en alvorlig visningsbug funnet pa WANJA-GAMER (2026-06-21): "Siste
  CoreCycler-logg" viste naermest ingenting og virket til a "forsvinne oppover"
  - rotarsak var at Get-KonsollLinjeFarge hadde [Parameter(Mandatory)] pa en
  [string]-parameter, som feiler pa TOMME STRENGER (ikke bare $null) - ekte
  CoreCycler-logglinjer inneholder ofte blanke linjer, sa visningen krasjet ved
  forste blanke linje hver gang. Dette krasjet helt opp til hovedtimeren, som
  IKKE bare avbrøt selve loggvisningen, men ogsa hindret lesingen av motorens
  offset-snapshot - sa Offset-rekken/skrivebordsloggen sa heller ikke ut til a
  oppdatere seg, til tross for at sokemotoren fungerte helt korrekt i
  bakgrunnen hele tiden. Timer-en kjorer na hvert av sine 3 deloppgaver i EGEN
  try/catch, slik at en feil i en av dem ikke kan sulteforde de andre
- "Siste CoreCycler-logg" viser na nyeste hendelse forst (ovenfra), med
  historikk som vokser nedover - ikke kun siste linje nederst som tidligere
- Rettet synlig "flimring" (med ujevne mellomrom) i "Siste CoreCycler-logg":
  boksen ble tomt og bygget opp pa nytt hvert tick (hvert 1,5 sekund) uansett
  om noe nytt faktisk var logget - derav den ujevne folelsen, siden CoreCycler
  ikke nodvendigvis logger en ny hendelse pa hvert tick. Hopper na over hele
  ombygningen nar innholdet er uendret, og bruker WM_SETREDRAW til a skjule
  skjermmalingen for de tick-ene der innholdet faktisk endrer seg
- "Siste CoreCycler-logg" rydder na opp RichTextBox-ens interne angre-historikk
  (ClearUndo) etter hver ombygning - uten dette vokser minnebruken sakte men
  ubegrenset over en langvarig kjoring. Funnet som en sannsynlig medvirkende
  arsak til "System.OutOfMemoryException" pa NR-GAMER etter en ~17-timers
  sammenhengende korsel (se Utviklingslogg-UI-Stabilitet.md for detaljer)
- Fant og rettet 4 til na ukjente forekomster av samme StrictMode-felle som
  Write-DesktopLog hadde (".PSObject.Properties.Name" kaster en feil nar
  samlingen har 0 elementer, men fungerer fint med 1+) - ny felles
  hjelpefunksjon Get-PropertyNames brukes na alle 12 stedene i koden som leser
  navn pa dynamiske felt (state.json-reparasjon, offset-rekke-formatering,
  laaste kjerner-sjekk m.m.)
- Installer.bat utelater na "logs"-mappene og state.json/avansert-valg.json fra
  kopieringen - disse er kjoretids-/brukerdata for DEN gjeldende maskinen, og
  skal ikke overskrives av eller blandes sammen med en (ny) installasjon
- Curve Optimizer-verdier forsvinner ikke lenger mellom tester/moduser: alle
  tester (inkl. Assistert undervolting selv) leser nå alltid fra den løpende
  offset-snapshot-filen først, i stedet for å lese "CurrentValues" direkte fra
  CPU-en - som med setVoltageOnlyForTestedCore=1 kun ville gitt riktig verdi for
  sist testede kjerne, og 0 for alle andre
- Krasjgjenoppretting skriver nå den korrigerte verdien tilbake til
  snapshot-filen (ikke bare til CPU-en), slik at et nytt krasj/gjenopptak alltid
  bygger videre på riktig grunnlag
- "Nullstill" i Manageren fjerner nå også snapshot-filen, for et reelt blankt
  blad
- Skrivebordsloggen (FiskumIT-CoreCycler-Logg.txt) skriver nå faktisk innhold
  løpende og en sluttoppsummering med per-kjerne-verdier - to separate bugs
  gjorde at den tidligere kun fikk en tom header
- Collect-FiskumITDiagnostics fant tidligere ingen loggfiler på en ferdig
  installert maskin (kun på utviklingsmaskinen) - finner nå Manager\logs og
  CoreCycler\logs riktig uansett hvor den kjøres fra
- Installer.bat: fikset en bug der sluttsammendraget skapte to feilplasserte,
  navnløse filer ("Fiskum"/"Generer") i kildemappen, forårsaket av at cmd.exe
  tolket "->" som en omdirigering
- Det separate CoreCycler-konsollvinduet vises ikke lenger - "Siste CoreCycler-
  logg" i Manager-UI'et viser na et fargelagt, filtrert ekvivalent av det
  samme innholdet (feil i rødt, advarsler i gult, vellykkede
  hendelser/overskrifter i grønt), i ett samlet vindu
- "State og historikk"-panelet er fjernet fra UI'et (Manager-intern bokføring,
  ikke interessant for vanlige brukere) - hendelsene logges fortsatt i sin
  helhet til Manager\logs\, og fanges opp av Collect-FiskumITDiagnostics
- Mørkt fargetema i hele UI'et (hovedvindu og "Avansert..."-dialogen)
- "y-cruncher Ryzen 3000/5000 1/2 thread(s)" er endret til "y-cruncher (auto)
  1/2 thread(s)" - bruker na yCruncher sin egen automatiske valg av riktig
  binær for prosessoren (mode = auto) i stedet for en hardkodet Zen 2-spesifikk
  binær (19-ZN2), og fjerner samtidig den feilaktig snevre "kun Ryzen
  3000/5000"-antagelsen fra navnet (config-filene er omdøpt til
  YCRUNCHER_AUTO_1.ini/YCRUNCHER_AUTO_2.ini)
- Fjernet "for AMD Ryzen 3000/5000" fra tittel/branding
- Ny CPU-sjekk for AVX/AVX2/AVX512-stotte (Windows' egen
  IsProcessorFeaturePresent): testene i "Avansert..." som krever et
  instruksjonssett denne CPU-en ikke har, er na gratt ut og kan ikke hukes av,
  og den vanlige stabilitetstest-planen hopper automatisk over dem - slik
  fungerer testvalget korrekt pa alle x86-64-CPU'er (AMD og Intel, gamle og
  nye), ikke bare de som stotter samme sett som AMD Ryzen 3000/5000
- "Assistert undervolting" stotter na ogsa Intel (i tillegg til AMD Ryzen):
  - AMD: krever Ryzen 5000-serien/Zen 3 eller nyere (Curve Optimizer finnes
    ikke pa eldre Ryzen 1000/2000/3000/4000) - sikkerhetsgrensen nedover
    (minValue) settes na automatisk til riktig verdi for generasjonen (-30 for
    5000/6000-serien, -50 for 7000-serien og nyere), i stedet for alltid -30
  - Rettet (etter videre nettsok) en reell feilkilde for AMD: modellnummeret
    ALENE ("5000 eller nyere") er IKKE til a stole pa for bærbare Ryzen-CPU-er.
    AMD har solgt ekte Zen 2-silisium (uten Curve Optimizer) under BADE "Ryzen
    5000"-serien ("Lucienne": Ryzen 3 5300U/Ryzen 5 5500U/Ryzen 7 5700U) OG
    "Ryzen 7000"-serien ("Mendocino": Ryzen 3 7320U/Ryzen 5 7520U) - til
    forveksling like modellnumre som ekte Zen 3/Zen 4 i samme serie (f.eks.
    5600U/5800U er ekte Zen 3 "Cezanne"). Manageren sjekker na CPUID Family
    (lest fra Windows, ikke bare modellnavnet) for a avgjore ekte
    silisium-generasjon og unnga a feilaktig godkjenne disse - se
    AssistedUndervolting_Ryzen.ini for full forklaring. Stasjonaere Ryzen-CPU-er
    er ikke kjent rammet av denne navngivningsforvirringen
  - Intel: ny profil (AssistedUndervolting_Intel.ini) som bruker det allerede
    bundlede IntelVoltageControl-verktoyet (MSR 0x150, 4. generasjon Haswell
    og nyere). Soker EN global spenningsforskyvning for hele CPU-en (Intel har
    ingen per-kjerne-kontroll som AMD), IKKE GARANTERT A FUNGERE - mange
    nyere Intel-systemer later denne MSR-en i BIOS som sikring mot
    "Plundervolt"-svakheten, og det finnes ingen dokumentert sikker
    minimumsverdi for Intel slik AMD har -30/-50
  - Utvidet (etter videre nettsok) med generasjons- og bærbar/stasjonær-bevisst
    tillitsvurdering for Intel - sannsynligheten for at spenningsforskyvningen
    faktisk fungerer varierer mye: historisk mest pålitelig pa 4.-9. gen
    (Haswell-Coffee Lake), Plundervolt-låsing ble vanlig pa bærbare fra 10. gen
    (Ice Lake/Comet Lake) og oppover, mobile Tiger Lake (11. gen) er ofte last
    helt av Intel selv, og 12.-14. gen (Alder Lake/Raptor Lake) varierer sterkt
    per hovedkort (se "CPU-stotte" og AssistedUndervolting_Intel.ini for full
    forklaring). Bærbare/OEM-modeller (suffiks U/Y/H/HX/G i CPU-navnet) er i
    alle generasjoner mer utsatt for last spenningskontroll enn stasjonære.
    Manageren viser en kort statuslinje i "Modus"-panelet og logger den fulle,
    generasjonsspesifikke forklaringen til Manager-loggen ved hver oppstart
  - "Modus"-panelet i UI'et viser na hvilken CPU som er oppdaget og hvorfor
    Assistert undervolting er (eller ikke er) tilgjengelig - radioknappen
    grases ut og kan ikke velges pa en ustottet CPU (f.eks. Ryzen eldre enn
    5000-serien, eller en CPU-familie som ikke er vurdert)

Mappestruktur
-------------
(flat, versjonsuavhengig struktur - versjonsnummer folges via git-tags/GitHub Releases,
ikke mappenavn, se https://github.com/88nightrider/FiskumIT-CoreCyclerManager-Norsk/releases)

Installer.bat
README.txt
Manager\
  FiskumIT-CoreCyclerManager.ps1
  FiskumIT-Logo.ico
  Start-FiskumIT-CoreCyclerManager.bat
  Stopp-CoreCycler-Prosesser.bat
  Nullstill-State.bat
  testplan.json
  state.json
  avansert-valg.json   (lages av "Avansert..."-dialogen, valgfritt)
  config\         (CoreCycler-config-presets, inkl. AssistedUndervolting_Ryzen.ini
                   og AssistedUndervolting_Intel.ini)
CoreCycler\       (sp00n/corecycler - script-corecycler.ps1 m.m.)

Installasjon
------------
1) Last ned CoreCycler fra https://github.com/sp00n/corecycler og legg
   innholdet i mappen "CoreCycler" ved siden av Installer.bat (eller bruk
   den medfølgende CoreCycler-mappen, som allerede inneholder Fiskum IT sine
   tilpasninger).
2) Dobbeltklikk Installer.bat. Godkjenn UAC-prompten som dukker opp.
3) Filene kopieres til C:\FiskumIT\CoreCyclerManager og en snarvei
   "Fiskum IT CoreCycler Manager" legges på skrivebordet.

Bruk
----
Start via skrivebordssnarveien. Velg modus ("Assistert undervolting" eller
"Vanlig stabilitetstest") i Modus-boksen før du trykker "Start / Gjenoppta".

Manageren logger alt til en enkelt fil på skrivebordet:
FiskumIT-CoreCycler-Logg.txt

Den viser bl.a.:
- "Set to Core" fra CoreCycler-loggen
- Hele Curve Optimizer offset-rekken for alle kjerner, og en egen
  per-kjerne-tabell med status (under søk/aktiv, eller låst)

CPU-støtte
----------
Vanlig stabilitetstest fungerer på alle x86-64-CPU'er (testene som krever
AVX/AVX2/AVX512 grås ut automatisk på en CPU uten støtte, se "Nyheter i
v0.8.1"). Dette er bekreftet ved nettsøk å gjelde i praksis HELE x86-64-æraen:
- x86-64 fantes ikke før 2003 (AMD Opteron/Athlon 64) - Intel sin variant
  (EM64T) kom i 2004. "x86-64-CPU fra år 2000" er derfor i praksis "fra første
  x86-64-CPU i 2003" - eldre, rene 32-bits CPU-er faller utenfor uansett, siden
  de ikke kan kjøre 64-bits Windows/PowerShell som Manageren krever
- SSE2 er et OBLIGATORISK krav i selve x86-64-spesifikasjonen (bekreftet: alle
  x86-64-v1-baseline-CPU-er må ha CMOV/CX8/SSE/SSE2 m.m.) - de vanlige
  stabilitetstestene (Prime95 SSE, y-cruncher, Linpack) krever aldri mer enn
  dette som minimum, og vil derfor kjøre på 100% av x86-64-CPU-er uten unntak,
  uansett alder
- AVX kom i 2011 (Intel Sandy Bridge/AMD Bulldozer), AVX2 i 2013 (Intel
  Haswell)/2015-2017 (AMD). Disse testene grås ut korrekt på eldre CPU-er fordi
  sjekken leser CPU-ens FAKTISKE maskinvarestøtte direkte fra Windows
  (IsProcessorFeaturePresent), ikke en gjetning basert på CPU-navn/-alder -
  dette gir riktig svar selv for spesialtilfeller som budsjett-CPU-er der
  AVX2 er deaktivert i mikrokode (f.eks. enkelte Pentium/Celeron-modeller)

"Assistert undervolting" krever:
- AMD Ryzen 5000-serien (Zen 3) eller nyere - Curve Optimizer finnes ikke på
  eldre Ryzen-generasjoner
- Eller Intel Core i3/i5/i7/i9, 4. generasjon (Haswell) eller nyere - IKKE
  garantert å fungere, se "Nyheter i v0.8.1". Sannsynligheten for at det
  faktisk fungerer varierer mye med generasjon og om CPU-en er bærbar/OEM
  eller stasjonær (basert på nettsøk om kjente BIOS-/Plundervolt-låsinger):
    - 4.-9. gen (Haswell-Coffee Lake): historisk mest pålitelig
    - 10. gen (Ice Lake/Comet Lake): ofte låst på bærbare, mindre på stasjonære
    - 11. gen (Rocket Lake/Tiger Lake): mobile Tiger Lake ofte låst av Intel
      selv, stasjonær Rocket Lake mer åpen
    - 12.-14. gen (Alder Lake/Raptor Lake): varierer sterkt per hovedkort -
      BIOS-intern spenningsforskyvning er ofte et bedre alternativ enn denne
      kjørende-Windows-metoden for disse generasjonene
    - 15.+ gen: for nytt til at det finnes dokumentasjon om denne metoden
  Manageren viser en kort statuslinje i "Modus"-panelet og logger en full,
  generasjonsspesifikk forklaring til Manager-loggen ved hver oppstart.

Manageren oppdager og viser selv hvilken CPU som er funnet og hvorfor
Assistert undervolting er (eller ikke er) tilgjengelig.
