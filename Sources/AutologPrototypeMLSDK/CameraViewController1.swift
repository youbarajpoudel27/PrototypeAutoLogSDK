//
//  File.swift
//  
//
//  Created by Youbaraj POUDEL on 26/02/2024.
//

import UIKit
import SwiftUI
import AVFoundation
import Vision
import Photos


@available(iOS 13.0, *)
class CameraViewController1: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var permissionGranted = false // Flag for permission
    var readyForScan = true
    
    private let captureSession = AVCaptureSession()
    
    private let sessionQueue = DispatchQueue(label: "sessionQueue")
    private var previewLayer = AVCaptureVideoPreviewLayer()
    var position: AVCaptureDevice.Position = .back

    
    @Published var capturedImage: UIImage? = nil
    @Published private var flashMode: AVCaptureDevice.FlashMode = .off
    var screenRect: CGRect! = nil // For view dimensions
    
    // Detector Specific
    private var videoOutput = AVCaptureVideoDataOutput()
    var requests = [VNRequest]()
    var detectionLayer: CALayer! = nil
    
      
    override func viewDidLoad() {
        checkCameraPermissions()
        
        sessionQueue.async { [unowned self] in
            guard permissionGranted else { return }
            self.setupFrameCaptureSession()
        
            self.setupLayers()
            self.setupGrainDetector()
            // Add the photo output.
            self.setupVideoInput()
            self.setupPhotoOutput()
            
            self.captureSession.startRunning()
        }
    }
    
    override func willTransition(to newCollection: UITraitCollection, with coordinator: UIViewControllerTransitionCoordinator) {
        screenRect = UIScreen.main.bounds
        self.previewLayer.frame = CGRect(x: 0, y: 0, width: screenRect.size.width, height: screenRect.size.height)

        switch UIDevice.current.orientation {
            // Home button on top
            case UIDeviceOrientation.portraitUpsideDown:
                self.previewLayer.connection?.videoOrientation = .portraitUpsideDown
             
            // Home button on right
            case UIDeviceOrientation.landscapeLeft:
                self.previewLayer.connection?.videoOrientation = .landscapeRight
            
            // Home button on left
            case UIDeviceOrientation.landscapeRight:
                self.previewLayer.connection?.videoOrientation = .landscapeLeft
             
            // Home button at bottom
            case UIDeviceOrientation.portrait:
                self.previewLayer.connection?.videoOrientation = .portrait
                
            default:
                break
            }
        
        // Detector
        updateObjectDetectionLayers()
    }
   
    
    //IF Permission is granted steup capture session.
    func setupFrameCaptureSession() {
        // Camera input
        guard let videoDevice = AVCaptureDevice.default(.builtInDualWideCamera,for: .video, position: .back) else { return }
        guard let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice) else { return }
           
        guard captureSession.canAddInput(videoDeviceInput) else { return }
        captureSession.addInput(videoDeviceInput)
                         
        // Preview layer
        screenRect = UIScreen.main.bounds
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = CGRect(x: 0, y: 0, width: screenRect.size.width, height: screenRect.size.height)
        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill // Fill screen
        previewLayer.connection?.videoOrientation = .portrait
        
        // Detector
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sampleBufferQueue"))
        captureSession.addOutput(videoOutput)
        
        videoOutput.connection(with: .video)?.videoOrientation = .portrait
        
        // Updates to UI must be on main queue
        DispatchQueue.main.async { [weak self] in
            self!.view.layer.addSublayer(self!.previewLayer)
        }
    }
    
    enum Status {
        case configured
        case unconfigured
        case unauthorized
        case failed
    }
    
    private func setupVideoInput() {
        do {
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
            guard let camera else {
                print("CameraManager: Video device is unavailable.")
                status = .unconfigured
                captureSession.commitConfiguration()
                return
            }
            
            let videoInput = try AVCaptureDeviceInput(device: camera)
            
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
                videoDeviceInput = videoInput
                status = .configured
            } else {
                print("CameraManager: Couldn't add video device input to the session.")
                status = .unconfigured
                captureSession.commitConfiguration()
                return
            }
            
           //set sutofocus
      
            camera.unlockForConfiguration()
            do {
                try camera.unlockForConfiguration()
                //zoome factor
                let maxZoomFactor = camera.activeFormat.videoMaxZoomFactor
                let zoomFactor = min(maxZoomFactor, max(1.0, maxZoomFactor))
                camera.videoZoomFactor = 1.6
                camera.unlockForConfiguration()
            } catch {
                print("Failed to set zoom level due to \(error.localizedDescription)")
            }
            
            
        } catch {
            print("CameraManager: Couldn't create video device input: \(error)")
            status = .failed
            captureSession.commitConfiguration()
            return
        }
    }
    
    let photoOutput = AVCapturePhotoOutput()
    @Published var status = Status.unconfigured

    private func setupPhotoOutput() {
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.maxPhotoQualityPrioritization = .quality // work for ios 15.6 and the older versions
            // photoOutput.maxPhotoDimensions = .init(width: 4032, height: 3024) // for ios 16.0*
            status = .configured
        } else {
            print("CameraManager: Could not add photo output to the session")
            status = .failed
            captureSession.commitConfiguration()
            return
        }
    }
    
    private var cameraDelegate: CameraDelegate?
    var videoDeviceInput: AVCaptureDeviceInput?

    func captureImage() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            
            var photoSettings = AVCapturePhotoSettings()
            
            // Capture HEIC photos when supported
            if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            }
            
            // Sets the flash option for the capture
            if ((self.videoDeviceInput?.device.isFlashAvailable) != nil) {
                photoSettings.flashMode = self.flashMode
            }
            
            photoSettings.isHighResolutionPhotoEnabled = true
            
            // Sets the preview thumbnail pixel format
            if let previewPhotoPixelFormatType = photoSettings.availablePreviewPhotoPixelFormatTypes.first {
                photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: previewPhotoPixelFormatType]
            }
            photoSettings.photoQualityPrioritization = .quality
            
            if let videoConnection = photoOutput.connection(with: .video), videoConnection.isVideoOrientationSupported {
                videoConnection.videoOrientation = .portrait
            }
            
            cameraDelegate = CameraDelegate { [weak self] image in
                self?.capturedImage = image
            }
            
            if let cameraDelegate {
                self.photoOutput.capturePhoto(with: photoSettings, delegate: cameraDelegate)
            }
        }
    }

    func triggerSnapPhoto(){
        showAlert()
    }
    
    
    public   func showAlert() {
        // Create the alert controller
        let alertController = UIAlertController(title: "Snap Alert", message: "Significant Grain Detected , You can snap the capture.", preferredStyle: .alert)
        
        // Create an action for the alert
        // For example, a 'Dismiss' action
        let dismissAction = UIAlertAction(title: "Okay", style: .default) { (action) in
            // Code to execute when the dismiss action is selected
            // For now, it does nothing, just dismisses the alert
            self.captureImage()

        }
        
        // Add the action to the alert controller
        alertController.addAction(dismissAction)
        
        // Present the alert to the user
        present(alertController, animated: true, completion: nil)
    }
    
   
    //Phone's Util specific functions
    //MARK : Camera Permissions
    public  func checkCameraPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            // Permission has been granted before
            case .authorized:
                permissionGranted = true
                
            // Permission has not been requested yet
            case .notDetermined:
                requestCameraPermission()
                    
            default:
                permissionGranted = false
            }
    }
    
    func requestCameraPermission() {
        sessionQueue.suspend()
        AVCaptureDevice.requestAccess(for: .video) { [unowned self] granted in
            self.permissionGranted = granted
            self.sessionQueue.resume()
        }
    }
    
    //END : Camera Permissions
    
}

@available(iOS 13.0, *)
 struct CameraViewSDK: UIViewControllerRepresentable {

    public func makeUIViewController(context: Context) -> UIViewController {
        return CameraViewController1()
    }

    public func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

public class CameraDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    
    private let completion: (UIImage?) -> Void
    
    public init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }
    
    public  func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            print("CameraManager: Error while capturing photo: \(error)")
            completion(nil)
            return
        }
        
        if let imageData = photo.fileDataRepresentation(), let capturedImage = UIImage(data: imageData) {
            saveImageToGallery(capturedImage)
            completion(capturedImage)
        } else {
            print("CameraManager: Image not fetched.")
        }
    }
    
    public func saveImageToGallery(_ image: UIImage) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        } completionHandler: { success, error in
            if success {
                print("Image saved to gallery.")
            } else if let error {
                print("Error saving image to gallery: \(error)")
            }
        }
    }
}


