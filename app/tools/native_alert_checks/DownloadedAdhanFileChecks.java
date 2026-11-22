package org.almomin.app;

import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;

/** Desktop JVM boundary checks. Not an Android device or provider acceptance test. */
public final class DownloadedAdhanFileChecks {
    static int checks;
    interface Action { void run() throws Exception; }
    static void check(boolean ok, String name) {
        if (!ok) throw new AssertionError(name);
        checks++;
    }
    static void rejects(Action action, String name) throws Exception {
        try { action.run(); } catch (IllegalArgumentException | IOException expected) {
            checks++;
            return;
        }
        throw new AssertionError(name);
    }
    static String hex(byte[] bytes) {
        StringBuilder text = new StringBuilder();
        for (byte b : bytes) text.append(String.format("%02x", b & 255));
        return text.toString();
    }
    public static void main(String[] args) throws Exception {
        byte[] bytes = Files.readAllBytes(Path.of(args[0]));
        String sha = Files.readString(Path.of(args[1]), StandardCharsets.UTF_8).trim();
        DownloadedAdhanFile.Key key = new DownloadedAdhanFile.Key(sha, bytes.length);
        check(DownloadedAdhanFile.verify(new ByteArrayInputStream(bytes), key), "Python Git blob fixture");
        String contentSha = hex(MessageDigest.getInstance("SHA-1").digest(bytes));
        check(!DownloadedAdhanFile.verify(new ByteArrayInputStream(bytes),
                new DownloadedAdhanFile.Key(contentSha, bytes.length)), "ordinary content SHA is not blob SHA");
        byte[] wrong = bytes.clone(); wrong[0] ^= 1;
        check(!DownloadedAdhanFile.verify(new ByteArrayInputStream(wrong), key), "same-size corrupt bytes");
        check(!DownloadedAdhanFile.verify(new ByteArrayInputStream(new byte[1001]), key), "short stream");
        check(!DownloadedAdhanFile.verify(new ByteArrayInputStream(new byte[5000]), key), "long stream");
        check(DownloadedAdhanFile.parse(sha, "4096").size == 4096, "canonical size");
        rejects(() -> DownloadedAdhanFile.parse(sha, "04096"), "leading zero");
        rejects(() -> DownloadedAdhanFile.parse(sha, "4096.0"), "fraction");
        rejects(() -> DownloadedAdhanFile.parse(sha, "-4096"), "negative");
        rejects(() -> DownloadedAdhanFile.parse(sha, "9999999999999999999"), "overflow");
        rejects(() -> DownloadedAdhanFile.parse(sha, "٤٠٩٦"), "non-ASCII size");
        rejects(() -> new DownloadedAdhanFile.Key(sha, 1000), "legacy minimum is not enough");
        rejects(() -> new DownloadedAdhanFile.Key(sha, 0), "empty size");
        rejects(() -> new DownloadedAdhanFile.Key(sha, DownloadedAdhanFile.MAX_BYTES + 1), "bounded native size");
        rejects(() -> new DownloadedAdhanFile.Key(sha.toUpperCase(), 4096), "noncanonical hash");
        rejects(() -> new DownloadedAdhanFile.Key("../" + sha, 4096), "path traversal");
        rejects(() -> new DownloadedAdhanFile.Key(null, 4096), "missing hash");
        rejects(() -> new DownloadedAdhanFile.Key("a".repeat(39), 4096), "short hash");
        Path temp = Files.createTempDirectory("downloaded-adhan-checks");
        try {
            Path root = Files.createDirectory(temp.resolve("adhkar_audio"));
            Path source = root.resolve("kiwifu_adhan_" + sha + ".mp3");
            rejects(() -> DownloadedAdhanFile.resolve(root.toFile(), key), "missing recording");
            Files.write(source, bytes);
            check(DownloadedAdhanFile.verifiedFile(root.toFile(), key).equals(source.toFile().getCanonicalFile()), "exact named file");
            Files.write(source, wrong);
            rejects(() -> DownloadedAdhanFile.verifiedFile(root.toFile(), key), "mutated registered recording");
            Files.delete(source);
            Files.createDirectory(source);
            rejects(() -> DownloadedAdhanFile.resolve(root.toFile(), key), "directory is not recording");
            Files.delete(source);
            Path outside = temp.resolve("private.bin"); Files.write(outside, bytes);
            Files.createSymbolicLink(source, outside);
            rejects(() -> DownloadedAdhanFile.resolve(root.toFile(), key), "file symlink escape");
            Files.delete(source);
            Files.write(source, bytes);
            Path alias = temp.resolve("linked_audio"); Files.createSymbolicLink(alias, root);
            rejects(() -> DownloadedAdhanFile.resolve(alias.toFile(), key), "directory symlink escape");
            File relative = new File(root.toFile(), ".");
            rejects(() -> DownloadedAdhanFile.resolve(relative, key), "noncanonical leaf directory");
            class CallerStream extends ByteArrayInputStream {
                boolean closed;
                CallerStream() { super(bytes); }
                @Override public void close() { closed = true; }
            }
            CallerStream stream = new CallerStream();
            check(DownloadedAdhanFile.verify(stream, key) && !stream.closed, "caller retains stream ownership");
            rejects(() -> DownloadedAdhanFile.verify(new InputStream() {
                @Override public int read() throws IOException { throw new IOException("injected"); }
            }, key), "stream failure propagates");
        } finally {
            try (java.util.stream.Stream<Path> paths = Files.walk(temp)) {
                paths.sorted(java.util.Comparator.reverseOrder()).forEach(path -> {
                    try { Files.delete(path); } catch (IOException error) { throw new RuntimeException(error); }
                });
            }
        }
        System.out.println("PASS " + checks + " native file boundary checks");
    }
}
