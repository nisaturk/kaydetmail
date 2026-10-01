// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get pressBackAgainToExit => 'Çıkmak için geri tuşuna tekrar basın.';

  @override
  String get draftSavedLocallyServerSync =>
      'Taslak yerel olarak kaydedildi; sunucu eşitlemesi başarısız.';

  @override
  String outgoingMessagesAreWaitingFor(int attention) {
    return '$attention gönderi Giden Kutusu’nda incelenmeyi bekliyor.';
  }

  @override
  String get open => 'Aç';

  @override
  String get couldntOpenTheOutboxTry =>
      'Giden Kutusu açılamadı. Yeniden deneyin.';

  @override
  String get full => 'Tam';

  @override
  String get senderSubjectAndAShort => 'Gönderen, konu ve kısa önizleme';

  @override
  String get limited => 'Sınırlı';

  @override
  String get senderAndSubject => 'Gönderen ve konu';

  @override
  String get private => 'Gizli';

  @override
  String get onlyNewEmail => 'Yalnızca \"Yeni e-posta\"';

  @override
  String get inboxSent => 'Gelen + Gönderilen';

  @override
  String get allFolders => 'Tüm klasörler';

  @override
  String get selectedFolders => 'Seçili klasörler';

  @override
  String thisFileExceedsTheMaximum(Object value) {
    return 'Bu dosya izin verilen maksimum boyutu ($value) aşıyor.';
  }

  @override
  String theTotalSizeOfAttachments(Object value) {
    return 'Eklerin toplam boyutu izin verilen sınırı ($value) aşıyor.';
  }

  @override
  String get attachmentCountLimitExceeded => 'Ek dosya sayısı sınırı aşıldı.';

  @override
  String get anAttachmentExceedsTheMaximum =>
      'Bir ek izin verilen maksimum boyutu aşıyor.';

  @override
  String get file => 'Dosya';

  @override
  String get sent => 'Gönderilenler';

  @override
  String get trash => 'Çöp Kutusu';

  @override
  String get archive => 'Arşiv';

  @override
  String get other => 'Diğer';

  @override
  String get inbox => 'Gelen Kutusu';

  @override
  String get allMail => 'Tüm mailler';

  @override
  String get outbox => 'Giden Kutusu';

  @override
  String get starred => 'Yıldızlılar';

  @override
  String get snoozed => 'Ertelenenler';

  @override
  String get drafts => 'Taslaklar';

  @override
  String get enterAValidEmailAddress => 'Geçerli bir e-posta adresi girin.';

  @override
  String get thisEmailIsAlreadySaved => 'Bu e-posta zaten kayıtlı.';

  @override
  String get labelNameCantBeEmpty => 'Etiket adı boş olamaz.';

  @override
  String get theSenderAddressCouldntBe => 'Gönderici adresi okunamadı.';

  @override
  String connected(Object email) {
    return '$email bağlandı.';
  }

  @override
  String get addNewAccount => 'Yeni hesap ekle';

  @override
  String get enterAValidEmailAddress2 => 'Geçerli bir e-posta adresi girin';

  @override
  String get email => 'E-posta';

  @override
  String get passwordIsRequired => 'Şifre zorunludur';

  @override
  String get password => 'Şifre';

  @override
  String get showPassword => 'Şifreyi göster';

  @override
  String get hidePassword => 'Şifreyi gizle';

  @override
  String get connect => 'Bağla';

  @override
  String get downloadCancelled => 'İndirme iptal edildi.';

  @override
  String get share => 'Paylaş';

  @override
  String get downloading => 'İndiriliyor…';

  @override
  String get cancel => 'İptal';

  @override
  String get thisFileTypeCantBe => 'Bu dosya türü uygulama içinde açılamıyor.';

  @override
  String get theFileCouldntBePreviewed => 'Dosya önizlenemedi.';

  @override
  String get openInAnotherApp => 'Başka uygulamada aç';

  @override
  String get emptyDocument => '(Boş belge)';

  @override
  String get chooseASavedTextOr => 'Hazır metin veya şablon seç';

  @override
  String get close => 'Kapat';

  @override
  String get tryAgain => 'Tekrar dene';

  @override
  String get noSavedTextsForThis =>
      'Bu hesapta kayıtlı metin yok.\nAyarlar > Hazır Metinler ve Şablonlar';

  @override
  String get downloadAgain => 'Tekrar indir';

  @override
  String get remove => 'Kaldır';

  @override
  String theEmailWillBeSent(Object _secondsLeft) {
    return 'E-posta $_secondsLeft sn içinde gönderilecek';
  }

  @override
  String get insertLink => 'Bağlantı Ekle';

  @override
  String get cancel2 => 'Vazgeç';

  @override
  String get add => 'Ekle';

  @override
  String get image => 'Görsel';

  @override
  String get embeddedContent => 'Gömülü içerik';

  @override
  String get addFromContacts => 'Kişilerden ekle';

  @override
  String get to => 'Kime';

  @override
  String get searchNameOrEmail => 'Ad veya e-posta ara';

  @override
  String get noSavedContactsYet => 'Henüz kayıtlı kişi yok.';

  @override
  String get noMatchingContactsFound => 'Eşleşen kişi bulunamadı.';

  @override
  String get editDraft => 'Taslağı Düzenle';

  @override
  String get sendNow => 'Şimdi Gönder';

  @override
  String get moreOptions => 'Diğer seçenekler';

  @override
  String get schedule => 'Zamanla';

  @override
  String get saveDraft => 'Taslağı kaydet';

  @override
  String get delete => 'Sil';

  @override
  String get addCcBcc => 'Cc / Bcc ekle';

  @override
  String get subject => 'Konu';

  @override
  String get writeYourMessage => 'Mesajınızı yazın';

  @override
  String get from => 'Kimden';

  @override
  String get chooseIdentity => 'Kimlik seç';

  @override
  String get chooseAccount => 'Hesap seç';

  @override
  String get attachFile => 'Dosya ekle';

  @override
  String get savedTexts => 'Hazır Metinler';

  @override
  String get anAttachmentCouldntBeDownloaded =>
      'Bir ek indirilemedi. Tekrar deneyin veya kaldırın.';

  @override
  String get attachmentsAreBeingPreparedPlease =>
      'Ekler hazırlanıyor, lütfen bekleyin.';

  @override
  String get chooseFile => 'Dosya seç';

  @override
  String get choosePhoto => 'Fotoğraf seç';

  @override
  String get camera => 'Kamera';

  @override
  String get couldntAccessTheCameraCheck =>
      'Kameraya erişilemedi. İzinleri kontrol edin veya dosya seçin.';

  @override
  String get couldntAccessPhotosCheckPermissions =>
      'Fotoğraflara erişilemedi. İzinleri kontrol edin veya dosya seçin.';

  @override
  String get imageSize => 'Görsel boyutu';

  @override
  String get original => 'Orijinal';

  @override
  String get large2048Px => 'Büyük (2048 px)';

  @override
  String get medium1280Px => 'Orta (1280 px)';

  @override
  String get small640Px => 'Küçük (640 px)';

  @override
  String preparingImages(Object completed, Object length) {
    return 'Görseller hazırlanıyor… ($completed/$length)';
  }

  @override
  String couldntResizeTheImageThe(Object name) {
    return '$name: Görsel küçültülemedi; özgün dosya kullanılacak.';
  }

  @override
  String get couldntSaveTheDraftTry => 'Taslak kaydedilemedi. Tekrar deneyin.';

  @override
  String get youCanSaveWhatYouve =>
      'Yazdıklarınızı daha sonra tamamlamak için kaydedebilir veya taslağı kalıcı olarak silebilirsiniz.';

  @override
  String get couldntSaveTheDraftYour =>
      'Taslak kaydedilemedi. İçeriğiniz ekranda tutuluyor.';

  @override
  String get draftSaved => 'Taslak kaydedildi.';

  @override
  String get saving => 'Kaydediliyor…';

  @override
  String get saveDraft2 => 'Taslağı Kaydet';

  @override
  String get deleteDraft => 'Taslağı Sil';

  @override
  String get keepEditing => 'Düzenlemeye devam et';

  @override
  String get thisActionCantBeUndone => 'Bu işlem geri alınamaz.';

  @override
  String couldntDeleteTheDraft(Object value) {
    return 'Taslak silinemedi: $value';
  }

  @override
  String get draftDeleted => 'Taslak silindi.';

  @override
  String get youMustEnterAtLeast => 'En az bir alıcı yazmalısınız.';

  @override
  String get fixTheInvalidEmailAddresses =>
      'Geçersiz e-posta adreslerini düzeltip tekrar deneyin.';

  @override
  String couldntSaveTheMessage(Object value) {
    return 'Gönderi kaydedilemedi: $value';
  }

  @override
  String get undo => 'Geri Al';

  @override
  String get aReadReceiptWillBe => 'Alıcılardan okundu bilgisi istenecek.';

  @override
  String get pleaseChooseAFutureDate => 'Lütfen ileri bir tarih ve saat seçin.';

  @override
  String theEmailIsScheduledTo(Object value) {
    return 'E-posta $value tarihinde gönderilmek üzere zamanlandı.';
  }

  @override
  String couldntSchedule(Object value) {
    return 'Zamanlanamadı: $value';
  }

  @override
  String couldntLoadTheSenderIdentity(Object value) {
    return 'Gönderen kimliği yüklenemedi: $value';
  }

  @override
  String get replaceTheSubject => 'Konuyu değiştir?';

  @override
  String get theCurrentSubjectWillBe =>
      'Mevcut konu hazır metindeki konuyla değiştirilecek.';

  @override
  String get keepSubject => 'Konuyu koru';

  @override
  String get replace => 'Değiştir';

  @override
  String get manageFolders => 'Klasörleri yönet';

  @override
  String get whichAccountsFoldersDoYou =>
      'Hangi hesabın klasörleri yönetilsin?';

  @override
  String get folder => 'Klasör';

  @override
  String get chooseParentFolder => 'Üst klasör seçin';

  @override
  String get topLevelFolder => 'Bağımsız klasör';

  @override
  String get newFolder => 'Yeni klasör';

  @override
  String get createSubfolder => 'Alt klasör oluştur';

  @override
  String get folderCreated => 'Klasör oluşturuldu.';

  @override
  String get rename => 'Yeniden adlandır';

  @override
  String get folderRenamed => 'Klasör yeniden adlandırıldı.';

  @override
  String get parentFolderChanged => 'Üst klasör değiştirildi.';

  @override
  String get folderCantBeDeleted => 'Klasör silinemez';

  @override
  String get ok => 'Tamam';

  @override
  String get deleteFolder => 'Klasör silinsin mi?';

  @override
  String theFolderWillBePermanently(Object name) {
    return '\"$name\" klasörü sunucudan kalıcı olarak silinecek.';
  }

  @override
  String get folderDeleted => 'Klasör silindi.';

  @override
  String whatShouldBeUsedAs(Object name) {
    return '\"$name\" ne olarak kullanılsın?';
  }

  @override
  String isNowUsedAs(Object name, Object value) {
    return '\"$name\" artık $value olarak kullanılıyor.';
  }

  @override
  String automaticDetectionRestoredFor(Object name) {
    return '\"$name\" için otomatik tespit geri yüklendi.';
  }

  @override
  String synced(Object name) {
    return '\"$name\" eşitlendi.';
  }

  @override
  String willSyncAutomatically(Object name) {
    return '\"$name\" otomatik eşitlenecek.';
  }

  @override
  String willNotSyncAutomatically(Object name) {
    return '\"$name\" otomatik eşitlenmeyecek.';
  }

  @override
  String get folders => 'Klasörler';

  @override
  String get rescanFoldersOnTheServer => 'Sunucudaki klasörleri yeniden tara';

  @override
  String get folderNotFound => 'Klasör bulunamadı';

  @override
  String usedAs(Object value) {
    return '$value olarak kullanılıyor';
  }

  @override
  String get standardFolders => 'Standart klasörler';

  @override
  String get myFolders => 'Klasörlerim';

  @override
  String get spam => 'Spam';

  @override
  String get showSubfolders => 'Alt klasörleri göster';

  @override
  String get hideSubfolders => 'Alt klasörleri gizle';

  @override
  String unread(Object unreadCount) {
    return '$unreadCount okunmamış';
  }

  @override
  String get syncingAutomatically => 'Otomatik eşitleniyor';

  @override
  String get changeParentFolder => 'Üst klasörü değiştir';

  @override
  String get assignFolderRole => 'Klasör rolü ata';

  @override
  String get revertToAutomatic => 'Otomatiğe döndür';

  @override
  String get syncNow => 'Şimdi eşitle';

  @override
  String get turnOffAutomaticSync => 'Otomatik eşitlemeyi kapat';

  @override
  String get turnOnAutomaticSync => 'Otomatik eşitlemeyi aç';

  @override
  String get folderName => 'Klasör adı';

  @override
  String get save => 'Kaydet';

  @override
  String get anActionTakenWhileOffline =>
      'Çevrimdışıyken yapılan bir işlem uygulanamadı. Son durum sunucudan yüklendi.';

  @override
  String get syncingAccounts => 'Hesaplar eşitleniyor…';

  @override
  String get accountsSynced => 'Hesaplar eşitlendi.';

  @override
  String get syncStatusNotFoundTry =>
      'Eşitleme durumu bulunamadı. Tekrar deneyin.';

  @override
  String get allInboxes => 'Tüm Gelen Kutuları';

  @override
  String emailsDeleted(int count) {
    return '$count e-posta silindi';
  }

  @override
  String draftsDeleted(int length) {
    return '$length taslak silindi';
  }

  @override
  String actionFailed(Object value) {
    return 'İşlem başarısız: $value';
  }

  @override
  String emailsPermanentlyDeleted(int length) {
    return '$length e-posta kalıcı olarak silindi';
  }

  @override
  String emailsArchived(int count) {
    return '$count e-posta arşivlendi';
  }

  @override
  String emailsMovedToSpam(int count) {
    return '$count e-posta spam kutusuna taşındı';
  }

  @override
  String emailsRestored(int count) {
    return '$count e-posta geri yüklendi';
  }

  @override
  String emailsUnarchived(int count) {
    return '$count e-posta arşivden çıkarıldı';
  }

  @override
  String emailsMarkedAsNotSpam(int count) {
    return '$count e-posta spam olmaktan çıkarıldı';
  }

  @override
  String get theseEmailsAreAlreadyBeing => 'Bu e-postalar zaten işleniyor.';

  @override
  String get undo2 => 'Geri al';

  @override
  String emailsMoved(int length) {
    return '$length e-posta taşındı.';
  }

  @override
  String get newEmail => 'Yeni E-posta';

  @override
  String get search => 'Ara';

  @override
  String get restore => 'Geri Yükle';

  @override
  String get deletePermanently => 'Kalıcı olarak sil';

  @override
  String get markAsRead => 'Okundu olarak işaretle';

  @override
  String get markAsUnread => 'Okunmadı olarak işaretle';

  @override
  String get archive2 => 'Arşivle';

  @override
  String get unarchive => 'Arşivden çıkar';

  @override
  String get removeStar => 'Yıldızı kaldır';

  @override
  String get star => 'Yıldızla';

  @override
  String get unpin => 'Sabitlemeyi kaldır';

  @override
  String get pin => 'Sabitle';

  @override
  String get removeSnooze => 'Ertelemeyi kaldır';

  @override
  String get snooze => 'Ertele';

  @override
  String get moveToSpam => 'Spam kutusuna gönder';

  @override
  String get notSpam => 'Spam değil';

  @override
  String get removeLabel => 'Etiketi kaldır';

  @override
  String get label => 'Etiketle';

  @override
  String get move => 'Taşı';

  @override
  String get selectAll => 'Tümünü seç';

  @override
  String get cancelSelection => 'Seçimi iptal et';

  @override
  String get n1Selected => '1 seçili';

  @override
  String selected(Object count) {
    return '$count seçili';
  }

  @override
  String get selectAnEmailToView => 'Görüntülemek için bir e-posta seçin';

  @override
  String get noConnectionShowingTheLatest =>
      'Bağlantı yok. Önbellekteki son postalar gösteriliyor.';

  @override
  String get restore2 => 'Geri yükle';

  @override
  String get readUnread => 'Okundu / okunmadı';

  @override
  String get star2 => 'Yıldız';

  @override
  String get justNow => 'az önce';

  @override
  String minutesAgo(int inMinutes) {
    return '$inMinutes dakika önce';
  }

  @override
  String hoursAgo(int inHours) {
    return '$inHours saat önce';
  }

  @override
  String daysAgo(int inDays) {
    return '$inDays gün önce';
  }

  @override
  String get tryLoadingMoreAgain => 'Daha fazlasını tekrar yükle';

  @override
  String get noMailMatchesThisFilter => 'Bu filtreyle eşleşen posta yok';

  @override
  String get clearFilter => 'Filtreyi temizle';

  @override
  String get newEmailsWillAppearHere =>
      'Yeni e-postalar geldiğinde burada görünür.';

  @override
  String get emailsFromYourConnectedAccounts =>
      'Bağlı hesaplarınızdaki e-postalar burada görünür.';

  @override
  String get emailsYouSendAppearHere =>
      'Gönderdiğiniz e-postalar burada görünür.';

  @override
  String get emailsYouStarAppearHere =>
      'Yıldızladığınız e-postalar burada görünür.';

  @override
  String get emailsYouSnoozeAppearHere =>
      'Ertelediğiniz e-postalar burada görünür.';

  @override
  String get draftsYouSaveAreKept => 'Kaydettiğiniz taslaklar burada durur.';

  @override
  String get emailsYouDeleteAreKept => 'Sildiğiniz e-postalar burada durur.';

  @override
  String get unwantedEmailsEndUpHere => 'İstenmeyen e-postalar buraya düşer.';

  @override
  String get emailsYouArchiveAreKept =>
      'Arşivlediğiniz e-postalar burada durur.';

  @override
  String get offline => 'Çevrimdışı';

  @override
  String isEmpty(Object label) {
    return '$label boş';
  }

  @override
  String get noInternetConnectionNewMail =>
      'İnternet bağlantısı yok. Bağlantı sağlanınca yeni postalar görünür.';

  @override
  String get refresh => 'Yenile';

  @override
  String get youreOffline => 'Çevrimdışısınız';

  @override
  String get yourEmailsCouldntBeLoaded => 'E-postalarınız yüklenemedi';

  @override
  String get noInternetConnectionItWill =>
      'İnternet bağlantısı yok. Bağlantı sağlanınca otomatik güncellenir.';

  @override
  String get accountReconnected => 'Hesap yeniden bağlandı.';

  @override
  String get signInFailedTryAgain => 'Giriş başarısız. Tekrar deneyin.';

  @override
  String get serverAddress => 'Sunucu adresi';

  @override
  String get aSecureAppForYour => 'E-postalarınız için güvenli bir uygulama';

  @override
  String get continueLabel => 'Devam';

  @override
  String get back => 'Geri';

  @override
  String get youAreReconnectingThisAccount => 'Şu hesabı yeniden bağlıyorsunuz';

  @override
  String get youAreSigningInWith => 'Şu hesapla oturum açıyorsunuz';

  @override
  String get reconnect => 'Yeniden Bağlan';

  @override
  String get signIn => 'Giriş Yap';

  @override
  String get hideQuote => 'Alıntıyı gizle';

  @override
  String get showQuote => 'Alıntıyı göster';

  @override
  String get showSignature => 'İmzayı göster';

  @override
  String get hideSignature => 'İmzayı gizle';

  @override
  String get remoteImagesWereBlockedIn =>
      'Bu mesajda uzak görseller güvenlik nedeniyle durduruldu.';

  @override
  String get loadImages => 'Görselleri yükle';

  @override
  String get cancelDownload => 'İndirmeyi iptal et';

  @override
  String get ready => 'Hazır';

  @override
  String get downloadAttachment => 'Eki indir';

  @override
  String get sendingReply => 'Yanıt gönderiliyor';

  @override
  String get replySent => 'Yanıt gönderildi';

  @override
  String get emailSent => 'E-posta gönderildi.';

  @override
  String couldntSendTheReply(Object value) {
    return 'Yanıt gönderilemedi: $value';
  }

  @override
  String get writeAQuickReply => 'Hızlı yanıt yaz…';

  @override
  String get sendReply => 'Yanıtı gönder';

  @override
  String get more => 'Daha fazla';

  @override
  String get replyAll => 'Tümünü Yanıtla';

  @override
  String get reply => 'Yanıtla';

  @override
  String get forward => 'İlet';

  @override
  String get print => 'Yazdır';

  @override
  String get shareAsPdf => 'PDF olarak paylaş';

  @override
  String get unsubscribe => 'Abonelikten Çık';

  @override
  String get showAllHeaders => 'Tüm başlıkları göster';

  @override
  String get showRawMime => 'Ham MIME göster';

  @override
  String get thisEmailNoLongerExists => 'Bu e-posta artık mevcut değil.';

  @override
  String get messageActions => 'İleti işlemleri';

  @override
  String get from2 => 'Kimden: ';

  @override
  String get to2 => 'Alıcı: ';

  @override
  String get cc => 'Cc: ';

  @override
  String get bcc => 'Bcc: ';

  @override
  String get date => 'Tarih: ';

  @override
  String signedByNotVerified(Object value) {
    return '$value imzalı (doğrulanmadı)';
  }

  @override
  String encryptedByCantBeOpened(Object value) {
    return '$value şifreli (açılamıyor)';
  }

  @override
  String get trackingContentBlocked => 'Takip içeriği engellendi';

  @override
  String get attachments => 'Ekler';

  @override
  String get replyAll2 => 'Tümünü yanıtla';

  @override
  String get noRecipients => 'alıcı yok';

  @override
  String get youCanPinAtMost => 'En fazla 3 mail sabitlenebilir.';

  @override
  String emailMovedTo(Object label) {
    return 'E-posta $label klasörüne taşındı.';
  }

  @override
  String get emailRestored => 'E-posta geri yüklendi.';

  @override
  String get emailMarkedAsNotSpam => 'E-posta spam değil olarak işaretlendi.';

  @override
  String get emailUnarchived => 'E-posta arşivden çıkarıldı.';

  @override
  String get emailPermanentlyDeleted => 'E-posta kalıcı olarak silindi.';

  @override
  String get unsubscribe2 => 'Abonelikten çıkılsın mı?';

  @override
  String get aRequestWillBeSent =>
      'Bu gönderenden e-posta almayı durdurmak için bir istek gönderilecek. Bu işlem geri alınamaz.';

  @override
  String get unsubscribeStarted => 'Abonelikten çıkma işlemi açıldı.';

  @override
  String get unsubscribingFailed => 'Abonelikten çıkma işlemi başarısız oldu.';

  @override
  String printingFailed(Object value) {
    return 'Yazdırma başarısız: $value';
  }

  @override
  String sharingThePdfFailed(Object value) {
    return 'PDF paylaşma başarısız: $value';
  }

  @override
  String couldntPrepareTheReply(Object value) {
    return 'Yanıt hazırlanamadı: $value';
  }

  @override
  String forwardedMessageFromSubject(
    Object sender,
    Object dateLine,
    Object subject,
    Object bodyText,
  ) {
    return '\n\n--- İletilen mesaj ---\nKimden: $sender\n${dateLine}Konu: $subject\n\n$bodyText';
  }

  @override
  String forwardedMessageFromSubject2(
    Object value,
    Object value2,
    Object value3,
    Object originalHtml,
  ) {
    return '<p><br></p><p>--- İletilen mesaj ---<br><strong>Kimden:</strong> $value<br>$value2<strong>Konu:</strong> $value3</p>$originalHtml';
  }

  @override
  String get allHeaders => 'Tüm başlıklar';

  @override
  String get rawMime => 'Ham MIME';

  @override
  String get signatureVerification => 'İmza doğrulaması';

  @override
  String couldntGetTheMessageSource(Object value) {
    return 'İleti kaynağı alınamadı: $value';
  }

  @override
  String get signatureAndCertificateChainVerified =>
      'İmza ve sertifika zinciri doğrulandı';

  @override
  String get signatureMatchesCertificateIsntTrusted =>
      'İmza eşleşiyor; sertifika güvenilir değil';

  @override
  String get signatureIsInvalid => 'İmza geçersiz';

  @override
  String get signatureCouldntBeVerified => 'İmza doğrulanamadı';

  @override
  String get openpgpKeyManagementAndVerification =>
      'OpenPGP anahtar yönetimi ve doğrulaması desteklenmiyor.';

  @override
  String get unknownSigner => 'Bilinmeyen imzacı';

  @override
  String signatureDate(Object value) {
    return 'İmza tarihi: $value';
  }

  @override
  String certificateExpires(Object value) {
    return 'Sertifika bitişi: $value';
  }

  @override
  String get accountNotifications => 'Hesap bildirimleri';

  @override
  String get theseSettingsApplyOnEvery =>
      'Bu ayarlar hesabın oturum açık olduğu tüm cihazlarda geçerlidir. Bu cihazdaki bildirimleri Ayarlar > Genel ayarlar > Bildirimler ile kapatabilirsiniz.';

  @override
  String get notifications => 'Bildirimler';

  @override
  String get inboxOnly => 'Yalnızca Gelen Kutusu';

  @override
  String get whenOffSyncedFoldersOther =>
      'Kapalıyken Gönderilmiş, Taslaklar, Çöp ve Spam dışındaki senkronize klasörler de bildirilir.';

  @override
  String get lockScreenPrivacy => 'Kilit ekranı gizliliği';

  @override
  String get notificationsAreSentAsPrivate =>
      'Sunucu önizlemeleri kapattığı için bildirimler Gizli olarak gönderilir.';

  @override
  String get editMessage => 'Gönderiyi Düzenle';

  @override
  String get newMessage => 'Yeni Gönderi';

  @override
  String get createANewMessage => 'Yeni gönderi oluştur?';

  @override
  String get checkSentFirstThisMessage =>
      'Önce Gönderilenler’i kontrol edin. Bu mesaj daha önce teslim edilmiş olabilir; yeniden göndermek alıcıya ikinci bir kopya ulaştırabilir.';

  @override
  String get newMessage2 => 'Yeni gönderi';

  @override
  String get deleteMessage => 'Gönderiyi sil?';

  @override
  String get theDeliveryResultIsUnknown =>
      'Gönderim sonucu bilinmiyor. Önce Gönderilenler’i kontrol edin. Yerel kopya silinsin mi?';

  @override
  String get theLocalCopyOfThis =>
      'Bu gönderinin yerel kopyası kalıcı olarak silinecek.';

  @override
  String get noPendingMessages => 'Bekleyen gönderi yok.';

  @override
  String get undoPeriod => 'Geri alma süresi';

  @override
  String get sending => 'Gönderiliyor';

  @override
  String get waitingForConnection => 'Bağlantı bekleniyor';

  @override
  String get couldntSend => 'Gönderilemedi';

  @override
  String get resultUnknown => 'Sonuç belirsiz';

  @override
  String to3(Object value) {
    return 'Kime: $value';
  }

  @override
  String get noInternetConnectionItWillBeSentAutomatically =>
      'İnternet bağlantısı yok. Bağlantı gelince otomatik gönderilecek.';

  @override
  String get checkSentBeforeSendingAgain =>
      'Tekrar göndermeden önce Gönderilenler’i kontrol edin.';

  @override
  String get tryNow => 'Şimdi dene';

  @override
  String get edit => 'Düzenle';

  @override
  String get recreateManually => 'Elle yeniden oluştur';

  @override
  String get viewContent => 'İçeriği görüntüle';

  @override
  String get scheduledSends => 'Zamanlanmış Gönderimler';

  @override
  String get scheduled => 'Zamanlandı';

  @override
  String get sent2 => 'Gönderildi';

  @override
  String get cancelled => 'İptal edildi';

  @override
  String get resultUnknownCheckSent =>
      'Sonuç belirsiz — Gönderilenler’i kontrol edin';

  @override
  String get cancelScheduledSend => 'Zamanlanmış gönderimi iptal et';

  @override
  String cancelTheSendOf(Object value) {
    return '\"$value\" gönderimi iptal edilsin mi?';
  }

  @override
  String get cancelSend => 'İptal Et';

  @override
  String get sendCancelled => 'Gönderim iptal edildi.';

  @override
  String get chooseAtLeastOneRecipient =>
      'En az bir alıcı ve ileri bir tarih seçin.';

  @override
  String get scheduledSendUpdated => 'Zamanlanmış gönderim güncellendi.';

  @override
  String get sendReQueued => 'Gönderim yeniden kuyruğa alındı.';

  @override
  String get failedSend => 'Başarısız gönderim';

  @override
  String get editScheduledSend => 'Zamanlanmışı düzenle';

  @override
  String get sendFailed => 'Gönderim başarısız';

  @override
  String get recipients => 'Alıcılar';

  @override
  String get content => 'İçerik';

  @override
  String get body => 'Gövde';

  @override
  String get sendTime => 'Gönderim zamanı';

  @override
  String get addAttachment => 'Ek ekle';

  @override
  String get retry => 'Yeniden dene';

  @override
  String get cancelSend2 => 'Gönderimi iptal et';

  @override
  String get noScheduledSends => 'Zamanlanmış gönderim yok';

  @override
  String get scheduleASendWithThe =>
      'E-posta yazarken sağ üstteki menüden \"Zamanla\" seçeneğini kullanın. Zamanlanan iletiler burada görünür.';

  @override
  String newEmailsAdded(int imported) {
    return 'Sunucu taraması tamamlandı. $imported yeni e-posta eklendi.';
  }

  @override
  String scanningTheServer(int imported, Object remaining) {
    return 'Sunucu taranıyor… $imported yeni e-posta eklendi; $remaining eşleşme kaldı.';
  }

  @override
  String serverScanStopped(int imported, Object remaining) {
    return 'Sunucu taraması durdu. $imported yeni e-posta eklendi; $remaining eşleşme alınamadı. Yeniden deneyin.';
  }

  @override
  String get searchEmail => 'E-posta ara';

  @override
  String get clear => 'Temizle';

  @override
  String get filters => 'Filtreler';

  @override
  String get searchingTheServer => 'Sunucuda aranıyor…';

  @override
  String get startTypingToSearch => 'Aramak için yazmaya başlayın.';

  @override
  String get noResultsMatchTheSelected =>
      'Seçili filtrelerle eşleşen sonuç yok.';

  @override
  String noResultsFor(Object value) {
    return '“$value” için sonuç yok.';
  }

  @override
  String get theMailboxIsStillSyncing =>
      'Posta kutusu hâlâ senkronize ediliyor. Arama sonuçları eksik olabilir.';

  @override
  String folder2(Object label) {
    return 'Klasör: $label';
  }

  @override
  String folder3(Object name) {
    return 'Klasör: $name';
  }

  @override
  String from3(Object value) {
    return 'Başlangıç: $value';
  }

  @override
  String to4(Object value) {
    return 'Bitiş: $value';
  }

  @override
  String get read => 'Okundu';

  @override
  String get unread2 => 'Okunmadı';

  @override
  String get starred2 => 'Yıldızlı';

  @override
  String get clearFilters => 'Filtreleri Temizle';

  @override
  String get advancedFilters => 'Gelişmiş Filtreler';

  @override
  String get account => 'Hesap';

  @override
  String get allAccounts => 'Tüm hesaplar';

  @override
  String get all => 'Tümü';

  @override
  String get eGNameCompanyCom => 'ör. ad@sirket.com';

  @override
  String get dateRange => 'Tarih Aralığı';

  @override
  String get start => 'Başlangıç';

  @override
  String get end => 'Bitiş';

  @override
  String get status => 'Durum';

  @override
  String get any => 'Herhangi';

  @override
  String get hasAttachment => 'Ek var';

  @override
  String get apply => 'Uygula';

  @override
  String get filtersAreCombinedWithAnd => 'Filtreler VE ile birleştirilir.';

  @override
  String get startTypingToSearchOr =>
      'Aramak veya filtrelemek için yazmaya başlayın';

  @override
  String get searchingTheServerAcrossAll => 'Tüm hesaplarda sunucuda aranıyor';

  @override
  String searchingIn(Object accountEmail) {
    return '$accountEmail hesabında aranıyor';
  }

  @override
  String get accountSettings => 'Hesap ayarları';

  @override
  String get theAccountIsNoLonger => 'Hesap artık bağlı değil.';

  @override
  String get signatures => 'İmzalar';

  @override
  String get createEmailSignaturesAndChoose =>
      'E-posta imzalarını oluştur ve varsayılanını seç';

  @override
  String get savedTexts2 => 'Hazır metinler';

  @override
  String get reusableSubjectsAndTexts => 'Tekrar kullanılan konu ve metinler';

  @override
  String get labels => 'Etiketler';

  @override
  String get createEditAndDeleteLabels => 'Etiket oluştur, düzenle, sil';

  @override
  String get contacts => 'Kişiler';

  @override
  String get contactsSuggestedWhileTyping => 'Yazarken önerilecek kişiler';

  @override
  String get folderTreeRolesAndSync => 'Klasör ağacı, roller ve eşitleme';

  @override
  String get syncLabel => 'Eşitleme';

  @override
  String get perFolderStatusAndFolders =>
      'Klasör bazlı durum ve eşitlenecek klasörler';

  @override
  String get folderScopeAndLockScreen =>
      'Klasör kapsamı ve kilit ekranı gizliliği';

  @override
  String get savedImagePreferences => 'Kayıtlı görsel tercihleri';

  @override
  String get trustedSendersAndDomains => 'Güvenilir gönderici ve alan adları';

  @override
  String get security => 'Güvenlik';

  @override
  String get connectedDevices => 'Bağlı cihazlar';

  @override
  String get devicesAndSessionsSignedIn =>
      'Bu hesaba giriş yapmış cihazlar ve oturumlar';

  @override
  String get disconnected => 'Bağlantısı kesildi';

  @override
  String get connectionProblem => 'Bağlantı sorunu';

  @override
  String get disabled => 'Devre dışı';

  @override
  String get updatePassword => 'Şifreyi güncelle';

  @override
  String get signOutOnThisDevice => 'Bu cihazdan çıkış yap';

  @override
  String get theAccountStaysOnThe =>
      'Hesap sunucuda kalır; yalnızca bu cihazdaki oturum ve veriler silinir.';

  @override
  String get signOut => 'Çıkış yapılsın mı?';

  @override
  String willBeSignedOutOn(Object email) {
    return '$email bu cihazdan çıkarılacak. Sunucudaki hesap ve e-postalar silinmez.';
  }

  @override
  String get signOut2 => 'Çıkış yap';

  @override
  String get removeAccount => 'Hesabı kaldır';

  @override
  String get deletesTheConnectionFromThe =>
      'Bağlantıyı sunucudan siler; e-postalar bu uygulamadan kaldırılır.';

  @override
  String get removeAccount2 => 'Hesap kaldırılsın mı?';

  @override
  String willBeRemovedAndIts(Object email) {
    return '$email kaldırılacak ve bu hesaba ait e-postalar uygulamadan silinecek. Emin misiniz?';
  }

  @override
  String get storage => 'Depolama';

  @override
  String ofUsed(Object value, Object value2, Object usedPercent) {
    return '$value / $value2 kullanılıyor (%$usedPercent)';
  }

  @override
  String get storageUsage => 'Depolama kullanımı';

  @override
  String get noContactsAddedYet => 'Henüz kişi eklenmedi.';

  @override
  String get newContact => 'Yeni Kişi';

  @override
  String get deleteContact => 'Kişiyi sil?';

  @override
  String willBeRemovedFromThe(Object value) {
    return '“$value” kişi listesinden kaldırılacak.';
  }

  @override
  String get yesDelete => 'Evet, sil';

  @override
  String get editContact => 'Kişiyi Düzenle';

  @override
  String get nameOptional => 'Ad (isteğe bağlı)';

  @override
  String get contactsPermissionWasntGrantedSuggestions =>
      'Kişilere erişim izni verilmedi. Öneriler mail geçmişinden ve eklediğiniz kişilerden gelmeye devam eder.';

  @override
  String get suggestDeviceContacts => 'Cihaz kişilerini öner';

  @override
  String get alsoSuggestsEmailAddressesFrom =>
      'Alıcı yazarken telefon rehberindeki e-posta adreslerini de önerir. Rehber yalnızca bu cihazda okunur, sunucuya gönderilmez.';

  @override
  String get showNewEmailNotificationsOn =>
      'Bu cihazda yeni e-posta bildirimlerini göster. Klasör kapsamı ve kilit ekranı gizliliği her hesabın kendi ayarlarındadır.';

  @override
  String get followsTheDeviceTheme => 'Cihazın temasını izler';

  @override
  String get light => 'Açık';

  @override
  String get dark => 'Koyu';

  @override
  String get swipeGestures => 'Kaydırma hareketleri';

  @override
  String get swipeAnEmailRightOr =>
      'Listede e-postayı sağa veya sola kaydırarak aşağıdaki işlemleri yapın. Çöp, Spam ve Arşiv klasörleri kendi işlemlerini kullanır.';

  @override
  String get onSwipeRight => 'Sağa kaydırınca';

  @override
  String get onSwipeLeft => 'Sola kaydırınca';

  @override
  String get undoSendPeriod => 'Göndermeyi geri alma süresi';

  @override
  String get blue => 'Mavi';

  @override
  String get green => 'Yeşil';

  @override
  String get orange => 'Turuncu';

  @override
  String get darkRed => 'Koyu kırmızı';

  @override
  String get red => 'Kırmızı';

  @override
  String get turquoise => 'Turkuaz';

  @override
  String get purple => 'Menekşe';

  @override
  String get redOrange => 'Kırmızı-turuncu';

  @override
  String get newLabel => 'Yeni Etiket';

  @override
  String customColor(Object value) {
    return 'Özel renk $value';
  }

  @override
  String get chooseCustomColor => 'Özel renk seç';

  @override
  String get deleteLabel => 'Etiketi sil?';

  @override
  String theLabelWillBeRemoved(Object value) {
    return '“$value” etiketi kaldırılacak. E-postalar silinmez, yalnızca bu etiket onlardan çıkarılır.';
  }

  @override
  String get editLabel => 'Etiketi Düzenle';

  @override
  String get name => 'Ad';

  @override
  String get create => 'Oluştur';

  @override
  String get apiConnection => 'API bağlantısı';

  @override
  String get checkingConnection => 'Bağlantı kontrol ediliyor…';

  @override
  String get serverAndServicesAreReady => 'Sunucu ve servisler hazır';

  @override
  String get couldntConnect => 'Bağlantı kurulamadı';

  @override
  String get checkConnectionAgain => 'Bağlantıyı yeniden kontrol et';

  @override
  String get sync => 'Senkronizasyon';

  @override
  String get serverConnection => 'Sunucu bağlantısı';

  @override
  String get thisSettingOnlyControlsHow =>
      'Bu ayar yalnızca uygulama açıkken görünen listeyi ne sıklıkla yenileyeceğinizi belirler. Sunucu, bu ayardan bağımsız olarak e-postalarınızı düzenli aralıklarla arka planda zaten senkronize eder; yeni posta bildirimleri bu ayarı beklemez.';

  @override
  String get autoRefreshNetwork => 'Otomatik yenileme ağı';

  @override
  String get pauseOnBatterySaver => 'Pil tasarrufunda duraklat';

  @override
  String get whenBatterySaverIsOn =>
      'Pil tasarrufu açıkken otomatik yenileme yapılmaz; aşağı çekerek yenileme ve bildirimler çalışmaya devam eder.';

  @override
  String get clearAttachmentCache => 'Ek önbelleğini temizle?';

  @override
  String downloadedAttachmentsTakingUpWill(Object _sizeLabel) {
    return '$_sizeLabel boyutundaki indirilen ekler silinecek.';
  }

  @override
  String get attachmentCacheCleared => 'Ek önbelleği temizlendi.';

  @override
  String get attachmentsAreDownloadedAutomaticallyOnly =>
      'Ekler yalnızca posta açıldığında, seçilen ağda ve boyut sınırının altındaysa otomatik indirilir.';

  @override
  String autoDownloadLimit(Object label) {
    return 'Otomatik indirme sınırı: $label';
  }

  @override
  String get clearAttachmentCache2 => 'Ek önbelleğini temizle';

  @override
  String get calculatingSize => 'Boyut hesaplanıyor…';

  @override
  String get removeLinkTrackingParameters =>
      'Bağlantı takip parametrelerini temizle';

  @override
  String get removesKnownAdvertisingAndCampaign =>
      'E-postalardaki bağlantıları açmadan önce bilinen reklam ve kampanya takip parametrelerini kaldırır.';

  @override
  String get appLock => 'Uygulama Kilidi';

  @override
  String get asksForFingerprintFaceId =>
      'Uygulamayı açtığınızda ya da seçilen süreden uzun arka planda kaldıktan sonra parmak izi/Face ID veya cihaz şifresi ister.';

  @override
  String get lockWhenReturningFromBackground => 'Arka plandan dönünce kilitle';

  @override
  String get screenProtection => 'Ekran Koruması';

  @override
  String get hidesMailContentInThe =>
      'Uygulama geçiş ekranında posta içeriğini gizler.';

  @override
  String get blocksScreenshotsAndScreenRecording =>
      'Ekran görüntüsü ve ekran kaydını engeller, son kullanılan uygulamalar listesinde içeriği gizler.';

  @override
  String couldntLoadDevices(Object value) {
    return 'Cihazlar yüklenemedi: $value';
  }

  @override
  String get signOutOfThisSession => 'Oturumu kapat?';

  @override
  String get theSessionOnThisDevice =>
      'Bu cihazdaki oturum kapatılacak ve bu hesaptan çıkış yapılacak.';

  @override
  String get thisDeviceWillNoLonger => 'Bu cihaz artık bu hesaba erişemeyecek.';

  @override
  String couldntSignOut(Object value) {
    return 'Oturum kapatılamadı: $value';
  }

  @override
  String get noConnectedDevices => 'Bağlı cihaz yok.';

  @override
  String lastUsed(Object value) {
    return 'Son kullanım: $value';
  }

  @override
  String get settings => 'Ayarlar';

  @override
  String get generalSettings => 'Genel ayarlar';

  @override
  String get appearanceInteractionNotificationsNetworkAnd =>
      'Görüntü, etkileşim, bildirimler, ağ ve gizlilik';

  @override
  String get accounts => 'Hesaplar';

  @override
  String get addAccount => 'Hesap ekle';

  @override
  String get connectANewMailAccount => 'Yeni posta hesabı bağla';

  @override
  String get signatureLabelContactFolderAnd =>
      'İmza, etiket, kişi, klasör ve bildirim ayarları';

  @override
  String get disconnectedUpdateThePassword =>
      'Bağlantısı kesildi — şifreyi güncelleyin';

  @override
  String get appearance => 'Görüntü';

  @override
  String get lightDarkOrSystemTheme => 'Açık, koyu veya sistem teması';

  @override
  String get language => 'Dil';

  @override
  String get tRkEOrEnglish => 'Türkçe veya English';

  @override
  String get interaction => 'Etkileşim';

  @override
  String get swipeUndoSendAndDevice =>
      'Kaydırma, göndermeyi geri alma ve cihaz kişileri';

  @override
  String get newEmailNotificationsOnThis =>
      'Bu cihazda yeni e-posta bildirimleri';

  @override
  String get network => 'Ağ';

  @override
  String get refreshAttachmentsAndServer => 'Yenileme, ekler ve sunucu';

  @override
  String get privacy => 'Gizlilik';

  @override
  String get appLockScreenProtectionAnd =>
      'Uygulama kilidi, ekran koruması ve bağlantılar';

  @override
  String get deleteSignature => 'İmzayı sil?';

  @override
  String theSignatureWillBePermanently(Object name) {
    return '“$name” imzası kalıcı olarak silinecek.';
  }

  @override
  String get none => 'Yok';

  @override
  String get noConnectedAccountFound => 'Bağlı hesap bulunamadı.';

  @override
  String get newSignature => 'Yeni imza';

  @override
  String get newEmail2 => 'Yeni e-posta';

  @override
  String get reply2 => 'Yanıt';

  @override
  String get noSignaturesYet => 'Henüz imza yok';

  @override
  String get signatureNameMustBe1 => 'İmza adı 1-100 karakter olmalı.';

  @override
  String get enterTheSignatureText => 'İmza metni yazın.';

  @override
  String get editSignature => 'İmzayı düzenle';

  @override
  String get signatureText => 'İmza metni';

  @override
  String get syncScopeSaved => 'Senkronizasyon kapsamı kaydedildi.';

  @override
  String get syncScope => 'Senkronizasyon kapsamı';

  @override
  String get chooseTheFoldersToUpdate =>
      'Arka planda güncellenecek klasörleri seçin. Diğer klasörler açıldığında yine yenilenir.';

  @override
  String get chooseAtLeastOneFolder => 'En az bir klasör seçin.';

  @override
  String foldersSyncedInTheBackground(Object value) {
    return 'Arka planda senkronize edilen klasörler: $value';
  }

  @override
  String get syncStatus => 'Senkronizasyon Durumu';

  @override
  String get noConnectedAccounts => 'Bağlı hesap yok.';

  @override
  String get noSyncAttemptsYet => 'Henüz senkronizasyon denemesi yok.';

  @override
  String actionsAreWaitingForA(int queued) {
    return '$queued işlem bağlantı bekliyor';
  }

  @override
  String get temporaryProblem => 'Geçici sorun';

  @override
  String get authenticationProblem => 'Kimlik doğrulama sorunu';

  @override
  String get configurationProblem => 'Yapılandırma sorunu';

  @override
  String get permanentProblem => 'Kalıcı sorun';

  @override
  String get unknownProblem => 'Bilinmeyen sorun';

  @override
  String get olderMailIsStillBeing => 'Geçmiş mailler hâlâ içeri aktarılıyor';

  @override
  String get noSuccessfulSyncYet => 'Henüz başarılı senkronizasyon yok';

  @override
  String get deleteSavedText => 'Hazır metni sil?';

  @override
  String theSavedTextWillBe(Object name) {
    return '“$name” hazır metni kalıcı olarak silinecek.';
  }

  @override
  String get noSavedTextsYet => 'Henüz hazır metin yok';

  @override
  String get noSubject => 'Konu yok';

  @override
  String get newSavedText => 'Yeni hazır metin';

  @override
  String get savedTextNameMustBe => 'Hazır metin adı 1-100 karakter olmalı.';

  @override
  String get subjectMustBeASingle =>
      'Konu tek satır ve en fazla 500 karakter olmalı.';

  @override
  String get enterTheSavedTextBody => 'Hazır metin gövdesini yazın.';

  @override
  String get editSavedText => 'Hazır metni düzenle';

  @override
  String get textBody => 'Metin gövdesi';

  @override
  String get savedImagePreferences2 => 'Kayıtlı Görsel Tercihleri';

  @override
  String get noSavedSendersYetRegular =>
      'Henüz kayıtlı gönderici yok.\nNormal görseller, bu listeye ekleme yapılmadan da yüklenir.';

  @override
  String get domain => 'Alan adı';

  @override
  String get sender => 'Gönderici';

  @override
  String get theServerDidntRespondPlease =>
      'Sunucu yanıt vermedi. Lütfen tekrar deneyin.';

  @override
  String get checkYourInternetConnection =>
      'İnternet bağlantınızı kontrol edin.';

  @override
  String get wrongPassword => 'Şifre yanlış.';

  @override
  String get yourSessionExpiredPleaseSign =>
      'Oturum süresi doldu. Lütfen yeniden giriş yapın.';

  @override
  String get accessHasntBeenEnabledFor =>
      'Bu e-posta adresi için erişim henüz açılmadı.';

  @override
  String get thisMailAccountHasBeen => 'Bu posta hesabı devre dışı bırakıldı.';

  @override
  String get thisAccountIsAlreadyConnected => 'Bu hesap zaten bağlı.';

  @override
  String get aTemplateWithThisName => 'Bu adla bir şablon zaten var.';

  @override
  String get noRegisteredAccountFoundFor =>
      'Bu e-posta için kayıtlı hesap bulunamadı.';

  @override
  String get automaticServerDiscoveryFailed =>
      'Otomatik sunucu keşfi başarısız oldu.';

  @override
  String get serverDiscoveryTimedOutTry =>
      'Sunucu keşfinin süresi doldu. Tekrar deneyin.';

  @override
  String get theServerSettingsArentSecure => 'Sunucu ayarları güvenli değil.';

  @override
  String get couldntReachTheMailServer =>
      'Posta sunucusuna ulaşılamadı. Tekrar deneyin.';

  @override
  String get emailNotFound => 'E-posta bulunamadı.';

  @override
  String get thisDraftIsNoLonger => 'Bu taslak artık geçerli değil.';

  @override
  String get theMailFolderIsUnavailable => 'Posta klasörü kullanılamıyor.';

  @override
  String get thisActionIsntSupportedFor =>
      'Bu işlem bu e-posta için desteklenmiyor.';

  @override
  String get theMailboxChangedRefreshAnd =>
      'Posta kutusu değişti. Yenileyip tekrar deneyin.';

  @override
  String get couldntMoveTheEmailTry => 'E-posta taşınamadı. Tekrar deneyin.';

  @override
  String get couldntPermanentlyDeleteTheEmail =>
      'E-posta kalıcı olarak silinemedi. Tekrar deneyin.';

  @override
  String get theActionCouldntBeCompleted =>
      'İşlem tamamlanamadı. Tekrar deneyin.';

  @override
  String get youCanPinAtMost3EmailsPer =>
      'Bir hesapta en fazla 3 e-posta sabitlenebilir.';

  @override
  String get theDraftHasntMatchedOn =>
      'Taslak sunucuda henüz eşleşmedi. Birkaç saniye sonra tekrar deneyin.';

  @override
  String get theSendResultIsUnknown =>
      'Gönderim sonucu belirsiz. Gönderilenler’i kontrol edin.';

  @override
  String get theMessageIsBeingSent =>
      'Gönderim sürüyor. Kısa süre sonra tekrar deneyin.';

  @override
  String get theSendRequestIsInvalid =>
      'Gönderim isteği geçersiz. Yeniden deneyin.';

  @override
  String get theSendRequestWasUsed =>
      'Gönderim isteği farklı içerikle daha önce kullanıldı. Yeni gönderim oluşturun.';

  @override
  String get theRecipientAddressIsInvalid => 'Alıcı adresi geçersiz.';

  @override
  String get invalidEmailAddress => 'Geçersiz e-posta adresi.';

  @override
  String get theEmailHeadersAreInvalid => 'E-posta başlıkları geçersiz.';

  @override
  String get theEmailCouldntBeCreated => 'E-posta oluşturulamadı.';

  @override
  String get theServerSettingsAreInvalid => 'Sunucu ayarları geçersiz.';

  @override
  String get thisSignInMethodIsnt => 'Bu giriş yöntemi sunucuda ayarlı değil.';

  @override
  String get theRedirectAddressIsInvalid => 'Yönlendirme adresi geçersiz.';

  @override
  String get sessionVerificationIsInvalidTry =>
      'Oturum doğrulaması geçersiz. Tekrar deneyin.';

  @override
  String get theProviderRejectedTheSign => 'Sağlayıcı girişi reddetti.';

  @override
  String get theServerIsBusyTry => 'Sunucu meşgul. Birazdan tekrar deneyin.';

  @override
  String get couldntDeleteTheDraftTry => 'Taslak silinemedi. Tekrar deneyin.';

  @override
  String get aSendCantBeScheduled => 'Geçmiş bir zamana gönderim zamanlanamaz.';

  @override
  String get thisSendIsNoLonger =>
      'Bu gönderim artık beklemede değil. Listeyi yenileyin.';

  @override
  String get theSendWasChangedOn =>
      'Gönderim başka bir cihazda değiştirildi. Yenileyip tekrar deneyin.';

  @override
  String get thisSendCanNoLonger =>
      'Bu gönderim artık düzenlenemez. Gönderilenler’i kontrol edin.';

  @override
  String get scheduledSendNotFoundRefresh =>
      'Zamanlanmış gönderim bulunamadı. Listeyi yenileyin.';

  @override
  String get theHeldAttachmentWasntFound =>
      'Bekletilen ek bulunamadı. Listeyi yenileyin.';

  @override
  String get theSelectedIdentityWasntFound => 'Seçilen kimlik bulunamadı.';

  @override
  String get theSelectedSignatureWasntFound => 'Seçilen imza bulunamadı.';

  @override
  String get thisAddressIsAlreadyRegistered =>
      'Bu adres zaten bir kimlik olarak kayıtlı.';

  @override
  String get thisIdentityIsUsedIn =>
      'Bu kimlik zamanlanmış bir gönderimde kullanılıyor.';

  @override
  String get theSessionIsAlreadyClosed => 'Oturum zaten kapatılmış.';

  @override
  String get theEmailBodyCantBe => 'E-posta gövdesi boş olamaz.';

  @override
  String get theEmailBodyIsToo => 'E-posta gövdesi çok büyük.';

  @override
  String get attachmentLimitExceeded => 'Ek dosya sınırı aşıldı.';

  @override
  String get aFolderWithThisName => 'Bu adda bir klasör zaten var.';

  @override
  String get theFolderIsntEmptyMove =>
      'Klasör boş değil. Önce içindeki postaları taşıyın veya silin.';

  @override
  String get deleteTheSubfoldersFirst => 'Önce alt klasörleri silin.';

  @override
  String get thisFolderCantBeChanged => 'Bu klasör değiştirilemez.';

  @override
  String get theFolderNameIsInvalid => 'Klasör adı geçersiz.';

  @override
  String get theMailServerDidntAccept =>
      'Posta sunucusu bu klasör adını kabul etmedi.';

  @override
  String get theFolderWasRemovedFrom => 'Klasör sunucudan kaldırılmış.';

  @override
  String get theSyncQueueIsFull =>
      'Eşitleme kuyruğu dolu. Birazdan tekrar deneyin.';

  @override
  String get syncWasPostponedTryAgain =>
      'Eşitleme ertelendi. Birazdan tekrar deneyin.';

  @override
  String get syncWasInterruptedTryAgain =>
      'Eşitleme yarıda kesildi. Tekrar deneyin.';

  @override
  String get syncCouldntBeCompletedTry =>
      'Eşitleme tamamlanamadı. Tekrar deneyin.';

  @override
  String get theAccountNeedsToBe => 'Hesap yeniden bağlanmayı istiyor.';

  @override
  String get thisSignInMethodIsntSupported =>
      'Bu giriş yöntemi desteklenmiyor.';

  @override
  String get theSmtpPasswordWasRejected => 'SMTP şifresi reddedildi.';

  @override
  String get thisSignInIsntSupported => 'Bu giriş şu an desteklenmiyor.';

  @override
  String get anUnexpectedErrorOccurred => 'Beklenmeyen bir hata oluştu.';

  @override
  String get theRequestCouldntBeCompleted => 'İstek tamamlanamadı.';

  @override
  String get attachmentNotFound => 'Ek bulunamadı.';

  @override
  String get theAttachmentCouldntBeDownloaded =>
      'Ek indirilemedi. Tekrar deneyin.';

  @override
  String get snoozedEmailIsBack => 'Ertelenen e-posta geri döndü';

  @override
  String get aSnoozedMessageHasReturned =>
      'Ertelenen bir iletiniz gelen kutusuna döndü.';

  @override
  String couldntDoTryAgain(Object label) {
    return '\"$label\" yapılamadı, tekrar deneyin.';
  }

  @override
  String get theServerAddressCantBe => 'Sunucu adresi boş olamaz.';

  @override
  String get enterAValidHttpHttps => 'Geçerli bir http/https adresi girin.';

  @override
  String get off => 'Kapalı';

  @override
  String get wiFiOnly => 'Yalnız Wi-Fi';

  @override
  String get starRemoveStar => 'Yıldızla / yıldızı kaldır';

  @override
  String get manual => 'Manuel';

  @override
  String get immediately => 'Hemen';

  @override
  String uploadingAttachment(Object percent) {
    return 'Ek yükleniyor: $percent%';
  }

  @override
  String get theMessageMayHaveBeen =>
      'Mesaj gönderilmiş olabilir. Giden Kutusu ve Gönderilenler’i kontrol edin.';

  @override
  String get couldntSendTheMessageWas =>
      'Gönderilemedi. Mesaj Giden Kutusu’nda saklandı.';

  @override
  String get theMessageMayHaveBeenSentCheckSent =>
      'Mesaj gönderilmiş olabilir. Gönderilenler’i kontrol edin.';

  @override
  String youCanPinAtMostEmailsPerAccount(
    Object maxPinnedMails,
    Object pinned,
    Object adding,
    Object value,
  ) {
    return 'Bir hesapta en fazla $maxPinnedMails e-posta sabitlenebilir. Şu an $pinned sabitli, $adding yeni seçildi$value. Hiçbiri sabitlenmedi.';
  }

  @override
  String get now => 'şimdi';

  @override
  String minAgo(Object inMinutes) {
    return '$inMinutes dk önce';
  }

  @override
  String get yesterday => 'dün';

  @override
  String get theSendDidntStartYou =>
      'Gönderim başlamadı. Giden Kutusu’ndan yeniden deneyebilirsiniz.';

  @override
  String get theServerReturnedAnUnexpected =>
      'Sunucudan beklenmeyen bir yanıt geldi.';

  @override
  String get anUnexpectedErrorOccurredPlease =>
      'Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.';

  @override
  String get standardFoldersCantBeDeleted => 'Standart klasörler silinemez.';

  @override
  String get deleteOrMoveTheSubfolders =>
      'Önce alt klasörleri silin ya da taşıyın.';

  @override
  String get theFolderContainsEmailsMove =>
      'Klasörde e-posta var. Silmeden önce e-postaları başka bir klasöre taşıyın.';

  @override
  String get folderNameCantBeEmpty => 'Klasör adı boş olamaz.';

  @override
  String get folderNameCantContainOr =>
      'Klasör adı * veya % karakteri içeremez.';

  @override
  String folderNameCantContain(Object delimiter) {
    return 'Klasör adı \"$delimiter\" karakterini içeremez.';
  }

  @override
  String get thisNameIsReservedChoose => 'Bu ad ayrılmış. Başka bir ad seçin.';

  @override
  String get attachments2 => 'Ekler:';

  @override
  String get otherFolders => 'Diğer Klasörler';

  @override
  String get accountAndApp => 'Hesap ve uygulama';

  @override
  String get syncAccounts => 'Hesapları eşitle';

  @override
  String get signOut3 => 'Çıkış Yap';

  @override
  String get finishSorting => 'Sıralamayı bitir';

  @override
  String get sortFolders => 'Klasörleri sırala';

  @override
  String get moveUp => 'Yukarı taşı';

  @override
  String get moveDown => 'Aşağı taşı';

  @override
  String get verifyYourIdentityToAccess =>
      'Postalarınıza erişmek için kimliğinizi doğrulayın';

  @override
  String get noFingerprintFaceRecognitionOr =>
      'Cihazınızda parmak izi, yüz tanıma veya ekran kilidi tanımlı değil. Uygulama kilidi bu nedenle doğrulanamıyor.';

  @override
  String get verifyYourIdentityWithYour =>
      'Devam etmek için parmak izi, yüz tanıma veya cihaz şifrenizle kimliğinizi doğrulayın.';

  @override
  String get continueAnyway => 'Yine de devam et';

  @override
  String get unlock => 'Kilidi Aç';

  @override
  String get customColor2 => 'Özel renk';

  @override
  String get hexCode => 'Hex kodu';

  @override
  String get invalidColor => 'Geçersiz renk';

  @override
  String get select => 'Seç';

  @override
  String get hueAndBrightness => 'Renk tonu ve parlaklık';

  @override
  String get color => 'Renk';

  @override
  String get labelsApplyPerAccount => 'Etiketler hesap bazında uygulanır';

  @override
  String get mailAccount => 'Posta hesabı';

  @override
  String couldntApplyTheLabel(Object value) {
    return 'Etiket uygulanamadı: $value';
  }

  @override
  String theseResultsComeFromThe(Object authservId) {
    return 'Bu sonuçlar $authservId tarafından eklenen posta başlığından alınmıştır. Yalnızca bilgi amaçlıdır.';
  }

  @override
  String get theseResultsComeFromTheMailHeaderFor =>
      'Bu sonuçlar posta başlığından alınmıştır. Yalnızca bilgi amaçlıdır.';

  @override
  String get pass => 'geçti';

  @override
  String get fail => 'başarısız';

  @override
  String get partialFail => 'kısmen başarısız';

  @override
  String get neutral => 'nötr';

  @override
  String get temporaryError => 'geçici hata';

  @override
  String get permanentError => 'kalıcı hata';

  @override
  String get theLinkCouldntBeOpened => 'Bağlantı açılamadı.';

  @override
  String theLinkWasntOpenedBecause(Object scheme) {
    return 'Bu bağlantı güvenli olmayan bir adres türü ($scheme:) kullandığı için açılmadı.';
  }

  @override
  String get theLinkWasntOpenedBecauseItsAddressIs =>
      'Bağlantı adresi geçersiz olduğu için açılmadı.';

  @override
  String theLinkTextShowsBut(Object displayedDomain) {
    return 'Bağlantı metni \"$displayedDomain\" adresini gösteriyor, ancak bağlantı başka bir alan adına gidiyor.';
  }

  @override
  String get theDomainContainsInternationalPunycode =>
      'Alan adı uluslararası (punycode) karakterler içeriyor.';

  @override
  String get theDomainMixesCharactersFrom =>
      'Alan adında farklı alfabelerden karakterler bir arada kullanılmış.';

  @override
  String get theDomainContainsMisleadingCharacters =>
      'Alan adında Latin harflerine benzeyen yanıltıcı karakterler var.';

  @override
  String get theAddressContainsUserInformation =>
      'Adres, gerçek alan adını gizleyebilen kullanıcı bilgisi içeriyor.';

  @override
  String get thisLinkLooksSuspicious => 'Bu bağlantı şüpheli görünüyor';

  @override
  String get actualDestination => 'Gerçek hedef';

  @override
  String get rawAddressPunycode => 'Ham adres (punycode)';

  @override
  String get fullLink => 'Tam bağlantı';

  @override
  String get openAnyway => 'Yine de aç';

  @override
  String get unread3 => 'okunmadı';

  @override
  String get starred3 => 'yıldızlı';

  @override
  String get pinned => 'sabitlenmiş';

  @override
  String get replied => 'yanıtlandı';

  @override
  String get hasAttachments => 'ek içeriyor';

  @override
  String messageConversation(Object threadCount) {
    return '$threadCount mesajlık konuşma';
  }

  @override
  String get unread4 => 'Okunmamış';

  @override
  String get attachments3 => 'Ekli';

  @override
  String get newestFirst => 'En yeni önce';

  @override
  String get oldestFirst => 'En eski önce';

  @override
  String get unreadFirst => 'Okunmamışlar önce';

  @override
  String get bySenderAZ => 'Gönderene göre (A-Z)';

  @override
  String get bySubjectAZ => 'Konuya göre (A-Z)';

  @override
  String get sort => 'Sırala';

  @override
  String get enterAValidPort => 'Geçerli bir port girin';

  @override
  String get manualServerSettings => 'Manuel sunucu ayarları';

  @override
  String get automaticServerDiscoveryFailedEnter =>
      'Otomatik sunucu keşfi başarısız oldu. IMAP/SMTP sunucu bilgilerini elle girin (993 IMAP ve 587 SMTP için önerilen varsayılan portlardır).';

  @override
  String get imapServer => 'IMAP sunucu';

  @override
  String get imapPort => 'IMAP port';

  @override
  String get smtpServer => 'SMTP sunucu';

  @override
  String get smtpPort => 'SMTP port';

  @override
  String get connect2 => 'Bağlan';

  @override
  String get thereAreNoOtherFolders => 'Taşınabilecek başka klasör yok.';

  @override
  String get emailsSelectedFromDifferentAccounts =>
      'Farklı hesaplardan seçilen e-postalar yalnızca ortak klasörlere taşınabilir.';

  @override
  String get permanentlyDeleteThisEmail => 'E-posta kalıcı olarak silinsin mi?';

  @override
  String permanentlyDeleteEmails(int count) {
    return '$count e-posta kalıcı olarak silinsin mi?';
  }

  @override
  String get address => 'Adres';

  @override
  String get in1Hour => '1 saat sonra';

  @override
  String get thisEvening600Pm => 'Bu akşam (18:00)';

  @override
  String get tomorrowMorning900Am => 'Yarın sabah (09:00)';

  @override
  String get nextWeekMonday900 => 'Gelecek hafta (Pazartesi 09:00)';

  @override
  String get chooseDateAndTime => 'Tarih ve saat seç';

  @override
  String get theChosenTimeIsIn =>
      'Seçilen saat geçmişte kalıyor, lütfen ileri bir saat seçin.';

  @override
  String youCanAttachAtMost(int maxAttachmentCount) {
    return 'En fazla $maxAttachmentCount dosya ekleyebilirsiniz.';
  }

  @override
  String get aLabelWithThisName => 'Bu isimde bir etiket zaten var.';

  @override
  String get emailAddressIsRequired => 'E-posta adresi zorunludur';

  @override
  String get theAttachmentCouldntBeDownloaded2 => 'Ek indirilemedi.';

  @override
  String add2(Object length) {
    return 'Ekle ($length)';
  }

  @override
  String get requestReadReceipt => 'Okundu bilgisi iste';

  @override
  String get whatShouldHappenToThis => 'Bu taslak ne olsun?';

  @override
  String get deleteEmail => 'E-posta silinsin mi?';

  @override
  String get deleteDraft2 => 'Taslak silinsin mi?';

  @override
  String get aReadReceiptWontBe => 'Okundu bilgisi istenmeyecek.';

  @override
  String emailsSnoozed(int length) {
    return '$length e-posta ertelendi.';
  }

  @override
  String lastSync(Object value) {
    return 'Son senkronizasyon: $value';
  }

  @override
  String get unsubscribed => 'Abonelik iptal edildi.';

  @override
  String get newEmailAndSnoozedEmail =>
      'Yeni e-posta ve ertelenen e-posta bildirimleri';

  @override
  String get noSubject2 => '(Konu yok)';

  @override
  String get noSubject3 => '(konu yok)';

  @override
  String get alsoSearchTheServer => 'Sunucuda da ara';

  @override
  String get composing => 'E-posta yazma';

  @override
  String get mailbox => 'Posta kutusu';

  @override
  String get darkGray => 'Koyu gri';

  @override
  String get thisDevice => 'Bu cihaz';

  @override
  String get everythingIsSynced => 'Hepsi senkronize';

  @override
  String get theAttachmentWasDownloadedIncompletely =>
      'Ek eksik indirildi. Tekrar deneyin.';

  @override
  String get theAttachmentCouldntBeSaved => 'Ek kaydedilemedi. Tekrar deneyin.';

  @override
  String get youHaveANewMessage => 'Yeni bir iletiniz var.';

  @override
  String get newEmailAndAccountNotifications =>
      'Yeni e-posta ve hesap bildirimleri';

  @override
  String get wiFiAndMobileData => 'Wi-Fi ve mobil veri';

  @override
  String get n1Mb => '1 MB';

  @override
  String get n5Mb => '5 MB';

  @override
  String get n10Mb => '10 MB';

  @override
  String get n5Seconds => '5 saniye';

  @override
  String get n10Seconds => '10 saniye';

  @override
  String get n20Seconds => '20 saniye';

  @override
  String get n30Seconds => '30 saniye';

  @override
  String get every5Minutes => 'Her 5 dakikada bir';

  @override
  String get every15Minutes => 'Her 15 dakikada bir';

  @override
  String get every30Minutes => 'Her 30 dakikada bir';

  @override
  String get everyHour => 'Her saat';

  @override
  String get after1Minute => '1 dakika sonra';

  @override
  String get after5Minutes => '5 dakika sonra';

  @override
  String get after15Minutes => '15 dakika sonra';

  @override
  String couldntSaveToTheOutbox(Object value) {
    return 'Giden Kutusu kaydedilemedi: $value';
  }

  @override
  String youCanPinMore(Object free) {
    return '; en fazla $free tane daha sabitleyebilirsiniz';
  }

  @override
  String get appLocked => 'Uygulama Kilitli';

  @override
  String get noLabelsInThisAccount => 'Bu hesapta etiket yok.';

  @override
  String get serverAddressIsRequired => 'Sunucu adresi zorunludur';

  @override
  String wroteSender(Object sender) {
    return '$sender yazdı:';
  }

  @override
  String wroteOnDate(Object date, Object sender) {
    return '$date tarihinde $sender yazdı:';
  }

  @override
  String forwardDateLine(Object date) {
    return 'Tarih: $date\n';
  }

  @override
  String forwardDateLineHtml(Object date) {
    return '<strong>Tarih:</strong> $date<br>';
  }

  @override
  String get recipientToMe => 'bana';

  @override
  String recipientToName(Object name) {
    return '$name’ye';
  }

  @override
  String couldntAddPhoto(Object error) {
    return 'Fotoğraf eklenemedi: $error';
  }

  @override
  String couldntAddPhotos(Object error) {
    return 'Fotoğraflar eklenemedi: $error';
  }

  @override
  String emailCount(int count) {
    return '$count e-posta';
  }

  @override
  String couldntReadSharedFiles(int count, Object names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Paylaşılan $count dosya okunamadı: $names',
      one: 'Paylaşılan dosya okunamadı: $names',
    );
    return '$_temp0';
  }

  @override
  String get earlierMessages => 'Önceki iletiler';

  @override
  String conversationMessageCount(int count) {
    return '$count ileti';
  }
}
