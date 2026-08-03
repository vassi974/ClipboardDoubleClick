# ClipboardDoubleClick — prototype

☕ [buymeacoffee.com/vassi974](https://buymeacoffee.com/vassi974) · [🇫🇷 Français](#français) · [🇬🇧 English](#english)

---

## Français

Utilitaire de presse-papiers déclenché par un **double clic droit** n'importe où sur macOS.

Dev perso, partagé avec le cœur — si l'outil te sert, un café est toujours apprécié :
☕ [buymeacoffee.com/vassi974](https://buymeacoffee.com/vassi974)

Disponible en 🇫🇷 français, 🇬🇧 anglais, 🇪🇸 espagnol et 🇩🇪 allemand — l'app se cale automatiquement
sur la langue système (repli sur l'anglais si la langue du Mac n'est pas gérée).

### Installation rapide (.dmg)

Télécharge le `.dmg` depuis la page [Releases](../../releases) de ce repo, ouvre-le, glisse
`ClipboardDoubleClick.app` dans `Applications`, puis lance l'app.

L'app n'est pas notariée par Apple (pas de compte développeur payant) : au premier lancement,
macOS va probablement dire qu'elle vient d'un développeur non identifié. Fais un **clic droit
sur l'app > Ouvrir** (au lieu d'un double-clic normal) pour autoriser l'exception, une seule
fois. macOS demandera aussi la permission **Accessibilité** (Réglages Système >
Confidentialité et sécurité > Accessibilité) : c'est nécessaire pour intercepter les doubles
clics droits partout sur le système.

Pour reconstruire le `.dmg` toi-même à partir du code : `./Packaging/build_app.sh`.

Ce dossier ne peut pas être compilé depuis ce sandbox (Linux, sans AppKit) : le code a été écrit
directement d'après la spec, à tester et itérer sur ton Mac.

### Ce qui est implémenté

- **Détection double clic droit global** (`RightClickTap.swift`) : un `CGEventTap` intercepte
  uniquement le 2e clic d'un double clic droit rapproché. Un simple clic droit continue de
  déclencher le menu contextuel normal de l'app — seul le 2e clic d'une paire rapide est avalé.
- **Surveillance du presse-papiers** (`ClipboardMonitor.swift`) : polling toutes les 0.5s
  (pas d'API native de notification sur macOS), capture texte brut + RTF si activé.
- **Stockage** (`ClipboardStore.swift`) : seul un aperçu tronqué à une ligne reste en mémoire ;
  le texte complet (même 500 pages) est écrit dans un fichier séparé par entrée, dans
  `~/Library/Application Support/ClipboardDoubleClick/bodies/`. Purge automatique par nombre de
  copies ET par ancienneté (max 30 jours), les épinglés sont exclus de la purge.
- **Menu 1 (historique)** (`HistoryPanel.swift`) : molette = déplace la sélection, clic gauche =
  colle l'élément sélectionné, clic droit = ferme, croix = supprime une entrée, étoile = épingle,
  champ de recherche, entrée "Menu" tout en haut pour rejoindre les réglages.
- **Menu 2 (réglages)** (`SettingsPanel.swift`) : effacer l'historique, nombre de copies à
  conserver, nombre de jours (plafonné à 30), effacer en sortie de session, tout convertir en
  texte brut, conserver le texte enrichi, quitter, à propos. Clic droit = retour au Menu 1.
- **Validation d'un item** (`AppDelegate.swift`) : le clic gauche recopie l'élément choisi sur
  le presse-papiers système et réactive l'app précédente — c'est ensuite à toi de faire Cmd+V.
  (Une simulation automatique de Cmd+V a été testée puis retirée : dans un contexte sans champ
  éditable au focus, ça ne collait rien et produisait juste le bip d'erreur système.)
- **Fermeture du menu** : un clic gauche ou droit en dehors de la fenêtre (autre app, bureau,
  etc.) referme le panel automatiquement.

### Pas encore fait (à voir selon tes retours de test)

- Liste d'exclusion par app pour désactiver le double clic droit (le réglage existe dans le
  modèle `AppSettings.excludedBundleIdentifiers`, mais il n'y a pas encore d'UI dans le Menu 2
  pour l'éditer — actuellement on ne peut le remplir qu'en modifiant le fichier
  `settings.json` à la main).
- Icône/app packagée proprement en `.app` (voir plus bas — pour l'instant c'est un exécutable
  en ligne de commande).
- Conversion multi-écrans un peu simplifiée (utilise la hauteur de l'écran principal pour
  convertir les coordonnées clic → position du panel).

### Comment tester sur ton Mac

1. Installe Xcode (ou juste les Command Line Tools : `xcode-select --install`).
2. Dans le Terminal :
   ```
   cd ClipboardDoubleClick
   swift run
   ```
3. Au premier lancement, macOS va demander la permission **Accessibilité** (nécessaire pour
   intercepter les clics globalement) : Réglages Système → Confidentialité et sécurité →
   Accessibilité → active "ClipboardDoubleClick" (ou "Terminal" si tu lances via `swift run`
   depuis le Terminal — c'est le process qui doit être autorisé).
4. Relance `swift run` après avoir donné la permission.
5. Copie un texte quelque part, puis fais un **double clic droit** n'importe où → le Menu doit
   apparaître avec l'historique.

Pour arrêter : `Ctrl+C` dans le Terminal, ou "Quitter" dans le Menu 2.

### Prochaine étape possible

Une fois que le comportement de base te convient, on peut :
- packager ça en vraie `.app` (icône, lancement au démarrage, pas besoin du Terminal ouvert) ;
- ajouter l'UI d'exclusion par app dans le Menu 2 ;
- affiner l'apparence (couleurs, police, animation d'ouverture) pour coller pile au mockup.

Dis-moi ce qui coince ou ce qui manque après ton premier essai, et j'ajuste le code.

---

## English

Clipboard history utility triggered by a **double right-click** anywhere on macOS.

Personal project, shared with love — if this tool is useful to you, a coffee is always
appreciated: ☕ [buymeacoffee.com/vassi974](https://buymeacoffee.com/vassi974)

Available in 🇫🇷 French, 🇬🇧 English, 🇪🇸 Spanish and 🇩🇪 German — the app automatically matches
your system language (falls back to English if your Mac's language isn't supported).

### Quick install (.dmg)

Download the `.dmg` from this repo's [Releases](../../releases) page, open it, drag
`ClipboardDoubleClick.app` into `Applications`, then launch it.

The app isn't notarized by Apple (no paid developer account): on first launch, macOS will
likely say it's from an unidentified developer. **Right-click the app > Open** (instead of a
normal double-click) to allow the one-time exception. macOS will also ask for **Accessibility**
permission (System Settings > Privacy & Security > Accessibility): required to intercept double
right-clicks system-wide.

To rebuild the `.dmg` yourself from source: `./Packaging/build_app.sh`.

This folder can't be compiled from this sandbox (Linux, no AppKit): the code was written
directly from the spec, to be tested and iterated on your Mac.

### What's implemented

- **Global double right-click detection** (`RightClickTap.swift`): a `CGEventTap` intercepts
  only the 2nd click of a fast double right-click. A single right-click still triggers the
  app's normal context menu — only the 2nd click of a quick pair is swallowed.
- **Clipboard monitoring** (`ClipboardMonitor.swift`): polling every 0.5s (macOS has no native
  clipboard-change notification), captures plain text + RTF when enabled.
- **Storage** (`ClipboardStore.swift`): only a one-line truncated preview stays in memory; the
  full text (even a 500-page one) is written to a separate file per entry, in
  `~/Library/Application Support/ClipboardDoubleClick/bodies/`. Auto-pruned by item count AND
  by age (max 30 days), pinned items are excluded from pruning.
- **Menu 1 (history)** (`HistoryPanel.swift`): scroll wheel = move selection, left-click = paste
  the selected item, right-click = close, cross = delete an entry, star = pin, search field,
  "Menu" entry at the top to reach settings.
- **Menu 2 (settings)** (`SettingsPanel.swift`): clear history, number of copies to keep, number
  of days (capped at 30), clear on quit, convert everything to plain text, keep rich text, quit,
  about. Right-click = back to Menu 1.
- **Confirming an item** (`AppDelegate.swift`): left-click copies the chosen item onto the
  system clipboard and reactivates the previous app — it's then up to you to press Cmd+V.
  (An automatic Cmd+V simulation was tried and removed: in a context with no editable field
  focused, it pasted nothing and just triggered the system error beep.)
- **Closing the menu**: a left or right click outside the window (another app, the desktop,
  etc.) automatically closes the panel.

### Not done yet (depends on your testing feedback)

- Per-app exclusion list to disable the double right-click trigger (the setting exists in the
  `AppSettings.excludedBundleIdentifiers` model, but there's no Menu 2 UI to edit it yet —
  currently you'd have to edit the `settings.json` file by hand).
- Properly packaged as a `.app` (see below — it's currently a command-line executable).
- Multi-screen coordinate conversion is somewhat simplified (uses the main screen's height to
  convert click coordinates into panel position).

### How to test on your Mac

1. Install Xcode (or just the Command Line Tools: `xcode-select --install`).
2. In Terminal:
   ```
   cd ClipboardDoubleClick
   swift run
   ```
3. On first launch, macOS will ask for **Accessibility** permission (needed to intercept clicks
   globally): System Settings → Privacy & Security → Accessibility → enable
   "ClipboardDoubleClick" (or "Terminal" if you launched via `swift run` from Terminal — that's
   the process that needs to be authorized).
4. Relaunch `swift run` after granting permission.
5. Copy some text somewhere, then do a **double right-click** anywhere → the Menu should appear
   with your history.

To stop: `Ctrl+C` in Terminal, or "Quit" in Menu 2.

### Possible next steps

Once the base behavior works for you, we could:
- package it as a proper `.app` (icon, launch at login, no need to keep Terminal open);
- add the per-app exclusion UI in Menu 2;
- polish the look (colors, font, opening animation) to match the mockup exactly.

Let me know what's off or missing after your first try, and I'll adjust the code.
