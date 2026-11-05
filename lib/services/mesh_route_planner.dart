/// Local route preference only. Advertised neighbor topology is untrusted and
/// is NEVER an identity/authentication or encryption mechanism.
class MeshLink {
  const MeshLink({required this.from, required this.to,
    this.transport = 'lan', this.quality = 1.0});
  final String from;
  final String to;
  final String transport;
  final double quality; // Observed/estimated link quality, 0.0 to 1.0.

  double get cost {
    // Prefer low-latency links, disfavor weak/unstable links.
    final bounded = quality.clamp(.05, 1.0);
    final penalty = transport == 'bluetooth' ? 1.7
        : transport == 'aware' ? .8 : 1.0;
    return penalty / bounded;
  }
}

class MeshRoute {
  const MeshRoute(this.path, this.cost);
  final List<String> path; // Source, intermediate hops, recipient.
  final double cost;
  int get hops => path.length - 1;
  String? get nextHop => path.length > 1 ? path[1] : null;
}

/// Bounded Dijkstra-like route search with a hop budget and loop prevention.
/// If the topology is incomplete it returns null and the caller can fall back
/// to bounded store-and-forward. It does not claim a global optimal route.
class MeshRoutePlanner {
  const MeshRoutePlanner._();
  static MeshRoute? bestKnownRoute({
    required String source,
    required String target,
    required Iterable<MeshLink> links,
    int maxHops = 5,
    Set<String> avoid = const <String>{},
  }) {
    if (source.isEmpty || target.isEmpty || source == target ||
        maxHops < 1 || maxHops > 8 || avoid.contains(target)) return null;
    final adjacency = <String, List<MeshLink>>{};
    for (final link in links) {
      if (link.from.isEmpty || link.to.isEmpty || link.from == link.to ||
          link.from.length > 128 || link.to.length > 128 ||
          link.quality.isNaN || link.quality <= 0 || link.quality > 1.0 ||
          avoid.contains(link.from) || avoid.contains(link.to)) continue;
      (adjacency[link.from] ??= <MeshLink>[]).add(link);
    }
    final frontier = <MeshRoute>[MeshRoute([source], 0)];
    final best = <String, double>{};
    var explored = 0;
    while (frontier.isNotEmpty && explored < 1024) {
      frontier.sort((a, b) => a.cost.compareTo(b.cost));
      final route = frontier.removeAt(0);
      explored++;
      final current = route.path.last;
      if (current == target) return route;
      if (route.hops >= maxHops) continue;
      for (final link in adjacency[current] ?? const <MeshLink>[]) {
        if (route.path.contains(link.to)) continue;
        final nextHops = route.hops + 1;
        final nextCost = route.cost + link.cost;
        final key = '${link.to}/$nextHops';
        if ((best[key] ?? double.infinity) <= nextCost) continue;
        best[key] = nextCost;
        frontier.add(MeshRoute([...route.path, link.to], nextCost));
      }
    }
    return null;
  }
}
