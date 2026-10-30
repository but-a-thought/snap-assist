# Snap Assist

[English](README.md) | Italiano

Mini app di menu bar per macOS che porta su Mac il comportamento **Snap Assist** di Windows: quando una finestra viene agganciata a metà schermo (sinistra o destra), nella metà rimasta libera compare una griglia con le altre finestre aperte; un clic e la finestra scelta va a occupare quello spazio.

Funziona con qualsiasi metodo di snap: **Rectangle**, Magnet, le scorciatoie da tastiera, il trascinamento ai bordi o il tiling nativo di macOS.

**[Scarica per macOS](https://github.com/hellomoto8999/snap-assist/releases/latest)** · macOS 15+

![Pannello di Snap Assist](docs/screenshot.png)

## Requisiti

- macOS 15 o successivo

## Lingua

L'interfaccia segue la lingua di macOS: **italiano** se il sistema è in italiano, **inglese** per tutte le altre lingue. Non serve configurare nulla.

Se vuoi forzare una lingua solo per Snap Assist: Impostazioni di Sistema → Generali → Lingua e regione → App → Snap Assist.

## Permessi

Al primo avvio l'app apre un pannello **Permessi** con lo stato dei due permessi e i pulsanti che portano direttamente al pannello giusto di Impostazioni di Sistema. Mentre il pannello è aperto l'app compare anche nel Dock e in ⌘Tab; chiudendolo torna a vivere solo nella barra dei menu.

| Permesso | A cosa serve | Dove |
|---|---|---|
| **Accessibilità** | leggere posizione/dimensione della finestra in primo piano e spostare quella scelta | Impostazioni di Sistema → Privacy e sicurezza → Accessibilità |
| **Registrazione schermo** | catturare le miniature delle finestre nel pannello di scelta | Impostazioni di Sistema → Privacy e sicurezza → Registrazione schermo |

Senza Accessibilità l'app non può funzionare. Senza Registrazione schermo funziona lo stesso, ma al posto delle anteprime mostra l'icona dell'app. Dopo aver concesso la Registrazione schermo può essere necessario riavviare l'app (pulsante **Riavvia Snap Assist** nel pannello o nel menu).

> Se dopo una ricompilazione i permessi sembrano "dimenticati", controlla di aver creato la firma stabile con `./scripts/setup-signing.sh`: con la firma ad-hoc il permesso va riconcesso a ogni build.

## Uso

1. Aggancia una finestra a sinistra (o a destra) con Rectangle o trascinandola al bordo.
2. Dopo circa mezzo secondo la metà libera si scurisce e mostra le altre finestre.
3. Clicca quella da affiancare: viene spostata, ridimensionata e portata in primo piano.
4. `Esc` o un clic fuori dal pannello annullano.

Le finestre sono ordinate dalla più in primo piano alla più indietro, come in Windows. Sono escluse le finestre dell'app stessa e quella appena agganciata. Il pannello compare ogni volta che una finestra viene **appena** agganciata a metà o a un **quarto** di schermo, anche se l'altra metà è già occupata da un'altra finestra; un semplice clic su una finestra già affiancata non lo riapre.

Quando agganci una finestra a un quarto, il pannello compare nel primo quarto adiacente libero (in alto a destra per una finestra in alto a sinistra, e così via).

**Centra con Control**: premi **Control** due volte (o tre, configurabile in Impostazioni → Comportamento) per centrare la finestra in primo piano sul suo schermo. Control usato come modificatore (Ctrl+C, Ctrl+clic, Ctrl+scroll) non attiva il gesto.

Per avviarla al login: Impostazioni di Sistema → Generali → Elementi login → «+» e scegli `SnapAssist.app`.

### Barra tra le due finestre

Quando due finestre occupano due aree adiacenti dello stesso schermo — metà, quarti o griglia — sul confine c'è una barra che permette di ridimensionarle insieme. È verticale tra finestre affiancate e orizzontale tra finestre impilate.

- La barra **compare solo quando avvicini il puntatore al confine** (entro circa 30 punti). Non resta sopra alle altre app e non copre il resto dello schermo.
- Passandoci sopra appare una piccola maniglia con tre puntini; il cursore diventa orizzontale o verticale e, trascinando, entrambe le finestre si ridimensionano mantenendo i bordi esterni (minimo 120 punti ciascuna).
- Resta anche dopo aver spostato il confine (es. 60/40), finché le due finestre restano adiacenti.
- Ogni schermo ha la sua barra, se ci sono coppie adiacenti su entrambi.
- Si nasconde quando apri il pannello di scelta, quando le finestre non sono più adiacenti o quando un'altra finestra copre il confine.
- Si può disattivare dal menu: **Barra di ridimensionamento tra finestre affiancate**.

### Layout (Shift + trascinamento)

In **Impostazioni → Layout** scegli un preset — metà, terzi, **centro + lati**, righe, 2×2, principale + colonna, colonna + principale, 3×2, 2×3 — oppure costruisci il tuo sul canvas: trascina su un'area vuota per disegnare una zona, dentro una zona per spostarla, sui bordi per ridimensionarla, ed eliminala con **Elimina**. **Genera griglia** ti dà un punto di partenza.

![Editor dei layout](docs/layout-editor.png)

Poi tieni premuto **Shift** e trascina una finestra dalla barra del titolo. Le zone compaiono in overlay; passa sopra una zona e rilascia per posizionare lì la finestra. L'overlay è per schermo, ignora il mouse e il trascinamento continua a funzionare normalmente.

**Avvia al login** è nella stessa finestra Impostazioni, sotto Comportamento (macOS potrebbe chiederti di approvarlo in Impostazioni di Sistema → Generali → Elementi login).

## Limiti noti

- Le finestre di app che non consentono il ridimensionamento programmatico (alcune preferenze di sistema, alcuni pannelli) non si spostano: l'app emette un suono.
- Le finestre su altri Space non sono proposte (sono proposte quelle visibili).
- Con Stage Manager attivo i frame sono sfalsati e il rilevamento può non scattare.
- App non firmate/notarizzate: è un progetto personale, non passa dal Gatekeeper come un'app dello store.

## Disinstallazione

1. Esci da Snap Assist (menu → Esci).
2. Elimina `SnapAssist.app`.
3. Rimuovi eventualmente la voce da Accessibilità e Registrazione schermo in Impostazioni di Sistema.

Le preferenze restano in `~/Library/Preferences/com.frank.snapassist.plist`.

## Licenza

MIT — vedi [LICENSE](LICENSE).
