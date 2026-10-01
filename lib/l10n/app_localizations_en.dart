// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get mailReconciliationPending =>
      'Moved on the server; waiting for folder sync.';

  @override
  String get mailReconciliationRetry =>
      'The message is syncing to its destination folder. Try again shortly.';

  @override
  String get pressBackAgainToExit => 'Press back again to exit.';

  @override
  String get draftSavedLocallyServerSync =>
      'Draft saved locally; server sync failed.';

  @override
  String outgoingMessagesAreWaitingFor(int attention) {
    String _temp0 = intl.Intl.pluralLogic(
      attention,
      locale: localeName,
      other:
          '$attention outgoing messages are waiting for review in the Outbox.',
      one: '1 outgoing message is waiting for review in the Outbox.',
    );
    return '$_temp0';
  }

  @override
  String get open => 'Open';

  @override
  String get couldntOpenTheOutboxTry => 'Couldn’t open the Outbox. Try again.';

  @override
  String get full => 'Full';

  @override
  String get senderSubjectAndAShort => 'Sender, subject and a short preview';

  @override
  String get limited => 'Limited';

  @override
  String get senderAndSubject => 'Sender and subject';

  @override
  String get private => 'Private';

  @override
  String get onlyNewEmail => 'Only “New email”';

  @override
  String get inboxSent => 'Inbox + Sent';

  @override
  String get allFolders => 'All folders';

  @override
  String get selectedFolders => 'Selected folders';

  @override
  String thisFileExceedsTheMaximum(Object value) {
    return 'This file exceeds the maximum allowed size ($value).';
  }

  @override
  String theTotalSizeOfAttachments(Object value) {
    return 'The total size of attachments exceeds the allowed limit ($value).';
  }

  @override
  String get attachmentCountLimitExceeded => 'Attachment count limit exceeded.';

  @override
  String get anAttachmentExceedsTheMaximum =>
      'An attachment exceeds the maximum allowed size.';

  @override
  String get file => 'File';

  @override
  String get sent => 'Sent';

  @override
  String get trash => 'Trash';

  @override
  String get archive => 'Archive';

  @override
  String get other => 'Other';

  @override
  String get inbox => 'Inbox';

  @override
  String get allMail => 'All mail';

  @override
  String get outbox => 'Outbox';

  @override
  String get pendingEmails => 'Pending Emails';

  @override
  String get starred => 'Starred';

  @override
  String get snoozed => 'Snoozed';

  @override
  String get drafts => 'Drafts';

  @override
  String get enterAValidEmailAddress => 'Enter a valid email address.';

  @override
  String get thisEmailIsAlreadySaved => 'This email is already saved.';

  @override
  String get labelNameCantBeEmpty => 'Label name can’t be empty.';

  @override
  String get theSenderAddressCouldntBe =>
      'The sender address couldn’t be read.';

  @override
  String connected(Object email) {
    return '$email connected.';
  }

  @override
  String get addNewAccount => 'Add new account';

  @override
  String get enterAValidEmailAddress2 => 'Enter a valid email address';

  @override
  String get email => 'Email';

  @override
  String get passwordIsRequired => 'Password is required';

  @override
  String get password => 'Password';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get connect => 'Connect';

  @override
  String get downloadCancelled => 'Download cancelled.';

  @override
  String get share => 'Share';

  @override
  String get downloading => 'Downloading…';

  @override
  String get cancel => 'Cancel';

  @override
  String get thisFileTypeCantBe =>
      'This file type can’t be opened inside the app.';

  @override
  String get theFileCouldntBePreviewed => 'The file couldn’t be previewed.';

  @override
  String get openInAnotherApp => 'Open in another app';

  @override
  String get emptyDocument => '(Empty document)';

  @override
  String get chooseASavedTextOr => 'Choose a saved text or template';

  @override
  String get close => 'Close';

  @override
  String get tryAgain => 'Try again';

  @override
  String get noSavedTextsForThis =>
      'No saved texts for this account.\nSettings > Saved texts and templates';

  @override
  String get downloadAgain => 'Download again';

  @override
  String get remove => 'Remove';

  @override
  String theEmailWillBeSent(Object _secondsLeft) {
    return 'The email will be sent in $_secondsLeft s';
  }

  @override
  String get insertLink => 'Insert link';

  @override
  String get cancel2 => 'Cancel';

  @override
  String get add => 'Add';

  @override
  String get image => 'Image';

  @override
  String get embeddedContent => 'Embedded content';

  @override
  String get addFromContacts => 'Add from contacts';

  @override
  String get to => 'To';

  @override
  String get searchNameOrEmail => 'Search name or email';

  @override
  String get noSavedContactsYet => 'No saved contacts yet.';

  @override
  String get noMatchingContactsFound => 'No matching contacts found.';

  @override
  String get editDraft => 'Edit draft';

  @override
  String get sendNow => 'Send now';

  @override
  String get moreOptions => 'More options';

  @override
  String get schedule => 'Schedule';

  @override
  String get saveDraft => 'Save draft';

  @override
  String get delete => 'Delete';

  @override
  String get addCcBcc => 'Add Cc / Bcc';

  @override
  String get subject => 'Subject';

  @override
  String get writeYourMessage => 'Write your message';

  @override
  String get from => 'From';

  @override
  String get chooseIdentity => 'Choose identity';

  @override
  String get chooseAccount => 'Choose account';

  @override
  String get attachFile => 'Attach file';

  @override
  String get savedTexts => 'Saved texts';

  @override
  String get anAttachmentCouldntBeDownloaded =>
      'An attachment couldn’t be downloaded. Try again or remove it.';

  @override
  String get attachmentsAreBeingPreparedPlease =>
      'Attachments are being prepared, please wait.';

  @override
  String get chooseFile => 'Choose file';

  @override
  String get choosePhoto => 'Choose photo';

  @override
  String get camera => 'Camera';

  @override
  String get couldntAccessTheCameraCheck =>
      'Couldn’t access the camera. Check permissions or choose a file.';

  @override
  String get couldntAccessPhotosCheckPermissions =>
      'Couldn’t access photos. Check permissions or choose a file.';

  @override
  String get imageSize => 'Image size';

  @override
  String get original => 'Original';

  @override
  String get large2048Px => 'Large (2048 px)';

  @override
  String get medium1280Px => 'Medium (1280 px)';

  @override
  String get small640Px => 'Small (640 px)';

  @override
  String preparingImages(Object completed, Object length) {
    return 'Preparing images… ($completed/$length)';
  }

  @override
  String couldntResizeTheImageThe(Object name) {
    return '$name: Couldn’t resize the image; the original file will be used.';
  }

  @override
  String get couldntSaveTheDraftTry => 'Couldn’t save the draft. Try again.';

  @override
  String get youCanSaveWhatYouve =>
      'You can save what you’ve written to finish later, or delete the draft permanently.';

  @override
  String get couldntSaveTheDraftYour =>
      'Couldn’t save the draft. Your content is kept on screen.';

  @override
  String get draftSaved => 'Draft saved.';

  @override
  String get saving => 'Saving…';

  @override
  String get saveDraft2 => 'Save draft';

  @override
  String get deleteDraft => 'Delete draft';

  @override
  String get keepEditing => 'Keep editing';

  @override
  String get thisActionCantBeUndone => 'This action can’t be undone.';

  @override
  String couldntDeleteTheDraft(Object value) {
    return 'Couldn’t delete the draft: $value';
  }

  @override
  String get draftDeleted => 'Draft deleted.';

  @override
  String get youMustEnterAtLeast => 'You must enter at least one recipient.';

  @override
  String get fixTheInvalidEmailAddresses =>
      'Fix the invalid email addresses and try again.';

  @override
  String couldntSaveTheMessage(Object value) {
    return 'Couldn’t save the message: $value';
  }

  @override
  String get undo => 'Undo';

  @override
  String get aReadReceiptWillBe =>
      'A read receipt will be requested from recipients.';

  @override
  String get pleaseChooseAFutureDate => 'Please choose a future date and time.';

  @override
  String theEmailIsScheduledTo(Object value) {
    return 'The email is scheduled to be sent on $value.';
  }

  @override
  String couldntSchedule(Object value) {
    return 'Couldn’t schedule: $value';
  }

  @override
  String couldntLoadTheSenderIdentity(Object value) {
    return 'Couldn’t load the sender identity: $value';
  }

  @override
  String get replaceTheSubject => 'Replace the subject?';

  @override
  String get theCurrentSubjectWillBe =>
      'The current subject will be replaced with the saved text’s subject.';

  @override
  String get keepSubject => 'Keep subject';

  @override
  String get replace => 'Replace';

  @override
  String get manageFolders => 'Manage folders';

  @override
  String get whichAccountsFoldersDoYou =>
      'Which account’s folders do you want to manage?';

  @override
  String get folder => 'Folder';

  @override
  String get chooseParentFolder => 'Choose parent folder';

  @override
  String get topLevelFolder => 'Top-level folder';

  @override
  String get newFolder => 'New folder';

  @override
  String get createSubfolder => 'Create subfolder';

  @override
  String get folderCreated => 'Folder created.';

  @override
  String get rename => 'Rename';

  @override
  String get folderRenamed => 'Folder renamed.';

  @override
  String get parentFolderChanged => 'Parent folder changed.';

  @override
  String get folderCantBeDeleted => 'Folder can’t be deleted';

  @override
  String get ok => 'OK';

  @override
  String get deleteFolder => 'Delete folder?';

  @override
  String theFolderWillBePermanently(Object name) {
    return 'The folder “$name” will be permanently deleted from the server.';
  }

  @override
  String get folderDeleted => 'Folder deleted.';

  @override
  String whatShouldBeUsedAs(Object name) {
    return 'What should “$name” be used as?';
  }

  @override
  String isNowUsedAs(Object name, Object value) {
    return '“$name” is now used as $value.';
  }

  @override
  String automaticDetectionRestoredFor(Object name) {
    return 'Automatic detection restored for “$name”.';
  }

  @override
  String synced(Object name) {
    return '“$name” synced.';
  }

  @override
  String willSyncAutomatically(Object name) {
    return '“$name” will sync automatically.';
  }

  @override
  String willNotSyncAutomatically(Object name) {
    return '“$name” will not sync automatically.';
  }

  @override
  String get folders => 'Folders';

  @override
  String get rescanFoldersOnTheServer => 'Rescan folders on the server';

  @override
  String get folderNotFound => 'Folder not found';

  @override
  String usedAs(Object value) {
    return 'Used as $value';
  }

  @override
  String get standardFolders => 'Standard folders';

  @override
  String get myFolders => 'My folders';

  @override
  String get spam => 'Spam';

  @override
  String get showSubfolders => 'Show subfolders';

  @override
  String get hideSubfolders => 'Hide subfolders';

  @override
  String unread(Object unreadCount) {
    return '$unreadCount unread';
  }

  @override
  String get syncingAutomatically => 'Syncing automatically';

  @override
  String get changeParentFolder => 'Change parent folder';

  @override
  String get assignFolderRole => 'Assign folder role';

  @override
  String get revertToAutomatic => 'Revert to automatic';

  @override
  String get syncNow => 'Sync now';

  @override
  String get turnOffAutomaticSync => 'Turn off automatic sync';

  @override
  String get turnOnAutomaticSync => 'Turn on automatic sync';

  @override
  String get folderName => 'Folder name';

  @override
  String get save => 'Save';

  @override
  String get anActionTakenWhileOffline =>
      'An action taken while offline couldn’t be applied. The latest state was loaded from the server.';

  @override
  String get syncingAccounts => 'Syncing accounts…';

  @override
  String get accountsSynced => 'Accounts synced.';

  @override
  String get syncStatusNotFoundTry => 'Sync status not found. Try again.';

  @override
  String get allInboxes => 'All Inboxes';

  @override
  String emailsDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count emails deleted',
      one: '1 email deleted',
    );
    return '$_temp0';
  }

  @override
  String draftsDeleted(int length) {
    String _temp0 = intl.Intl.pluralLogic(
      length,
      locale: localeName,
      other: '$length drafts deleted',
      one: '1 draft deleted',
    );
    return '$_temp0';
  }

  @override
  String actionFailed(Object value) {
    return 'Action failed: $value';
  }

  @override
  String emailsPermanentlyDeleted(int length) {
    String _temp0 = intl.Intl.pluralLogic(
      length,
      locale: localeName,
      other: '$length emails permanently deleted',
      one: '1 email permanently deleted',
    );
    return '$_temp0';
  }

  @override
  String emailsArchived(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count emails archived',
      one: '1 email archived',
    );
    return '$_temp0';
  }

  @override
  String emailsMovedToSpam(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count emails moved to spam',
      one: '1 email moved to spam',
    );
    return '$_temp0';
  }

  @override
  String emailsRestored(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count emails restored',
      one: '1 email restored',
    );
    return '$_temp0';
  }

  @override
  String emailsUnarchived(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count emails unarchived',
      one: '1 email unarchived',
    );
    return '$_temp0';
  }

  @override
  String emailsMarkedAsNotSpam(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count emails marked as not spam',
      one: '1 email marked as not spam',
    );
    return '$_temp0';
  }

  @override
  String get theseEmailsAreAlreadyBeing =>
      'These emails are already being processed.';

  @override
  String get undo2 => 'Undo';

  @override
  String emailsMoved(int length) {
    String _temp0 = intl.Intl.pluralLogic(
      length,
      locale: localeName,
      other: '$length emails moved.',
      one: '1 email moved.',
    );
    return '$_temp0';
  }

  @override
  String get newEmail => 'New email';

  @override
  String get search => 'Search';

  @override
  String get restore => 'Restore';

  @override
  String get deletePermanently => 'Delete permanently';

  @override
  String get markAsRead => 'Mark as read';

  @override
  String get markAsUnread => 'Mark as unread';

  @override
  String get archive2 => 'Archive';

  @override
  String get unarchive => 'Unarchive';

  @override
  String get removeStar => 'Remove star';

  @override
  String get star => 'Star';

  @override
  String get unpin => 'Unpin';

  @override
  String get pin => 'Pin';

  @override
  String get removeSnooze => 'Remove snooze';

  @override
  String get snooze => 'Snooze';

  @override
  String get moveToSpam => 'Move to spam';

  @override
  String get notSpam => 'Not spam';

  @override
  String get removeLabel => 'Remove label';

  @override
  String get label => 'Label';

  @override
  String get move => 'Move';

  @override
  String get selectAll => 'Select all';

  @override
  String get cancelSelection => 'Cancel selection';

  @override
  String get n1Selected => '1 selected';

  @override
  String selected(Object count) {
    return '$count selected';
  }

  @override
  String get selectAnEmailToView => 'Select an email to view it';

  @override
  String get noConnectionShowingTheLatest =>
      'No connection. Showing the latest cached mail.';

  @override
  String get restore2 => 'Restore';

  @override
  String get readUnread => 'Read / unread';

  @override
  String get star2 => 'Star';

  @override
  String get justNow => 'just now';

  @override
  String minutesAgo(int inMinutes) {
    String _temp0 = intl.Intl.pluralLogic(
      inMinutes,
      locale: localeName,
      other: '$inMinutes minutes ago',
      one: '1 minute ago',
    );
    return '$_temp0';
  }

  @override
  String hoursAgo(int inHours) {
    String _temp0 = intl.Intl.pluralLogic(
      inHours,
      locale: localeName,
      other: '$inHours hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String daysAgo(int inDays) {
    String _temp0 = intl.Intl.pluralLogic(
      inDays,
      locale: localeName,
      other: '$inDays days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String get tryLoadingMoreAgain => 'Try loading more again';

  @override
  String get noMailMatchesThisFilter => 'No mail matches this filter';

  @override
  String get clearFilter => 'Clear filter';

  @override
  String get newEmailsWillAppearHere =>
      'New emails will appear here when they arrive.';

  @override
  String get emailsFromYourConnectedAccounts =>
      'Emails from your connected accounts appear here.';

  @override
  String get emailsYouSendAppearHere => 'Emails you send appear here.';

  @override
  String get emailsYouStarAppearHere => 'Emails you star appear here.';

  @override
  String get emailsYouSnoozeAppearHere => 'Emails you snooze appear here.';

  @override
  String get draftsYouSaveAreKept => 'Drafts you save are kept here.';

  @override
  String get emailsYouDeleteAreKept => 'Emails you delete are kept here.';

  @override
  String get unwantedEmailsEndUpHere => 'Unwanted emails end up here.';

  @override
  String get emailsYouArchiveAreKept => 'Emails you archive are kept here.';

  @override
  String get offline => 'Offline';

  @override
  String isEmpty(Object label) {
    return '$label is empty';
  }

  @override
  String get noInternetConnectionNewMail =>
      'No internet connection. New mail will appear once you’re connected.';

  @override
  String get refresh => 'Refresh';

  @override
  String get youreOffline => 'You’re offline';

  @override
  String get yourEmailsCouldntBeLoaded => 'Your emails couldn’t be loaded';

  @override
  String get noInternetConnectionItWill =>
      'No internet connection. It will update automatically once you’re connected.';

  @override
  String get accountReconnected => 'Account reconnected.';

  @override
  String get signInFailedTryAgain => 'Sign-in failed. Try again.';

  @override
  String get serverAddress => 'Server address';

  @override
  String get aSecureAppForYour => 'A secure app for your email';

  @override
  String get continueLabel => 'Continue';

  @override
  String get back => 'Back';

  @override
  String get youAreReconnectingThisAccount =>
      'You are reconnecting this account';

  @override
  String get youAreSigningInWith => 'You are signing in with this account';

  @override
  String get reconnect => 'Reconnect';

  @override
  String get signIn => 'Sign in';

  @override
  String get hideQuote => 'Hide quote';

  @override
  String get showQuote => 'Show quote';

  @override
  String get showSignature => 'Show signature';

  @override
  String get hideSignature => 'Hide signature';

  @override
  String get remoteImagesWereBlockedIn =>
      'Remote images were blocked in this message for security.';

  @override
  String get loadImages => 'Load images';

  @override
  String get cancelDownload => 'Cancel download';

  @override
  String get ready => 'Ready';

  @override
  String get downloadAttachment => 'Download attachment';

  @override
  String get sendingReply => 'Sending reply';

  @override
  String get replySent => 'Reply sent';

  @override
  String get emailSent => 'Email sent.';

  @override
  String couldntSendTheReply(Object value) {
    return 'Couldn’t send the reply: $value';
  }

  @override
  String get writeAQuickReply => 'Write a quick reply…';

  @override
  String get sendReply => 'Send reply';

  @override
  String get more => 'More';

  @override
  String get replyAll => 'Reply all';

  @override
  String get reply => 'Reply';

  @override
  String get forward => 'Forward';

  @override
  String get print => 'Print';

  @override
  String get shareAsPdf => 'Share as PDF';

  @override
  String get unsubscribe => 'Unsubscribe';

  @override
  String get showAllHeaders => 'Show all headers';

  @override
  String get showRawMime => 'Show raw MIME';

  @override
  String get thisEmailNoLongerExists => 'This email no longer exists.';

  @override
  String get messageActions => 'Message actions';

  @override
  String get from2 => 'From: ';

  @override
  String get to2 => 'To: ';

  @override
  String get cc => 'Cc: ';

  @override
  String get bcc => 'Bcc: ';

  @override
  String get date => 'Date: ';

  @override
  String signedByNotVerified(Object value) {
    return 'Signed by $value (not verified)';
  }

  @override
  String encryptedByCantBeOpened(Object value) {
    return 'Encrypted by $value (can’t be opened)';
  }

  @override
  String get trackingContentBlocked => 'Tracking content blocked';

  @override
  String get attachments => 'Attachments';

  @override
  String get replyAll2 => 'Reply all';

  @override
  String get noRecipients => 'no recipients';

  @override
  String get youCanPinAtMost => 'You can pin at most 3 emails.';

  @override
  String emailMovedTo(Object label) {
    return 'Email moved to $label.';
  }

  @override
  String get emailRestored => 'Email restored.';

  @override
  String get emailMarkedAsNotSpam => 'Email marked as not spam.';

  @override
  String get emailUnarchived => 'Email unarchived.';

  @override
  String get emailPermanentlyDeleted => 'Email permanently deleted.';

  @override
  String get unsubscribe2 => 'Unsubscribe?';

  @override
  String get aRequestWillBeSent =>
      'A request will be sent to stop receiving email from this sender. This can’t be undone.';

  @override
  String get unsubscribeStarted => 'Unsubscribe started.';

  @override
  String get unsubscribingFailed => 'Unsubscribing failed.';

  @override
  String printingFailed(Object value) {
    return 'Printing failed: $value';
  }

  @override
  String sharingThePdfFailed(Object value) {
    return 'Sharing the PDF failed: $value';
  }

  @override
  String couldntPrepareTheReply(Object value) {
    return 'Couldn’t prepare the reply: $value';
  }

  @override
  String forwardedMessageFromSubject(
    Object sender,
    Object dateLine,
    Object subject,
    Object bodyText,
  ) {
    return '\n\n--- Forwarded message ---\nFrom: $sender\n${dateLine}Subject: $subject\n\n$bodyText';
  }

  @override
  String forwardedMessageFromSubject2(
    Object value,
    Object value2,
    Object value3,
    Object originalHtml,
  ) {
    return '<p><br></p><p>--- Forwarded message ---<br><strong>From:</strong> $value<br>$value2<strong>Subject:</strong> $value3</p>$originalHtml';
  }

  @override
  String get allHeaders => 'All headers';

  @override
  String get rawMime => 'Raw MIME';

  @override
  String get signatureVerification => 'Signature verification';

  @override
  String couldntGetTheMessageSource(Object value) {
    return 'Couldn’t get the message source: $value';
  }

  @override
  String get signatureAndCertificateChainVerified =>
      'Signature and certificate chain verified';

  @override
  String get signatureMatchesCertificateIsntTrusted =>
      'Signature matches; certificate isn’t trusted';

  @override
  String get signatureIsInvalid => 'Signature is invalid';

  @override
  String get signatureCouldntBeVerified => 'Signature couldn’t be verified';

  @override
  String get openpgpKeyManagementAndVerification =>
      'OpenPGP key management and verification aren’t supported.';

  @override
  String get unknownSigner => 'Unknown signer';

  @override
  String signatureDate(Object value) {
    return 'Signature date: $value';
  }

  @override
  String certificateExpires(Object value) {
    return 'Certificate expires: $value';
  }

  @override
  String get accountNotifications => 'Account notifications';

  @override
  String get theseSettingsApplyOnEvery =>
      'These settings apply on every device where the account is signed in. You can turn off notifications on this device under Settings > General settings > Notifications.';

  @override
  String get notifications => 'Notifications';

  @override
  String get inboxOnly => 'Inbox only';

  @override
  String get whenOffSyncedFoldersOther =>
      'When off, synced folders other than Sent, Drafts, Trash and Spam are notified too.';

  @override
  String get lockScreenPrivacy => 'Lock screen privacy';

  @override
  String get notificationsAreSentAsPrivate =>
      'Notifications are sent as Private because the server turned previews off.';

  @override
  String get editMessage => 'Edit message';

  @override
  String get newMessage => 'New message';

  @override
  String get createANewMessage => 'Create a new message?';

  @override
  String get checkSentFirstThisMessage =>
      'Check Sent first. This message may already have been delivered; sending it again could give the recipient a second copy.';

  @override
  String get newMessage2 => 'New message';

  @override
  String get deleteMessage => 'Delete message?';

  @override
  String get theDeliveryResultIsUnknown =>
      'The delivery result is unknown. Check Sent first. Delete the local copy?';

  @override
  String get theLocalCopyOfThis =>
      'The local copy of this message will be permanently deleted.';

  @override
  String get noPendingMessages => 'No pending messages.';

  @override
  String get undoPeriod => 'Undo period';

  @override
  String get sending => 'Sending';

  @override
  String get waitingForConnection => 'Waiting for connection';

  @override
  String get couldntSend => 'Couldn’t send';

  @override
  String get resultUnknown => 'Result unknown';

  @override
  String to3(Object value) {
    return 'To: $value';
  }

  @override
  String get noInternetConnectionItWillBeSentAutomatically =>
      'No internet connection. It will be sent automatically once you’re connected.';

  @override
  String get checkSentBeforeSendingAgain => 'Check Sent before sending again.';

  @override
  String get tryNow => 'Try now';

  @override
  String get edit => 'Edit';

  @override
  String get recreateManually => 'Recreate manually';

  @override
  String get viewContent => 'View content';

  @override
  String get scheduledSends => 'Scheduled sends';

  @override
  String get scheduled => 'Scheduled';

  @override
  String get sent2 => 'Sent';

  @override
  String get cancelled => 'Cancelled';

  @override
  String get resultUnknownCheckSent => 'Result unknown — check Sent';

  @override
  String get cancelScheduledSend => 'Cancel scheduled send';

  @override
  String cancelTheSendOf(Object value) {
    return 'Cancel the send of “$value”?';
  }

  @override
  String get cancelSend => 'Cancel send';

  @override
  String get sendCancelled => 'Send cancelled.';

  @override
  String get chooseAtLeastOneRecipient =>
      'Choose at least one recipient and a future date.';

  @override
  String get scheduledSendUpdated => 'Scheduled send updated.';

  @override
  String get sendReQueued => 'Send re-queued.';

  @override
  String get failedSend => 'Failed send';

  @override
  String get editScheduledSend => 'Edit scheduled send';

  @override
  String get sendFailed => 'Send failed';

  @override
  String get recipients => 'Recipients';

  @override
  String get content => 'Content';

  @override
  String get body => 'Body';

  @override
  String get sendTime => 'Send time';

  @override
  String get addAttachment => 'Add attachment';

  @override
  String get retry => 'Retry';

  @override
  String get loadMoreResults => 'Load more results';

  @override
  String searchResultCount(int shown, int total) {
    return '$shown of $total results';
  }

  @override
  String get offlineSearchResults =>
      'Offline accounts show only matches available on this device.';

  @override
  String get cancelSend2 => 'Cancel send';

  @override
  String get noScheduledSends => 'No scheduled sends';

  @override
  String get scheduleASendWithThe =>
      'While composing, choose “Schedule” from the top-right menu. Scheduled messages appear here.';

  @override
  String newEmailsAdded(int imported) {
    String _temp0 = intl.Intl.pluralLogic(
      imported,
      locale: localeName,
      other: '$imported new emails added.',
      one: '1 new email added.',
    );
    return 'Server scan finished. $_temp0';
  }

  @override
  String scanningTheServer(int imported, Object remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      imported,
      locale: localeName,
      other: '$imported new emails added',
      one: '1 new email added',
    );
    return 'Scanning the server… $_temp0; $remaining matches left.';
  }

  @override
  String serverScanStopped(int imported, Object remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      imported,
      locale: localeName,
      other: '$imported new emails added',
      one: '1 new email added',
    );
    return 'Server scan stopped. $_temp0; $remaining matches couldn’t be fetched. Try again.';
  }

  @override
  String get searchEmail => 'Search email';

  @override
  String get clear => 'Clear';

  @override
  String get filters => 'Filters';

  @override
  String get searchingTheServer => 'Searching the server…';

  @override
  String get startTypingToSearch => 'Start typing to search.';

  @override
  String get noResultsMatchTheSelected =>
      'No results match the selected filters.';

  @override
  String noResultsFor(Object value) {
    return 'No results for “$value”.';
  }

  @override
  String get theMailboxIsStillSyncing =>
      'The mailbox is still syncing. Search results may be incomplete.';

  @override
  String folder2(Object label) {
    return 'Folder: $label';
  }

  @override
  String folder3(Object name) {
    return 'Folder: $name';
  }

  @override
  String from3(Object value) {
    return 'From: $value';
  }

  @override
  String to4(Object value) {
    return 'To: $value';
  }

  @override
  String get read => 'Read';

  @override
  String get unread2 => 'Unread';

  @override
  String get starred2 => 'Starred';

  @override
  String get clearFilters => 'Clear filters';

  @override
  String get advancedFilters => 'Advanced filters';

  @override
  String get account => 'Account';

  @override
  String get allAccounts => 'All accounts';

  @override
  String get all => 'All';

  @override
  String get eGNameCompanyCom => 'e.g. name@company.com';

  @override
  String get dateRange => 'Date range';

  @override
  String get start => 'Start';

  @override
  String get end => 'End';

  @override
  String get status => 'Status';

  @override
  String get any => 'Any';

  @override
  String get hasAttachment => 'Has attachment';

  @override
  String get apply => 'Apply';

  @override
  String get filtersAreCombinedWithAnd => 'Filters are combined with AND.';

  @override
  String get startTypingToSearchOr => 'Start typing to search or filter';

  @override
  String get searchingTheServerAcrossAll =>
      'Searching the server across all accounts';

  @override
  String searchingIn(Object accountEmail) {
    return 'Searching in $accountEmail';
  }

  @override
  String get accountSettings => 'Account settings';

  @override
  String get theAccountIsNoLonger => 'The account is no longer connected.';

  @override
  String get signatures => 'Signatures';

  @override
  String get createEmailSignaturesAndChoose =>
      'Create email signatures and choose the default';

  @override
  String get savedTexts2 => 'Saved texts';

  @override
  String get reusableSubjectsAndTexts => 'Reusable subjects and texts';

  @override
  String get labels => 'Labels';

  @override
  String get createEditAndDeleteLabels => 'Create, edit and delete labels';

  @override
  String get contacts => 'Contacts';

  @override
  String get contactsSuggestedWhileTyping => 'Contacts suggested while typing';

  @override
  String get folderTreeRolesAndSync => 'Folder tree, roles and sync';

  @override
  String get syncLabel => 'Sync';

  @override
  String get perFolderStatusAndFolders =>
      'Per-folder status and folders to sync';

  @override
  String get folderScopeAndLockScreen => 'Folder scope and lock screen privacy';

  @override
  String get savedImagePreferences => 'Saved image preferences';

  @override
  String get trustedSendersAndDomains => 'Trusted senders and domains';

  @override
  String get security => 'Security';

  @override
  String get connectedDevices => 'Connected devices';

  @override
  String get devicesAndSessionsSignedIn =>
      'Devices and sessions signed in to this account';

  @override
  String get disconnected => 'Disconnected';

  @override
  String get connectionProblem => 'Connection problem';

  @override
  String get disabled => 'Disabled';

  @override
  String get updatePassword => 'Update password';

  @override
  String get signOutOnThisDevice => 'Sign out on this device';

  @override
  String get theAccountStaysOnThe =>
      'The account stays on the server; only the session and data on this device are deleted.';

  @override
  String get signOut => 'Sign out?';

  @override
  String willBeSignedOutOn(Object email) {
    return '$email will be signed out on this device. The account and emails on the server aren’t deleted.';
  }

  @override
  String get signOut2 => 'Sign out';

  @override
  String get removeAccount => 'Remove account';

  @override
  String get deletesTheConnectionFromThe =>
      'Deletes the connection from the server; the emails are removed from this app.';

  @override
  String get removeAccount2 => 'Remove account?';

  @override
  String willBeRemovedAndIts(Object email) {
    return '$email will be removed and its emails deleted from the app. Are you sure?';
  }

  @override
  String get storage => 'Storage';

  @override
  String ofUsed(Object value, Object value2, Object usedPercent) {
    return '$value of $value2 used ($usedPercent%)';
  }

  @override
  String get storageUsage => 'Storage usage';

  @override
  String get noContactsAddedYet => 'No contacts added yet.';

  @override
  String get newContact => 'New contact';

  @override
  String get deleteContact => 'Delete contact?';

  @override
  String willBeRemovedFromThe(Object value) {
    return '“$value” will be removed from the contact list.';
  }

  @override
  String get yesDelete => 'Yes, delete';

  @override
  String get editContact => 'Edit contact';

  @override
  String get nameOptional => 'Name (optional)';

  @override
  String get contactsPermissionWasntGrantedSuggestions =>
      'Contacts permission wasn’t granted. Suggestions keep coming from your mail history and the contacts you add.';

  @override
  String get suggestDeviceContacts => 'Suggest device contacts';

  @override
  String get alsoSuggestsEmailAddressesFrom =>
      'Also suggests email addresses from your phone’s address book while you type recipients. The address book is only read on this device and isn’t sent to the server.';

  @override
  String get showNewEmailNotificationsOn =>
      'Show new email notifications on this device. Folder scope and lock screen privacy are in each account’s own settings.';

  @override
  String get followsTheDeviceTheme => 'Follows the device theme';

  @override
  String get light => 'Light';

  @override
  String get dark => 'Dark';

  @override
  String get swipeGestures => 'Swipe gestures';

  @override
  String get swipeAnEmailRightOr =>
      'Swipe an email right or left in the list to run the actions below. Trash, Spam and Archive folders use their own actions.';

  @override
  String get onSwipeRight => 'On swipe right';

  @override
  String get onSwipeLeft => 'On swipe left';

  @override
  String get undoSendPeriod => 'Undo send period';

  @override
  String get blue => 'Blue';

  @override
  String get green => 'Green';

  @override
  String get orange => 'Orange';

  @override
  String get darkRed => 'Dark red';

  @override
  String get red => 'Red';

  @override
  String get turquoise => 'Turquoise';

  @override
  String get purple => 'Purple';

  @override
  String get redOrange => 'Red-orange';

  @override
  String get newLabel => 'New label';

  @override
  String customColor(Object value) {
    return 'Custom color $value';
  }

  @override
  String get chooseCustomColor => 'Choose custom color';

  @override
  String get deleteLabel => 'Delete label?';

  @override
  String theLabelWillBeRemoved(Object value) {
    return 'The label “$value” will be removed. Emails aren’t deleted; only this label is removed from them.';
  }

  @override
  String get editLabel => 'Edit label';

  @override
  String get name => 'Name';

  @override
  String get create => 'Create';

  @override
  String get apiConnection => 'API connection';

  @override
  String get checkingConnection => 'Checking connection…';

  @override
  String get serverAndServicesAreReady => 'Server and services are ready';

  @override
  String get couldntConnect => 'Couldn’t connect';

  @override
  String get checkConnectionAgain => 'Check connection again';

  @override
  String get sync => 'Sync';

  @override
  String get serverConnection => 'Server connection';

  @override
  String get thisSettingOnlyControlsHow =>
      'This setting only controls how often the list you see refreshes while the app is open. The server already syncs your email in the background at regular intervals regardless of this setting; new mail notifications don’t wait for it.';

  @override
  String get autoRefreshNetwork => 'Auto-refresh network';

  @override
  String get pauseOnBatterySaver => 'Pause on battery saver';

  @override
  String get whenBatterySaverIsOn =>
      'When battery saver is on, auto-refresh doesn’t run; pull-to-refresh and notifications keep working.';

  @override
  String get clearAttachmentCache => 'Clear attachment cache?';

  @override
  String downloadedAttachmentsTakingUpWill(Object _sizeLabel) {
    return 'Downloaded attachments taking up $_sizeLabel will be deleted.';
  }

  @override
  String get attachmentCacheCleared => 'Attachment cache cleared.';

  @override
  String get attachmentsAreDownloadedAutomaticallyOnly =>
      'Attachments are downloaded automatically only when a mail is opened, on the selected network, and under the size limit.';

  @override
  String autoDownloadLimit(Object label) {
    return 'Auto-download limit: $label';
  }

  @override
  String get clearAttachmentCache2 => 'Clear attachment cache';

  @override
  String get calculatingSize => 'Calculating size…';

  @override
  String get removeLinkTrackingParameters => 'Remove link tracking parameters';

  @override
  String get removesKnownAdvertisingAndCampaign =>
      'Removes known advertising and campaign tracking parameters from links in emails before opening them.';

  @override
  String get appLock => 'App lock';

  @override
  String get asksForFingerprintFaceId =>
      'Asks for fingerprint/Face ID or the device passcode when you open the app or after it has been in the background longer than the chosen time.';

  @override
  String get lockWhenReturningFromBackground =>
      'Lock when returning from background';

  @override
  String get screenProtection => 'Screen protection';

  @override
  String get hidesMailContentInThe => 'Hides mail content in the app switcher.';

  @override
  String get blocksScreenshotsAndScreenRecording =>
      'Blocks screenshots and screen recording and hides content in the recent apps list.';

  @override
  String couldntLoadDevices(Object value) {
    return 'Couldn’t load devices: $value';
  }

  @override
  String get signOutOfThisSession => 'Sign out of this session?';

  @override
  String get theSessionOnThisDevice =>
      'The session on this device will be closed and this account will be signed out.';

  @override
  String get thisDeviceWillNoLonger =>
      'This device will no longer be able to access this account.';

  @override
  String couldntSignOut(Object value) {
    return 'Couldn’t sign out: $value';
  }

  @override
  String get noConnectedDevices => 'No connected devices.';

  @override
  String lastUsed(Object value) {
    return 'Last used: $value';
  }

  @override
  String get settings => 'Settings';

  @override
  String get generalSettings => 'General settings';

  @override
  String get appearanceInteractionNotificationsNetworkAnd =>
      'Appearance, interaction, notifications, network and privacy';

  @override
  String get accounts => 'Accounts';

  @override
  String get addAccount => 'Add account';

  @override
  String get connectANewMailAccount => 'Connect a new mail account';

  @override
  String get signatureLabelContactFolderAnd =>
      'Signature, label, contact, folder and notification settings';

  @override
  String get disconnectedUpdateThePassword =>
      'Disconnected — update the password';

  @override
  String get appearance => 'Appearance';

  @override
  String get lightDarkOrSystemTheme => 'Light, dark or system theme';

  @override
  String get language => 'Language';

  @override
  String get tRkEOrEnglish => 'Türkçe or English';

  @override
  String get interaction => 'Interaction';

  @override
  String get swipeUndoSendAndDevice => 'Swipe, undo send and device contacts';

  @override
  String get newEmailNotificationsOnThis =>
      'New email notifications on this device';

  @override
  String get network => 'Network';

  @override
  String get refreshAttachmentsAndServer => 'Refresh, attachments and server';

  @override
  String get privacy => 'Privacy';

  @override
  String get appLockScreenProtectionAnd =>
      'App lock, screen protection and links';

  @override
  String get deleteSignature => 'Delete signature?';

  @override
  String theSignatureWillBePermanently(Object name) {
    return 'The signature “$name” will be permanently deleted.';
  }

  @override
  String get none => 'None';

  @override
  String get noConnectedAccountFound => 'No connected account found.';

  @override
  String get newSignature => 'New signature';

  @override
  String get newEmail2 => 'New email';

  @override
  String get reply2 => 'Reply';

  @override
  String get noSignaturesYet => 'No signatures yet';

  @override
  String get signatureNameMustBe1 => 'Signature name must be 1-100 characters.';

  @override
  String get enterTheSignatureText => 'Enter the signature text.';

  @override
  String get editSignature => 'Edit signature';

  @override
  String get signatureText => 'Signature text';

  @override
  String get syncScopeSaved => 'Sync scope saved.';

  @override
  String get syncScope => 'Sync scope';

  @override
  String get chooseTheFoldersToUpdate =>
      'Choose the folders to update in the background. Other folders still refresh when opened.';

  @override
  String get chooseAtLeastOneFolder => 'Choose at least one folder.';

  @override
  String foldersSyncedInTheBackground(Object value) {
    return 'Folders synced in the background: $value';
  }

  @override
  String get syncStatus => 'Sync status';

  @override
  String get noConnectedAccounts => 'No connected accounts.';

  @override
  String get noSyncAttemptsYet => 'No sync attempts yet.';

  @override
  String actionsAreWaitingForA(int queued) {
    String _temp0 = intl.Intl.pluralLogic(
      queued,
      locale: localeName,
      other: '$queued actions are waiting for a connection',
      one: '1 action is waiting for a connection',
    );
    return '$_temp0';
  }

  @override
  String get temporaryProblem => 'Temporary problem';

  @override
  String get authenticationProblem => 'Authentication problem';

  @override
  String get configurationProblem => 'Configuration problem';

  @override
  String get permanentProblem => 'Permanent problem';

  @override
  String get unknownProblem => 'Unknown problem';

  @override
  String get olderMailIsStillBeing => 'Older mail is still being imported';

  @override
  String get noSuccessfulSyncYet => 'No successful sync yet';

  @override
  String get deleteSavedText => 'Delete saved text?';

  @override
  String theSavedTextWillBe(Object name) {
    return 'The saved text “$name” will be permanently deleted.';
  }

  @override
  String get noSavedTextsYet => 'No saved texts yet';

  @override
  String get noSubject => 'No subject';

  @override
  String get newSavedText => 'New saved text';

  @override
  String get savedTextNameMustBe => 'Saved text name must be 1-100 characters.';

  @override
  String get subjectMustBeASingle =>
      'Subject must be a single line and at most 500 characters.';

  @override
  String get enterTheSavedTextBody => 'Enter the saved text body.';

  @override
  String get editSavedText => 'Edit saved text';

  @override
  String get textBody => 'Text body';

  @override
  String get savedImagePreferences2 => 'Saved image preferences';

  @override
  String get noSavedSendersYetRegular =>
      'No saved senders yet.\nRegular images load even without adding them to this list.';

  @override
  String get domain => 'Domain';

  @override
  String get sender => 'Sender';

  @override
  String get theServerDidntRespondPlease =>
      'The server didn’t respond. Please try again.';

  @override
  String get checkYourInternetConnection => 'Check your internet connection.';

  @override
  String get wrongPassword => 'Wrong password.';

  @override
  String get yourSessionExpiredPleaseSign =>
      'Your session expired. Please sign in again.';

  @override
  String get accessHasntBeenEnabledFor =>
      'Access hasn’t been enabled for this email address yet.';

  @override
  String get thisMailAccountHasBeen => 'This mail account has been disabled.';

  @override
  String get thisAccountIsAlreadyConnected =>
      'This account is already connected.';

  @override
  String get aTemplateWithThisName =>
      'A template with this name already exists.';

  @override
  String get noRegisteredAccountFoundFor =>
      'No registered account found for this email.';

  @override
  String get automaticServerDiscoveryFailed =>
      'Automatic server discovery failed.';

  @override
  String get serverDiscoveryTimedOutTry =>
      'Server discovery timed out. Try again.';

  @override
  String get theServerSettingsArentSecure =>
      'The server settings aren’t secure.';

  @override
  String get couldntReachTheMailServer =>
      'Couldn’t reach the mail server. Try again.';

  @override
  String get emailNotFound => 'Email not found.';

  @override
  String get thisDraftIsNoLonger => 'This draft is no longer valid.';

  @override
  String get theMailFolderIsUnavailable => 'The mail folder is unavailable.';

  @override
  String get thisActionIsntSupportedFor =>
      'This action isn’t supported for this email.';

  @override
  String get theMailboxChangedRefreshAnd =>
      'The mailbox changed. Refresh and try again.';

  @override
  String get couldntMoveTheEmailTry => 'Couldn’t move the email. Try again.';

  @override
  String get couldntPermanentlyDeleteTheEmail =>
      'Couldn’t permanently delete the email. Try again.';

  @override
  String get theActionCouldntBeCompleted =>
      'The action couldn’t be completed. Try again.';

  @override
  String get youCanPinAtMost3EmailsPer =>
      'You can pin at most 3 emails per account.';

  @override
  String get theDraftHasntMatchedOn =>
      'The draft hasn’t matched on the server yet. Try again in a few seconds.';

  @override
  String get theSendResultIsUnknown =>
      'The send result is unknown. Check Sent.';

  @override
  String get theMessageIsBeingSent =>
      'The message is being sent. Try again shortly.';

  @override
  String get theSendRequestIsInvalid =>
      'The send request is invalid. Try again.';

  @override
  String get theSendRequestWasUsed =>
      'The send request was used before with different content. Create a new message.';

  @override
  String get theRecipientAddressIsInvalid =>
      'The recipient address is invalid.';

  @override
  String get invalidEmailAddress => 'Invalid email address.';

  @override
  String get theEmailHeadersAreInvalid => 'The email headers are invalid.';

  @override
  String get theEmailCouldntBeCreated => 'The email couldn’t be created.';

  @override
  String get theServerSettingsAreInvalid => 'The server settings are invalid.';

  @override
  String get thisSignInMethodIsnt =>
      'This sign-in method isn’t set up on the server.';

  @override
  String get theRedirectAddressIsInvalid => 'The redirect address is invalid.';

  @override
  String get sessionVerificationIsInvalidTry =>
      'Session verification is invalid. Try again.';

  @override
  String get theProviderRejectedTheSign => 'The provider rejected the sign-in.';

  @override
  String get theServerIsBusyTry => 'The server is busy. Try again in a moment.';

  @override
  String get couldntDeleteTheDraftTry =>
      'Couldn’t delete the draft. Try again.';

  @override
  String get aSendCantBeScheduled => 'A send can’t be scheduled in the past.';

  @override
  String get thisSendIsNoLonger =>
      'This send is no longer pending. Refresh the list.';

  @override
  String get theSendWasChangedOn =>
      'The send was changed on another device. Refresh and try again.';

  @override
  String get thisSendCanNoLonger =>
      'This send can no longer be edited. Check Sent.';

  @override
  String get scheduledSendNotFoundRefresh =>
      'Scheduled send not found. Refresh the list.';

  @override
  String get theHeldAttachmentWasntFound =>
      'The held attachment wasn’t found. Refresh the list.';

  @override
  String get theSelectedIdentityWasntFound =>
      'The selected identity wasn’t found.';

  @override
  String get theSelectedSignatureWasntFound =>
      'The selected signature wasn’t found.';

  @override
  String get thisAddressIsAlreadyRegistered =>
      'This address is already registered as an identity.';

  @override
  String get thisIdentityIsUsedIn =>
      'This identity is used in a scheduled send.';

  @override
  String get theSessionIsAlreadyClosed => 'The session is already closed.';

  @override
  String get theEmailBodyCantBe => 'The email body can’t be empty.';

  @override
  String get theEmailBodyIsToo => 'The email body is too large.';

  @override
  String get attachmentLimitExceeded => 'Attachment limit exceeded.';

  @override
  String get aFolderWithThisName => 'A folder with this name already exists.';

  @override
  String get theFolderIsntEmptyMove =>
      'The folder isn’t empty. Move or delete its mail first.';

  @override
  String get deleteTheSubfoldersFirst => 'Delete the subfolders first.';

  @override
  String get thisFolderCantBeChanged => 'This folder can’t be changed.';

  @override
  String get theFolderNameIsInvalid => 'The folder name is invalid.';

  @override
  String get theMailServerDidntAccept =>
      'The mail server didn’t accept this folder name.';

  @override
  String get theFolderWasRemovedFrom =>
      'The folder was removed from the server.';

  @override
  String get theSyncQueueIsFull =>
      'The sync queue is full. Try again in a moment.';

  @override
  String get syncWasPostponedTryAgain =>
      'Sync was postponed. Try again in a moment.';

  @override
  String get syncWasInterruptedTryAgain => 'Sync was interrupted. Try again.';

  @override
  String get syncCouldntBeCompletedTry =>
      'Sync couldn’t be completed. Try again.';

  @override
  String get theAccountNeedsToBe => 'The account needs to be reconnected.';

  @override
  String get thisSignInMethodIsntSupported =>
      'This sign-in method isn’t supported.';

  @override
  String get theSmtpPasswordWasRejected => 'The SMTP password was rejected.';

  @override
  String get thisSignInIsntSupported =>
      'This sign-in isn’t supported right now.';

  @override
  String get anUnexpectedErrorOccurred => 'An unexpected error occurred.';

  @override
  String get theRequestCouldntBeCompleted =>
      'The request couldn’t be completed.';

  @override
  String get attachmentNotFound => 'Attachment not found.';

  @override
  String get theAttachmentCouldntBeDownloaded =>
      'The attachment couldn’t be downloaded. Try again.';

  @override
  String get snoozedEmailIsBack => 'Snoozed email is back';

  @override
  String get aSnoozedMessageHasReturned =>
      'A snoozed message has returned to your inbox.';

  @override
  String couldntDoTryAgain(Object label) {
    return 'Couldn’t do “$label”, try again.';
  }

  @override
  String get theServerAddressCantBe => 'The server address can’t be empty.';

  @override
  String get enterAValidHttpHttps => 'Enter a valid http/https address.';

  @override
  String get off => 'Off';

  @override
  String get wiFiOnly => 'Wi-Fi only';

  @override
  String get starRemoveStar => 'Star / remove star';

  @override
  String get manual => 'Manual';

  @override
  String get immediately => 'Immediately';

  @override
  String uploadingAttachment(Object percent) {
    return 'Uploading attachment: $percent%';
  }

  @override
  String get theMessageMayHaveBeen =>
      'The message may have been sent. Check the Outbox and Sent.';

  @override
  String get couldntSendTheMessageWas =>
      'Couldn’t send. The message was kept in the Outbox.';

  @override
  String get theMessageMayHaveBeenSentCheckSent =>
      'The message may have been sent. Check Sent.';

  @override
  String youCanPinAtMostEmailsPerAccount(
    Object maxPinnedMails,
    Object pinned,
    Object adding,
    Object value,
  ) {
    return 'You can pin at most $maxPinnedMails emails per account. $pinned are pinned now and $adding new ones were selected$value. None were pinned.';
  }

  @override
  String get now => 'now';

  @override
  String minAgo(Object inMinutes) {
    return '$inMinutes min ago';
  }

  @override
  String get yesterday => 'yesterday';

  @override
  String get theSendDidntStartYou =>
      'The send didn’t start. You can try again from the Outbox.';

  @override
  String get theServerReturnedAnUnexpected =>
      'The server returned an unexpected response.';

  @override
  String get anUnexpectedErrorOccurredPlease =>
      'An unexpected error occurred. Please try again.';

  @override
  String get standardFoldersCantBeDeleted =>
      'Standard folders can’t be deleted.';

  @override
  String get deleteOrMoveTheSubfolders =>
      'Delete or move the subfolders first.';

  @override
  String get theFolderContainsEmailsMove =>
      'The folder contains emails. Move them to another folder before deleting.';

  @override
  String get folderNameCantBeEmpty => 'Folder name can’t be empty.';

  @override
  String get folderNameCantContainOr => 'Folder name can’t contain * or %.';

  @override
  String folderNameCantContain(Object delimiter) {
    return 'Folder name can’t contain “$delimiter”.';
  }

  @override
  String get thisNameIsReservedChoose =>
      'This name is reserved. Choose another.';

  @override
  String get attachments2 => 'Attachments:';

  @override
  String get otherFolders => 'Other folders';

  @override
  String get accountAndApp => 'Account and app';

  @override
  String get syncAccounts => 'Sync accounts';

  @override
  String get signOut3 => 'Sign out';

  @override
  String get finishSorting => 'Finish sorting';

  @override
  String get sortFolders => 'Sort folders';

  @override
  String get moveUp => 'Move up';

  @override
  String get moveDown => 'Move down';

  @override
  String get verifyYourIdentityToAccess =>
      'Verify your identity to access your mail';

  @override
  String get noFingerprintFaceRecognitionOr =>
      'No fingerprint, face recognition or screen lock is set up on your device, so the app lock can’t be verified.';

  @override
  String get verifyYourIdentityWithYour =>
      'Verify your identity with your fingerprint, face recognition or device passcode to continue.';

  @override
  String get continueAnyway => 'Continue anyway';

  @override
  String get unlock => 'Unlock';

  @override
  String get customColor2 => 'Custom color';

  @override
  String get hexCode => 'Hex code';

  @override
  String get invalidColor => 'Invalid color';

  @override
  String get select => 'Select';

  @override
  String get hueAndBrightness => 'Hue and brightness';

  @override
  String get color => 'Color';

  @override
  String get labelsApplyPerAccount => 'Labels apply per account';

  @override
  String get mailAccount => 'Mail account';

  @override
  String couldntApplyTheLabel(Object value) {
    return 'Couldn’t apply the label: $value';
  }

  @override
  String theseResultsComeFromThe(Object authservId) {
    return 'These results come from the mail header added by $authservId. For information only.';
  }

  @override
  String get theseResultsComeFromTheMailHeaderFor =>
      'These results come from the mail header. For information only.';

  @override
  String get pass => 'pass';

  @override
  String get fail => 'fail';

  @override
  String get partialFail => 'partial fail';

  @override
  String get neutral => 'neutral';

  @override
  String get temporaryError => 'temporary error';

  @override
  String get permanentError => 'permanent error';

  @override
  String get theLinkCouldntBeOpened => 'The link couldn’t be opened.';

  @override
  String theLinkWasntOpenedBecause(Object scheme) {
    return 'The link wasn’t opened because it uses an unsafe address type ($scheme:).';
  }

  @override
  String get theLinkWasntOpenedBecauseItsAddressIs =>
      'The link wasn’t opened because its address is invalid.';

  @override
  String theLinkTextShowsBut(Object displayedDomain) {
    return 'The link text shows “$displayedDomain”, but the link goes to a different domain.';
  }

  @override
  String get theDomainContainsInternationalPunycode =>
      'The domain contains international (punycode) characters.';

  @override
  String get theDomainMixesCharactersFrom =>
      'The domain mixes characters from different alphabets.';

  @override
  String get theDomainContainsMisleadingCharacters =>
      'The domain contains misleading characters that look like Latin letters.';

  @override
  String get theAddressContainsUserInformation =>
      'The address contains user information that can hide the real domain.';

  @override
  String get thisLinkLooksSuspicious => 'This link looks suspicious';

  @override
  String get actualDestination => 'Actual destination';

  @override
  String get rawAddressPunycode => 'Raw address (punycode)';

  @override
  String get fullLink => 'Full link';

  @override
  String get openAnyway => 'Open anyway';

  @override
  String get unread3 => 'unread';

  @override
  String get starred3 => 'starred';

  @override
  String get pinned => 'pinned';

  @override
  String get replied => 'replied';

  @override
  String get hasAttachments => 'has attachments';

  @override
  String messageConversation(Object threadCount) {
    return '$threadCount-message conversation';
  }

  @override
  String get unread4 => 'Unread';

  @override
  String get attachments3 => 'Attachments';

  @override
  String get newestFirst => 'Newest first';

  @override
  String get oldestFirst => 'Oldest first';

  @override
  String get unreadFirst => 'Unread first';

  @override
  String get bySenderAZ => 'By sender (A-Z)';

  @override
  String get bySubjectAZ => 'By subject (A-Z)';

  @override
  String get sort => 'Sort';

  @override
  String get enterAValidPort => 'Enter a valid port';

  @override
  String get manualServerSettings => 'Manual server settings';

  @override
  String get automaticServerDiscoveryFailedEnter =>
      'Automatic server discovery failed. Enter the IMAP/SMTP server details manually (993 for IMAP and 587 for SMTP are the recommended default ports).';

  @override
  String get imapServer => 'IMAP server';

  @override
  String get imapPort => 'IMAP port';

  @override
  String get smtpServer => 'SMTP server';

  @override
  String get smtpPort => 'SMTP port';

  @override
  String get connect2 => 'Connect';

  @override
  String get thereAreNoOtherFolders => 'There are no other folders to move to.';

  @override
  String get emailsSelectedFromDifferentAccounts =>
      'Emails selected from different accounts can only be moved to shared folders.';

  @override
  String get permanentlyDeleteThisEmail => 'Permanently delete this email?';

  @override
  String permanentlyDeleteEmails(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Permanently delete $count emails?',
      one: 'Permanently delete 1 email?',
    );
    return '$_temp0';
  }

  @override
  String get address => 'Address';

  @override
  String get in1Hour => 'In 1 hour';

  @override
  String get thisEvening600Pm => 'This evening (6:00 PM)';

  @override
  String get tomorrowMorning900Am => 'Tomorrow morning (9:00 AM)';

  @override
  String get nextWeekMonday900 => 'Next week (Monday 9:00 AM)';

  @override
  String get chooseDateAndTime => 'Choose date and time';

  @override
  String get theChosenTimeIsIn =>
      'The chosen time is in the past, please choose a later time.';

  @override
  String youCanAttachAtMost(int maxAttachmentCount) {
    String _temp0 = intl.Intl.pluralLogic(
      maxAttachmentCount,
      locale: localeName,
      other: '$maxAttachmentCount files',
      one: '1 file',
    );
    return 'You can attach at most $_temp0.';
  }

  @override
  String get aLabelWithThisName => 'A label with this name already exists.';

  @override
  String get emailAddressIsRequired => 'Email address is required';

  @override
  String get theAttachmentCouldntBeDownloaded2 =>
      'The attachment couldn’t be downloaded.';

  @override
  String add2(Object length) {
    return 'Add ($length)';
  }

  @override
  String get requestReadReceipt => 'Request read receipt';

  @override
  String get whatShouldHappenToThis => 'What should happen to this draft?';

  @override
  String get deleteEmail => 'Delete email?';

  @override
  String get deleteDraft2 => 'Delete draft?';

  @override
  String get aReadReceiptWontBe => 'A read receipt won’t be requested.';

  @override
  String emailsSnoozed(int length) {
    String _temp0 = intl.Intl.pluralLogic(
      length,
      locale: localeName,
      other: '$length emails snoozed.',
      one: '1 email snoozed.',
    );
    return '$_temp0';
  }

  @override
  String lastSync(Object value) {
    return 'Last sync: $value';
  }

  @override
  String get unsubscribed => 'Unsubscribed.';

  @override
  String get newEmailAndSnoozedEmail =>
      'New email and snoozed email notifications';

  @override
  String get noSubject2 => '(No subject)';

  @override
  String get noSubject3 => '(no subject)';

  @override
  String get alsoSearchTheServer => 'Also search the server';

  @override
  String get composing => 'Composing';

  @override
  String get mailbox => 'Mailbox';

  @override
  String get darkGray => 'Dark gray';

  @override
  String get thisDevice => 'This device';

  @override
  String get everythingIsSynced => 'Everything is synced';

  @override
  String get theAttachmentWasDownloadedIncompletely =>
      'The attachment was downloaded incompletely. Try again.';

  @override
  String get theAttachmentCouldntBeSaved =>
      'The attachment couldn’t be saved. Try again.';

  @override
  String get youHaveANewMessage => 'You have a new message.';

  @override
  String get newEmailAndAccountNotifications =>
      'New email and account notifications';

  @override
  String get wiFiAndMobileData => 'Wi-Fi and mobile data';

  @override
  String get n1Mb => '1 MB';

  @override
  String get n5Mb => '5 MB';

  @override
  String get n10Mb => '10 MB';

  @override
  String get n5Seconds => '5 seconds';

  @override
  String get n10Seconds => '10 seconds';

  @override
  String get n20Seconds => '20 seconds';

  @override
  String get n30Seconds => '30 seconds';

  @override
  String get every5Minutes => 'Every 5 minutes';

  @override
  String get every15Minutes => 'Every 15 minutes';

  @override
  String get every30Minutes => 'Every 30 minutes';

  @override
  String get everyHour => 'Every hour';

  @override
  String get after1Minute => 'After 1 minute';

  @override
  String get after5Minutes => 'After 5 minutes';

  @override
  String get after15Minutes => 'After 15 minutes';

  @override
  String couldntSaveToTheOutbox(Object value) {
    return 'Couldn’t save to the Outbox: $value';
  }

  @override
  String youCanPinMore(Object free) {
    return '; you can pin $free more';
  }

  @override
  String get appLocked => 'App locked';

  @override
  String get noLabelsInThisAccount => 'No labels in this account.';

  @override
  String get serverAddressIsRequired => 'Server address is required';

  @override
  String wroteSender(Object sender) {
    return '$sender wrote:';
  }

  @override
  String wroteOnDate(Object date, Object sender) {
    return 'On $date, $sender wrote:';
  }

  @override
  String forwardDateLine(Object date) {
    return 'Date: $date\n';
  }

  @override
  String forwardDateLineHtml(Object date) {
    return '<strong>Date:</strong> $date<br>';
  }

  @override
  String get recipientToMe => 'to me';

  @override
  String recipientToName(Object name) {
    return 'to $name';
  }

  @override
  String couldntAddPhoto(Object error) {
    return 'Couldn’t add the photo: $error';
  }

  @override
  String couldntAddPhotos(Object error) {
    return 'Couldn’t add the photos: $error';
  }

  @override
  String emailCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count emails',
      one: '1 email',
    );
    return '$_temp0';
  }

  @override
  String couldntReadSharedFiles(int count, Object names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Couldn’t read $count shared files: $names',
      one: 'Couldn’t read the shared file: $names',
    );
    return '$_temp0';
  }

  @override
  String get earlierMessages => 'Earlier messages';

  @override
  String conversationMessageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages',
      one: '1 message',
    );
    return '$_temp0';
  }
}
