library packet;

class Packet {
  String type;
  String data;
  
  Packet(this.type, this.data);
  
  Packet.from(Map<String, dynamic> map) :
    type = map['type'], data = map['data'];
  
  bool operator==(other) {
    if (other is Map<String, dynamic>) {
      return type == other['type'] && data == other['data'];
    }
  }
}

/*class Packet implements Map<String, dynamic> {
  Map<String, dynamic> _content;

  Packet() : _content = new Map<String, dynamic>();

  Packet.from(Map<String, dynamic> other) : _content = other;

  bool containsValue(dynamic value) {
    _content.containsValue(value);
  }

  bool containsKey(String key) {
    return _content.containsKey(key);
  }

  dynamic operator [](String key) {
    return _content[key];
  }

  void operator []=(String key, dynamic value) {
    _content[key] = value;
  }

  dynamic putIfAbsent(String key, dynamic ifAbsent()) {
    return _content.putIfAbsent(key, ifAbsent);
  }

  dynamic remove(String key) {
    _content.remove(key);
  }

  void clear() {
    _content.clear();
  }

  void forEach(void f(String key, dynamic value)) {
    _content.forEach(f);
  }

  Iterable<String> get keys => _content.keys;

  Iterable<dynamic> get values => _content.values;

  int get length => _content.length;

  bool get isEmpty => _content.isEmpty;
  
  noSuchMethod(InvocationMirror msg) {
    if (msg.isGetter) {
      return _content[msg.memberName];
    }
    if (msg.isSetter) {
      return _content[msg.memberName] = msg.positionalArguments[0];
    }
    super.noSuchMethod(msg);
  }
}*/