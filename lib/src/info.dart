Map<String, dynamic> _removeNull(Map<String, dynamic> data) {
  var data2 = <String, dynamic>{};

  data.forEach((s, d) {
    if (d != null) data2[s] = d;
  });
  return data2;
}

///NATS Server Info
class Info {
  String serverId;
  String serverName;
  String version;
  int proto;
  String go;
  String host;
  int port;
  int maxPayload;
  int clientId;

  //todo
  //authen required
  //tls_required
  //tls_verify
  //connect_url

  Info(
      {this.serverId,
      this.serverName,
      this.version,
      this.proto,
      this.go,
      this.host,
      this.port,
      this.maxPayload,
      this.clientId});

  ///constructure from json
  Info.fromJson(Map<String, dynamic> json) {
    serverId = json['server_id'];
    serverName = json['server_name'];
    version = json['version'];
    proto = json['proto'];
    go = json['go'];
    host = json['host'];
    port = json['port'];
    maxPayload = json['max_payload'];
    clientId = json['client_id'];
  }

  ///convert to json
  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['server_id'] = serverId;
    data['server_name'] = serverName;
    data['version'] = version;
    data['proto'] = proto;
    data['go'] = go;
    data['host'] = host;
    data['port'] = port;
    data['max_payload'] = maxPayload;
    data['client_id'] = clientId;

    return _removeNull(data);
  }
}

///connection option to send to server
class ConnectOption {
  bool verbose;
  bool pedantic;
  bool tlsRequired;
  String name;
  String lang;
  String version;
  int protocol;

  ///construcure
  ConnectOption(
      {this.verbose,
      this.pedantic,
      this.tlsRequired,
      this.name,
      this.lang,
      this.version,
      this.protocol});

  ///constructure from json
  ConnectOption.fromJson(Map<String, dynamic> json) {
    verbose = json['verbose'];
    pedantic = json['pedantic'];
    tlsRequired = json['tls_required'];
    name = json['name'];
    lang = json['lang'];
    version = json['version'];
    protocol = json['protocol'];
  }

  ///export to json
  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['verbose'] = verbose;
    data['pedantic'] = pedantic;
    data['tls_required'] = tlsRequired;
    data['name'] = name;
    data['lang'] = lang;
    data['version'] = version;
    data['protocol'] = protocol;

    return _removeNull(data);
  }
}
