import 'package:test/test.dart';
import 'package:voxreverb/voxreverb.dart';

void main() {
  test('AcousticRoomVolume computes distinct Eyring RT60 decay for stone cavern vs foam booth', () {
    final cavern = AcousticRoomVolume(
      id: 'cavern',
      bounds: const ReverbAabb(ReverbVec3(-15, 0, -15), ReverbVec3(15, 10, 15)),
      defaultMaterial: AcousticSurfaceMaterial.stoneCavern,
    );
    final booth = AcousticRoomVolume(
      id: 'booth',
      bounds: const ReverbAabb(ReverbVec3(0, 0, 0), ReverbVec3(3, 2.5, 3)),
      defaultMaterial: AcousticSurfaceMaterial.acousticFoam,
    );

    expect(cavern.computeEyringRt60(), greaterThan(3.0));
    expect(booth.computeEyringRt60(), lessThan(0.25));
    expect(cavern.earlyReflectionDelayMs, greaterThan(booth.earlyReflectionDelayMs));
  });

  test('AcousticPropagationSolver routes diffraction through portals and shifts virtual pan origin', () {
    final solver = AcousticPropagationSolver()
      ..addRoom(
        AcousticRoomVolume(
          id: 'hall',
          bounds: const ReverbAabb(ReverbVec3(0, 0, 0), ReverbVec3(12, 5, 10)),
          defaultMaterial: AcousticSurfaceMaterial.concrete,
        ),
      )
      ..addRoom(
        AcousticRoomVolume(
          id: 'study',
          bounds: const ReverbAabb(ReverbVec3(12, 0, 0), ReverbVec3(20, 4, 10)),
          defaultMaterial: AcousticSurfaceMaterial.woodPanel,
        ),
      )
      ..addAperture(
        AcousticAperture(
          id: 'door_oak',
          roomAId: 'hall',
          roomBId: 'study',
          center: const ReverbVec3(12, 1.5, 8),
          openFactor: 1.0,
        ),
      );

    final openRes = solver.solve(
      emitterPos: const ReverbVec3(16, 1.5, 2),
      listenerPos: const ReverbVec3(4, 1.5, 8),
    );
    expect(openRes.traversedPortalIds, ['door_oak']);
    expect(openRes.diffractionGain, greaterThan(0.55));
    expect(openRes.lowPassCutoffHz, greaterThan(15000.0));
    // Virtual source aligns along portal center (+X from listener at z=8), not directly toward z=2
    expect(openRes.virtualSourcePosition.x, greaterThan(4.0));
    expect(openRes.virtualSourcePosition.z, closeTo(8.0, 1e-4));

    // Closing the door muffles high frequencies and slashes transmission gain
    solver.apertures['door_oak']!.openFactor = 0.0;
    final closedRes = solver.solve(
      emitterPos: const ReverbVec3(16, 1.5, 2),
      listenerPos: const ReverbVec3(4, 1.5, 8),
    );
    expect(closedRes.diffractionGain, lessThan(0.1));
    expect(closedRes.lowPassCutoffHz, lessThan(800.0));
  });

  test('AcousticPropagationSolver picks shortest acoustic path among multi-room doorways', () {
    final solver = AcousticPropagationSolver()
      ..addRoom(
        AcousticRoomVolume(
          id: 'room_a',
          bounds: const ReverbAabb(ReverbVec3(0, 0, 0), ReverbVec3(10, 4, 10)),
        ),
      )
      ..addRoom(
        AcousticRoomVolume(
          id: 'room_b',
          bounds: const ReverbAabb(ReverbVec3(10, 0, 0), ReverbVec3(20, 4, 10)),
        ),
      )
      ..addRoom(
        AcousticRoomVolume(
          id: 'room_c',
          bounds: const ReverbAabb(ReverbVec3(20, 0, 0), ReverbVec3(30, 4, 10)),
        ),
      )
      ..addAperture(
        AcousticAperture(
          id: 'p_ab_sealed',
          roomAId: 'room_a',
          roomBId: 'room_b',
          center: const ReverbVec3(10, 1, 2),
          openFactor: 0.0,
        ),
      )
      ..addAperture(
        AcousticAperture(
          id: 'p_ab_open',
          roomAId: 'room_a',
          roomBId: 'room_b',
          center: const ReverbVec3(10, 1, 8),
          openFactor: 1.0,
        ),
      )
      ..addAperture(
        AcousticAperture(
          id: 'p_bc',
          roomAId: 'room_b',
          roomBId: 'room_c',
          center: const ReverbVec3(20, 1, 5),
          openFactor: 1.0,
        ),
      );

    final res = solver.solve(
      emitterPos: const ReverbVec3(25, 1, 5),
      listenerPos: const ReverbVec3(5, 1, 5),
    );
    expect(res.traversedPortalIds, ['p_bc', 'p_ab_open']);
  });
}
