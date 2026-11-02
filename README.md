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

## Własne reklamy marki

Wersja bezpłatna pokazuje podczas aktywnej transmisji dyskretny baner u dołu telewizora: przez 8 sekund co 20 minut. Baner nie zatrzymuje ani nie zasłania całego obrazu.

Na ekranie startowym Mi Boxa znajduje się adres lokalnego panelu reklam (port `8081`) oraz sześciocyfrowy kod dostępu. Otwórz ten adres w przeglądarce urządzenia podłączonego do tej samej sieci Wi‑Fi i zaloguj się:

- użytkownik: `admin`,
- hasło: kod pokazany na telewizorze.

W panelu można dodawać, wyłączać, ponownie włączać i usuwać reklamy. Aktywne reklamy są tasowane: każda pojawia się raz w danej kolejce, a ta sama reklama nie występuje bezpośrednio po sobie. Lista jest zapisywana lokalnie na Mi Boxie i nie wymaga zewnętrznego serwera. Panel działa przez zwykłe HTTP wyłącznie w sieci lokalnej, dlatego należy używać go w zaufanej sieci.

Częstotliwość i czas emisji można zmienić w `android-tv/app/src/main/java/pl/miboxscreen/tv/HouseAdConfig.kt`.

Domyślna konfiguracja:

- pierwsza reklama: `RW DESIGN — Projektowanie stron i aplikacji`,
- czas wyświetlania: 8 sekund,
- odstęp: 20 minut.

Wyłączenie reklam po zakupie Pro będzie realizowane przez StoreKit i stan uprawnienia użytkownika w kolejnym etapie.

## Logo i ikony aplikacji

Źródła identyfikacji znajdują się w katalogu `branding/`:

- `mibox-screen-master.png` — pełna ikona 1024×1024 px,
- `mibox-screen-mark.png` — znak z przezroczystym tłem do ikon adaptacyjnych i banerów.

iOS korzysta z pojedynczej ikony 1024×1024 px w `Assets.xcassets/AppIcon.appiconset`; Xcode generuje z niej wymagane rozmiary. Android TV zawiera ikonę standardową w pięciu gęstościach, adaptive icon dla Androida 8.0+ oraz lokalizowany baner 16:9 z nazwą aplikacji w rozmiarach od 160×90 do 640×360 px.

## Zakres MVP

Obraz działa bezpośrednio w sieci lokalnej, a serwer sygnalizacyjny działa na odbiorniku Android TV. W tej wersji przesyłany jest obraz bez dźwięku. Sieci gościnne z izolacją klientów mogą blokować automatyczne wykrywanie i połączenie między urządzeniami.
