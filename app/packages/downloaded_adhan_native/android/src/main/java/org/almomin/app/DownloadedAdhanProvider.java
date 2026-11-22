package org.almomin.app;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;
import android.system.Os;
import android.system.OsConstants;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.util.List;

/** Read-only access to one digest-named recording per explicitly granted URI. */
public final class DownloadedAdhanProvider extends ContentProvider {
    static File directory(Context context) {
        return new File(context.getDir("flutter", Context.MODE_PRIVATE), "adhkar_audio");
    }

    static Uri uri(Context context, DownloadedAdhanFile.Key key) {
        return new Uri.Builder().scheme("content")
                .authority(context.getPackageName() + ".downloaded_adhan_audio")
                .appendPath("v1").appendPath(key.sha1)
                .appendPath(Long.toString(key.size)).build();
    }

    static DownloadedAdhanFile.Key key(Context context, Uri value) {
        List<String> parts = value.getPathSegments();
        if (!"content".equals(value.getScheme()) ||
                !(context.getPackageName() + ".downloaded_adhan_audio").equals(value.getAuthority()) ||
                value.getQuery() != null || value.getFragment() != null ||
                parts.size() != 3 || !"v1".equals(parts.get(0))) {
            throw new IllegalArgumentException("Invalid pinned recording URI");
        }
        DownloadedAdhanFile.Key key = DownloadedAdhanFile.parse(parts.get(1), parts.get(2));
        if (!uri(context, key).equals(value)) throw new IllegalArgumentException("Noncanonical recording URI");
        return key;
    }

    @Override public boolean onCreate() { return true; }

    @Override public String getType(Uri uri) {
        key(attachedContext(), uri);
        return "audio/mpeg";
    }

    private Context attachedContext() {
        Context context = getContext();
        if (context == null) throw new IllegalStateException("Provider is not attached");
        return context;
    }

    @Override public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        if (!"r".equals(mode)) throw new FileNotFoundException("Read-only recording");
        ParcelFileDescriptor descriptor = null;
        try {
            Context context = attachedContext();
            DownloadedAdhanFile.Key key = key(context, uri);
            File file = DownloadedAdhanFile.resolve(directory(context), key);
            descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY);
            if (descriptor.getStatSize() != key.size) throw new IOException("Recording size changed");
            // Validate the same open inode that is returned to the native player.
            try (InputStream input = new ParcelFileDescriptor.AutoCloseInputStream(
                    ParcelFileDescriptor.dup(descriptor.getFileDescriptor()))) {
                if (!DownloadedAdhanFile.verify(input, key)) throw new IOException("Recording bytes changed");
            }
            Os.lseek(descriptor.getFileDescriptor(), 0, OsConstants.SEEK_SET);
            return descriptor;
        } catch (Exception unavailable) {
            if (descriptor != null) try { descriptor.close(); } catch (IOException ignored) {}
            throw new FileNotFoundException("Verified recording is unavailable");
        }
    }

    @Override public Cursor query(Uri uri, String[] projection, String selection,
                                  String[] selectionArgs, String sortOrder) {
        Context context = attachedContext();
        DownloadedAdhanFile.Key key = key(context, uri);
        if (selection != null || selectionArgs != null || sortOrder != null) {
            throw new IllegalArgumentException("Recording queries do not accept filters");
        }
        String[] columns = projection == null
                ? new String[]{OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE} : projection;
        Object[] values = new Object[columns.length];
        for (int i = 0; i < columns.length; i++) {
            if (OpenableColumns.DISPLAY_NAME.equals(columns[i]) || "title".equals(columns[i])) {
                values[i] = "adhan-" + key.sha1.substring(0, 8) + ".mp3";
            } else if (OpenableColumns.SIZE.equals(columns[i])) {
                values[i] = key.size;
            } else throw new IllegalArgumentException("Unsupported recording column");
        }
        MatrixCursor cursor = new MatrixCursor(columns, 1);
        try {
            DownloadedAdhanFile.resolve(directory(context), key);
            cursor.addRow(values);
        } catch (IOException missing) { /* Missing recordings return no row. */ }
        return cursor;
    }

    @Override public Uri insert(Uri uri, ContentValues values) { throw new UnsupportedOperationException("Read only"); }
    @Override public int update(Uri uri, ContentValues values, String selection, String[] args) { throw new UnsupportedOperationException("Read only"); }
    @Override public int delete(Uri uri, String selection, String[] args) { throw new UnsupportedOperationException("Read only"); }
}
