import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

enum RiskLevel { low, medium, high, unknown }

RiskLevel riskLevelFromText(String value) {
  switch (value.toUpperCase()) {
    case 'LOW':
      return RiskLevel.low;
    case 'MEDIUM':
      return RiskLevel.medium;
    case 'HIGH':
      return RiskLevel.high;
    default:
      return RiskLevel.unknown;
  }
}

Color riskColor(RiskLevel risk) {
  switch (risk) {
    case RiskLevel.low:
      return const Color(0xFF16A34A);
    case RiskLevel.medium:
      return const Color(0xFFEAB308);
    case RiskLevel.high:
      return const Color(0xFFDC2626);
    case RiskLevel.unknown:
      return const Color(0xFF64748B);
  }
}

double riskMarkerHue(RiskLevel risk) {
  switch (risk) {
    case RiskLevel.low:
      return BitmapDescriptor.hueGreen;
    case RiskLevel.medium:
      return BitmapDescriptor.hueYellow;
    case RiskLevel.high:
      return BitmapDescriptor.hueRed;
    case RiskLevel.unknown:
      return BitmapDescriptor.hueViolet;
  }
}
