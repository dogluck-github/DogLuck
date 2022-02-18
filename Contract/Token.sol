//SPDX-License-Identifier:  UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract Token is ERC20 {
    using SafeMath for uint256;

    address public governance;
    address public pendingGov;

    uint256 public cap;

    mapping(address => bool) public minters;

    event NewPendingGov(address oldPendingGov, address newPendingGov);

    event NewGov(address oldGov, address newGov);

    event DestroyCount(uint256 count);

    modifier onlyGov() {
        require(msg.sender == governance, "governance");
        _;
    }

    constructor() ERC20("DogLuck", "DLK") {
        cap = 1000000000 * 10**18;
        governance = msg.sender;
        addMinter(msg.sender);
    }

    function mint(address _account, uint256 _amount) public returns (bool) {
        require(minters[msg.sender], "minter");
        _mint(_account, _amount);
        return true;
    }

    function addMinter(address _minter) public onlyGov {
        minters[_minter] = true;
    }

    function removeMinter(address _minter) public onlyGov {
        minters[_minter] = false;
    }

    function setPendingGov(address _pendingGov) external onlyGov {
        address oldPendingGov = pendingGov;
        pendingGov = _pendingGov;
        emit NewPendingGov(oldPendingGov, _pendingGov);
    }

    function acceptGov() external {
        require(msg.sender == pendingGov, "not setter");
        address oldGov = governance;
        governance = pendingGov;
        pendingGov = address(0);
        emit NewGov(oldGov, governance);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        super._beforeTokenTransfer(from, to, amount);

        if (from == address(0)) {
            // When minting tokens
            require(totalSupply().add(amount) <= cap, "Cap exceeded");
        }
    }
}
