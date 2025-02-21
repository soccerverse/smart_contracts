# Soccerverse Helper Contracts

Soccerverse uses [Democrit-EVM](https://github.com/xaya/democrit-evm) for
building an exchange between in-game coins and on-chain WCHI.  We also
employ some other helper contracts, e.g. for auto-conversion of currency
when doing Democrit maker-orders or for the sale of club packs.

## Referral Tracker

The `ReferralTracker` contract with production ref data, which can be used
for production and also development / testing, is deployed on
[0x329612BB11Eea1Ea5065993DC32b41C86D6068c2](https://polygonscan.com/address/0x329612BB11Eea1Ea5065993DC32b41C86D6068c2).

## Democrit

The main entry points for Democrit (other contracts can be retrieved from
these) are:

| Contract | Production (`g/sv`) | Test (`g/svt`) |
| -------- | -------------------  | -------------- |
| AutoConvert | [0xA3098c68Fd99233B57Bd065AAc545Cca5f1ac296](https://polygonscan.com/address/0xA3098c68Fd99233B57Bd065AAc545Cca5f1ac296) | [0x65e25Ac5cCA094519729D5896C0BC3D8D682292e](https://polygonscan.com/address/0x65e25Ac5cCA094519729D5896C0BC3D8D682292e) |
| DemocritSoccerverse | [0xEB265D9fBb05641266366F15EcE76a268EF4a2A4](https://polygonscan.com/address/0xEB265D9fBb05641266366F15EcE76a268EF4a2A4) | [0x183F8a1aF8bdD9db777CC31F3a05B6b7E36f2A4A](https://polygonscan.com/address/0x183F8a1aF8bdD9db777CC31F3a05B6b7E36f2A4A) |

The subgraph for Democrit is deployed and can be queried at:
- Production (`g/sv`):
  - [https://api.studio.thegraph.com/query/97741/soccerverse-democrit-sv/version/latest](https://api.studio.thegraph.com/query/97741/soccerverse-democrit-sv/version/latest)
  - [https://polygon-mainnet.graph-eu.p2pify.com/0b6e45304f8e91b9cf21b1b492654e22/sgr-491-874-073](https://polygon-mainnet.graph-eu.p2pify.com/0b6e45304f8e91b9cf21b1b492654e22/sgr-491-874-073)
- Test (`g/svt`): [https://api.studio.thegraph.com/query/44576/soccerverse-democrit-svt/version/latest](https://api.studio.thegraph.com/query/44576/soccerverse-democrit-svt/version/latest)

## Pack Sale

Contracts for the pack sale are deployed at:

| Contract | Production (`g/sv`) | Test (`g/svt`) |
| -------- | ------------------- | -------------- |
| ClubMinter | [0xeEE0d855112b71Dc68d72053594Af03F92C586Ae](https://polygonscan.com/address/0xeEE0d855112b71Dc68d72053594Af03F92C586Ae) | [0x14373DbC5c7C99028d58d07D77D3Fb365391d1eF](https://polygonscan.com/address/0x14373DbC5c7C99028d58d07D77D3Fb365391d1eF) |
| PackVoucher | [0x9De075D87B812eC647d5541CB50d65Bc06Ec6509](https://polygonscan.com/address/0x9De075D87B812eC647d5541CB50d65Bc06Ec6509) | - |
| PurchaseTracker | [0x879E44f2025cAd323f8F1C7C28F672F5f3f92304](https://polygonscan.com/address/0x879E44f2025cAd323f8F1C7C28F672F5f3f92304) | [0xA81AB19fE4a85709B5DCAD7ae1d404975CAE9e8B](https://polygonscan.com/address/0xA81AB19fE4a85709B5DCAD7ae1d404975CAE9e8B) |
| SwappingPackSale "tier 1" | [0x8501A9018A5625b720355A5A05c5dA3D5E8bB003](https://polygonscan.com/address/0x8501A9018A5625b720355A5A05c5dA3D5E8bB003) | [0xD7E32eab3FCb5C84d52ED07Cb823E7D379A17c9c](https://polygonscan.com/address/0xD7E32eab3FCb5C84d52ED07Cb823E7D379A17c9c) |
| SwappingPackSale "tier 2" | [0x0bF818f3A69485c8B05Cf6292D9A04C6f58ADF08](https://polygonscan.com/address/0x0bF818f3A69485c8B05Cf6292D9A04C6f58ADF08) | [0xb01d455CA703f2284f8B5433994E2419ca4BcC80](https://polygonscan.com/address/0xb01d455CA703f2284f8B5433994E2419ca4BcC80) |
| SwappingPackSale "tier 3" | [0x4259D89087b6EBBC8bE38A30393a2F99F798FE2f](https://polygonscan.com/address/0x4259D89087b6EBBC8bE38A30393a2F99F798FE2f) | [0xc9c3E2688ea0bA342b9fB9a3C49C5F40793BD15A](https://polygonscan.com/address/0xc9c3E2688ea0bA342b9fB9a3C49C5F40793BD15A) |
| SwappingPackSale "tier 4" | [0x167360A54746b82e38f700dF0ef812c269c4e565](https://polygonscan.com/address/0x167360A54746b82e38f700dF0ef812c269c4e565) | [0x74C68EA9aD80D5B6AdE5F4AfEe3D79d2176C6807](https://polygonscan.com/address/0x74C68EA9aD80D5B6AdE5F4AfEe3D79d2176C6807) |
| SwappingPackSale "tier 5" | [0x3d25Cb3139811c6AeE9D5ae8a01B2e5824b5dB91](https://polygonscan.com/address/0x3d25Cb3139811c6AeE9D5ae8a01B2e5824b5dB91) | [0xd1E7895648f7916780B4DADd7fc54a07a4d2C8C2](https://polygonscan.com/address/0xd1E7895648f7916780B4DADd7fc54a07a4d2C8C2) |
