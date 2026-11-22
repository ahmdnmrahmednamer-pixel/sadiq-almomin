package org.almomin.app;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

/** Pure file boundary for immutable, digest-named Kiwifu downloads. */
public final class DownloadedAdhanFile {
    private DownloadedAdhanFile() {}
    public static final long MAX_BYTES = 100L * 1024L * 1024L;

    public static final class Key {
        public final String sha1;
        public final long size;
        public Key(String sha1, long size) {
            if (sha1 == null || !sha1.matches("[0-9a-f]{40}") || size <= 1000 || size > MAX_BYTES) {
                throw new IllegalArgumentException("Invalid pinned recording identity");
            }
            this.sha1 = sha1;
            this.size = size;
        }
    }

    public static Key parse(String sha1, String size) {
        if (size == null || !size.matches("[1-9][0-9]{3,8}")) {
            throw new IllegalArgumentException("Invalid pinned recording size");
        }
        return new Key(sha1, Long.parseLong(size));
    }

    public static File resolve(File directory, Key key) throws IOException {
        File absolute = directory.getAbsoluteFile();
        File root = new File(absolute.getParentFile().getCanonicalFile(), absolute.getName());
        if (!root.getCanonicalFile().equals(root)) throw new IOException("Recording directory is a link");
        File expected = new File(root, "kiwifu_adhan_" + key.sha1 + ".mp3");
        File actual = expected.getCanonicalFile();
        if (!actual.equals(expected) || !actual.isFile() || actual.length() != key.size) {
            throw new IOException("Pinned recording is unavailable");
        }
        return actual;
    }

    /** Does not close the caller's stream. The digest includes Git's blob header. */
    public static boolean verify(InputStream input, Key key) throws IOException {
        final MessageDigest digest;
        try {
            digest = MessageDigest.getInstance("SHA-1");
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException(impossible);
        }
        digest.update(("blob " + key.size + "\u0000").getBytes(StandardCharsets.UTF_8));
        byte[] buffer = new byte[16 * 1024];
        long count = 0;
        int read;
        while ((read = input.read(buffer)) != -1) {
            count += read;
            if (count > key.size) return false;
            digest.update(buffer, 0, read);
        }
        if (count != key.size) return false;
        StringBuilder hex = new StringBuilder(40);
        for (byte b : digest.digest()) hex.append(String.format(java.util.Locale.ROOT, "%02x", b & 255));
        return key.sha1.contentEquals(hex);
    }

    public static File verifiedFile(File directory, Key key) throws IOException {
        File file = resolve(directory, key);
        try (InputStream input = new FileInputStream(file)) {
            if (!verify(input, key)) throw new IOException("Pinned recording bytes do not match");
        }
        return file;
    }
}
