# KAYDET UI/UX ve UI Wiring Audit Planı

Bu belge yalnızca planlama içindir. Audit sırasında kaynak kod değiştirilmemiştir.

İnceleme sonrası yorum eklemek için ilgili bulgunun altına şu formatta satır ekleyin:

```text
### YORUM: Buraya kararınızı, itirazınızı veya ek bağlamı yazın.
```

Birden fazla yorum gerekiyorsa aynı bulgu altında birden fazla `### YORUM:` satırı kullanılabilir.

## Genel sonuç

Uygulamanın temel ekran akışları ve `MailRepository` ayrımı temiz. Ancak UI katmanında birkaç kritik wiring problemi var. Öncelik görsel yenileme değil; önce yaşam döngüsü, veri kaybı, multi-account kapsamı ve hatalı iyimser güncellemeler düzeltilmeli.

### YORUM:

## P0 — Kritik bulgular

### YORUM:

## 1. Girişten sonra uygulama seviyesindeki servislerin devre dışı kalması

**Problem**

`LoginScreen`, başarılı girişte `Navigator.pushReplacement(HomeScreen)` kullanıyor. Bu işlem `MaterialApp.home` altındaki `_AuthGate` rotasını kaldırıyor.

`_AuthGate` şu sorumlulukları taşıyor:

- Periyodik senkronizasyon timer'ı
- `AppSettingsController` dinleyicisi
- Push bildirimi tıklama aboneliği
- Başlangıç oturum restorasyonu

Manuel girişten sonra oluşabilecek sonuçlar:

- Ayarlardaki senkronizasyon aralığı çalışmayabilir.
- Push bildirimi tıklaması e-posta detayını açmayabilir.
- Logout → login döngüsünde aynı sorun tekrar oluşur.

**İlgili yerler**

- `lib/app.dart`: `_AuthGateState`
- `lib/screens/login_screen.dart`: `_login`
- `lib/screens/settings_screen.dart`: `_signOutAfterRevoke`

**Ek push problemi**

`PushService.initialize()` uygulama açılır açılmaz token kaydetmeye çalışıyor. Kullanıcı henüz giriş yapmamışsa repository'de hesap yok. Giriş tamamlanınca cihaz kaydı tekrar tetiklenmiyor; yalnızca token yenilenirse veya bildirim ayarı değiştirilirse yeniden deneniyor.

**Önerilen karar**

Auth durumu navigator rotalarıyla değil, kökte kalıcı bir session coordinator ile yönetilmeli. Login ekranı sadece auth durumunu değiştirmeli; `HomeScreen`'e doğrudan replacement yapmamalı.

### YORUM: Dediğin sorunu çözelim, önerdiğin yol ile.

## 2. Taslak kaydında yanlış başarı mesajı ve veri kaybı riski

**Problem**

`ComposeScreen._saveDraft()` hataları tamamen yutuyor. Buna rağmen geri çıkış diyaloğu:

- “Taslak kaydedildi.” mesajını gösteriyor.
- Ekranı kapatıyor.

Backend kaydı başarısız olsa bile kullanıcıya başarı bildirilip içerik kaybedilebilir.

Ayrıca `_hasContent` ve `_saveDraft()` içindeki `hasAny` kontrolleri Cc/Bcc alanlarını dikkate almıyor. Sadece bu alanlara giriş yapan kullanıcı uyarı almadan çıkabilir.

**İlgili yer**

- `lib/screens/compose_screen.dart`

**Önerilen karar**

- `_saveDraft()` başarı/başarısızlık sonucu dönmeli.
- Başarısız kayıtta ekran kapanmamalı.
- Cc/Bcc içerik kontrolüne eklenmeli.
- Yeni mesaj, mevcut taslak ve cevap/ilet akışlarının çıkış metinleri ayrılmalı.
- Mevcut taslakta “Sil” davranışının “değişiklikleri at” mı yoksa “taslağı sil” mi olduğu açıklaştırılmalı.

### YORUM: Önerdiğin yol ile dediğin sorunu çözelim.

## 3. Yanıtlandı/iletildi durumunun gönderimden önce işaretlenmesi

**Problem**

`MailDetailScreen._reply()` ve `_forward()` compose ekranı açılır açılmaz şu metotları çağırıyor:

- `markAsReplied`
- `markAsForwarded`

Kullanıcı compose ekranından vazgeçse bile e-posta yanıtlanmış veya iletilmiş görünüyor.

**Önerilen karar**

Bu işaretler yalnızca gönderim başarıyla tamamlandıktan sonra uygulanmalı. `ComposeScreen`, başarılı gönderim sonucunu önceki ekrana döndürmeli veya gönderim işlemi repository tarafında ilgili orijinal mesajı atomik olarak güncellemeli.

### YORUM: Önerdiğin yol ile dediğin sorunu çözelim.

## 4. Multi-account arama kontratının uygulanmaması

**Problem**

`SearchScreen` ve `MailRepository.searchEmails()` aramanın tüm hesapları kapsadığını söylüyor. Fakat `ApiMailRepository.getAllEmails()` `_scopedSessions` kullanıyor. Aktif hesap seçiliyse yalnızca o hesap aranıyor.

Bu, arayüz kontratı ile implementasyon arasında doğrudan çelişki oluşturuyor.

**İlgili yerler**

- `lib/screens/search_screen.dart`
- `lib/repositories/mail_repository.dart`
- `lib/repositories/api_mail_repository.dart`: `getAllEmails`

**Önerilen karar**

İki API ayrılmalı:

- Aktif kapsam için `getScopedEmails()`
- Gerçekten tüm hesaplar için `getAllEmails()`

Arama, açık ürün kararına göre doğru API'yi kullanmalı.

### YORUM: Önerdiğin yol ile dediğin sorunu çözelim.

## 5. Unified mailbox etiketlerinin hesap sınırını aşması

**Problem**

Etiketler hesap-local olarak tanımlanmış. Ancak birleşik görünümde:

- `getLabels()` tüm hesapların etiketlerini birleştiriyor.
- Bulk label picker bu birleşik listeyi gösteriyor.
- Seçilen bir etiket, farklı hesaplara ait seçili e-postalara uygulanabiliyor.

Sonuç olarak hesap A'nın etiket ID'si hesap B'nin mail label map'ine yazılabiliyor. Hesap B'ye geçildiğinde bu etiket tanımı görünmediği için durum tutarsızlaşıyor.

**İlgili yerler**

- `lib/widgets/label_picker_sheet.dart`
- `lib/repositories/api_mail_repository.dart`: `getLabels`, `addLabelsToEmails`

**Önerilen karar**

Birleşik seçimde etiketleme için seçenekler:

1. Yalnızca aynı hesaptan seçim yapılmasına izin vermek.
2. Hesap bazında ayrı etiket seçimi sunmak.
3. Aynı isimdeki etiketleri hesap başına çoğaltan açık bir operasyon oluşturmak.

En güvenli ve sade varsayılan: farklı hesapları kapsayan seçimde etiketleme aksiyonunu devre dışı bırakıp nedenini açıklamak.

### YORUM: Hesapların seçimleri ayrı ayrı olmalı, biri diğerini etkilememeli

## 6. Swipe başarısız olduğunda satırın görünümden kaybolması

**Problem**

`InboxScreen._swipeMove()` satırı önce `_dismissed` kümesine ekleyip görünümden kaldırıyor. Repository işlemi başarısız olursa:

- `_dismissed` geri alınmıyor.
- Kullanıcıya hata gösterilmiyor.
- Future hatası yakalanmıyor.

E-posta sunucuda taşınmamış olsa bile mevcut ekran oturumunda kaybolmuş görünüyor.

**Önerilen karar**

İyimser hareket transaction gibi ele alınmalı:

- Satırı gizle.
- İşlem başarılıysa snackbar ve undo göster.
- Başarısızsa satırı geri getir ve hata göster.
- Aynı satır üzerinde işlem sürerken tekrar gesture engellenmeli.
- Bulk delete/archive/spam aksiyonlarında da aynı busy/error modeli kullanılmalı.

### YORUM: Önerdiğin yol ile dediğin sorunu çözelim.

## P1 — Yüksek öncelikli bulgular

### YORUM:

## 7. Senkronizasyon ve swipe ayarlarının kalıcı olmaması

Yalnızca bildirim tercihi ve sunucu adresi persist ediliyor.

Uygulama yeniden açıldığında sıfırlanan ayarlar:

- Senkronizasyon aralığı
- Kaydırarak sil tercihi

`AppSettingsController` bu iki ayar için yalnızca bellek içi state tutuyor.

### YORUM: bu sorunu çözelim, uygulama içi sqlite dbimize yazabiliriz bence ayarları da

## 8. Genel HTTP timeout bulunmaması

`ApiClient` isteklerinde timeout bulunmuyor. Yalnızca health check beş saniyelik timeout kullanıyor.

Etkilenen kullanıcı akışları:

- Login
- Session restore
- Inbox ilk yükleme
- E-posta detayı
- Ek indirme
- Gönderme
- Bağlı cihazlar

Bağlantı yarı açık kalırsa kullanıcı süresiz spinner görebilir.

### YORUM: Bu sorunu çözelim hata yönetimimiz daha gelişmiş olsun, bu uzun ui-ux-wiring-audit.md dosyasını komple yaptıktan sonra Firebase Crashlytics ve Firebase Performance Monitoring de ekleyeceğiz uygulamaya, bunun için de bir alt yapı olsun şimdiden.

## 9. Aramanın yalnızca yüklenmiş e-postaları taraması

`SearchScreen`, repository'nin bellekteki snapshot'ını arıyor. Backend arama kapasitesi UI'a bağlanmamış.

Sonuçlar:

- Henüz paginate edilmemiş mail “sonuç yok” olarak raporlanabilir.
- Kullanıcı sonucun eksik olduğunu anlayamaz.
- Arama ekranında loading/error/server-client ayrımı yok.

### YORUM: Önerdiğin yol ile dediğin sorunu çözelim.

## 10. Arama sonucundaki taslağın yanlış ekrana açılması

Inbox içindeki taslak `ComposeScreen`'e açılıyor. Arama sonucu taslak ise doğrudan `MailDetailScreen` açılıyor. Aynı nesne iki giriş noktasında farklı davranıyor.

### YORUM: Önerdiğin yol ile dediğin sorunu çözelim.

## 11. Yeni hesap ekleme akışında manuel kurulum fallback'inin olmaması

Ana login ekranında otomatik discovery başarısız olursa manuel IMAP/SMTP diyaloğu açılıyor. `AddAccountScreen` aynı fallback'i sunmuyor.

Şifre validasyonu da tutarsız:

- Login: en az 6 karakter
- Yeni hesap: yalnızca boş olmama

Backend kontratı açıkça gerektirmiyorsa mail sunucusu şifresine istemci tarafında minimum altı karakter kuralı uygulanmamalı.

### YORUM: Önerdiğin yol ile dediğin sorunu çözelim. şifreyi biz niye frontendde kontrol ediyoruz, backend gerektirmiyorsa kontrol etmeyelim

## 12. Sunucu değiştirmenin oturum güvenliğini açıklamaması

Kullanıcı aktif hesaplar varken API base URL'ini değiştirebiliyor. Mevcut tokenlar ve yüklenmiş mailbox state'i tutuluyor. Yeni sunucuya eski session bilgileriyle devam edilmeye çalışılması kafa karıştırıcı ve riskli.

**Önerilen karar**

Sunucu değişikliği:

- Aktif oturumları kapatmalı veya
- Açık bir yeniden giriş onayı istemeli.

### YORUM: sunucu değişikliğinde refreshtoken ile bir otomatik yenileme yapalım, kullancıya yansımasın tokenların süresi bitmediyse. Müşteri memnuniyeyi odaklı olalım yani.

## 13. Pin/star bilgi mimarisinin tutarsız olması

Üründe iki bağımsız alan var:

- `isPinned`
- `isStarred`

Drawer'daki `MailFolder.pinned` etiketi “Yıldızlılar” ve ikon olarak yıldız kullanıyor. Repository'nin sanal klasörü ise hem pinned hem starred e-postaları birleştiriyor.

Kullanıcı açısından belirsizlikler:

- Yıldızlamak mı klasöre ekliyor?
- Sabitlemek mi?
- İkisi neden ayrı?
- Neden pin sınırı üç fakat klasörün adı Yıldızlılar?

**Karar seçenekleri**

1. Pin özelliğini kaldırıp yıldızı tek highlight modeli yapmak.
2. Klasörü “Sabitlenenler” olarak ayırmak.
3. İki özellik korunacaksa ayrı filtreler göstermek.

### YORUM: iki özellik de korunacak, pinlemek pinlendiği kutuda, maillerin en üstüne çıkarma işlevi görsün listede. starlamak ise tıpkı label eklemek gibi bir sınıflandırma olsun sadece ve ayrı bir klasörde de görüntüleyip filtreleyebilelim

## 14. Pagination bitiş durumunun olmaması

UI ve repository'de açık bir `hasMore` durumu bulunmuyor. Listenin sonuna gelindiğinde yeni sayfalar tekrar tekrar talep edilebilir. Load-more hataları da tamamen gizleniyor.

### YORUM: Önerdiğin yol ile dediğin sorunu çözelim.

## P2 — UI/UX ve görsel sistem

### YORUM:

## 15. Güçlü taraflar

- Ekranlar genel olarak sade ve okunabilir.
- Türkçe metinler çoğunlukla doğrudan.
- Inbox, detail, attachment ve session ekranlarında loading/error/empty ayrımları düşünülmüş.
- Compose alanları gereksiz kartlara bölünmemiş.
- Repository abstraction UI katmanını backend'den ayırıyor.
- Drawer, mailbox selector ve hesap yönetimi görevleri kabaca ayrılmış.
- Undo mekanizması doğru yönde bir karar.

### YORUM:

## 16. Tasarım sisteminin eksik olması

`AppTheme` yalnızca birkaç global bileşeni tanımlıyor. Ekranlarda çok sayıda dağınık değer bulunuyor:

- Font size
- Renk
- Radius
- Padding
- Loading indicator ölçüsü
- Destructive action rengi

Eksik global temalar:

- `ListTileTheme`
- `IconButtonTheme`
- `FloatingActionButtonTheme`
- `BottomSheetTheme`
- `DialogTheme`
- `CardTheme`
- `ChipTheme`
- Disabled/busy/focus durumları
- Typography scale

Lucide ikonlarıyla `Icons.star` birlikte kullanılmış; stroke/fill dili tutarsız.

### YORUM: Önerdiğin yol ile dediğin sorunu çözelim.

## 17. Marka dilinin zayıf olması

Canlı desktop render'da login ekranı temiz fakat jenerik ve geniş alanda çok küçük kaldı:

- Sistem fontu
- Siyah/beyaz tekdüze palet
- Pastel “K” avatarı dışında marka işareti yok
- Çok geniş boşlukta 420 px form
- Desktop/tablet için kompozisyon yok

Mobil öncelikliyse desktop/web target'larının ürün kapsamından çıkarılması düşünülebilir. Çoklu platform hedefleniyorsa adaptive layout gerekir.

### YORUM: renk paletimiz ztn müşteri isteği üzerine siyah/beyaz/gri şeklinde(bu yüzden bu renklerden uzaklaşma), bir karanlık tema da ekleyebiliriz uygulamaya, cihazın temasına göre otomatik tema değişebilir, veya kullanıcı kendisi de ayarlayabilir olsun. ve responsive bir tasarımımız olsun.

## 18. Adaptive layout bulunmaması

`LayoutBuilder` yalnızca inbox empty state'inde kullanılıyor. Uygulama çapında şunlar bulunmuyor:

- Tablet master/detail
- Desktop navigation rail
- Geniş ekran max-width mailbox
- Compose genişlik yönetimi
- Settings iki kolon
- Klavye/focus traversal

Web hedefi şu anda `sqlite3`/FFI nedeniyle derlenmiyor. Web desteklenmeyecekse target açıkça kapsam dışı tutulmalı; desteklenecekse cache implementasyonu platforma göre ayrılmalı.

### YORUM: web tarafı için de sqlite bağımlılığına başka bir çare bulup mobilde nasıl çalışıyorsa orada da aynı şekilde çalışabilir olsun. ve ayrıca tasarmımızı adaptive yapalım

## 19. E-posta listesi metadata yoğunluğu

Bir satırın üst bölümünde aynı anda şunlar bulunabiliyor:

- Star
- Pin
- Attachment
- Read/unread
- Replied
- Forwarded
- Saat

Dar ekranda ve büyük fontta taşma riski yüksek. Durum ikonları birincil içerikten fazla dikkat çekiyor.

**Önerilen yapı**

- Üst satır: gönderici ve zaman
- İkinci satır: konu ve thread count
- Üçüncü satır: preview
- En fazla iki önemli metadata ikonu
- Diğer durumlar detail veya erişilebilir açıklama içinde

### YORUM: durum ikonları müşterinin ana isteklerinden, bu yüzden onlar mutlaka bulunmalı, ve şuan o kısımlar buglu bence, bazen replied olsa bile iconu gelmiyor veya forwardedken iconu gelmiyor gibi sorunlar var o kısımlar tekrar incelenmeli. müşteri özellikle eki var mı, cevaplandı mı, forwarded oldu mu, hangi labelları içeriyor gibi durumları listeden direkt maillere girmeden görmek istiyor.

## 20. Compose gövdesinin etkileşim alanı

Body `TextField`, `SingleChildScrollView` içinde intrinsik yüksekliğiyle başlıyor. Boş compose ekranında kalan beyaz alanın tamamı yazma alanı gibi davranmıyor.

Gövde kalan alanı doldurmalı ve boş alana dokunmak cursor'u body alanına taşımalı.

### YORUM: Önerdiğin yol ile dediğin sorunu çözelim.

## 21. Loading tasarımının jenerik olması

Ana akışlarda ağırlıklı olarak `CircularProgressIndicator` kullanılıyor. Mail listesi ve detay ekranında içerik geometrisini gösteren skeleton daha az layout sıçraması yaratır.

Bu çalışma wiring düzeltmelerinden sonra ele alınmalı.

### YORUM: Önerdiğin yol ile dediğin sorunu çözelim.

## Erişilebilirlik bulguları

### YORUM:

## 22. Semantics, kontrast ve dokunma hedefleri

- `lib/` altında özel `Semantics` kullanımı yok.
- Renk paleti seçenekleri `GestureDetector` ile oluşturulmuş 32×32 hedefler; önerilen minimum 48×48'in altında.
- Renk seçeneklerinin erişilebilir isimleri yok.
- Login şifre göster/gizle düğmesinde tooltip yok; AddAccount ekranında var.
- Thread kartlarında expanded/collapsed state screen reader'a aktarılmıyor.
- Mail row durum ikonları anlamlı birleşik bir semantic label üretmiyor.
- Long-press ile seçim ve swipe aksiyonlarının erişilebilir alternatifi görünür değil.
- `tertiaryText` `#9CA3AF`, beyaz üzerinde yaklaşık **2.54:1** kontrast veriyor; normal metin için WCAG AA gereksinimi olan 4.5:1'i karşılamıyor.
- Büyük text scale altında app bar aksiyonları, mail metadata satırı ve sabit 64 px compose label alanı riskli.

Login ekranının canlı semantics ağacında temel form alanı, devam düğmesi ve sunucu düğmesi doğru etiketlendi. Sorunlar ağırlıklı olarak özel widget ve durum göstergelerinde.

### YORUM: Önerdiğin yol ile dediğin sorunu çözelim.

## Önerilen uygulama planı

### YORUM:

## Faz 1 — Uygulama yaşam döngüsü ve veri bütünlüğü

1. Auth durumunu kök seviyede kalıcı hale getir.
2. Login/logout ekranlarının `HomeScreen`/`LoginScreen` rotalarını doğrudan replacement etmesini kaldır.
3. Sync scheduler ve push navigation aboneliğini auth ekranlarından bağımsız app coordinator'a taşı.
4. Başarılı login/account connect sonrasında push device registration'ı açıkça tetikle.
5. Draft save sonucunu kullanıcıya doğru aktar.
6. Reply/forward flag'lerini başarılı gönderim sonrasına taşı.
7. Swipe ve bulk aksiyonlara rollback, busy ve hata durumu ekle.

**Kabul kriterleri**

- Login → sync ayarı → timer çalışması
- Push tap → doğru detail ekranı
- Başarısız draft save → compose ekranının kapanmaması
- Başarısız swipe → satırın geri gelmesi

### YORUM:

## Faz 2 — Multi-account kontratı

1. Scoped ve global mail erişimini ayrı API'lere böl.
2. Search kapsamını ürün kararıyla sabitle.
3. Unified label picker'da hesaplar arası label sızıntısını engelle.
4. Her klasör başlığında aktif mailbox kapsamını görünür kıl.
5. Settings içindeki labels/sessions ekranlarında hangi hesabın düzenlendiğini göster.
6. Pin/star modelini tek ve anlaşılır ürün kavramına indir.

**Kabul kriterleri**

- Aktif hesap seçiliyken global arama beklenen tüm hesapları bulur.
- Hesap A etiketi hesap B e-postasına yazılamaz.
- Kullanıcı her ekranda hangi hesap kapsamını gördüğünü anlayabilir.

### YORUM:

## Faz 3 — Async durum modeli

1. API isteklerine merkezi timeout ve sınıflandırılmış hata ekle.
2. Inbox pagination'a `hasMore`, load-more error ve retry ekle.
3. Search'ü debounce edilmiş server search'e bağla; loading/error/partial-result durumlarını göster.
4. AddAccount'e manuel discovery fallback'i ekle.
5. Dosya seçme ve attachment read hatalarını kullanıcıya göster.
6. Sync interval ve swipe tercihlerini persist et.
7. Sunucu değiştirmede logout/re-auth güvenlik akışı ekle.

### YORUM:

## Faz 4 — Bilgi mimarisi ve interaction cleanup

1. Draft, sent, trash, spam ve archive klasörleri için bağlamsal aksiyon setleri oluştur.
2. Search sonucundaki draft'ı compose'a aç.
3. Compose recipient alanlarını doğrulanmış adres/chip modeline geçir.
4. Gönderim sırasında back, form edit ve ek ekleme davranışlarını kilitle.
5. Empty/error/offline durumlarına bağlamsal CTA ve son senkronizasyon bilgisi ekle.
6. Mail listesi metadata yoğunluğunu azalt.

### YORUM:

## Faz 5 — Tasarım sistemi ve erişilebilirlik

1. Renk, typography, spacing, radius ve component-state token'larını `AppTheme` altında merkezileştir.
2. Tek ikon ailesi ve tutarlı filled/outline durumları kullan.
3. Tertiary metin kontrastını yükselt.
4. Tüm custom gesture'lara semantic label, role, state ve 48×48 hedef ekle.
5. Büyük text scale, TalkBack/VoiceOver ve keyboard traversal desteği ekle.
6. Tablet/desktop hedefleniyorsa navigation rail, constrained mailbox ve master/detail düzeni oluştur.
7. Mail listesi/detail için skeleton loading tasarla.

### YORUM:

## Faz 6 — UI doğrulama matrisi

Kalıcı testlerin odak noktası wiring kontratları olmalı:

- Login sonrası sync/push coordinator yaşamaya devam ediyor.
- Draft kaydı başarısızsa ekran kapanmıyor.
- Compose iptali reply/forward flag'i yazmıyor.
- Global search aktif account'tan bağımsız.
- Cross-account label uygulanamıyor.
- Swipe failure satırı geri getiriyor.
- Search draft'ı compose'a açıyor.
- Ayarlar restart sonrası korunuyor.
- Büyük text scale'da overflow oluşmuyor.
- Semantics ağacında custom kontroller etiketli.

### YORUM:

## Audit doğrulama kayıtları

- `flutter analyze`: temiz.
- `flutter test`: 105 test geçti.
- Mevcut test dizisinde `testWidgets`, `WidgetTester` veya `pumpWidget` tabanlı UI testi bulunmadı; suite ağırlıklı repository/service katmanını kapsıyor.
- Desktop uygulama canlı çalıştırıldı; login ekranı Flutter inspector üzerinden render ve semantics açısından incelendi.
- Android uygulaması cihaza kurulup başlatıldı; cihaz kilitli olduğu için authenticated ekranlar görsel olarak dolaşılamadı.
- Web çalıştırma `sqlite3` FFI bağımlılığı nedeniyle derlenmedi.

### YORUM:
