class AutofillCandidate {
  const AutofillCandidate({
    required this.title,
    required this.username,
    required this.domain,
  });

  final String title;
  final String username;
  final String domain;
}

abstract class AutofillProvider {
  Future<List<AutofillCandidate>> findCandidates(String domain);
}

class NoAutofillProvider implements AutofillProvider {
  const NoAutofillProvider();

  @override
  Future<List<AutofillCandidate>> findCandidates(String domain) async =>
      const <AutofillCandidate>[];
}
