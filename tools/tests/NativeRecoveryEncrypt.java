// Synthetic host interoperability harness. Executes production Kotlin/JCA code.
import java.nio.file.Files;
import java.nio.file.Path;
import com.pvfd3.pvfd_epcr.RecoveryEncryption;
public final class NativeRecoveryEncrypt {
    public static void main(String[] args) {
        try {
            byte[] plaintext = System.in.readAllBytes();
            byte[] publicDer = Files.readAllBytes(Path.of(args[0]));
            System.out.write(new RecoveryEncryption().encrypt(plaintext, publicDer, args[1]));
        } catch (Exception ignored) {
            System.err.println("Synthetic native encryption failed");
            System.exit(1);
        }
    }
}
