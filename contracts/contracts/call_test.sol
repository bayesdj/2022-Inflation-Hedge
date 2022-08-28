// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";

///@title this is the contract where the underlying resides. 
interface node_ea {
    function requestUint() external;
    function getUint() external view returns(uint256);
}

/** @title binary call option exchange. Users can place bids and asks, take the bids
or asks, cancel them. At expiration, the binary option will pay buyer the payout_amount 
(minus a fee) if underlying > strike, otherwise the payout_amount (minus a fee) goes to 
the seller. Chainlink Keeper will automatically pull updated data from the 
external adapter after expiration. If data is not updated upon expiration, Keeper will 
will request the data every 4 hours. Once data is updated, the expiration function will 
be called by Keeper. 
*/
contract optionExchange is Pausable, Ownable, KeeperCompatibleInterface {
    address public underlying_add; /// the contract address that extracts the option underlying. 
    uint public payout_amount; 
    uint public multiplier; 
    uint public fee; /// rewards for exchange owner, only charged when transaction occurs.
    uint public expire_time; 
    uint public underlying; 
    uint public keeper_interval;
    uint public keeper_timestamp;
    uint public keeper_counter;
    bool public settled; /// once settled, users can withdraw their tokens. 

    struct option {
        uint strike; // the underlying will compare with strike at expiration
        uint premium; //Fee that option writer charges
        bool canceled; //Has option been canceled
        uint id; //Unique ID of option, also array index
        address seller; //Issuer of option
        address buyer; //Buyer of option
        bool transacted; // is the option transacted
    }

    ///@notice arrays to hold bids and asks. 
    option[] public bids; 
    option[] public asks; 
    
    ///@notice account balances after settlement. 
    mapping(address => uint256) public winners;

    constructor() {
        underlying_add = 0x1D2CcD6157f50EFd35894Af2a1aeFcacA48c5252;
        multiplier = 1e15; /// one finney
        payout_amount = 1000*multiplier; /// one ether
        fee = 1*multiplier;
        expire_time = 1663088400; /// unix time Sep 13 2022, 10:00 am
        settled = false;
        underlying = getTarget();
        keeper_interval = 3600*4; /// 4 hours;
        keeper_timestamp = block.timestamp;
        keeper_counter = 0;
    }

    function max(uint256 a, uint256 b) public pure returns (uint256) {
        return a >= b ? a : b;
    }

    /// conditions that must be met for Chainlink Keeper
    function checkUpkeep(bytes calldata /*calldata*/) external view override returns (bool upkeepNeeded, bytes memory performData) {
        uint next_keeper_time = max(expire_time, keeper_timestamp + keeper_interval);
        if(block.timestamp <= next_keeper_time || settled) {
            return (false, bytes(""));
        }
        return (true, bytes(""));
    }
    
    /** A may not be updated at the exact expiration time. Keeper can automatically 
    update the EA after expiration, and once updated, let the call contracts expire. 
     */ 
    function performUpkeep(bytes calldata /*performData*/) external override {
        /// revalidating the upkeep in the performUpkeep function
        uint next_keeper_time = max(expire_time, keeper_timestamp + keeper_interval);
        require(block.timestamp > next_keeper_time && !settled);
        keeper_timestamp = block.timestamp;
        keeper_counter += 1;

        uint ePrice = getTarget();
        if (ePrice == underlying) {
            node_ea(underlying_add).requestUint();
            underlying = 700*multiplier; /// @dev for testing
        }
        else {
            ePrice = 700*multiplier; /// @dev for testing
            underlying = ePrice;
            expire_keeper();
        }
    }

    /// get the underlying value from EA. It is at about 648 on 8/24/22
    function getTarget() public view returns (uint256){
        return node_ea(underlying_add).getUint()*10;
    }

    ///@param _strike strike price in finney. 
    ///@param _premium price of option in finney.
    function placeBid(uint _strike, uint _premium) public payable {
        require(!settled, "call contract already settled");
        uint premium_amount = _premium*multiplier;
        require(premium_amount>0 && premium_amount<payout_amount, "invalid premium amount");
        require(msg.value == premium_amount, "not enough premium");
        option memory call = option({premium: premium_amount, strike: _strike*multiplier, canceled:false, 
                                id:bids.length, seller:address(0), buyer:msg.sender,
                                transacted: false});
        bids.push(call);
    }

    function placeAsk(uint _strike, uint _premium) public payable {
        require(!settled, "call contract already settled");
        uint premium_amount = _premium*multiplier;
        require(premium_amount>0 && premium_amount<payout_amount, "invalid premium amount");
        require(msg.value == payout_amount-premium_amount, "not enough margin");
        option memory call = option({premium: premium_amount, strike: _strike*multiplier, canceled:false, 
                                id:asks.length, seller:msg.sender, buyer:address(0), 
                                transacted: false});
        asks.push(call);
    }

    ///@param id index in asks array
    function buy(uint id) public payable {
        require(!settled, "call contract already settled");
        require(!asks[id].canceled, "Option is canceled");
        require(!asks[id].transacted, "Option already taken");
        require(msg.value == asks[id].premium, "incorrect margin");
        asks[id].buyer = msg.sender;
        asks[id].transacted = true;
    }

    ///@param id index in bids array
    function sell(uint id) public payable {
        require(!settled, "call contract already settled");
        require(!bids[id].canceled, "Option is canceled");
        require(!bids[id].transacted, "Option already taken");
        require(msg.value == payout_amount - bids[id].premium, "incorrect margin");
        bids[id].seller = msg.sender;
        bids[id].transacted = true;
    }

    ///@param id index in bids array
    function cancelBid(uint id) public payable {
        option storage x = bids[id];
        require(x.buyer == msg.sender, "only the buyer can cancel this bid");
        require(!x.canceled, "option already canceled");
        require(!x.transacted, "already transacted");
        payable(x.buyer).transfer(x.premium);
        x.canceled = true;
    }

    ///@param id index in asks array
    function cancelAsk(uint id) public payable {
        option storage x = asks[id];
        require(x.seller == msg.sender, "only the seller can cancel this ask");
        require(!x.canceled, "option already canceled");
        require(!x.transacted, "already transacted");
        payable(x.seller).transfer(payout_amount - x.premium);
        x.canceled = true;
    }

    /** After expiration time, the underlying from the API should be updated. However, 
    the API provider may or may not update at the exact time. Thefore, the owner 
    should call this function once the API is updated. Another solution is to use 
    Chainlink Keeper to call this function. 
    Upon expiration, if underlying is greater than strike, option buyers win the payout-
    amount. If underlying is less than strike, option sellers win the payout-amount. 
    If untransacted bids or asks are still not canceled, deposit will be available 
    for withdraw. 
    */ 
    function expire_keeper() private {
        require(block.timestamp > expire_time, "expire time not reached yet");
        // uint256 ePrice = _ePrice * multiplier;
        uint256 ePrice = underlying;
        for (uint i=0; i<bids.length; i++) {
            if (bids[i].transacted){
                option storage x = bids[i];
                address payee = (ePrice > x.strike)? x.buyer : x.seller;
                winners[payee] += (payout_amount - fee);
            }
            else if (!bids[i].canceled){
                option storage x = bids[i];
                winners[x.buyer] += x.premium;
            }
        }
        for (uint i=0; i<asks.length; i++) {
            if (asks[i].transacted){
                option storage x = asks[i];
                address payee = (ePrice > x.strike)? x.buyer : x.seller;
                winners[payee] += (payout_amount - fee);
            }
            else if (!asks[i].canceled){
                option storage x = asks[i];
                winners[x.seller] += payout_amount - x.premium;
            }
        }
        settled = true;
    }

    /// A backup function that allows contract owner to expire the contract. 
    function expire_manual() external onlyOwner {
        require(block.timestamp > expire_time, "expire time not reached yet");
        // uint256 ePrice = _ePrice * multiplier;
        uint256 ePrice = underlying;
        for (uint i=0; i<bids.length; i++) {
            if (bids[i].transacted){
                option storage x = bids[i];
                address payee = (ePrice > x.strike)? x.buyer : x.seller;
                winners[payee] += (payout_amount - fee);
            }
            else if (!bids[i].canceled){
                option storage x = bids[i];
                winners[x.buyer] += x.premium;
            }
        }
        for (uint i=0; i<asks.length; i++) {
            if (asks[i].transacted){
                option storage x = asks[i];
                address payee = (ePrice > x.strike)? x.buyer : x.seller;
                winners[payee] += (payout_amount - fee);
            }
            else if (!asks[i].canceled){
                option storage x = asks[i];
                winners[x.seller] += payout_amount - x.premium;
            }
        }
        settled = true;
    }

    function gettime() public view returns (uint256) {
        return block.timestamp; 
    }

    ///@dev this is a testing function. Expiration should be immutable. 
    function setExpireTime(uint _expire_time) external onlyOwner {
        expire_time = _expire_time; 
    }

    ///allows the owner to change keeper time interval
    function setKeeperInterval(uint _keeper_interval) external onlyOwner {
        keeper_interval = _keeper_interval; 
    }

    /** allow contract owner to withdraw fees in the contract after other users
    withdraw their balances */
    function ownerWithdraw() external payable onlyOwner{
        require(settled, "not settled yet");
        payable(msg.sender).transfer(address(this).balance);
    }

    /** winners collect their balances or users get back their margins from bids
    and asks */
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
