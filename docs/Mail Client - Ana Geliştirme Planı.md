# Mail Client - Ana Geliştirme Planı

## 1. Hedef

Projenin uzun vadeli hedefi:

> Android ve iOS öncelikli, Flutter tabanlı, çoklu hesap destekleyen, offline çalışabilen, güvenli ve modern bir mail istemcisi oluşturmak.

Platform önceliği:

```text
1. Android
2. iOS
3. Desktop
```

Desktop hedef dışı değildir ancak ürün ve mimari kararları masaüstü merkezli alınmayacaktır.

Flutter'ın cross-platform yapısı korunacak; ileride Windows/Linux/macOS desteği eklenebilecek şekilde platform bağımsız domain ve data katmanları kullanılacaktır.

Mevcut backend yeniden yazılmayacak.

Korunacak temel:

```text
IMAP sync
SMTP send
UID / UIDVALIDITY
credential encryption
refresh-token rotation
account isolation
mail discovery
SSRF protection
TLS validation
attachment storage
idempotent sending
audit/logging
PostgreSQL persistence
```

Ana geliştirme stratejisi:

```text
Backend production baseline
        ↓
Rich Mail Domain Model
        ↓
MIME / HTML Security
        ↓
Conversation / Thread
        ↓
Mobile Flutter Foundation
        ↓
Mail Operations + Draft / Outbox
        ↓
Multi-Account / Unified Views
        ↓
Search
        ↓
OAuth2 / Providers
        ↓
Mobile Background Sync / Notifications
        ↓
Sync Scalability
        ↓
Product Polish
```

---

# 2. Değişmeyecek Mimari Kararlar

## MailAccount principal olmaya devam edecek

Backend'de tekrar:

```text
User
 └── MailAccount[]
```

modeline dönülmeyecek.

Backend authentication:

```text
JWT sub = MailAccountId
```

olarak kalacak.

Her mail hesabı bağımsız:

```text
MailAccount
├── Credentials
├── Sessions
├── Folders
├── Messages
├── Attachments
├── Devices
└── Sync State
```

olacak.

---

## LocalProfile backend User değildir

Bir cihazdaki hesapların gruplanması Flutter tarafında yapılacak:

```text
LocalProfile
├── Gmail Account
├── Outlook Account
└── Custom IMAP Account
```

Bu kavram:

```text
Flutter local state / local database
```

içinde bulunacak.

Backend'e sırf Unified Inbox için application-level User eklenmeyecek.

---

# 3. Mobile-First Tasarım İlkeleri

Ürün kararlarında Android/iOS davranışları önceliklidir.

## UI source-of-truth

Flutter UI mümkün olduğunca doğrudan backend response'una bağlı çalışmayacak.

Hedef:

```text
Flutter UI
    ↓
Local Database
    ↑
Repository
    ↑↓
Backend API
```

Local database ekranların ana veri kaynağı olacak.

Bu sayede:

- uygulama hızlı açılır,
- internet olmadan mailler görüntülenebilir,
- network değişimleri UI'yı doğrudan bozmaz,
- unified inbox local olarak oluşturulabilir.

---

## Mobile lifecycle

Uygulamanın:

```text
foreground
background
suspended
terminated
```

durumları dikkate alınacak.

Flutter tarafında uzun süre çalışan desktop-style background worker varsayılmayacak.

Android ve iOS'un background execution limitleri mimarinin parçası olacak.

---

## Push-first synchronization

Mobilde sürekli polling ana mekanizma olmamalı.

Tercih edilen akış:

```text
Backend detects new mail
        ↓
FCM / APNs
        ↓
Mobile notification
        ↓
App foreground/background opportunity
        ↓
API delta sync
        ↓
Local DB update
```

Push notification veri kaynağı değildir.

Push yalnız:

```text
"yeni veri olabilir"
```

sinyalidir.

Gerçek state her zaman backend API'den alınır.

---

## Secure storage

Mobil cihazda:

```text
provider password
provider OAuth refresh token
```

saklanmayacak.

Bunlar backend'de kalacak.

Flutter'ın saklaması gereken Mail Client session bilgileri OS-backed secure storage kullanmalı.

Android:

```text
Keystore
```

iOS:

```text
Keychain
```

Flutter'da uygun secure-storage abstraction üzerinden kullanılmalı.

---

# 4. Faz 0 - Production Hardening ve Baseline

## Amaç

Domain modelini değiştirmeden önce mevcut backend'i güvenli baseline haline getirmek.

### 0.1 JWT production güvenliği

Production ortamında development JWT key ile uygulama başlamamalı.

```text
Production
+
missing/default Jwt:Key
        ↓
startup failure
```

Development için örnek key kullanılabilir.

Production configuration en az:

```text
Jwt__Key
ConnectionStrings__Default
DataProtection__KeyPath
DataProtection__CertificatePath
```

içermeli.

`.env.example` gerçek secret içermeden genişletilmeli.

---

### 0.2 Authenticated log enrichment

Pipeline:

```text
Correlation
    ↓
Authentication
    ↓
Authenticated log enrichment
```

Authenticated loglarda:

```text
CorrelationId
MailAccountId
```

bulunmalı.

---

### 0.3 Discovery resource limits

Configuration:

```text
MailDiscovery:
  OverallTimeoutSeconds
  StrategyTimeoutSeconds
  MaxDocumentBytes
```

Başlangıç:

```text
Overall timeout: 30-45 saniye
Max document: 256 KB
```

Autoconfig XML:

- DTD disabled
- external entity disabled
- bounded input

olmalı.

Autodiscover JSON da bounded okunmalı.

---

### 0.4 JWT account existence validation

JWT geçerli olsa bile account silinmişse:

```text
authentication reject
```

edilmeli.

`NeedsReauthentication` account cached mail erişimi için authenticated kalabilir.

---

### 0.5 CI baseline

Korunacak:

```text
Release build
Unit tests
PostgreSQL integration
GreenMail integration
Formatting
NuGet vulnerability audit
CodeQL
```

## Faz 0 çıkış kriteri

- Production development JWT key ile başlamaz.
- Authenticated loglarda MailAccountId vardır.
- Discovery bounded çalışır.
- Silinmiş account token'ı reddedilir.
- CI tamamen yeşildir.

---

# 5. Faz 1 - Rich Mail Domain Model

## Amaç

Gerçek MIME mesajını önemli semantiğini kaybetmeden saklamak.

---

## Participants

```text
MailParticipant
- Id
- MailId
- Type
- Address
- NormalizedAddress
- DisplayName
- SortOrder
```

Type:

```text
From
To
Cc
Bcc
ReplyTo
```

Mail:

```text
Mail
├── From[]
├── To[]
├── Cc[]
├── Bcc[]
└── ReplyTo[]
```

desteklemeli.

---

## Message identity

Eklenmeli:

```text
MessageId
InReplyToMessageId
References
```

Message-ID normalize edilmeli.

Eksik veya hatalı Message-ID sync'i bozmamalı.

Duplicate Message-ID mümkün olduğu için unique key olarak kullanılmamalı.

IMAP mesaj identity'si:

```text
MailFolder + UID
```

temelinde kalmalı.

---

## Headers

Önemli structured headers:

```text
Message-Id
In-Reply-To
References
Date
Reply-To
Content-Language
List-Id
List-Unsubscribe
```

Gerekirse:

```text
MailHeader
- MailId
- Name
- Value
```

kullanılabilir.

---

## Flags

Destek:

```text
Seen
Answered
Flagged
Deleted
Draft
Recent
```

Custom IMAP keywords ayrıca modellenebilir.

---

## Attachments

```text
Attachment
- ContentId
- IsInline
- ContentDisposition
- FileName
- ContentType
- SizeBytes
- StoragePath
```

Gelecekte:

```text
SHA256
MimePartId
```

eklenebilir.

---

## Timestamps

Ayrılmalı:

```text
SentAt
ReceivedAt
InternalDate
```

---

## API DTO

Domain entity yerine:

```text
MailListItemResponse
MailDetailResponse
MailParticipantResponse
AttachmentResponse
```

kullanılmalı.

---

## MIME mapping

```text
MimeMessage
    ↓
IncomingMailMapper
    ↓
Normalized Mail Aggregate
    ↓
PostgreSQL
```

Mapper:

- participants
- headers
- flags
- dates
- body variants
- attachments
- Content-ID
- threading metadata

korumalı.

## Faz 1 testleri

```text
multiple From
multiple To
Cc/Bcc
Reply-To
missing Message-ID
duplicate Message-ID
malformed Message-ID
In-Reply-To
References
plain text
HTML
multipart alternative
CID images
multiple attachments
UTF-8 / encoded headers
custom flags
```

## Çıkış kriteri

Gerçek MIME mail threading, rendering ve reply için gereken verileri kaybetmeden saklanabilir.

---

# 6. Faz 2 - MIME / HTML Security

## Amaç

Mobil WebView veya HTML renderer'a raw mail HTML verilmesini önlemek.

Pipeline:

```text
MIME
 ↓
Parse
 ↓
Normalize
 ↓
Sanitize
 ↓
Remote Content Policy
 ↓
CID Resolution
 ↓
Safe Flutter Rendering Contract
```

## Block

```text
script
iframe
object
embed
event handlers
javascript:
unsafe forms
dangerous CSS
```

---

## Remote images

Varsayılan:

```text
blocked
```

Response metadata:

```text
hasRemoteContent
```

UI kullanıcıya:

```text
"Harici görselleri yükle"
```

aksiyonu gösterebilir.

---

## Tracking protection

Otomatik fetch edilmemeli:

```text
tracking pixels
remote images
remote CSS
remote fonts
```

---

## CID

```html
<img src="cid:logo123">
```

güvenli attachment representation'a dönüştürülmeli.

---

## Mobil link handling

Link doğrudan WebView içinde sınırsız navigation yapmamalı.

Desteklenen scheme:

```text
https
http
mailto
```

kontrollü ele alınmalı.

Unsafe schemes reddedilmeli.

## Çıkış kriteri

Güvenilmeyen mail Android/iOS üzerinde güvenli biçimde gösterilebilir.

---

# 7. Faz 3 - Conversation / Thread Engine

## Domain

```text
Conversation
- Id
- MailAccountId
- NormalizedSubject
- StartedAt
- LastMessageAt
```

İlişki:

```text
Conversation
├── Mail
├── Mail
└── Mail
```

Matching sırası:

```text
1. In-Reply-To
2. References
3. Message-ID graph
4. Controlled subject fallback
```

Subject-only threading yapılmamalı.

Algorithm:

- deterministic
- idempotent
- cycle-safe
- arrival-order independent

olmalı.

API:

```text
GET /api/conversations
GET /api/conversations/{id}
```

## Çıkış kriteri

Reply zinciri doğru conversation altında gruplanır.

---

# 8. Faz 4 - Flutter Mobile Foundation

## Amaç

Android/iOS uygulamasının veri ve state temelini backend contractları üzerine kurmak.

Büyük UI polish yapılmayacak.

Architecture:

```text
Presentation
    ↓
Application / State
    ↓
Domain
    ↓
Repository
    ↓
┌─────────────┬────────────┐
│ Local DB    │ Remote API │
└─────────────┴────────────┘
```

## Local database

Önerilen:

```text
SQLite + Drift
```

Local olarak:

```text
Accounts
Folders
Conversations
Messages
Participants
Attachment metadata
Sync metadata
Pending operations
Drafts
Outbox
```

saklanabilir.

---

## Local Profile

```text
LocalProfile
├── Account A
├── Account B
└── Account C
```

Account session'ları birbirinden bağımsızdır.

---

## Session management

Her account:

```text
AccessToken
RefreshToken
MailAccount metadata
```

taşır.

Refresh token secure storage'a yazılır.

Access token memory/cache seviyesinde tutulabilir.

---

## Repository pattern

Örneğin:

```text
MailRepository
ConversationRepository
AccountRepository
FolderRepository
```

UI network DTO'suna doğrudan bağlı olmamalı.

---

## İlk mobile screens

İlk ürün iskeleti:

```text
Account Setup
Account List
Inbox
Conversation View
Message View
Basic Compose
Settings
Reauthentication
```

Bu aşamada ileri seviye polish yapılmayacak.

## Faz 4 çıkış kriteri

Android/iOS uygulaması backend'e bağlanabilir, account session yönetebilir ve local cache üzerinden temel inbox gösterebilir.

---

# 9. Faz 5 - Mail Operations + Draft / Outbox

Destek:

```text
read / unread
star / unstar
archive
trash
restore
spam
move
copy
```

sonrasında bulk işlemler.

---

## Reply

```text
Reply
Reply All
Forward
```

doğru participant modeli üzerinden çalışmalı.

Reply:

```text
Reply-To
↓ yoksa
From
```

Reply All:

- sender
- To
- Cc

üzerinden hesaplanmalı.

Kullanıcının kendi address'i çıkarılmalı.

---

## Draft

Draft hem:

```text
local mobile draft
```

hem ileride:

```text
remote Drafts folder
```

ile çalışabilecek şekilde tasarlanmalı.

Mobilde compose sırasında sürekli server'a bağlı olma zorunluluğu olmamalı.

---

## Mobile Outbox

Mobil ürün için kritik.

```text
Compose
 ↓
Local persistent Outbox
 ↓
Network available
 ↓
Backend send
 ↓
Idempotency-Key
 ↓
SMTP
```

State:

```text
Pending
Sending
Sent
Retrying
Failed
DeliveryUnknown
```

App process öldürülse bile pending send kaybolmamalı.

## Çıkış kriteri

Offline compose/send queue dahil temel mail yönetim işlemleri mobil uygulamadan yapılabilir.

---

# 10. Faz 6 - Multi-Account / Unified Views

Flutter local database:

```text
Account A ─┐
Account B ─┼→ Local DB → Unified Inbox
Account C ─┘
```

Unified:

```text
Inbox
Sent
Unread count
Notifications
Search
```

local profile üzerinden oluşturulur.

Backend:

```text
one request
=
one authenticated account
```

modelini korur.

Server-side unified User sistemi oluşturulmaz.

## Çıkış kriteri

Android/iOS uygulamasında birden fazla hesap aynı UI içinde yönetilebilir.

---

# 11. Faz 7 - Search

Backend:

```text
PostgreSQL FTS
```

ile başlayacak.

Search:

```text
Subject
BodyText
From
To
Cc
ReplyTo
Attachment filename
MessageId
```

Filters:

```text
folder
conversation
date
read/unread
flagged
attachments
```

Flutter ayrıca local cache üzerinde hızlı/offline search sağlayabilir.

Bu iki search katmanı farklı amaç taşır:

```text
Local Search
→ hızlı + offline + cached data

Backend Search
→ server'da bulunan tam indexed data
```

## Çıkış kriteri

Kullanıcı Android/iOS'ta hem cached mailleri offline hem backend verisini online arayabilir.

---

# 12. Faz 8 - OAuth2 / Provider Support

Öncelik:

```text
1. Gmail
2. Microsoft / Outlook
3. diğer provider'lar
```

Generic IMAP:

```text
Password
AppSpecificPassword
```

kalır.

OAuth:

```text
Flutter
 ↓
system browser / provider authorization
 ↓
callback / deep link
 ↓
backend
 ↓
code exchange
 ↓
encrypted provider refresh token
 ↓
XOAUTH2 IMAP/SMTP
```

Mobilde OAuth için embedded WebView yerine mümkün olduğunca system browser / platform authorization yaklaşımı tercih edilmeli.

Gerekli:

```text
state
PKCE
deep-link/app-link validation
callback validation
```

MailClient refresh token ile provider refresh token karıştırılmamalı.

## Çıkış kriteri

Gmail ve Microsoft account Android/iOS'tan güvenli OAuth flow ile eklenebilir.

---

# 13. Faz 9 - Mobile Background Sync ve Notifications

Bu faz masaüstü background worker varsayımlarına göre değil Android/iOS kısıtlarına göre tasarlanmalı.

## Push

Backend:

```text
new mail
 ↓
Firebase / APNs
 ↓
device token
```

Flutter:

```text
push received
 ↓
notification
 ↓
schedule / trigger delta refresh
```

---

## Android

Dikkate alınmalı:

```text
Doze
App Standby
battery optimization
WorkManager
background execution limits
notification permission
```

---

## iOS

Dikkate alınmalı:

```text
APNs
Background App Refresh
BGTaskScheduler
silent notification limitations
system scheduling decisions
```

iOS üzerinde sürekli background polling garantisi olmadığı kabul edilmeli.

---

## Sync strategy

```text
App launch
→ immediate delta sync

App foreground
→ refresh if stale

Push
→ targeted refresh

Background opportunity
→ bounded refresh

Manual pull-to-refresh
→ high-priority refresh
```

## Çıkış kriteri

Mobil client sürekli polling gerektirmeden güncel mailbox deneyimi sağlayabilir.

---

# 14. Faz 10 - Sync Scalability / Reliability

Backend tarafında:

```text
bounded account concurrency
bounded folder concurrency
retry/backoff
jitter
priority
cancellation
provider connection budget
```

eklenebilir.

Priority:

```text
User requested
>
Inbox
>
other folders
```

Correctness concurrency'den önce gelir.

## Çıkış kriteri

Çok account ve büyük mailbox yükünde backend stabil çalışır.

---

# 15. Faz 11 - Observability / Mobile Diagnostics

Backend metrics:

```text
sync_duration
messages_synced
sync_failures
auth_failures
smtp_duration
smtp_failures
delivery_unknown
api_latency
search_latency
```

Mobile diagnostics:

```text
sync result
local DB migration result
API latency
push received
push → sync latency
outbox retry
session refresh failure
```

Hassas içerikler telemetry'ye yazılmamalı.

---

# 16. Faz 12 - Product Polish

Mobile öncelikli:

```text
Swipe actions
Pull-to-refresh
Notification actions
Biometric app lock
Dynamic theme
Dark mode
Share sheet
Attachment viewer
OS file picker
Deep links
App links
Contact integration
Signatures
Templates
Snooze
Scheduled send
Rules
Filters
Tags
Smart folders
Calendar integration
```

Daha sonra desktop:

```text
keyboard-first navigation
multi-window
system tray
desktop notifications
drag & drop
```

gibi platform özellikleri eklenebilir.

Desktop hiçbir zaman Android/iOS temel mimarisini belirleyen platform olmayacaktır.

---

# 17. Nihai Domain Model

Backend:

```text
MailAccount
├── MailCredential
├── MailSession
├── MailFolder[]
├── DeviceRegistration[]
└── SyncState[]
```

Mail:

```text
Conversation
└── Mail[]
    ├── MailParticipant[]
    ├── MailHeader[]
    ├── MailFlags
    └── Attachment[]
```

Flutter:

```text
LocalProfile
├── LocalAccount[]
├── Conversations
├── Messages
├── Drafts
├── Outbox
├── PendingOperations
└── LocalSyncState
```

---

# 18. API Evolution Strategy

Current-account scoped backend korunur:

```text
GET /api/folders
GET /api/mails
GET /api/mails/{id}
POST /api/mails/send
```

Yeni endpointler:

```text
/api/conversations
/api/conversations/{id}

/api/search

/api/messages/{id}/read
/api/messages/{id}/unread
/api/messages/{id}/star
/api/messages/{id}/archive
/api/messages/{id}/trash
/api/messages/{id}/move
```

Unified API başlangıçta backend'e eklenmez.

Unified state Flutter local database üzerinden oluşturulur.

---

# 19. Test Stratejisi

## Backend unit

```text
recipient parsing
Message-ID normalization
References parsing
thread matching
subject normalization
MIME mapping
HTML sanitization
remote content detection
CID resolution
flags
reply recipients
sync state
```

## Backend integration

```text
PostgreSQL
GreenMail IMAP
GreenMail SMTP
migrations
account isolation
mail operations
thread persistence
search
attachments
```

## Flutter unit

```text
repository logic
state transitions
session management
unified merge
outbox state machine
offline operation queue
search mapping
```

## Flutter integration

```text
SQLite/Drift
secure storage
API repository
token refresh
local cache reconciliation
```

## Mobile end-to-end

```text
Install app
→ add account
→ discovery
→ authenticate
→ initial sync
→ inbox
→ open conversation
→ safe HTML
→ mark read
→ reply
→ send
→ notification
→ offline mode
→ reconnect
→ reconcile
```

Multi-account:

```text
Account A
+
Account B
→ Unified Inbox
→ account-specific actions
```

---

# 20. Migration Stratejisi

Database migration'lar additive ilerlemeli.

Rich Mail Model geçişi:

```text
1. yeni participant/header alanlarını ekle
2. mevcut veriyi backfill et
3. application code'u yeni modele geçir
4. doğrula
5. eski kolonları daha sonraki migration'da kaldır
```

Mobile local DB de migration versioning kullanmalı.

Uygulama güncellemesi mevcut offline mailbox cache'ini gereksiz yere silmemeli.

---

# 21. Development Gates

## Gate A

```text
Production hardening complete
CI green
```

## Gate B

```text
Rich Mail Model complete
DTO contracts stable
```

## Gate C

Gerçek Message View öncesi:

```text
HTML sanitization
remote content policy
CID support
```

## Gate D

Mobile feature development öncesi:

```text
Flutter local DB
repository architecture
secure session storage
```

## Gate E

Unified Inbox öncesi:

```text
multi-account local profile
account-independent repositories
```

## Gate F

Production mobile release öncesi:

```text
Android background behavior tested
iOS background behavior tested
FCM/APNs tested
offline/outbox tested
token refresh tested
```

---

# 22. Öncelik Tablosu

| ID | İş | Öncelik | Faz |
|---|---|---:|---:|
| TD-00 | Production hardening | P0 | 0 |
| TD-01 | Rich mail model | P0 | 1 |
| TD-02 | MIME / HTML security | P0 | 2 |
| TD-03 | Conversation/thread | P0 | 3 |
| TD-04 | Flutter mobile foundation | P0 | 4 |
| TD-05 | Mail operations | P0 | 5 |
| TD-06 | Draft / mobile outbox | P0 | 5 |
| TD-07 | Multi-account / unified | P0 | 6 |
| TD-08 | Search | P0 | 7 |
| TD-09 | OAuth2/providers | P1 | 8 |
| TD-10 | Mobile background sync/push | P0 | 9 |
| TD-11 | Backend sync scalability | P1 | 10 |
| TD-12 | Observability | P1 | 11 |
| TD-13 | Mobile product polish | P1 | 12 |
| TD-14 | Desktop-specific features | P2 | Future |

---

# 23. Yapılmaması Gerekenler

## Backend'i yeniden yazma

Mevcut transport/security altyapısı korunmalı.

## Backend'e unified inbox için User ekleme

LocalProfile mobil tarafta yeterli.

## Mobil uygulamayı thin API client yapma

Local DB kullanılmalı.

## Mobilde sürekli polling'e güvenme

Android/iOS background execution sınırlıdır.

## Raw HTML render etme

Sanitize edilmemiş içerik UI'ya ulaşmamalı.

## Provider password'u mobile storage'a koyma

Provider credentials backend'de kalmalı.

## Subject-only threading

Yetersizdir.

## İlk aşamada Elasticsearch ekleme

PostgreSQL FTS ile başlanmalı.

## Flutter UI'yı backend domain entity'lerine bağlama

DTO + repository abstraction kullanılmalı.

## Desktop ihtiyaçlarını mobil mimarinin önüne koyma

Desktop gelecekte ek hedef olabilir.

---

# 24. Şimdi Yapılacak İş

Sıradaki iş:

```text
SPRINT 0
Production Hardening
```

Ardından:

```text
SPRINT 1
Rich Mail Domain Model
```

Sonrasında:

```text
SPRINT 2
MIME / HTML Security

SPRINT 3
Conversation / Thread

SPRINT 4
Flutter Mobile Foundation
```

Bu noktadan sonra Android/iOS üzerinde gerçek ürün geliştirmesi hızlandırılabilir.

---

# 25. Nihai İş Sırası

```text
[CURRENT]
Backend foundation
      │
      ▼
[0] Production Hardening
      │
      ▼
[1] Rich Mail Model
      │
      ▼
[2] MIME / HTML Security
      │
      ▼
[3] Conversation / Thread
      │
      ▼
[4] Flutter Mobile Foundation
 Android + iOS
      │
      ▼
[5] Mail Operations
 Draft + Outbox
      │
      ▼
[6] Multi-Account
 Unified Views
      │
      ▼
[7] Search
      │
      ▼
[8] OAuth2 / Providers
      │
      ▼
[9] Push + Mobile Background Sync
      │
      ▼
[10] Backend Sync Scalability
      │
      ▼
[11] Observability
      │
      ▼
[12] Mobile Product Polish
      │
      ▼
[FUTURE]
Desktop-specific support
```

Ana prensip:

> Backend mail verisinin güvenilir kaynağıdır; Flutter local database ise mobil kullanıcı deneyiminin ana veri kaynağıdır.

Android ve iOS uygulaması çevrimdışı çalışabilecek şekilde tasarlanacak, push-assisted synchronization kullanacak ve mobil işletim sistemlerinin background execution kurallarını mimarinin temel girdilerinden biri olarak kabul edecektir.

Desktop desteği ileride aynı domain/repository katmanları üzerine eklenebilir, ancak mevcut roadmap Android/iOS merkezlidir.