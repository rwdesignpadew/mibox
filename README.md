# MiBox Screen

Aplikacja iOS do udostępniania ekranu iPhone’a na Mi Boxie przez wbudowany Google Cast/Chromecast.

Na Mi Boxie nie instaluje się żadnej dodatkowej aplikacji. Użytkownik wybiera telewizor za pomocą oficjalnego okna Google Cast, a rozszerzenie ReplayKit udostępnia ekran jako lokalny strumień HLS.

## Wymagania

- Mi Box lub inne urządzenie z wbudowanym Google Cast,
- iPhone z iOS 16 lub nowszym,
- oba urządzenia w tej samej sieci Wi‑Fi,
- macOS z Xcode 16+ do kompilacji aplikacji.

## Uruchomienie

```bash
cd ios
brew install xcodegen
xcodegen generate
open MiBoxScreen.xcodeproj
```

Na fizycznym iPhonie:

1. Naciśnij ikonę Cast.
2. Wybierz Mi Box z listy urządzeń Google Cast.
3. Naciśnij „Rozpocznij udostępnianie”.
4. W systemowym oknie wybierz „MiBox Screen” i rozpocznij transmisję.

iOS zawsze wymaga systemowego potwierdzenia transmisji ReplayKit. Nie można legalnie ani technicznie pominąć tego kroku.

## Architektura

- `ios/MiBoxScreen` — aplikacja SwiftUI, oficjalny Google Cast i StoreKit 2,
- `ios/ScreenBroadcast` — rozszerzenie ReplayKit kodujące ekran do H.264/fMP4 i udostępniające lokalny HLS,
- `ios/Shared` — dane współdzielone przez App Group.

Katalogi `android-tv` i `signaling` zawierają wycofany prototyp własnego odbiornika. Nie są budowane, publikowane ani wymagane przez aplikację iOS.

## Pro i reklamy

Zakup `pl.miboxscreen.ios.pro` jest jednorazowym zakupem StoreKit. Panel reklam z prototypu Android TV nie jest częścią aktualnej architektury. Reklamy własnej marki wymagają osobnego źródła konfiguracji dostępnego z internetu; nie należy opierać ich na aplikacji instalowanej na telewizorze.

## Ograniczenia testowe

ReplayKit i pobieranie lokalnego HLS przez odbiornik Cast należy sprawdzać na fizycznym iPhonie oraz Mi Boxie. Kompilacja w symulatorze nie potwierdza działania całego przepływu sieciowego.
