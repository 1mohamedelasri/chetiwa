import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.CodeSigner;
import java.security.KeyStore;
import java.security.MessageDigest;
import java.security.cert.X509Certificate;
import java.util.HexFormat;
import java.util.Locale;
import java.util.Properties;
import java.util.jar.JarFile;

/** Checks the configured upload key, and optionally every signed AAB payload. */
class VerifyUploadSignature {
    public static void main(String[] args) {
        try {
            verify(args);
        } catch (Exception error) {
            // Exceptions can contain private paths or aliases. Keep them out of CI logs.
            System.err.println("Upload-key/signature verification failed ("
                + error.getClass().getSimpleName() + "). Check the private signing configuration.");
            System.exit(1);
        }
    }

    private static void verify(String[] args) throws Exception {
        if (args.length < 1 || args.length > 2) {
            throw new IllegalArgumentException("Expected key.properties and optional AAB");
        }
        Path propertiesPath = Path.of(args[0]).toAbsolutePath();
        Properties properties = new Properties();
        try (InputStream stream = Files.newInputStream(propertiesPath)) {
            properties.load(stream);
        }
        for (String key : new String[]{"storeFile", "storePassword", "keyAlias", "keyPassword"}) {
            if (properties.getProperty(key, "").isBlank()) {
                throw new IllegalArgumentException("Incomplete signing configuration");
            }
        }
        // Match Gradle's file(...) resolution in android/app/build.gradle.kts.
        Path storePath = Path.of(properties.getProperty("storeFile"));
        if (!storePath.isAbsolute()) {
            storePath = propertiesPath.getParent().resolve("app").resolve(storePath);
        }
        KeyStore store = KeyStore.getInstance(storePath.toFile(),
            properties.getProperty("storePassword").toCharArray());
        KeyStore.Entry entry = store.getEntry(properties.getProperty("keyAlias"),
            new KeyStore.PasswordProtection(properties.getProperty("keyPassword").toCharArray()));
        if (!(entry instanceof KeyStore.PrivateKeyEntry privateEntry)) {
            throw new IllegalArgumentException("Not a private signing key");
        }
        X509Certificate expected = (X509Certificate) privateEntry.getCertificate();
        expected.checkValidity();
        if (expected.getSubjectX500Principal().getName().toLowerCase(Locale.ROOT)
                .contains("cn=android debug")) {
            throw new IllegalArgumentException("Android debug keys cannot sign a release");
        }
        if (args.length == 2) {
            int signedEntries = 0;
            try (JarFile jar = new JarFile(args[1], true)) {
                var entries = jar.entries();
                while (entries.hasMoreElements()) {
                    var item = entries.nextElement();
                    if (item.isDirectory()) continue;
                    String name = item.getName().toUpperCase(Locale.ROOT);
                    if (name.equals("META-INF/MANIFEST.MF") ||
                        name.matches("META-INF/[^/]+\\.(SF|RSA|DSA|EC)")) continue;
                    // Reading the complete entry makes JarFile verify its digest.
                    try (InputStream stream = jar.getInputStream(item)) {
                        stream.transferTo(OutputStream.nullOutputStream());
                    }
                    CodeSigner[] signers = item.getCodeSigners();
                    if (signers == null || signers.length != 1 ||
                        !expected.equals(signers[0].getSignerCertPath().getCertificates().get(0))) {
                        throw new SecurityException("Unsigned payload or unexpected signer");
                    }
                    signedEntries++;
                }
            }
            if (signedEntries == 0) throw new SecurityException("Empty signed payload");
        }
        System.out.println(HexFormat.of().formatHex(
            MessageDigest.getInstance("SHA-256").digest(expected.getEncoded())));
    }
}
