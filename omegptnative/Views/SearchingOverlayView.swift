import Combine
import SwiftUI

struct SearchingOverlayView: View {
    let scopeBadge: String
    let canFallbackToGlobal: Bool
    let onCancelSearch: () -> Void
    let onGlobalFallback: () -> Void

    @State private var pulseText = false
    @State private var elapsedSeconds: Double = 0
    @State private var didTriggerFallback = false
    @State private var animatedBadgeText = ""
    @State private var flashRadar = false
    @State private var orbBreath = false
    @State private var marqueeOffset: CGFloat = 0

    private let fallbackTickTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    private let fallbackDuration: Double = 5
    private let liveQueueItems = ["🇹🇷 A...", "🇺🇸 K...", "🇩🇪 M...", "🇧🇷 L...", "🇯🇵 Y...", "🇫🇷 N..."]

    private var fallbackProgress: Double {
        guard canFallbackToGlobal else { return 0 }
        return min(max(elapsedSeconds / fallbackDuration, 0), 1)
    }

    private var marqueeText: String {
        liveQueueItems.joined(separator: "   |   ")
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundLayer

                closeButton(geometry: geometry)
                    .zIndex(30)

                topBadge(geometry: geometry)
                    .zIndex(20)

                centerLayer
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .zIndex(15)

                bottomQueue(geometry: geometry)
                    .zIndex(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onAppear {
            pulseText = true
            orbBreath = false
            elapsedSeconds = 0
            didTriggerFallback = false
            flashRadar = false
            animatedBadgeText = scopeBadge
            marqueeOffset = 0

            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                marqueeOffset = -340
            }

            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                orbBreath = true
            }
        }
        .onChange(of: scopeBadge) { _, newValue in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                animatedBadgeText = newValue
            }
        }
        .onReceive(fallbackTickTimer) { _ in
            guard canFallbackToGlobal, !didTriggerFallback else { return }
            elapsedSeconds += 0.05
            if elapsedSeconds >= fallbackDuration {
                didTriggerFallback = true
                withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                    animatedBadgeText = "Global 🌎"
                }
                flashRadar = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    flashRadar = false
                }
                onGlobalFallback()
            }
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.45))
            Circle()
                .fill(Color.purple.opacity(0.28))
                .frame(width: 310, height: 310)
                .blur(radius: 80)
                .offset(x: -130, y: -140)
            Circle()
                .fill(Color.blue.opacity(0.3))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: 120, y: 170)
            Circle()
                .fill(Color.cyan.opacity(0.18))
                .frame(width: 220, height: 220)
                .blur(radius: 80)
                .offset(x: 100, y: -180)
        }
        .blur(radius: 14)
        .overlay(Rectangle().fill(.ultraThinMaterial).opacity(0.6))
        .ignoresSafeArea()
    }

    private func closeButton(geometry: GeometryProxy) -> some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    onCancelSearch()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial)
                        .background(Color.black.opacity(0.35))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, geometry.safeAreaInsets.top + 14)
            .padding(.trailing, 18)
            Spacer()
        }
    }

    private func topBadge(geometry: GeometryProxy) -> some View {
        VStack {
            Text(animatedBadgeText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .background(Color.black.opacity(0.22))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 3)
                .animation(.spring(response: 0.36, dampingFraction: 0.82), value: animatedBadgeText)
                .padding(.top, geometry.safeAreaInsets.top + 74)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var centerLayer: some View {
        VStack(spacing: 18) {
            ZStack {
                ForEach(0..<4, id: \.self) { index in
                    OrbWaveRing(index: index)
                        .zIndex(0)
                }

                if canFallbackToGlobal {
                    Circle()
                        .trim(from: 0, to: fallbackProgress)
                        .stroke(
                            AngularGradient(
                                colors: [Color.cyan.opacity(0.95), Color.blue.opacity(0.85), Color.cyan.opacity(0.95)],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                        )
                        .frame(width: 220, height: 220)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: Color.cyan.opacity(0.35), radius: 10)
                        .animation(.linear(duration: 0.05), value: fallbackProgress)
                        .zIndex(1)
                }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.95),
                                Color.cyan.opacity(0.75),
                                Color.blue.opacity(0.45),
                                .clear
                            ],
                            center: .center,
                            startRadius: 2,
                            endRadius: 56
                        )
                    )
                    .frame(width: 116, height: 116)
                    .scaleEffect(orbBreath ? 1.06 : 0.94)
                    .opacity(orbBreath ? 0.95 : 0.78)
                    .zIndex(2)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.95), Color.cyan.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 26, height: 26)
                    .shadow(color: Color.cyan.opacity(0.65), radius: 14)
                    .zIndex(3)

                Image(systemName: "chevron.left.2")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(.white)
                    .shadow(color: Color.blue.opacity(0.5), radius: 10)
                    .zIndex(4)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.yellow.opacity(0.5), Color.cyan.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 220, height: 220)
                    .opacity(flashRadar ? 0.22 : 0)
                    .blur(radius: 6)
                    .animation(.easeOut(duration: 0.5), value: flashRadar)
                    .zIndex(5)
            }
            .frame(width: 250, height: 250)

            Text("Searching...")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .scaleEffect(pulseText ? 1.03 : 0.97)
                .opacity(pulseText ? 0.98 : 0.78)
                .animation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true), value: pulseText)
        }
    }

    private func bottomQueue(geometry: GeometryProxy) -> some View {
        VStack {
            Spacer()

            ZStack {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .background(Color.black.opacity(0.22))
                    .overlay(Capsule().stroke(Color.white.opacity(0.24), lineWidth: 0.5))

                GeometryReader { proxy in
                    HStack(spacing: 40) {
                        Text(marqueeText)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        Text(marqueeText)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .offset(x: marqueeOffset)
                    .frame(width: proxy.size.width, alignment: .leading)
                    .clipped()
                }
                .padding(.horizontal, 14)
            }
            .frame(height: 42)
            .frame(maxWidth: 360)
            .padding(.horizontal, 24)
            .padding(.bottom, max(geometry.safeAreaInsets.bottom, 22))
        }
        .frame(maxWidth: .infinity)
    }
}

struct OrbWaveRing: View {
    let index: Int
    @State private var expand = false

    var body: some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: [
                        Color.cyan.opacity(0.75),
                        Color.blue.opacity(0.55),
                        Color.white.opacity(0.15),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.8
            )
            .frame(width: 56, height: 56)
            .scaleEffect(expand ? 3.25 : 0.35)
            .opacity(expand ? 0 : 0.9)
            .blur(radius: 0.3)
            .onAppear {
                withAnimation(.easeOut(duration: 3.2).repeatForever(autoreverses: false).delay(Double(index) * 0.62)) {
                    expand = true
                }
            }
    }
}

struct RadarRing: View {
    let index: Int
    let isIntensified: Bool
    @State private var animateOut = false
    @State private var animationToken = UUID()

    var body: some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: [
                        Color(red: 0.15, green: 0.94, blue: 0.52).opacity(isIntensified ? 0.92 : 0.75),
                        Color(red: 0.06, green: 0.55, blue: 1.0).opacity(isIntensified ? 0.75 : 0.48),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: isIntensified ? 2.6 : 2.0
            )
            .frame(width: 78, height: 78)
            .scaleEffect(animateOut ? 2.9 : 0.22)
            .opacity(animateOut ? 0.0 : (isIntensified ? 0.95 : 0.7))
            .blur(radius: isIntensified ? 0.9 : 0.35)
            .onAppear {
                startAnimation()
            }
            .onChange(of: isIntensified) { _, _ in
                animationToken = UUID()
                startAnimation()
            }
            .id(animationToken)
    }

    private func startAnimation() {
        animateOut = false
        let duration = isIntensified ? 1.8 : 3.2
        let delay = Double(index) * 0.48
        withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: false).delay(delay)) {
            animateOut = true
        }
    }
}

struct SwipeArrowIndicator: View {
    let isIntensified: Bool
    @State private var slide = false

    var body: some View {
        Image(systemName: "chevron.left.2")
            .font(.system(size: 32, weight: .bold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                .white,
                Color(red: 0.16, green: 0.95, blue: 0.54),
                Color(red: 0.1, green: 0.65, blue: 1.0)
            )
            .offset(x: slide ? -14 : 14)
            .shadow(color: Color.green.opacity(isIntensified ? 0.55 : 0.3), radius: 12, x: 0, y: 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true)) {
                    slide = true
                }
            }
    }
}
