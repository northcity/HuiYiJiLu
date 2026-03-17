//
//  HuiyijiluWidgetBundle.swift
//  HuiyijiluWidget
//
//  Widget bundle — only contains Live Activity (no home screen widgets).
//

import WidgetKit
import SwiftUI

@main
struct HuiyijiluWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecordingLiveActivity()
    }
}
