//
//  main.swift
//  Outletgen
//
//  Created by Michal Ciurus on 28/01/2019.

import Foundation


// Modules to import
var modules: Set<String> = []
// Code for view controller extensions and their outlet views
typealias OutletsDict = [String : Outlet]
var viewControllersExtensionCode: [String : OutletsDict] = [ : ]
var allRestorationIDs: Set<String> = []

let homeFolder = try! Folder(path: "")
let file = try homeFolder.createFile(named: "Outletgen.swift")

func findViewFiles(folder: Folder) {
    
    for subfolder in folder.subfolders {
        findViewFiles(folder: subfolder)
    }
    
    for file in folder.files {
        if file.extension == "xib" || file.extension == "storyboard" {
            parseXib(file: file)
        }
    }
}

func parseXib(file: File) {
    let fileString = try! file.readAsString()
    let xml = SWXMLHash.parse(fileString)
    
    readChildrenRecursivelyIn(xml: xml, destinationExtension: nil)
}

func parseConstraint(_ element: XMLElement) -> ConstraintOutlet? {
    guard let identifier = element.attribute(by: "identifier")?.text else { return nil }
    let constraintClass = element.attribute(by: "customClass")?.text ?? "NSLayoutConstraint"
    return ConstraintOutlet(constraintID: identifier, className: constraintClass)
}

func saveOutlet(extensionName: String?, outlet: Outlet?) {
    guard let vc = extensionName else { return }
    guard let outlet = outlet else { return }
    
    if viewControllersExtensionCode[vc] == nil {
        viewControllersExtensionCode[vc] = OutletsDict()
    }
    
    viewControllersExtensionCode[vc]?[outlet.id] = outlet
}

extension XMLElement {
    func getOutletID() -> String? {
        let attributes = self.xmlChildren.filter { $0.name == "userDefinedRuntimeAttributes" }
        guard let runtimeAttrs = attributes.first else { return nil }
        let outlets = runtimeAttrs.xmlChildren.filter {
            return $0.allAttributes["keyPath"]?.text == "outletIdentifier"
        }
        return outlets.first?.attribute(by: "value")?.text
    }
}

func readChildrenRecursivelyIn(xml: XMLIndexer, destinationExtension: String?) {
    // This is the Swift extension where the found views will be generated in
    var currentDestinationExtension = destinationExtension
    
    for child in xml.children {
        // Reading ViewControllers destinations
        if child.element!.name.contains("viewController") {
            if let customViewController = child.element!.attribute(by: "customClass")?.text {
                currentDestinationExtension = customViewController
                if let customModule = child.element!.attribute(by: "customModule")?.text {
                    modules.insert(customModule)
                }
            } else {
                currentDestinationExtension = nil
            }
        }
        
        // Reading table view and collection view cells and subviews destinations
        let collectionViewElements = ["tableViewCell", "collectionViewCell", "collectionReusableView"]
        if collectionViewElements.contains(child.element!.name)  {
            currentDestinationExtension = child.element!.attribute(by: "customClass")?.text
        }
        
        // Reading the xib owners destinations
        if child.element!.attribute(by: "userLabel")?.text == "File's Owner" {
            currentDestinationExtension = child.element!.attribute(by: "customClass")?.text
        }
        
        if let restId = child.element?.attribute(by: "restorationIdentifier")?.text {
            var className = "UI" + child.element!.name.capitalizingFirstLetter()
            
            if let customClass = child.element!.attribute(by: "customClass") {
                className = customClass.text
                modules.insert(child.element!.attribute(by: "customModule")!.text)
            }
            
            let view = UIViewOutlet(
                restorationID: restId,
                className: className
            )
            
            saveOutlet(extensionName: currentDestinationExtension, outlet: view)
            
            allRestorationIDs.insert(restId)
        }
        
        
        if let outletID = child.element!.getOutletID() {
            print ("\(child.element!.name) \(outletID)")
            var className = "UI" + child.element!.name.capitalizingFirstLetter()
            if className == "UIConstraint" {
                className = "NSLayoutConstraint"
            }
            
            if let customClass = child.element!.attribute(by: "customClass") {
                className = customClass.text
                modules.insert(child.element!.attribute(by: "customModule")!.text)
            }
            
            let view = UIViewOutlet(
                restorationID: outletID,
                className: className
            )
            
            saveOutlet(extensionName: currentDestinationExtension, outlet: view)
            
            allRestorationIDs.insert(outletID)
        }
        
        // Reading constraints
        if child.element!.name == "constraint" {
            let constraint = parseConstraint(child.element!)
            saveOutlet(extensionName: currentDestinationExtension, outlet: constraint)
        }
        
        readChildrenRecursivelyIn(xml: child, destinationExtension: currentDestinationExtension)
    }
}

findViewFiles(folder: homeFolder)

var generatedCode = ""
generatedCode += "//Auto Generated Code \n\n"
generatedCode += "import UIKit"

// Generating the imports
// TODO: Read current module and remove it from imports to prevent a warning
for module in modules {
    if module != getCurrentModuleName() {
        generatedCode += "\nimport \(module)"
    }
}

// Generating the extensions code
for vcKey in viewControllersExtensionCode.keys {
    generatedCode += "\n \n"
    generatedCode += "\nextension \(vcKey) {"
    for extensionVar in viewControllersExtensionCode[vcKey]!.keys {
        generatedCode += viewControllersExtensionCode[vcKey]![extensionVar]!.code
    }
    generatedCode += "\n }"
}

generatedCode += "\n \n"

// Generating the keys array code
generatedCode += "\nlet AllAssociatedObjectsKeys = "
generatedCode += "["

// Code for array with key views
var keysArrayCode: String = ""

for restId in allRestorationIDs {
    if keysArrayCode != "" {
        keysArrayCode = keysArrayCode + ", "
    }
    
    keysArrayCode = keysArrayCode + "\"\(restId)\""
}

generatedCode += keysArrayCode
generatedCode += "]"

// Adding the swizzle code
generatedCode += "\n\n//Swizzling Code \n\n"
generatedCode += logicCode

try! file.append(string: generatedCode)
