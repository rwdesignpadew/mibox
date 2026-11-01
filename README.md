# MiBox Screen

MVP do udostępniania całego ekranu iPhone'a na Mi Boxie przez WebRTC. Projekt składa się z:

- `signaling/` — mały serwer WebSocket uruchamiany na komputerze lub serwerze w sieci,
- `android-tv/` — odbiornik instalowany na Mi Boxie,
- `ios/` — aplikacja i rozszerzenie systemowe ReplayKit do transmisji ekranu.

> iOS zawsze wyświetla systemowe potwierdzenie rozpoczęcia transmisji. Aplikacja nie może ominąć tego kroku.

## Wymagania

- Mi Box z Android TV 6.0 lub nowszym,
- iPhone z iOS 16 lub nowszym,
- macOS z Xcode 16+ do zbudowania aplikacji iOS,
- Android Studio z JDK 17 do zbudowania aplikacji TV,
- Node.js 20+ dla serwera.

## 1. Serwer sygnalizacyjny

Na komputerze dostępnym dla obu urządzeń:

```powershell
cd signaling
npm install
npm start
```

Zapora systemowa musi zezwalać na połączenia przychodzące TCP na porcie `8080`. Stan serwera można sprawdzić pod `http://ADRES_IP:8080/health`.

Adres IP komputera w Windows można znaleźć poleceniem:

```powershell
ipconfig
```

## 2. Odbiornik na Mi Box

1. Otwórz katalog `android-tv` w Android Studio.
2. W pliku użytkownika `~/.gradle/gradle.properties` ustaw adres serwera:

   ```properties
   SIGNALING_URL=ws://192.168.1.10:8080/signal
   ```

3. Zbuduj APK (`Build > Build APK`) i zainstaluj je na Mi Boxie przez ADB lub Android Studio.
4. Uruchom **MiBox Screen**. Telewizor pokaże 6-cyfrowy kod.

Przykładowa instalacja przez ADB:

```powershell
adb connect ADRES_IP_MIBOXA:5555
adb install -r android-tv\app\build\outputs\apk\debug\app-debug.apk
```

## 3. Aplikacja iOS

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
4. Wpisz `ws://ADRES_IP:8080/signal` i kod z telewizora.
5. Naciśnij **Rozpocznij udostępnianie**, wybierz **MiBox Screen** i potwierdź transmisję.

## Testy

```powershell
cd signaling
npm test
```

## Zakres MVP

Obraz działa peer-to-peer; serwer przekazuje wyłącznie komunikaty zestawiające połączenie. W tej wersji przesyłany jest obraz bez dźwięku. Publiczne wdrożenie powinno używać `wss://`, uwierzytelniania, własnego serwera TURN oraz rotacji/wygaśnięcia kodów pokojów.
