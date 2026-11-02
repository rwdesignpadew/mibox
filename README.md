# MiBox Screen

MVP do udostępniania całego ekranu iPhone'a na Mi Boxie przez WebRTC. Projekt składa się z:

- `android-tv/` — odbiornik instalowany na Mi Boxie, zawierający lokalny serwer sygnalizacyjny,
- `ios/` — aplikacja i rozszerzenie systemowe ReplayKit do transmisji ekranu.
- `signaling/` — opcjonalny serwer referencyjny używany tylko do testów i dalszego rozwoju.

> iOS zawsze wyświetla systemowe potwierdzenie rozpoczęcia transmisji. Aplikacja nie może ominąć tego kroku.

## Wymagania

- Mi Box z Android TV 6.0 lub nowszym,
- iPhone z iOS 16 lub nowszym,
- macOS z Xcode 16+ do zbudowania aplikacji iOS,
- Android Studio z JDK 17 do zbudowania aplikacji TV.

Komputer ani zewnętrzny serwer nie są potrzebne podczas korzystania z aplikacji. iPhone i telewizor muszą być połączone z tą samą siecią Wi‑Fi, która nie blokuje komunikacji między urządzeniami.

## 1. Odbiornik na Mi Box

1. Otwórz katalog `android-tv` w Android Studio.
2. Zbuduj APK (`Build > Build APK`) i zainstaluj je na Mi Boxie przez ADB lub Android Studio.
3. Uruchom **MiBox Screen**. Telewizor uruchomi lokalny odbiornik i pokaże 6-cyfrowy kod.

Build można też wykonać bez Android Studio, używając dołączonego Gradle Wrappera:

```powershell
cd android-tv
.\gradlew.bat assembleDebug
```

Gotowy plik znajdzie się w `android-tv/app/build/outputs/apk/debug/app-debug.apk`.

Przykładowa instalacja przez ADB:

```powershell
adb connect ADRES_IP_MIBOXA:5555
adb install -r android-tv\app\build\outputs\apk\debug\app-debug.apk
```

## 2. Aplikacja iOS

Na Macu zainstaluj XcodeGen (`brew install xcodegen`), a następnie:

```bash
cd ios
xcodegen generate
open MiBoxScreen.xcodeproj
```

W Xcode:

1. Ustaw swój zespół podpisujący dla targetów `MiBoxScreen` i `ScreenBroadcast`.
2. Zmień identyfikatory pakietów oraz App Group `group.pl.miboxscreen.ios`, jeżeli ten identyfikator jest już zajęty. Zmiana musi być taka sama w obu plikach `.entitlements` oraz w `SharedSettings.swift`.
3. Uruchom aplikację na fizycznym iPhonie (ReplayKit nie jest miarodajny w symulatorze).
4. Poczekaj, aż aplikacja automatycznie znajdzie odbiornik w lokalnej sieci, i wpisz kod z telewizora. Ręczne podanie adresu pozostaje dostępne jako opcja awaryjna.
5. Naciśnij **Rozpocznij udostępnianie**, wybierz **MiBox Screen** i potwierdź transmisję.

## Testy

```powershell
cd signaling
npm test
```

## Zakres MVP

Obraz działa bezpośrednio w sieci lokalnej, a serwer sygnalizacyjny działa na odbiorniku Android TV. W tej wersji przesyłany jest obraz bez dźwięku. Sieci gościnne z izolacją klientów mogą blokować automatyczne wykrywanie i połączenie między urządzeniami.
