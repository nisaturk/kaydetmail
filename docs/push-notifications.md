# Push bildirimleri (FCM) kurulum rehberi

Durum: Firebase projesi bağlı (`mail-client-37a01`, backend ile aynı proje), Android tarafı
uçtan uca hazır ve **varsayılan olarak açık** (`AppConfig.pushEnabled`; web/masaüstü
`PushService.isSupportedPlatform` ile atlanır).

Kapatmak için: `flutter run --dart-define=PUSH_ENABLED=false`.

## 1. Firebase projesi
Android uygulaması zaten eklendi: paket adı `com.example.kaydetmail`, app id
`1:741294667910:android:66aeeb2c15cb493fc2f907`, proje `mail-client-37a01` (backend'in
`secrets/mail-client-37a01-firebase-adminsdk-fbsvc-*.json`'ı ile aynı proje — backend zaten
`Firebase__Enabled=true` ile bu projeye bağlı). Config dosyası `android/app/google-services.json`
içinde — commit edilmez (bkz. `.gitignore`), yeniden üretmek gerekirse Firebase Console →
Project settings → genel sekmesindeki Android uygulamasından ya da
`dart pub global activate flutterfire_cli && flutterfire configure` ile indirilebilir.

iOS henüz eklenmedi (Apple Developer hesabı + APNs Auth Key gerektirir, bu turda kapsam dışı).
Gerekirse: iOS uygulaması ekle (aynı bundle id) → `GoogleService-Info.plist` → Xcode ile
`ios/Runner/`.

## 2. Android Gradle
Tamamlandı:
- `android/settings.gradle.kts` → `id("com.google.gms.google-services") version "4.4.2" apply false`
- `android/app/build.gradle.kts` → `id("com.google.gms.google-services")`
- `android/app/google-services.json` mevcut.
- `android/app/src/main/AndroidManifest.xml` → `POST_NOTIFICATIONS` izni (Android 13+) ve
  arka plan/kapalı-uygulama bildirimleri için `default_notification_icon` meta-data'sı.

`flutter build apk --debug` ile doğrulandı (Gradle assemble
temiz, google-services eklentisi `google-services.json`'ı işliyor).

## 3. Android Studio profili
`.idea/workspace.xml` içinde **"Kaydetmail (Profile + FCM)"** adında bir run configuration var:
`flutter run --profile --dart-define=PUSH_ENABLED=true --dart-define=USE_MOCK_API=false`.
Prod'a yakın (profile build — debug banner yok, gerçek performans) ve FCM açık şekilde
çalışır. Gerçek cihazda test ederken sunucu adresini uygulama içi Ayarlar ekranından
makinenin LAN IP'sine çevir (ör. `http://192.168.1.23:5071`) — `10.0.2.2` sadece Android
emülatöründe host'a erişmek için işe yarar, fiziksel cihazdan görünmez.

## 4. iOS
- Apple Developer'da APNs Auth Key (.p8) oluştur → Firebase Console → Cloud Messaging'e yükle.
- Xcode: Push Notifications + Background Modes → Remote notifications.
- Gerçek cihaz gerekir (simülatörde push yok).

## 5. Backend
- Cihaz token'ı `registerCurrentDevice` ile gönderilir (her açılışta upsert).
- Backend, Firebase service account ile FCM'e mesaj atar (`Firebase__Enabled=true`,
  `secrets/mail-client-37a01-firebase-adminsdk-fbsvc-*.json`). Bu anahtar uygulamaya konmaz.
- Payload yalnız id taşır (`type`, `mailId`); içerik `GET /api/mails/{id}` ile çekilir.
  Tipler: `new_mail`, `mail_state_changed`, `account_reauthentication_required`, `sync_error`.
- `new_mail` / `account_reauthentication_required` / `sync_error` bir `notification` bloğu da
  taşır — Android'in FCM SDK'sı uygulama arka plandayken/kapalıyken sistem bildirimini
  kendisi gösterir, ekstra kod gerekmez. `mail_state_changed` yalnız `data` taşır (sessiz
  senkron sinyali).

## 6. Flutter tarafında tamamlananlar
- `FirebaseMessaging.onBackgroundMessage` handler'ı kayıtlı (`firebaseMessagingBackgroundHandler`,
  `lib/services/push_service.dart`) — arka planda/uygulama kapalıyken Firebase'i yeniden
  başlatır, plugin sözleşmesi bunu ister.
- Bildirime tıklayınca ilgili maile gitme: `FirebaseMessaging.onMessageOpenedApp` +
  `getInitialMessage()` → `PushService.onMailTapped` stream'i → `app.dart` bunu dinleyip
  `MailDetailScreen`'i `navigatorKey` üzerinden açıyor (soğuk başlangıç dahil).
- Uygulama açıkken gelen push'lar (FCM ön planda kendisi göstermez)
  `flutter_local_notifications` ile `mail` kanalında (yüksek önem) gösterilir; bildirime
  tıklamak yine `onMailTapped`'e düşer. Manifest'teki
  `default_notification_channel_id` arka plan bildirimlerini de aynı kanala yönlendirir.
  `new_mail` geldiğinde Gelen Kutusu listesi de yenilenir. `mail_state_changed` sessiz kalır.
- Oturum açıldıktan sonra bağlanan her yeni hesap için cihaz otomatik yeniden kaydedilir.
- `flutter_local_notifications` için Android'de core library desugaring açık
  (`android/app/build.gradle.kts`).

## 7. Henüz yapılmayanlar
- iOS: APNs anahtarı ve `GoogleService-Info.plist` henüz yok.

## Not: build hatası
`receive_sharing_intent` Android SDK 37 ister; `compileSdk = 37` yapıldı. AGP 9.1.0 en fazla 36'yı
"önerir" ama 37 ile derler (yalnız uyarı).
