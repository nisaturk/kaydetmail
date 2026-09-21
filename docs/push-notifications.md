# Push bildirimleri (FCM) kurulum rehberi

Durum: Dart tarafı hazır (`lib/services/push_service.dart`), ama **varsayılan olarak kapalı**
(`AppConfig.pushEnabled`). Firebase config dosyaları yok, Firebase projesi bağlı değil.

Açmak için: `flutter run --dart-define=PUSH_ENABLED=true` (yukarıdaki adımlar bittikten sonra).

## 1. Firebase projesi
1. console.firebase.google.com → proje oluştur.
2. Android uygulaması ekle (`com.example.kaydetmail`, yayın öncesi gerçek id ile değiştirin) →
   `google-services.json` → `android/app/`.
3. iOS uygulaması ekle (aynı bundle id) → `GoogleService-Info.plist` → Xcode ile `ios/Runner/`.

Kısa yol: `dart pub global activate flutterfire_cli && flutterfire configure`.
`firebase_options.dart` oluşursa `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`
olarak güncelleyin.

## 2. Android Gradle (config dosyası eklendikten SONRA)
`google-services.json` yokken bu eklenirse build kırılır, bu yüzden henüz eklenmedi.
- `android/settings.gradle.kts` plugins: `id("com.google.gms.google-services") version "4.4.2" apply false`
- `android/app/build.gradle.kts` plugins: `id("com.google.gms.google-services")`

`POST_NOTIFICATIONS` izni (Android 13+) manifest'e eklendi.

## 3. iOS
- Apple Developer'da APNs Auth Key (.p8) oluştur → Firebase Console → Cloud Messaging'e yükle.
- Xcode: Push Notifications + Background Modes → Remote notifications.
- Gerçek cihaz gerekir (simülatörde push yok).

## 4. Backend
- Cihaz token'ı `registerCurrentDevice` ile gönderilir (her açılışta upsert).
- Backend, Firebase service account ile FCM'e mesaj atar. Bu anahtar uygulamaya konmaz.
- Payload yalnız id taşır (`type`, `mailId`); içerik `GET /api/mails/{id}` ile çekilir.
  Tipler: `new_mail`, `mail_state_changed`, `account_reauthentication_required`, `sync_error`.

## 5. Henüz yapılmayanlar
- `FirebaseMessaging.onBackgroundMessage` handler'ı (şu an yalnız uygulama açıkken `onMessage`).
- Data-only mesajda bildirim göstermek için `flutter_local_notifications` ya da backend'in
  `notification` alanı da göndermesi.
- Bildirime tıklayınca ilgili maile gitme (`onMessageOpenedApp` / `getInitialMessage`).

## Not: build hatası
`receive_sharing_intent` Android SDK 37 ister; `compileSdk = 37` yapıldı. AGP 9.1.0 en fazla 36'yı
"önerir" ama 37 ile derler (yalnız uyarı).
