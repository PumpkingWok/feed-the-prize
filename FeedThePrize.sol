// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./SafeMath.sol";
import "./Ownable.sol";

abstract contract IdleDAIV3 {
    function mintIdleToken(uint256 _amount, bool _skipWholeRebalance) virtual public returns(uint256);
    function reedemIdleToken(uint256 _amount, bool _skipRebalance, uint256[] calldata _clientProtocolAmounts) virtual external returns(uint256);
    function balanceOf(address account) virtual public returns(uint256);
    function tokenPrice() virtual public returns(uint256);
    function tokenDecimals() virtual public returns(uint256);
}

abstract contract PoolTogetherDAI {
   function depositSponsorship(uint256 _amount) virtual public;
   function withdrawSponsorshipAndFee(uint256 _amount) virtual public;
   function balanceOf(address _addr) virtual public returns(uint256);
}

/**
 * @title FeedThePrize
 * @dev Feed the PoolTogether prize
 */
contract FeedThePrize is Ownable{
    
    using SafeMath for uint256;
    
    // amount stored in DAI
    mapping(address => uint256) public feedBook;
    
    uint256 public idleTotalA = 0;
    uint256 public ptTotalA = 0;
    
    event FeedPrize(address indexed _from, uint256 _amount);
    event FeedPT(address indexed _from, uint256 _amount);
    event FeedIdle(address indexed _from, uint256 _amount);
    event Withdraw(address indexed _from, uint256 _amount);
    event WithdrawPT(address indexed _from, uint256 _amount);
    event WithdrawIdle(address indexed _from, uint256 _amount);
    
    constructor() public {
        
    }
    
    IdleDAIV3 public idleP = IdleDAIV3(0x78751B12Da02728F467A44eAc40F5cbc16Bd7934);
    PoolTogetherDAI public ptP = PoolTogetherDAI(0x29fe7D60DdF151E5b52e5FAB4f1325da6b2bD958);
    
    // Feed Pool functions
    
    function feedPrize(uint256 _amount) public payable {
        require(_amount > 0, "The amount to feed has to be greater than 0");
        
        uint256 amountToFeed = _amount;
        
        uint256 idleA = 0;
        uint256 ptA = 0;
        (ptA, idleA) = getExceedAndRebalanceAmount(amountToFeed, true);
        
        if(idleA > 0) {
            idleP.mintIdleToken(idleA, true);
            feedBook[msg.sender] = feedBook[msg.sender].add(idleA);
            idleTotalA = idleTotalA.add(idleA);
            emit FeedIdle(msg.sender, idleA);
        }
        
        if(ptA > 0) {
            ptP.depositSponsorship(ptA);
            feedBook[msg.sender] = feedBook[msg.sender].add(ptA);
            ptTotalA = ptTotalA.add(ptA);
            emit FeedPT(msg.sender, ptA);
        }
        
        emit FeedPrize(msg.sender, amountToFeed);
    }
    
    function withdraw(uint256 _amount) public {
        require(_amount > 0, "The amount to withdraw has to be greater than 0");
        
        uint256 amountToW = _amount;
        
        require(amountToW <= feedBook[msg.sender], "Funds not sufficient for this address");
       
        uint256 idleW = 0;
        uint256 ptW = 0;
        (ptW, idleW) = getExceedAndRebalanceAmount(amountToW, false);
       
        if (idleW > 0) {
            uint256[] memory empty;
            uint256 idleTokenAmount = idleW.div(idleP.tokenPrice());
            idleP.reedemIdleToken(idleTokenAmount, true, empty);
            feedBook[msg.sender] = feedBook[msg.sender].sub(idleW);
            idleTotalA = idleTotalA.sub(idleW);
            emit WithdrawIdle(msg.sender, idleW);
        }
       
        if (ptW > 0) {
            ptP.withdrawSponsorshipAndFee(ptW);
            feedBook[msg.sender] = feedBook[msg.sender].sub(ptW);
            ptTotalA = ptTotalA.sub(ptW);
            emit WithdrawPT(msg.sender, ptW);
        }
       
        emit Withdraw(msg.sender, amountToW);
    }
    
    function getExceedAndRebalanceAmount(uint256 amount, bool feed) public returns(uint256, uint256) {
        uint256 ptAmount = 0;
        uint256 idleAmount = 0;
        uint256 amountToSplit = 0;
        uint256 amountToRebalance = 0;
        uint256 idleBalance = getIdleBalance();
        
        if(feed) {
            if (idleBalance > ptTotalA) {
                amountToRebalance = idleBalance.sub(ptTotalA);
                if (amountToRebalance >= amount) {
                    ptAmount = amount;
                } else {
                    ptAmount = amountToRebalance;
                }
            } else if(idleBalance < ptTotalA) {
                amountToRebalance = ptTotalA.sub(idleBalance);
                if (amountToRebalance >= amount) {
                    idleAmount = amount;
                } else {
                    idleAmount = amountToRebalance;
                }
            }
        } else {
            if (idleBalance > ptTotalA) {
                amountToRebalance = idleBalance.sub(ptTotalA);
                if (amountToRebalance >= amount) {
                    idleAmount = amount;
                } else {
                    idleAmount = amountToRebalance;
                }
            } else if(idleBalance < ptTotalA) {
                amountToRebalance = ptTotalA.sub(idleBalance);
                if (amountToRebalance >= amount) {
                    ptAmount = amount;
                } else {
                    ptAmount = amountToRebalance;
                }
            }
        }
        
        if(ptAmount != amount && idleAmount != amount) {
            amountToSplit = amount.sub(amountToRebalance);
            uint256 amountSplitted = amountToSplit.div(2);
            idleAmount = idleAmount.add(amountSplitted);
            ptAmount = ptAmount.add(amountSplitted);
        }
        
        require(idleAmount.add(ptAmount) == amount, "The total amount has to be the same");
        
        return (ptAmount, idleAmount);
    }
    
    // Return balance in DAI
    function getIdleBalance() public returns(uint256) {
        return idleP.balanceOf(address(this)).mul(idleP.tokenPrice());
    }
    
    function getPTBalance() public returns(uint256) {
        return ptP.balanceOf(address(this));
    }
    
    function getTotalA() public view returns(uint256) {
        return idleTotalA.add(ptTotalA);
    }
    
    function getInterestEarned() public returns(uint256) {
        return getIdleBalance().sub(idleTotalA);
    }
}