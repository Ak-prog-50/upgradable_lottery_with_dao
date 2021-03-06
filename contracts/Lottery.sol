// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.0 <0.9.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol"; //* vrf coordinator contract interface
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol"; //* base contract for any VRF consumer
import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

error Lottery__TransferFailed();
error Lottery__SendMoreToEnterLottery();
error Lottery__LotteryNotOpen();
// error Lottery__NotTheOwner();

contract Lottery is VRFConsumerBaseV2, Ownable{
    // using SafeMathChainlink for uint256; //! Using safe math is only for uints. Need to use a library like abdk before pushing to production to check for overflow errros. (divi func in ABDK)

    enum LotteryState {
        OPEN,
        CLOSED,
        SELECTING_WINNER
    }

    address public immutable i_owner;
    int8 public immutable i_entranceFeeInUsd;
    VRFCoordinatorV2Interface immutable i_vrfCoordinator; // default visibility is internal in vars.

    mapping(address => uint256) public s_addressToAmountDeposited;
    address[] public s_participants;
    address payable public s_recentWinner;
    uint256 public s_requestId;
    uint64 s_subscriptionId;
    LotteryState public s_lotteryState;
    AggregatorV3Interface internal s_priceFeed;

    // These could be parameterized as well.
    bytes32 constant KEY_HASH =
        0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc; //* gas lane key hash (check docs for more info)
    uint32 constant CALLBACK_GAS_LIMIT = 100000; //* gas limit when VRF callback rawFulfillRandomWords func in VRFConsumerBaseV2.
    uint16 constant REQUEST_CONFIRMATIONS = 3; //* number of confirmations VRF node waits for before fulfilling request
    uint32 constant NUM_WORDS = 1; //* number of words(uint256 values) in the random word request

    event WinnerGotMoney(address _recentWinner, uint256[] _randomWords);

    constructor(
        address _priceFeed,
        address _vrfCoordinator,
        int8 _entranceFeeInUsd,
        uint64 _subscriptionId
    ) VRFConsumerBaseV2(_vrfCoordinator) {
        i_owner = msg.sender;
        i_entranceFeeInUsd = _entranceFeeInUsd;
        s_priceFeed = AggregatorV3Interface(_priceFeed);
        s_lotteryState = LotteryState.CLOSED; //* default lottery state is closed
        s_subscriptionId = _subscriptionId;
        i_vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
    }

    // onlyOwner modifier
    // modifier onlyOwner() {
    //     if (msg.sender != i_owner) revert Lottery__NotTheOwner();
    //     _;
    // }

    // checkOpened modifier
    modifier checkOpened() {
        if (s_lotteryState != LotteryState.OPEN) revert Lottery__LotteryNotOpen();
        _;
    }

    function getEntranceFee() public view returns (uint256) {
        (, int256 answer, , , ) = s_priceFeed.latestRoundData(); // * returns ETH/USD rate with 8 decimal places as answer
        // console.log(uint(answer), "answer");

        int256 roundedAnswer = answer / (10**8); // * 245678999700 => rounded as 2456
        // console.log(uint(roundedAnswer), "roundedAnswer");

        int256 oneUSDInWei = 1 ether / roundedAnswer; //notes: answers decimals are ignored. need to recheck how to do rounding better
        // console.log(uint(oneUSDInWei), "oneUsdInWEi");

        int256 entranceFeeInWei = oneUSDInWei * i_entranceFeeInUsd;
        // console.log(uint(entranceFeeInWei), "entranceFeeInwei");

        return uint256(entranceFeeInWei);
    }

    function enter() public payable checkOpened {
        // know who has enterred
        // what amount has been deposited

        // check if the amount is enough
        if (msg.value < getEntranceFee())
            revert Lottery__SendMoreToEnterLottery();

        s_participants.push(msg.sender);
        s_addressToAmountDeposited[msg.sender] = msg.value; //! check how this works when funds added twice by the same address from the second start of lottery.
    }

    function startLottery() external onlyOwner {
        require(s_lotteryState == LotteryState.CLOSED);
        s_lotteryState = LotteryState.OPEN;
    }

    function endLottery() external onlyOwner checkOpened {
        require(s_participants.length > 0, "No participants");

        s_lotteryState = LotteryState.SELECTING_WINNER;
        // * requestRandomWords() function returns a uint256 value
        s_requestId = i_vrfCoordinator.requestRandomWords(
            KEY_HASH,
            s_subscriptionId,
            REQUEST_CONFIRMATIONS,
            CALLBACK_GAS_LIMIT,
            NUM_WORDS
        );
    }

    function fulfillRandomWords(uint256, uint256[] memory _randomWords)
        internal
        override
    {
        // * this function is for the callback from the VRF node. Can be called only from the VRF node. (check docs for more info. (request response cycle))
        require(s_lotteryState == LotteryState.SELECTING_WINNER);
        require(_randomWords[0] > 0);
        require(_randomWords.length > 0);
        require(s_participants.length > 0);

        uint256 indexOfWinner = _randomWords[0] % s_participants.length;
        require(indexOfWinner < s_participants.length);

        s_recentWinner = payable(s_participants[indexOfWinner]); // participants array is not payable.

        (bool success, ) = s_recentWinner.call{value: address(this).balance}("");  //* Calls to_recentWinner(an account contract in etheruem) from the lottery contract without specifying function bytes data.
        if (!success) revert Lottery__TransferFailed();

        // reset particiapants array
        s_participants = new address[](0);

        s_lotteryState = LotteryState.CLOSED;
        emit WinnerGotMoney(s_recentWinner, _randomWords);
    }
}

// test resting addresstoamount
// test how to store previous data
