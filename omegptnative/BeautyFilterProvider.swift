import AVFoundation
import CoreImage
import Foundation
import Vision
import WebRTC
import simd

enum ProfessionalColorPreset: String, CaseIterable, Identifiable {
    case none = "Orijinal"
    case analog = "Analog"
    case ash = "Ash"
    case bright = "Bright"
    case clean = "Clean"
    case retro = "Retro"
    case vivid = "Vivid"
    case cool = "Cool"
    case warm = "Warm"
    case bw = "B&W"
    case dramatic = "Dramatic"
    case softFocus = "Soft"
    case cinematic = "Cinematic"
    case pastel = "Pastel"
    case noir = "Noir"
    case sunset = "Sunset"
    case mocha = "Mocha"
    case fresh = "Fresh"
    case glow = "Glow"
    case tealOrange = "Teal+Orange"

    var id: String { rawValue }

    var systemIcon: String {
        switch self {
        case .none: return "nosign"
        case .analog: return "camera.filters"
        case .ash: return "moon.stars.fill"
        case .bright: return "sun.max.fill"
        case .clean: return "drop.fill"
        case .retro: return "sparkles.tv"
        case .vivid: return "paintpalette.fill"
        case .cool: return "snowflake"
        case .warm: return "thermometer.sun.fill"
        case .bw: return "circle.lefthalf.filled"
        case .dramatic: return "theatermasks.fill"
        case .softFocus: return "camera.aperture"
        case .cinematic: return "film.stack.fill"
        case .pastel: return "cloud.sun.fill"
        case .noir: return "moon.fill"
        case .sunset: return "sunset.fill"
        case .mocha: return "cup.and.saucer.fill"
        case .fresh: return "leaf.fill"
        case .glow: return "sparkle"
        case .tealOrange: return "circle.hexagongrid.fill"
        }
    }
}

final class BeautyFilterProvider {
    struct Configuration {
        var smoothing: Float = 0.0
        var eyeEnhance: Float = 0.0
        var noseContour: Float = 0.0
        var jawlineContour: Float = 0.0
        var teethWhitening: Float = 0.0
        var teethLuminanceMin: Float = 0.46
        var teethChromaMax: Float = 0.38
        var vibrance: Float = 0.0
        var exposure: Float = 0.0
        var colorPreset: ProfessionalColorPreset = .none
        var presetIntensity: Float = 0.0
    }

    private let ciContext: CIContext
    private let processQueue = DispatchQueue(label: "beauty.filter.provider.queue", qos: .userInitiated)
    private let visionQueue = DispatchQueue(label: "beauty.filter.provider.vision.queue", qos: .utility)
    private let visionSequenceHandler = VNSequenceRequestHandler()
    private let mouthRectLock = NSLock()
    private let previewLock = NSLock()
    private let colorCubeDimension = 16

    private var configuration = Configuration()
    private var colorCubeCache: [ProfessionalColorPreset: Data] = [:]
    private var frameCounter = 0
    private var previewFrameCounter = 0
    private var whiteBalanceFrameCounter = 0
    private var isVisionDetectionInProgress = false
    private var cachedMouthRectNormalized: CGRect?
    private var cachedPreviewSourceImage: CIImage?
    private var cachedWhiteBalanceTemperature: Float = 6500

    init() {
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: metalDevice, options: [
                .cacheIntermediates: false,
                .priorityRequestLow: false,
                .name: "BeautyFilterContext"
            ])
        } else {
            ciContext = CIContext(options: [
                .cacheIntermediates: false,
                .priorityRequestLow: false,
                .name: "BeautyFilterContextCPU"
            ])
        }
    }

    func updateConfiguration(_ configuration: Configuration) {
        processQueue.async { [weak self] in
            self?.configuration = configuration
        }
    }

    func process(sampleBuffer: CMSampleBuffer) -> CVPixelBuffer? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        return process(pixelBuffer: pixelBuffer)
    }

    func process(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        var result: CVPixelBuffer?
        processQueue.sync {
            result = self.processSync(pixelBuffer: pixelBuffer)
        }
        return result
    }

    func generatePreviewImages(intensity: Float = 0.4) -> [ProfessionalColorPreset: CGImage] {
        var sourceImage: CIImage?
        previewLock.lock()
        sourceImage = cachedPreviewSourceImage
        previewLock.unlock()

        guard let sourceImage else { return [:] }

        var previews: [ProfessionalColorPreset: CGImage] = [:]
        for preset in ProfessionalColorPreset.allCases {
            let baseImage = preset == .none ? sourceImage : applyBaseColorAdjustments(to: sourceImage, configuration: configuration)
            let filtered = applyColorPreset(preset, intensity: intensity, to: baseImage)
            if let cgImage = ciContext.createCGImage(filtered, from: filtered.extent) {
                previews[preset] = cgImage
            }
        }
        return previews
    }

    private func processSync(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        if shouldBypassProcessing {
            return pixelBuffer
        }

        let inputImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = inputImage.extent

        let sharpenedImage = applyCaptureSharpening(to: inputImage)
        let whiteBalancedImage = applyAutoWhiteBalance(to: sharpenedImage, extent: extent)
        updatePreviewSourceCache(from: whiteBalancedImage)

        let originalImage = whiteBalancedImage
        var workingImage = applyEdgeAwareSkinSmoothing(to: originalImage, extent: extent)

        if let detailBlend = CIFilter(name: "CIOverlayBlendMode") {
            detailBlend.setValue(originalImage, forKey: kCIInputImageKey)
            detailBlend.setValue(workingImage, forKey: kCIInputBackgroundImageKey)
            if let overlaid = detailBlend.outputImage {
                let edgeProtectedMask = makeEdgeProtectionMask(from: originalImage, cropTo: extent)
                let detailMask = softenMask(edgeProtectedMask, radius: 0.8, cropTo: extent)
                workingImage = blend(image: overlaid, over: workingImage, mask: detailMask, cropTo: extent)
            }
        }

        if let unsharp = CIFilter(name: "CIUnsharpMask") {
            unsharp.setValue(workingImage, forKey: kCIInputImageKey)
            unsharp.setValue(0.9, forKey: kCIInputRadiusKey)
            unsharp.setValue(max(0.16, configuration.eyeEnhance * 0.9), forKey: kCIInputIntensityKey)
            if let output = unsharp.outputImage {
                workingImage = output
            }
        }

        if let controls = CIFilter(name: "CIColorControls") {
            controls.setValue(workingImage, forKey: kCIInputImageKey)
            controls.setValue(1.0, forKey: kCIInputSaturationKey)
            controls.setValue(0.0, forKey: kCIInputBrightnessKey)
            controls.setValue(1.0 + ((configuration.noseContour + configuration.jawlineContour) * 0.08), forKey: kCIInputContrastKey)
            if let output = controls.outputImage {
                workingImage = output
            }
        }

        if configuration.teethWhitening > 0.01 {
            scheduleMouthLandmarkDetectionIfNeeded(pixelBuffer: pixelBuffer)
            workingImage = applySelectiveTeethWhitening(
                to: workingImage,
                intensity: configuration.teethWhitening,
                extent: extent
            )
        }

        workingImage = applyBaseColorAdjustments(to: workingImage, configuration: configuration)
        workingImage = applyHighlightGlow(to: workingImage, extent: extent)

        if configuration.colorPreset == .analog, configuration.presetIntensity > 0.01 {
            workingImage = applyAnalogFilmGrain(
                to: workingImage,
                intensity: configuration.presetIntensity,
                extent: extent
            )
        }

        workingImage = applyColorPreset(
            configuration.colorPreset,
            intensity: configuration.presetIntensity,
            to: workingImage
        )

        guard let outputBuffer = Self.makePixelBuffer(width: Int(extent.width), height: Int(extent.height)) else {
            return nil
        }

        ciContext.render(workingImage, to: outputBuffer, bounds: extent, colorSpace: CGColorSpaceCreateDeviceRGB())
        return outputBuffer
    }

    private var shouldBypassProcessing: Bool {
        configuration.colorPreset == .none &&
        configuration.smoothing <= 0.001 &&
        configuration.presetIntensity <= 0.001 &&
        configuration.eyeEnhance <= 0.001 &&
        configuration.noseContour <= 0.001 &&
        configuration.jawlineContour <= 0.001 &&
        configuration.teethWhitening <= 0.001 &&
        configuration.vibrance <= 0.001 &&
        configuration.exposure <= 0.001
    }

    private func applyCaptureSharpening(to image: CIImage) -> CIImage {
        guard let sharpen = CIFilter(name: "CISharpenLuminance") else { return image }
        sharpen.setValue(image, forKey: kCIInputImageKey)
        sharpen.setValue(0.4, forKey: kCIInputSharpnessKey)
        return sharpen.outputImage ?? image
    }

    private func applyAutoWhiteBalance(to image: CIImage, extent: CGRect) -> CIImage {
        whiteBalanceFrameCounter += 1
        if whiteBalanceFrameCounter % 8 == 0 {
            cachedWhiteBalanceTemperature = estimatedWhiteBalanceTemperature(for: image, extent: extent)
        }

        guard let tempTint = CIFilter(name: "CITemperatureAndTint") else { return image }
        tempTint.setValue(image, forKey: kCIInputImageKey)
        tempTint.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
        tempTint.setValue(CIVector(x: CGFloat(cachedWhiteBalanceTemperature), y: 0), forKey: "inputTargetNeutral")
        return tempTint.outputImage ?? image
    }

    private func estimatedWhiteBalanceTemperature(for image: CIImage, extent: CGRect) -> Float {
        guard let averageFilter = CIFilter(name: "CIAreaAverage") else { return cachedWhiteBalanceTemperature }
        averageFilter.setValue(image, forKey: kCIInputImageKey)
        averageFilter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
        guard let outputImage = averageFilter.outputImage else { return cachedWhiteBalanceTemperature }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let red = Float(bitmap[0]) / 255
        let blue = Float(bitmap[2]) / 255
        let warmthBias = (red - blue) * 900
        return max(5400, min(7600, 6500 - warmthBias))
    }

    private func applyEdgeAwareSkinSmoothing(to image: CIImage, extent: CGRect) -> CIImage {
        let downscale: CGFloat = 0.55
        let downscaledImage = image.transformed(by: CGAffineTransform(scaleX: downscale, y: downscale))
        var smoothedDownscaledImage = downscaledImage

        if let bilateral = CIFilter(name: "CIBilateralFilter") {
            bilateral.setValue(downscaledImage, forKey: kCIInputImageKey)
            bilateral.setValue(max(2.0, configuration.smoothing * 12.0), forKey: "inputDistanceNormalizationFactor")
            if let output = bilateral.outputImage {
                smoothedDownscaledImage = output
            }
            if configuration.smoothing > 0.32 {
                bilateral.setValue(smoothedDownscaledImage, forKey: kCIInputImageKey)
                bilateral.setValue(max(1.8, configuration.smoothing * 7.0), forKey: "inputDistanceNormalizationFactor")
                if let output = bilateral.outputImage {
                    smoothedDownscaledImage = output
                }
            }
        } else if let noiseReduction = CIFilter(name: "CINoiseReduction") {
            noiseReduction.setValue(downscaledImage, forKey: kCIInputImageKey)
            noiseReduction.setValue(max(0.01, configuration.smoothing * 0.08), forKey: "inputNoiseLevel")
            noiseReduction.setValue(max(0.3, configuration.eyeEnhance + 0.18), forKey: "inputSharpness")
            if let output = noiseReduction.outputImage {
                smoothedDownscaledImage = output
            }
        }

        let smoothedImage = smoothedDownscaledImage.transformed(
            by: CGAffineTransform(scaleX: 1.0 / downscale, y: 1.0 / downscale)
        )

        let grayscale = applyColorControls(to: image, saturation: 0, brightness: 0, contrast: 1.04)
        let tonalMask = makeThresholdMask(from: grayscale, min: 0.2, max: 0.9)
        let chromaDifference = blendDifference(input: image, background: grayscale)
        let chromaMask = makeInvertedThresholdMask(
            from: applyColorControls(to: chromaDifference, saturation: 0, brightness: 0, contrast: 1.0),
            min: 0.04,
            max: 0.28
        )
        let edgeMask = makeEdgeProtectionMask(from: image, cropTo: extent)
        let smoothingMask = softenMask(
            multiply(multiply(tonalMask, by: chromaMask), by: edgeMask),
            radius: 2.0,
            cropTo: extent
        )

        return blend(image: smoothedImage, over: image, mask: smoothingMask, cropTo: extent)
    }

    private func applyHighlightGlow(to image: CIImage, extent: CGRect) -> CIImage {
        let grayscale = applyColorControls(to: image, saturation: 0, brightness: 0, contrast: 1.05)
        let highlightMask = softenMask(
            makeThresholdMask(from: grayscale, min: 0.62, max: 1.0),
            radius: 5.0,
            cropTo: extent
        )
        let glowRadius = max(3.0, configuration.smoothing * 14.0)
        let bloomed = gaussianBlur(image, radius: glowRadius, cropTo: extent)
        let glowLayer = applyColorControls(
            to: bloomed,
            saturation: 1.01,
            brightness: 0.01 + (configuration.smoothing * 0.015),
            contrast: 1.0
        )
        return blend(image: glowLayer, over: image, mask: highlightMask, cropTo: extent)
    }

    private func applyAnalogFilmGrain(to image: CIImage, intensity: Float, extent: CGRect) -> CIImage {
        guard let randomGenerator = CIFilter(name: "CIRandomGenerator") else { return image }
        let noise = randomGenerator.outputImage?.cropped(to: extent) ?? image
        let monochromeNoise = applyColorControls(
            to: noise,
            saturation: 0,
            brightness: -0.48 + (0.02 * intensity),
            contrast: 1.35
        )
        let softenedNoise = gaussianBlur(monochromeNoise, radius: 0.35, cropTo: extent)
        return mix(
            image: softenedNoise,
            with: image,
            amount: max(0.015, min(0.06, intensity * 0.05)),
            cropTo: extent
        )
    }

    private func applyBaseColorAdjustments(to image: CIImage, configuration: Configuration) -> CIImage {
        var output = image

        if let vibrance = CIFilter(name: "CIVibrance") {
            vibrance.setValue(output, forKey: kCIInputImageKey)
            vibrance.setValue(configuration.vibrance + 0.08, forKey: "inputAmount")
            if let filtered = vibrance.outputImage {
                output = filtered
            }
        }

        if let exposure = CIFilter(name: "CIExposureAdjust") {
            exposure.setValue(output, forKey: kCIInputImageKey)
            exposure.setValue(configuration.exposure, forKey: kCIInputEVKey)
            if let filtered = exposure.outputImage {
                output = filtered
            }
        }

        if let colorControls = CIFilter(name: "CIColorControls") {
            colorControls.setValue(output, forKey: kCIInputImageKey)
            colorControls.setValue(1.06, forKey: kCIInputSaturationKey)
            colorControls.setValue(1.06, forKey: kCIInputContrastKey)
            if let filtered = colorControls.outputImage {
                output = filtered
            }
        }

        return output
    }

    private func applyColorPreset(
        _ preset: ProfessionalColorPreset,
        intensity: Float,
        to image: CIImage
    ) -> CIImage {
        let clampedIntensity = max(0, min(1, intensity))
        guard preset != .none else { return image }

        var output = applyColorCubePreset(preset, intensity: clampedIntensity, to: image)

        switch preset {
        case .softFocus:
            let softened = gaussianBlur(output, radius: max(1.2, 4.2 * clampedIntensity), cropTo: image.extent)
            let softMask = softenMask(
                makeThresholdMask(
                    from: applyColorControls(to: image, saturation: 0, brightness: 0, contrast: 0.96),
                    min: 0.2,
                    max: 0.94
                ),
                radius: 2.2,
                cropTo: image.extent
            )
            output = blend(image: softened, over: output, mask: softMask, cropTo: image.extent)
            output = applyColorControls(
                to: output,
                saturation: 1.0 - (0.05 * clampedIntensity),
                brightness: 0.01 * clampedIntensity,
                contrast: 1.0 - (0.03 * clampedIntensity)
            )
        case .dramatic, .noir:
            output = applyColorControls(
                to: output,
                saturation: preset == .noir ? 0.02 : (1.0 - (0.12 * clampedIntensity)),
                brightness: preset == .noir ? -0.005 : 0,
                contrast: 1.0 + (0.1 * clampedIntensity)
            )
        case .bright, .clean, .fresh, .glow:
            output = applyPreset(
                to: output,
                saturation: 1.0 + (0.04 * clampedIntensity),
                brightness: 0.008 * clampedIntensity,
                contrast: 1.0 + (0.025 * clampedIntensity),
                exposure: 0.08 * clampedIntensity,
                temperatureNeutral: CIVector(x: 6600, y: 0),
                temperatureTarget: CIVector(x: 6200, y: -4)
            )
        default:
            break
        }

        return output
    }

    private func updatePreviewSourceCache(from image: CIImage) {
        previewFrameCounter += 1
        guard previewFrameCounter % 18 == 0 else { return }

        let orientedImage = image.oriented(.right)
        let targetSize: CGFloat = 72
        let scale = min(
            targetSize / max(orientedImage.extent.width, 1),
            targetSize / max(orientedImage.extent.height, 1)
        )
        guard scale > 0 else { return }

        var previewImage = orientedImage
        if let scaleFilter = CIFilter(name: "CILanczosScaleTransform") {
            scaleFilter.setValue(orientedImage, forKey: kCIInputImageKey)
            scaleFilter.setValue(scale, forKey: kCIInputScaleKey)
            scaleFilter.setValue(1.0, forKey: kCIInputAspectRatioKey)
            if let output = scaleFilter.outputImage {
                previewImage = output
            }
        } else {
            previewImage = orientedImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        previewLock.lock()
        cachedPreviewSourceImage = previewImage.cropped(to: previewImage.extent.integral)
        previewLock.unlock()
    }

    private func applyColorCubePreset(
        _ preset: ProfessionalColorPreset,
        intensity: Float,
        to image: CIImage
    ) -> CIImage {
        guard let colorCube = CIFilter(name: "CIColorCube") else { return image }
        colorCube.setValue(image, forKey: kCIInputImageKey)
        colorCube.setValue(colorCubeDimension, forKey: "inputCubeDimension")
        colorCube.setValue(colorCubeData(for: preset), forKey: "inputCubeData")
        let cubeOutput = colorCube.outputImage ?? image
        if intensity >= 0.999 { return cubeOutput }
        return mix(image: cubeOutput, with: image, amount: intensity, cropTo: image.extent)
    }

    private func scheduleMouthLandmarkDetectionIfNeeded(pixelBuffer: CVPixelBuffer) {
        frameCounter += 1
        guard frameCounter % 6 == 0 else { return }
        guard !isVisionDetectionInProgress else { return }
        isVisionDetectionInProgress = true

        visionQueue.async { [weak self] in
            guard let self else { return }
            defer { self.isVisionDetectionInProgress = false }

            let request = VNDetectFaceLandmarksRequest()
            do {
                try self.visionSequenceHandler.perform([request], on: pixelBuffer, orientation: .leftMirrored)
                guard let face = request.results?.first,
                      let mouthRect = self.mouthRectNormalized(from: face) else {
                    return
                }
                self.mouthRectLock.lock()
                self.cachedMouthRectNormalized = mouthRect
                self.mouthRectLock.unlock()
            } catch {
                return
            }
        }
    }

    private func mouthRectNormalized(from face: VNFaceObservation) -> CGRect? {
        guard let landmarks = face.landmarks,
              let lips = landmarks.outerLips ?? landmarks.innerLips else {
            return nil
        }

        let points = lips.normalizedPoints
        guard !points.isEmpty else { return nil }

        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        for point in points {
            let x = face.boundingBox.origin.x + CGFloat(point.x) * face.boundingBox.size.width
            let y = face.boundingBox.origin.y + CGFloat(point.y) * face.boundingBox.size.height
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
        }

        guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else { return nil }

        let expansionX = (maxX - minX) * 0.16
        let expansionY = (maxY - minY) * 0.22
        let rect = CGRect(
            x: max(0, minX - expansionX),
            y: max(0, minY - expansionY),
            width: min(1, maxX + expansionX) - max(0, minX - expansionX),
            height: min(1, maxY + expansionY) - max(0, minY - expansionY)
        )
        return rect.width > 0 && rect.height > 0 ? rect : nil
    }

    private func applySelectiveTeethWhitening(to image: CIImage, intensity: Float, extent: CGRect) -> CIImage {
        mouthRectLock.lock()
        let mouthRectNormalized = cachedMouthRectNormalized
        mouthRectLock.unlock()

        guard let mouthRectNormalized else { return image }
        let mouthRect = CGRect(
            x: extent.origin.x + mouthRectNormalized.origin.x * extent.width,
            y: extent.origin.y + mouthRectNormalized.origin.y * extent.height,
            width: mouthRectNormalized.width * extent.width,
            height: mouthRectNormalized.height * extent.height
        )
        guard mouthRect.width > 2, mouthRect.height > 2 else { return image }

        let roi = mouthRect.insetBy(dx: -4, dy: -3).intersection(extent)
        guard !roi.isNull, roi.width > 2, roi.height > 2 else { return image }

        let mouthImage = image.cropped(to: roi)
        let grayscale = applyColorControls(to: mouthImage, saturation: 0, brightness: 0, contrast: 1.05)
        let luminanceMask = makeThresholdMask(
            from: grayscale,
            min: max(0.2, min(configuration.teethLuminanceMin, 0.85)),
            max: 0.98
        )

        let desaturated = applyColorControls(to: mouthImage, saturation: 0, brightness: 0, contrast: 1.0)
        let chromaDifference = blendDifference(input: mouthImage, background: desaturated)
        let lowChromaMask = makeInvertedThresholdMask(
            from: applyColorControls(to: chromaDifference, saturation: 0, brightness: 0, contrast: 1.0),
            min: 0.08,
            max: max(0.18, min(configuration.teethChromaMax, 0.65))
        )

        let centerMask = radialCenterMask(in: roi)
        var finalMask = multiply(luminanceMask, by: lowChromaMask)
        finalMask = multiply(finalMask, by: centerMask)
        finalMask = softenMask(finalMask, radius: 1.6, cropTo: roi)

        var whitenedROI = mouthImage
        if let clamp = CIFilter(name: "CIColorClamp") {
            clamp.setValue(whitenedROI, forKey: kCIInputImageKey)
            clamp.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputMinComponents")
            clamp.setValue(
                CIVector(
                    x: 1.0,
                    y: 0.985 + CGFloat(0.01 * intensity),
                    z: 0.965 + CGFloat(0.02 * intensity),
                    w: 1.0
                ),
                forKey: "inputMaxComponents"
            )
            if let output = clamp.outputImage {
                whitenedROI = output
            }
        }

        whitenedROI = applyColorControls(
            to: whitenedROI,
            saturation: 1.0 - (0.42 * intensity),
            brightness: 0.005 + (0.045 * intensity),
            contrast: 1.0 + (0.11 * intensity)
        )

        let composited = whitenedROI.composited(over: image)
        return blend(image: composited, over: image, mask: finalMask, cropTo: extent)
    }

    private func applyColorControls(
        to image: CIImage,
        saturation: Float,
        brightness: Float,
        contrast: Float
    ) -> CIImage {
        guard let controls = CIFilter(name: "CIColorControls") else { return image }
        controls.setValue(image, forKey: kCIInputImageKey)
        controls.setValue(saturation, forKey: kCIInputSaturationKey)
        controls.setValue(brightness, forKey: kCIInputBrightnessKey)
        controls.setValue(contrast, forKey: kCIInputContrastKey)
        return controls.outputImage ?? image
    }

    private func blendDifference(input: CIImage, background: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CIDifferenceBlendMode") else { return input }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(background, forKey: kCIInputBackgroundImageKey)
        return filter.outputImage ?? input
    }

    private func multiply(_ a: CIImage, by b: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CIMultiplyCompositing") else { return a }
        filter.setValue(a, forKey: kCIInputImageKey)
        filter.setValue(b, forKey: kCIInputBackgroundImageKey)
        return filter.outputImage ?? a
    }

    private func makeThresholdMask(from image: CIImage, min minThreshold: Float, max maxThreshold: Float) -> CIImage {
        let range = Swift.max(0.0001, maxThreshold - minThreshold)
        let scale = 1.0 / range
        let bias = -minThreshold * scale

        guard let matrix = CIFilter(name: "CIColorMatrix") else { return image }
        matrix.setValue(image, forKey: kCIInputImageKey)
        matrix.setValue(CIVector(x: CGFloat(scale), y: 0, z: 0, w: 0), forKey: "inputRVector")
        matrix.setValue(CIVector(x: 0, y: CGFloat(scale), z: 0, w: 0), forKey: "inputGVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: CGFloat(scale), w: 0), forKey: "inputBVector")
        matrix.setValue(CIVector(x: CGFloat(bias), y: CGFloat(bias), z: CGFloat(bias), w: 0), forKey: "inputBiasVector")
        let normalized = matrix.outputImage ?? image

        guard let clamp = CIFilter(name: "CIColorClamp") else { return normalized }
        clamp.setValue(normalized, forKey: kCIInputImageKey)
        clamp.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputMinComponents")
        clamp.setValue(CIVector(x: 1, y: 1, z: 1, w: 1), forKey: "inputMaxComponents")
        return clamp.outputImage ?? normalized
    }

    private func makeInvertedThresholdMask(from image: CIImage, min minThreshold: Float, max maxThreshold: Float) -> CIImage {
        let mask = makeThresholdMask(from: image, min: minThreshold, max: maxThreshold)
        guard let invert = CIFilter(name: "CIColorInvert") else { return mask }
        invert.setValue(mask, forKey: kCIInputImageKey)
        return invert.outputImage ?? mask
    }

    private func radialCenterMask(in roi: CGRect) -> CIImage {
        guard let radial = CIFilter(name: "CIRadialGradient") else {
            return CIImage(color: .white).cropped(to: roi)
        }
        radial.setValue(CIVector(cgPoint: CGPoint(x: roi.midX, y: roi.midY)), forKey: "inputCenter")
        radial.setValue(min(roi.width, roi.height) * 0.13, forKey: "inputRadius0")
        radial.setValue(min(roi.width, roi.height) * 0.72, forKey: "inputRadius1")
        radial.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: 1), forKey: "inputColor0")
        radial.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 0), forKey: "inputColor1")
        return (radial.outputImage ?? CIImage(color: .white)).cropped(to: roi)
    }

    private func applyPreset(
        to image: CIImage,
        saturation: Float,
        brightness: Float,
        contrast: Float,
        exposure: Float,
        temperatureNeutral: CIVector,
        temperatureTarget: CIVector
    ) -> CIImage {
        var output = image

        if let colorControls = CIFilter(name: "CIColorControls") {
            colorControls.setValue(output, forKey: kCIInputImageKey)
            colorControls.setValue(saturation, forKey: kCIInputSaturationKey)
            colorControls.setValue(brightness, forKey: kCIInputBrightnessKey)
            colorControls.setValue(contrast, forKey: kCIInputContrastKey)
            if let filtered = colorControls.outputImage {
                output = filtered
            }
        }

        if let exposureFilter = CIFilter(name: "CIExposureAdjust") {
            exposureFilter.setValue(output, forKey: kCIInputImageKey)
            exposureFilter.setValue(exposure, forKey: kCIInputEVKey)
            if let filtered = exposureFilter.outputImage {
                output = filtered
            }
        }

        if let tempTint = CIFilter(name: "CITemperatureAndTint") {
            tempTint.setValue(output, forKey: kCIInputImageKey)
            tempTint.setValue(temperatureNeutral, forKey: "inputNeutral")
            tempTint.setValue(temperatureTarget, forKey: "inputTargetNeutral")
            if let filtered = tempTint.outputImage {
                output = filtered
            }
        }

        return output
    }

    private func colorCubeData(for preset: ProfessionalColorPreset) -> Data {
        if let cached = colorCubeCache[preset] {
            return cached
        }

        let recipe = presetRecipe(for: preset)
        let cubeData = Self.makeColorCubeData(dimension: colorCubeDimension) { color in
            self.transformedColor(color, recipe: recipe)
        }
        colorCubeCache[preset] = cubeData
        return cubeData
    }

    private func presetRecipe(for preset: ProfessionalColorPreset) -> LUTRecipe {
        switch preset {
        case .none:
            return .identity
        case .analog:
            return LUTRecipe(
                saturation: 1.06,
                contrast: 1.06,
                exposure: 0.08,
                gamma: 0.92,
                vibrance: 0.1,
                warmth: 0.2,
                fade: 0.12,
                redLift: 0.05,
                greenLift: 0.01,
                blueLift: -0.015,
                highlightBoost: 0.04,
                highlightTint: SIMD3<Float>(0.06, 0.03, -0.015)
            )
        case .ash:
            return LUTRecipe(saturation: 0.62, contrast: 1.2, exposure: -0.03, gamma: 1.04, vibrance: -0.08, cool: 0.1, fade: 0.01, blueLift: 0.02)
        case .bright:
            return LUTRecipe(saturation: 1.12, contrast: 1.08, exposure: 0.08, gamma: 0.95, vibrance: 0.09, warmth: 0.02, highlightBoost: 0.05)
        case .clean:
            return LUTRecipe(saturation: 0.96, contrast: 1.08, exposure: 0.06, gamma: 0.96, vibrance: 0.04, cool: 0.09, highlightBoost: 0.04)
        case .retro:
            return LUTRecipe(saturation: 0.84, contrast: 1.14, exposure: -0.01, gamma: 0.93, vibrance: 0.02, warmth: 0.14, fade: 0.12, redLift: 0.05, greenLift: 0.02)
        case .vivid:
            return LUTRecipe(saturation: 1.28, contrast: 1.16, exposure: 0.03, gamma: 0.94, vibrance: 0.14, warmth: 0.01, highlightBoost: 0.03)
        case .cool:
            return LUTRecipe(saturation: 0.94, contrast: 1.08, exposure: 0.0, gamma: 1.02, vibrance: 0.02, cool: 0.15, blueLift: 0.05, shadowTint: SIMD3<Float>(-0.01, 0.02, 0.06))
        case .warm:
            return LUTRecipe(saturation: 1.04, contrast: 1.07, exposure: 0.02, gamma: 0.98, vibrance: 0.05, warmth: 0.16, redLift: 0.04, highlightTint: SIMD3<Float>(0.05, 0.02, -0.01))
        case .bw:
            return LUTRecipe(saturation: 0.0, contrast: 1.24, exposure: 0.0, gamma: 1.02, fade: 0.01, shadowCrush: 0.09)
        case .dramatic:
            return LUTRecipe(saturation: 0.72, contrast: 1.28, exposure: -0.08, gamma: 1.06, vibrance: -0.04, cool: 0.06, shadowCrush: 0.09)
        case .softFocus:
            return LUTRecipe(saturation: 0.9, contrast: 0.96, exposure: 0.04, gamma: 0.94, vibrance: -0.02, fade: 0.08, highlightBoost: 0.04)
        case .cinematic:
            return LUTRecipe(saturation: 0.9, contrast: 1.18, exposure: -0.02, gamma: 1.02, vibrance: 0.03, warmth: 0.08, cool: 0.04, shadowCrush: 0.07, tealOrange: 0.13, shadowTint: SIMD3<Float>(-0.01, 0.02, 0.05), highlightTint: SIMD3<Float>(0.06, 0.02, -0.03))
        case .pastel:
            return LUTRecipe(saturation: 0.82, contrast: 0.93, exposure: 0.07, gamma: 0.91, vibrance: -0.03, fade: 0.12, redLift: 0.03, blueLift: 0.04, highlightTint: SIMD3<Float>(0.04, 0.02, 0.03))
        case .noir:
            return LUTRecipe(saturation: 0.01, contrast: 1.3, exposure: -0.04, gamma: 1.08, shadowCrush: 0.12)
        case .sunset:
            return LUTRecipe(saturation: 1.12, contrast: 1.09, exposure: 0.03, gamma: 0.97, vibrance: 0.08, warmth: 0.22, redLift: 0.06, tealOrange: 0.07, highlightTint: SIMD3<Float>(0.08, 0.03, -0.02))
        case .mocha:
            return LUTRecipe(saturation: 0.88, contrast: 1.12, exposure: 0.0, gamma: 1.0, vibrance: -0.01, warmth: 0.13, redLift: 0.03, greenLift: -0.01)
        case .fresh:
            return LUTRecipe(saturation: 1.08, contrast: 1.04, exposure: 0.05, gamma: 0.96, vibrance: 0.08, cool: 0.04, greenLift: 0.04, highlightBoost: 0.03)
        case .glow:
            return LUTRecipe(saturation: 1.02, contrast: 1.0, exposure: 0.09, gamma: 0.92, vibrance: 0.05, warmth: 0.03, fade: 0.04, highlightBoost: 0.09, highlightTint: SIMD3<Float>(0.06, 0.03, 0.0))
        case .tealOrange:
            return LUTRecipe(saturation: 1.02, contrast: 1.17, exposure: 0.01, gamma: 1.0, vibrance: 0.07, shadowCrush: 0.05, tealOrange: 0.22, shadowTint: SIMD3<Float>(-0.02, 0.03, 0.08), highlightTint: SIMD3<Float>(0.08, 0.03, -0.02))
        }
    }

    private func transformedColor(_ color: SIMD3<Float>, recipe: LUTRecipe) -> SIMD3<Float> {
        var c = color
        let luma = dot(c, SIMD3<Float>(0.299, 0.587, 0.114))
        let gray = SIMD3<Float>(repeating: luma)

        c = simd_mix(gray, c, SIMD3<Float>(repeating: recipe.saturation))
        c = ((c - 0.5) * recipe.contrast) + 0.5
        c *= powf(2, recipe.exposure)
        c = pow(
            clamp(c, min: SIMD3<Float>(repeating: 0), max: SIMD3<Float>(repeating: 1)),
            SIMD3<Float>(repeating: recipe.gamma)
        )

        c.x += recipe.redLift
        c.y += recipe.greenLift
        c.z += recipe.blueLift

        if recipe.warmth != 0 || recipe.cool != 0 {
            c.x += recipe.warmth * 0.07
            c.y += recipe.warmth * 0.015
            c.z -= recipe.warmth * 0.05
            c.x -= recipe.cool * 0.025
            c.y += recipe.cool * 0.01
            c.z += recipe.cool * 0.06
        }

        if recipe.tealOrange > 0 {
            let shadowWeight = max(0, 1 - luma * 1.3)
            let highlightWeight = max(0, (luma - 0.42) * 1.5)
            c.x += highlightWeight * recipe.tealOrange * 0.1
            c.z -= highlightWeight * recipe.tealOrange * 0.04
            c.x -= shadowWeight * recipe.tealOrange * 0.03
            c.y += shadowWeight * recipe.tealOrange * 0.03
            c.z += shadowWeight * recipe.tealOrange * 0.08
        }

        if recipe.vibrance != 0 {
            let maxChannel = max(c.x, max(c.y, c.z))
            let minChannel = min(c.x, min(c.y, c.z))
            let saturationAmount = maxChannel - minChannel
            let vibranceWeight = max(0, 1 - saturationAmount) * recipe.vibrance
            c += (c - gray) * vibranceWeight
        }

        if recipe.highlightBoost > 0 {
            let weight = max(0, (luma - 0.55) / 0.45)
            c += SIMD3<Float>(repeating: weight * recipe.highlightBoost)
        }

        if recipe.shadowCrush > 0 {
            let weight = max(0, (0.45 - luma) / 0.45)
            c -= SIMD3<Float>(repeating: weight * recipe.shadowCrush)
        }

        if recipe.shadowTint != .zero {
            let weight = max(0, (0.5 - luma) / 0.5)
            c += recipe.shadowTint * weight
        }

        if recipe.highlightTint != .zero {
            let weight = max(0, (luma - 0.5) / 0.5)
            c += recipe.highlightTint * weight
        }

        if recipe.fade > 0 {
            c = simd_mix(c, SIMD3<Float>(repeating: 0.5), SIMD3<Float>(repeating: recipe.fade * 0.22))
        }

        return clamp(c, min: SIMD3<Float>(repeating: 0), max: SIMD3<Float>(repeating: 1))
    }

    private func makeEdgeProtectionMask(from image: CIImage, cropTo extent: CGRect) -> CIImage {
        guard let edgeFilter = CIFilter(name: "CIEdges"),
              let invertFilter = CIFilter(name: "CIColorInvert") else {
            return CIImage(color: .white).cropped(to: extent)
        }

        edgeFilter.setValue(image, forKey: kCIInputImageKey)
        edgeFilter.setValue(2.8, forKey: kCIInputIntensityKey)
        let edges = edgeFilter.outputImage ?? image
        invertFilter.setValue(edges, forKey: kCIInputImageKey)
        let inverted = invertFilter.outputImage ?? edges
        return softenMask(inverted, radius: 1.4, cropTo: extent)
    }

    private func softenMask(_ image: CIImage, radius: Float, cropTo extent: CGRect) -> CIImage {
        guard let blur = CIFilter(name: "CIGaussianBlur") else { return image.cropped(to: extent) }
        blur.setValue(image, forKey: kCIInputImageKey)
        blur.setValue(radius, forKey: kCIInputRadiusKey)
        return (blur.outputImage ?? image).cropped(to: extent)
    }

    private func gaussianBlur(_ image: CIImage, radius: Float, cropTo extent: CGRect) -> CIImage {
        softenMask(image, radius: radius, cropTo: extent)
    }

    private func blend(image foreground: CIImage, over background: CIImage, mask: CIImage, cropTo extent: CGRect) -> CIImage {
        guard let filter = CIFilter(name: "CIBlendWithMask") else { return foreground.cropped(to: extent) }
        filter.setValue(foreground, forKey: kCIInputImageKey)
        filter.setValue(background, forKey: kCIInputBackgroundImageKey)
        filter.setValue(mask, forKey: kCIInputMaskImageKey)
        return (filter.outputImage ?? foreground).cropped(to: extent)
    }

    private func mix(image foreground: CIImage, with background: CIImage, amount: Float, cropTo extent: CGRect) -> CIImage {
        let clampedAmount = max(0, min(1, amount))
        let mask = CIImage(
            color: CIColor(
                red: CGFloat(clampedAmount),
                green: CGFloat(clampedAmount),
                blue: CGFloat(clampedAmount),
                alpha: 1
            )
        )
        .cropped(to: extent)
        return blend(image: foreground, over: background, mask: mask, cropTo: extent)
    }

    private static func makeColorCubeData(
        dimension: Int,
        transform: (SIMD3<Float>) -> SIMD3<Float>
    ) -> Data {
        var cubeData = [Float]()
        cubeData.reserveCapacity(dimension * dimension * dimension * 4)

        let maxIndex = Float(dimension - 1)
        for z in 0..<dimension {
            let blue = Float(z) / maxIndex
            for y in 0..<dimension {
                let green = Float(y) / maxIndex
                for x in 0..<dimension {
                    let red = Float(x) / maxIndex
                    let transformed = transform(SIMD3<Float>(red, green, blue))
                    cubeData.append(transformed.x)
                    cubeData.append(transformed.y)
                    cubeData.append(transformed.z)
                    cubeData.append(1.0)
                }
            }
        }

        return cubeData.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    private struct LUTRecipe {
        var saturation: Float = 1.0
        var contrast: Float = 1.0
        var exposure: Float = 0.0
        var gamma: Float = 1.0
        var vibrance: Float = 0.0
        var warmth: Float = 0.0
        var cool: Float = 0.0
        var fade: Float = 0.0
        var redLift: Float = 0.0
        var greenLift: Float = 0.0
        var blueLift: Float = 0.0
        var highlightBoost: Float = 0.0
        var shadowCrush: Float = 0.0
        var tealOrange: Float = 0.0
        var shadowTint = SIMD3<Float>(repeating: 0)
        var highlightTint = SIMD3<Float>(repeating: 0)

        static let identity = LUTRecipe()
    }

    private static func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        return pixelBuffer
    }
}

final class BeautyFrameProcessorDelegate: NSObject, RTCVideoCapturerDelegate {
    private let videoSource: RTCVideoSource
    private let filterProvider: BeautyFilterProvider
    private let frameQueue = DispatchQueue(label: "beauty.frame.processor.queue", qos: .userInitiated)

    var isEnabled = true

    init(videoSource: RTCVideoSource, filterProvider: BeautyFilterProvider) {
        self.videoSource = videoSource
        self.filterProvider = filterProvider
        super.init()
    }

    func capturer(_ capturer: RTCVideoCapturer, didCapture frame: RTCVideoFrame) {
        guard isEnabled else {
            videoSource.capturer(capturer, didCapture: frame)
            return
        }

        frameQueue.async { [weak self] in
            guard let self else { return }
            guard let cvBuffer = (frame.buffer as? RTCCVPixelBuffer)?.pixelBuffer else {
                self.videoSource.capturer(capturer, didCapture: frame)
                return
            }

            guard let filteredBuffer = self.filterProvider.process(pixelBuffer: cvBuffer) else {
                self.videoSource.capturer(capturer, didCapture: frame)
                return
            }

            let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: filteredBuffer)
            let filteredFrame = RTCVideoFrame(
                buffer: rtcPixelBuffer,
                rotation: frame.rotation,
                timeStampNs: frame.timeStampNs
            )
            self.videoSource.capturer(capturer, didCapture: filteredFrame)
        }
    }
}
