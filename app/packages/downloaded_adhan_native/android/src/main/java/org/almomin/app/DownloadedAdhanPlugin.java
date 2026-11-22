package org.almomin.app;

import io.flutter.embedding.engine.plugins.FlutterPlugin;

/** Registers in UI, renewal and notification-action engines through Flutter. */
public final class DownloadedAdhanPlugin implements FlutterPlugin {
    private DownloadedAdhanSounds.Binding nativeBinding;
    @Override public void onAttachedToEngine(FlutterPluginBinding binding) {
        nativeBinding = DownloadedAdhanSounds.attach(binding.getBinaryMessenger(), binding.getApplicationContext());
        DownloadedAdhanSounds.restoreAsync(binding.getApplicationContext(), () -> {});
    }
    @Override public void onDetachedFromEngine(FlutterPluginBinding binding) {
        if (nativeBinding != null) nativeBinding.detach();
        nativeBinding = null;
    }
}
