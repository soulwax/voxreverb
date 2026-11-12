import 'dart:math' as math;

import 'material.dart';
import 'math.dart';

/// Weighted surface composition inside an [AcousticRoomVolume].
final class AcousticSurfaceWeight {
  final AcousticSurfaceMaterial material;
  final double weight;

  const AcousticSurfaceWeight(this.material, [this.weight = 1.0]);
}

/// Enclosed acoustic zone whose volume and surface mix determine Eyring/Sabine RT60 decay.
final class AcousticRoomVolume {
  final String id;
  ReverbAabb bounds;
  double? volumeOverrideM3;
  double? surfaceAreaOverrideM2;
  final List<AcousticSurfaceWeight> surfaces;
  double airAbsorptionPerMeter;
  bool enabled;

  AcousticRoomVolume({
    required this.id,
    required this.bounds,
    this.volumeOverrideM3,
    this.surfaceAreaOverrideM2,
    List<AcousticSurfaceWeight>? surfaces,
    AcousticSurfaceMaterial defaultMaterial = AcousticSurfaceMaterial.concrete,
    this.airAbsorptionPerMeter = 0.002,
    this.enabled = true,
  }) : surfaces = surfaces != null && surfaces.isNotEmpty
            ? List<AcousticSurfaceWeight>.from(surfaces)
            : [AcousticSurfaceWeight(defaultMaterial, 1.0)];

  double get volumeM3 => math.max(0.1, volumeOverrideM3 ?? bounds.volume);
  double get surfaceAreaM2 =>
      math.max(0.1, surfaceAreaOverrideM2 ?? bounds.surfaceArea);

  double get meanAbsorption {
    var weightSum = 0.0;
    var weightedAbs = 0.0;
    for (final sw in surfaces) {
      final w = math.max(0.0, sw.weight);
      weightSum += w;
      weightedAbs += sw.material.meanAbsorption * w;
    }
    if (weightSum <= 1e-9) return 0.1;
    return (weightedAbs / weightSum).clamp(0.005, 0.995).toDouble();
  }

  double get hfDampRatio {
    var weightSum = 0.0;
    var weightedDamp = 0.0;
    for (final sw in surfaces) {
      final w = math.max(0.0, sw.weight);
      weightSum += w;
      weightedDamp += sw.material.hfDamping * w;
    }
    if (weightSum <= 1e-9) return 0.35;
    return (weightedDamp / weightSum).clamp(0.05, 0.98).toDouble();
  }

  double get meanFreePathMeters => (4.0 * volumeM3) / surfaceAreaM2;

  /// First-bounce early reflection arrival latency in milliseconds (`343 m/s` speed of sound).
  double get earlyReflectionDelayMs => (meanFreePathMeters / 343.0) * 1000.0;

  /// Classical Sabine RT60 decay time (seconds) for live rooms.
  double computeSabineRt60() {
    final s = surfaceAreaM2;
    final a = meanAbsorption;
    return (0.161 * volumeM3) / math.max(1e-4, s * a);
  }

  /// Norris-Eyring RT60 decay time (seconds), accurate even for heavily damped rooms.
  double computeEyringRt60() {
    final s = surfaceAreaM2;
    final alpha = meanAbsorption.clamp(0.005, 0.995);
    final airTerm = 4.0 * airAbsorptionPerMeter * volumeM3;
    final denom = (-s * math.log(1.0 - alpha)) + airTerm;
    return (0.161 * volumeM3) / math.max(1e-4, denom);
  }

  /// Heuristic Schroeder/convolution wet reverb mix (`0.08..0.88`) derived from room liveness.
  double get wetSendSuggestion {
    final rt = computeEyringRt60();
    return (0.08 + (rt / 3.2) * 0.72 * (1.0 - meanAbsorption * 0.4))
        .clamp(0.08, 0.88)
        .toDouble();
  }
}

/// Opening (doorway, archway, window, vent) linking two adjacent [AcousticRoomVolume]s.
final class AcousticAperture {
  final String id;
  final String roomAId;
  final String roomBId;
  ReverbVec3 center;
  double areaSqMeters;
  double openFactor;
  double closedTransmissionGain;
  bool enabled;

  AcousticAperture({
    required this.id,
    required this.roomAId,
    required this.roomBId,
    required this.center,
    this.areaSqMeters = 2.2,
    this.openFactor = 1.0,
    this.closedTransmissionGain = 0.08,
    this.enabled = true,
  });

  double get effectiveTransmissionGain {
    if (!enabled) return closedTransmissionGain;
    final o = openFactor.clamp(0.0, 1.0);
    // Small apertures naturally attenuate slightly relative to wide corridor archways.
    final areaScale = (0.45 + math.min(1.0, areaSqMeters / 3.0) * 0.55).clamp(0.25, 1.0);
    final openGain = (closedTransmissionGain + (1.0 - closedTransmissionGain) * o) * areaScale;
    return o <= 1e-4 ? closedTransmissionGain : openGain.clamp(0.01, 1.0).toDouble();
  }

  double get lowPassCutoffHz {
    if (!enabled) return 550.0;
    final o = openFactor.clamp(0.0, 1.0);
    return (650.0 + (18500.0 - 650.0) * math.pow(o, 1.35)).toDouble();
  }
}

/// Solved acoustic propagation path from emitter to listener across room portals.
final class AcousticPathResult {
  final String? emitterRoomId;
  final String? listenerRoomId;
  final double directGain;
  final double diffractionGain;
  final double totalWetMix;
  final double lowPassCutoffHz;
  final double targetRt60Seconds;
  final double hfDamping;
  final double earlyReflectionMs;
  final List<String> traversedPortalIds;
  final ReverbVec3 virtualSourcePosition;

  const AcousticPathResult({
    required this.emitterRoomId,
    required this.listenerRoomId,
    required this.directGain,
    required this.diffractionGain,
    required this.totalWetMix,
    required this.lowPassCutoffHz,
    required this.targetRt60Seconds,
    required this.hfDamping,
    required this.earlyReflectionMs,
    required this.traversedPortalIds,
    required this.virtualSourcePosition,
  });
}

/// Shortest-path Dijkstra portal diffraction and room-to-room reverberation solver.
final class AcousticPropagationSolver {
  final Map<String, AcousticRoomVolume> rooms = {};
  final Map<String, AcousticAperture> apertures = {};

  void addRoom(AcousticRoomVolume room) => rooms[room.id] = room;
  void removeRoom(String id) => rooms.remove(id);

  void addAperture(AcousticAperture aperture) => apertures[aperture.id] = aperture;
  void removeAperture(String id) => apertures.remove(id);

  /// Finds the smallest-volume active [AcousticRoomVolume] containing [pos].
  AcousticRoomVolume? locateRoom(ReverbVec3 pos) {
    AcousticRoomVolume? best;
    var bestVol = double.infinity;
    for (final room in rooms.values) {
      if (!room.enabled || !room.bounds.contains(pos)) continue;
      final vol = room.volumeM3;
      if (vol < bestVol) {
        bestVol = vol;
        best = room;
      }
    }
    return best;
  }

  /// Computes portal-diffracted attenuation, LPF cutoff, virtual pan position & reverb blend.
  AcousticPathResult solve({
    required ReverbVec3 emitterPos,
    required ReverbVec3 listenerPos,
  }) {
    final emitRoom = locateRoom(emitterPos);
    final listRoom = locateRoom(listenerPos);

    if (emitRoom == null || listRoom == null) {
      return AcousticPathResult(
        emitterRoomId: emitRoom?.id,
        listenerRoomId: listRoom?.id,
        directGain: 1.0,
        diffractionGain: 1.0,
        totalWetMix: listRoom?.wetSendSuggestion ?? 0.05,
        lowPassCutoffHz: 20000.0,
        targetRt60Seconds: listRoom?.computeEyringRt60() ?? 0.15,
        hfDamping: listRoom?.hfDampRatio ?? 0.3,
        earlyReflectionMs: listRoom?.earlyReflectionDelayMs ?? 4.0,
        traversedPortalIds: const [],
        virtualSourcePosition: emitterPos,
      );
    }

    if (emitRoom.id == listRoom.id) {
      return AcousticPathResult(
        emitterRoomId: emitRoom.id,
        listenerRoomId: listRoom.id,
        directGain: 1.0,
        diffractionGain: 1.0,
        totalWetMix: listRoom.wetSendSuggestion,
        lowPassCutoffHz: 20000.0,
        targetRt60Seconds: listRoom.computeEyringRt60(),
        hfDamping: listRoom.hfDampRatio,
        earlyReflectionMs: listRoom.earlyReflectionDelayMs,
        traversedPortalIds: const [],
        virtualSourcePosition: emitterPos,
      );
    }

    // Dijkstra shortest acoustic loss path from emitRoom to listRoom across portals
    final bestCost = <String, double>{emitRoom.id: 0.0};
    final prevPortal = <String, AcousticAperture>{};
    final prevRoom = <String, String>{};
    final lastNodePos = <String, ReverbVec3>{emitRoom.id: emitterPos};
    final unvisited = <String>{...rooms.keys};

    while (unvisited.isNotEmpty) {
      String? currId;
      var minCost = double.infinity;
      for (final id in unvisited) {
        final c = bestCost[id] ?? double.infinity;
        if (c < minCost) {
          minCost = c;
          currId = id;
        }
      }
      if (currId == null || currId == listRoom.id) break;
      unvisited.remove(currId);
      final currPos = lastNodePos[currId]!;

      for (final ap in apertures.values) {
        String? nextRoomId;
        if (ap.roomAId == currId) {
          nextRoomId = ap.roomBId;
        } else if (ap.roomBId == currId) {
          nextRoomId = ap.roomAId;
        }
        if (nextRoomId == null || !unvisited.contains(nextRoomId)) continue;
        final targetRoom = rooms[nextRoomId];
        if (targetRoom == null || !targetRoom.enabled) continue;

        final segDist = currPos.distanceTo(ap.center);
        final portalPenalty = -math.log(math.max(1e-4, ap.effectiveTransmissionGain));
        final edgeCost = portalPenalty + segDist * 0.04;
        final candCost = minCost + edgeCost;
        if (candCost < (bestCost[nextRoomId] ?? double.infinity)) {
          bestCost[nextRoomId] = candCost;
          prevPortal[nextRoomId] = ap;
          prevRoom[nextRoomId] = currId;
          lastNodePos[nextRoomId] = ap.center;
        }
      }
    }

    if (!prevPortal.containsKey(listRoom.id)) {
      // Completely disconnected rooms (solid barrier)
      return AcousticPathResult(
        emitterRoomId: emitRoom.id,
        listenerRoomId: listRoom.id,
        directGain: 0.05,
        diffractionGain: 0.05,
        totalWetMix: listRoom.wetSendSuggestion,
        lowPassCutoffHz: 480.0,
        targetRt60Seconds: listRoom.computeEyringRt60(),
        hfDamping: listRoom.hfDampRatio,
        earlyReflectionMs: listRoom.earlyReflectionDelayMs,
        traversedPortalIds: const [],
        virtualSourcePosition: emitterPos,
      );
    }

    // Reconstruct traversed portal sequence from emitter room -> listener room
    final pathPortals = <AcousticAperture>[];
    var cursor = listRoom.id;
    while (prevPortal.containsKey(cursor)) {
      pathPortals.add(prevPortal[cursor]!);
      cursor = prevRoom[cursor]!;
    }
    final orderedPortals = pathPortals.reversed.toList(growable: false);

    var cumulativeGain = 1.0;
    var minLpf = 20000.0;
    var totalDist = 0.0;
    var prevPos = emitterPos;

    for (final p in orderedPortals) {
      totalDist += prevPos.distanceTo(p.center);
      cumulativeGain *= p.effectiveTransmissionGain;
      if (p.lowPassCutoffHz < minLpf) minLpf = p.lowPassCutoffHz;
      prevPos = p.center;
    }
    totalDist += prevPos.distanceTo(listenerPos);

    final distAtten = 1.0 / (1.0 + totalDist * 0.015);
    final diffractedGain = (cumulativeGain * distAtten).clamp(0.01, 1.0).toDouble();

    // Apparent virtual origin lies along direction to the final portal into listener room
    final exitPortal = orderedPortals.last;
    final dirToPortal = (exitPortal.center - listenerPos).normalized;
    final virtualPos = dirToPortal.lengthSquared > 1e-6
        ? listenerPos + (dirToPortal * math.max(1.0, totalDist))
        : emitterPos;

    // Blend RT60 subtly toward emitter room when portal is wide open
    final openBlend = orderedPortals.last.openFactor.clamp(0.0, 1.0) * 0.35;
    final targetRt60 = listRoom.computeEyringRt60() * (1.0 - openBlend) +
        emitRoom.computeEyringRt60() * openBlend;

    return AcousticPathResult(
      emitterRoomId: emitRoom.id,
      listenerRoomId: listRoom.id,
      directGain: diffractedGain,
      diffractionGain: diffractedGain,
      totalWetMix: listRoom.wetSendSuggestion,
      lowPassCutoffHz: minLpf,
      targetRt60Seconds: targetRt60,
      hfDamping: listRoom.hfDampRatio,
      earlyReflectionMs: listRoom.earlyReflectionDelayMs,
      traversedPortalIds: [for (final p in orderedPortals) p.id],
      virtualSourcePosition: virtualPos,
    );
  }
}
