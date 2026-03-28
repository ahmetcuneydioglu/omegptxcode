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
                .fill(Color.white.opacity(0.62))
            Circle()
                .fill(Color(red: 0.76, green: 0.35, blue: 0.98).opacity(0.24))
                .frame(width: 310, height: 310)
                .blur(radius: 80)
                .offset(x: -130, y: -140)
            Circle()
                .fill(Color(red: 0.42, green: 0.55, blue: 1.0).opacity(0.22))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: 120, y: 170)
            Circle()
                .fill(Color(red: 1.0, green: 0.46, blue: 0.74).opacity(0.18))
                .frame(width: 220, height: 220)
                .blur(radius: 80)
                .offset(x: 100, y: -180)
        }
        .blur(radius: 10)
        .overlay(Rectangle().fill(.ultraThinMaterial).opacity(0.35))
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
                        .foregroundStyle(Color(red: 0.39, green: 0.36, blue: 0.54))
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.84))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.96), lineWidth: 1))
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
                .foregroundStyle(Color(red: 0.37, green: 0.35, blue: 0.52))
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.84))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.96), lineWidth: 1)
                )
                .shadow(color: Color(red: 0.75, green: 0.68, blue: 0.86).opacity(0.18), radius: 10, x: 0, y: 4)
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
                                colors: [Color(red: 0.86, green: 0.35, blue: 0.95), Color(red: 0.40, green: 0.52, blue: 1.0), Color(red: 0.86, green: 0.35, blue: 0.95)],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                        )
                        .frame(width: 220, height: 220)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: Color(red: 0.85, green: 0.42, blue: 0.93).opacity(0.32), radius: 10)
                        .animation(.linear(duration: 0.05), value: fallbackProgress)
                        .zIndex(1)
                }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.95),
                                Color(red: 0.96, green: 0.47, blue: 0.77).opacity(0.62),
                                Color(red: 0.46, green: 0.56, blue: 1.0).opacity(0.38),
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
                            colors: [Color.white.opacity(0.95), Color(red: 0.86, green: 0.35, blue: 0.95).opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 26, height: 26)
                    .shadow(color: Color(red: 0.85, green: 0.42, blue: 0.93).opacity(0.45), radius: 14)
                    .zIndex(3)

                Image(systemName: "chevron.left.2")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color(red: 0.57, green: 0.33, blue: 0.95).opacity(0.35), radius: 10)
                    .zIndex(4)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.63, blue: 0.79).opacity(0.48), Color(red: 0.48, green: 0.56, blue: 1.0).opacity(0.48)],
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
                .foregroundStyle(Color(red: 0.36, green: 0.33, blue: 0.49))
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
                    .fill(Color.white.opacity(0.84))
                    .overlay(Capsule().stroke(Color.white.opacity(0.96), lineWidth: 1))

                GeometryReader { proxy in
                    HStack(spacing: 40) {
                        Text(marqueeText)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.45, green: 0.43, blue: 0.56))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        Text(marqueeText)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.45, green: 0.43, blue: 0.56))
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
                        Color(red: 0.86, green: 0.35, blue: 0.95).opacity(0.65),
                        Color(red: 0.46, green: 0.56, blue: 1.0).opacity(0.45),
                        Color.white.opacity(0.20),
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
                        Color(red: 0.96, green: 0.43, blue: 0.74).opacity(isIntensified ? 0.92 : 0.75),
                        Color(red: 0.52, green: 0.44, blue: 0.98).opacity(isIntensified ? 0.78 : 0.52),
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
                Color(red: 0.98, green: 0.47, blue: 0.74),
                Color(red: 0.54, green: 0.43, blue: 0.98)
            )
            .offset(x: slide ? -14 : 14)
            .shadow(color: Color(red: 0.84, green: 0.44, blue: 0.92).opacity(isIntensified ? 0.55 : 0.3), radius: 12, x: 0, y: 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true)) {
                    slide = true
                }
            }
    }
}
