

class ServerScript {
  final int? id;
  final String name;
  final String description;
  final String content;
  final String? createdAt;
  final String? updatedAt;

  ServerScript({
    this.id,
    required this.name,
    this.description = '',
    required this.content,
    this.createdAt,
    this.updatedAt,
  });

  factory ServerScript.fromJson(Map<String, dynamic> json) {
    return ServerScript(
      id: json['ID'],
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      content: json['content'] ?? '',
      createdAt: json['CreatedAt'],
      updatedAt: json['UpdatedAt'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'ID': id,
      'name': name,
      'description': description,
      'content': content,
    };
  }
}

class DockerContainer {
  final String id;
  final String names;
  final String image;
  final String state;
  final String status;
  final String ports;

  DockerContainer({
    required this.id,
    required this.names,
    required this.image,
    required this.state,
    required this.status,
    required this.ports,
  });

  factory DockerContainer.fromJson(Map<String, dynamic> json) {
    return DockerContainer(
      id: json['id'] ?? '',
      names: json['names'] ?? '',
      image: json['image'] ?? '',
      state: json['state'] ?? '',
      status: json['status'] ?? '',
      ports: json['ports'] ?? '',
    );
  }

  bool get isRunning => state.toLowerCase() == 'running';
}
