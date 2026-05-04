import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

class WalkthroughService {
  static const String _walkthroughKey = 'walkthrough_completed';

  Future<bool> isWalkthroughCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_walkthroughKey) ?? false;
  }

  Future<void> setWalkthroughCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_walkthroughKey, true);
  }

  void showWalkthrough({
    required BuildContext context,
    required List<TargetFocus> targets,
    VoidCallback? onFinish,
  }) {
    TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      textSkip: "SKIP",
      paddingFocus: 10,
      opacityShadow: 0.8,
      onFinish: () {
        setWalkthroughCompleted();
        if (onFinish != null) onFinish();
      },
      onSkip: () {
        setWalkthroughCompleted();
        return true;
      },
    ).show(context: context);
  }

  List<TargetFocus> createDashboardTargets({
    required GlobalKey keyStopButton,
    required GlobalKey keySpeedSlider,
    required GlobalKey keyStats,
    required GlobalKey keyShipmentList,
    required GlobalKey keyAddButton,
  }) {
    List<TargetFocus> targets = [];

    targets.add(
      TargetFocus(
        identify: "keyStopButton",
        keyTarget: keyStopButton,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue.shade300.withValues(alpha: 0.5)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.power_settings_new, color: Colors.red.shade300, size: 24),
                        const SizedBox(width: 12),
                        const Text(
                          "System Control",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 22.0,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 12.0),
                      child: Text(
                        "Master switch for all logistics services. Use this to halt the entire network in case of emergencies or system-wide updates.",
                        style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );

    targets.add(
      TargetFocus(
        identify: "keyStats",
        keyTarget: keyStats,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue.shade300.withValues(alpha: 0.5)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.analytics_outlined, color: Colors.blueAccent, size: 24),
                        SizedBox(width: 12),
                        Text(
                          "Live Performance",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 22.0,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 12.0),
                      child: Text(
                        "Monitor mission-critical metrics in real-time. Instantly identify high-risk shipments and track total fleet activity.",
                        style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );

    targets.add(
      TargetFocus(
        identify: "keySpeedSlider",
        keyTarget: keySpeedSlider,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue.shade300.withValues(alpha: 0.5)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.speed, color: Colors.orangeAccent, size: 24),
                        SizedBox(width: 12),
                        Text(
                          "Temporal Control",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 22.0,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 12.0),
                      child: Text(
                        "Accelerate the simulation up to 10x to analyze long-term trends and predict future bottlenecks in minutes instead of hours.",
                        style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );

    targets.add(
      TargetFocus(
        identify: "keyShipmentList",
        keyTarget: keyShipmentList,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue.shade300.withValues(alpha: 0.5)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.list_alt, color: Colors.tealAccent, size: 24),
                        SizedBox(width: 12),
                        Text(
                          "Operations Hub",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 22.0,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 12.0),
                      child: Text(
                        "Individual shipment cards with integrated AI insights. Drill down into specific routes, or toggle simulations for pinpoint testing.",
                        style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );

    targets.add(
      TargetFocus(
        identify: "keyAddButton",
        keyTarget: keyAddButton,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue.shade300.withValues(alpha: 0.5)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.add_task, color: Colors.purpleAccent, size: 24),
                        SizedBox(width: 12),
                        Text(
                          "New Dispatch",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 22.0,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 12.0),
                      child: Text(
                        "Initiate a new logistics mission. Our Gemini-powered AI will automatically calculate delay risks and suggest optimal routing upon creation.",
                        style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );

    return targets;
  }
}
