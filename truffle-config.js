module.exports = {

  contracts_build_directory: "./build",

  networks: {

    development: {
      host: 'localhost',
      port: 8545,
      network_id: '*'
    },

    ganache: {
      host: "localhost",
      port: 8545,
      network_id: "5777", 
      from: "0xF4C603865F0FCEE4158e4143C1701BFE427AA274",  
      gas: 70000000, // Gas limit used for deploys             
    },

    develop: {
      port: 8545,
      gas: 7000000, // Gas limit used for deploys
      gasPrice: 20000000000  // 20 gwei (in wei) (default: 100 gwei)
    },

    rinkeby: {
      host: "localhost", // Connect to geth on the specified
      port: 8545,
      from: "0xcf757ac9610b264aa967832c93a0e9ccc5f99d8e",
      network_id: 4,
      gas: 7000000, // Gas limit used for deploys      
    }
  },

  // Configure your compilers
  compilers: {
    solc: {
      version: "0.5.1",    // Fetch exact version from solc-bin (default: truffle's version)
      // docker: true,        // Use "0.5.1" you've installed locally with docker (default: false)
      settings: {          // See the solidity docs for advice about optimization and evmVersion
        optimizer: {
          enabled: true,
          runs: 200
        },
      // evmVersion: "byzantium"
      }
    }
  }
};
