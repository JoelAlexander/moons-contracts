// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import "../lib/solidity-trigonometry/src/Trigonometry.sol";

contract Moons {

    event AdminAdded(address indexed admin, address indexed addedBy, uint256 rank, string memo);
    event AdminRemoved(address indexed admin, address indexed addedBy, uint256 rank, string memo);
    event ParticipantAdded(address indexed participant, address indexed addedBy, uint256 rank, string memo);
    event ParticipantRemoved(address indexed participant, address indexed addedBy, uint256 rank, string memo);
    event FundsDisbursed(address indexed token, address indexed participant, uint256 amount, string memo);
    event ConstitutionChanged(address indexed admin, string constitution);
    event NameChanged(address indexed admin, string name);
    event Knock(address indexed addr, string memo);

    string public name;
    string public constitution;

    uint256 public immutable startTime;
    uint256 public immutable cycleTime;

    mapping(address => uint256) lastDisburseCycle;

    address[] admins;
    uint256 adminCount;
    mapping(address => uint) adminIndex;
    mapping(address => uint) adminRank;

    address[] participants;
    uint256 participantCount;
    mapping(address => uint) participantIndex;
    mapping(address => uint) participantRank;

    constructor(string memory _name, string memory _constitution, uint256 _cycleTime) {
        cycleTime = _cycleTime;
        startTime = block.timestamp;
        name = _name;
        constitution = _constitution;
        adminIndex[msg.sender] = 1;
        adminRank[msg.sender] = 1;
        admins.push(msg.sender);
        adminCount = 1;
    }

    modifier requireAdmin() {
        require(adminRank[msg.sender] > 0, "Sender must be admin");
        _;
    }

    modifier requireAdminSeniority(address addr) {
        require(adminRank[msg.sender] > 0 && adminRank[addr] > 0 && (adminRank[msg.sender] < adminRank[addr]),
        "Must have admin seniority");
        _;
    }

    modifier requireParticipant() {
        require(participantRank[msg.sender] != 0, "Sender must be a participant");
        _;
    }

    modifier requireAdminOrSelf(address participant) {
        require(adminRank[msg.sender] > 0 || msg.sender == participant, "Sender must be an admin or the participant");
        _;
    }

    modifier disburseOncePerCycle() {
        uint256 currentCycle = getCurrentCycle();
        require(lastDisburseCycle[msg.sender] < currentCycle, "Can only disburse funds once per cycle");
        lastDisburseCycle[msg.sender] = currentCycle;
        _;
    }

    modifier disbursementValueIsBelowMaximum(address token, uint256 value) {
        require(value < getMaximumAllowedDisbursement(token), "Value equals or exceeds maximum allowed disbursment");
        _;
    }

    function getCurrentCycle() public view returns (uint256) {
        return 1 + ((block.timestamp - startTime) / cycleTime);
    }

    function getMaximumAllowedDisbursement(address token) public view returns (uint256) {
        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 elapsedTime = block.timestamp - startTime;
        uint256 rank = participantRank[msg.sender];
        if (participantCount == 0 || rank == 0) {
            return 0;
        }

        uint256 cycleTimeOffsetRadiansFixed18 = (elapsedTime * 2 * 3_141592653589793238) / cycleTime;
        uint256 participantOffsetRadiansFixed18 = ((rank - 1) * 2 * 3_141592653589793238) / participantCount;
        int256 sinOfHalfSignedFixed18 = Trigonometry.sin((cycleTimeOffsetRadiansFixed18 + participantOffsetRadiansFixed18) / 2);
        uint256 sinOfHalfFixed18 = sinOfHalfSignedFixed18 > 0 ? uint256(sinOfHalfSignedFixed18) : uint256(-sinOfHalfSignedFixed18);
        uint256 multiplierFixed18 = (sinOfHalfFixed18 ** 2) / 1e18;
        uint256 sqrtParticipantCountFixed6 = sqrt(participantCount * (1e6 ** 2));
        return multiplierFixed18 * balance / (sqrtParticipantCountFixed6 * 1e12);
    }

    function mayDisburse(address addr) public view returns (bool) {
        return lastDisburseCycle[addr] < getCurrentCycle();
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

    function getParticipants() public view returns (address[] memory, uint256[] memory) {
        uint j = 0;
        address[] memory addresses = new address[](participantCount);
        uint256[] memory ranks = new uint256[](participantCount);
        for (uint i = 0; i < participants.length; i++) {
            address addr = participants[i];
            uint activeIndex = participantIndex[addr];
            if (activeIndex != 0 && (activeIndex - 1) == i) {
                addresses[j] = addr;
                ranks[j] = participantRank[addr];
                j++;
            }
        }
        return (addresses, ranks);
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

    function addParticipant(address participant, string calldata memo) external requireAdmin {
        require(participantRank[participant] == 0, "Must not already be a participant");
        uint256 index = participants.length + 1;
        uint256 rank = participantCount + 1;
        participantIndex[participant] = index;
        participantRank[participant] = rank;
        participants.push(participant);
        participantCount++;
        emit ParticipantAdded(participant, msg.sender, rank, memo);
    }

    function removeParticipant(address participant, string calldata memo) external requireAdminOrSelf(participant) {
        uint256 removedRank = participantRank[participant];
        require(removedRank > 0, "Must already be a participant");
        for (uint i = 0; i < participants.length; i++) {
            address addr = participants[i];
            uint activeIndex = participantIndex[addr];
            uint checkRank = participantRank[addr];
            if (activeIndex != 0 && (activeIndex - 1) == i && checkRank > removedRank) {
                participantRank[addr] = checkRank - 1;
            }
        }
        participantIndex[participant] = 0;
        participantRank[participant] = 0;
        participantCount--;
        emit ParticipantRemoved(participant, msg.sender, removedRank, memo);
    }

    function disburseFunds(address token, uint256 value, string calldata memo) external requireParticipant disburseOncePerCycle disbursementValueIsBelowMaximum(token, value) {
        require(IERC20(token).transfer(msg.sender, value), "Transfer failed");
        emit FundsDisbursed(token, msg.sender, value, memo);
    }

    function setName(string calldata _name) external requireAdmin {
        name = _name;
        emit NameChanged(msg.sender, _name);
    }

    function setConstitution(string calldata _constitution) external requireAdmin {
        constitution = _constitution;
        emit ConstitutionChanged(msg.sender, _constitution);
    }

    function knock(string calldata memo) external {
        emit Knock(msg.sender, memo);
    }

    function sqrt(uint256 x) public pure returns (uint256) {
        if (x == 0) return 0;
        if (x <= 3) return 1;
        
        uint256 z = x / 2;
        uint256 y = x;

        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }

        return y;
    }
}
