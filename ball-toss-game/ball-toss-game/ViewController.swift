//
//  ViewController.swift
//  ball-toss-game
//
//  Created by Matthew Chin on 05/10/2017.
//  Copyright © 2017 Matthew Chin. All rights reserved.
//

import UIKit
import SceneKit
import ARKit

class ViewController: UIViewController, ARSCNViewDelegate, SCNPhysicsContactDelegate {

    @IBOutlet var sceneView: ARSCNView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Diaply the buttons
        createThrowButton()
        createMagicButton()
        
        // Set the view's delegate
        sceneView.delegate = self
        
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true
        
        // Set the scene to the view
        sceneView.scene = SCNScene()
        
        // Make the scene a contact delegate of the physics world for contact detection
        sceneView.scene.physicsWorld.contactDelegate = self
        
//        // Allow various debug options to check whether real-world features are properly detected
//        sceneView.debugOptions = [.showConstraints, .showPhysicsShapes, .showLightExtents, ARSCNDebugOptions.showFeaturePoints, ARSCNDebugOptions.showWorldOrigin]
        
//        // Create an omni light source for the scene
//        let myOmniLight = SCNLight()
//        let myOmniLightNode = SCNNode()
//        myOmniLight.type = SCNLight.LightType.omni
//        myOmniLight.color = UIColor.white
//        myOmniLightNode.light = myOmniLight
//        myOmniLightNode.position = SCNVector3(x: -30, y: 30, z: 60)
//        sceneView.scene.rootNode.addChildNode(myOmniLightNode)
        
        // Add a diffuse light source that is continuously updated based on analysed light entering the camera
        self.sceneView.autoenablesDefaultLighting = true
        self.sceneView.automaticallyUpdatesLighting = true
        
        // Smooth edges of 3D objects to make them look nicer
        self.sceneView.antialiasingMode = .multisampling4X
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        
        // Configure session to detect horizontal planes
        configuration.planeDetection = .horizontal
        
        // Map AR coordinate space to the real-world coordinate space as closely as possible
        configuration.worldAlignment = .gravity
        
        configuration.isLightEstimationEnabled = true
        
        // Run the view's session
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }

    @IBAction func throwButttonPressed(_ sender: UIButton) {
        
        // Define appearance of sphere
        let sphere = SCNSphere(radius: 0.025)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.red
        material.lightingModel = .physicallyBased
        sphere.materials = [material]
        let sphereNode = SCNNode(geometry: sphere)
        sphereNode.name = "ball"

        // Initialize sphere as physics body and define physical properties
        sphereNode.physicsBody = SCNPhysicsBody(type: .dynamic, shape: nil)
        sphereNode.physicsBody?.isAffectedByGravity = true
        sphereNode.physicsBody?.mass = 0.5
        sphereNode.physicsBody?.restitution = 0.5
        sphereNode.physicsBody?.friction = 0.5
        
        // Create a sphere a quarter of a meter in front of the camera
        let camera = self.sceneView.pointOfView!
        let position = SCNVector3(x: 0, y: 0, z: -0.25)
        sphereNode.position = camera.convertPosition(position, to: nil)
        sphereNode.rotation = camera.rotation
        
        // Apply force to sphere in the direction the camera is facing
        let (direction, _) = self.getUserDirection()
        let sphereDirection = direction
        sphereNode.physicsBody?.applyForce(sphereDirection, asImpulse: true)
        
        // Add sphere node to root node
        sceneView.scene.rootNode.addChildNode(sphereNode)
        
        print("Ball thrown")
    }
    
    @IBAction func magicButttonPressed(_ sender: UIButton) {

        guard let hat = sceneView.scene.rootNode.childNode(withName: "hat", recursively:true) else {return}

        let min = hat.convertPosition((hat.boundingBox.min), to: sceneView.scene.rootNode)
        let max = hat.convertPosition((hat.boundingBox.max), to: sceneView.scene.rootNode)

        sceneView.scene.rootNode.enumerateChildNodes {node,_ in
        
        // Since the hat is within its bounding box, we need to make our search volume smaller than the original bounding box to avoid removing the hat.  To do this we multiply by 0.99.
        if node.presentation.position.x < 0.99*(max.x) && node.presentation.position.x > 0.99*(min.x) && node.presentation.position.y < 0.99*(max.y) && node.presentation.position.y > 0.99*(min.y) && node.presentation.position.z < 0.99*(max.z) && node.presentation.position.z > 0.99*(min.z) {
            
                addParticleEffects()
                node.removeFromParentNode()
                print("Magic!")
            }
        }
    }

    // MARK: - ARSCNViewDelegate
    
    // Get camera direction for ball throwing
    func getUserDirection() -> (SCNVector3, SCNVector3) { // (direction, position)
        
        if let frame = self.sceneView.session.currentFrame {
            // 4x4 transform matrix representing camera in world coordinate space
            let mat = SCNMatrix4(frame.camera.transform)
            // Orientation of camera in world space
            // Note: the multiplied factor defines the magnitude and direction of force
            let dir = SCNVector3(-2 * mat.m31, -2 * mat.m32, -2 * mat.m33)
            // Location of camera in world space (in case you need this info.)
            let pos = SCNVector3(mat.m41, mat.m42, mat.m43)
            
            return (dir, pos)
        }
        return (SCNVector3(0, 0, -1), SCNVector3(0, 0, -0.2))
    }
    
    
    @IBAction func onViewTapped(_ sender: UITapGestureRecognizer) {
        // Get tap location
        let tapLocation = sender.location(in: sceneView)
        
        // Perform hit test
        let results = sceneView.hitTest(tapLocation, types: .existingPlaneUsingExtent)
        
        // If a hit was received, get position of
        if let result = results.first {
            // Place the hat at the tapped location
            placeHat(result)
            // Also add a floor so that the balls won't fall to -inf on y-axis
            placeFloor(result)
        }
    }
    
    // Place a hat in the scene
    func placeHat(_ result: ARHitTestResult) {
        
        // Get transform of result
        let transform = result.worldTransform
        
        // Get position from transform (4th column of transformation matrix)
        let planePosition = SCNVector3Make(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        
        // Add hat
        let hatNode = createHatFromScene(planePosition)!
        hatNode.name = "hat"
        sceneView.scene.rootNode.addChildNode(hatNode)
    
    }
    
    // Give hat.scn a node
    private func createHatFromScene(_ position: SCNVector3) -> SCNNode? {
        guard let url = Bundle.main.url(forResource: "art.scnassets/hat", withExtension: "scn") else {
            NSLog("Could not find hat scene")
            return nil
        }
        guard let node = SCNReferenceNode(url: url) else { return nil }
        
        node.load()
        
        // Position scene
        node.position = position
        
        return node
    }
    
    // Place a floor in the scene
    func placeFloor(_ result: ARHitTestResult) {
        
        // Get transform of result
        let transform = result.worldTransform
        
        // Get position from transform (4th column of transformation matrix)
        let planePosition = SCNVector3Make(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        
        // Add floor
        let floorNode = createFloorFromScene(planePosition)!
        sceneView.scene.rootNode.addChildNode(floorNode)
        
    }
    
    // Make a node for the floor
    private func createFloorFromScene(_ position: SCNVector3) -> SCNNode? {
        let floorNode = SCNNode()
        let floor =  SCNFloor()
        floorNode.geometry = floor
        floorNode.geometry?.firstMaterial?.diffuse.contents = UIColor.clear
        floorNode.physicsBody=SCNPhysicsBody(type: .static, shape: nil)
        
        floorNode.position = position
        
        return floorNode
    }
    
    // Plane node that is anchored to detected plane
    private var planeNode: SCNNode?
    
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        // Create an SCNNode for a detect ARPlaneAnchor
        guard let _ = anchor as? ARPlaneAnchor else {
            return nil
        }
        planeNode = SCNNode()
        return planeNode
    }
    
    // Add a plane to the scene to show user that a plane has been detected
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        
        // Create an SNCPlane on the ARPlane
        guard let planeAnchor = anchor as? ARPlaneAnchor else {
            return
        }
        
        let plane = SCNPlane(width: CGFloat(planeAnchor.extent.x), height: CGFloat(planeAnchor.extent.z))
        
        let planeMaterial = SCNMaterial()
        planeMaterial.diffuse.contents = UIColor(red: 255/255, green: 255/255, blue: 255/255, alpha: 0.3)
        plane.materials = [planeMaterial]
        
        let planeNode = SCNNode(geometry: plane)
        planeNode.position = SCNVector3Make(planeAnchor.center.x, 0, planeAnchor.center.z)
        
        planeNode.transform = SCNMatrix4MakeRotation(-Float.pi / 2, 1, 0, 0)
        
        node.addChildNode(planeNode)
        
    }
    
    // Create button for throwing balls
    func createThrowButton() {
        let button = UIButton(frame: CGRect(x: 200, y: 550, width: 150, height: 90))
        button.backgroundColor = UIColor.white
        let lightBlue = UIColor(red: 53.0/255.0, green: 155.0/255.0, blue: 220.0/255.0, alpha: 1.0)
        let lightGrey = UIColor(red: 53, green: 155, blue: 220, alpha: 0.5)
        button.backgroundColor = UIColor.white
        button.layer.cornerRadius = 5
        button.layer.borderWidth = 1
        button.setTitleColor(lightBlue, for: .normal)
        button.setTitleColor(lightGrey, for: .highlighted)
        button.setTitle("Throw Ball", for: [])
        button.titleLabel!.font =  UIFont(name:"Arial", size: 20)
        button.addTarget(self, action: #selector(throwButttonPressed), for: .touchUpInside)
        
        self.view.addSubview(button)
    }
    
    // Create button for vanishing balls
    func createMagicButton() {
        let button = UIButton(frame: CGRect(x: 30, y: 550, width: 150, height: 90))
        let lightBlue = UIColor(red: 53.0/255.0, green: 155.0/255.0, blue: 220.0/255.0, alpha: 1.0)
        let lightGrey = UIColor(red: 53, green: 155, blue: 220, alpha: 0.5)
        button.backgroundColor = UIColor.white
        button.layer.cornerRadius = 5
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.black.cgColor
        button.setTitleColor(lightBlue, for: .normal)
        button.setTitleColor(lightGrey, for: .highlighted)
        button.setTitle("Magic!", for: [])
        button.titleLabel!.font =  UIFont(name:"Arial", size: 20)
        button.addTarget(self, action: #selector(magicButttonPressed), for: .touchUpInside)
        
        self.view.addSubview(button)
    }
    
    private func addParticleEffects() {
        let hat = sceneView.scene.rootNode.childNode(withName: "hat", recursively: true)
        let sparkles = SCNParticleSystem(named: "sparkles", inDirectory: nil)!
        hat?.addParticleSystem(sparkles)
    }
    
    /*
     Contact detection functions for debugging purposes
     */
    
    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        print("contactDelegate: Begin")
    }
    
    func physicsWorld(_ world: SCNPhysicsWorld, didUpdate contact: SCNPhysicsContact) {
        print("contactDelegate: Update")
    }
    
    func physicsWorld(_ world: SCNPhysicsWorld, didEnd contact: SCNPhysicsContact) {
        print("contactDelegate: End")
        
        let firstNode = contact.nodeA
        let secondNode = contact.nodeB
        
        print("NodeA: \(String(describing: firstNode.name!))")
        print("NodeB: \(String(describing: secondNode.name!))")
        
        print("contactPoint: \(String(describing: contact.contactPoint))")
        print("contactNormal: \(String(describing: contact.contactNormal))")
        print("collisionImpulse: \(String(describing: contact.collisionImpulse))")
        print("penetrationDistance: \(String(describing: contact.penetrationDistance))")
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        
    }
    
}

