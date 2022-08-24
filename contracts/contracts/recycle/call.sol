// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// interface node_ea {
//     // function requestUint() external;
//     function getUint() external view returns(uint256);
// }

contract optionExchange is Pausable, Ownable {
    address public underlying_add;
    uint public payout_amount; 
    uint public multiplier;
    uint public fee;
    uint public expire_time; 
    bool public settled;

    struct option {
        uint strike; //Price in USD (18 decimal places) option allows buyer to purchase tokens at
        uint premium; //Fee in contract token that option writer charges
        bool canceled; //Has option been canceled
        uint id; //Unique ID of option, also array index
        address seller; //Issuer of option
        address buyer; //Buyer of option
        bool transacted;
    }

    option[] public bids;
    option[] public asks;
    mapping(address => uint256) public winners;

    constructor() {
        underlying_add = 0xc1aE74454fC26c087642aA68a751b8bd51dD5eea;
        multiplier = 1e15; // one finney
        payout_amount = 1000*multiplier;
        fee = 1*multiplier;
        expire_time = 1663088400; // Sep 13 2022, 10:00 am
        settled = false;
    }

    // function getTarget() public view returns (uint256){
    //     return node_ea(underlying_add).getUint();
    // }

    function placeBid(uint _strike, uint _premium) public payable {
        uint premium_amount = _premium*multiplier;
        require(premium_amount>0 && premium_amount<payout_amount, "invalid premium amount");
        require(msg.value == premium_amount, "not enough premium");
        option memory call = option({premium: premium_amount, strike: _strike*multiplier, canceled:false, 
                                id:bids.length, seller:address(0), buyer:msg.sender,
                                transacted: false});
        bids.push(call);
    }

    function placeAsk(uint _strike, uint _premium) public payable {
        uint premium_amount = _premium*multiplier;
        require(premium_amount>0 && premium_amount<payout_amount, "invalid premium amount");
        require(msg.value == payout_amount-premium_amount, "not enough margin");
        option memory call = option({premium: premium_amount, strike: _strike*multiplier, canceled:false, 
                                id:asks.length, seller:msg.sender, buyer:address(0), 
                                transacted: false});
        asks.push(call);
    }

    function buy(uint id) public payable {
        require(!asks[id].canceled, "Option is canceled");
        require(!asks[id].transacted, "Option already taken");
        require(msg.value == asks[id].premium, "incorrect margin");
        asks[id].buyer = msg.sender;
        asks[id].transacted = true;
    }

    function sell(uint id) public payable {
        require(!bids[id].canceled, "Option is canceled");
        require(!bids[id].transacted, "Option already taken");
        require(msg.value == payout_amount - bids[id].premium, "incorrect margin");
        bids[id].seller = msg.sender;
        bids[id].transacted = true;
    }

    function cancelBid(uint id) public payable {
        option storage x = bids[id];
        require(x.buyer == msg.sender, "only the buyer can cancel this bid");
        require(!x.canceled, "option already canceled");
        require(!x.transacted, "already transacted");
        payable(x.buyer).transfer(x.premium);
        x.canceled = true;
    }

    function cancelAsk(uint id) public payable {
        option storage x = asks[id];
        require(x.seller == msg.sender, "only the seller can cancel this ask");
        require(!x.canceled, "option already canceled");
        require(!x.transacted, "already transacted");
        payable(x.seller).transfer(payout_amount - x.premium);
        x.canceled = true;
    }

    function expire(uint _ePrice) public onlyOwner {
        // uint256 ePrice = _ePrice * multiplier;
        require(block.timestamp > expire_time, "expire time not reached yet");
        uint256 ePrice = _ePrice * multiplier;
        for (uint i=0; i<bids.length; i++) {
            if (bids[i].transacted){
                option storage x = bids[i];
                address payee = (ePrice > x.strike)? x.buyer : x.seller;
                winners[payee] += (payout_amount - fee);
            }
        }
        for (uint i=0; i<asks.length; i++) {
            if (asks[i].transacted){
                option storage x = asks[i];
                address payee = (ePrice > x.strike)? x.buyer : x.seller;
                winners[payee] += (payout_amount - fee);
            }
        }
        settled = true;
    }

    function gettime() public view returns (uint256) {
        return block.timestamp; 
    }

    function setExpireTime(uint _expire_time) external onlyOwner {
        expire_time = _expire_time; 
    }

    function withdraw() public payable {
        require(settled, "not settled yet");
        uint256 amount = winners[msg.sender];
        require(amount > 0, "no money owed");
        winners[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
    }

    function getContractBal() external view returns (uint256) {
        return address(this).balance;
    }


    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}