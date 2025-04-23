//
//  TurnTable.swift
//  DJ
//
//  Created by 峰 on 2025/3/5.
//

import SwiftUI
import RealityKit
import RealityKitContent

class TurnTable {
    public var needle = Entity()
    private var needleIsUp = false
    private var needleIsMoving = false
    private var needToPlayTrack = false
    
    public var dial = Entity()
    
    public var disc = Entity()
    private var discDegress:Int64 = 0
    
    private var audioController: AudioPlaybackController?
    private var timer: Timer?
    private var audioTotalDuration = Duration(secondsComponent: 0, attosecondsComponent: 0)
    private var currentAudioDuration = Duration(secondsComponent: 0, attosecondsComponent: 0)
    
    enum Track: String {
    case Ocean = "/Root/Ocean_Wave_wav"
    case Forest = "/Root/Forest_Morning_mp3"
    case Storm = "/Root/Sand_Storm_mp3"
    }
    
    public var track: Track = .Ocean
    
    public func setupContent(content: Entity) {
        if let needle = content.findEntity(named: "Needle_low_low_TurnTable_Detail_MAT_0")?.children.first {
            setupNeedle(entity: needle)
        }
        
        if let dial = content.findEntity(named: "Dial_low_TurnTable_Detail_MAT_0")?.children.first {
            setupDial(entity: dial)
        }
        
        if let disc = content.findEntity(named: "DiscPlate_low_Discplate_MAT_0")?.children.first {
            setupDisc(entity: disc)
        }
    }
    
    public func changeToTrack(track: Track) {
        guard track != self.track else { return }
        self.track = track
        self.needToPlayTrack = !self.needleIsUp
        self.stopPlay(isPause: false) { [weak self] in
            guard let self = self else { return }
            
            Task {
                let leaveAnimation = await FromToByAnimation<Transform>(name: "DiscLeave",
                                                                   from: self.disc.transform, to: .init(translation: [self.disc.transform.translation.x, self.disc.transform.translation.y - 0.5, self.disc.transform.translation.z]),
                                                               duration: 0.3,
                                                                 timing: .easeInOut,
                                                             bindTarget: .transform)
                if let leaveAnimationResource = try? await AnimationResource.generate(with: leaveAnimation) {
                    await self.disc.playAnimation(leaveAnimationResource)
                }
                
                await self.changeDiscOpacity(isToClear: true)
                
                try await Task.sleep(for: .seconds(0.5))
                
                let enterAnimation = await FromToByAnimation<Transform>(name: "DiscEnter",
                                                                   from: self.disc.transform, to: .init(translation: [self.disc.transform.translation.x, self.disc.transform.translation.y + 0.5, self.disc.transform.translation.z]),
                                                               duration: 0.3,
                                                                 timing: .easeInOut,
                                                             bindTarget: .transform)
                if let enterAnimationResource = try? await AnimationResource.generate(with: enterAnimation) {
                    await self.disc.playAnimation(enterAnimationResource)
                }
                
                await self.changeDiscOpacity(isToClear: false)

                self.audioController = nil
                if self.needToPlayTrack {
                    self.startPlay()
                }
                self.needToPlayTrack = false
            }
        }
    }
    
    public func handleDragChanged(value: (Entity, DragGesture.Value)) {
        if value.0 == self.needle {
            self.handleDragNeedleChanged(value: value.1)
        } else if value.0 == self.disc {
            self.handleDragDiscChanged(value: value.1)
        }
    }
    
    public func handleDragEnded(value: (Entity, DragGesture.Value)) {
        if value.0 == self.needle {
            self.handleDragNeedleEnded(value: value.1)
        } else if value.0 == self.disc {
            self.handleDragDiscEnded(value: value.1)
        }
    }
    
    public func handleRotateChanged(value: (Entity, RotateGesture3D.Value)) {
        if value.0 == self.dial {
            self.handleRotateDailChanged(value: value.1)
        }
    }
    
    private func handleDragNeedleChanged(value: DragGesture.Value) {
        if self.needleIsMoving {
            return
        }
        
        if value.velocity.height > 300 && self.needleIsUp {
            self.startPlay()
        } else if value.velocity.height < -300 && !self.needleIsUp {
            self.stopPlay(isPause: true)
        }
    }
        
    private func handleDragNeedleEnded(value: DragGesture.Value) {
        self.needleIsMoving = false
    }
    
    private func handleDragDiscChanged(value: DragGesture.Value) {
        guard !self.needleIsUp else { return }
        self.disc.stopAllAnimations()
        self.stopVocalPlay(isPause: true)
        let orientation = Rotation3D(self.disc.orientation(relativeTo: self.disc.parent))
        var newOrientation = orientation
        
        if value.location.x >= value.startLocation.x {
            newOrientation = orientation.rotated(by: .init(angle: .degrees(1.0), axis: .z))
            self.discDegress += 1
        } else {
            newOrientation = orientation.rotated(by: .init(angle: .degrees(-1.0), axis: .z))
            self.discDegress -= 1
        }
        
        self.disc.setOrientation(.init(newOrientation), relativeTo: self.disc.parent)
    }
    
    private func handleDragDiscEnded(value: DragGesture.Value) {
        Task {
            if !self.needleIsUp {
                await self.startDiscAnimation()
                self.applyVocalDuration()
                await self.startVocalPlay()
            }
        }
    }
    
    private func handleRotateDailChanged(value: RotateGesture3D.Value) {
        var dailAngle = self.dial.transform.rotation.angle
        
        // counterclockwise
        if value.rotation.axis.y > 0 {
            dailAngle += .pi / 90
            dailAngle = min(dailAngle, .pi * 4 / 3)
        // clockwise
        } else {
            dailAngle -= .pi / 90
            dailAngle = max(dailAngle, 0)
        }

        self.dial.setOrientation(simd_quatf(angle: dailAngle, axis: SIMD3<Float>(0.0, 0.0, 1.0)), relativeTo: self.dial.parent)
        
        let ratio = dailAngle / (.pi * 4 / 3)
        adjustDecibel(ratio: Double(ratio))
    }
    
    private func setupNeedle(entity: Entity) {
        guard let modelComponent = entity.components[ModelComponent.self] else { return }
        self.needle = entity
        self.needle.transform = generateNeedUpTransform()
        self.needleIsUp = true
        
        self.needle.components.set(InputTargetComponent())
        self.needle.components[CollisionComponent.self] = .init(shapes: [.generateConvex(from: modelComponent.mesh)])
        self.needle.components.set(HoverEffectComponent(.spotlight(.init(color: .white, strength: 1.0))))
    }
    
    private func setupDial(entity: Entity) {
        guard let modelComponent = entity.components[ModelComponent.self] else { return }
        self.dial = entity
        self.dial.components.set(InputTargetComponent())
        self.dial.components[CollisionComponent.self] = .init(shapes: [.generateConvex(from: modelComponent.mesh)])
        self.dial.components.set(HoverEffectComponent(.spotlight(.init(color: .white, strength: 1.0))))
    }
    
    private func setupDisc(entity: Entity) {
        guard let modelComponent = entity.components[ModelComponent.self] else { return }
        self.disc = entity
        
        self.disc.components.set(InputTargetComponent())
        self.disc.components[CollisionComponent.self] = .init(shapes: [.generateConvex(from: modelComponent.mesh)])
        self.disc.components.set(HoverEffectComponent(.spotlight(.init(color: .white, strength: 1.0))))
        self.disc.components.set(OpacityComponent(opacity: 1.0))
    }
    
    private func startPlay() {
        self.needle.move(to: generateNeedDownTransform(), relativeTo: self.needle.parent, duration: 1.0, timingFunction: .easeInOut)
        self.needleIsMoving = true
        self.needleIsUp = false
        
        Task {
            try await Task.sleep(for: .seconds(0.8))
            await self.startDiscAnimation()
            await self.startVocalPlay()
        }
    }
    
    private func startDiscAnimation() async {
        let orbit = await OrbitAnimation(name: "Orbit",
                                   duration: 12,
                                   axis: [0, 0, 1],
                                   startTransform:self.disc.transform,
                                   orientToPath: true,
                                   bindTarget: .transform,
                                   repeatMode: .repeat)
        
        if let animation = try? await AnimationResource.generate(with: orbit) {
            await self.disc.playAnimation(animation)
        }
    }
    
    private func stopPlay(isPause: Bool, completion: (() -> Void)? = nil) {
        let transform = generateNeedUpTransform()
        self.needle.move(to: transform, relativeTo: self.needle.parent, duration: 1.0)
        self.needleIsMoving = true
        self.needleIsUp = true
        
        Task {
            try await Task.sleep(for: .seconds(0.8))
            await self.disc.stopAllAnimations()
            self.stopVocalPlay(isPause: isPause)

            if let completion = completion {
                completion()
            }
        }
    }
    
    @MainActor
    private func startVocalPlay() async {
        if self.audioController != nil {
            self.audioController?.play()
            self.startAudioTimer()
        } else {
            guard let audioResource = try? await AudioFileResource(named: self.track.rawValue, from: "Immersive.usda", in: realityKitContentBundle) else { return }
            self.audioTotalDuration = audioResource.duration
            self.audioController = self.disc.prepareAudio(audioResource)
            self.audioController?.play()
            self.startAudioTimer()
            self.audioController?.completionHandler = { [weak self] in
                self?.stopPlay(isPause: false)
            }
        }
    }
    
    private func stopVocalPlay(isPause: Bool) {
        if isPause {
            self.audioController?.pause()
            self.stopAudioTimer()
        } else {
            self.audioController?.stop()
            self.stopAudioTimer()
            self.currentAudioDuration = Duration(secondsComponent: 0, attosecondsComponent: 0)
            self.audioTotalDuration = Duration(secondsComponent: 0, attosecondsComponent: 0)
        }
    }
    
    private func applyVocalDuration() {
        let ratio = self.discDegress / 10
        self.currentAudioDuration += Duration(secondsComponent: -ratio, attosecondsComponent: 0)
        self.discDegress = 0
        if self.currentAudioDuration.components.seconds < 0 {
            self.currentAudioDuration = Duration(secondsComponent: 0, attosecondsComponent: 0)
        }
        if self.currentAudioDuration.components.seconds > self.audioTotalDuration.components.seconds {
            self.currentAudioDuration = Duration(secondsComponent: self.audioTotalDuration.components.seconds, attosecondsComponent: 0)
        }
        self.audioController?.seek(to: self.currentAudioDuration)
    }
    
    private func startAudioTimer() {
        let timer = Timer(timeInterval: 1.0, repeats: true, block: { [weak self] _ in
            self?.currentAudioDuration += Duration(secondsComponent: 1, attosecondsComponent: 0)
        })
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    
    private func stopAudioTimer() {
        self.timer?.invalidate()
        self.timer = nil
    }
    
    private func changeDiscOpacity(isToClear: Bool) async {
        let frameRate: TimeInterval = 1.0/20.0 // 20FPS
        let duration: TimeInterval = 0.5
        let totalFrames = Int(duration / frameRate)
        var currentFrame = 0
        
        await MainActor.run {
            _ = Timer.scheduledTimer(withTimeInterval: frameRate, repeats: true, block: { [weak self] timer in
                guard var opacityComponent = self?.disc.components[OpacityComponent.self] else { return }

                currentFrame += 1
                let progress = Float(currentFrame) / Float(totalFrames)
                opacityComponent.opacity = isToClear ? (1 - progress) : progress
                self?.disc.components[OpacityComponent.self] = opacityComponent
                
                if currentFrame >= totalFrames {
                    timer.invalidate()
                }
            })
        }
    }
    
    private func adjustDecibel(ratio: Double) {
        self.audioController?.fade(to: ratio * -30, duration: 0)
    }
    
    private func generateNeedUpTransform() -> Transform {
        return Transform(rotation: simd_quatf(angle: -.pi/6, axis: SIMD3<Float>(0.0, 1.0, 0.0)))
    }
    
    private func generateNeedDownTransform() -> Transform {
        return Transform(rotation: simd_quatf(angle: 0, axis: SIMD3<Float>(0.0, 1.0, 0.0)))
    }
}
