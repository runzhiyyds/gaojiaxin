import java.net.*;
import java.nio.*;
import javax.net.ssl.*;
import java.util.*;
public class TLSHelloProbe {
  public static void main(String[] args) throws Exception {
    InetAddress address=InetAddress.getByName(args[0]);
    for(String host:new String[]{args[0],"supabase.co","supabase.com","developers.cloudflare.com"}) {
      Socket socket=new Socket();String stage="TCP";int received=0;long t=System.nanoTime();
      try {
        socket.connect(new InetSocketAddress(address,443),6000);socket.setSoTimeout(6000);
        SSLEngine engine=SSLContext.getDefault().createSSLEngine(host,443);
        engine.setUseClientMode(true);
        SSLParameters params=engine.getSSLParameters();params.setEndpointIdentificationAlgorithm("HTTPS");
        params.setServerNames(Collections.singletonList(new SNIHostName(host)));engine.setSSLParameters(params);
        engine.setEnabledProtocols(new String[]{"TLSv1.2"});engine.beginHandshake();
        ByteBuffer output=ByteBuffer.allocate(engine.getSession().getPacketBufferSize());
        engine.wrap(ByteBuffer.allocate(0),output);output.flip();byte[] hello=new byte[output.remaining()];output.get(hello);
        if(hello.length==0)throw new IllegalStateException("ClientHello not produced");
        stage="FIRST_TLS_RECORD";t=System.nanoTime();socket.getOutputStream().write(hello);socket.getOutputStream().flush();
        byte[] header=new byte[5];
        while(received<header.length) {int n=socket.getInputStream().read(header,received,header.length-received);if(n<0)break;received+=n;}
        System.out.println("host="+host+" ip="+address.getHostAddress()+" clientHelloBytes="+hello.length+" received="+received+" firstRecordType="+(received>0?(header[0]&255):0)+" ms="+(System.nanoTime()-t)/1000000);
      }catch(Exception e){System.out.println("host="+host+" ip="+address.getHostAddress()+" stage="+stage+" received="+received+" error="+e.getClass().getSimpleName()+" message="+e.getMessage()+" ms="+(System.nanoTime()-t)/1000000);}
      finally {socket.close();}
    }
  }
}