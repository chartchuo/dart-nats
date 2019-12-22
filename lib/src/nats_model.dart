Map<String, dynamic> _removeNull(Map<String, dynamic> data) {
  Map<String, dynamic> data2 = Map<String, dynamic>();

  data.forEach((s, d) {
    if (d != null) data2[s] = d;
  });
  return data2;
}

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

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['server_id'] = this.serverId;
    data['server_name'] = this.serverName;
    data['version'] = this.version;
    data['proto'] = this.proto;
    data['go'] = this.go;
    data['host'] = this.host;
    data['port'] = this.port;
    data['max_payload'] = this.maxPayload;
    data['client_id'] = this.clientId;

    return _removeNull(data);
  }
}

class ConnectOption {
  bool verbose;
  bool pedantic;
  bool tlsRequired;
  String name;
  String lang;
  String version;
  int protocol;

  ConnectOption(
      {this.verbose,
      this.pedantic,
      this.tlsRequired,
      this.name,
      this.lang,
      this.version,
      this.protocol});

  ConnectOption.fromJson(Map<String, dynamic> json) {
    verbose = json['verbose'];
    pedantic = json['pedantic'];
    tlsRequired = json['tls_required'];
    name = json['name'];
    lang = json['lang'];
    version = json['version'];
    protocol = json['protocol'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['verbose'] = this.verbose;
    data['pedantic'] = this.pedantic;
    data['tls_required'] = this.tlsRequired;
    data['name'] = this.name;
    data['lang'] = this.lang;
    data['version'] = this.version;
    data['protocol'] = this.protocol;

    return _removeNull(data);
  }
}
