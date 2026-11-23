/// A cumulative 20-LED cue before a calibrated shift target.
class ShiftLights {
  static const count = 20;
  static const leadRpm = 1500;
  final int litCount;
  final bool shiftNow;

  const ShiftLights._(this.litCount, this.shiftNow);

  factory ShiftLights(double rpm, num targetRpm) {
    if (!rpm.isFinite || rpm <= 0 || !targetRpm.isFinite || targetRpm <= 0) {
      return const ShiftLights._(0, false);
    }
    if (rpm >= targetRpm) return const ShiftLights._(count, true);
    final start = targetRpm - leadRpm;
    if (rpm < start) return const ShiftLights._(0, false);
    return ShiftLights._(
      (((rpm - start) / leadRpm * count).floor() + 1).clamp(0, count),
      false,
    );
  }
}
