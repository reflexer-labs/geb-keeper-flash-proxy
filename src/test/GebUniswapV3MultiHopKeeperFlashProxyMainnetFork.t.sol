
pragma solidity ^0.6.7;

import "ds-test/test.sol";
import {GebUniswapV3MultiHopKeeperFlashProxy} from "../GebUniswapV3MultiHopKeeperFlashProxy.sol";

// === HEVM ===

interface Hevm {
    function warp(uint256) external;
    function roll(uint256) external;
    function store(
        address,
        bytes32,
        bytes32
    ) external;
    function store(
        address,
        bytes32,
        address
    ) external;
    function load(address, bytes32) external view returns (bytes32);
}

// === Helpers ===

abstract contract AuthLike {
    function authorizedAccounts(address) external view virtual returns (uint256);
}

abstract contract TokenLike {
    function approve(address, uint256) public virtual returns (bool);
    function decimals() public view virtual returns (uint256);
    function totalSupply() public view virtual returns (uint256);
    function balanceOf(address) public view virtual returns (uint256);
    function name() public view virtual returns (string memory);
    function symbol() public view virtual returns (string memory);
    function owner() public view virtual returns (address);
}

abstract contract DSProxyLike {
    function execute(address _target, bytes memory _data) public payable virtual returns (bytes memory response);
}

// === GEB ===

abstract contract DSPauseLike {
    function proxy() external view virtual returns (address);
    function delay() external view virtual returns (uint256);
    function scheduleTransaction(
        address,
        bytes32,
        bytes calldata,
        uint256
    ) external virtual;
    function executeTransaction(
        address,
        bytes32,
        bytes calldata,
        uint256
    ) external virtual returns (bytes memory);
    function authority() external view virtual returns (address);
    function owner() external view virtual returns (address);
}

abstract contract LiquidationEngineLike is AuthLike {
    function collateralTypes(bytes32) virtual public view returns (
        address collateralAuctionHouse,
        uint256 liquidationPenalty,     // [wad]
        uint256 liquidationQuantity     // [rad]
    );
    function disableContract() virtual external;
    function liquidateSAFE(bytes32, address) external virtual returns (uint);
}

abstract contract SAFEEngineLike {
    function coinBalance(address) public view virtual returns (uint256);
    function debtBalance(address) public view virtual returns (uint256);
    function settleDebt(uint256) external virtual;
    function approveSAFEModification(address) external virtual;
    function denySAFEModification(address) external virtual;
    function modifyCollateralBalance(
        bytes32,
        address,
        int256
    ) external virtual;
    function transferInternalCoins(
        address,
        address,
        uint256
    ) external virtual;
    function createUnbackedDebt(
        address,
        address,
        uint256
    ) external virtual;
    function collateralTypes(bytes32)
        public
        view
        virtual
        returns (
        uint256 debtAmount, // [wad]
        uint256 accumulatedRate, // [ray]
        uint256 safetyPrice, // [ray]
        uint256 debtCeiling, // [rad]
        uint256 debtFloor, // [rad]
        uint256 liquidationPrice // [ray]
        );
    function safes(bytes32, address)
        public
        view
        virtual
        returns (
        uint256 lockedCollateral, // [wad]
        uint256 generatedDebt // [wad]
        );
    function globalDebt() public virtual returns (uint256);
    function transferCollateral(
        bytes32 collateralType,
        address src,
        address dst,
        uint256 wad
    ) external virtual;

    function confiscateSAFECollateralAndDebt(
        bytes32 collateralType,
        address safe,
        address collateralSource,
        address debtDestination,
        int256 deltaCollateral,
        int256 deltaDebt
    ) external virtual;
    function disableContract() external virtual;
    function tokenCollateral(bytes32, address) public view virtual returns (uint256);
}

abstract contract SystemCoinLike {
    function balanceOf(address) public view virtual returns (uint256);
    function approve(address, uint256) public virtual returns (uint256);
    function transfer(address, uint256) public virtual returns (bool);
    function transferFrom(
        address,
        address,
        uint256
    ) public virtual returns (bool);
}

abstract contract GebSafeManagerLike {
    function safei() public view virtual returns (uint256);
    function safes(uint256) public view virtual returns (address);
    function ownsSAFE(uint256) public view virtual returns (address);
    function lastSAFEID(address) public virtual returns (uint);
    function safeCan(
        address,
        uint256,
        address
    ) public view virtual returns (uint256);
}

abstract contract TaxCollectorLike {
    function collateralTypes(bytes32) public virtual returns (uint256, uint256);
    function taxSingle(bytes32) public virtual returns (uint256);
    function modifyParameters(bytes32, uint256) external virtual;
    function taxAll() external virtual;
    function globalStabilityFee() external view virtual returns (uint256);
}

abstract contract DSTokenLike {
    function balanceOf(address) public view virtual returns (uint256);
    function approve(address, uint256) public virtual;
    function transfer(address, uint256) public virtual returns (bool);
    function transferFrom(
        address,
        address,
        uint256
    ) public virtual returns (bool);
}

abstract contract CoinJoinLike {
    function safeEngine() public virtual returns (SAFEEngineLike);
    function systemCoin() public virtual returns (DSTokenLike);
    function join(address, uint256) public payable virtual;
    function exit(address, uint256) public virtual;
}

abstract contract CollateralJoinLike {
    function decimals() public virtual returns (uint256);
    function collateral() public virtual returns (TokenLike);
    function join(address, uint256) public payable virtual;
    function exit(address, uint256) public virtual;
}

abstract contract IncreasingDiscountCollateralAuctionHouseLike {
    function safeEngine() external virtual view returns (address);
    function maxDiscount() external virtual view returns (uint256);
    function minimumBid() external virtual view returns (uint256);
    function perSecondDiscountUpdateRate() external virtual returns (uint256);
    function buyCollateral(uint256, uint256) external virtual;
    function bids(uint256) external virtual view returns (uint256, uint256, uint256, uint256, uint256, uint256, uint48, address, address);
}

contract Addresses {
    mapping (string => address) internal addr;
    constructor() public {
        addr["GEB_SAFE_ENGINE"] = 0xCC88a9d330da1133Df3A7bD823B95e52511A6962;
        addr["GEB_TAX_COLLECTOR"] = 0xcDB05aEda142a1B0D6044C09C64e4226c1a281EB;
        addr["GEB_LIQUIDATION_ENGINE"] = 0x27Efc6FFE79692E0521E7e27657cF228240A06c2;
        addr["GEB_COIN_JOIN"] = 0x0A5653CCa4DB1B6E265F47CAf6969e64f1CFdC45;
        addr["GEB_PAUSE"] = 0x2cDE6A1147B0EE61726b86d83Fd548401B1162c7;
        addr["GEB_PAUSE_PROXY"] = 0xa57A4e6170930ac547C147CdF26aE4682FA8262E;
        addr["GEB_GOV_ACTIONS"] = 0xe3Da59FEda69B4D83a10EB383230AFf439dd802b;
        addr["GEB_COIN"] = 0x03ab458634910AaD20eF5f1C8ee96F1D6ac54919;
        addr["PROXY_ACTIONS"] = 0x880CECbC56F48bCE5E0eF4070017C0a4270F64Ed;
        addr["SAFE_MANAGER"] = 0xEfe0B4cA532769a3AE758fD82E1426a03A94F185;
        addr["ETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        addr["GEB_JOIN_ETH_A"] = 0x2D3cD7b81c93f188F3CB8aD87c8Acc73d6226e3A;
        addr["GEB_COLLATERAL_AUCTION_HOUSE_ETH_A"] = 0x9fC9ae5c87FD07368e87D1EA0970a6fC1E6dD6Cb;
    }
}

// Container contract for the most common geb live contracts
contract Contracts is Addresses {
    DSPauseLike public pause;
    SAFEEngineLike public safeEngine;
    SystemCoinLike public systemCoin;
    GebSafeManagerLike public safeManager;
    TaxCollectorLike public taxCollector;
    CoinJoinLike public coinJoin;
    CollateralJoinLike public ethAJoin;
    TokenLike public weth;
    LiquidationEngineLike public liquidationEngine;
    IncreasingDiscountCollateralAuctionHouseLike public collateralAuctionHouseEthA;

    constructor() public {
        pause = DSPauseLike(addr["GEB_PAUSE"]);
        safeEngine = SAFEEngineLike(addr["GEB_SAFE_ENGINE"]);
        systemCoin = SystemCoinLike(addr["GEB_COIN"]);
        safeManager = GebSafeManagerLike(addr["SAFE_MANAGER"]);
        taxCollector = TaxCollectorLike(addr["GEB_TAX_COLLECTOR"]);
        coinJoin = CoinJoinLike(addr["GEB_COIN_JOIN"]);
        ethAJoin = CollateralJoinLike(addr["GEB_JOIN_ETH_A"]);
        weth = TokenLike(addr["ETH"]);
        liquidationEngine = LiquidationEngineLike(addr["GEB_LIQUIDATION_ENGINE"]);
        collateralAuctionHouseEthA = IncreasingDiscountCollateralAuctionHouseLike(addr["GEB_COLLATERAL_AUCTION_HOUSE_ETH_A"]);
    }
}

contract TestBaseUtils {
    uint256 constant WAD = 10**18;
    uint256 constant RAY = 10**27;
    uint256 constant RAD = 10**45;

    bytes20 constant CHEAT_CODE = bytes20(uint160(uint256(keccak256("hevm cheat code"))));

    bytes32 constant ETH_A = bytes32("ETH-A");

    function getExtcodehash(address target) public view returns (bytes32 codehash) {
        assembly {
        codehash := extcodehash(target)
        }
    }

    function addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(addr));
    }
}

// Contract with Geb test helpers
contract TestBase is DSTest, TestBaseUtils, Addresses {
    Hevm internal hevm;
    Contracts internal contracts;

    function setUp() public virtual {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        contracts = new Contracts();
    }

    // Execute the pending proposa
    function execProposal(address target, bytes memory proposalPayload) internal {
        // Setting this as owner in pause
        bytes32 savedPauseOwner = hevm.load(address(contracts.pause()), bytes32(uint256(1)));
        hevm.store(address(contracts.pause()), bytes32(uint256(1)), addressToBytes32(address(this)));
        assertEq(contracts.pause().owner(), address(this));

        bytes32 tag;
        assembly {
        tag := extcodehash(target)
        }

        // Schedule, wait and execute proposal
        uint256 earliestExecutionTime = now + contracts.pause().delay();
        contracts.pause().scheduleTransaction(target, tag, proposalPayload, earliestExecutionTime);
        hevm.warp(now + contracts.pause().delay());
        contracts.pause().executeTransaction(target, tag, proposalPayload, earliestExecutionTime);

        // Remove pause ownership
        hevm.store(address(contracts.pause()), bytes32(uint256(1)), savedPauseOwner);
    }
}

contract Guy {
    function proxyActionsCall(address payable proxyActions, bytes memory data) public payable returns (bool, bytes memory) {
        return proxyActions.delegatecall(data);
    }
}

// Should only be run on mainnet fork, tests ignored when running locallly. To run all tests:
// dapp test -vv -m test_fork --rpc-url <nodeUrl>
contract KeeperFLashProxyV3MainnetForkTest is TestBase {
    GebUniswapV3MultiHopKeeperFlashProxy keeperProxy;

    function setUp() public override {
        super.setUp();
    }

    modifier onlyFork() {
        if (block.timestamp > 1629777750) _;
    }

    function test_fork_rai_dai() public payable onlyFork {
        keeperProxy = new GebUniswapV3MultiHopKeeperFlashProxy(
            addr["GEB_COLLATERAL_AUCTION_HOUSE_ETH_A"],
            addr["ETH"],
            addr["GEB_COIN"],
            0xcB0C5d9D92f4F2F80cce7aa271a1E148c226e19D, // rai/dai
            0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8, // dai/eth
            addr["GEB_COIN_JOIN"],
            addr["GEB_JOIN_ETH_A"]
        );

        _test_keeper_proxy();
    }

    function test_fork_rai_dai_deployed() public payable onlyFork {
        keeperProxy = GebUniswapV3MultiHopKeeperFlashProxy(0xc2e5b0dcD4bB9696D16F8c1658b2A55EEBf4E6F5);
        _test_keeper_proxy();
    }

    function test_fork_rai_usdc() public payable onlyFork {
        keeperProxy = new GebUniswapV3MultiHopKeeperFlashProxy(
            addr["GEB_COLLATERAL_AUCTION_HOUSE_ETH_A"],
            addr["ETH"],
            addr["GEB_COIN"],
            0xFA7D7A0858a45C1b3b7238522A0C0d123900c118, // rai/usdc
            0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8, // usdc/eth
            addr["GEB_COIN_JOIN"],
            addr["GEB_JOIN_ETH_A"]
        );
        _test_keeper_proxy();
    }

    function test_fork_rai_usdc_deployed() public payable onlyFork {
        keeperProxy = GebUniswapV3MultiHopKeeperFlashProxy(0xDf8Cf7c751E538eA5bEc688fFF31A8F9d152B264);
        _test_keeper_proxy();
    }

    function test_fork_rai_eth_deployed() public payable onlyFork {
        keeperProxy = GebUniswapV3MultiHopKeeperFlashProxy(0xcDCE3aF4ef75bC89601A2E785172c6B9f65a0aAc);
        _test_keeper_proxy();
    }

    function _test_keeper_proxy() internal {
        (address auctionHouseAddress,,) = contracts.liquidationEngine().collateralTypes("ETH-A");
        IncreasingDiscountCollateralAuctionHouseLike auctionHouse = IncreasingDiscountCollateralAuctionHouseLike(auctionHouseAddress);

        Guy bob = new Guy();

        // creating unsafe safe
        (,, uint safetyPrice,,,) = contracts.safeEngine().collateralTypes("ETH-A");

        bob.proxyActionsCall{value: 10 ether}(payable(addr["PROXY_ACTIONS"]),
            abi.encodeWithSignature(
                "openLockETHAndGenerateDebt(address,address,address,address,bytes32,uint256)",
                addr["SAFE_MANAGER"],
                addr["GEB_TAX_COLLECTOR"],
                addr["GEB_JOIN_ETH_A"],
                addr["GEB_COIN_JOIN"],
                bytes32("ETH-A"),
                (safetyPrice / 100000000) - 1
            )
        );

        uint safe = contracts.safeManager().lastSAFEID(address(bob));
        assertTrue(safe != 0);
        address safeHandler = contracts.safeManager().safes(safe);
        assertTrue(safeHandler != address(0));

        // moving safe under water
        execProposal
            (addr["GEB_GOV_ACTIONS"],
            abi.encodeWithSignature(
                "taxSingleAndModifyParameters(address,bytes32,bytes32,uint256)",
                address(contracts.taxCollector()),
                bytes32("ETH-A"),
                bytes32("stabilityFee"),
                uint(1.1 * 10**27)
            )
        );
        hevm.warp(now + 1);
        contracts.taxCollector().taxSingle("ETH-A");

        // liquidating through the proxy
        uint previousBalance = address(this).balance;

        uint auctionId = keeperProxy.liquidateAndSettleSAFE(safeHandler);

        assertTrue(previousBalance < address(this).balance); // profit!

        assertTrue(auctionId != 0); // auction happened
        (uint amountToSell, uint amountToRaise,,,,,,,) = auctionHouse.bids(auctionId);
        assertTrue(amountToSell == 0 && amountToRaise == 0); // auction settled

        // keeper retains no balance
        assertEq(contracts.weth().balanceOf(address(keeperProxy)), 0);
        assertEq(contracts.systemCoin().balanceOf(address(keeperProxy)), 0);
        assertEq(TokenLike(0x6B175474E89094C44Da98b954EedeAC495271d0F).balanceOf(address(keeperProxy)), 0); // dai
        assertEq(TokenLike(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48).balanceOf(address(keeperProxy)), 0); // usdc
        assertEq(address(keeperProxy).balance, 0);
    }

    fallback() external payable {}
}
