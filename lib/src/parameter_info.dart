/// Information about a parameter for alignment
class ParameterInfo {
  final List<String> annotations; // All annotations as strings
  final String type; // Parameter type
  final String name; // Parameter name
  final bool isRequired; // Is required parameter

  ParameterInfo({
    required this.annotations,
    required this.type,
    required this.name,
    required this.isRequired,
  });

  /// Get the formatted annotation block
  String get annotationBlock {
    if (annotations.isEmpty) {
      return '';
    }
    return annotations.join('\n');
  }

  /// Get the length of the longest annotation line
  int get maxAnnotationLength {
    if (annotations.isEmpty) {
      return 0;
    }
    return annotations.map((a) => a.length).reduce((a, b) => a > b ? a : b);
  }
}
