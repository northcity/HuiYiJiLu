//
//  CircularWaveView.swift
//  Huiyijilu
//
//  圆形波纹录音动画 — 参考竞品的圆环呼吸式动画效果
//  根据音量大小，圆环呼吸式缩放 + 多层淡色圆环

import SwiftUI

/// 圆形波纹动画组件 — 用于录音页面中央区域
struct CircularWaveView: View {
    let audioLevel: Float       // 0.0 ~ 1.0
    let isActive: Bool          // 是否录音中
    let accentColor: Color      // 主题色（麦克风=红, 内录=紫）

    @State private var animationPhase: CGFloat = 0

    var body: some View {
        ZStack {
            // 第3层：最外圈（最淡）
            Circle()
                .stroke(accentColor.opacity(isActive ? 0.08 : 0.03), lineWidth: 1.5)
                .frame(width: outerSize(layer: 3), height: outerSize(layer: 3))
                .scaleEffect(isActive ? 1.0 + CGFloat(audioLevel) * 0.15 : 0.95)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: animationPhase)

            // 第2层
            Circle()
                .stroke(accentColor.opacity(isActive ? 0.12 : 0.05), lineWidth: 1.5)
                .frame(width: outerSize(layer: 2), height: outerSize(layer: 2))
                .scaleEffect(isActive ? 1.0 + CGFloat(audioLevel) * 0.1 : 0.97)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true).delay(0.2), value: animationPhase)

            // 第1层：主圆环
            Circle()
                .stroke(accentColor.opacity(isActive ? 0.35 : 0.1), lineWidth: 2)
                .frame(width: outerSize(layer: 1), height: outerSize(layer: 1))
                .scaleEffect(isActive ? 1.0 + CGFloat(audioLevel) * 0.06 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true).delay(0.1), value: animationPhase)

            // 最内层：浅色填充圆
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            accentColor.opacity(isActive ? 0.06 : 0.02),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: outerSize(layer: 0) / 2
                    )
                )
                .frame(width: outerSize(layer: 0), height: outerSize(layer: 0))
        }
        .onAppear {
            if isActive { animationPhase = 1 }
        }
        .onChange(of: isActive) { _, active in
            animationPhase = active ? 1 : 0
        }
    }

    private func outerSize(layer: Int) -> CGFloat {
        switch layer {
        case 0:  return 220     // 内部渐变填充
        case 1:  return 240     // 主圆环
        case 2:  return 280     // 中间
        case 3:  return 320     // 最外圈
        default: return 240
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        CircularWaveView(audioLevel: 0.5, isActive: true, accentColor: .red)
        CircularWaveView(audioLevel: 0.0, isActive: false, accentColor: .red)
    }
}
