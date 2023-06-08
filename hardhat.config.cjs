/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
    networks: {
        hardhat: {},
    },
    solidity: {
        version: '0.8.18',
        settings: {
            optimizer: {
                enabled: true,
                runs: 200,
            },
        },
    },
}
