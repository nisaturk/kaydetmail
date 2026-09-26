import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/services/attachment_auto_download_policy.dart';
import 'package:kaydetmail/services/sync_policy.dart';
import 'package:kaydetmail/state/app_settings_controller.dart';

void main() {
  bool run(
    SyncNetworkPolicy policy,
    AttachmentConnection connection, {
    bool saver = false,
    bool pause = true,
  }) => shouldRunPeriodicSync(
    policy: policy,
    connection: connection,
    batterySaverOn: saver,
    pauseOnBatterySaver: pause,
  );

  test('wifi-only skips periodic sync on mobile data', () {
    expect(
      run(SyncNetworkPolicy.wifiOnly, AttachmentConnection.mobile),
      isFalse,
    );
    expect(run(SyncNetworkPolicy.wifiOnly, AttachmentConnection.wifi), isTrue);
    expect(
      run(SyncNetworkPolicy.wifiAndMobile, AttachmentConnection.mobile),
      isTrue,
    );
  });

  test('never syncs offline', () {
    expect(
      run(SyncNetworkPolicy.wifiAndMobile, AttachmentConnection.none),
      isFalse,
    );
  });

  test('battery saver pauses only when the option is on', () {
    expect(
      run(
        SyncNetworkPolicy.wifiAndMobile,
        AttachmentConnection.wifi,
        saver: true,
      ),
      isFalse,
    );
    expect(
      run(
        SyncNetworkPolicy.wifiAndMobile,
        AttachmentConnection.wifi,
        saver: true,
        pause: false,
      ),
      isTrue,
    );
  });
}
