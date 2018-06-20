var BitAcademyToken = artifacts.require("./BitAcademyToken.sol");

module.exports = function(deployer) {
  deployer.deploy(BitAcademyToken,"0x37f90f9BE74C6Af83e2eFA6A918ca5D38eB655e4",1000000000);
};
