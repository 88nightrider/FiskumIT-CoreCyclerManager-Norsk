---
Formål: kronologisk utviklingslogg for UI- og stabilitetsfiksene i Fiskum IT
CoreCycler Manager (live-loggvisning, StrictMode-fallgruver, timer-robusthet,
Installer.bat datasikkerhet). Skrevet for å kunne flyttes mellom flere
utviklingsmaskiner uten å være bundet til en bestemt mappe/stasjonsbokstav.
Se også: Utviklingslogg-Prosessorstotte.md (CPU-deteksjon/undervolt-støtte,
en helt separat tema-logg) og README.txt sin "Nyheter i vX.Y"-seksjon i hver
versjonsmappe (den detaljerte, versjonsbundne endringsloggen).
---

# Utviklingslogg - UI og stabilitet

Dette er en logg over HVORFOR ting ble bygget/fikset som de ble, ikke en
detaljert endringslogg (den finnes i `README.txt`). Alle funn under kom fra
faktiske diagnose-pakker (`.diag`-filer) og skjermbilder fra testmaskinen
WANJA-GAMER, ikke spekulasjon - se hvert punkt for hvordan det ble bekreftet.

## 1. "Siste CoreCycler-logg" virket å "forsvinne oppover"

**Symptom rapportert av bruker**: loggvisningen i UI-et viste nesten ingenting
og virket til å bare vise siste verdi, som om alt eldre innhold "forsvant
oppover" etter hvert.

**Rotårsak** (funnet via en `.diag`-pakke fra WANJA-GAMER og isolert
PowerShell-testing): `Get-KonsollLinjeFarge` hadde `[Parameter(Mandatory)]`
på en `[string]`-parameter. Under `Set-StrictMode -Version Latest` feiler et
slikt kall på en **tom streng** (ikke bare `$null`) - ekte CoreCycler-
logglinjer inneholder ofte blanke linjer, så funksjonen krasjet konsekvent
ved første blanke linje i hver ombygning. Samme grunnfeil-KLASSE som tidligere
ble funnet i `Write-DesktopLog` (der var det et `[string[]]`-array med ett
tomt element som var problemet, her et enkelt `[string]`).

**Alvorlig kaskadeeffekt**: krasjet kastet seg helt opp til hovedtimerens
felles try/catch, som dekket BÅDE `Refresh-CoreCyclerLogView`,
`Handle-ProcessFinished` og `Refresh-UiState` i én blokk. Det betyr at en feil
i loggvisningen også stoppet `Refresh-CoreCyclerLogView` sin EGEN, senere
lesing av motorens offset-snapshot-fil - så "Offset-rekke" og skrivebords-
loggen sluttet også å oppdatere seg, til tross for at selve søkemotoren
fungerte helt korrekt i bakgrunnen hele tiden. Bekreftet direkte: samme
WANJA-GAMER-logg viste Curve Optimizer gå fra -1 til -16 på Core 0 og videre
til Core 3 (-9 til -10) over de 43 minuttene brukeren observerte "ingen
endring" i UI-et - testen var ALDRI fastlåst, bare usynlig pga. denne bugen.

**Fiks**:
- Fjernet `Mandatory` fra `Get-KonsollLinjeFarge` (samme mønster som
  `Write-DesktopLog`-fiksen).
- Hovedtimeren kjører nå hver av sine 3 deloppgaver i EGEN try/catch, slik at
  en feil i én av dem ikke kan sulteforde de andre igjen i fremtiden.
- `Refresh-CoreCyclerLogView` har nå også en egen try/catch rundt selve
  `Set-LiveLogView`-kallet, som ekstra beskyttelse i tillegg til rotfiksen.

**Verifisert**: kjørt isolert mot de siste 1500 rå linjene fra den faktiske,
980KB store WANJA-GAMER-loggen (samme fil som opprinnelig krasjet) - 0 krasj
etter fiksen. Deretter kjørt live i selve Manager-UI-et med samme logg lastet
inn, bekreftet skjermbilde med rik, flerlinjes, fargelagt historikk.

## 2. Nyeste hendelse vises nå øverst

Brukeren ønsket at loggvisningen skulle vokse nedover (eldste nederst, nyeste
øverst) i stedet for motsatt - slik at man kan se siste hendelse uten å
scrolle. Implementert i `Set-LiveLogView` med `[array]::Reverse()` på listen
av konsoll-ekvivalente linjer før de skrives til boksen, og caret satt til
posisjon 0 (i stedet for slutten) etter ombygning. Verifisert i samme
skjermbilde som punkt 1 - toppen av boksen viste korrekt den faktisk siste
hendelsen fra loggfilen (Core 3, -9 til -10, kl. 19:17:15).

## 3. ".PSObject.Properties.Name"-fellen - 4 nye forekomster

**Bakgrunn**: `Write-DesktopLog`-fiksen avdekket en TREDJE StrictMode-
fallgruve-klasse i denne kodebasen (etter Mandatory-på-array og lesing av
ikke-eksisterende JSON-egenskap/aldri-satt Script-variabel): et kall som
`(NoeObjekt).PSObject.Properties.Name` kaster "The property 'Name' cannot be
found on this object" - men KUN når samlingen `.PSObject.Properties` har
NULL elementer. Med 1 eller flere egenskaper fungerer akkurat samme kall helt
fint. Reprodusert isolert: `$emptyObj = [pscustomobject]@{}` etterfulgt av
`@($emptyObj.PSObject.Properties.Name)` kaster under StrictMode, mens et
objekt med minst én egenskap ikke gjør det.

**Hvordan funnet i praksis**: en try/catch lagt til defensivt i
`Write-DesktopSnapshot` (for å logge objekttype ved feil) fanget akkurat
denne feilen på en ekte WANJA-GAMER-kjøring - et tomt `coreOffsets`- eller
`laasteKjerner`-objekt (helt gyldig tilstand, f.eks. før noen kjerne er låst
ennå) trigget feilen.

**Fiks**: ny felles hjelpefunksjon `Get-PropertyNames` (rett før
`Repair-State`) som sjekker `.Count -eq 0` før den prøver `.Name`-
enumereringen, og returnerer et tomt array i så fall i stedet for å krasje.
Et grep gjennom hele scriptet fant 12 forekomster av det utrygge mønsteret
totalt (i `Repair-State`, `Format-OffsetRekke`,
`Update-CurveOptimizerStateFromLog`-området og `Write-DesktopSnapshot`) - alle
12 erstattet med `Get-PropertyNames`-kall.

**Verifisert**: isolert PowerShell-repro av selve StrictMode-fellen (over),
samt AST-syntakssjekk av hele scriptet etter refaktoreringen.

## 4. Synlig "flimring" i loggvisningen

**Symptom rapportert av bruker**: etter at punkt 1 var fikset, flimret
loggboksen synlig "med ujevne mellomrom".

**Rotårsak**: `Set-LiveLogView` tømte (`.Clear()`) og bygde opp HELE boksen
fra grunnen på hvert UI-tick (hvert 1,5 sekund) - uavhengig av om CoreCycler
faktisk hadde logget noe nytt siden forrige tick. Brukerens "ujevne
mellomrom"-observasjon var korrekt presis: selve ombygningen skjedde på et
helt jevnt klokkeslett, men var bare SYNLIG som flimring på de tick-ene der
innholdet faktisk endret seg - og CoreCycler logger ikke nødvendigvis en ny
konsoll-hendelse på hvert tick.

**Fiks**, to deler:
- Bygger en sammenligningsstreng av innholdet og hopper over HELE
  Clear()+ombygning-syklusen når innholdet er identisk med forrige tick
  (cachet i `$Script:SisteLiveLogInnhold`) - dette eliminerer flimring helt
  på de (mange) tick-ene uten noe nytt å vise.
- For tick-ene der innholdet FAKTISK endrer seg: ny `Add-Type`
  (`FiskumIT.NoFlicker`) mot `user32.dll`s `SendMessage`, brukt til å sende
  `WM_SETREDRAW` (0x000B) `false` før ombygningen og `true` etter - dette er
  en etablert, velkjent WinForms-teknikk for å undertrykke selve
  skjermmalingen (ikke det samme som `SuspendLayout`/`ResumeLayout`, som bare
  gjelder kontroll-LAYOUT) mens kontrollen tømmes og bygges opp på nytt, slik
  at brukeren bare ser sluttresultatet i ett steg i stedet for et kort synlig
  "tomt → fylles opp igjen"-blink.

**Verifisert**: kjørt live i Manager-UI-et med en logg som inneholder blanke
linjer (samme type innhold som opprinnelig krasjet i punkt 1) - ingen krasj,
korrekt nyeste-først-sortering og fargelegging beholdt etter endringen.

## 5. Installer.bat - datasikkerhet ved (re)installasjon

Oppdaget i to omganger mens en WANJA-GAMER-diagnose ble undersøkt:

**Del 1 - brukerdata**: dev-trærets egen `Manager\state.json` inneholdt
utviklingsmaskinens eget testforløp. `Installer.bat` sin robocopy var
ubetinget (`/E` overskriver alltid filer med samme navn) - en (re)installasjon
ville dermed slette ekte testfremdrift på målmaskinen. Fikset med
`/XF state.json avansert-valg.json` - begge er kjøretids-/brukerdata for DEN
gjeldende maskinen, ikke kildefiler, og Manageren lager selv friske
standardverdier ved første oppstart hvis de mangler.

**Del 2 - logg-sammenblanding mellom maskiner**: brukerens faktiske
arbeidsflyt kopierer hele dev-treet (inkl. `Manager\logs\` og
`CoreCycler\logs\`) direkte til WANJA-GAMER, ikke bare via `Installer.bat`.
Dette ble bekreftet å ha blandet sammen utviklingsmaskinens EGNE
testkjøringer med WANJA-GAMER sine i samme loggfil (samme dato = samme
filnavn, eksakte tidsstempel-treff bekreftet sammenblandingen) - svært
forvirrende ved feilsøking. Fikset med `/XD logs` på begge robocopy-linjene
(Manager og CoreCycler), samt fjernet utviklingsmaskinens egen liggende logg
fra selve kildemappen for å unngå at den følger med på neste kopiering
uansett metode.

**Verifisert**: lesning av `Installer.bat` etter endring (manuell
gjennomgang av robocopy-flaggene), samt direkte tidsstempel-sammenligning
mellom de to maskinenes logg-oppføringer som beviste den opprinnelige
sammenblandingen.

## 6. Systemfrys på NR-GAMER - minneuttømming, IKKE (primært) silisium-ustabilitet

**Symptom rapportert av bruker**: maskinen frøs helt (svart skjerm,
explorer.exe så ut til å restarte) under en EGENDEFINERT, mye tyngre
"Assistert undervolting"-test (8 ulike yCruncher-deltester à 60 sek hver,
`mode=19-ZN2` hardkodet i stedet for `auto`, kjørt sammenhengende i ca. 17
timer - se `AssistedUndervolting_Ryzen.ini` i `Loggfiler for utvikling`-mappen
(het tidligere `Feil`) for den faktiske
konfigurasjonen som ble brukt). Brukerens egen hypotese var i utgangspunktet
at de testede Curve Optimizer-verdiene var blitt for aggressive.

**Funn fra selve CoreCycler-motorloggen** (12,4 MB, 115 "Set to Core"-
hendelser): motoren rapporterte `FATAL ERROR: Could not set the Curve
Optimizer values! Reason: ... "Ikke nok minneressurser tilgjengelig for å
utføre denne kommandoen"` kl. 15:07 den 21.06 - dette er en
Win32-PROSESSTART-feil (motoren kunne ikke starte `ryzen-smu-cli.exe` på
grunn av reell SYSTEM-minneuttømming), ikke en WHEA-/beregningsfeil fra selve
stresstesten. Motorprosessen logget ingenting mer etter dette tidspunktet -
selve testen hadde altså allerede stanset HELE 7 TIMER før systemfrysen
brukeren observerte rundt kl. 22:08-22:10.

**Funn fra Manager-loggen**: Manager-PROSESSEN (separat fra motoren) fikk
sine egne `System.OutOfMemoryException`-feil fra kl. 17:51 (~2,5 time etter
motorens krasj), eskalerende til vedvarende "Ingen tilgang"-feil fra kl.
17:55 helt til systemfrysen - et mønster som passer med GRADVIS, økende
systemminnepress over flere timer, ikke en plutselig hendelse.

**Det positive funnet**: ved krasjtidspunktet hadde søket alt funnet
(eller var i ferd med å fullføre) verdier for 7 av 8 kjerner - flere kjerner
hadde nådd den konfigurerte sikkerhetsgrensen (`minValue = -30`) UTEN å
feile, andre hadde funnet sin egen, mindre aggressive grense via en reell
WHEA-hendelse (helt normal, forventet oppførsel for et nedover-søk - det er
SLIK det finner grensen). Bare kjerne 3 (som selv hadde nådd -30 uten å feile
noen gang) var i en uavklart mellomtilstand da krasjet skjedde.

**Kjent, ikke fullt undersøkt hull**: Manager sin krasjgjenoppretting fant
ingen offset-snapshot-fil å gjenopprette fra ("fant ingen offset-snapshot å
gjenopprette fra"). Kan ikke bekreftes med sikkerhet hvorfor uten kildekoden
til DENNE spesifikke (gamle, "v0.8"-merkede) installasjonen - mest sannsynlig
forklaring er at den samme minneuttømmingen som hindret
`ryzen-smu-cli.exe`-oppstart også hindret selve snapshot-skrivingen mot
slutten. NR-GAMER kjørte for øvrig en eldre "v0.8"-build (bekreftet via
oppstartsbanneret "for AMD Ryzen 3000/5000", som var fjernet i en tidligere
fiks) - INGEN av fiksene i denne loggen var til stede på denne maskinen.

**Fiks (forebyggende, Manager-siden)**: lagt til `$rtb.ClearUndo()` i
`Set-LiveLogView` etter hver ombygning - RichTextBox bygger opp en intern
angre-historikk for hver `AppendText`, som `.Clear()` IKKE rydder. Over en
svært langvarig, sammenhengende kjøring (timer-tick hvert 1,5 sek i flere
timer/døgn) er dette en kjent, klassisk WinForms-fallgruve for ubegrenset
minnevekst. Adresserer ikke motorens egen krasj (et helt SEPARAT
prosess/system-nivå problem, ikke noe i Manager-koden kan forhindre at
systemet totalt sett går tom for minne), men reduserer Managerens EGET bidrag
til minnepresset over svært lange kjøringer.

**Anbefaling til brukeren** (kommunisert direkte, ikke en kodeendring): for
fremtidige svært lange (flere-timers/døgnlange) kjøringer - foretrekk det
lettere, anbefalte 3-test yCruncher-batteriet (SFTv4/FFTv4/N63) over en
tyngre egendefinert batteri som dette, bruk `auto` for `mode` i stedet for å
hardkode en arkitektur-spesifikk binær, og hold et øye med minnebruk i
Oppgavebehandling under svært lange kjøringer som en tidlig varsel.

**Verifisert**: tidslinjen over er rekonstruert direkte fra tidsstemplene og
feilmeldingene i begge logger (motor + Manager) i den faktiske `.diag`-
pakken fra NR-GAMER, ikke antatt. `ClearUndo()`-fiksen er syntaktisk
verifisert (AST-parser) og distribuert, men IKKE årsaks-verifisert mot et
nytt 17-timers forløp (upraktisk å reprodusere i utviklingsøkten).

## 7. Den gjenoppstående "mørke blokken" nederst i vinduet (v0.8.7 og v0.8.7.8)

**Symptom rapportert av bruker**: på skjermer med høyere oppløsning, hvis
vinduet ble satt til en større høyde enn standard, fikk man et mørkt
(bakgrunnsfarget) felt nederst i vinduet ved neste åpning - i samme høyde
som utvidelsen. Feltet forsvant IKKE når vinduet senere ble krympet igjen,
og la seg da OVER alt annet innhold i vinduet.

**Første forsøk (v0.8.7)**: antok at `$groupLog` (loggboksen) manglet riktig
`Anchor`, og at `$mainPanel` sin `AutoScrollMinSize` satt seg fast på den
største historiske høyden (en kjent WinForms-kvirk). Fikset ved å sette
`Anchor` på `$groupLog` og tvinge `AutoScrollMinSize` til å regnes på nytt
ved `Add_Resize`. **Denne fiksen var IKKE tilstrekkelig** - bekreftet på
nytt via to skjermbilder fra brukeren på en høyere-oppløsning-skjerm
(`Loggfiler for utvikling`-mappen, het tidligere `Feil`), lenge etter at
v0.8.7 var utgitt.

**Faktisk rotårsak (funnet v0.8.7.8, via diagnostikk lagt til under
utvikling)**: en midlertidig `Add-Content`-logglinje som skrev ut
`$mainPanel.Size`/`.ClientSize` ved ulike tidspunkt (rett etter `Build-Ui`,
ved `Add_Resize`, ved `Add_Shown`) avdekket at `$mainPanel` sin EGEN
`Anchor=Bottom` (relativt til `$form`) ALDRI strekker høyden korrekt - selv
etter `PerformLayout()` og selv etter at vinduet faktisk er vist
(`Add_Shown`). Bredden strekker korrekt (`Anchor=Right` virker fint), men
høyden sitter fast på design-tids-verdien. Dette er et kjent WinForms-
samspill der `AutoScroll=$true` forstyrrer normal `Anchor`-høyde-resizing
langs selve scroll-aksen - v0.8.7-fiksen adresserte kun `$groupLog` sin
Anchor (inni panelet), ikke `$mainPanel` sin EGEN Anchor (mot vinduet), som
var det faktiske, dypere problemet.

**Fiks (v0.8.7.8)**: ny funksjon `Update-MainPanelLayout` som setter BÅDE
`$mainPanel` og `$groupLog` sin høyde EKSPLISITT via kode (ikke `Anchor`) -
`$mainPanel.Size` beregnes fra `$App.Ui.Form.ClientSize.Height`, uavhengig
av Anchor helt. Fjernet `Bottom` fra `Anchor` på begge kontrollene (kun
`Top,Left,Right` igjen). Kalt ved oppstart (`Add_Shown`) og ved hvert
`Add_Resize`.

**Verifisert**: skjermbilder bekreftet BÅDE scenarioet "åpne med en stor
lagret vindushøyde" (det opprinnelige bilde 1-symptomet) OG "krympe vinduet
tilbake ned igjen etterpå" (bilde 2-symptomet, der feltet tidligere la seg
over alt annet innhold) - ingen mørk blokk i noen av tilfellene etter
fiksen. Diagnostikk-logglinjen ble fjernet igjen før utgivelse, siden den
kun var nødvendig for å bekrefte rotårsaken under selve utviklingen.

## 8. Tekstbryting i Hjelp/Oppdatering-vinduene - v0.8.7.3-fiksen var IKKE nok (v0.8.7.12)

**Symptom rapportert av bruker**: to skjermbilder (`Loggfiler for
utvikling`-mappen) viste at teksten i "Hjelp"-vinduet fortsatt forsvant ut
til høyre i stedet for å brytes til ny linje, til tross for at `WordWrap` og
`ScrollBars='Vertical'` allerede var satt (v0.8.7.3-fiksen, se README.txt).

**Faktisk rotårsak**: reprodusert isolert (egen, minimal WinForms-test
utenfor selve Manager-koden) - `RichTextBox.RightMargin` (standardverdi `0`)
er den egenskapen som FAKTISK styrer hvor teksten brytes, og den oppdateres
ALDRI automatisk til kontrollens egen bredde, uavhengig av `WordWrap`/
`ScrollBars`. v0.8.7.3-fiksen løste et ekte delproblem (den synlige
horisontale scrollbaren), men adresserte ikke selve brytepunktet.

**Fiks**: `$txt.RightMargin = $txt.ClientSize.Width` satt eksplisitt rett
etter `.Text` i både `Show-BrukerveiledningDialog` og
`Show-OppdateringTilgjengeligDialog`, pluss en `Add_Resize`-handler som
setter den på nytt (siden `RightMargin` er en FAST pikselverdi, ikke
relativ/automatisk - akkurat som `$groupLog`/`$mainPanel` sin høyde i punkt 7
over måtte settes eksplisitt, ikke via `Anchor`).

**Verifisert**: isolert skjermbilde-test (ekte skjermdump, ikke
`DrawToBitmap` - den metoden viste seg å ikke rendre RichTextBox-innhold
korrekt for denne typen verifisering) bekreftet teksten brytes korrekt
innenfor vinduets bredde etter fiksen, ved den faktiske standardstørrelsen
til dialogen.

## 9. Hovedvindu-redesign: egen venstrekolonne for loggen, kompakt høyrekolonne (v0.8.7.12-v0.8.7.13)

**Bakgrunn**: punkt 7 løste at `$groupLog` fikk riktig høyde, men løste ikke
det underliggende problemet at loggen var SISTE element i en vertikalt
stablet, rullbar kolonne - på mindre skjermer/vinduer ble den fortsatt presset
ned til et minimum (150px), siden alt annet innhold (Status, Handlinger,
Modus, Automatisk gjenoppretting, Fremdrift) krevde plass FØRST.

**Løsning (v0.8.7.12)**: vinduet delt i to faste kolonner under headeren -
`$groupLog` parentert direkte på `$form` (IKKE inni `$mainPanel` lenger) i en
egen, fast VENSTRE kolonne som bruker hele vinduets høyde, uavhengig av
resten av innholdet. ALT annet innhold (inkl. Status/Handlinger, som
tidligere lå i en egen ikke-rullbar topp-sone) flyttet inn i en smalere,
rullbar `$mainPanel` til høyre. Vinduets bredde hevet fra 1260 til 1280
(fortsatt låst) for å gi plass til den nye kolonnen uten å gjøre høyre
kolonne for smal. `Update-MainPanelLayout` forenklet betraktelig: siden
`$groupLog` ikke lenger er inni `$mainPanel`, kan `$mainPanel` sin
`AutoScrollMinSize` nå settes ÉN gang (stabelen har fast høyde), og
`$groupLog` sin høyde regnes ut direkte fra `$form.ClientSize.Height` - samme
mønster, men enklere enn punkt 7 sin opprinnelige versjon.

**Justering (v0.8.7.13)**: brukerens tilbakemelding - "Modus"-boksen hadde
for mye åpent rom (radioknapper/avkrysningsboks/hint-tekster spredt med
unødvendig store mellomrom), venstrekolonnen var bredere enn nødvendig for
loggtekst, og "Avslutt"-knappen burde være lettere tilgjengelig. Endringer:
- Venstrekolonne smalnet fra 592 til 500px, bredden gitt til høyrekolonnen
  (640 → 732px) i stedet for å krympe totalbredden.
- "Modus"-boksen komprimert fra 330 til 230px høyde (tettere Y-plassering av
  alle kontroller, samt at den bredere boksen gir kortere status-teksten
  færre tekstbrytingslinjer).
- "Avslutt" flyttet fra "Handlinger" til øvre høyre hjørne i headeren, rett
  under versjonsmerkingen - alltid synlig uten å rulle.

**Verifisert**: isolert layout-test (samme geometri som faktisk kode) med
ekte skjermdump ved både standard (900px) og minimum (540px) vindushøyde -
ingen klipping, ingen uventet horisontal scrollbar (en reell, observert
bivirkning av for trange `GroupBox`-bredder relativt til `$mainPanel` sin
vertikale scrollbar-bredde - måtte justeres med ca. 12px ekstra margin).

**Videre justering (v0.8.7.14)**: brukeren ba om å komprimere høyre kolonne
i HØYDEN (ikke bredden), flytte "Fremdrift" til toppen av venstre kolonne
(over loggen), sette en 720p-vennlig standardstørrelse, og gjøre vinduets
BREDDE utvidbar - med all ekstra bredde gående til venstre kolonne, ikke til
høyre. Endringer:
- Status/Handlinger/Modus/Automatisk gjenoppretting komprimert videre i
  høyden (tettere rad-/kontrollplassering) - bredden (688px) er UENDRET.
- `$groupProgress` ("Fremdrift") flyttet ut av `$mainPanel`-stabelen og inn
  i venstre kolonne, parentert direkte på `$form`, plassert OVER `$groupLog`
  (`$groupLog.Top` er nå `$groupProgress.Bottom + 10`, ikke en fast verdi).
- `$form.Size` standard endret til 1280x700 (var 1280x900) - passer
  komfortabelt på en 720p-skjerm (1280x720) inkl. oppgavelinje/vindusramme.
- `$form.MaximumSize.Width` hevet kraftig (var låst til 1280, lik
  MinimumSize) - bredden kan nå utvides. `$mainPanel` byttet fra
  `Anchor=Top,Left` til `Anchor=Top,Right` (holder FAST bredde, men flytter
  seg automatisk til høyre når vinduet utvides), mens `$groupProgress`/
  `$groupLog` fikk `Anchor=Top,Left,Right` lagt til (strekker seg i bredde).
  Viktig presisering fra testingen: ren `Anchor=Right`-stretching av en
  vanlig `GroupBox` (uten `AutoScroll`) er HELT vanlig, pålitelig WinForms-
  oppførsel - IKKE samme kvirk som `$mainPanel` sin høyde (den gjaldt
  spesifikt `AutoScroll` sin EGEN akse). `Update-MainPanelLayout` måtte
  derfor IKKE endres for bredde-delen, kun kommentarene oppdatert.

**Verifisert**: isolert layout-test ved tre scenarioer (ekte skjermdump,
samme geometri som faktisk kode): (1) standard 1280×700 - "Fremdrift" øverst
i venstre kolonne, loggen under, ingen klipping; (2) faktisk RESIZE fra
1280×700 til 1700×700 (viktig: testet som en ekte etterfølgende
størrelsesendring, IKKE en form opprettet direkte i full bredde - den første
metoden ga et FEILAKTIG resultat der venstre kolonne ikke strakk seg, fordi
WinForms sin `Anchor`-margin fanges ved FØRSTE layout, ikke ved opprettelse)
- venstre kolonne strakk seg korrekt til å fylle all ny bredde, høyre kolonne
forble fast og glir langs høyre kant; (3) minimum høyde 540px - begge
kolonner krymper korrekt i høyden, ingen klipping.
