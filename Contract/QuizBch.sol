// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IBenSwapRouterNative {
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
}

interface IDLK {
    function mint(address to, uint256 amount) external returns (bool);
}

contract QuizBch is Ownable {
    using SafeMath for uint256;
    address private constant dlkAddress =
        0xA019F70Ed3C02E861249B9e942bf4b88BCB408Df;
    address private constant destroyAddress =
        0x69C1c41254C3A355b1f6E742C32996C74F78aFA5;
    address private constant routerAddress =
        0xa194133ED572D86fe27796F2feADBAFc062cB9E0;
    address private constant wbchAddress =
        0x3743eC0673453E5009310C727Ba4eaF7b3a1cc04;
    uint256 public presentToken;
    uint256 private totalShare;
    uint256 public buybackTokenCount;
    mapping(address => uint256) private sharesAndLockUntil;
    struct Buyer {
        uint256 amount;
        uint256 height;
        uint256 game;
        uint256 poker;
    }
    mapping(address => Buyer) private buyer;
    uint256 private constant pokerCount = 52;

    event Deposit(
        address indexed addr,
        uint256 beforeAmount,
        uint256 afterAmount,
        uint256 time
    );

    event Withdraw(
        address indexed addr,
        uint256 deltaBalance,
        uint256 deltaShare,
        uint256 time
    );

    event Poker(
        address indexed addr,
        uint256 amount,
        uint256 indexed t,
        uint256 indexed game,
        uint256 poker,
        uint256 time,
        uint256 height,
        uint256 odds
    );

    constructor() {
        presentToken = 2000000;
    }

    function deposit() public payable {
        uint256 amount = msg.value;
        uint256 oldBalance = address(this).balance.sub(amount).sub(
            buybackTokenCount
        );
        uint256 mySharesAndLockUntil = sharesAndLockUntil[msg.sender];
        uint256 oldShare = mySharesAndLockUntil >> 64;
        if (totalShare == 0) {
            emit Deposit(msg.sender, oldShare, amount, block.timestamp);
            sharesAndLockUntil[msg.sender] =
                (amount << 64) |
                (block.number + 512);
            totalShare = amount;
            return;
        }
        uint256 deltaShare = amount.mul(totalShare).div(oldBalance);
        sharesAndLockUntil[msg.sender] =
            ((deltaShare + oldShare) << 64) |
            (block.number + 512);
        totalShare = totalShare.add(deltaShare);
        emit Deposit(msg.sender, oldShare, deltaShare, block.timestamp);
    }

    function withdraw(uint256 deltaShare) external {
        uint256 mySharesAndLockUntil = sharesAndLockUntil[msg.sender];
        uint256 oldShare = mySharesAndLockUntil >> 64;
        uint256 lockUntil = uint256(uint64(mySharesAndLockUntil));
        require(oldShare >= deltaShare, "not enough share");
        require(block.number >= lockUntil, "still locked");
        uint256 oldBalance = address(this).balance.sub(buybackTokenCount);
        uint256 deltaBalance = oldBalance.mul(deltaShare).div(totalShare);
        sharesAndLockUntil[msg.sender] =
            ((oldShare.sub(deltaShare)) << 64) |
            lockUntil;
        totalShare = totalShare.sub(deltaShare);
        emit Withdraw(msg.sender, deltaBalance, deltaShare, block.timestamp);
        (bool successc, ) = msg.sender.call{value: deltaBalance}("");
        require(successc, "withdraw transfer failed");
    }

    function info(address addr)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 totalBalance = address(this).balance;
        uint256 mySharesAndLockUntil = sharesAndLockUntil[addr];
        return (
            totalBalance.sub(buybackTokenCount),
            totalShare,
            mySharesAndLockUntil >> 64,
            uint256(uint64(mySharesAndLockUntil))
        );
    }

    function buyback() external returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = wbchAddress;
        path[1] = dlkAddress;
        uint256 oldBuybackPoolFunds = buybackTokenCount;
        uint256[] memory amounts;
        amounts = IBenSwapRouterNative(routerAddress).swapExactETHForTokens{
            value: oldBuybackPoolFunds
        }(0, path, destroyAddress, 9000000000);
        buybackTokenCount = oldBuybackPoolFunds.sub(amounts[0]);
        return amounts[1];
    }

    function setPresentToken(uint256 _count) external onlyOwner {
        presentToken = _count;
    }

    function buyPoker(uint256 _game, uint256 _poker) public payable {
        require(
            ((_game == 1 || _game == 2) && _poker > 1 && _poker < pokerCount) ||
                _game == 3,
            "data error"
        );
        Buyer memory b = buyer[msg.sender];
        if (
            b.height > 0 &&
            b.height + 256 > block.number &&
            blockhash(b.height) != 0
        ) {
            getPokerReward();
        }
        uint256 amount = msg.value;
        require(amount >= 10, "amount err");
        uint256 oldBalance = address(this).balance.sub(amount).sub(
            buybackTokenCount
        );
        uint256 remained = amount.sub(amount.div(40));
        buybackTokenCount = buybackTokenCount.add(amount.div(200));
        (uint256 po, ) = pokerOdds(_game, _poker, 0);
        if (po > 30000) {
            require(
                remained.mul(po).div(100) < oldBalance,
                "amount too large 0.01"
            );
        } else {
            require(
                remained.mul(po).div(100).mul(2) < oldBalance,
                "amount too large 0.005"
            );
        }
        if (presentToken > 0) {
            IDLK(dlkAddress).mint(
                msg.sender,
                amount.mul(presentToken).div(100)
            );
        }
        Buyer storage bs = buyer[msg.sender];
        bs.amount = remained;
        bs.height = block.number;
        bs.game = _game;
        bs.poker = _poker;
        emit Poker(
            msg.sender,
            msg.value,
            1,
            _game,
            _poker,
            block.timestamp,
            block.number,
            po
        );
    }

    function getPokerReward() public returns (uint256 reward) {
        Buyer memory b = buyer[msg.sender];
        if (b.height == 0) return 0;
        bytes32 hash = blockhash(b.height);
        if (uint256(hash) == 0) return ~uint256(0);
        buyer[msg.sender].height = 0;
        (uint256 po, bool isPoker) = pokerOdds(
            b.game,
            b.poker,
            pokerNmber(b.height, hash, msg.sender)
        );
        if (isPoker) {
            reward = b.amount.mul(po).div(10000);
            (bool successc, ) = msg.sender.call{value: reward}("");
            require(successc, "withdraw transfer failed");
            emit Poker(
                msg.sender,
                reward,
                2,
                b.game,
                b.poker,
                block.timestamp,
                b.height,
                po
            );
        }
    }

    function pokerOdds(
        uint256 _game,
        uint256 _poker,
        uint256 _nmber
    ) private pure returns (uint256, bool) {
        if (_game == 1) {
            return (
                uint256(pokerCount * 10000).div(
                    uint256(pokerCount).sub(_poker)
                ),
                _nmber > _poker
            );
        }
        if (_game == 2) {
            return (
                uint256(pokerCount * 10000).div(_poker.sub(1)),
                _nmber < _poker
            );
        }
        if (_game == 3) {
            return (pokerCount * 10000, _nmber == _poker);
        }
        return (0, false);
    }

    function getMyBuyer(address _addr) public view returns (Buyer memory) {
        return buyer[_addr];
    }

    function pokerNmber(
        uint256 _height,
        bytes32 _hash,
        address _addr
    ) public pure returns (uint8) {
        return
            uint8(
                uint256(keccak256(abi.encodePacked(_height, _hash, _addr))) %
                    pokerCount
            ) + 1;
    }
}
