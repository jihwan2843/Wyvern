// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >0.8.0 <=0.9.9;

enum SaleSide {
    BUY,
    SELL
}
enum SaleKind {
    FIXED_PRICE,
    AUTION_PRICE
}
struct Order {
    address exchange;
    address maker;
    address taker;
    SaleSide saleSide;
    SaleKind saleKind;
    address target;
    address paymentToken;
    bytes callData_;
    bytes replacementPattern;
    uint256 listingTime;
    uint256 expirationTime;
    uint256 basePrice;
    uint256 endPrice;
    uint256 salt;
}
