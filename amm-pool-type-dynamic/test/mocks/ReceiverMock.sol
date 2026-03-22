pragma solidity 0.8.24;

contract ReceiverMock {
    fallback() external payable {}
    receive() external payable {}
}

contract ReceiverMockReject {
    fallback() external payable {
        revert("ReceiverMockReject: Rejected");
    }
    receive() external payable {
        revert("ReceiverMockReject: Rejected");
    }
}