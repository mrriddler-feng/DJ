//
//  ImmersiveView.swift
//  DJ
//
//  Created by 峰 on 2025/2/25.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ImmersiveView: View {
    
    let turnTable = TurnTable()
    @State var pickerCur: Int = 0
    
    var body: some View {
        RealityView { content, attachments  in
            // Add the initial RealityKit content
            if let immersiveContentEntity = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                content.add(immersiveContentEntity)
                self.turnTable.setupContent(content: immersiveContentEntity)
            }
            
            if let experienceInfo = attachments.entity(for: "Track") {
                content.add(experienceInfo)
                experienceInfo.transform.rotation = simd_quatf(angle: -.pi / 4, axis: [1,0,0])
                experienceInfo.position += [0, 0.45, -0.3]
            }
        } attachments: {
            Attachment(id: "Track") {
                    VStack(spacing: 20) {
                        Text("Choose your track!")
                            .font(.title)
                        Picker("Track", selection: $pickerCur) {
                            Text("Ocean")
                                .font(.subheadline)
                                .foregroundStyle(Color.secondary)
                                .tag(0)
                            Text("Forest")
                                .font(.subheadline)
                                .foregroundStyle(Color.secondary)
                                .tag(1)
                            Text("Storm")
                                .font(.subheadline)
                                .foregroundStyle(Color.secondary)
                                .tag(2)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: pickerCur) { oldValue, newValue in
                            print(pickerCur)
                            if pickerCur == 0 {
                                self.turnTable.changeToTrack(track: .Ocean)
                            } else if pickerCur == 1 {
                                self.turnTable.changeToTrack(track: .Forest)
                            } else if pickerCur == 2 {
                                self.turnTable.changeToTrack(track: .Storm)
                            }
                        }
                    }
                    .padding(20)
                    .glassBackgroundEffect()
                    .frame(width: 450)
            }
        }
        .gesture(DragGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                self.turnTable.handleDragChanged(value: (value.entity, value.gestureValue))
            }.onEnded { value in
                self.turnTable.handleDragEnded(value: (value.entity, value.gestureValue))
            })
        .gesture(RotateGesture3D(constrainedToAxis: .y)
            .targetedToAnyEntity()
            .onChanged({ value in
                self.turnTable.handleRotateChanged(value: (value.entity, value.gestureValue))
            })
        )
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
