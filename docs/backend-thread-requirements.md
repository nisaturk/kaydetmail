# Backend: sohbet (thread) görünümü için gereksinimler

Mobil uygulama çok mesajlı konuşmaları sohbet balonları olarak gösteriyor. Bunun için thread'in
**tam ve tutarlı** gelmesi gerekiyor. Uygulama tarafında yerel önbellekle telafi ediliyor
(gönderilen yanıt yerelde thread'e ekleniyor), ama aşağıdaki backend eksikleri giderilmezse
sohbet görünümü gerçek mail kutusunda eksik ya da tekrarlı kalır.

Ilgili istemci kodu: `ApiMailRepository.fetchThreadEmails`, `MailDetailScreen._enrichThread`.

## 1. Konuşma gruplaması yalnızca subject'e bağlı olmamalı (öncelik: yüksek)

**Bugün:** `docs/flutter-api-integration.md` §6: konuşmalar "normalize edilmiş subject" üzerinden
gruplanıyor.

**Sorun:** Karşı taraf konuyu değiştirirse (`Re:` dışında bir düzenleme, farklı dilde `Ynt:`/`AW:`
öneki, konu düzenleme) yanıt ayrı konuşmaya düşer. Aynı konu başlığını kullanan ilişkisiz mailler
tek konuşmada birleşir.

**İstenen:** Gruplama önce `Message-ID` / `In-Reply-To` / `References` zincirine göre, bunlar yoksa
normalize subject'e göre yapılsın. `Re:`, `Fwd:`, `Ynt:`, `İlt:`, `AW:`, `WG:` önekleri
normalize edilirken temizlensin.

## 2. Gönderilen yanıt, gönderimden hemen sonra konuşmada görünmeli (öncelik: yüksek)

**Bugün:** `POST /api/mails/send` → `{ sent, sentCopySaved, warning }`. Oluşan mailin id'si ve
`conversationId`'si dönmüyor. Gönderilmiş kopya IMAP'e yazılıp eşleşene kadar
`GET /api/conversations/{id}` içinde yok.

**Sorun:** Kullanıcı yanıtladıktan sonra thread'i açtığında kendi yanıtı sunucu konuşmasında
görünmüyor; istemci geçici bir yerel kopya (`sent-<zaman damgası>`) ekliyor. Sunucu sonradan aynı
maili gerçek id ile döndürünce aynı mesaj **iki kez** görünebilir.

**İstenen (biri yeterli, ikisi ideal):**
- `POST /api/mails/send` ve `POST /api/drafts/{id}/send` yanıtına `mailId` ve `conversationId`
  eklensin (`reconciliationPending: true` semantiği taslaktaki gibi). İstemci geçici kopyayı bu
  id ile değiştirebilsin.
- Gönderilen kopya `sentCopySaved: true` olduğunda `GET /api/conversations/{id}` içinde hemen yer
  alsın (yerel veritabanına, IMAP eşleşmesini beklemeden yazılsın).

## 3. `conversationId` her mail yanıtında dolu olmalı (öncelik: orta)

`GET /api/mails/{id}` ve liste öğelerinde `conversationId` "varsa" geliyor. İstemci boş
`conversationId` gelen maili tek mesajlık thread sayıyor ve sohbet görünümünü açmıyor.
Her mail bir konuşmaya ait olmalı (tek mailse kendi konuşması). Gönderilmiş ve Taslak klasörleri
dahil.

## 4. Konuşma mesajları klasörlerden bağımsız dönmeli (öncelik: orta)

`GET /api/conversations/{id}` içindeki `messages[]` Gelen Kutusu, Gönderilmiş, Arşiv ve
(isteğe bağlı) Çöp'teki tüm mesajları içermeli. Sohbette karşılıklı yazışma gösterildiği için
yalnızca gelen kutusundaki mesajlar dönerse kullanıcının kendi yanıtları eksik kalır.
Çöp/Spam mesajları için `includeTrash=false` gibi bir query seçeneği faydalı olur.

## 5. Mesaj özetinde yön bilgisi (öncelik: düşük)

Şu an istemci "kendi mesajım mı" bilgisini gönderen adresini bağlı hesap adresleriyle
karşılaştırarak çıkarıyor. Takma adlar (alias) ve "Send as" adresleri bu eşleşmeyi bozar
(kendi mesajı karşı tarafınmış gibi solda görünür).

**İstenen:** `messages[]` ve mail detayında `isFromMe: bool` (ya da hesabın tüm kimlik adreslerini
`GET /api/accounts` içinde `aliases[]` olarak döndürmek).

## 6. Konuşma sayacı tutarlılığı (öncelik: düşük)

`messageCount` ile `GET /api/conversations/{id}` içindeki `messages.length` aynı olmalı. İstemci
liste satırında `messageCount` ile "N mesaj" gösteriyor, detayda farklı sayı görünürse tutarsız
görünüyor.

## Kabul kriterleri

1. Bir mail yanıtlanınca (`replySourceMailId` ile) yanıt, gönderimden ≤ 2 sn içinde
   `GET /api/conversations/{id}` `messages[]` listesinde bulunur.
2. Konu satırı değiştirilen bir yanıt aynı konuşmaya düşer (`In-Reply-To` ile).
3. Gönderim yanıtı `mailId` + `conversationId` içerir.
4. Aynı mesaj hiçbir zaman iki farklı id ile aynı konuşmada listelenmez.
5. Uygulama tarafında sohbet görünümü, sunucuyla senkron olsun olmasın aynı mesajı bir kez gösterir
   (bu maddenin istemci kısmı §2 tamamlanınca eklenecek).
