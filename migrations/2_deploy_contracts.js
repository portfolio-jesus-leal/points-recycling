var CustomOracle = artifacts.require("CustomOracle.sol");

module.exports = function(deployer) { 
  deployer.deploy(CustomOracle, {gas: 6500000, value: 1000000000000000000})
};