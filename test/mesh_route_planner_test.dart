import 'package:flutter_test/flutter_test.dart';
import 'package:blousab/services/mesh_route_planner.dart';

void main() {
  test('chooses a high-quality two-hop route over an unreliable direct link', () {
    final route = MeshRoutePlanner.bestKnownRoute(source: 'A', target: 'D', links: const [
      MeshLink(from: 'A', to: 'D', quality: .15),
      MeshLink(from: 'A', to: 'B', quality: 1),
      MeshLink(from: 'B', to: 'D', quality: 1),
    ]);
    expect(route?.path, ['A', 'B', 'D']);
    expect(route?.nextHop, 'B');
  });

  test('respects hop budget and returns null for disconnected peers', () {
    const links = [MeshLink(from: 'A', to: 'B'), MeshLink(from: 'B', to: 'C')];
    expect(MeshRoutePlanner.bestKnownRoute(source: 'A', target: 'C', links: links, maxHops: 1), isNull);
    expect(MeshRoutePlanner.bestKnownRoute(source: 'A', target: 'X', links: links), isNull);
  });

  test('excludes loops and forbidden relays', () {
    const links = [MeshLink(from: 'A', to: 'B'), MeshLink(from: 'B', to: 'A'),
      MeshLink(from: 'B', to: 'D'), MeshLink(from: 'A', to: 'C'), MeshLink(from: 'C', to: 'D')];
    final route = MeshRoutePlanner.bestKnownRoute(source: 'A', target: 'D', links: links, avoid: {'B'});
    expect(route?.path, ['A', 'C', 'D']);
  });
}
