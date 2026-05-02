import 'package:cloud_firestore/cloud_firestore.dart';

import '../firebase_options.dart';
import '../models/shipment.dart';

class FirebaseService {
  FirebaseService({FirebaseFirestore? firestore})
      : _firestoreInternal = firestore;

  final FirebaseFirestore? _firestoreInternal;

  FirebaseFirestore get _firestore {
    if (_firestoreInternal != null) return _firestoreInternal!;
    
    if (!enabled) {
      throw StateError(
        'Firebase is not initialized. '
        'Enable it with --dart-define=ENABLE_FIREBASE=true',
      );
    }
    return FirebaseFirestore.instance;
  }

  bool get enabled => DashboardFirebaseOptions.enabled;

  Stream<Shipment> watchShipment(String shipmentId) {
    return _firestore
        .collection('shipments')
        .doc(shipmentId)
        .snapshots()
        .where((snapshot) => snapshot.exists && snapshot.data() != null)
        .map((snapshot) => Shipment.fromMap(snapshot.id, snapshot.data()!));
  }

  Stream<bool> watchGlobalStopStatus() {
    return _firestore
        .collection('system')
        .doc('config')
        .snapshots()
        .map((snapshot) => snapshot.data()?['isGlobalStopped'] == true);
  }
}
