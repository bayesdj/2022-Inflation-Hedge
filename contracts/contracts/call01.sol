// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";

interface node_ea {
    // function requestUint() external;
    function getUint() external view returns(uint256);
}

contract MyContract is AccessControl {
    address public underlying_add;
    uint public payout_amount; 
    uint public multiplier;

    struct option {
        uint strike; //Price in USD (18 decimal places) option allows buyer to purchase tokens at
        uint premium; //Fee in contract token that option writer charges
        bool canceled; //Has option been canceled
        uint id; //Unique ID of option, also array index
        address payable seller; //Issuer of option
        address payable buyer; //Buyer of option
        bool transacted;
    }

    option[] public bids;
    option[] public asks;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        underlying_add = 0xc1aE74454fC26c087642aA68a751b8bd51dD5eea;
        multiplier = 1000;
        payout_amount = 100*multiplier;
    }

    function getTarget() public view returns (uint256){
        return node_ea(underlying_add).getUint();
    }

    function placeBid(uint _strike, uint _premium) public payable {
        uint premium_amount = _premium*multiplier;
        require(msg.value == premium_amount, "not enough premium");
        option memory call = option({premium: premium_amount, strike: _strike, canceled:false, 
                                id:bids.length, seller:address(0), buyer:msg.sender,
                                transacted: false});
        bids.push(call);
    }

    function placeAsk(uint _strike, uint _premium) public payable {
        uint premium_amount = _premium*multiplier;
        require(msg.value == payout_amount-premium_amount, "not enough margin");
        option memory call = option({premium: premium_amount, strike: _strike, canceled:false, 
                                id:bids.length, seller:msg.sender, buyer:address(0), 
                                transacted: false});
        asks.push(call);
    }

    function buyAsk(uint id) public payable {
        require(!asks[id].canceled, "Option is canceled");
        require(msg.value == asks[id].premium, "not enough margin");
        asks[id].buyer = msg.sender;
        asks[id].transacted = true;
    }

    function sellBid(uint id) public payable {
        require(!bids[id].canceled, "Option is canceled");
        require(msg.value == payout_amount-asks[id].premium, "not enough margin");
        bids[id].seller = msg.sender;
        bids[id].transacted = true;
    }
}