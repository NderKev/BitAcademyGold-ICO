var BitAcademyToken = artifacts.require("./BitAcademyToken.sol");
var PreICOBitAcademyGold = artifacts.require("./PreICOBitAcademyGold.sol");

module.exports = function(deployer) {
  //deployer.deploy(BitAcademyToken,"0x37f90f9BE74C6Af83e2eFA6A918ca5D38eB655e4",1000000000);
  deployer.deploy(PreICOBitAcademyGold,73079733835916,"0x37f90f9BE74C6Af83e2eFA6A918ca5D38eB655e4","0x6454835367dfe5bcb3787fdb968ac0bdc3ece1d9",1529487347,1529573747, "0x37f90f9BE74C6Af83e2eFA6A918ca5D38eB655e4");
};
