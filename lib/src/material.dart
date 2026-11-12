/// Multi-band surface absorption & scattering properties for acoustic rooms.
final class AcousticSurfaceMaterial {
  final String id;
  final double lowAbsorption;
  final double midAbsorption;
  final double highAbsorption;
  final double scattering;
  final double transmissionLossDb;

  const AcousticSurfaceMaterial({
    required this.id,
    required this.lowAbsorption,
    required this.midAbsorption,
    required this.highAbsorption,
    this.scattering = 0.25,
    this.transmissionLossDb = 30.0,
  });

  double get meanAbsorption =>
      (lowAbsorption + midAbsorption + highAbsorption) / 3.0;

  /// Normalized high-frequency damping factor derived from HF vs LF absorption contrast.
  double get hfDamping =>
      (0.35 + (highAbsorption - lowAbsorption)).clamp(0.05, 0.98).toDouble();

  static const concrete = AcousticSurfaceMaterial(
    id: 'concrete',
    lowAbsorption: 0.02,
    midAbsorption: 0.04,
    highAbsorption: 0.06,
    scattering: 0.2,
    transmissionLossDb: 42.0,
  );

  static const stoneCavern = AcousticSurfaceMaterial(
    id: 'stone_cavern',
    lowAbsorption: 0.03,
    midAbsorption: 0.05,
    highAbsorption: 0.09,
    scattering: 0.72,
    transmissionLossDb: 48.0,
  );

  static const woodPanel = AcousticSurfaceMaterial(
    id: 'wood_panel',
    lowAbsorption: 0.14,
    midAbsorption: 0.1,
    highAbsorption: 0.08,
    scattering: 0.35,
    transmissionLossDb: 26.0,
  );

  static const heavyCarpet = AcousticSurfaceMaterial(
    id: 'heavy_carpet',
    lowAbsorption: 0.08,
    midAbsorption: 0.35,
    highAbsorption: 0.65,
    scattering: 0.5,
    transmissionLossDb: 18.0,
  );

  static const glass = AcousticSurfaceMaterial(
    id: 'glass',
    lowAbsorption: 0.18,
    midAbsorption: 0.06,
    highAbsorption: 0.04,
    scattering: 0.08,
    transmissionLossDb: 24.0,
  );

  static const metal = AcousticSurfaceMaterial(
    id: 'metal',
    lowAbsorption: 0.03,
    midAbsorption: 0.04,
    highAbsorption: 0.05,
    scattering: 0.15,
    transmissionLossDb: 36.0,
  );

  static const acousticFoam = AcousticSurfaceMaterial(
    id: 'acoustic_foam',
    lowAbsorption: 0.25,
    midAbsorption: 0.72,
    highAbsorption: 0.88,
    scattering: 0.65,
    transmissionLossDb: 16.0,
  );
}
