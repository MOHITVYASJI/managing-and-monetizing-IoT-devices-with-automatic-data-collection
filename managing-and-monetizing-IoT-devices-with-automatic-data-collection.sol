// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IoT Device Management Platform
 * @dev Smart contract for managing IoT devices, data collection, verification, and marketplace
 * @author IoT Management Team
 */
contract Project {
    
    // Events
    event DeviceRegistered(uint256 indexed deviceId, address indexed owner, string deviceType);
    event DataSubmitted(uint256 indexed deviceId, bytes32 indexed dataHash, uint256 timestamp);
    event DataVerified(uint256 indexed deviceId, bytes32 indexed dataHash, address indexed verifier);
    event DeviceListed(uint256 indexed deviceId, uint256 price);
    event DeviceSold(uint256 indexed deviceId, address indexed buyer, uint256 price);
    event RewardDistributed(address indexed recipient, uint256 amount);

    // Structs
    struct Device {
        uint256 id;
        address owner;
        string deviceType;
        string location;
        bool isActive;
        uint256 dataCount;
        uint256 reputationScore;
        uint256 lastDataSubmission;
        uint256 price; // For marketplace (0 means not for sale)
        bool isForSale;
    }

    struct DataEntry {
        bytes32 dataHash;
        uint256 deviceId;
        uint256 timestamp;
        bool isVerified;
        address verifier;
        string dataType;
    }

    // State variables
    mapping(uint256 => Device) public devices;
    mapping(bytes32 => DataEntry) public dataEntries;
    mapping(address => uint256[]) public ownerDevices;
    mapping(uint256 => bytes32[]) public deviceData;
    
    uint256 public nextDeviceId = 1;
    uint256 public constant VERIFICATION_REWARD = 0.001 ether;
    uint256 public constant DATA_SUBMISSION_REWARD = 0.0005 ether;
    uint256 public constant MARKETPLACE_FEE = 250; // 2.5%
    
    address public platformOwner;
    uint256 public totalRewardsDistributed;

    modifier onlyDeviceOwner(uint256 _deviceId) {
        require(devices[_deviceId].owner == msg.sender, "Not device owner");
        _;
    }

    modifier onlyPlatformOwner() {
        require(msg.sender == platformOwner, "Not platform owner");
        _;
    }

    modifier deviceExists(uint256 _deviceId) {
        require(devices[_deviceId].id != 0, "Device does not exist");
        _;
    }

    constructor() {
        platformOwner = msg.sender;
    }

    /**
     * @dev Core Function 1: Register IoT Device
     * @param _deviceType Type of IoT device (sensor, camera, etc.)
     * @param _location Physical location of the device
     */
    function registerDevice(
        string memory _deviceType,
        string memory _location
    ) external returns (uint256) {
        uint256 deviceId = nextDeviceId++;
        
        devices[deviceId] = Device({
            id: deviceId,
            owner: msg.sender,
            deviceType: _deviceType,
            location: _location,
            isActive: true,
            dataCount: 0,
            reputationScore: 100, // Starting reputation
            lastDataSubmission: 0,
            price: 0,
            isForSale: false
        });

        ownerDevices[msg.sender].push(deviceId);
        
        emit DeviceRegistered(deviceId, msg.sender, _deviceType);
        return deviceId;
    }

    /**
     * @dev Core Function 2: Submit and Verify IoT Data
     * @param _deviceId ID of the device submitting data
     * @param _dataHash Hash of the data being submitted
     * @param _dataType Type of data (temperature, humidity, etc.)
     */
    function submitData(
        uint256 _deviceId,
        bytes32 _dataHash,
        string memory _dataType
    ) external onlyDeviceOwner(_deviceId) deviceExists(_deviceId) {
        require(devices[_deviceId].isActive, "Device is not active");
        require(_dataHash != bytes32(0), "Invalid data hash");

        // Create data entry
        dataEntries[_dataHash] = DataEntry({
            dataHash: _dataHash,
            deviceId: _deviceId,
            timestamp: block.timestamp,
            isVerified: false,
            verifier: address(0),
            dataType: _dataType
        });

        // Update device stats
        devices[_deviceId].dataCount++;
        devices[_deviceId].lastDataSubmission = block.timestamp;
        deviceData[_deviceId].push(_dataHash);

        // Reward data submission
        _distributeReward(msg.sender, DATA_SUBMISSION_REWARD);

        emit DataSubmitted(_deviceId, _dataHash, block.timestamp);
    }

    /**
     * @dev Verify submitted data (can be called by any address for decentralized verification)
     * @param _dataHash Hash of the data to verify
     */
    function verifyData(bytes32 _dataHash) external {
        require(dataEntries[_dataHash].dataHash != bytes32(0), "Data entry does not exist");
        require(!dataEntries[_dataHash].isVerified, "Data already verified");
        require(msg.sender != devices[dataEntries[_dataHash].deviceId].owner, "Cannot verify own device data");

        dataEntries[_dataHash].isVerified = true;
        dataEntries[_dataHash].verifier = msg.sender;

        // Increase device reputation
        uint256 deviceId = dataEntries[_dataHash].deviceId;
        devices[deviceId].reputationScore += 10;

        // Reward verifier
        _distributeReward(msg.sender, VERIFICATION_REWARD);

        emit DataVerified(deviceId, _dataHash, msg.sender);
    }

    /**
     * @dev Core Function 3: Marketplace Operations
     * @param _deviceId ID of the device to list for sale
     * @param _price Price in wei for the device
     */
    function listDeviceForSale(
        uint256 _deviceId,
        uint256 _price
    ) external onlyDeviceOwner(_deviceId) deviceExists(_deviceId) {
        require(_price > 0, "Price must be greater than 0");
        require(!devices[_deviceId].isForSale, "Device already listed");

        devices[_deviceId].price = _price;
        devices[_deviceId].isForSale = true;

        emit DeviceListed(_deviceId, _price);
    }

    /**
     * @dev Purchase a device from the marketplace
     * @param _deviceId ID of the device to purchase
     */
    function purchaseDevice(uint256 _deviceId) external payable deviceExists(_deviceId) {
        Device storage device = devices[_deviceId];
        require(device.isForSale, "Device not for sale");
        require(msg.value >= device.price, "Insufficient payment");
        require(msg.sender != device.owner, "Cannot buy own device");

        address previousOwner = device.owner;
        uint256 salePrice = device.price;

        // Calculate marketplace fee
        uint256 fee = (salePrice * MARKETPLACE_FEE) / 10000;
        uint256 sellerAmount = salePrice - fee;

        // Transfer ownership
        device.owner = msg.sender;
        device.isForSale = false;
        device.price = 0;

        // Update owner mappings
        _removeDeviceFromOwner(previousOwner, _deviceId);
        ownerDevices[msg.sender].push(_deviceId);

        // Transfer payments
        payable(previousOwner).transfer(sellerAmount);
        payable(platformOwner).transfer(fee);

        // Refund excess payment
        if (msg.value > salePrice) {
            payable(msg.sender).transfer(msg.value - salePrice);
        }

        emit DeviceSold(_deviceId, msg.sender, salePrice);
    }

    // Helper functions
    function _distributeReward(address _recipient, uint256 _amount) private {
        if (address(this).balance >= _amount) {
            payable(_recipient).transfer(_amount);
            totalRewardsDistributed += _amount;
            emit RewardDistributed(_recipient, _amount);
        }
    }

    function _removeDeviceFromOwner(address _owner, uint256 _deviceId) private {
        uint256[] storage userDevices = ownerDevices[_owner];
        for (uint256 i = 0; i < userDevices.length; i++) {
            if (userDevices[i] == _deviceId) {
                userDevices[i] = userDevices[userDevices.length - 1];
                userDevices.pop();
                break;
            }
        }
    }

    // View functions
    function getDevice(uint256 _deviceId) external view returns (Device memory) {
        return devices[_deviceId];
    }

    function getDeviceData(uint256 _deviceId) external view returns (bytes32[] memory) {
        return deviceData[_deviceId];
    }

    function getOwnerDevices(address _owner) external view returns (uint256[] memory) {
        return ownerDevices[_owner];
    }

    function getDataEntry(bytes32 _dataHash) external view returns (DataEntry memory) {
        return dataEntries[_dataHash];
    }

    // Platform management
    function depositRewardFunds() external payable onlyPlatformOwner {
        // Function to deposit funds for rewards
    }

    function withdrawPlatformFunds() external onlyPlatformOwner {
        payable(platformOwner).transfer(address(this).balance);
    }

    function deactivateDevice(uint256 _deviceId) external onlyDeviceOwner(_deviceId) {
        devices[_deviceId].isActive = false;
    }

    function activateDevice(uint256 _deviceId) external onlyDeviceOwner(_deviceId) {
        devices[_deviceId].isActive = true;
    }

    receive() external payable {}
}
