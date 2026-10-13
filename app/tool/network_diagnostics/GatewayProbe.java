import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.InetAddress;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import javax.net.ssl.HttpsURLConnection;

/** Read-only check of the deployed gateway, with normal TLS validation. */
public class GatewayProbe {
  public static void main(String[] args) throws Exception {
    if (args.length != 1) throw new IllegalArgumentException("Provide one HTTPS health URL");
    URI url = new URI(args[0]);
    if (!"https".equals(url.getScheme()) || url.getHost() == null
        || url.getUserInfo() != null || url.getQuery() != null || url.getFragment() != null
        || !("/health".equals(url.getPath()) || "/auth/v1/health".equals(url.getPath()))) {
      throw new IllegalArgumentException("Use a credential-free HTTPS health URL");
    }
    for (InetAddress address : InetAddress.getAllByName(url.getHost())) {
      System.out.println("DNS " + url.getHost() + " " + address.getHostAddress());
    }
    long started = System.nanoTime();
    HttpsURLConnection connection = null;
    try {
      connection = (HttpsURLConnection) url.toURL().openConnection();
      connection.setConnectTimeout(6000);
      connection.setReadTimeout(10000);
      connection.setInstanceFollowRedirects(false);
      connection.setRequestProperty("Connection", "close");
      int status = connection.getResponseCode();
      System.out.println("HTTP " + status + " elapsed_ms=" + (System.nanoTime() - started) / 1000000);
      String type = connection.getContentType();
      InputStream input = status < 400 ? connection.getInputStream() : connection.getErrorStream();
      if (input != null) {
        try (InputStream body = input) {
          if (type != null && type.contains("application/json")) {
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            byte[] bytes = new byte[512];
            int count;
            while (output.size() < 2048 && (count = body.read(bytes, 0, Math.min(bytes.length, 2048 - output.size()))) > 0) {
              output.write(bytes, 0, count);
            }
            System.out.println(new String(output.toByteArray(), StandardCharsets.UTF_8));
          }
        }
      }
    } catch (Exception error) {
      System.out.println("FAILED " + error.getClass().getSimpleName() + " " + error.getMessage()
          + " elapsed_ms=" + (System.nanoTime() - started) / 1000000);
    } finally {
      if (connection != null) connection.disconnect();
    }
  }
}
