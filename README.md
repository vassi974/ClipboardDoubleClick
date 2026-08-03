# ClipboardDoubleClick — prototype

Utilitaire de presse-papiers déclenché par un **double clic droit** n'importe où sur macOS.

Dev perso, partagé avec le cœur — si l'outil te sert, un café est toujours apprécié :
☕ [buymeacoffee.com/vassi974](https://buymeacoffee.com/vassi974)

Ce dossier ne peut pas être compilé depuis ce sandbox (Linux, sans AppKit) : le code a été écrit
directement d'après la spec, à tester et itérer sur ton Mac.

## Ce qui est implémenté

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

## Pas encore fait (à voir selon tes retours de test)

- Liste d'exclusion par app pour désactiver le double clic droit (le réglage existe dans le
  modèle `AppSettings.excludedBundleIdentifiers`, mais il n'y a pas encore d'UI dans le Menu 2
  pour l'éditer — actuellement on ne peut le remplir qu'en modifiant le fichier
  `settings.json` à la main).
- Icône/app packagée proprement en `.app` (voir plus bas — pour l'instant c'est un exécutable
  en ligne de commande).
- Conversion multi-écrans un peu simplifiée (utilise la hauteur de l'écran principal pour
  convertir les coordonnées clic → position du panel).

## Comment tester sur ton Mac

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

## Prochaine étape possible

Une fois que le comportement de base te convient, on peut :
- packager ça en vraie `.app` (icône, lancement au démarrage, pas besoin du Terminal ouvert) ;
- ajouter l'UI d'exclusion par app dans le Menu 2 ;
- affiner l'apparence (couleurs, police, animation d'ouverture) pour coller pile au mockup.

Dis-moi ce qui coince ou ce qui manque après ton premier essai, et j'ajuste le code.
