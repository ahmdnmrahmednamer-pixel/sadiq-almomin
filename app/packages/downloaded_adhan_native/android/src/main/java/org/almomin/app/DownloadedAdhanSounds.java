package org.almomin.app;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.util.AtomicFile;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FileInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Prepares narrow read grants, without changing choices, schedules or audio files. */
public final class DownloadedAdhanSounds {
    private DownloadedAdhanSounds() {}
    private static final ExecutorService IO = Executors.newSingleThreadExecutor();
    private static final Handler MAIN = new Handler(Looper.getMainLooper());
    private static final int MAX_ENTRIES = 4096;
    private static final int MAX_INDEX_BYTES = 1024 * 1024;

    public static final class Binding {
        private final MethodChannel channel;
        private volatile boolean active = true;
        private Binding(MethodChannel channel) { this.channel = channel; }
        public void detach() { active = false; channel.setMethodCallHandler(null); }
    }

    public static Binding attach(BinaryMessenger messenger, Context context) {
        final Context app = context.getApplicationContext();
        MethodChannel channel = new MethodChannel(messenger, "almomin/downloaded_adhan_sound");
        Binding binding = new Binding(channel);
        channel.setMethodCallHandler((call, result) -> {
                    if (!binding.active) return;
                    if (!"prepare".equals(call.method)) { result.notImplemented(); return; }
                    Object hash = call.argument("blobSha1");
                    Object length = call.argument("sizeBytes");
                    if (!(hash instanceof String) || !(length instanceof Number)) {
                        result.error("invalid_recording", "Pinned recording identity required", null);
                        return;
                    }
                    final DownloadedAdhanFile.Key key;
                    try {
                        Number number = (Number) length;
                        if (number.doubleValue() != number.longValue()) throw new IllegalArgumentException();
                        key = new DownloadedAdhanFile.Key((String) hash, number.longValue());
                    } catch (IllegalArgumentException invalid) {
                        result.error("invalid_recording", "Pinned recording identity required", null);
                        return;
                    }
                    IO.execute(() -> {
                        try {
                            DownloadedAdhanFile.verifiedFile(DownloadedAdhanProvider.directory(app), key);
                            if (!binding.active) return;
                            Uri uri = DownloadedAdhanProvider.uri(app, key);
                            grant(app, uri);
                            remember(app, uri);
                            Map<String, Object> answer = new LinkedHashMap<>();
                            answer.put("uri", uri.toString());
                            answer.put("blobSha1", key.sha1);
                            answer.put("sizeBytes", key.size);
                            MAIN.post(() -> { if (binding.active) result.success(answer); });
                        } catch (Exception unavailable) {
                            MAIN.post(() -> { if (binding.active) result.error("recording_unavailable",
                                    "Verified native recording could not be prepared", null); });
                        }
                    });
                });
        return binding;
    }

    private static String systemUiPackage(Context context) throws Exception {
        int resource = context.getResources().getIdentifier(
                "config_systemUIServiceComponent", "string", "android");
        ComponentName component = resource == 0 ? null : ComponentName.unflattenFromString(
                context.getResources().getString(resource));
        String name = component == null ? "com.android.systemui" : component.getPackageName();
        PackageManager manager = context.getPackageManager();
        ApplicationInfo info = manager.getApplicationInfo(name, 0);
        if ((info.flags & (ApplicationInfo.FLAG_SYSTEM | ApplicationInfo.FLAG_UPDATED_SYSTEM_APP)) == 0 ||
                manager.checkSignatures("android", name) != PackageManager.SIGNATURE_MATCH) {
            throw new IOException("System sound reader could not be verified");
        }
        return name;
    }

    private static void grant(Context context, Uri uri) throws Exception {
        // No prefix or write grants. Never make the provider world-readable.
        context.grantUriPermission(systemUiPackage(context), uri, Intent.FLAG_GRANT_READ_URI_PERMISSION);
        context.grantUriPermission("android", uri, Intent.FLAG_GRANT_READ_URI_PERMISSION);
    }

    private static AtomicFile index(Context context) {
        return new AtomicFile(new File(context.getFilesDir(), "downloaded_adhan_sound_uris_v1"));
    }

    private static Set<String> readIndex(Context context) throws IOException {
        AtomicFile file = index(context);
        Set<String> values = new LinkedHashSet<>();
        if (!file.getBaseFile().exists() && !new File(file.getBaseFile() + ".bak").exists()) return values;
        if (file.getBaseFile().length() > MAX_INDEX_BYTES) throw new IOException("Recording index is too large");
        byte[] bytes;
        try (FileInputStream input = file.openRead();
             ByteArrayOutputStream buffer = new ByteArrayOutputStream()) {
            byte[] chunk = new byte[8192];
            int count;
            while ((count = input.read(chunk)) != -1) {
                if (buffer.size() + count > MAX_INDEX_BYTES) throw new IOException("Recording index is too large");
                buffer.write(chunk, 0, count);
            }
            bytes = buffer.toByteArray();
        }
        for (String value : new String(bytes, StandardCharsets.UTF_8).split("\n")) {
            try {
                Uri uri = Uri.parse(value);
                DownloadedAdhanFile.Key key = DownloadedAdhanProvider.key(context, uri);
                DownloadedAdhanFile.resolve(DownloadedAdhanProvider.directory(context), key);
                values.add(uri.toString());
            } catch (IllegalArgumentException | IOException missing) {
                // Missing or malformed entries do not authorize a different file.
            }
            if (values.size() > MAX_ENTRIES) throw new IOException("Too many recording grants");
        }
        return values;
    }

    private static void remember(Context context, Uri uri) throws IOException {
        Set<String> values = readIndex(context);
        if (!values.contains(uri.toString()) && values.size() >= MAX_ENTRIES) {
            throw new IOException("Too many recording grants");
        }
        values.add(uri.toString());
        StringBuilder text = new StringBuilder();
        for (String value : values) text.append(value).append('\n');
        AtomicFile file = index(context);
        FileOutputStream output = null;
        try {
            output = file.startWrite();
            output.write(text.toString().getBytes(StandardCharsets.UTF_8));
            file.finishWrite(output);
            if (!readIndex(context).contains(uri.toString())) throw new IOException("Recording grant index was not saved");
        } catch (IOException error) {
            if (output != null) file.failWrite(output);
            throw error;
        }
    }

    public static void restoreAsync(Context context, Runnable finished) {
        Context app = context.getApplicationContext();
        IO.execute(() -> {
            try {
                for (String value : readIndex(app)) {
                    try { grant(app, Uri.parse(value)); } catch (Exception unavailable) {
                        // An unsupported reader must not broaden access to other packages.
                    }
                }
            } catch (IOException unavailable) {
                // Keep the index and all source files; preparation can be retried in-app.
            } finally { finished.run(); }
        });
    }
}
