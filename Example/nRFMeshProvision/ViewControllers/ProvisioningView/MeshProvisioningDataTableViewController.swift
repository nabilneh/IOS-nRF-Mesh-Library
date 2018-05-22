//
//  MeshConfigurationTableViewController.swift
//  nRFMeshProvision_Example
//
//  Created by Mostafa Berg on 16/01/2018.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import UIKit
import nRFMeshProvision
import CoreBluetooth

class MeshProvisioningDataTableViewController: UITableViewController, UITextFieldDelegate {

    // MARK: - Outlets and Actions
    @IBOutlet weak var provisioningProgressIndicator: UIProgressView!
    @IBOutlet weak var provisioningProgressLabel: UILabel!
    @IBOutlet weak var provisioningProgressTitleLabel: UILabel!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var provisioningActionCell: UITableViewCell!
    @IBOutlet weak var provisioningProgressCell: UITableViewCell!
    @IBOutlet weak var nodeNameCell: UITableViewCell!
    @IBOutlet weak var unicastAddressCell: UITableViewCell!
    @IBOutlet weak var appKeyCell: UITableViewCell!
    
    // MARK: - Properties
    private var isProvisioning: Bool = false
    private var totalSteps: Float = 24
    private var completedSteps: Float = 0
    private var targetNode: UnprovisionedMeshNode!
    private var logEntries: [LogEntry] = [LogEntry]()
    private var meshManager: NRFMeshManager!
    private var stateManager: MeshStateManager!
    private var centralManager: CBCentralManager!
    
    // AppKey Configuration
    private var netKeyIndex: Data!
    private var appKeyIndex: Data!
    private var appKeyData: Data!
    
    // Private temprorary Unicast storage between prov/config state
    private var targetNodeUnicast: Data?
    
    // Provisioned node properties
    var destinationAddress: Data!
    var targetProvisionedNode: ProvisionedMeshNode!

    var nodeName: String! = "Mesh Node"
    var nodeAddress: Data!
    var appKeyName: String!
    let freetextTag = 1 //Text fields tagged with this value will allow any input type
    let hexTextTag  = 2 //Text fields tagget with this value will only allow Hex input

    // MARK: - UIViewController implementation
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if appKeyName == nil {
            updateProvisioningDataUI()
        }
    }

    // MARK: - Implementaiton
    private func updateProvisioningDataUI() {
        if nodeName == "Mesh Node" {
            nodeName = targetNode.nodeBLEName()
        }
        let nextUnicast = meshManager.stateManager().state().nextUnicast
        //Set the unicast according to the state
        nodeAddress = nextUnicast
        //Update provisioning Data UI with default values
        unicastAddressCell.detailTextLabel?.text = "0x\(nodeAddress.hexString())"
        nodeNameCell.detailTextLabel?.text = nodeName
        //Select first key by default
        didSelectAppKeyWithIndex(0)
    }

    public func setTargetNode(_ aNode: UnprovisionedMeshNode) {
        if let aManager = (UIApplication.shared.delegate as? AppDelegate)?.meshManager {
            meshManager     = aManager
            targetNode      = aNode
            targetNode.delegate     = self
            targetNode.logDelegate  = self as UnprovisionedMeshNodeLoggingDelegate
            stateManager            = meshManager.stateManager()
            centralManager          = meshManager.centralManager()
        }
    }

    func handleProvisioningButtonTapped() {
        if isProvisioning == false {
            navigationItem.hidesBackButton = true
            isProvisioning = true
            connectNode(targetNode)
        }
    }

    func didSelectUnicastAddressCell() {
        let unicast = meshManager.stateManager().state().unicastAddress
        presentInputViewWithTitle("Please enter Unicast Address",
                                  message: "2 Bytes, > 0x0000",
                                  inputType: hexTextTag,
                                  placeholder: self.nodeAddress.hexString()) { (anAddress) -> Void in
                                    if var anAddress = anAddress {
                                        anAddress = anAddress.lowercased().replacingOccurrences(of: "0x", with: "")
                                        if anAddress.count == 4 {
                                            if anAddress == "0000" ||
                                                anAddress == String(data: unicast,
                                                                    encoding: .utf8) {
                                                print("Adderss cannot be 0x0000, minimum possible address is 0x0001")
                                            } else {
                                                self.nodeAddress = Data(hexString: anAddress)
                                                let readableName = "0x\(self.nodeAddress.hexString())"
                                                self.unicastAddressCell.detailTextLabel?.text = readableName
                                            }
                                        } else {
                                            print("Unicast address must be exactly 2 bytes")
                                        }
                                    }
        }
    }

    func didSelectNodeNameCell() {
        presentInputViewWithTitle("Please enter a name",
                                  message: "20 Characters Max",
                                  inputType: freetextTag,
                                  placeholder: "\(self.targetNode.nodeBLEName())") { (aName) -> Void in
                                    if let aName = aName {
                                        if aName.count <= 20 {
                                            self.nodeName = aName
                                            self.nodeNameCell.detailTextLabel?.text = aName
                                        } else {
                                            print("Name cannot be longer than 20 characters")
                                        }
                                    }
        }
    }

    func didSelectAppkeyCell() {
        self.performSegue(withIdentifier: "showAppKeySelector", sender: nil)
    }

    func didSelectAppKeyWithIndex(_ anIndex: Int) {
        let meshState = meshManager.stateManager().state()
        netKeyIndex = meshState.keyIndex
        let appKey = meshState.appKeys[anIndex]
        appKeyName = appKey.keys.first
        appKeyData = appKey.values.first
        let anAppKeyIndex = UInt16(anIndex)
        appKeyIndex = Data([UInt8((anAppKeyIndex & 0xFF00) >> 8), UInt8(anAppKeyIndex & 0x00FF)])
        appKeyCell.textLabel?.text = appKeyName
        appKeyCell.detailTextLabel?.text = "0x\(appKeyData!.hexString())"
    }

    // MARK: - Input Alert
    func presentInputViewWithTitle(_ aTitle: String,
                                   message aMessage: String,
                                   inputType: Int,
                                   placeholder aPlaceholder: String?,
                                   andCompletionHandler aHandler : @escaping (String?) -> Void) {
        let inputAlertView = UIAlertController(title: aTitle, message: aMessage, preferredStyle: .alert)
        inputAlertView.addTextField { (aTextField) in
            aTextField.keyboardType = UIKeyboardType.asciiCapable
            aTextField.returnKeyType = .done
            aTextField.delegate = self
            aTextField.tag = inputType
            //Show clear button button when user is not editing
            aTextField.clearButtonMode = UITextFieldViewMode.whileEditing
            if let aPlaceholder = aPlaceholder {
                aTextField.text = aPlaceholder
            }
        }

        let saveAction = UIAlertAction(title: "Save", style: .default) { (_) in
            DispatchQueue.main.async {
                if let text = inputAlertView.textFields![0].text {
                    if text.count > 0 {
                        if inputType == self.hexTextTag {
                            aHandler(text.uppercased())
                        } else {
                            aHandler(text)
                        }
                    }
                }
            }
        }

        let cancelACtion = UIAlertAction(title: "Cancel", style: .cancel) { (_) in
            DispatchQueue.main.async {
                aHandler(nil)
            }
        }

        inputAlertView.addAction(saveAction)
        inputAlertView.addAction(cancelACtion)
        present(inputAlertView, animated: true, completion: nil)
    }

    // MARK: - UITextFieldDelegate
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        return true
    }

    func textField(_ textField: UITextField,
                   shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {
        if textField.tag == freetextTag {
            return true
        } else if textField.tag == hexTextTag {
            if range.length > 0 {
                //Going backwards, always allow deletion
                return true
            } else {
                let value = string.data(using: .utf8)![0]
                //Only allow HexaDecimal values 0->9, a->f and A->F or x
                return (value == 120 || value >= 48 && value <= 57) || (value >= 65 && value <= 70) || (value >= 97 && value <= 102)
            }
        } else {
            return true
        }
   }

    // MARK: - Table view delegate
    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return !isProvisioning
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch indexPath.section {
        case 0:
            switch indexPath.row {
            case 0:
                didSelectNodeNameCell()
            case 1:
                didSelectUnicastAddressCell()
            case 2:
                didSelectAppkeyCell()
            default:
                break
            }
        case 1:
            handleProvisioningButtonTapped()
        default:
            break
        }
    }

    // MARK: - Segue and flow
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        return identifier == "showAppKeySelector"
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showAppKeySelector" {
            if let destinationView = segue.destination as? AppKeySelectorTableViewController {
                destinationView.setSelectionCallback({ (appKeyIndex) in
                    self.didSelectAppKeyWithIndex(appKeyIndex)
                }, andMeshStateManager: meshManager.stateManager())
            }
        }
    }
}

extension MeshProvisioningDataTableViewController {
    
    // MARK: - Progress handling
    func stepCompleted(withIndicatorState activityEnabled: Bool) {
        DispatchQueue.main.async {
            activityEnabled ? self.activityIndicator.stopAnimating() : self.activityIndicator.startAnimating()
            self.completedSteps += 1.0
            if self.completedSteps >= self.totalSteps {
                self.provisioningProgressLabel.text = "100 %"
                self.provisioningProgressTitleLabel.text = "Progress"
                self.provisioningProgressIndicator.setProgress(1, animated: true)
            } else {
                let completion = self.completedSteps / self.totalSteps * 100.0
                self.provisioningProgressLabel.text = "\(Int(completion)) %"
                self.provisioningProgressIndicator.setProgress(completion / 100.0, animated: true)
            }
        }
    }
    
    // MARK: - Logging
    public func logEventWithMessage(_ aMessage: String) {
        print("LOG: \(aMessage)")
//        logEntries.append(LogEntry(withMessage: aMessage, andTimestamp: Date()))
//        provisioningLogTableView?.reloadData()
//        if logEntries.count > 0 {
//            //Scroll to bottom of table view when we start getting data
//            //(.bottom places the last row to the bottom of tableview)
//            provisioningLogTableView?.scrollToRow(at: IndexPath(row: logEntries.count - 1, section: 0),
//                                                  at: .bottom, animated: true)
//        }
    }

    // MARK: - Provisioning and Configuration
    private func verifyNodeIdentity(_ identityData: Data, withUnicast aUnicast: Data) -> Bool{
        let dataToVerify = Data(identityData.dropFirst())
        let netKey = stateManager.state().netKey
        let hash = Data(dataToVerify.dropLast(8))
        let random = Data(dataToVerify.dropFirst(8))
        let helper = OpenSSLHelper()
        let salt = helper.calculateSalt(Data([0x6E, 0x6B, 0x69, 0x6B])) //"nkik" ASCII
        let p =  Data([0x69, 0x64, 0x31, 0x32, 0x38, 0x01]) // id128 || 0x01
        if let identityKey = helper.calculateK1(withN: netKey, salt: salt, andP: p) {
            let padding = Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
            let hashInputs = padding + random + aUnicast
            if let fullHash = helper.calculateEvalue(with: hashInputs, andKey: identityKey) {
                let calculatedHash = fullHash.dropFirst(fullHash.count - 8) //Keep only last 64 bits
                if calculatedHash == hash {
                    return true
                } else {
                    return false
                }
            } else {
                return false
            }
        }
        return false
    }

    private func discoveryCompleted() {
        logEventWithMessage("discovery completed")
        let meshStateObject = stateManager.state()
        let netKeyIndex = meshStateObject.keyIndex
        
        //Pack the Network Key
        let netKeyOctet1 = netKeyIndex[0] << 4
        var netKeyOctet2 =  netKeyIndex[1] & 0xF0
        netKeyOctet2 = netKeyOctet2 >> 4
        let firstOctet = netKeyOctet1 | netKeyOctet2
        let secondOctet = netKeyIndex[1] << 4
        let packedNetKey = Data([firstOctet, secondOctet])
        
        let nodeProvisioningdata = ProvisioningData(netKey: meshStateObject.netKey,
                                                    keyIndex: packedNetKey,
                                                    flags: meshStateObject.flags,
                                                    ivIndex: meshStateObject.IVIndex,
                                                    friendlyName: nodeName,
                                                    unicastAddress: self.nodeAddress)
        targetNode.provision(withProvisioningData: nodeProvisioningdata)
        stepCompleted(withIndicatorState: false)
    }

    private func connectNode(_ aNode: ProvisionedMeshNode) {
        targetProvisionedNode = aNode
        centralManager.delegate = self
        centralManager.connect(targetProvisionedNode.blePeripheral(), options: nil)
    }
    
    private func connectNode(_ aNode: UnprovisionedMeshNode) {
        targetNode = aNode
        centralManager.delegate = self
        centralManager.connect(targetNode.blePeripheral(), options: nil)
        targetNode.logDelegate?.logConnect()
    }
}

extension MeshProvisioningDataTableViewController: CBCentralManagerDelegate {
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        //Looking for advertisement data of service 0x1828 with 17 octet length
        //0x01 (Node ID), 8 Octets Hash + 8 Octets Random number
        if let serviceDataDictionary = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]{
            if let data = serviceDataDictionary[MeshServiceProxyUUID] {
                if data.count == 17 {
                    if data[0] == 0x01 {
                        self.logEventWithMessage("found proxy node with node id: \(data.hexString())")
                        self.logEventWithMessage("verifying NodeID: \(data.hexString())")
                        if targetNodeUnicast != nil {
                            if verifyNodeIdentity(data, withUnicast: targetNodeUnicast!) {
                                stepCompleted(withIndicatorState: true)
                                logEventWithMessage("node identity verified!")
                                logEventWithMessage("unicast found: \(targetNodeUnicast!.hexString())")
                                central.stopScan()
                                targetProvisionedNode = ProvisionedMeshNode(withUnprovisionedNode: targetNode,
                                                                            andDelegate: self)
                                let currentDelegate = targetNode.blePeripheral().delegate
                                peripheral.delegate = currentDelegate
                                targetNode = nil
                                targetProvisionedNode.overrideBLEPeripheral(peripheral)
                                connectNode(targetProvisionedNode)
                                targetNodeUnicast = nil
                            } else {
                                self.logEventWithMessage("unexpected unicast, skipping node.")
                            }
                        }
                    }
                }
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if targetNode != nil {
            if peripheral == targetNode.blePeripheral() {
                logDisconnect()
            }
        } else if targetProvisionedNode != nil {
            if peripheral == targetProvisionedNode.blePeripheral() {
                logDisconnect()
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if targetNode != nil {
            logEventWithMessage("unprovisioned node connected")
            logEventWithMessage("starting service discovery")
            targetNode.discover()
        } else if targetProvisionedNode != nil {
            logEventWithMessage("provisioned proxy node connected")
            logEventWithMessage("starting service discovery")
            stepCompleted(withIndicatorState: true)
            targetProvisionedNode.discover()
        }
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            if targetNode != nil {
                connectNode(targetNode)
            }
            if targetProvisionedNode != nil {
                stepCompleted(withIndicatorState: true)
                connectNode(targetProvisionedNode)
            }
        } else {
            logEventWithMessage("central manager not available")
        }
    }
}

extension MeshProvisioningDataTableViewController: UnprovisionedMeshNodeDelegate {
    func nodeShouldDisconnect(_ aNode: UnprovisionedMeshNode) {
        if aNode == targetNode {
            centralManager.cancelPeripheralConnection(aNode.blePeripheral())
        }
    }
    
    func nodeRequiresUserInput(_ aNode: UnprovisionedMeshNode,
                               completionHandler aHandler: @escaping (String) -> Void) {
        let alertView = UIAlertController(title: "Device request",
                                          message: "please enter confirmation code",
                                          preferredStyle: UIAlertControllerStyle.alert)
        var textField: UITextField?
        alertView.addTextField { (aTextField) in
            aTextField.placeholder = "1234"
            aTextField.keyboardType = .decimalPad
            textField = aTextField
        }
        let okAction = UIAlertAction(title: "Ok", style: .default) { (_) in
            aHandler((textField?.text)!)
            self.dismiss(animated: true, completion: nil)
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { (_) in
            self.logEventWithMessage("user input cancelled")
            self.dismiss(animated: true, completion: nil)
        }
        alertView.addAction(okAction)
        alertView.addAction(cancelAction)
        self.present(alertView, animated: true, completion: nil)
    }
    
    func nodeDidCompleteDiscovery(_ aNode: UnprovisionedMeshNode) {
        if aNode == targetNode {
            discoveryCompleted()
        } else {
            logEventWithMessage("unknown node completed discovery")
        }
    }
    
    func nodeProvisioningCompleted(_ aNode: UnprovisionedMeshNode) {
        stepCompleted(withIndicatorState: true)
        logEventWithMessage("Provisioning succeeded")
        //Store provisioning node data now
        let nodeEntry = aNode.getNodeEntryData()
        guard nodeEntry != nil else {
            logEventWithMessage("failed to get node entry data")
            activityIndicator.stopAnimating()
            isProvisioning = false
            navigationItem.hidesBackButton = false
            return
        }
        let state = stateManager.state()
        if let anIndex = state.provisionedNodes.index(where: { $0.nodeUnicast == nodeEntry?.nodeUnicast}) {
            state.provisionedNodes.remove(at: anIndex)
        }
        nodeEntry?.nodeUnicast = self.nodeAddress
        //Store target node unicast to verify node identity on upcoming reconnect
        targetNodeUnicast = self.nodeAddress
        state.provisionedNodes.append(nodeEntry!)
        stateManager.saveState()
        targetNode.shouldDisconnect()
        stepCompleted(withIndicatorState: true)
        //Now let's switch to a provisioned node object and start configuration
        targetProvisionedNode = ProvisionedMeshNode(withUnprovisionedNode: aNode, andDelegate: self)
        destinationAddress = self.nodeAddress
        centralManager.scanForPeripherals(withServices: [MeshServiceProxyUUID], options: nil)
        logEventWithMessage("scanning for provisioned proxy nodes")
    }
    
    func nodeProvisioningFailed(_ aNode: UnprovisionedMeshNode, withErrorCode anErrorCode: ProvisioningErrorCodes) {
        stepCompleted(withIndicatorState: false)
        logEventWithMessage("provisioning failed, error: \(anErrorCode)")
        isProvisioning = false
        navigationItem.hidesBackButton = false
    }
}

extension MeshProvisioningDataTableViewController: ProvisionedMeshNodeDelegate {

    func configurationSucceeded() {
        stepCompleted(withIndicatorState: false)
        logEventWithMessage("configuration completed!")
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .seconds(1)) {
            self.meshManager.updateProxyNode(self.targetProvisionedNode)
            self.navigationController?.popToRootViewController(animated: true)
        }
    }

    func nodeDidCompleteDiscovery(_ aNode: ProvisionedMeshNode) {
        if aNode == targetProvisionedNode {
            stepCompleted(withIndicatorState: false)
            targetProvisionedNode.configure(destinationAddress: destinationAddress,
                                            appKeyIndex: appKeyIndex,
                                            appKeyData: appKeyData,
                                            andNetKeyIndex: netKeyIndex)
        }
    }
    
    func nodeShouldDisconnect(_ aNode: ProvisionedMeshNode) {
        if aNode == targetProvisionedNode {
            centralManager.cancelPeripheralConnection(aNode.blePeripheral())
        }
    }
    
    func receivedCompositionData(_ compositionData: CompositionStatusMessage) {
        guard targetProvisionedNode != nil else {
            logEventWithMessage("received composition data from unknown node, ignoring")
            return
        }
        stepCompleted(withIndicatorState: false)
        let state = stateManager.state()
        if let anIndex = state.provisionedNodes.index(where: { $0.nodeUnicast == self.nodeAddress}) {
            let aNodeEntry = state.provisionedNodes[anIndex]
            state.provisionedNodes.remove(at: anIndex)
            aNodeEntry.companyIdentifier = compositionData.companyIdentifier
            aNodeEntry.productVersion = compositionData.productVersion
            aNodeEntry.productIdentifier = compositionData.productIdentifier
            aNodeEntry.featureFlags = compositionData.features
            aNodeEntry.replayProtectionCount = compositionData.replayProtectionCount
            aNodeEntry.elements = compositionData.elements
            state.provisionedNodes.append(aNodeEntry)
            logEventWithMessage("received composition data")
            logEventWithMessage("company identifier:\(compositionData.companyIdentifier.hexString())")
            logEventWithMessage("product identifier:\(compositionData.productIdentifier.hexString())")
            logEventWithMessage("product version:\(compositionData.productVersion.hexString())")
            logEventWithMessage("feature flags:\(compositionData.features.hexString())")
            logEventWithMessage("element count:\(compositionData.elements.count)")
            for anElement in aNodeEntry.elements! {
                logEventWithMessage("Element models:\(anElement.totalModelCount())")
            }
            //Set unicast to current set value, to allow the user to force override addresses
            state.nextUnicast = self.nodeAddress
            //Increment next available address
            state.incrementUnicastBy(compositionData.elements.count)
            logEventWithMessage("next unicast address available: \(state.nextUnicast.hexString())")
            stateManager.saveState()
        } else {
            logEventWithMessage("Received composition data but node isn't stored, please provision again")
        }
    }
    
    func receivedAppKeyStatusData(_ appKeyStatusData: AppKeyStatusMessage) {
        stepCompleted(withIndicatorState: false)
        logEventWithMessage("received app key status messasge")
        if appKeyStatusData.statusCode == .success {
            logEventWithMessage("status code: Success")
            logEventWithMessage("appkey index: \(appKeyStatusData.appKeyIndex.hexString())")
            logEventWithMessage("netKey index: \(appKeyStatusData.netKeyIndex.hexString())")
            
            // Update state with configured key
            let state = stateManager.state()
            if let anIndex = state.provisionedNodes.index(where: { $0.nodeUnicast == self.nodeAddress}) {
                let aNodeEntry = state.provisionedNodes[anIndex]
                state.provisionedNodes.remove(at: anIndex)
                if aNodeEntry.appKeys.contains(appKeyStatusData.appKeyIndex) == false {
                    aNodeEntry.appKeys.append(appKeyStatusData.appKeyIndex)
                }
                //and update
                state.provisionedNodes.append(aNodeEntry)
                stateManager.saveState()
                for aKey in aNodeEntry.appKeys {
                    logEventWithMessage("appKeyData:\(aKey.hexString())")
                }
            }
        } else {
            logEventWithMessage("received error code: \(appKeyStatusData.statusCode)")
            activityIndicator.stopAnimating()
        }
    }
    
    func receivedModelAppBindStatus(_ modelAppStatusData: ModelAppBindStatusMessage) {
        //NOOP
    }
    
    func receivedModelPublicationStatus(_ modelPublicationStatusData: ModelPublicationStatusMessage) {
        //NOOP
    }
    
    func receivedModelSubsrciptionStatus(_ modelSubscriptionStatusData: ModelSubscriptionStatusMessage) {
        //NOOP
    }
    
    func receivedDefaultTTLStatus(_ defaultTTLStatusData: DefaultTTLStatusMessage) {
        //NOOP
    }
    
    func receivedNodeResetStatus(_ resetStatusData: NodeResetStatusMessage) {
        //NOOP
    }
}

extension MeshProvisioningDataTableViewController: ProvisionedMeshNodeLoggingDelegate {

}

extension MeshProvisioningDataTableViewController: UnprovisionedMeshNodeLoggingDelegate {
    func logDisconnect() {
        stepCompleted(withIndicatorState: false)
        logEventWithMessage("disconnected")
    }
    
    func logConnect() {
        stepCompleted(withIndicatorState: true)
        logEventWithMessage("connected")
    }
    
    func logDiscoveryStarted() {
        stepCompleted(withIndicatorState: true)
        logEventWithMessage("started discovery")
    }
    
    func logDiscoveryCompleted() {
        stepCompleted(withIndicatorState: false)
        logEventWithMessage("discovery completed")
    }
    
    func logSwitchedToProvisioningState(withMessage aMessage: String) {
        logEventWithMessage("switched provisioning state: \(aMessage)")
    }
    
    func logUserInputRequired() {
        stepCompleted(withIndicatorState: true)
        logEventWithMessage("user input required")
    }
    
    func logUserInputCompleted(withMessage aMessage: String) {
        stepCompleted(withIndicatorState: false)
        logEventWithMessage("input complete: \(aMessage)")
    }
    
    func logGenerateKeypair(withMessage aMessage: String) {
        stepCompleted(withIndicatorState: false)
        logEventWithMessage("keypare generated, pubkey: \(aMessage)")
    }
    
    func logCalculatedECDH(withMessage aMessage: String) {
        stepCompleted(withIndicatorState: false)
        logEventWithMessage("calculated DHKey: \(aMessage)")
    }
    
    func logGeneratedProvisionerRandom(withMessage aMessage: String) {
        stepCompleted(withIndicatorState: false)
        logEventWithMessage("provisioner random: \(aMessage)")
    }
    
    func logReceivedDeviceRandom(withMessage aMessage: String) {
        stepCompleted(withIndicatorState: false)
        logEventWithMessage("device random: \(aMessage)")
    }
    
    func logGeneratedProvisionerConfirmationValue(withMessage aMessage: String) {
        stepCompleted(withIndicatorState: false)
        logEventWithMessage("provisioner confirmation: \(aMessage)")
    }
    
    func logReceivedDeviceConfirmationValue(withMessage aMessage: String) {
        stepCompleted(withIndicatorState: false)
        logEventWithMessage("device confirmation: \(aMessage)")
    }
    
    func logGenratedProvisionInviteData(withMessage aMessage: String) {
        stepCompleted(withIndicatorState: true)
        logEventWithMessage("provision invite data: \(aMessage)")
    }
    
    func logGeneratedProvisioningStartData(withMessage aMessage: String) {
        stepCompleted(withIndicatorState: false)
        logEventWithMessage("provision start data: \(aMessage)")
    }
    
    func logReceivedCapabilitiesData(withMessage aMessage: String) {
        stepCompleted(withIndicatorState: false)
        logEventWithMessage("capabilities : \(aMessage)")
    }
    
    func logReceivedDevicePublicKey(withMessage aMessage: String) {
        stepCompleted(withIndicatorState: false)
        logEventWithMessage("device public key: \(aMessage)")
    }
    
    func logProvisioningSucceeded() {
        stepCompleted(withIndicatorState: true)
        logEventWithMessage("provisioning succeeded")
    }
    
    func logProvisioningFailed(withMessage aMessage: String) {
        stepCompleted(withIndicatorState: false)
        isProvisioning = false
        navigationItem.hidesBackButton = false
        logEventWithMessage("provisioning failed: \(aMessage)")
    }
}
