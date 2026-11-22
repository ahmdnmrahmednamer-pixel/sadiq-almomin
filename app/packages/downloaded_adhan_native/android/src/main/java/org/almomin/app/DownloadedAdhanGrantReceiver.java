package org.almomin.app;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Explicit URI grants expire at reboot; this never creates or cancels an alarm. */
public final class DownloadedAdhanGrantReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        if (intent == null) return;
        String action = intent.getAction();
        if (!Intent.ACTION_BOOT_COMPLETED.equals(action) &&
                !Intent.ACTION_MY_PACKAGE_REPLACED.equals(action) &&
                !"android.intent.action.QUICKBOOT_POWERON".equals(action) &&
                !"com.htc.intent.action.QUICKBOOT_POWERON".equals(action)) return;
        PendingResult pending = goAsync();
        DownloadedAdhanSounds.restoreAsync(context, pending::finish);
    }
}
