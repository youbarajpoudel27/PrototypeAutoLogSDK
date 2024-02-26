//
//  File.swift
//  
//
//  Created by Youbaraj POUDEL on 26/02/2024.
//
 
import Vision
import AVFoundation
import UIKit

@available(iOS 13.0, *)
extension CameraViewController1 {
    
    func setupGrainDetector() {
        let modelURL = Bundle.main.url(forResource: "GrainDetectionModel", withExtension: "mlmodelc")
    
        do {
            let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: modelURL!))
            let recognitions = VNCoreMLRequest(model: visionModel, completionHandler: detectionDidComplete)
          //  print("rec: \(recognitions)")

            self.requests = [recognitions]
        } catch let error {
            print(error)
        }
    }
 
    func detectionDidComplete(request: VNRequest, error: Error?) {
        if readyForScan {
            DispatchQueue.main.async(execute: {
                if let results = request.results {
                    self.setUpAutologWithExtractedDetections(results)
                    //print(results)

                }
                
            })
        }
       
    }
    

    func setUpAutologWithExtractedDetections(_ results: [VNObservation]) {
        var minX: Double = 0.0
        var maxX: Double = 0.0
        var minY: Double = 0.0
        var maxY: Double = 0.0
        
        let experimentalOffset: Double = -2
        let minPercentageGrainDetectionTrigger: Double = 90

        var heightCoverage: Double = 0.0
        var widthCoverage: Double = 0.0
        
      
        
        let screenSize: CGRect = CGRect(x: 0,y: 0,width: 294.8, height: 661.5)
        
        let heightThreshold: Double = (screenSize.height * minPercentageGrainDetectionTrigger)/100
        let widthThreshold: Double = (screenSize.width * minPercentageGrainDetectionTrigger)/100
        
        let boundingBoxAreaThreshold: Double = 0.007721518166363239
        
        detectionLayer.sublayers = nil
        
        var boundingBoxArray = [Double]()
        for observation in results where observation is VNRecognizedObjectObservation {
            guard let objectObservation = observation as? VNRecognizedObjectObservation else { continue }
            
            // Transformations
            let objectBounds = VNImageRectForNormalizedRect(objectObservation.boundingBox, Int(screenRect.size.width), Int(screenRect.size.height))
          
            let width =  objectObservation.boundingBox.width
            let height =  objectObservation.boundingBox.height
            
            let boundingBoxArea = width * height
            boundingBoxArray.append(boundingBoxArea)
            
            let sorted = boundingBoxArray.sorted()
            let median = sorted.sorted(by: <)[sorted.count / 2]

            print("boundingBoxArea: \(boundingBoxArea)")
            print("Median: \(median)")
            
//            print("BoundingBox: \(boundingBoxArea)")
            
            if (boundingBoxArea < boundingBoxAreaThreshold) {
                print("Yes Grains")
//                print("cars")
                
//                minX = objectBounds.minX
//                maxX = objectBounds.maxX
//                minY = objectBounds.minY
//                maxY = objectBounds.maxY
                
                
                if minX > objectBounds.minX {
                    minX = objectBounds.minX
                }
                
                if maxX < objectBounds.maxX {
                    maxX = objectBounds.maxX
                }
                
                
                if minY > objectBounds.minY {
                    minY = objectBounds.minY
                }
                
                if maxY < objectBounds.maxY {
                    maxY = objectBounds.maxY
                }
                
                widthCoverage = abs(maxX - minX)
                heightCoverage = abs(maxY - minY)
          
                var areaGrainCoverage = heightCoverage * widthCoverage
//                var coveragePercentage = 100 * areaGrainCoverage/cameraArea
                
                print("heightScreen: \(screenSize.height)")
                print("widthScreen: \(screenSize.width)")
                print("AreaScreen: \(screenSize.width * screenRect.height)")
 
                print("heightThreshold: \(heightThreshold)")
                print("widthThreshold: \(widthThreshold)")
                
                print("heightCoverage: \(heightCoverage)")
                print("widthCoverage: \(widthCoverage)")
             
                if heightCoverage + experimentalOffset > heightThreshold && widthCoverage + experimentalOffset > widthThreshold {
                    print("takeSnape: True height: \(heightCoverage) and width: \(widthCoverage)")
                 
                    readyForScan = false
                    triggerSnapPhoto()
                    
                } else {
                    print("takeSnape: False height: \(heightCoverage) and width: \(widthCoverage)")
 
                }
               
                
            } else {
                print("No Grains")
                
            }
           
        }
    }
    
    func setupLayers() {
        detectionLayer = CALayer()
        detectionLayer.frame = CGRect(x: 0, y: 0, width: screenRect.size.width, height: screenRect.size.height)
        self.view.layer.addSublayer(detectionLayer)
    }
    
    func updateObjectDetectionLayers() {
        detectionLayer?.frame = CGRect(x: 0, y: 0, width: screenRect.size.width, height: screenRect.size.height)
    }
    
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:]) // Create handler to perform request on the buffer

        do {
            try imageRequestHandler.perform(self.requests) // Schedules vision requests to be performed
        } catch {
            print(error)
        }
    }
}
