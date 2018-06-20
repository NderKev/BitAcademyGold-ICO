const HDWalletProvider = require("truffle-hdwallet-provider-privkey");
const privKey = "bb951f4ab9c3665c69a187a3bf344b6b5ec0f9cc782de96132312011f92dec2b";

module.exports = {
  // See <http://truffleframework.com/docs/advanced/configuration>
  // to customize your Truffle configuration!

    networks: {
      ropsten: {
        provider: () => { return new HDWalletProvider(privKey, "https://ropsten.infura.io/PGeaCCgYpthSugPncips")},
        network_id: '3'
      },
      rinkeby: {
        provider: () => { return new HDWalletProvider(privKey, "https://rinkeby.infura.io/PGeaCCgYpthSugPncips")},
        network_id: '4'
      },
      development: {
          host: "127.0.0.1",
          port: 8545,
          network_id: "*" // Match any network id
      }
  }
};
