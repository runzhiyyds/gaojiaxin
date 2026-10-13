import java.net.*;
import java.io.*;
import javax.net.ssl.*;
import java.util.*;
public class NetworkProbe {
  static void probe(String host,InetAddress address,String protocol) {
    Socket tcp=null; SSLSocket tls=null; long t=System.nanoTime(); String stage="TCP";
    try {
      tcp=new Socket(); tcp.connect(new InetSocketAddress(address,443),6000); tcp.setSoTimeout(6000);
      System.out.println("TCP host="+host+" ip="+address.getHostAddress()+" ms="+(System.nanoTime()-t)/1000000);
      stage="TLS"; t=System.nanoTime();
      tls=(SSLSocket)((SSLSocketFactory)SSLSocketFactory.getDefault()).createSocket(tcp,host,443,true);
      SSLParameters params=tls.getSSLParameters(); params.setEndpointIdentificationAlgorithm("HTTPS");
      params.setServerNames(Collections.singletonList(new SNIHostName(host))); tls.setSSLParameters(params);
      if(!protocol.equals("default")) tls.setEnabledProtocols(new String[]{protocol});
      tls.startHandshake();
      System.out.println("TLS host="+host+" ip="+address.getHostAddress()+" mode="+protocol+" negotiated="+tls.getSession().getProtocol()+" ms="+(System.nanoTime()-t)/1000000);
      stage="HTTP"; t=System.nanoTime();
      String path=host.endsWith("supabase.co")?"/auth/v1/health":"/";
      String req="GET "+path+" HTTP/1.1\r\nHost: "+host+"\r\nConnection: close\r\n\r\n";
      tls.getOutputStream().write(req.getBytes("US-ASCII")); tls.getOutputStream().flush();
      BufferedReader reader=new BufferedReader(new InputStreamReader(tls.getInputStream(),"US-ASCII"));
      System.out.println("HTTP host="+host+" status="+reader.readLine()+" ms="+(System.nanoTime()-t)/1000000);
    } catch(Exception e) {
      System.out.println("FAILED stage="+stage+" host="+host+" ip="+address.getHostAddress()+" mode="+protocol+" error="+e.getClass().getSimpleName()+" message="+e.getMessage()+" ms="+(System.nanoTime()-t)/1000000);
    } finally {try{if(tls!=null)tls.close();else if(tcp!=null)tcp.close();}catch(Exception ignored){}}
  }
  public static void main(String[] args) throws Exception {
    String host=args[0];
    InetAddress[] addresses=InetAddress.getAllByName(host);
    for(InetAddress address:addresses) {
      System.out.println("DNS "+host+" "+address.getHostAddress());
      probe(host,address,"default"); probe(host,address,"TLSv1.2");
    }
    for(String control:new String[]{"supabase.co","supabase.com","developers.cloudflare.com"}) {
      probe(control,addresses[0],"default");
    }
  }
}