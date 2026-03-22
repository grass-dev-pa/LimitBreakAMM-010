pragma solidity >=0.8.0;

import {ERC20} from "@limitbreak/tm-core-lib/src/token/erc20/ERC20.sol";
import {Ownable} from "@limitbreak/tm-core-lib/src/utils/access/Ownable.sol";

contract ERC20Mock is ERC20, Ownable {
    uint8 private immutable _decimals;

    constructor(string memory _name, string memory _symbol, uint8 decimals_)
        ERC20(_name, _symbol)
        Ownable(msg.sender)
    {
        _decimals = decimals_;
    }

    function mint(address to, uint256 value) public virtual {
        _mint(to, value);
    }

    function burn(address from, uint256 value) public virtual {
        _burn(from, value);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}

contract BrokenERC20Mock is ERC20Mock {
    bool private _broken;

    constructor(string memory _name, string memory _symbol, uint8 decimals_) ERC20Mock(_name, _symbol, decimals_) {}

    function setBroken(bool broken) public {
        _broken = broken;
    }

    function _validateTransfer(address, address, address, uint256, uint256) internal view override {
        if (_broken) {
            revert("BrokenERC20Mock: Transfer is broken");
        }
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        _validateTransfer(msg.sender, to, address(this), value, 0);
        return super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        _validateTransfer(from, to, address(this), value, 0);
        return super.transferFrom(from, to, value);
    }
}
