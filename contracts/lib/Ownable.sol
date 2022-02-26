pragma solidity ^0.5.1;

contract Ownable {
    
    address _owner;


    modifier onlyOwner {
         require(_owner == msg.sender);
        _;
    }
    
    
}