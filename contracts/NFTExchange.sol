// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >0.8.0 <=0.9.0;

import "./Order.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

struct Sig {
    bytes32 r;
    bytes32 s;
    uint8 v;
}

contract NFTExchange is Ownable {
    // Order 구조체의 타입해쉬
    bytes32 private constant ORDER_TYPEHASH =
        0x437a5ccd912c6a90692bf48ff59bd71607c053d62292db467002418254aa1f4d;

    bytes32 private DOMAIN_SEPERATOR =
        keccak256(
            abi.encode(
                keccak256(
                    "EIP721Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256("Wyvern Clone Coding Exchange"),
                // version
                keccak256("1"),
                // chainId
                5,
                address(this)
            )
        );

    // 수수료를 납부하는 주소
    address public feeAddress;

    // order를 사용했으면 재사용 못하게 하기
    mapping(bytes32 => bool) public cancelledOfFinalized;

    constructor(address _feeAddress) Ownable(msg.sender) {
        feeAddress = _feeAddress;
    }

    // 수수료 납부 주소를 변경. Contract Owner만 호출 가능
    function setFeeAddress(address _feeAddress) external onlyOwner {
        feeAddress = _feeAddress;
    }

    function atomicMatch(
        Order memory buy,
        Sig memory buySig,
        Order memory sell,
        Sig memory sellSig
    ) external {
        bytes32 buyHash = validateOrder(buy, buySig);
        bytes32 sellHash = validateOrder(sell, sellSig);

        require(
            !cancelledOfFinalized[buyHash] && !cancelledOfFinalized[sellHash],
            "finalized order"
        );

        require(orderCanMatch(buy, sell), "not matched");

        // target이 CA이 인지 코드 사이즈로 체크
        uint size;
        address target = sell.target;
        assembly {
            size := extcodesize(target)
        }
        require(size > 0);

        if (buy.replacementPattern.length > 0) {
            guardedArrayReplace(
                buy.callData_,
                sell.callData_,
                buy.replacementPattern
            );
        }

        if (sell.replacementPattern.length > 0) {
            guardedArrayReplace(
                sell.callData_,
                buy.callData_,
                sell.replacementPattern
            );
        }

        require(keccak256(buy.callData_) == keccak256(sell.callData_));

        cancelledOfFinalized[buyHash] = true;
        cancelledOfFinalized[sellHash] = true;

        executeFundsTransfer(buy, sell);
    }

    function calculateMatchPrice(
        Order memory buy,
        Order memory sell
    ) internal view returns (uint256) {
        uint256 buyPrice = getOrderPrice(buy);
        uint256 sellPrice = getOrderPrice(sell);

        require(buyPrice >= sellPrice);

        return buyPrice;
    }

    function getOrderPrice(Order memory order) internal view returns (uint256) {
        // 고정가격 방식 일때
        if (order.saleKind == SaleKind.FIXED_PRICE) {
            return order.basePrice;
            // 경매 방식 일때
        } else {
            // Sell with declining price 방식 일때
            if (order.basePrice > order.endPrice) {
                return
                    order.basePrice -
                    ((block.timestamp - order.listingTime) *
                        (order.basePrice - order.endPrice)) /
                    (order.expirationTime - order.listingTime);
                // Sell to highest bidder 방식 일때
            } else {
                if (order.saleSide == SaleSide.SELL) {
                    return order.basePrice;
                } else {
                    return order.endPrice;
                }
            }
        }
    }

    function getFeePrice(uint256 price) internal pure returns (uint256) {
        return price / 40;
    }

    function executeFundsTransfer(
        Order memory buy,
        Order memory sell
    ) internal {
        if (sell.paymentToken != address(0)) {
            require(msg.value == 0);
        }

        uint256 price = calculateMatchPrice(buy, sell);
        uint256 fee = getFeePrice(price);

        if (price == 0) {
            return;
        }

        // ERC-20을 전송해야 하는 경우
        if (sell.paymentToken != address(0)) {
            // NFT 가격 전송
            IERC20(sell.paymentToken).transferFrom(
                buy.maker,
                sell.maker,
                price
            );
            // 수수료 전송
            IERC20(sell.paymentToken).transferFrom(buy.maker, feeAddress, fee);
        } else {
            // 이더를 전송해야 하는 경우
            require(msg.sender == buy.maker);

            (bool result, ) = sell.maker.call{value: price}("");
            require(result);
            (result, ) = feeAddress.call{value: fee}("");
            require(result);

            uint256 remain = msg.value - price - fee;
            if (remain > 0) {
                (result, ) = msg.sender.call{value: remain}("");
                require(result);
            }
        }
    }

    // 서로의 주문이 매칭이 되는지 확인
    function orderCanMatch(
        Order memory buy,
        Order memory sell
    ) internal view returns (bool) {
        // Sell to highest bidder 방식
        if (
            sell.saleKind == SaleKind.AUTION_PRICE &&
            sell.basePrice <= sell.endPrice
        ) {
            require(msg.sender == sell.maker);
        }
        return
            (buy.taker == address(0) || buy.taker == sell.maker) &&
            (sell.taker == address(0) || buy.maker == sell.taker) &&
            (buy.saleSide == SaleSide.BUY && sell.saleSide == SaleSide.SELL) &&
            (buy.saleKind == sell.saleKind) &&
            (buy.target == sell.target) &&
            (buy.paymentToken == sell.paymentToken) &&
            (buy.basePrice == sell.basePrice) &&
            //  Sell to highest bidder 방식
            (sell.saleKind == SaleKind.FIXED_PRICE ||
                sell.basePrice <= sell.endPrice ||
                buy.endPrice == sell.endPrice) &&
            (canSettleOrder(buy) && canSettleOrder(sell));
    }

    // 주문의 유효시간을 체크
    function canSettleOrder(Order memory order) internal view returns (bool) {
        // expirationTime 은 optional이여서 0이 될수 도 있다
        return ((order.listingTime <= block.timestamp &&
            order.expirationTime == 0) ||
            order.expirationTime >= block.timestamp);
    }

    // 주문을 검증
    function validateOrder(
        Order memory order,
        Sig memory sig
    ) internal view returns (bytes32 orderHash) {
        if (msg.sender != order.maker) {
            orderHash = validateOrderSig(order, sig);
        }

        require(order.exchange == address(this));

        if (order.saleKind == SaleKind.AUTION_PRICE) {
            require(order.expirationTime > order.listingTime);
        }
    }

    // 서명을 검증?
    function validateOrderSig(
        Order memory order,
        Sig memory sig
    ) internal view returns (bytes32 orderHash) {
        bytes32 sigMessage;
        (orderHash, sigMessage) = orderSigMessage(order);

        require(ecrecover(sigMessage, sig.v, sig.r, sig.s) == order.maker);
    }

    // 해쉬값 구하기
    function hashOrder(Order memory order) public pure returns (bytes32 hash) {
        return
            keccak256(
                abi.encodePacked(
                    // callStack에 저장될 수 있는 인자의 개수는 최대 16개이다
                    abi.encode(
                        ORDER_TYPEHASH,
                        order.exchange,
                        order.maker,
                        order.taker,
                        order.saleSide, // bytes크기는 가변적이기 때문에 keccak256으로 해싱해야 한다.
                        order.saleKind,
                        order.target,
                        order.paymentToken,
                        keccak256(order.callData_),
                        keccak256(order.replacementPattern)
                    ),
                    abi.encode(
                        order.listingTime,
                        order.expirationTime,
                        order.basePrice,
                        order.endPrice,
                        order.salt
                    )
                )
            );
    }

    function guardedArrayReplace(
        bytes memory array,
        bytes memory desired,
        bytes memory mask
    ) internal pure {
        require(array.length == desired.length);
        require(array.length == mask.length);

        uint words = array.length / 0x20;
        uint index = words * 0x20;
        assert(index / 0x20 == words);
        uint i;

        for (i = 0; i < words; i++) {
            /* Conceptually: array[i] = (!mask[i] && array[i]) || (mask[i] && desired[i]), bitwise in word chunks. */
            assembly {
                let commonIndex := mul(0x20, add(1, i))
                let maskValue := mload(add(mask, commonIndex))
                mstore(
                    add(array, commonIndex),
                    or(
                        and(not(maskValue), mload(add(array, commonIndex))),
                        and(maskValue, mload(add(desired, commonIndex)))
                    )
                )
            }
        }

        /* Deal with the last section of the byte array. */
        if (words > 0) {
            /* This overlaps with bytes already set but is still more efficient than iterating through each of the remaining bytes individually. */
            i = words;
            assembly {
                let commonIndex := mul(0x20, add(1, i))
                let maskValue := mload(add(mask, commonIndex))
                mstore(
                    add(array, commonIndex),
                    or(
                        and(not(maskValue), mload(add(array, commonIndex))),
                        and(maskValue, mload(add(desired, commonIndex)))
                    )
                )
            }
        } else {
            /* If the byte array is shorter than a word, we must unfortunately do the whole thing bytewise.
               (bounds checks could still probably be optimized away in assembly, but this is a rare case) */
            for (i = index; i < array.length; i++) {
                array[i] =
                    ((mask[i] ^ 0xff) & array[i]) |
                    (mask[i] & desired[i]);
            }
        }
    }

    function orderSigMessage(
        Order memory order
    ) internal view returns (bytes32 orderHash, bytes32 sigMessage) {
        orderHash = hashOrder(order);
        sigMessage = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPERATOR, orderHash)
        );
    }
}
