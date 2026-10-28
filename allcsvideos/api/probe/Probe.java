import java.net.HttpURLConnection;
import java.net.URI;

// docker HEALTHCHECK for distroless images (no shell, no curl):
// java -cp /app/probe Probe <url>  ->  exit 0 on HTTP 200, else 1
public class Probe {
    public static void main(String[] args) {
        try {
            var c = (HttpURLConnection) URI.create(args[0]).toURL().openConnection();
            c.setConnectTimeout(2000);
            c.setReadTimeout(3000);
            System.exit(c.getResponseCode() == 200 ? 0 : 1);
        } catch (Exception e) {
            System.err.println("probe: " + e);
            System.exit(1);
        }
    }
}
