// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "solidity-trigonometry/Trigonometry.sol";

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract Moons {

    uint256 constant PHASE_OFFSET_SCALED = 3_141592653589793238;

    event AdminAdded(address indexed admin, address indexed addedBy, uint256 rank, string memo);
    event AdminRemoved(address indexed admin, address indexed addedBy, uint256 rank, string memo);
    event FundsAdded(address indexed token, address indexed participant, uint256 amount, string memo);
    event FundsDisbursed(address indexed token, address indexed participant, uint256 amount, string memo);
    event ParticipantAdded(address indexed token, address indexed participant, address indexed addedBy, uint256 rank, string memo);
    event ParticipantRemoved(address indexed token, address indexed participant, address indexed addedBy, uint256 rank, string memo);

    uint256 public startTime;
    uint256 public cycleTime;

    address[] admins;
    mapping(address => uint) adminIndex;
    mapping(address => uint) adminRank;
    uint adminCount;

    mapping(address => address[]) tokenParticipants;
    mapping(address => mapping(address => uint)) tokenParticipantIndex;
    mapping(address => mapping(address => uint)) tokenParticipantRank;
    mapping(address => uint) tokenParticipantCount;

    mapping(address => mapping(address => uint256)) lastAddCycle;
    mapping(address => mapping(address => uint256)) lastDisburseCycle;

    function getCycle() public view returns (uint256, uint256) {
        return (startTime, cycleTime);
    }

    function getCurrentCycle() public view returns (uint256) {
        return (block.timestamp - startTime) / cycleTime;
    }

    function getCycleMultiplier(address token) public view returns (int256) {
        uint256 elapsedTime = block.timestamp - startTime;
        uint256 currentParticipantCount = tokenParticipantCount[token];
        uint256 participantRank = tokenParticipantRank[token][msg.sender];
        if (currentParticipantCount == 0 || participantRank == 0) {
            return 0;
        }

        uint256 offsetRadiansScaled = ((participantRank - 1) * 2 * 3_141592653589793238) / currentParticipantCount;
        uint256 elapsedTimeRadiansScaled = (elapsedTime * 2 * 3_141592653589793238) / cycleTime;
        return Trigonometry.cos(elapsedTimeRadiansScaled + offsetRadiansScaled + PHASE_OFFSET_SCALED);
    }

    function getAdminCount() public view returns (uint) {
        return adminCount;
    }

    function getTokenParticipantCount(address token) public view returns (uint) {
        return tokenParticipantCount[token];
    }

    modifier requireAdmin() {
        require(adminRank[msg.sender] > 0, "Sender must be admin");
        _;
    }

    modifier requireAdminSeniority(address addr) {
        require(adminRank[msg.sender] > 0 && adminRank[addr] > 0 && adminRank[msg.sender] < adminRank[addr],
        "Must have admin seniority");
        _;
    }

    modifier requireParticipant(address token) {
        require(tokenParticipantRank[token][msg.sender] != 0, "Sender must be a token participant");
        _;
    }

    modifier addOncePerCycle(address token) {
        uint256 currentCycle = getCurrentCycle();
        require(lastAddCycle[token][msg.sender] < currentCycle, "Can only add funds once per cycle");
        lastAddCycle[token][msg.sender] = currentCycle;
        _;
    }

    modifier disburseOncePerCycle(address token) {
        uint256 currentCycle = getCurrentCycle();
        require(lastDisburseCycle[token][msg.sender] < currentCycle, "Can only disburse funds once per cycle");
        lastDisburseCycle[token][msg.sender] = currentCycle;
        _;
    }

    function getAdmins() public view returns (address[] memory, uint256[] memory) {
        uint j = 0;
        address[] memory addresses = new address[](adminCount);
        uint256[] memory ranks = new uint256[](adminCount);
        for (uint i = 0; i < admins.length; i++) {
            address addr = admins[i];
            uint activeIndex = adminIndex[addr];
            if (activeIndex != 0 && (activeIndex - 1) == i) {
                addresses[j] = addr;
                ranks[j] = adminRank[addr];
                j++;
            }
        }
        return (addresses, ranks);
    }

    function getTokenParticipants(address token) public view returns (address[] memory, uint256[] memory) {
        uint j = 0;
        uint256 participantCount = tokenParticipantCount[token];
        address[] memory addresses = new address[](participantCount);
        uint256[] memory ranks = new uint256[](participantCount);
        for (uint i = 0; i < tokenParticipants[token].length; i++) {
            address addr = tokenParticipants[token][i];
            uint activeIndex = tokenParticipantIndex[token][addr];
            if (activeIndex != 0 && (activeIndex - 1) == i) {
                addresses[j] = addr;
                ranks[j] = tokenParticipantRank[token][addr];
                j++;
            }
        }
        return (addresses, ranks);
    }

    constructor(uint256 _cycleTime) {
        cycleTime = _cycleTime;
        startTime = block.timestamp;
        adminIndex[msg.sender] = 1;
        adminRank[msg.sender] = 1;
        admins.push(msg.sender);
        adminCount = 1;
    }

    function addAdmin(address admin, string calldata memo) external requireAdmin {
        require(adminRank[admin] == 0, "Must not already be an admin");
        uint256 index = admins.length + 1;
        uint256 rank = adminCount + 1;
        adminIndex[admin] = index;
        adminRank[admin] = rank;
        admins.push(admin);
        adminCount++;
        emit AdminAdded(admin, msg.sender, rank, memo);
    }

    function removeAdmin(address admin, string calldata memo) external requireAdminSeniority(admin) {
        uint removedRank = adminRank[admin];
        for (uint i = 0; i < admins.length; i++) {
            address addr = admins[i];
            uint activeIndex = adminIndex[addr];
            uint checkRank = adminRank[addr];
            if (activeIndex != 0 && (activeIndex - 1) == i && checkRank > removedRank) {
                adminRank[addr] = checkRank - 1;
            }
        }
        adminIndex[admin] = 0;
        adminRank[admin] = 0;
        adminCount--;
        emit AdminRemoved(admin, msg.sender, removedRank, memo);
    }

    function addParticipant(address token, address participant, string calldata memo) external requireAdmin {
        require(tokenParticipantRank[token][participant] == 0, "Must not already be a token participant");
        uint256 index = tokenParticipants[token].length + 1;
        uint256 rank = tokenParticipantCount[token] + 1;
        tokenParticipantIndex[token][participant] = index;
        tokenParticipantRank[token][participant] = rank;
        tokenParticipants[token].push(participant);
        tokenParticipantCount[token]++;
        emit ParticipantAdded(token, participant, msg.sender, rank, memo);
    }

    function removeParticipant(address token, address participant, string calldata memo) external requireAdmin {
        uint256 removedRank = tokenParticipantRank[token][participant];
        require(removedRank > 0, "Must already be a token participant");
        for (uint i = 0; i < tokenParticipants[token].length; i++) {
            address addr = tokenParticipants[token][i];
            uint activeIndex = tokenParticipantIndex[token][addr];
            uint checkRank = tokenParticipantRank[token][addr];
            if (activeIndex != 0 && (activeIndex - 1) == i && checkRank > removedRank) {
                tokenParticipantRank[token][addr] = checkRank - 1;
            }
        }
        tokenParticipantIndex[token][participant] = 0;
        tokenParticipantRank[token][participant] = 0;
        tokenParticipantCount[token]--;
        emit ParticipantRemoved(token, participant, msg.sender, removedRank, memo);
    }

    function addFunds(address token, uint256 amount, string calldata memo) external requireParticipant(token) addOncePerCycle(token) {
        int256 cycleMultiplier = getCycleMultiplier(token) * int256(-1);
        require(cycleMultiplier > 0, "May not add funds at this time");
        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 maxAllowedAmount = balance == 0 ? ~uint256(0) : (uint256(cycleMultiplier) * balance * 2) / 1E18;
        require(amount < maxAllowedAmount, "Amount exceeds max allowed");
        require(IERC20(token).transferFrom(msg.sender, address(this), amount), "Transfer failed");
        emit FundsAdded(token, msg.sender, amount, memo);
    }

    function disburseFunds(address token, uint256 amount, string calldata memo) external requireParticipant(token) disburseOncePerCycle(token) {
        int256 cycleMultiplier = getCycleMultiplier(token);
        require(cycleMultiplier > 0, "May not disburse funds at this time");
        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 maxAllowedAmount = (uint256(cycleMultiplier) * balance) / (1E18 * 2);
        require(amount < maxAllowedAmount, "Amount exceeds max allowed");
        require(IERC20(token).transfer(msg.sender, amount), "Transfer failed");
        emit FundsDisbursed(token, msg.sender, amount, memo);
    }
}
