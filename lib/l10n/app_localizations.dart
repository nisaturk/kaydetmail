import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_tr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('tr'),
  ];

  /// No description provided for @draftSavedLocallyServerSync.
  ///
  /// In tr, this message translates to:
  /// **'Taslak yerel olarak kaydedildi; sunucu eşitlemesi başarısız.'**
  String get draftSavedLocallyServerSync;

  /// No description provided for @outgoingMessagesAreWaitingFor.
  ///
  /// In tr, this message translates to:
  /// **'{attention} gönderi Giden Kutusu’nda incelenmeyi bekliyor.'**
  String outgoingMessagesAreWaitingFor(int attention);

  /// No description provided for @open.
  ///
  /// In tr, this message translates to:
  /// **'Aç'**
  String get open;

  /// No description provided for @couldntOpenTheOutboxTry.
  ///
  /// In tr, this message translates to:
  /// **'Giden Kutusu açılamadı. Yeniden deneyin.'**
  String get couldntOpenTheOutboxTry;

  /// No description provided for @full.
  ///
  /// In tr, this message translates to:
  /// **'Tam'**
  String get full;

  /// No description provided for @senderSubjectAndAShort.
  ///
  /// In tr, this message translates to:
  /// **'Gönderen, konu ve kısa önizleme'**
  String get senderSubjectAndAShort;

  /// No description provided for @limited.
  ///
  /// In tr, this message translates to:
  /// **'Sınırlı'**
  String get limited;

  /// No description provided for @senderAndSubject.
  ///
  /// In tr, this message translates to:
  /// **'Gönderen ve konu'**
  String get senderAndSubject;

  /// No description provided for @private.
  ///
  /// In tr, this message translates to:
  /// **'Gizli'**
  String get private;

  /// No description provided for @onlyNewEmail.
  ///
  /// In tr, this message translates to:
  /// **'Yalnızca \"Yeni e-posta\"'**
  String get onlyNewEmail;

  /// No description provided for @inboxSent.
  ///
  /// In tr, this message translates to:
  /// **'Gelen + Gönderilen'**
  String get inboxSent;

  /// No description provided for @allFolders.
  ///
  /// In tr, this message translates to:
  /// **'Tüm klasörler'**
  String get allFolders;

  /// No description provided for @selectedFolders.
  ///
  /// In tr, this message translates to:
  /// **'Seçili klasörler'**
  String get selectedFolders;

  /// No description provided for @thisFileExceedsTheMaximum.
  ///
  /// In tr, this message translates to:
  /// **'Bu dosya izin verilen maksimum boyutu ({value}) aşıyor.'**
  String thisFileExceedsTheMaximum(Object value);

  /// No description provided for @theTotalSizeOfAttachments.
  ///
  /// In tr, this message translates to:
  /// **'Eklerin toplam boyutu izin verilen sınırı ({value}) aşıyor.'**
  String theTotalSizeOfAttachments(Object value);

  /// No description provided for @attachmentCountLimitExceeded.
  ///
  /// In tr, this message translates to:
  /// **'Ek dosya sayısı sınırı aşıldı.'**
  String get attachmentCountLimitExceeded;

  /// No description provided for @anAttachmentExceedsTheMaximum.
  ///
  /// In tr, this message translates to:
  /// **'Bir ek izin verilen maksimum boyutu aşıyor.'**
  String get anAttachmentExceedsTheMaximum;

  /// No description provided for @file.
  ///
  /// In tr, this message translates to:
  /// **'Dosya'**
  String get file;

  /// No description provided for @sent.
  ///
  /// In tr, this message translates to:
  /// **'Gönderilenler'**
  String get sent;

  /// No description provided for @trash.
  ///
  /// In tr, this message translates to:
  /// **'Çöp Kutusu'**
  String get trash;

  /// No description provided for @archive.
  ///
  /// In tr, this message translates to:
  /// **'Arşiv'**
  String get archive;

  /// No description provided for @other.
  ///
  /// In tr, this message translates to:
  /// **'Diğer'**
  String get other;

  /// No description provided for @inbox.
  ///
  /// In tr, this message translates to:
  /// **'Gelen Kutusu'**
  String get inbox;

  /// No description provided for @allMail.
  ///
  /// In tr, this message translates to:
  /// **'Tüm mailler'**
  String get allMail;

  /// No description provided for @outbox.
  ///
  /// In tr, this message translates to:
  /// **'Giden Kutusu'**
  String get outbox;

  /// No description provided for @starred.
  ///
  /// In tr, this message translates to:
  /// **'Yıldızlılar'**
  String get starred;

  /// No description provided for @snoozed.
  ///
  /// In tr, this message translates to:
  /// **'Ertelenenler'**
  String get snoozed;

  /// No description provided for @drafts.
  ///
  /// In tr, this message translates to:
  /// **'Taslaklar'**
  String get drafts;

  /// No description provided for @enterAValidEmailAddress.
  ///
  /// In tr, this message translates to:
  /// **'Geçerli bir e-posta adresi girin.'**
  String get enterAValidEmailAddress;

  /// No description provided for @thisEmailIsAlreadySaved.
  ///
  /// In tr, this message translates to:
  /// **'Bu e-posta zaten kayıtlı.'**
  String get thisEmailIsAlreadySaved;

  /// No description provided for @labelNameCantBeEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Etiket adı boş olamaz.'**
  String get labelNameCantBeEmpty;

  /// No description provided for @theSenderAddressCouldntBe.
  ///
  /// In tr, this message translates to:
  /// **'Gönderici adresi okunamadı.'**
  String get theSenderAddressCouldntBe;

  /// No description provided for @connected.
  ///
  /// In tr, this message translates to:
  /// **'{email} bağlandı.'**
  String connected(Object email);

  /// No description provided for @addNewAccount.
  ///
  /// In tr, this message translates to:
  /// **'Yeni hesap ekle'**
  String get addNewAccount;

  /// No description provided for @enterAValidEmailAddress2.
  ///
  /// In tr, this message translates to:
  /// **'Geçerli bir e-posta adresi girin'**
  String get enterAValidEmailAddress2;

  /// No description provided for @email.
  ///
  /// In tr, this message translates to:
  /// **'E-posta'**
  String get email;

  /// No description provided for @passwordIsRequired.
  ///
  /// In tr, this message translates to:
  /// **'Şifre zorunludur'**
  String get passwordIsRequired;

  /// No description provided for @password.
  ///
  /// In tr, this message translates to:
  /// **'Şifre'**
  String get password;

  /// No description provided for @showPassword.
  ///
  /// In tr, this message translates to:
  /// **'Şifreyi göster'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In tr, this message translates to:
  /// **'Şifreyi gizle'**
  String get hidePassword;

  /// No description provided for @connect.
  ///
  /// In tr, this message translates to:
  /// **'Bağla'**
  String get connect;

  /// No description provided for @downloadCancelled.
  ///
  /// In tr, this message translates to:
  /// **'İndirme iptal edildi.'**
  String get downloadCancelled;

  /// No description provided for @share.
  ///
  /// In tr, this message translates to:
  /// **'Paylaş'**
  String get share;

  /// No description provided for @downloading.
  ///
  /// In tr, this message translates to:
  /// **'İndiriliyor…'**
  String get downloading;

  /// No description provided for @cancel.
  ///
  /// In tr, this message translates to:
  /// **'İptal'**
  String get cancel;

  /// No description provided for @thisFileTypeCantBe.
  ///
  /// In tr, this message translates to:
  /// **'Bu dosya türü uygulama içinde açılamıyor.'**
  String get thisFileTypeCantBe;

  /// No description provided for @theFileCouldntBePreviewed.
  ///
  /// In tr, this message translates to:
  /// **'Dosya önizlenemedi.'**
  String get theFileCouldntBePreviewed;

  /// No description provided for @openInAnotherApp.
  ///
  /// In tr, this message translates to:
  /// **'Başka uygulamada aç'**
  String get openInAnotherApp;

  /// No description provided for @emptyDocument.
  ///
  /// In tr, this message translates to:
  /// **'(Boş belge)'**
  String get emptyDocument;

  /// No description provided for @chooseASavedTextOr.
  ///
  /// In tr, this message translates to:
  /// **'Hazır metin veya şablon seç'**
  String get chooseASavedTextOr;

  /// No description provided for @close.
  ///
  /// In tr, this message translates to:
  /// **'Kapat'**
  String get close;

  /// No description provided for @tryAgain.
  ///
  /// In tr, this message translates to:
  /// **'Tekrar dene'**
  String get tryAgain;

  /// No description provided for @noSavedTextsForThis.
  ///
  /// In tr, this message translates to:
  /// **'Bu hesapta kayıtlı metin yok.\nAyarlar > Hazır Metinler ve Şablonlar'**
  String get noSavedTextsForThis;

  /// No description provided for @downloadAgain.
  ///
  /// In tr, this message translates to:
  /// **'Tekrar indir'**
  String get downloadAgain;

  /// No description provided for @remove.
  ///
  /// In tr, this message translates to:
  /// **'Kaldır'**
  String get remove;

  /// No description provided for @theEmailWillBeSent.
  ///
  /// In tr, this message translates to:
  /// **'E-posta {_secondsLeft} sn içinde gönderilecek'**
  String theEmailWillBeSent(Object _secondsLeft);

  /// No description provided for @insertLink.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı Ekle'**
  String get insertLink;

  /// No description provided for @cancel2.
  ///
  /// In tr, this message translates to:
  /// **'Vazgeç'**
  String get cancel2;

  /// No description provided for @add.
  ///
  /// In tr, this message translates to:
  /// **'Ekle'**
  String get add;

  /// No description provided for @image.
  ///
  /// In tr, this message translates to:
  /// **'Görsel'**
  String get image;

  /// No description provided for @embeddedContent.
  ///
  /// In tr, this message translates to:
  /// **'Gömülü içerik'**
  String get embeddedContent;

  /// No description provided for @addFromContacts.
  ///
  /// In tr, this message translates to:
  /// **'Kişilerden ekle'**
  String get addFromContacts;

  /// No description provided for @to.
  ///
  /// In tr, this message translates to:
  /// **'Kime'**
  String get to;

  /// No description provided for @searchNameOrEmail.
  ///
  /// In tr, this message translates to:
  /// **'Ad veya e-posta ara'**
  String get searchNameOrEmail;

  /// No description provided for @noSavedContactsYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz kayıtlı kişi yok.'**
  String get noSavedContactsYet;

  /// No description provided for @noMatchingContactsFound.
  ///
  /// In tr, this message translates to:
  /// **'Eşleşen kişi bulunamadı.'**
  String get noMatchingContactsFound;

  /// No description provided for @editDraft.
  ///
  /// In tr, this message translates to:
  /// **'Taslağı Düzenle'**
  String get editDraft;

  /// No description provided for @sendNow.
  ///
  /// In tr, this message translates to:
  /// **'Şimdi Gönder'**
  String get sendNow;

  /// No description provided for @moreOptions.
  ///
  /// In tr, this message translates to:
  /// **'Diğer seçenekler'**
  String get moreOptions;

  /// No description provided for @schedule.
  ///
  /// In tr, this message translates to:
  /// **'Zamanla'**
  String get schedule;

  /// No description provided for @saveDraft.
  ///
  /// In tr, this message translates to:
  /// **'Taslağı kaydet'**
  String get saveDraft;

  /// No description provided for @delete.
  ///
  /// In tr, this message translates to:
  /// **'Sil'**
  String get delete;

  /// No description provided for @addCcBcc.
  ///
  /// In tr, this message translates to:
  /// **'Cc / Bcc ekle'**
  String get addCcBcc;

  /// No description provided for @subject.
  ///
  /// In tr, this message translates to:
  /// **'Konu'**
  String get subject;

  /// No description provided for @writeYourMessage.
  ///
  /// In tr, this message translates to:
  /// **'Mesajınızı yazın'**
  String get writeYourMessage;

  /// No description provided for @from.
  ///
  /// In tr, this message translates to:
  /// **'Kimden'**
  String get from;

  /// No description provided for @chooseIdentity.
  ///
  /// In tr, this message translates to:
  /// **'Kimlik seç'**
  String get chooseIdentity;

  /// No description provided for @chooseAccount.
  ///
  /// In tr, this message translates to:
  /// **'Hesap seç'**
  String get chooseAccount;

  /// No description provided for @attachFile.
  ///
  /// In tr, this message translates to:
  /// **'Dosya ekle'**
  String get attachFile;

  /// No description provided for @savedTexts.
  ///
  /// In tr, this message translates to:
  /// **'Hazır Metinler'**
  String get savedTexts;

  /// No description provided for @anAttachmentCouldntBeDownloaded.
  ///
  /// In tr, this message translates to:
  /// **'Bir ek indirilemedi. Tekrar deneyin veya kaldırın.'**
  String get anAttachmentCouldntBeDownloaded;

  /// No description provided for @attachmentsAreBeingPreparedPlease.
  ///
  /// In tr, this message translates to:
  /// **'Ekler hazırlanıyor, lütfen bekleyin.'**
  String get attachmentsAreBeingPreparedPlease;

  /// No description provided for @chooseFile.
  ///
  /// In tr, this message translates to:
  /// **'Dosya seç'**
  String get chooseFile;

  /// No description provided for @choosePhoto.
  ///
  /// In tr, this message translates to:
  /// **'Fotoğraf seç'**
  String get choosePhoto;

  /// No description provided for @camera.
  ///
  /// In tr, this message translates to:
  /// **'Kamera'**
  String get camera;

  /// No description provided for @couldntAccessTheCameraCheck.
  ///
  /// In tr, this message translates to:
  /// **'Kameraya erişilemedi. İzinleri kontrol edin veya dosya seçin.'**
  String get couldntAccessTheCameraCheck;

  /// No description provided for @couldntAccessPhotosCheckPermissions.
  ///
  /// In tr, this message translates to:
  /// **'Fotoğraflara erişilemedi. İzinleri kontrol edin veya dosya seçin.'**
  String get couldntAccessPhotosCheckPermissions;

  /// No description provided for @imageSize.
  ///
  /// In tr, this message translates to:
  /// **'Görsel boyutu'**
  String get imageSize;

  /// No description provided for @original.
  ///
  /// In tr, this message translates to:
  /// **'Orijinal'**
  String get original;

  /// No description provided for @large2048Px.
  ///
  /// In tr, this message translates to:
  /// **'Büyük (2048 px)'**
  String get large2048Px;

  /// No description provided for @medium1280Px.
  ///
  /// In tr, this message translates to:
  /// **'Orta (1280 px)'**
  String get medium1280Px;

  /// No description provided for @small640Px.
  ///
  /// In tr, this message translates to:
  /// **'Küçük (640 px)'**
  String get small640Px;

  /// No description provided for @preparingImages.
  ///
  /// In tr, this message translates to:
  /// **'Görseller hazırlanıyor… ({completed}/{length})'**
  String preparingImages(Object completed, Object length);

  /// No description provided for @couldntResizeTheImageThe.
  ///
  /// In tr, this message translates to:
  /// **'{name}: Görsel küçültülemedi; özgün dosya kullanılacak.'**
  String couldntResizeTheImageThe(Object name);

  /// No description provided for @couldntSaveTheDraftTry.
  ///
  /// In tr, this message translates to:
  /// **'Taslak kaydedilemedi. Tekrar deneyin.'**
  String get couldntSaveTheDraftTry;

  /// No description provided for @youCanSaveWhatYouve.
  ///
  /// In tr, this message translates to:
  /// **'Yazdıklarınızı daha sonra tamamlamak için kaydedebilir veya taslağı kalıcı olarak silebilirsiniz.'**
  String get youCanSaveWhatYouve;

  /// No description provided for @couldntSaveTheDraftYour.
  ///
  /// In tr, this message translates to:
  /// **'Taslak kaydedilemedi. İçeriğiniz ekranda tutuluyor.'**
  String get couldntSaveTheDraftYour;

  /// No description provided for @draftSaved.
  ///
  /// In tr, this message translates to:
  /// **'Taslak kaydedildi.'**
  String get draftSaved;

  /// No description provided for @saving.
  ///
  /// In tr, this message translates to:
  /// **'Kaydediliyor…'**
  String get saving;

  /// No description provided for @saveDraft2.
  ///
  /// In tr, this message translates to:
  /// **'Taslağı Kaydet'**
  String get saveDraft2;

  /// No description provided for @deleteDraft.
  ///
  /// In tr, this message translates to:
  /// **'Taslağı Sil'**
  String get deleteDraft;

  /// No description provided for @keepEditing.
  ///
  /// In tr, this message translates to:
  /// **'Düzenlemeye devam et'**
  String get keepEditing;

  /// No description provided for @thisActionCantBeUndone.
  ///
  /// In tr, this message translates to:
  /// **'Bu işlem geri alınamaz.'**
  String get thisActionCantBeUndone;

  /// No description provided for @couldntDeleteTheDraft.
  ///
  /// In tr, this message translates to:
  /// **'Taslak silinemedi: {value}'**
  String couldntDeleteTheDraft(Object value);

  /// No description provided for @draftDeleted.
  ///
  /// In tr, this message translates to:
  /// **'Taslak silindi.'**
  String get draftDeleted;

  /// No description provided for @youMustEnterAtLeast.
  ///
  /// In tr, this message translates to:
  /// **'En az bir alıcı yazmalısınız.'**
  String get youMustEnterAtLeast;

  /// No description provided for @fixTheInvalidEmailAddresses.
  ///
  /// In tr, this message translates to:
  /// **'Geçersiz e-posta adreslerini düzeltip tekrar deneyin.'**
  String get fixTheInvalidEmailAddresses;

  /// No description provided for @couldntSaveTheMessage.
  ///
  /// In tr, this message translates to:
  /// **'Gönderi kaydedilemedi: {value}'**
  String couldntSaveTheMessage(Object value);

  /// No description provided for @undo.
  ///
  /// In tr, this message translates to:
  /// **'Geri Al'**
  String get undo;

  /// No description provided for @aReadReceiptWillBe.
  ///
  /// In tr, this message translates to:
  /// **'Alıcılardan okundu bilgisi istenecek.'**
  String get aReadReceiptWillBe;

  /// No description provided for @pleaseChooseAFutureDate.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen ileri bir tarih ve saat seçin.'**
  String get pleaseChooseAFutureDate;

  /// No description provided for @theEmailIsScheduledTo.
  ///
  /// In tr, this message translates to:
  /// **'E-posta {value} tarihinde gönderilmek üzere zamanlandı.'**
  String theEmailIsScheduledTo(Object value);

  /// No description provided for @couldntSchedule.
  ///
  /// In tr, this message translates to:
  /// **'Zamanlanamadı: {value}'**
  String couldntSchedule(Object value);

  /// No description provided for @couldntLoadTheSenderIdentity.
  ///
  /// In tr, this message translates to:
  /// **'Gönderen kimliği yüklenemedi: {value}'**
  String couldntLoadTheSenderIdentity(Object value);

  /// No description provided for @replaceTheSubject.
  ///
  /// In tr, this message translates to:
  /// **'Konuyu değiştir?'**
  String get replaceTheSubject;

  /// No description provided for @theCurrentSubjectWillBe.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut konu hazır metindeki konuyla değiştirilecek.'**
  String get theCurrentSubjectWillBe;

  /// No description provided for @keepSubject.
  ///
  /// In tr, this message translates to:
  /// **'Konuyu koru'**
  String get keepSubject;

  /// No description provided for @replace.
  ///
  /// In tr, this message translates to:
  /// **'Değiştir'**
  String get replace;

  /// No description provided for @manageFolders.
  ///
  /// In tr, this message translates to:
  /// **'Klasörleri yönet'**
  String get manageFolders;

  /// No description provided for @whichAccountsFoldersDoYou.
  ///
  /// In tr, this message translates to:
  /// **'Hangi hesabın klasörleri yönetilsin?'**
  String get whichAccountsFoldersDoYou;

  /// No description provided for @folder.
  ///
  /// In tr, this message translates to:
  /// **'Klasör'**
  String get folder;

  /// No description provided for @chooseParentFolder.
  ///
  /// In tr, this message translates to:
  /// **'Üst klasör seçin'**
  String get chooseParentFolder;

  /// No description provided for @topLevelFolder.
  ///
  /// In tr, this message translates to:
  /// **'Bağımsız klasör'**
  String get topLevelFolder;

  /// No description provided for @newFolder.
  ///
  /// In tr, this message translates to:
  /// **'Yeni klasör'**
  String get newFolder;

  /// No description provided for @createSubfolder.
  ///
  /// In tr, this message translates to:
  /// **'Alt klasör oluştur'**
  String get createSubfolder;

  /// No description provided for @folderCreated.
  ///
  /// In tr, this message translates to:
  /// **'Klasör oluşturuldu.'**
  String get folderCreated;

  /// No description provided for @rename.
  ///
  /// In tr, this message translates to:
  /// **'Yeniden adlandır'**
  String get rename;

  /// No description provided for @folderRenamed.
  ///
  /// In tr, this message translates to:
  /// **'Klasör yeniden adlandırıldı.'**
  String get folderRenamed;

  /// No description provided for @parentFolderChanged.
  ///
  /// In tr, this message translates to:
  /// **'Üst klasör değiştirildi.'**
  String get parentFolderChanged;

  /// No description provided for @folderCantBeDeleted.
  ///
  /// In tr, this message translates to:
  /// **'Klasör silinemez'**
  String get folderCantBeDeleted;

  /// No description provided for @ok.
  ///
  /// In tr, this message translates to:
  /// **'Tamam'**
  String get ok;

  /// No description provided for @deleteFolder.
  ///
  /// In tr, this message translates to:
  /// **'Klasör silinsin mi?'**
  String get deleteFolder;

  /// No description provided for @theFolderWillBePermanently.
  ///
  /// In tr, this message translates to:
  /// **'\"{name}\" klasörü sunucudan kalıcı olarak silinecek.'**
  String theFolderWillBePermanently(Object name);

  /// No description provided for @folderDeleted.
  ///
  /// In tr, this message translates to:
  /// **'Klasör silindi.'**
  String get folderDeleted;

  /// No description provided for @whatShouldBeUsedAs.
  ///
  /// In tr, this message translates to:
  /// **'\"{name}\" ne olarak kullanılsın?'**
  String whatShouldBeUsedAs(Object name);

  /// No description provided for @isNowUsedAs.
  ///
  /// In tr, this message translates to:
  /// **'\"{name}\" artık {value} olarak kullanılıyor.'**
  String isNowUsedAs(Object name, Object value);

  /// No description provided for @automaticDetectionRestoredFor.
  ///
  /// In tr, this message translates to:
  /// **'\"{name}\" için otomatik tespit geri yüklendi.'**
  String automaticDetectionRestoredFor(Object name);

  /// No description provided for @synced.
  ///
  /// In tr, this message translates to:
  /// **'\"{name}\" eşitlendi.'**
  String synced(Object name);

  /// No description provided for @willSyncAutomatically.
  ///
  /// In tr, this message translates to:
  /// **'\"{name}\" otomatik eşitlenecek.'**
  String willSyncAutomatically(Object name);

  /// No description provided for @willNotSyncAutomatically.
  ///
  /// In tr, this message translates to:
  /// **'\"{name}\" otomatik eşitlenmeyecek.'**
  String willNotSyncAutomatically(Object name);

  /// No description provided for @folders.
  ///
  /// In tr, this message translates to:
  /// **'Klasörler'**
  String get folders;

  /// No description provided for @rescanFoldersOnTheServer.
  ///
  /// In tr, this message translates to:
  /// **'Sunucudaki klasörleri yeniden tara'**
  String get rescanFoldersOnTheServer;

  /// No description provided for @folderNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Klasör bulunamadı'**
  String get folderNotFound;

  /// No description provided for @usedAs.
  ///
  /// In tr, this message translates to:
  /// **'{value} olarak kullanılıyor'**
  String usedAs(Object value);

  /// No description provided for @standardFolder.
  ///
  /// In tr, this message translates to:
  /// **'Standart klasör'**
  String get standardFolder;

  /// No description provided for @unread.
  ///
  /// In tr, this message translates to:
  /// **'{unreadCount} okunmamış'**
  String unread(Object unreadCount);

  /// No description provided for @syncingAutomatically.
  ///
  /// In tr, this message translates to:
  /// **'Otomatik eşitleniyor'**
  String get syncingAutomatically;

  /// No description provided for @changeParentFolder.
  ///
  /// In tr, this message translates to:
  /// **'Üst klasörü değiştir'**
  String get changeParentFolder;

  /// No description provided for @assignFolderRole.
  ///
  /// In tr, this message translates to:
  /// **'Klasör rolü ata'**
  String get assignFolderRole;

  /// No description provided for @revertToAutomatic.
  ///
  /// In tr, this message translates to:
  /// **'Otomatiğe döndür'**
  String get revertToAutomatic;

  /// No description provided for @syncNow.
  ///
  /// In tr, this message translates to:
  /// **'Şimdi eşitle'**
  String get syncNow;

  /// No description provided for @turnOffAutomaticSync.
  ///
  /// In tr, this message translates to:
  /// **'Otomatik eşitlemeyi kapat'**
  String get turnOffAutomaticSync;

  /// No description provided for @turnOnAutomaticSync.
  ///
  /// In tr, this message translates to:
  /// **'Otomatik eşitlemeyi aç'**
  String get turnOnAutomaticSync;

  /// No description provided for @folderName.
  ///
  /// In tr, this message translates to:
  /// **'Klasör adı'**
  String get folderName;

  /// No description provided for @save.
  ///
  /// In tr, this message translates to:
  /// **'Kaydet'**
  String get save;

  /// No description provided for @anActionTakenWhileOffline.
  ///
  /// In tr, this message translates to:
  /// **'Çevrimdışıyken yapılan bir işlem uygulanamadı. Son durum sunucudan yüklendi.'**
  String get anActionTakenWhileOffline;

  /// No description provided for @syncingAccounts.
  ///
  /// In tr, this message translates to:
  /// **'Hesaplar eşitleniyor…'**
  String get syncingAccounts;

  /// No description provided for @accountsSynced.
  ///
  /// In tr, this message translates to:
  /// **'Hesaplar eşitlendi.'**
  String get accountsSynced;

  /// No description provided for @syncStatusNotFoundTry.
  ///
  /// In tr, this message translates to:
  /// **'Eşitleme durumu bulunamadı. Tekrar deneyin.'**
  String get syncStatusNotFoundTry;

  /// No description provided for @allInboxes.
  ///
  /// In tr, this message translates to:
  /// **'Tüm Gelen Kutuları'**
  String get allInboxes;

  /// No description provided for @emailsDeleted.
  ///
  /// In tr, this message translates to:
  /// **'{count} e-posta silindi'**
  String emailsDeleted(int count);

  /// No description provided for @draftsDeleted.
  ///
  /// In tr, this message translates to:
  /// **'{length} taslak silindi'**
  String draftsDeleted(int length);

  /// No description provided for @actionFailed.
  ///
  /// In tr, this message translates to:
  /// **'İşlem başarısız: {value}'**
  String actionFailed(Object value);

  /// No description provided for @emailsPermanentlyDeleted.
  ///
  /// In tr, this message translates to:
  /// **'{length} e-posta kalıcı olarak silindi'**
  String emailsPermanentlyDeleted(int length);

  /// No description provided for @emailsArchived.
  ///
  /// In tr, this message translates to:
  /// **'{count} e-posta arşivlendi'**
  String emailsArchived(int count);

  /// No description provided for @emailsMovedToSpam.
  ///
  /// In tr, this message translates to:
  /// **'{count} e-posta spam kutusuna taşındı'**
  String emailsMovedToSpam(int count);

  /// No description provided for @emailsRestored.
  ///
  /// In tr, this message translates to:
  /// **'{count} e-posta geri yüklendi'**
  String emailsRestored(int count);

  /// No description provided for @emailsUnarchived.
  ///
  /// In tr, this message translates to:
  /// **'{count} e-posta arşivden çıkarıldı'**
  String emailsUnarchived(int count);

  /// No description provided for @emailsMarkedAsNotSpam.
  ///
  /// In tr, this message translates to:
  /// **'{count} e-posta spam olmaktan çıkarıldı'**
  String emailsMarkedAsNotSpam(int count);

  /// No description provided for @theseEmailsAreAlreadyBeing.
  ///
  /// In tr, this message translates to:
  /// **'Bu e-postalar zaten işleniyor.'**
  String get theseEmailsAreAlreadyBeing;

  /// No description provided for @undo2.
  ///
  /// In tr, this message translates to:
  /// **'Geri al'**
  String get undo2;

  /// No description provided for @emailsMoved.
  ///
  /// In tr, this message translates to:
  /// **'{length} e-posta taşındı.'**
  String emailsMoved(int length);

  /// No description provided for @newEmail.
  ///
  /// In tr, this message translates to:
  /// **'Yeni E-posta'**
  String get newEmail;

  /// No description provided for @search.
  ///
  /// In tr, this message translates to:
  /// **'Ara'**
  String get search;

  /// No description provided for @restore.
  ///
  /// In tr, this message translates to:
  /// **'Geri Yükle'**
  String get restore;

  /// No description provided for @deletePermanently.
  ///
  /// In tr, this message translates to:
  /// **'Kalıcı olarak sil'**
  String get deletePermanently;

  /// No description provided for @markAsRead.
  ///
  /// In tr, this message translates to:
  /// **'Okundu olarak işaretle'**
  String get markAsRead;

  /// No description provided for @markAsUnread.
  ///
  /// In tr, this message translates to:
  /// **'Okunmadı olarak işaretle'**
  String get markAsUnread;

  /// No description provided for @archive2.
  ///
  /// In tr, this message translates to:
  /// **'Arşivle'**
  String get archive2;

  /// No description provided for @unarchive.
  ///
  /// In tr, this message translates to:
  /// **'Arşivden çıkar'**
  String get unarchive;

  /// No description provided for @removeStar.
  ///
  /// In tr, this message translates to:
  /// **'Yıldızı kaldır'**
  String get removeStar;

  /// No description provided for @star.
  ///
  /// In tr, this message translates to:
  /// **'Yıldızla'**
  String get star;

  /// No description provided for @unpin.
  ///
  /// In tr, this message translates to:
  /// **'Sabitlemeyi kaldır'**
  String get unpin;

  /// No description provided for @pin.
  ///
  /// In tr, this message translates to:
  /// **'Sabitle'**
  String get pin;

  /// No description provided for @removeSnooze.
  ///
  /// In tr, this message translates to:
  /// **'Ertelemeyi kaldır'**
  String get removeSnooze;

  /// No description provided for @snooze.
  ///
  /// In tr, this message translates to:
  /// **'Ertele'**
  String get snooze;

  /// No description provided for @moveToSpam.
  ///
  /// In tr, this message translates to:
  /// **'Spam kutusuna gönder'**
  String get moveToSpam;

  /// No description provided for @notSpam.
  ///
  /// In tr, this message translates to:
  /// **'Spam değil'**
  String get notSpam;

  /// No description provided for @removeLabel.
  ///
  /// In tr, this message translates to:
  /// **'Etiketi kaldır'**
  String get removeLabel;

  /// No description provided for @label.
  ///
  /// In tr, this message translates to:
  /// **'Etiketle'**
  String get label;

  /// No description provided for @move.
  ///
  /// In tr, this message translates to:
  /// **'Taşı'**
  String get move;

  /// No description provided for @selectAll.
  ///
  /// In tr, this message translates to:
  /// **'Tümünü seç'**
  String get selectAll;

  /// No description provided for @cancelSelection.
  ///
  /// In tr, this message translates to:
  /// **'Seçimi iptal et'**
  String get cancelSelection;

  /// No description provided for @n1Selected.
  ///
  /// In tr, this message translates to:
  /// **'1 seçili'**
  String get n1Selected;

  /// No description provided for @selected.
  ///
  /// In tr, this message translates to:
  /// **'{count} seçili'**
  String selected(Object count);

  /// No description provided for @selectAnEmailToView.
  ///
  /// In tr, this message translates to:
  /// **'Görüntülemek için bir e-posta seçin'**
  String get selectAnEmailToView;

  /// No description provided for @noConnectionShowingTheLatest.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı yok. Önbellekteki son postalar gösteriliyor.'**
  String get noConnectionShowingTheLatest;

  /// No description provided for @restore2.
  ///
  /// In tr, this message translates to:
  /// **'Geri yükle'**
  String get restore2;

  /// No description provided for @readUnread.
  ///
  /// In tr, this message translates to:
  /// **'Okundu / okunmadı'**
  String get readUnread;

  /// No description provided for @star2.
  ///
  /// In tr, this message translates to:
  /// **'Yıldız'**
  String get star2;

  /// No description provided for @justNow.
  ///
  /// In tr, this message translates to:
  /// **'az önce'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In tr, this message translates to:
  /// **'{inMinutes} dakika önce'**
  String minutesAgo(int inMinutes);

  /// No description provided for @hoursAgo.
  ///
  /// In tr, this message translates to:
  /// **'{inHours} saat önce'**
  String hoursAgo(int inHours);

  /// No description provided for @daysAgo.
  ///
  /// In tr, this message translates to:
  /// **'{inDays} gün önce'**
  String daysAgo(int inDays);

  /// No description provided for @tryLoadingMoreAgain.
  ///
  /// In tr, this message translates to:
  /// **'Daha fazlasını tekrar yükle'**
  String get tryLoadingMoreAgain;

  /// No description provided for @noMailMatchesThisFilter.
  ///
  /// In tr, this message translates to:
  /// **'Bu filtreyle eşleşen posta yok'**
  String get noMailMatchesThisFilter;

  /// No description provided for @clearFilter.
  ///
  /// In tr, this message translates to:
  /// **'Filtreyi temizle'**
  String get clearFilter;

  /// No description provided for @newEmailsWillAppearHere.
  ///
  /// In tr, this message translates to:
  /// **'Yeni e-postalar geldiğinde burada görünür.'**
  String get newEmailsWillAppearHere;

  /// No description provided for @emailsFromYourConnectedAccounts.
  ///
  /// In tr, this message translates to:
  /// **'Bağlı hesaplarınızdaki e-postalar burada görünür.'**
  String get emailsFromYourConnectedAccounts;

  /// No description provided for @emailsYouSendAppearHere.
  ///
  /// In tr, this message translates to:
  /// **'Gönderdiğiniz e-postalar burada görünür.'**
  String get emailsYouSendAppearHere;

  /// No description provided for @emailsYouStarAppearHere.
  ///
  /// In tr, this message translates to:
  /// **'Yıldızladığınız e-postalar burada görünür.'**
  String get emailsYouStarAppearHere;

  /// No description provided for @emailsYouSnoozeAppearHere.
  ///
  /// In tr, this message translates to:
  /// **'Ertelediğiniz e-postalar burada görünür.'**
  String get emailsYouSnoozeAppearHere;

  /// No description provided for @draftsYouSaveAreKept.
  ///
  /// In tr, this message translates to:
  /// **'Kaydettiğiniz taslaklar burada durur.'**
  String get draftsYouSaveAreKept;

  /// No description provided for @emailsYouDeleteAreKept.
  ///
  /// In tr, this message translates to:
  /// **'Sildiğiniz e-postalar burada durur.'**
  String get emailsYouDeleteAreKept;

  /// No description provided for @unwantedEmailsEndUpHere.
  ///
  /// In tr, this message translates to:
  /// **'İstenmeyen e-postalar buraya düşer.'**
  String get unwantedEmailsEndUpHere;

  /// No description provided for @emailsYouArchiveAreKept.
  ///
  /// In tr, this message translates to:
  /// **'Arşivlediğiniz e-postalar burada durur.'**
  String get emailsYouArchiveAreKept;

  /// No description provided for @offline.
  ///
  /// In tr, this message translates to:
  /// **'Çevrimdışı'**
  String get offline;

  /// No description provided for @isEmpty.
  ///
  /// In tr, this message translates to:
  /// **'{label} boş'**
  String isEmpty(Object label);

  /// No description provided for @noInternetConnectionNewMail.
  ///
  /// In tr, this message translates to:
  /// **'İnternet bağlantısı yok. Bağlantı sağlanınca yeni postalar görünür.'**
  String get noInternetConnectionNewMail;

  /// No description provided for @refresh.
  ///
  /// In tr, this message translates to:
  /// **'Yenile'**
  String get refresh;

  /// No description provided for @youreOffline.
  ///
  /// In tr, this message translates to:
  /// **'Çevrimdışısınız'**
  String get youreOffline;

  /// No description provided for @yourEmailsCouldntBeLoaded.
  ///
  /// In tr, this message translates to:
  /// **'E-postalarınız yüklenemedi'**
  String get yourEmailsCouldntBeLoaded;

  /// No description provided for @noInternetConnectionItWill.
  ///
  /// In tr, this message translates to:
  /// **'İnternet bağlantısı yok. Bağlantı sağlanınca otomatik güncellenir.'**
  String get noInternetConnectionItWill;

  /// No description provided for @accountReconnected.
  ///
  /// In tr, this message translates to:
  /// **'Hesap yeniden bağlandı.'**
  String get accountReconnected;

  /// No description provided for @signInFailedTryAgain.
  ///
  /// In tr, this message translates to:
  /// **'Giriş başarısız. Tekrar deneyin.'**
  String get signInFailedTryAgain;

  /// No description provided for @serverAddress.
  ///
  /// In tr, this message translates to:
  /// **'Sunucu adresi'**
  String get serverAddress;

  /// No description provided for @aSecureAppForYour.
  ///
  /// In tr, this message translates to:
  /// **'E-postalarınız için güvenli bir uygulama'**
  String get aSecureAppForYour;

  /// No description provided for @continueLabel.
  ///
  /// In tr, this message translates to:
  /// **'Devam'**
  String get continueLabel;

  /// No description provided for @back.
  ///
  /// In tr, this message translates to:
  /// **'Geri'**
  String get back;

  /// No description provided for @youAreReconnectingThisAccount.
  ///
  /// In tr, this message translates to:
  /// **'Şu hesabı yeniden bağlıyorsunuz'**
  String get youAreReconnectingThisAccount;

  /// No description provided for @youAreSigningInWith.
  ///
  /// In tr, this message translates to:
  /// **'Şu hesapla oturum açıyorsunuz'**
  String get youAreSigningInWith;

  /// No description provided for @reconnect.
  ///
  /// In tr, this message translates to:
  /// **'Yeniden Bağlan'**
  String get reconnect;

  /// No description provided for @signIn.
  ///
  /// In tr, this message translates to:
  /// **'Giriş Yap'**
  String get signIn;

  /// No description provided for @hideQuote.
  ///
  /// In tr, this message translates to:
  /// **'Alıntıyı gizle'**
  String get hideQuote;

  /// No description provided for @showQuoteAndSignature.
  ///
  /// In tr, this message translates to:
  /// **'Alıntı ve imzayı göster'**
  String get showQuoteAndSignature;

  /// No description provided for @remoteImagesWereBlockedIn.
  ///
  /// In tr, this message translates to:
  /// **'Bu mesajda uzak görseller güvenlik nedeniyle durduruldu.'**
  String get remoteImagesWereBlockedIn;

  /// No description provided for @loadImages.
  ///
  /// In tr, this message translates to:
  /// **'Görselleri yükle'**
  String get loadImages;

  /// No description provided for @cancelDownload.
  ///
  /// In tr, this message translates to:
  /// **'İndirmeyi iptal et'**
  String get cancelDownload;

  /// No description provided for @ready.
  ///
  /// In tr, this message translates to:
  /// **'Hazır'**
  String get ready;

  /// No description provided for @downloadAttachment.
  ///
  /// In tr, this message translates to:
  /// **'Eki indir'**
  String get downloadAttachment;

  /// No description provided for @sendingReply.
  ///
  /// In tr, this message translates to:
  /// **'Yanıt gönderiliyor'**
  String get sendingReply;

  /// No description provided for @replySent.
  ///
  /// In tr, this message translates to:
  /// **'Yanıt gönderildi'**
  String get replySent;

  /// No description provided for @couldntSendTheReply.
  ///
  /// In tr, this message translates to:
  /// **'Yanıt gönderilemedi: {value}'**
  String couldntSendTheReply(Object value);

  /// No description provided for @writeAQuickReply.
  ///
  /// In tr, this message translates to:
  /// **'Hızlı yanıt yaz…'**
  String get writeAQuickReply;

  /// No description provided for @sendReply.
  ///
  /// In tr, this message translates to:
  /// **'Yanıtı gönder'**
  String get sendReply;

  /// No description provided for @more.
  ///
  /// In tr, this message translates to:
  /// **'Daha fazla'**
  String get more;

  /// No description provided for @replyAll.
  ///
  /// In tr, this message translates to:
  /// **'Tümünü Yanıtla'**
  String get replyAll;

  /// No description provided for @reply.
  ///
  /// In tr, this message translates to:
  /// **'Yanıtla'**
  String get reply;

  /// No description provided for @forward.
  ///
  /// In tr, this message translates to:
  /// **'İlet'**
  String get forward;

  /// No description provided for @print.
  ///
  /// In tr, this message translates to:
  /// **'Yazdır'**
  String get print;

  /// No description provided for @shareAsPdf.
  ///
  /// In tr, this message translates to:
  /// **'PDF olarak paylaş'**
  String get shareAsPdf;

  /// No description provided for @unsubscribe.
  ///
  /// In tr, this message translates to:
  /// **'Abonelikten Çık'**
  String get unsubscribe;

  /// No description provided for @showAllHeaders.
  ///
  /// In tr, this message translates to:
  /// **'Tüm başlıkları göster'**
  String get showAllHeaders;

  /// No description provided for @showRawMime.
  ///
  /// In tr, this message translates to:
  /// **'Ham MIME göster'**
  String get showRawMime;

  /// No description provided for @thisEmailNoLongerExists.
  ///
  /// In tr, this message translates to:
  /// **'Bu e-posta artık mevcut değil.'**
  String get thisEmailNoLongerExists;

  /// No description provided for @messageActions.
  ///
  /// In tr, this message translates to:
  /// **'İleti işlemleri'**
  String get messageActions;

  /// No description provided for @from2.
  ///
  /// In tr, this message translates to:
  /// **'Kimden: '**
  String get from2;

  /// No description provided for @to2.
  ///
  /// In tr, this message translates to:
  /// **'Alıcı: '**
  String get to2;

  /// No description provided for @cc.
  ///
  /// In tr, this message translates to:
  /// **'Cc: '**
  String get cc;

  /// No description provided for @bcc.
  ///
  /// In tr, this message translates to:
  /// **'Bcc: '**
  String get bcc;

  /// No description provided for @date.
  ///
  /// In tr, this message translates to:
  /// **'Tarih: '**
  String get date;

  /// No description provided for @signedByNotVerified.
  ///
  /// In tr, this message translates to:
  /// **'{value} imzalı (doğrulanmadı)'**
  String signedByNotVerified(Object value);

  /// No description provided for @encryptedByCantBeOpened.
  ///
  /// In tr, this message translates to:
  /// **'{value} şifreli (açılamıyor)'**
  String encryptedByCantBeOpened(Object value);

  /// No description provided for @trackingContentBlocked.
  ///
  /// In tr, this message translates to:
  /// **'Takip içeriği engellendi'**
  String get trackingContentBlocked;

  /// No description provided for @attachments.
  ///
  /// In tr, this message translates to:
  /// **'Ekler'**
  String get attachments;

  /// No description provided for @replyAll2.
  ///
  /// In tr, this message translates to:
  /// **'Tümünü yanıtla'**
  String get replyAll2;

  /// No description provided for @noRecipients.
  ///
  /// In tr, this message translates to:
  /// **'alıcı yok'**
  String get noRecipients;

  /// No description provided for @youCanPinAtMost.
  ///
  /// In tr, this message translates to:
  /// **'En fazla 3 mail sabitlenebilir.'**
  String get youCanPinAtMost;

  /// No description provided for @emailMovedTo.
  ///
  /// In tr, this message translates to:
  /// **'E-posta {label} klasörüne taşındı.'**
  String emailMovedTo(Object label);

  /// No description provided for @emailRestored.
  ///
  /// In tr, this message translates to:
  /// **'E-posta geri yüklendi.'**
  String get emailRestored;

  /// No description provided for @emailMarkedAsNotSpam.
  ///
  /// In tr, this message translates to:
  /// **'E-posta spam değil olarak işaretlendi.'**
  String get emailMarkedAsNotSpam;

  /// No description provided for @emailUnarchived.
  ///
  /// In tr, this message translates to:
  /// **'E-posta arşivden çıkarıldı.'**
  String get emailUnarchived;

  /// No description provided for @emailPermanentlyDeleted.
  ///
  /// In tr, this message translates to:
  /// **'E-posta kalıcı olarak silindi.'**
  String get emailPermanentlyDeleted;

  /// No description provided for @unsubscribe2.
  ///
  /// In tr, this message translates to:
  /// **'Abonelikten çıkılsın mı?'**
  String get unsubscribe2;

  /// No description provided for @aRequestWillBeSent.
  ///
  /// In tr, this message translates to:
  /// **'Bu gönderenden e-posta almayı durdurmak için bir istek gönderilecek. Bu işlem geri alınamaz.'**
  String get aRequestWillBeSent;

  /// No description provided for @unsubscribeStarted.
  ///
  /// In tr, this message translates to:
  /// **'Abonelikten çıkma işlemi açıldı.'**
  String get unsubscribeStarted;

  /// No description provided for @unsubscribingFailed.
  ///
  /// In tr, this message translates to:
  /// **'Abonelikten çıkma işlemi başarısız oldu.'**
  String get unsubscribingFailed;

  /// No description provided for @printingFailed.
  ///
  /// In tr, this message translates to:
  /// **'Yazdırma başarısız: {value}'**
  String printingFailed(Object value);

  /// No description provided for @sharingThePdfFailed.
  ///
  /// In tr, this message translates to:
  /// **'PDF paylaşma başarısız: {value}'**
  String sharingThePdfFailed(Object value);

  /// No description provided for @couldntPrepareTheReply.
  ///
  /// In tr, this message translates to:
  /// **'Yanıt hazırlanamadı: {value}'**
  String couldntPrepareTheReply(Object value);

  /// No description provided for @forwardedMessageFromSubject.
  ///
  /// In tr, this message translates to:
  /// **'\n\n--- İletilen mesaj ---\nKimden: {sender}\n{dateLine}Konu: {subject}\n\n{bodyText}'**
  String forwardedMessageFromSubject(
    Object sender,
    Object dateLine,
    Object subject,
    Object bodyText,
  );

  /// No description provided for @forwardedMessageFromSubject2.
  ///
  /// In tr, this message translates to:
  /// **'<p><br></p><p>--- İletilen mesaj ---<br><strong>Kimden:</strong> {value}<br>{value2}<strong>Konu:</strong> {value3}</p>{originalHtml}'**
  String forwardedMessageFromSubject2(
    Object value,
    Object value2,
    Object value3,
    Object originalHtml,
  );

  /// No description provided for @allHeaders.
  ///
  /// In tr, this message translates to:
  /// **'Tüm başlıklar'**
  String get allHeaders;

  /// No description provided for @rawMime.
  ///
  /// In tr, this message translates to:
  /// **'Ham MIME'**
  String get rawMime;

  /// No description provided for @signatureVerification.
  ///
  /// In tr, this message translates to:
  /// **'İmza doğrulaması'**
  String get signatureVerification;

  /// No description provided for @couldntGetTheMessageSource.
  ///
  /// In tr, this message translates to:
  /// **'İleti kaynağı alınamadı: {value}'**
  String couldntGetTheMessageSource(Object value);

  /// No description provided for @signatureAndCertificateChainVerified.
  ///
  /// In tr, this message translates to:
  /// **'İmza ve sertifika zinciri doğrulandı'**
  String get signatureAndCertificateChainVerified;

  /// No description provided for @signatureMatchesCertificateIsntTrusted.
  ///
  /// In tr, this message translates to:
  /// **'İmza eşleşiyor; sertifika güvenilir değil'**
  String get signatureMatchesCertificateIsntTrusted;

  /// No description provided for @signatureIsInvalid.
  ///
  /// In tr, this message translates to:
  /// **'İmza geçersiz'**
  String get signatureIsInvalid;

  /// No description provided for @signatureCouldntBeVerified.
  ///
  /// In tr, this message translates to:
  /// **'İmza doğrulanamadı'**
  String get signatureCouldntBeVerified;

  /// No description provided for @openpgpKeyManagementAndVerification.
  ///
  /// In tr, this message translates to:
  /// **'OpenPGP anahtar yönetimi ve doğrulaması desteklenmiyor.'**
  String get openpgpKeyManagementAndVerification;

  /// No description provided for @unknownSigner.
  ///
  /// In tr, this message translates to:
  /// **'Bilinmeyen imzacı'**
  String get unknownSigner;

  /// No description provided for @signatureDate.
  ///
  /// In tr, this message translates to:
  /// **'İmza tarihi: {value}'**
  String signatureDate(Object value);

  /// No description provided for @certificateExpires.
  ///
  /// In tr, this message translates to:
  /// **'Sertifika bitişi: {value}'**
  String certificateExpires(Object value);

  /// No description provided for @accountNotifications.
  ///
  /// In tr, this message translates to:
  /// **'Hesap bildirimleri'**
  String get accountNotifications;

  /// No description provided for @theseSettingsApplyOnEvery.
  ///
  /// In tr, this message translates to:
  /// **'Bu ayarlar hesabın oturum açık olduğu tüm cihazlarda geçerlidir. Bu cihazdaki bildirimleri Ayarlar > Genel ayarlar > Bildirimler ile kapatabilirsiniz.'**
  String get theseSettingsApplyOnEvery;

  /// No description provided for @notifications.
  ///
  /// In tr, this message translates to:
  /// **'Bildirimler'**
  String get notifications;

  /// No description provided for @inboxOnly.
  ///
  /// In tr, this message translates to:
  /// **'Yalnızca Gelen Kutusu'**
  String get inboxOnly;

  /// No description provided for @whenOffSyncedFoldersOther.
  ///
  /// In tr, this message translates to:
  /// **'Kapalıyken Gönderilmiş, Taslaklar, Çöp ve Spam dışındaki senkronize klasörler de bildirilir.'**
  String get whenOffSyncedFoldersOther;

  /// No description provided for @lockScreenPrivacy.
  ///
  /// In tr, this message translates to:
  /// **'Kilit ekranı gizliliği'**
  String get lockScreenPrivacy;

  /// No description provided for @notificationsAreSentAsPrivate.
  ///
  /// In tr, this message translates to:
  /// **'Sunucu önizlemeleri kapattığı için bildirimler Gizli olarak gönderilir.'**
  String get notificationsAreSentAsPrivate;

  /// No description provided for @editMessage.
  ///
  /// In tr, this message translates to:
  /// **'Gönderiyi Düzenle'**
  String get editMessage;

  /// No description provided for @newMessage.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Gönderi'**
  String get newMessage;

  /// No description provided for @createANewMessage.
  ///
  /// In tr, this message translates to:
  /// **'Yeni gönderi oluştur?'**
  String get createANewMessage;

  /// No description provided for @checkSentFirstThisMessage.
  ///
  /// In tr, this message translates to:
  /// **'Önce Gönderilenler’i kontrol edin. Bu mesaj daha önce teslim edilmiş olabilir; yeniden göndermek alıcıya ikinci bir kopya ulaştırabilir.'**
  String get checkSentFirstThisMessage;

  /// No description provided for @newMessage2.
  ///
  /// In tr, this message translates to:
  /// **'Yeni gönderi'**
  String get newMessage2;

  /// No description provided for @deleteMessage.
  ///
  /// In tr, this message translates to:
  /// **'Gönderiyi sil?'**
  String get deleteMessage;

  /// No description provided for @theDeliveryResultIsUnknown.
  ///
  /// In tr, this message translates to:
  /// **'Gönderim sonucu bilinmiyor. Önce Gönderilenler’i kontrol edin. Yerel kopya silinsin mi?'**
  String get theDeliveryResultIsUnknown;

  /// No description provided for @theLocalCopyOfThis.
  ///
  /// In tr, this message translates to:
  /// **'Bu gönderinin yerel kopyası kalıcı olarak silinecek.'**
  String get theLocalCopyOfThis;

  /// No description provided for @noPendingMessages.
  ///
  /// In tr, this message translates to:
  /// **'Bekleyen gönderi yok.'**
  String get noPendingMessages;

  /// No description provided for @undoPeriod.
  ///
  /// In tr, this message translates to:
  /// **'Geri alma süresi'**
  String get undoPeriod;

  /// No description provided for @sending.
  ///
  /// In tr, this message translates to:
  /// **'Gönderiliyor'**
  String get sending;

  /// No description provided for @waitingForConnection.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı bekleniyor'**
  String get waitingForConnection;

  /// No description provided for @couldntSend.
  ///
  /// In tr, this message translates to:
  /// **'Gönderilemedi'**
  String get couldntSend;

  /// No description provided for @resultUnknown.
  ///
  /// In tr, this message translates to:
  /// **'Sonuç belirsiz'**
  String get resultUnknown;

  /// No description provided for @to3.
  ///
  /// In tr, this message translates to:
  /// **'Kime: {value}'**
  String to3(Object value);

  /// No description provided for @noInternetConnectionItWillBeSentAutomatically.
  ///
  /// In tr, this message translates to:
  /// **'İnternet bağlantısı yok. Bağlantı gelince otomatik gönderilecek.'**
  String get noInternetConnectionItWillBeSentAutomatically;

  /// No description provided for @checkSentBeforeSendingAgain.
  ///
  /// In tr, this message translates to:
  /// **'Tekrar göndermeden önce Gönderilenler’i kontrol edin.'**
  String get checkSentBeforeSendingAgain;

  /// No description provided for @tryNow.
  ///
  /// In tr, this message translates to:
  /// **'Şimdi dene'**
  String get tryNow;

  /// No description provided for @edit.
  ///
  /// In tr, this message translates to:
  /// **'Düzenle'**
  String get edit;

  /// No description provided for @recreateManually.
  ///
  /// In tr, this message translates to:
  /// **'Elle yeniden oluştur'**
  String get recreateManually;

  /// No description provided for @viewContent.
  ///
  /// In tr, this message translates to:
  /// **'İçeriği görüntüle'**
  String get viewContent;

  /// No description provided for @scheduledSends.
  ///
  /// In tr, this message translates to:
  /// **'Zamanlanmış Gönderimler'**
  String get scheduledSends;

  /// No description provided for @scheduled.
  ///
  /// In tr, this message translates to:
  /// **'Zamanlandı'**
  String get scheduled;

  /// No description provided for @sent2.
  ///
  /// In tr, this message translates to:
  /// **'Gönderildi'**
  String get sent2;

  /// No description provided for @cancelled.
  ///
  /// In tr, this message translates to:
  /// **'İptal edildi'**
  String get cancelled;

  /// No description provided for @resultUnknownCheckSent.
  ///
  /// In tr, this message translates to:
  /// **'Sonuç belirsiz — Gönderilenler’i kontrol edin'**
  String get resultUnknownCheckSent;

  /// No description provided for @cancelScheduledSend.
  ///
  /// In tr, this message translates to:
  /// **'Zamanlanmış gönderimi iptal et'**
  String get cancelScheduledSend;

  /// No description provided for @cancelTheSendOf.
  ///
  /// In tr, this message translates to:
  /// **'\"{value}\" gönderimi iptal edilsin mi?'**
  String cancelTheSendOf(Object value);

  /// No description provided for @cancelSend.
  ///
  /// In tr, this message translates to:
  /// **'İptal Et'**
  String get cancelSend;

  /// No description provided for @sendCancelled.
  ///
  /// In tr, this message translates to:
  /// **'Gönderim iptal edildi.'**
  String get sendCancelled;

  /// No description provided for @chooseAtLeastOneRecipient.
  ///
  /// In tr, this message translates to:
  /// **'En az bir alıcı ve ileri bir tarih seçin.'**
  String get chooseAtLeastOneRecipient;

  /// No description provided for @scheduledSendUpdated.
  ///
  /// In tr, this message translates to:
  /// **'Zamanlanmış gönderim güncellendi.'**
  String get scheduledSendUpdated;

  /// No description provided for @sendReQueued.
  ///
  /// In tr, this message translates to:
  /// **'Gönderim yeniden kuyruğa alındı.'**
  String get sendReQueued;

  /// No description provided for @failedSend.
  ///
  /// In tr, this message translates to:
  /// **'Başarısız gönderim'**
  String get failedSend;

  /// No description provided for @editScheduledSend.
  ///
  /// In tr, this message translates to:
  /// **'Zamanlanmışı düzenle'**
  String get editScheduledSend;

  /// No description provided for @sendFailed.
  ///
  /// In tr, this message translates to:
  /// **'Gönderim başarısız'**
  String get sendFailed;

  /// No description provided for @recipients.
  ///
  /// In tr, this message translates to:
  /// **'Alıcılar'**
  String get recipients;

  /// No description provided for @content.
  ///
  /// In tr, this message translates to:
  /// **'İçerik'**
  String get content;

  /// No description provided for @body.
  ///
  /// In tr, this message translates to:
  /// **'Gövde'**
  String get body;

  /// No description provided for @sendTime.
  ///
  /// In tr, this message translates to:
  /// **'Gönderim zamanı'**
  String get sendTime;

  /// No description provided for @addAttachment.
  ///
  /// In tr, this message translates to:
  /// **'Ek ekle'**
  String get addAttachment;

  /// No description provided for @retry.
  ///
  /// In tr, this message translates to:
  /// **'Yeniden dene'**
  String get retry;

  /// No description provided for @cancelSend2.
  ///
  /// In tr, this message translates to:
  /// **'Gönderimi iptal et'**
  String get cancelSend2;

  /// No description provided for @noScheduledSends.
  ///
  /// In tr, this message translates to:
  /// **'Zamanlanmış gönderim yok'**
  String get noScheduledSends;

  /// No description provided for @scheduleASendWithThe.
  ///
  /// In tr, this message translates to:
  /// **'Yazarken \"Gönder\" yanındaki oktan bir gönderim zamanlayınca burada görünür.'**
  String get scheduleASendWithThe;

  /// No description provided for @newEmailsAdded.
  ///
  /// In tr, this message translates to:
  /// **'Sunucu taraması tamamlandı. {imported} yeni e-posta eklendi.'**
  String newEmailsAdded(int imported);

  /// No description provided for @scanningTheServer.
  ///
  /// In tr, this message translates to:
  /// **'Sunucu taranıyor… {imported} yeni e-posta eklendi; {remaining} eşleşme kaldı.'**
  String scanningTheServer(int imported, Object remaining);

  /// No description provided for @serverScanStopped.
  ///
  /// In tr, this message translates to:
  /// **'Sunucu taraması durdu. {imported} yeni e-posta eklendi; {remaining} eşleşme alınamadı. Yeniden deneyin.'**
  String serverScanStopped(int imported, Object remaining);

  /// No description provided for @searchEmail.
  ///
  /// In tr, this message translates to:
  /// **'E-posta ara'**
  String get searchEmail;

  /// No description provided for @clear.
  ///
  /// In tr, this message translates to:
  /// **'Temizle'**
  String get clear;

  /// No description provided for @filters.
  ///
  /// In tr, this message translates to:
  /// **'Filtreler'**
  String get filters;

  /// No description provided for @searchingTheServer.
  ///
  /// In tr, this message translates to:
  /// **'Sunucuda aranıyor…'**
  String get searchingTheServer;

  /// No description provided for @startTypingToSearch.
  ///
  /// In tr, this message translates to:
  /// **'Aramak için yazmaya başlayın.'**
  String get startTypingToSearch;

  /// No description provided for @noResultsMatchTheSelected.
  ///
  /// In tr, this message translates to:
  /// **'Seçili filtrelerle eşleşen sonuç yok.'**
  String get noResultsMatchTheSelected;

  /// No description provided for @noResultsFor.
  ///
  /// In tr, this message translates to:
  /// **'“{value}” için sonuç yok.'**
  String noResultsFor(Object value);

  /// No description provided for @theMailboxIsStillSyncing.
  ///
  /// In tr, this message translates to:
  /// **'Posta kutusu hâlâ senkronize ediliyor. Arama sonuçları eksik olabilir.'**
  String get theMailboxIsStillSyncing;

  /// No description provided for @folder2.
  ///
  /// In tr, this message translates to:
  /// **'Klasör: {label}'**
  String folder2(Object label);

  /// No description provided for @folder3.
  ///
  /// In tr, this message translates to:
  /// **'Klasör: {name}'**
  String folder3(Object name);

  /// No description provided for @from3.
  ///
  /// In tr, this message translates to:
  /// **'Başlangıç: {value}'**
  String from3(Object value);

  /// No description provided for @to4.
  ///
  /// In tr, this message translates to:
  /// **'Bitiş: {value}'**
  String to4(Object value);

  /// No description provided for @read.
  ///
  /// In tr, this message translates to:
  /// **'Okundu'**
  String get read;

  /// No description provided for @unread2.
  ///
  /// In tr, this message translates to:
  /// **'Okunmadı'**
  String get unread2;

  /// No description provided for @starred2.
  ///
  /// In tr, this message translates to:
  /// **'Yıldızlı'**
  String get starred2;

  /// No description provided for @clearFilters.
  ///
  /// In tr, this message translates to:
  /// **'Filtreleri Temizle'**
  String get clearFilters;

  /// No description provided for @advancedFilters.
  ///
  /// In tr, this message translates to:
  /// **'Gelişmiş Filtreler'**
  String get advancedFilters;

  /// No description provided for @account.
  ///
  /// In tr, this message translates to:
  /// **'Hesap'**
  String get account;

  /// No description provided for @allAccounts.
  ///
  /// In tr, this message translates to:
  /// **'Tüm hesaplar'**
  String get allAccounts;

  /// No description provided for @all.
  ///
  /// In tr, this message translates to:
  /// **'Tümü'**
  String get all;

  /// No description provided for @eGNameCompanyCom.
  ///
  /// In tr, this message translates to:
  /// **'ör. ad@sirket.com'**
  String get eGNameCompanyCom;

  /// No description provided for @dateRange.
  ///
  /// In tr, this message translates to:
  /// **'Tarih Aralığı'**
  String get dateRange;

  /// No description provided for @start.
  ///
  /// In tr, this message translates to:
  /// **'Başlangıç'**
  String get start;

  /// No description provided for @end.
  ///
  /// In tr, this message translates to:
  /// **'Bitiş'**
  String get end;

  /// No description provided for @status.
  ///
  /// In tr, this message translates to:
  /// **'Durum'**
  String get status;

  /// No description provided for @any.
  ///
  /// In tr, this message translates to:
  /// **'Herhangi'**
  String get any;

  /// No description provided for @hasAttachment.
  ///
  /// In tr, this message translates to:
  /// **'Ek var'**
  String get hasAttachment;

  /// No description provided for @apply.
  ///
  /// In tr, this message translates to:
  /// **'Uygula'**
  String get apply;

  /// No description provided for @filtersAreCombinedWithAnd.
  ///
  /// In tr, this message translates to:
  /// **'Filtreler VE ile birleştirilir.'**
  String get filtersAreCombinedWithAnd;

  /// No description provided for @startTypingToSearchOr.
  ///
  /// In tr, this message translates to:
  /// **'Aramak veya filtrelemek için yazmaya başlayın'**
  String get startTypingToSearchOr;

  /// No description provided for @searchingTheServerAcrossAll.
  ///
  /// In tr, this message translates to:
  /// **'Tüm hesaplarda sunucuda aranıyor'**
  String get searchingTheServerAcrossAll;

  /// No description provided for @searchingIn.
  ///
  /// In tr, this message translates to:
  /// **'{accountEmail} hesabında aranıyor'**
  String searchingIn(Object accountEmail);

  /// No description provided for @accountSettings.
  ///
  /// In tr, this message translates to:
  /// **'Hesap ayarları'**
  String get accountSettings;

  /// No description provided for @theAccountIsNoLonger.
  ///
  /// In tr, this message translates to:
  /// **'Hesap artık bağlı değil.'**
  String get theAccountIsNoLonger;

  /// No description provided for @signatures.
  ///
  /// In tr, this message translates to:
  /// **'İmzalar'**
  String get signatures;

  /// No description provided for @createEmailSignaturesAndChoose.
  ///
  /// In tr, this message translates to:
  /// **'E-posta imzalarını oluştur ve varsayılanını seç'**
  String get createEmailSignaturesAndChoose;

  /// No description provided for @savedTexts2.
  ///
  /// In tr, this message translates to:
  /// **'Hazır metinler'**
  String get savedTexts2;

  /// No description provided for @reusableSubjectsAndTexts.
  ///
  /// In tr, this message translates to:
  /// **'Tekrar kullanılan konu ve metinler'**
  String get reusableSubjectsAndTexts;

  /// No description provided for @labels.
  ///
  /// In tr, this message translates to:
  /// **'Etiketler'**
  String get labels;

  /// No description provided for @createEditAndDeleteLabels.
  ///
  /// In tr, this message translates to:
  /// **'Etiket oluştur, düzenle, sil'**
  String get createEditAndDeleteLabels;

  /// No description provided for @contacts.
  ///
  /// In tr, this message translates to:
  /// **'Kişiler'**
  String get contacts;

  /// No description provided for @contactsSuggestedWhileTyping.
  ///
  /// In tr, this message translates to:
  /// **'Yazarken önerilecek kişiler'**
  String get contactsSuggestedWhileTyping;

  /// No description provided for @folderTreeRolesAndSync.
  ///
  /// In tr, this message translates to:
  /// **'Klasör ağacı, roller ve eşitleme'**
  String get folderTreeRolesAndSync;

  /// No description provided for @syncLabel.
  ///
  /// In tr, this message translates to:
  /// **'Eşitleme'**
  String get syncLabel;

  /// No description provided for @perFolderStatusAndFolders.
  ///
  /// In tr, this message translates to:
  /// **'Klasör bazlı durum ve eşitlenecek klasörler'**
  String get perFolderStatusAndFolders;

  /// No description provided for @folderScopeAndLockScreen.
  ///
  /// In tr, this message translates to:
  /// **'Klasör kapsamı ve kilit ekranı gizliliği'**
  String get folderScopeAndLockScreen;

  /// No description provided for @savedImagePreferences.
  ///
  /// In tr, this message translates to:
  /// **'Kayıtlı görsel tercihleri'**
  String get savedImagePreferences;

  /// No description provided for @trustedSendersAndDomains.
  ///
  /// In tr, this message translates to:
  /// **'Güvenilir gönderici ve alan adları'**
  String get trustedSendersAndDomains;

  /// No description provided for @security.
  ///
  /// In tr, this message translates to:
  /// **'Güvenlik'**
  String get security;

  /// No description provided for @connectedDevices.
  ///
  /// In tr, this message translates to:
  /// **'Bağlı cihazlar'**
  String get connectedDevices;

  /// No description provided for @devicesAndSessionsSignedIn.
  ///
  /// In tr, this message translates to:
  /// **'Bu hesaba giriş yapmış cihazlar ve oturumlar'**
  String get devicesAndSessionsSignedIn;

  /// No description provided for @disconnected.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantısı kesildi'**
  String get disconnected;

  /// No description provided for @connectionProblem.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı sorunu'**
  String get connectionProblem;

  /// No description provided for @disabled.
  ///
  /// In tr, this message translates to:
  /// **'Devre dışı'**
  String get disabled;

  /// No description provided for @updatePassword.
  ///
  /// In tr, this message translates to:
  /// **'Şifreyi güncelle'**
  String get updatePassword;

  /// No description provided for @signOutOnThisDevice.
  ///
  /// In tr, this message translates to:
  /// **'Bu cihazdan çıkış yap'**
  String get signOutOnThisDevice;

  /// No description provided for @theAccountStaysOnThe.
  ///
  /// In tr, this message translates to:
  /// **'Hesap sunucuda kalır; yalnızca bu cihazdaki oturum ve veriler silinir.'**
  String get theAccountStaysOnThe;

  /// No description provided for @signOut.
  ///
  /// In tr, this message translates to:
  /// **'Çıkış yapılsın mı?'**
  String get signOut;

  /// No description provided for @willBeSignedOutOn.
  ///
  /// In tr, this message translates to:
  /// **'{email} bu cihazdan çıkarılacak. Sunucudaki hesap ve e-postalar silinmez.'**
  String willBeSignedOutOn(Object email);

  /// No description provided for @signOut2.
  ///
  /// In tr, this message translates to:
  /// **'Çıkış yap'**
  String get signOut2;

  /// No description provided for @removeAccount.
  ///
  /// In tr, this message translates to:
  /// **'Hesabı kaldır'**
  String get removeAccount;

  /// No description provided for @deletesTheConnectionFromThe.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantıyı sunucudan siler; e-postalar bu uygulamadan kaldırılır.'**
  String get deletesTheConnectionFromThe;

  /// No description provided for @removeAccount2.
  ///
  /// In tr, this message translates to:
  /// **'Hesap kaldırılsın mı?'**
  String get removeAccount2;

  /// No description provided for @willBeRemovedAndIts.
  ///
  /// In tr, this message translates to:
  /// **'{email} kaldırılacak ve bu hesaba ait e-postalar uygulamadan silinecek. Emin misiniz?'**
  String willBeRemovedAndIts(Object email);

  /// No description provided for @storage.
  ///
  /// In tr, this message translates to:
  /// **'Depolama'**
  String get storage;

  /// No description provided for @ofUsed.
  ///
  /// In tr, this message translates to:
  /// **'{value} / {value2} kullanılıyor (%{usedPercent})'**
  String ofUsed(Object value, Object value2, Object usedPercent);

  /// No description provided for @storageUsage.
  ///
  /// In tr, this message translates to:
  /// **'Depolama kullanımı'**
  String get storageUsage;

  /// No description provided for @noContactsAddedYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz kişi eklenmedi.'**
  String get noContactsAddedYet;

  /// No description provided for @newContact.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Kişi'**
  String get newContact;

  /// No description provided for @deleteContact.
  ///
  /// In tr, this message translates to:
  /// **'Kişiyi sil?'**
  String get deleteContact;

  /// No description provided for @willBeRemovedFromThe.
  ///
  /// In tr, this message translates to:
  /// **'“{value}” kişi listesinden kaldırılacak.'**
  String willBeRemovedFromThe(Object value);

  /// No description provided for @yesDelete.
  ///
  /// In tr, this message translates to:
  /// **'Evet, sil'**
  String get yesDelete;

  /// No description provided for @editContact.
  ///
  /// In tr, this message translates to:
  /// **'Kişiyi Düzenle'**
  String get editContact;

  /// No description provided for @nameOptional.
  ///
  /// In tr, this message translates to:
  /// **'Ad (isteğe bağlı)'**
  String get nameOptional;

  /// No description provided for @contactsPermissionWasntGrantedSuggestions.
  ///
  /// In tr, this message translates to:
  /// **'Kişilere erişim izni verilmedi. Öneriler mail geçmişinden ve eklediğiniz kişilerden gelmeye devam eder.'**
  String get contactsPermissionWasntGrantedSuggestions;

  /// No description provided for @suggestDeviceContacts.
  ///
  /// In tr, this message translates to:
  /// **'Cihaz kişilerini öner'**
  String get suggestDeviceContacts;

  /// No description provided for @alsoSuggestsEmailAddressesFrom.
  ///
  /// In tr, this message translates to:
  /// **'Alıcı yazarken telefon rehberindeki e-posta adreslerini de önerir. Rehber yalnızca bu cihazda okunur, sunucuya gönderilmez.'**
  String get alsoSuggestsEmailAddressesFrom;

  /// No description provided for @showNewEmailNotificationsOn.
  ///
  /// In tr, this message translates to:
  /// **'Bu cihazda yeni e-posta bildirimlerini göster. Klasör kapsamı ve kilit ekranı gizliliği her hesabın kendi ayarlarındadır.'**
  String get showNewEmailNotificationsOn;

  /// No description provided for @followsTheDeviceTheme.
  ///
  /// In tr, this message translates to:
  /// **'Cihazın temasını izler'**
  String get followsTheDeviceTheme;

  /// No description provided for @light.
  ///
  /// In tr, this message translates to:
  /// **'Açık'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In tr, this message translates to:
  /// **'Koyu'**
  String get dark;

  /// No description provided for @swipeGestures.
  ///
  /// In tr, this message translates to:
  /// **'Kaydırma hareketleri'**
  String get swipeGestures;

  /// No description provided for @swipeAnEmailRightOr.
  ///
  /// In tr, this message translates to:
  /// **'Listede e-postayı sağa veya sola kaydırarak aşağıdaki işlemleri yapın. Çöp, Spam ve Arşiv klasörleri kendi işlemlerini kullanır.'**
  String get swipeAnEmailRightOr;

  /// No description provided for @onSwipeRight.
  ///
  /// In tr, this message translates to:
  /// **'Sağa kaydırınca'**
  String get onSwipeRight;

  /// No description provided for @onSwipeLeft.
  ///
  /// In tr, this message translates to:
  /// **'Sola kaydırınca'**
  String get onSwipeLeft;

  /// No description provided for @undoSendPeriod.
  ///
  /// In tr, this message translates to:
  /// **'Göndermeyi geri alma süresi'**
  String get undoSendPeriod;

  /// No description provided for @blue.
  ///
  /// In tr, this message translates to:
  /// **'Mavi'**
  String get blue;

  /// No description provided for @green.
  ///
  /// In tr, this message translates to:
  /// **'Yeşil'**
  String get green;

  /// No description provided for @orange.
  ///
  /// In tr, this message translates to:
  /// **'Turuncu'**
  String get orange;

  /// No description provided for @darkRed.
  ///
  /// In tr, this message translates to:
  /// **'Koyu kırmızı'**
  String get darkRed;

  /// No description provided for @red.
  ///
  /// In tr, this message translates to:
  /// **'Kırmızı'**
  String get red;

  /// No description provided for @turquoise.
  ///
  /// In tr, this message translates to:
  /// **'Turkuaz'**
  String get turquoise;

  /// No description provided for @purple.
  ///
  /// In tr, this message translates to:
  /// **'Menekşe'**
  String get purple;

  /// No description provided for @redOrange.
  ///
  /// In tr, this message translates to:
  /// **'Kırmızı-turuncu'**
  String get redOrange;

  /// No description provided for @newLabel.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Etiket'**
  String get newLabel;

  /// No description provided for @customColor.
  ///
  /// In tr, this message translates to:
  /// **'Özel renk {value}'**
  String customColor(Object value);

  /// No description provided for @chooseCustomColor.
  ///
  /// In tr, this message translates to:
  /// **'Özel renk seç'**
  String get chooseCustomColor;

  /// No description provided for @deleteLabel.
  ///
  /// In tr, this message translates to:
  /// **'Etiketi sil?'**
  String get deleteLabel;

  /// No description provided for @theLabelWillBeRemoved.
  ///
  /// In tr, this message translates to:
  /// **'“{value}” etiketi kaldırılacak. E-postalar silinmez, yalnızca bu etiket onlardan çıkarılır.'**
  String theLabelWillBeRemoved(Object value);

  /// No description provided for @editLabel.
  ///
  /// In tr, this message translates to:
  /// **'Etiketi Düzenle'**
  String get editLabel;

  /// No description provided for @name.
  ///
  /// In tr, this message translates to:
  /// **'Ad'**
  String get name;

  /// No description provided for @create.
  ///
  /// In tr, this message translates to:
  /// **'Oluştur'**
  String get create;

  /// No description provided for @apiConnection.
  ///
  /// In tr, this message translates to:
  /// **'API bağlantısı'**
  String get apiConnection;

  /// No description provided for @checkingConnection.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı kontrol ediliyor…'**
  String get checkingConnection;

  /// No description provided for @serverAndServicesAreReady.
  ///
  /// In tr, this message translates to:
  /// **'Sunucu ve servisler hazır'**
  String get serverAndServicesAreReady;

  /// No description provided for @couldntConnect.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı kurulamadı'**
  String get couldntConnect;

  /// No description provided for @checkConnectionAgain.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantıyı yeniden kontrol et'**
  String get checkConnectionAgain;

  /// No description provided for @sync.
  ///
  /// In tr, this message translates to:
  /// **'Senkronizasyon'**
  String get sync;

  /// No description provided for @serverConnection.
  ///
  /// In tr, this message translates to:
  /// **'Sunucu bağlantısı'**
  String get serverConnection;

  /// No description provided for @thisSettingOnlyControlsHow.
  ///
  /// In tr, this message translates to:
  /// **'Bu ayar yalnızca uygulama açıkken görünen listeyi ne sıklıkla yenileyeceğinizi belirler. Sunucu, bu ayardan bağımsız olarak e-postalarınızı düzenli aralıklarla arka planda zaten senkronize eder; yeni posta bildirimleri bu ayarı beklemez.'**
  String get thisSettingOnlyControlsHow;

  /// No description provided for @autoRefreshNetwork.
  ///
  /// In tr, this message translates to:
  /// **'Otomatik yenileme ağı'**
  String get autoRefreshNetwork;

  /// No description provided for @pauseOnBatterySaver.
  ///
  /// In tr, this message translates to:
  /// **'Pil tasarrufunda duraklat'**
  String get pauseOnBatterySaver;

  /// No description provided for @whenBatterySaverIsOn.
  ///
  /// In tr, this message translates to:
  /// **'Pil tasarrufu açıkken otomatik yenileme yapılmaz; aşağı çekerek yenileme ve bildirimler çalışmaya devam eder.'**
  String get whenBatterySaverIsOn;

  /// No description provided for @clearAttachmentCache.
  ///
  /// In tr, this message translates to:
  /// **'Ek önbelleğini temizle?'**
  String get clearAttachmentCache;

  /// No description provided for @downloadedAttachmentsTakingUpWill.
  ///
  /// In tr, this message translates to:
  /// **'{_sizeLabel} boyutundaki indirilen ekler silinecek.'**
  String downloadedAttachmentsTakingUpWill(Object _sizeLabel);

  /// No description provided for @attachmentCacheCleared.
  ///
  /// In tr, this message translates to:
  /// **'Ek önbelleği temizlendi.'**
  String get attachmentCacheCleared;

  /// No description provided for @attachmentsAreDownloadedAutomaticallyOnly.
  ///
  /// In tr, this message translates to:
  /// **'Ekler yalnızca posta açıldığında, seçilen ağda ve boyut sınırının altındaysa otomatik indirilir.'**
  String get attachmentsAreDownloadedAutomaticallyOnly;

  /// No description provided for @autoDownloadLimit.
  ///
  /// In tr, this message translates to:
  /// **'Otomatik indirme sınırı: {label}'**
  String autoDownloadLimit(Object label);

  /// No description provided for @clearAttachmentCache2.
  ///
  /// In tr, this message translates to:
  /// **'Ek önbelleğini temizle'**
  String get clearAttachmentCache2;

  /// No description provided for @calculatingSize.
  ///
  /// In tr, this message translates to:
  /// **'Boyut hesaplanıyor…'**
  String get calculatingSize;

  /// No description provided for @removeLinkTrackingParameters.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı takip parametrelerini temizle'**
  String get removeLinkTrackingParameters;

  /// No description provided for @removesKnownAdvertisingAndCampaign.
  ///
  /// In tr, this message translates to:
  /// **'E-postalardaki bağlantıları açmadan önce bilinen reklam ve kampanya takip parametrelerini kaldırır.'**
  String get removesKnownAdvertisingAndCampaign;

  /// No description provided for @appLock.
  ///
  /// In tr, this message translates to:
  /// **'Uygulama Kilidi'**
  String get appLock;

  /// No description provided for @asksForFingerprintFaceId.
  ///
  /// In tr, this message translates to:
  /// **'Uygulamayı açtığınızda ya da seçilen süreden uzun arka planda kaldıktan sonra parmak izi/Face ID veya cihaz şifresi ister.'**
  String get asksForFingerprintFaceId;

  /// No description provided for @lockWhenReturningFromBackground.
  ///
  /// In tr, this message translates to:
  /// **'Arka plandan dönünce kilitle'**
  String get lockWhenReturningFromBackground;

  /// No description provided for @screenProtection.
  ///
  /// In tr, this message translates to:
  /// **'Ekran Koruması'**
  String get screenProtection;

  /// No description provided for @hidesMailContentInThe.
  ///
  /// In tr, this message translates to:
  /// **'Uygulama geçiş ekranında posta içeriğini gizler.'**
  String get hidesMailContentInThe;

  /// No description provided for @blocksScreenshotsAndScreenRecording.
  ///
  /// In tr, this message translates to:
  /// **'Ekran görüntüsü ve ekran kaydını engeller, son kullanılan uygulamalar listesinde içeriği gizler.'**
  String get blocksScreenshotsAndScreenRecording;

  /// No description provided for @couldntLoadDevices.
  ///
  /// In tr, this message translates to:
  /// **'Cihazlar yüklenemedi: {value}'**
  String couldntLoadDevices(Object value);

  /// No description provided for @signOutOfThisSession.
  ///
  /// In tr, this message translates to:
  /// **'Oturumu kapat?'**
  String get signOutOfThisSession;

  /// No description provided for @theSessionOnThisDevice.
  ///
  /// In tr, this message translates to:
  /// **'Bu cihazdaki oturum kapatılacak ve bu hesaptan çıkış yapılacak.'**
  String get theSessionOnThisDevice;

  /// No description provided for @thisDeviceWillNoLonger.
  ///
  /// In tr, this message translates to:
  /// **'Bu cihaz artık bu hesaba erişemeyecek.'**
  String get thisDeviceWillNoLonger;

  /// No description provided for @couldntSignOut.
  ///
  /// In tr, this message translates to:
  /// **'Oturum kapatılamadı: {value}'**
  String couldntSignOut(Object value);

  /// No description provided for @noConnectedDevices.
  ///
  /// In tr, this message translates to:
  /// **'Bağlı cihaz yok.'**
  String get noConnectedDevices;

  /// No description provided for @lastUsed.
  ///
  /// In tr, this message translates to:
  /// **'Son kullanım: {value}'**
  String lastUsed(Object value);

  /// No description provided for @settings.
  ///
  /// In tr, this message translates to:
  /// **'Ayarlar'**
  String get settings;

  /// No description provided for @generalSettings.
  ///
  /// In tr, this message translates to:
  /// **'Genel ayarlar'**
  String get generalSettings;

  /// No description provided for @appearanceInteractionNotificationsNetworkAnd.
  ///
  /// In tr, this message translates to:
  /// **'Görüntü, etkileşim, bildirimler, ağ ve gizlilik'**
  String get appearanceInteractionNotificationsNetworkAnd;

  /// No description provided for @accounts.
  ///
  /// In tr, this message translates to:
  /// **'Hesaplar'**
  String get accounts;

  /// No description provided for @addAccount.
  ///
  /// In tr, this message translates to:
  /// **'Hesap ekle'**
  String get addAccount;

  /// No description provided for @connectANewMailAccount.
  ///
  /// In tr, this message translates to:
  /// **'Yeni posta hesabı bağla'**
  String get connectANewMailAccount;

  /// No description provided for @signatureLabelContactFolderAnd.
  ///
  /// In tr, this message translates to:
  /// **'İmza, etiket, kişi, klasör ve bildirim ayarları'**
  String get signatureLabelContactFolderAnd;

  /// No description provided for @disconnectedUpdateThePassword.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantısı kesildi — şifreyi güncelleyin'**
  String get disconnectedUpdateThePassword;

  /// No description provided for @appearance.
  ///
  /// In tr, this message translates to:
  /// **'Görüntü'**
  String get appearance;

  /// No description provided for @lightDarkOrSystemTheme.
  ///
  /// In tr, this message translates to:
  /// **'Açık, koyu veya sistem teması'**
  String get lightDarkOrSystemTheme;

  /// No description provided for @language.
  ///
  /// In tr, this message translates to:
  /// **'Dil'**
  String get language;

  /// No description provided for @tRkEOrEnglish.
  ///
  /// In tr, this message translates to:
  /// **'Türkçe veya English'**
  String get tRkEOrEnglish;

  /// No description provided for @interaction.
  ///
  /// In tr, this message translates to:
  /// **'Etkileşim'**
  String get interaction;

  /// No description provided for @swipeUndoSendAndDevice.
  ///
  /// In tr, this message translates to:
  /// **'Kaydırma, göndermeyi geri alma ve cihaz kişileri'**
  String get swipeUndoSendAndDevice;

  /// No description provided for @newEmailNotificationsOnThis.
  ///
  /// In tr, this message translates to:
  /// **'Bu cihazda yeni e-posta bildirimleri'**
  String get newEmailNotificationsOnThis;

  /// No description provided for @network.
  ///
  /// In tr, this message translates to:
  /// **'Ağ'**
  String get network;

  /// No description provided for @refreshAttachmentsAndServer.
  ///
  /// In tr, this message translates to:
  /// **'Yenileme, ekler ve sunucu'**
  String get refreshAttachmentsAndServer;

  /// No description provided for @privacy.
  ///
  /// In tr, this message translates to:
  /// **'Gizlilik'**
  String get privacy;

  /// No description provided for @appLockScreenProtectionAnd.
  ///
  /// In tr, this message translates to:
  /// **'Uygulama kilidi, ekran koruması ve bağlantılar'**
  String get appLockScreenProtectionAnd;

  /// No description provided for @deleteSignature.
  ///
  /// In tr, this message translates to:
  /// **'İmzayı sil?'**
  String get deleteSignature;

  /// No description provided for @theSignatureWillBePermanently.
  ///
  /// In tr, this message translates to:
  /// **'“{name}” imzası kalıcı olarak silinecek.'**
  String theSignatureWillBePermanently(Object name);

  /// No description provided for @none.
  ///
  /// In tr, this message translates to:
  /// **'Yok'**
  String get none;

  /// No description provided for @noConnectedAccountFound.
  ///
  /// In tr, this message translates to:
  /// **'Bağlı hesap bulunamadı.'**
  String get noConnectedAccountFound;

  /// No description provided for @newSignature.
  ///
  /// In tr, this message translates to:
  /// **'Yeni imza'**
  String get newSignature;

  /// No description provided for @newEmail2.
  ///
  /// In tr, this message translates to:
  /// **'Yeni e-posta'**
  String get newEmail2;

  /// No description provided for @reply2.
  ///
  /// In tr, this message translates to:
  /// **'Yanıt'**
  String get reply2;

  /// No description provided for @noSignaturesYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz imza yok'**
  String get noSignaturesYet;

  /// No description provided for @signatureNameMustBe1.
  ///
  /// In tr, this message translates to:
  /// **'İmza adı 1-100 karakter olmalı.'**
  String get signatureNameMustBe1;

  /// No description provided for @enterTheSignatureText.
  ///
  /// In tr, this message translates to:
  /// **'İmza metni yazın.'**
  String get enterTheSignatureText;

  /// No description provided for @editSignature.
  ///
  /// In tr, this message translates to:
  /// **'İmzayı düzenle'**
  String get editSignature;

  /// No description provided for @signatureText.
  ///
  /// In tr, this message translates to:
  /// **'İmza metni'**
  String get signatureText;

  /// No description provided for @syncScopeSaved.
  ///
  /// In tr, this message translates to:
  /// **'Senkronizasyon kapsamı kaydedildi.'**
  String get syncScopeSaved;

  /// No description provided for @syncScope.
  ///
  /// In tr, this message translates to:
  /// **'Senkronizasyon kapsamı'**
  String get syncScope;

  /// No description provided for @chooseTheFoldersToUpdate.
  ///
  /// In tr, this message translates to:
  /// **'Arka planda güncellenecek klasörleri seçin. Diğer klasörler açıldığında yine yenilenir.'**
  String get chooseTheFoldersToUpdate;

  /// No description provided for @chooseAtLeastOneFolder.
  ///
  /// In tr, this message translates to:
  /// **'En az bir klasör seçin.'**
  String get chooseAtLeastOneFolder;

  /// No description provided for @foldersSyncedInTheBackground.
  ///
  /// In tr, this message translates to:
  /// **'Arka planda senkronize edilen klasörler: {value}'**
  String foldersSyncedInTheBackground(Object value);

  /// No description provided for @syncStatus.
  ///
  /// In tr, this message translates to:
  /// **'Senkronizasyon Durumu'**
  String get syncStatus;

  /// No description provided for @noConnectedAccounts.
  ///
  /// In tr, this message translates to:
  /// **'Bağlı hesap yok.'**
  String get noConnectedAccounts;

  /// No description provided for @noSyncAttemptsYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz senkronizasyon denemesi yok.'**
  String get noSyncAttemptsYet;

  /// No description provided for @actionsAreWaitingForA.
  ///
  /// In tr, this message translates to:
  /// **'{queued} işlem bağlantı bekliyor'**
  String actionsAreWaitingForA(int queued);

  /// No description provided for @temporaryProblem.
  ///
  /// In tr, this message translates to:
  /// **'Geçici sorun'**
  String get temporaryProblem;

  /// No description provided for @authenticationProblem.
  ///
  /// In tr, this message translates to:
  /// **'Kimlik doğrulama sorunu'**
  String get authenticationProblem;

  /// No description provided for @configurationProblem.
  ///
  /// In tr, this message translates to:
  /// **'Yapılandırma sorunu'**
  String get configurationProblem;

  /// No description provided for @permanentProblem.
  ///
  /// In tr, this message translates to:
  /// **'Kalıcı sorun'**
  String get permanentProblem;

  /// No description provided for @unknownProblem.
  ///
  /// In tr, this message translates to:
  /// **'Bilinmeyen sorun'**
  String get unknownProblem;

  /// No description provided for @olderMailIsStillBeing.
  ///
  /// In tr, this message translates to:
  /// **'Geçmiş mailler hâlâ içeri aktarılıyor'**
  String get olderMailIsStillBeing;

  /// No description provided for @noSuccessfulSyncYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz başarılı senkronizasyon yok'**
  String get noSuccessfulSyncYet;

  /// No description provided for @deleteSavedText.
  ///
  /// In tr, this message translates to:
  /// **'Hazır metni sil?'**
  String get deleteSavedText;

  /// No description provided for @theSavedTextWillBe.
  ///
  /// In tr, this message translates to:
  /// **'“{name}” hazır metni kalıcı olarak silinecek.'**
  String theSavedTextWillBe(Object name);

  /// No description provided for @noSavedTextsYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz hazır metin yok'**
  String get noSavedTextsYet;

  /// No description provided for @noSubject.
  ///
  /// In tr, this message translates to:
  /// **'Konu yok'**
  String get noSubject;

  /// No description provided for @newSavedText.
  ///
  /// In tr, this message translates to:
  /// **'Yeni hazır metin'**
  String get newSavedText;

  /// No description provided for @savedTextNameMustBe.
  ///
  /// In tr, this message translates to:
  /// **'Hazır metin adı 1-100 karakter olmalı.'**
  String get savedTextNameMustBe;

  /// No description provided for @subjectMustBeASingle.
  ///
  /// In tr, this message translates to:
  /// **'Konu tek satır ve en fazla 500 karakter olmalı.'**
  String get subjectMustBeASingle;

  /// No description provided for @enterTheSavedTextBody.
  ///
  /// In tr, this message translates to:
  /// **'Hazır metin gövdesini yazın.'**
  String get enterTheSavedTextBody;

  /// No description provided for @editSavedText.
  ///
  /// In tr, this message translates to:
  /// **'Hazır metni düzenle'**
  String get editSavedText;

  /// No description provided for @textBody.
  ///
  /// In tr, this message translates to:
  /// **'Metin gövdesi'**
  String get textBody;

  /// No description provided for @savedImagePreferences2.
  ///
  /// In tr, this message translates to:
  /// **'Kayıtlı Görsel Tercihleri'**
  String get savedImagePreferences2;

  /// No description provided for @noSavedSendersYetRegular.
  ///
  /// In tr, this message translates to:
  /// **'Henüz kayıtlı gönderici yok.\nNormal görseller, bu listeye ekleme yapılmadan da yüklenir.'**
  String get noSavedSendersYetRegular;

  /// No description provided for @domain.
  ///
  /// In tr, this message translates to:
  /// **'Alan adı'**
  String get domain;

  /// No description provided for @sender.
  ///
  /// In tr, this message translates to:
  /// **'Gönderici'**
  String get sender;

  /// No description provided for @theServerDidntRespondPlease.
  ///
  /// In tr, this message translates to:
  /// **'Sunucu yanıt vermedi. Lütfen tekrar deneyin.'**
  String get theServerDidntRespondPlease;

  /// No description provided for @checkYourInternetConnection.
  ///
  /// In tr, this message translates to:
  /// **'İnternet bağlantınızı kontrol edin.'**
  String get checkYourInternetConnection;

  /// No description provided for @wrongPassword.
  ///
  /// In tr, this message translates to:
  /// **'Şifre yanlış.'**
  String get wrongPassword;

  /// No description provided for @yourSessionExpiredPleaseSign.
  ///
  /// In tr, this message translates to:
  /// **'Oturum süresi doldu. Lütfen yeniden giriş yapın.'**
  String get yourSessionExpiredPleaseSign;

  /// No description provided for @accessHasntBeenEnabledFor.
  ///
  /// In tr, this message translates to:
  /// **'Bu e-posta adresi için erişim henüz açılmadı.'**
  String get accessHasntBeenEnabledFor;

  /// No description provided for @thisMailAccountHasBeen.
  ///
  /// In tr, this message translates to:
  /// **'Bu posta hesabı devre dışı bırakıldı.'**
  String get thisMailAccountHasBeen;

  /// No description provided for @thisAccountIsAlreadyConnected.
  ///
  /// In tr, this message translates to:
  /// **'Bu hesap zaten bağlı.'**
  String get thisAccountIsAlreadyConnected;

  /// No description provided for @aTemplateWithThisName.
  ///
  /// In tr, this message translates to:
  /// **'Bu adla bir şablon zaten var.'**
  String get aTemplateWithThisName;

  /// No description provided for @noRegisteredAccountFoundFor.
  ///
  /// In tr, this message translates to:
  /// **'Bu e-posta için kayıtlı hesap bulunamadı.'**
  String get noRegisteredAccountFoundFor;

  /// No description provided for @automaticServerDiscoveryFailed.
  ///
  /// In tr, this message translates to:
  /// **'Otomatik sunucu keşfi başarısız oldu.'**
  String get automaticServerDiscoveryFailed;

  /// No description provided for @serverDiscoveryTimedOutTry.
  ///
  /// In tr, this message translates to:
  /// **'Sunucu keşfinin süresi doldu. Tekrar deneyin.'**
  String get serverDiscoveryTimedOutTry;

  /// No description provided for @theServerSettingsArentSecure.
  ///
  /// In tr, this message translates to:
  /// **'Sunucu ayarları güvenli değil.'**
  String get theServerSettingsArentSecure;

  /// No description provided for @couldntReachTheMailServer.
  ///
  /// In tr, this message translates to:
  /// **'Posta sunucusuna ulaşılamadı. Tekrar deneyin.'**
  String get couldntReachTheMailServer;

  /// No description provided for @emailNotFound.
  ///
  /// In tr, this message translates to:
  /// **'E-posta bulunamadı.'**
  String get emailNotFound;

  /// No description provided for @thisDraftIsNoLonger.
  ///
  /// In tr, this message translates to:
  /// **'Bu taslak artık geçerli değil.'**
  String get thisDraftIsNoLonger;

  /// No description provided for @theMailFolderIsUnavailable.
  ///
  /// In tr, this message translates to:
  /// **'Posta klasörü kullanılamıyor.'**
  String get theMailFolderIsUnavailable;

  /// No description provided for @thisActionIsntSupportedFor.
  ///
  /// In tr, this message translates to:
  /// **'Bu işlem bu e-posta için desteklenmiyor.'**
  String get thisActionIsntSupportedFor;

  /// No description provided for @theMailboxChangedRefreshAnd.
  ///
  /// In tr, this message translates to:
  /// **'Posta kutusu değişti. Yenileyip tekrar deneyin.'**
  String get theMailboxChangedRefreshAnd;

  /// No description provided for @couldntMoveTheEmailTry.
  ///
  /// In tr, this message translates to:
  /// **'E-posta taşınamadı. Tekrar deneyin.'**
  String get couldntMoveTheEmailTry;

  /// No description provided for @couldntPermanentlyDeleteTheEmail.
  ///
  /// In tr, this message translates to:
  /// **'E-posta kalıcı olarak silinemedi. Tekrar deneyin.'**
  String get couldntPermanentlyDeleteTheEmail;

  /// No description provided for @theActionCouldntBeCompleted.
  ///
  /// In tr, this message translates to:
  /// **'İşlem tamamlanamadı. Tekrar deneyin.'**
  String get theActionCouldntBeCompleted;

  /// No description provided for @youCanPinAtMost3EmailsPer.
  ///
  /// In tr, this message translates to:
  /// **'Bir hesapta en fazla 3 e-posta sabitlenebilir.'**
  String get youCanPinAtMost3EmailsPer;

  /// No description provided for @theDraftHasntMatchedOn.
  ///
  /// In tr, this message translates to:
  /// **'Taslak sunucuda henüz eşleşmedi. Birkaç saniye sonra tekrar deneyin.'**
  String get theDraftHasntMatchedOn;

  /// No description provided for @theSendResultIsUnknown.
  ///
  /// In tr, this message translates to:
  /// **'Gönderim sonucu belirsiz. Gönderilenler’i kontrol edin.'**
  String get theSendResultIsUnknown;

  /// No description provided for @theMessageIsBeingSent.
  ///
  /// In tr, this message translates to:
  /// **'Gönderim sürüyor. Kısa süre sonra tekrar deneyin.'**
  String get theMessageIsBeingSent;

  /// No description provided for @theSendRequestIsInvalid.
  ///
  /// In tr, this message translates to:
  /// **'Gönderim isteği geçersiz. Yeniden deneyin.'**
  String get theSendRequestIsInvalid;

  /// No description provided for @theSendRequestWasUsed.
  ///
  /// In tr, this message translates to:
  /// **'Gönderim isteği farklı içerikle daha önce kullanıldı. Yeni gönderim oluşturun.'**
  String get theSendRequestWasUsed;

  /// No description provided for @theRecipientAddressIsInvalid.
  ///
  /// In tr, this message translates to:
  /// **'Alıcı adresi geçersiz.'**
  String get theRecipientAddressIsInvalid;

  /// No description provided for @invalidEmailAddress.
  ///
  /// In tr, this message translates to:
  /// **'Geçersiz e-posta adresi.'**
  String get invalidEmailAddress;

  /// No description provided for @theEmailHeadersAreInvalid.
  ///
  /// In tr, this message translates to:
  /// **'E-posta başlıkları geçersiz.'**
  String get theEmailHeadersAreInvalid;

  /// No description provided for @theEmailCouldntBeCreated.
  ///
  /// In tr, this message translates to:
  /// **'E-posta oluşturulamadı.'**
  String get theEmailCouldntBeCreated;

  /// No description provided for @theServerSettingsAreInvalid.
  ///
  /// In tr, this message translates to:
  /// **'Sunucu ayarları geçersiz.'**
  String get theServerSettingsAreInvalid;

  /// No description provided for @thisSignInMethodIsnt.
  ///
  /// In tr, this message translates to:
  /// **'Bu giriş yöntemi sunucuda ayarlı değil.'**
  String get thisSignInMethodIsnt;

  /// No description provided for @theRedirectAddressIsInvalid.
  ///
  /// In tr, this message translates to:
  /// **'Yönlendirme adresi geçersiz.'**
  String get theRedirectAddressIsInvalid;

  /// No description provided for @sessionVerificationIsInvalidTry.
  ///
  /// In tr, this message translates to:
  /// **'Oturum doğrulaması geçersiz. Tekrar deneyin.'**
  String get sessionVerificationIsInvalidTry;

  /// No description provided for @theProviderRejectedTheSign.
  ///
  /// In tr, this message translates to:
  /// **'Sağlayıcı girişi reddetti.'**
  String get theProviderRejectedTheSign;

  /// No description provided for @theServerIsBusyTry.
  ///
  /// In tr, this message translates to:
  /// **'Sunucu meşgul. Birazdan tekrar deneyin.'**
  String get theServerIsBusyTry;

  /// No description provided for @couldntDeleteTheDraftTry.
  ///
  /// In tr, this message translates to:
  /// **'Taslak silinemedi. Tekrar deneyin.'**
  String get couldntDeleteTheDraftTry;

  /// No description provided for @aSendCantBeScheduled.
  ///
  /// In tr, this message translates to:
  /// **'Geçmiş bir zamana gönderim zamanlanamaz.'**
  String get aSendCantBeScheduled;

  /// No description provided for @thisSendIsNoLonger.
  ///
  /// In tr, this message translates to:
  /// **'Bu gönderim artık beklemede değil. Listeyi yenileyin.'**
  String get thisSendIsNoLonger;

  /// No description provided for @theSendWasChangedOn.
  ///
  /// In tr, this message translates to:
  /// **'Gönderim başka bir cihazda değiştirildi. Yenileyip tekrar deneyin.'**
  String get theSendWasChangedOn;

  /// No description provided for @thisSendCanNoLonger.
  ///
  /// In tr, this message translates to:
  /// **'Bu gönderim artık düzenlenemez. Gönderilenler’i kontrol edin.'**
  String get thisSendCanNoLonger;

  /// No description provided for @scheduledSendNotFoundRefresh.
  ///
  /// In tr, this message translates to:
  /// **'Zamanlanmış gönderim bulunamadı. Listeyi yenileyin.'**
  String get scheduledSendNotFoundRefresh;

  /// No description provided for @theHeldAttachmentWasntFound.
  ///
  /// In tr, this message translates to:
  /// **'Bekletilen ek bulunamadı. Listeyi yenileyin.'**
  String get theHeldAttachmentWasntFound;

  /// No description provided for @theSelectedIdentityWasntFound.
  ///
  /// In tr, this message translates to:
  /// **'Seçilen kimlik bulunamadı.'**
  String get theSelectedIdentityWasntFound;

  /// No description provided for @theSelectedSignatureWasntFound.
  ///
  /// In tr, this message translates to:
  /// **'Seçilen imza bulunamadı.'**
  String get theSelectedSignatureWasntFound;

  /// No description provided for @thisAddressIsAlreadyRegistered.
  ///
  /// In tr, this message translates to:
  /// **'Bu adres zaten bir kimlik olarak kayıtlı.'**
  String get thisAddressIsAlreadyRegistered;

  /// No description provided for @thisIdentityIsUsedIn.
  ///
  /// In tr, this message translates to:
  /// **'Bu kimlik zamanlanmış bir gönderimde kullanılıyor.'**
  String get thisIdentityIsUsedIn;

  /// No description provided for @theSessionIsAlreadyClosed.
  ///
  /// In tr, this message translates to:
  /// **'Oturum zaten kapatılmış.'**
  String get theSessionIsAlreadyClosed;

  /// No description provided for @theEmailBodyCantBe.
  ///
  /// In tr, this message translates to:
  /// **'E-posta gövdesi boş olamaz.'**
  String get theEmailBodyCantBe;

  /// No description provided for @theEmailBodyIsToo.
  ///
  /// In tr, this message translates to:
  /// **'E-posta gövdesi çok büyük.'**
  String get theEmailBodyIsToo;

  /// No description provided for @attachmentLimitExceeded.
  ///
  /// In tr, this message translates to:
  /// **'Ek dosya sınırı aşıldı.'**
  String get attachmentLimitExceeded;

  /// No description provided for @aFolderWithThisName.
  ///
  /// In tr, this message translates to:
  /// **'Bu adda bir klasör zaten var.'**
  String get aFolderWithThisName;

  /// No description provided for @theFolderIsntEmptyMove.
  ///
  /// In tr, this message translates to:
  /// **'Klasör boş değil. Önce içindeki postaları taşıyın veya silin.'**
  String get theFolderIsntEmptyMove;

  /// No description provided for @deleteTheSubfoldersFirst.
  ///
  /// In tr, this message translates to:
  /// **'Önce alt klasörleri silin.'**
  String get deleteTheSubfoldersFirst;

  /// No description provided for @thisFolderCantBeChanged.
  ///
  /// In tr, this message translates to:
  /// **'Bu klasör değiştirilemez.'**
  String get thisFolderCantBeChanged;

  /// No description provided for @theFolderNameIsInvalid.
  ///
  /// In tr, this message translates to:
  /// **'Klasör adı geçersiz.'**
  String get theFolderNameIsInvalid;

  /// No description provided for @theMailServerDidntAccept.
  ///
  /// In tr, this message translates to:
  /// **'Posta sunucusu bu klasör adını kabul etmedi.'**
  String get theMailServerDidntAccept;

  /// No description provided for @theFolderWasRemovedFrom.
  ///
  /// In tr, this message translates to:
  /// **'Klasör sunucudan kaldırılmış.'**
  String get theFolderWasRemovedFrom;

  /// No description provided for @theSyncQueueIsFull.
  ///
  /// In tr, this message translates to:
  /// **'Eşitleme kuyruğu dolu. Birazdan tekrar deneyin.'**
  String get theSyncQueueIsFull;

  /// No description provided for @syncWasPostponedTryAgain.
  ///
  /// In tr, this message translates to:
  /// **'Eşitleme ertelendi. Birazdan tekrar deneyin.'**
  String get syncWasPostponedTryAgain;

  /// No description provided for @syncWasInterruptedTryAgain.
  ///
  /// In tr, this message translates to:
  /// **'Eşitleme yarıda kesildi. Tekrar deneyin.'**
  String get syncWasInterruptedTryAgain;

  /// No description provided for @syncCouldntBeCompletedTry.
  ///
  /// In tr, this message translates to:
  /// **'Eşitleme tamamlanamadı. Tekrar deneyin.'**
  String get syncCouldntBeCompletedTry;

  /// No description provided for @theAccountNeedsToBe.
  ///
  /// In tr, this message translates to:
  /// **'Hesap yeniden bağlanmayı istiyor.'**
  String get theAccountNeedsToBe;

  /// No description provided for @thisSignInMethodIsntSupported.
  ///
  /// In tr, this message translates to:
  /// **'Bu giriş yöntemi desteklenmiyor.'**
  String get thisSignInMethodIsntSupported;

  /// No description provided for @theSmtpPasswordWasRejected.
  ///
  /// In tr, this message translates to:
  /// **'SMTP şifresi reddedildi.'**
  String get theSmtpPasswordWasRejected;

  /// No description provided for @thisSignInIsntSupported.
  ///
  /// In tr, this message translates to:
  /// **'Bu giriş şu an desteklenmiyor.'**
  String get thisSignInIsntSupported;

  /// No description provided for @anUnexpectedErrorOccurred.
  ///
  /// In tr, this message translates to:
  /// **'Beklenmeyen bir hata oluştu.'**
  String get anUnexpectedErrorOccurred;

  /// No description provided for @theRequestCouldntBeCompleted.
  ///
  /// In tr, this message translates to:
  /// **'İstek tamamlanamadı.'**
  String get theRequestCouldntBeCompleted;

  /// No description provided for @attachmentNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Ek bulunamadı.'**
  String get attachmentNotFound;

  /// No description provided for @theAttachmentCouldntBeDownloaded.
  ///
  /// In tr, this message translates to:
  /// **'Ek indirilemedi. Tekrar deneyin.'**
  String get theAttachmentCouldntBeDownloaded;

  /// No description provided for @snoozedEmailIsBack.
  ///
  /// In tr, this message translates to:
  /// **'Ertelenen e-posta geri döndü'**
  String get snoozedEmailIsBack;

  /// No description provided for @aSnoozedMessageHasReturned.
  ///
  /// In tr, this message translates to:
  /// **'Ertelenen bir iletiniz gelen kutusuna döndü.'**
  String get aSnoozedMessageHasReturned;

  /// No description provided for @couldntDoTryAgain.
  ///
  /// In tr, this message translates to:
  /// **'\"{label}\" yapılamadı, tekrar deneyin.'**
  String couldntDoTryAgain(Object label);

  /// No description provided for @theServerAddressCantBe.
  ///
  /// In tr, this message translates to:
  /// **'Sunucu adresi boş olamaz.'**
  String get theServerAddressCantBe;

  /// No description provided for @enterAValidHttpHttps.
  ///
  /// In tr, this message translates to:
  /// **'Geçerli bir http/https adresi girin.'**
  String get enterAValidHttpHttps;

  /// No description provided for @off.
  ///
  /// In tr, this message translates to:
  /// **'Kapalı'**
  String get off;

  /// No description provided for @wiFiOnly.
  ///
  /// In tr, this message translates to:
  /// **'Yalnız Wi-Fi'**
  String get wiFiOnly;

  /// No description provided for @starRemoveStar.
  ///
  /// In tr, this message translates to:
  /// **'Yıldızla / yıldızı kaldır'**
  String get starRemoveStar;

  /// No description provided for @manual.
  ///
  /// In tr, this message translates to:
  /// **'Manuel'**
  String get manual;

  /// No description provided for @immediately.
  ///
  /// In tr, this message translates to:
  /// **'Hemen'**
  String get immediately;

  /// No description provided for @uploadingAttachment.
  ///
  /// In tr, this message translates to:
  /// **'Ek yükleniyor: {percent}%'**
  String uploadingAttachment(Object percent);

  /// No description provided for @theMessageMayHaveBeen.
  ///
  /// In tr, this message translates to:
  /// **'Mesaj gönderilmiş olabilir. Giden Kutusu ve Gönderilenler’i kontrol edin.'**
  String get theMessageMayHaveBeen;

  /// No description provided for @couldntSendTheMessageWas.
  ///
  /// In tr, this message translates to:
  /// **'Gönderilemedi. Mesaj Giden Kutusu’nda saklandı.'**
  String get couldntSendTheMessageWas;

  /// No description provided for @theMessageMayHaveBeenSentCheckSent.
  ///
  /// In tr, this message translates to:
  /// **'Mesaj gönderilmiş olabilir. Gönderilenler’i kontrol edin.'**
  String get theMessageMayHaveBeenSentCheckSent;

  /// No description provided for @youCanPinAtMostEmailsPerAccount.
  ///
  /// In tr, this message translates to:
  /// **'Bir hesapta en fazla {maxPinnedMails} e-posta sabitlenebilir. Şu an {pinned} sabitli, {adding} yeni seçildi{value}. Hiçbiri sabitlenmedi.'**
  String youCanPinAtMostEmailsPerAccount(
    Object maxPinnedMails,
    Object pinned,
    Object adding,
    Object value,
  );

  /// No description provided for @now.
  ///
  /// In tr, this message translates to:
  /// **'şimdi'**
  String get now;

  /// No description provided for @minAgo.
  ///
  /// In tr, this message translates to:
  /// **'{inMinutes} dk önce'**
  String minAgo(Object inMinutes);

  /// No description provided for @yesterday.
  ///
  /// In tr, this message translates to:
  /// **'dün'**
  String get yesterday;

  /// No description provided for @theSendDidntStartYou.
  ///
  /// In tr, this message translates to:
  /// **'Gönderim başlamadı. Giden Kutusu’ndan yeniden deneyebilirsiniz.'**
  String get theSendDidntStartYou;

  /// No description provided for @theServerReturnedAnUnexpected.
  ///
  /// In tr, this message translates to:
  /// **'Sunucudan beklenmeyen bir yanıt geldi.'**
  String get theServerReturnedAnUnexpected;

  /// No description provided for @anUnexpectedErrorOccurredPlease.
  ///
  /// In tr, this message translates to:
  /// **'Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.'**
  String get anUnexpectedErrorOccurredPlease;

  /// No description provided for @standardFoldersCantBeDeleted.
  ///
  /// In tr, this message translates to:
  /// **'Standart klasörler silinemez.'**
  String get standardFoldersCantBeDeleted;

  /// No description provided for @deleteOrMoveTheSubfolders.
  ///
  /// In tr, this message translates to:
  /// **'Önce alt klasörleri silin ya da taşıyın.'**
  String get deleteOrMoveTheSubfolders;

  /// No description provided for @theFolderContainsEmailsMove.
  ///
  /// In tr, this message translates to:
  /// **'Klasörde e-posta var. Silmeden önce e-postaları başka bir klasöre taşıyın.'**
  String get theFolderContainsEmailsMove;

  /// No description provided for @folderNameCantBeEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Klasör adı boş olamaz.'**
  String get folderNameCantBeEmpty;

  /// No description provided for @folderNameCantContainOr.
  ///
  /// In tr, this message translates to:
  /// **'Klasör adı * veya % karakteri içeremez.'**
  String get folderNameCantContainOr;

  /// No description provided for @folderNameCantContain.
  ///
  /// In tr, this message translates to:
  /// **'Klasör adı \"{delimiter}\" karakterini içeremez.'**
  String folderNameCantContain(Object delimiter);

  /// No description provided for @thisNameIsReservedChoose.
  ///
  /// In tr, this message translates to:
  /// **'Bu ad ayrılmış. Başka bir ad seçin.'**
  String get thisNameIsReservedChoose;

  /// No description provided for @attachments2.
  ///
  /// In tr, this message translates to:
  /// **'Ekler:'**
  String get attachments2;

  /// No description provided for @otherFolders.
  ///
  /// In tr, this message translates to:
  /// **'Diğer Klasörler'**
  String get otherFolders;

  /// No description provided for @accountAndApp.
  ///
  /// In tr, this message translates to:
  /// **'Hesap ve uygulama'**
  String get accountAndApp;

  /// No description provided for @syncAccounts.
  ///
  /// In tr, this message translates to:
  /// **'Hesapları eşitle'**
  String get syncAccounts;

  /// No description provided for @signOut3.
  ///
  /// In tr, this message translates to:
  /// **'Çıkış Yap'**
  String get signOut3;

  /// No description provided for @finishSorting.
  ///
  /// In tr, this message translates to:
  /// **'Sıralamayı bitir'**
  String get finishSorting;

  /// No description provided for @sortFolders.
  ///
  /// In tr, this message translates to:
  /// **'Klasörleri sırala'**
  String get sortFolders;

  /// No description provided for @moveUp.
  ///
  /// In tr, this message translates to:
  /// **'Yukarı taşı'**
  String get moveUp;

  /// No description provided for @moveDown.
  ///
  /// In tr, this message translates to:
  /// **'Aşağı taşı'**
  String get moveDown;

  /// No description provided for @verifyYourIdentityToAccess.
  ///
  /// In tr, this message translates to:
  /// **'Postalarınıza erişmek için kimliğinizi doğrulayın'**
  String get verifyYourIdentityToAccess;

  /// No description provided for @noFingerprintFaceRecognitionOr.
  ///
  /// In tr, this message translates to:
  /// **'Cihazınızda parmak izi, yüz tanıma veya ekran kilidi tanımlı değil. Uygulama kilidi bu nedenle doğrulanamıyor.'**
  String get noFingerprintFaceRecognitionOr;

  /// No description provided for @verifyYourIdentityWithYour.
  ///
  /// In tr, this message translates to:
  /// **'Devam etmek için parmak izi, yüz tanıma veya cihaz şifrenizle kimliğinizi doğrulayın.'**
  String get verifyYourIdentityWithYour;

  /// No description provided for @continueAnyway.
  ///
  /// In tr, this message translates to:
  /// **'Yine de devam et'**
  String get continueAnyway;

  /// No description provided for @unlock.
  ///
  /// In tr, this message translates to:
  /// **'Kilidi Aç'**
  String get unlock;

  /// No description provided for @customColor2.
  ///
  /// In tr, this message translates to:
  /// **'Özel renk'**
  String get customColor2;

  /// No description provided for @hexCode.
  ///
  /// In tr, this message translates to:
  /// **'Hex kodu'**
  String get hexCode;

  /// No description provided for @invalidColor.
  ///
  /// In tr, this message translates to:
  /// **'Geçersiz renk'**
  String get invalidColor;

  /// No description provided for @select.
  ///
  /// In tr, this message translates to:
  /// **'Seç'**
  String get select;

  /// No description provided for @hueAndBrightness.
  ///
  /// In tr, this message translates to:
  /// **'Renk tonu ve parlaklık'**
  String get hueAndBrightness;

  /// No description provided for @color.
  ///
  /// In tr, this message translates to:
  /// **'Renk'**
  String get color;

  /// No description provided for @labelsApplyPerAccount.
  ///
  /// In tr, this message translates to:
  /// **'Etiketler hesap bazında uygulanır'**
  String get labelsApplyPerAccount;

  /// No description provided for @mailAccount.
  ///
  /// In tr, this message translates to:
  /// **'Posta hesabı'**
  String get mailAccount;

  /// No description provided for @couldntApplyTheLabel.
  ///
  /// In tr, this message translates to:
  /// **'Etiket uygulanamadı: {value}'**
  String couldntApplyTheLabel(Object value);

  /// No description provided for @theseResultsComeFromThe.
  ///
  /// In tr, this message translates to:
  /// **'Bu sonuçlar {authservId} tarafından eklenen posta başlığından alınmıştır. Yalnızca bilgi amaçlıdır.'**
  String theseResultsComeFromThe(Object authservId);

  /// No description provided for @theseResultsComeFromTheMailHeaderFor.
  ///
  /// In tr, this message translates to:
  /// **'Bu sonuçlar posta başlığından alınmıştır. Yalnızca bilgi amaçlıdır.'**
  String get theseResultsComeFromTheMailHeaderFor;

  /// No description provided for @pass.
  ///
  /// In tr, this message translates to:
  /// **'geçti'**
  String get pass;

  /// No description provided for @fail.
  ///
  /// In tr, this message translates to:
  /// **'başarısız'**
  String get fail;

  /// No description provided for @partialFail.
  ///
  /// In tr, this message translates to:
  /// **'kısmen başarısız'**
  String get partialFail;

  /// No description provided for @neutral.
  ///
  /// In tr, this message translates to:
  /// **'nötr'**
  String get neutral;

  /// No description provided for @temporaryError.
  ///
  /// In tr, this message translates to:
  /// **'geçici hata'**
  String get temporaryError;

  /// No description provided for @permanentError.
  ///
  /// In tr, this message translates to:
  /// **'kalıcı hata'**
  String get permanentError;

  /// No description provided for @theLinkCouldntBeOpened.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı açılamadı.'**
  String get theLinkCouldntBeOpened;

  /// No description provided for @theLinkWasntOpenedBecause.
  ///
  /// In tr, this message translates to:
  /// **'Bu bağlantı güvenli olmayan bir adres türü ({scheme}:) kullandığı için açılmadı.'**
  String theLinkWasntOpenedBecause(Object scheme);

  /// No description provided for @theLinkWasntOpenedBecauseItsAddressIs.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı adresi geçersiz olduğu için açılmadı.'**
  String get theLinkWasntOpenedBecauseItsAddressIs;

  /// No description provided for @theLinkTextShowsBut.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı metni \"{displayedDomain}\" adresini gösteriyor, ancak bağlantı başka bir alan adına gidiyor.'**
  String theLinkTextShowsBut(Object displayedDomain);

  /// No description provided for @theDomainContainsInternationalPunycode.
  ///
  /// In tr, this message translates to:
  /// **'Alan adı uluslararası (punycode) karakterler içeriyor.'**
  String get theDomainContainsInternationalPunycode;

  /// No description provided for @theDomainMixesCharactersFrom.
  ///
  /// In tr, this message translates to:
  /// **'Alan adında farklı alfabelerden karakterler bir arada kullanılmış.'**
  String get theDomainMixesCharactersFrom;

  /// No description provided for @theDomainContainsMisleadingCharacters.
  ///
  /// In tr, this message translates to:
  /// **'Alan adında Latin harflerine benzeyen yanıltıcı karakterler var.'**
  String get theDomainContainsMisleadingCharacters;

  /// No description provided for @theAddressContainsUserInformation.
  ///
  /// In tr, this message translates to:
  /// **'Adres, gerçek alan adını gizleyebilen kullanıcı bilgisi içeriyor.'**
  String get theAddressContainsUserInformation;

  /// No description provided for @thisLinkLooksSuspicious.
  ///
  /// In tr, this message translates to:
  /// **'Bu bağlantı şüpheli görünüyor'**
  String get thisLinkLooksSuspicious;

  /// No description provided for @actualDestination.
  ///
  /// In tr, this message translates to:
  /// **'Gerçek hedef'**
  String get actualDestination;

  /// No description provided for @rawAddressPunycode.
  ///
  /// In tr, this message translates to:
  /// **'Ham adres (punycode)'**
  String get rawAddressPunycode;

  /// No description provided for @fullLink.
  ///
  /// In tr, this message translates to:
  /// **'Tam bağlantı'**
  String get fullLink;

  /// No description provided for @openAnyway.
  ///
  /// In tr, this message translates to:
  /// **'Yine de aç'**
  String get openAnyway;

  /// No description provided for @unread3.
  ///
  /// In tr, this message translates to:
  /// **'okunmadı'**
  String get unread3;

  /// No description provided for @starred3.
  ///
  /// In tr, this message translates to:
  /// **'yıldızlı'**
  String get starred3;

  /// No description provided for @pinned.
  ///
  /// In tr, this message translates to:
  /// **'sabitlenmiş'**
  String get pinned;

  /// No description provided for @replied.
  ///
  /// In tr, this message translates to:
  /// **'yanıtlandı'**
  String get replied;

  /// No description provided for @hasAttachments.
  ///
  /// In tr, this message translates to:
  /// **'ek içeriyor'**
  String get hasAttachments;

  /// No description provided for @messageConversation.
  ///
  /// In tr, this message translates to:
  /// **'{threadCount} mesajlık konuşma'**
  String messageConversation(Object threadCount);

  /// No description provided for @unread4.
  ///
  /// In tr, this message translates to:
  /// **'Okunmamış'**
  String get unread4;

  /// No description provided for @attachments3.
  ///
  /// In tr, this message translates to:
  /// **'Ekli'**
  String get attachments3;

  /// No description provided for @newestFirst.
  ///
  /// In tr, this message translates to:
  /// **'En yeni önce'**
  String get newestFirst;

  /// No description provided for @oldestFirst.
  ///
  /// In tr, this message translates to:
  /// **'En eski önce'**
  String get oldestFirst;

  /// No description provided for @unreadFirst.
  ///
  /// In tr, this message translates to:
  /// **'Okunmamışlar önce'**
  String get unreadFirst;

  /// No description provided for @bySenderAZ.
  ///
  /// In tr, this message translates to:
  /// **'Gönderene göre (A-Z)'**
  String get bySenderAZ;

  /// No description provided for @bySubjectAZ.
  ///
  /// In tr, this message translates to:
  /// **'Konuya göre (A-Z)'**
  String get bySubjectAZ;

  /// No description provided for @sort.
  ///
  /// In tr, this message translates to:
  /// **'Sırala'**
  String get sort;

  /// No description provided for @enterAValidPort.
  ///
  /// In tr, this message translates to:
  /// **'Geçerli bir port girin'**
  String get enterAValidPort;

  /// No description provided for @manualServerSettings.
  ///
  /// In tr, this message translates to:
  /// **'Manuel sunucu ayarları'**
  String get manualServerSettings;

  /// No description provided for @automaticServerDiscoveryFailedEnter.
  ///
  /// In tr, this message translates to:
  /// **'Otomatik sunucu keşfi başarısız oldu. IMAP/SMTP sunucu bilgilerini elle girin (993 IMAP ve 587 SMTP için önerilen varsayılan portlardır).'**
  String get automaticServerDiscoveryFailedEnter;

  /// No description provided for @imapServer.
  ///
  /// In tr, this message translates to:
  /// **'IMAP sunucu'**
  String get imapServer;

  /// No description provided for @imapPort.
  ///
  /// In tr, this message translates to:
  /// **'IMAP port'**
  String get imapPort;

  /// No description provided for @smtpServer.
  ///
  /// In tr, this message translates to:
  /// **'SMTP sunucu'**
  String get smtpServer;

  /// No description provided for @smtpPort.
  ///
  /// In tr, this message translates to:
  /// **'SMTP port'**
  String get smtpPort;

  /// No description provided for @connect2.
  ///
  /// In tr, this message translates to:
  /// **'Bağlan'**
  String get connect2;

  /// No description provided for @thereAreNoOtherFolders.
  ///
  /// In tr, this message translates to:
  /// **'Taşınabilecek başka klasör yok.'**
  String get thereAreNoOtherFolders;

  /// No description provided for @emailsSelectedFromDifferentAccounts.
  ///
  /// In tr, this message translates to:
  /// **'Farklı hesaplardan seçilen e-postalar yalnızca ortak klasörlere taşınabilir.'**
  String get emailsSelectedFromDifferentAccounts;

  /// No description provided for @permanentlyDeleteThisEmail.
  ///
  /// In tr, this message translates to:
  /// **'E-posta kalıcı olarak silinsin mi?'**
  String get permanentlyDeleteThisEmail;

  /// No description provided for @permanentlyDeleteEmails.
  ///
  /// In tr, this message translates to:
  /// **'{count} e-posta kalıcı olarak silinsin mi?'**
  String permanentlyDeleteEmails(int count);

  /// No description provided for @address.
  ///
  /// In tr, this message translates to:
  /// **'Adres'**
  String get address;

  /// No description provided for @in1Hour.
  ///
  /// In tr, this message translates to:
  /// **'1 saat sonra'**
  String get in1Hour;

  /// No description provided for @thisEvening600Pm.
  ///
  /// In tr, this message translates to:
  /// **'Bu akşam (18:00)'**
  String get thisEvening600Pm;

  /// No description provided for @tomorrowMorning900Am.
  ///
  /// In tr, this message translates to:
  /// **'Yarın sabah (09:00)'**
  String get tomorrowMorning900Am;

  /// No description provided for @nextWeekMonday900.
  ///
  /// In tr, this message translates to:
  /// **'Gelecek hafta (Pazartesi 09:00)'**
  String get nextWeekMonday900;

  /// No description provided for @chooseDateAndTime.
  ///
  /// In tr, this message translates to:
  /// **'Tarih ve saat seç'**
  String get chooseDateAndTime;

  /// No description provided for @theChosenTimeIsIn.
  ///
  /// In tr, this message translates to:
  /// **'Seçilen saat geçmişte kalıyor, lütfen ileri bir saat seçin.'**
  String get theChosenTimeIsIn;

  /// No description provided for @youCanAttachAtMost.
  ///
  /// In tr, this message translates to:
  /// **'En fazla {maxAttachmentCount} dosya ekleyebilirsiniz.'**
  String youCanAttachAtMost(int maxAttachmentCount);

  /// No description provided for @aLabelWithThisName.
  ///
  /// In tr, this message translates to:
  /// **'Bu isimde bir etiket zaten var.'**
  String get aLabelWithThisName;

  /// No description provided for @emailAddressIsRequired.
  ///
  /// In tr, this message translates to:
  /// **'E-posta adresi zorunludur'**
  String get emailAddressIsRequired;

  /// No description provided for @theAttachmentCouldntBeDownloaded2.
  ///
  /// In tr, this message translates to:
  /// **'Ek indirilemedi.'**
  String get theAttachmentCouldntBeDownloaded2;

  /// No description provided for @add2.
  ///
  /// In tr, this message translates to:
  /// **'Ekle ({length})'**
  String add2(Object length);

  /// No description provided for @requestReadReceipt.
  ///
  /// In tr, this message translates to:
  /// **'Okundu bilgisi iste'**
  String get requestReadReceipt;

  /// No description provided for @whatShouldHappenToThis.
  ///
  /// In tr, this message translates to:
  /// **'Bu taslak ne olsun?'**
  String get whatShouldHappenToThis;

  /// No description provided for @deleteEmail.
  ///
  /// In tr, this message translates to:
  /// **'E-posta silinsin mi?'**
  String get deleteEmail;

  /// No description provided for @deleteDraft2.
  ///
  /// In tr, this message translates to:
  /// **'Taslak silinsin mi?'**
  String get deleteDraft2;

  /// No description provided for @aReadReceiptWontBe.
  ///
  /// In tr, this message translates to:
  /// **'Okundu bilgisi istenmeyecek.'**
  String get aReadReceiptWontBe;

  /// No description provided for @emailsSnoozed.
  ///
  /// In tr, this message translates to:
  /// **'{length} e-posta ertelendi.'**
  String emailsSnoozed(int length);

  /// No description provided for @lastSync.
  ///
  /// In tr, this message translates to:
  /// **'Son senkronizasyon: {value}'**
  String lastSync(Object value);

  /// No description provided for @unsubscribed.
  ///
  /// In tr, this message translates to:
  /// **'Abonelik iptal edildi.'**
  String get unsubscribed;

  /// No description provided for @newEmailAndSnoozedEmail.
  ///
  /// In tr, this message translates to:
  /// **'Yeni e-posta ve ertelenen e-posta bildirimleri'**
  String get newEmailAndSnoozedEmail;

  /// No description provided for @noSubject2.
  ///
  /// In tr, this message translates to:
  /// **'(Konu yok)'**
  String get noSubject2;

  /// No description provided for @noSubject3.
  ///
  /// In tr, this message translates to:
  /// **'(konu yok)'**
  String get noSubject3;

  /// No description provided for @alsoSearchTheServer.
  ///
  /// In tr, this message translates to:
  /// **'Sunucuda da ara'**
  String get alsoSearchTheServer;

  /// No description provided for @composing.
  ///
  /// In tr, this message translates to:
  /// **'E-posta yazma'**
  String get composing;

  /// No description provided for @mailbox.
  ///
  /// In tr, this message translates to:
  /// **'Posta kutusu'**
  String get mailbox;

  /// No description provided for @darkGray.
  ///
  /// In tr, this message translates to:
  /// **'Koyu gri'**
  String get darkGray;

  /// No description provided for @thisDevice.
  ///
  /// In tr, this message translates to:
  /// **'Bu cihaz'**
  String get thisDevice;

  /// No description provided for @everythingIsSynced.
  ///
  /// In tr, this message translates to:
  /// **'Hepsi senkronize'**
  String get everythingIsSynced;

  /// No description provided for @theAttachmentWasDownloadedIncompletely.
  ///
  /// In tr, this message translates to:
  /// **'Ek eksik indirildi. Tekrar deneyin.'**
  String get theAttachmentWasDownloadedIncompletely;

  /// No description provided for @theAttachmentCouldntBeSaved.
  ///
  /// In tr, this message translates to:
  /// **'Ek kaydedilemedi. Tekrar deneyin.'**
  String get theAttachmentCouldntBeSaved;

  /// No description provided for @youHaveANewMessage.
  ///
  /// In tr, this message translates to:
  /// **'Yeni bir iletiniz var.'**
  String get youHaveANewMessage;

  /// No description provided for @newEmailAndAccountNotifications.
  ///
  /// In tr, this message translates to:
  /// **'Yeni e-posta ve hesap bildirimleri'**
  String get newEmailAndAccountNotifications;

  /// No description provided for @wiFiAndMobileData.
  ///
  /// In tr, this message translates to:
  /// **'Wi-Fi ve mobil veri'**
  String get wiFiAndMobileData;

  /// No description provided for @n1Mb.
  ///
  /// In tr, this message translates to:
  /// **'1 MB'**
  String get n1Mb;

  /// No description provided for @n5Mb.
  ///
  /// In tr, this message translates to:
  /// **'5 MB'**
  String get n5Mb;

  /// No description provided for @n10Mb.
  ///
  /// In tr, this message translates to:
  /// **'10 MB'**
  String get n10Mb;

  /// No description provided for @n5Seconds.
  ///
  /// In tr, this message translates to:
  /// **'5 saniye'**
  String get n5Seconds;

  /// No description provided for @n10Seconds.
  ///
  /// In tr, this message translates to:
  /// **'10 saniye'**
  String get n10Seconds;

  /// No description provided for @n20Seconds.
  ///
  /// In tr, this message translates to:
  /// **'20 saniye'**
  String get n20Seconds;

  /// No description provided for @n30Seconds.
  ///
  /// In tr, this message translates to:
  /// **'30 saniye'**
  String get n30Seconds;

  /// No description provided for @every5Minutes.
  ///
  /// In tr, this message translates to:
  /// **'Her 5 dakikada bir'**
  String get every5Minutes;

  /// No description provided for @every15Minutes.
  ///
  /// In tr, this message translates to:
  /// **'Her 15 dakikada bir'**
  String get every15Minutes;

  /// No description provided for @every30Minutes.
  ///
  /// In tr, this message translates to:
  /// **'Her 30 dakikada bir'**
  String get every30Minutes;

  /// No description provided for @everyHour.
  ///
  /// In tr, this message translates to:
  /// **'Her saat'**
  String get everyHour;

  /// No description provided for @after1Minute.
  ///
  /// In tr, this message translates to:
  /// **'1 dakika sonra'**
  String get after1Minute;

  /// No description provided for @after5Minutes.
  ///
  /// In tr, this message translates to:
  /// **'5 dakika sonra'**
  String get after5Minutes;

  /// No description provided for @after15Minutes.
  ///
  /// In tr, this message translates to:
  /// **'15 dakika sonra'**
  String get after15Minutes;

  /// No description provided for @couldntSaveToTheOutbox.
  ///
  /// In tr, this message translates to:
  /// **'Giden Kutusu kaydedilemedi: {value}'**
  String couldntSaveToTheOutbox(Object value);

  /// No description provided for @youCanPinMore.
  ///
  /// In tr, this message translates to:
  /// **'; en fazla {free} tane daha sabitleyebilirsiniz'**
  String youCanPinMore(Object free);

  /// No description provided for @appLocked.
  ///
  /// In tr, this message translates to:
  /// **'Uygulama Kilitli'**
  String get appLocked;

  /// No description provided for @noLabelsInThisAccount.
  ///
  /// In tr, this message translates to:
  /// **'Bu hesapta etiket yok.'**
  String get noLabelsInThisAccount;

  /// No description provided for @serverAddressIsRequired.
  ///
  /// In tr, this message translates to:
  /// **'Sunucu adresi zorunludur'**
  String get serverAddressIsRequired;

  /// No description provided for @wroteSender.
  ///
  /// In tr, this message translates to:
  /// **'{sender} yazdı:'**
  String wroteSender(Object sender);

  /// No description provided for @wroteOnDate.
  ///
  /// In tr, this message translates to:
  /// **'{date} tarihinde {sender} yazdı:'**
  String wroteOnDate(Object date, Object sender);

  /// No description provided for @forwardDateLine.
  ///
  /// In tr, this message translates to:
  /// **'Tarih: {date}\n'**
  String forwardDateLine(Object date);

  /// No description provided for @forwardDateLineHtml.
  ///
  /// In tr, this message translates to:
  /// **'<strong>Tarih:</strong> {date}<br>'**
  String forwardDateLineHtml(Object date);

  /// No description provided for @andMorePeople.
  ///
  /// In tr, this message translates to:
  /// **'{names} ve {count} kişi daha'**
  String andMorePeople(Object names, int count);

  /// No description provided for @threadParticipantSummary.
  ///
  /// In tr, this message translates to:
  /// **'{people} · {count} ileti'**
  String threadParticipantSummary(Object people, int count);

  /// No description provided for @recipientToMe.
  ///
  /// In tr, this message translates to:
  /// **'bana'**
  String get recipientToMe;

  /// No description provided for @recipientToName.
  ///
  /// In tr, this message translates to:
  /// **'{name}’ye'**
  String recipientToName(Object name);

  /// No description provided for @couldntAddPhoto.
  ///
  /// In tr, this message translates to:
  /// **'Fotoğraf eklenemedi: {error}'**
  String couldntAddPhoto(Object error);

  /// No description provided for @couldntAddPhotos.
  ///
  /// In tr, this message translates to:
  /// **'Fotoğraflar eklenemedi: {error}'**
  String couldntAddPhotos(Object error);

  /// No description provided for @emailCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} e-posta'**
  String emailCount(int count);

  /// No description provided for @couldntReadSharedFiles.
  ///
  /// In tr, this message translates to:
  /// **'{count, plural, =1{Paylaşılan dosya okunamadı: {names}} other{Paylaşılan {count} dosya okunamadı: {names}}}'**
  String couldntReadSharedFiles(int count, Object names);

  /// No description provided for @earlierMessages.
  ///
  /// In tr, this message translates to:
  /// **'Önceki iletiler'**
  String get earlierMessages;

  /// No description provided for @conversationMessageCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} ileti'**
  String conversationMessageCount(int count);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'tr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'tr':
      return AppLocalizationsTr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
