//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

// TODO
// cannot claim prize bc NFTs nontransferable, MUSTFIX lol

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MintChaos is ERC721Enumerable, Ownable {
    uint256 public currentMintPrice = 0.00042 ether;
    uint256 public constant MIN_PRICE = 0.00000042 ether;
    uint256 public nextTokenId = 0;
    uint8 public constant ARRAY_LENGTH = 5;
    uint8 public MAX_NUMBER = 2;

    // Mapping: tokenId => position => number
    mapping(uint256 => uint256[ARRAY_LENGTH]) public tokenMetadata;

    // Mapping: user => position => number => count
    mapping(address => mapping(uint8 => mapping(uint8 => uint256))) public userNumberCounts;

    uint256 public prizePool;
    uint256 public contractBalance;

    mapping(address => bool) public isWinner;

    constructor() ERC721("MintChaos", "CHAOS") {}

    function mint() public payable {
        require(msg.value >= currentMintPrice, "Insufficient ETH sent");

        uint256 tokenId = nextTokenId;
        _safeMint(msg.sender, tokenId);
        
        uint256[ARRAY_LENGTH] memory randomNumbers;
        for (uint8 i = 0; i < ARRAY_LENGTH; i++) {
            randomNumbers[i] = (uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, i))) % MAX_NUMBER) + 1;
            userNumberCounts[msg.sender][i][uint8(randomNumbers[i])]++;
        }
        
        tokenMetadata[tokenId] = randomNumbers;
        nextTokenId++;

        // Add to prize pool
        prizePool += currentMintPrice / 2;
        // Add to contract balance
        contractBalance += currentMintPrice / 2;

        uint256 excess = msg.value - currentMintPrice;
        if (excess > 0) {
            payable(msg.sender).transfer(excess);
        }
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
        
        if (from != address(0)) { // Not minting
            require(!isWinner[from], "Winner cannot transfer NFTs");
            for (uint8 i = 0; i < ARRAY_LENGTH; i++) {
                uint8 number = uint8(tokenMetadata[tokenId][i]);
                if (userNumberCounts[from][i][number] > 0) {
                    userNumberCounts[from][i][number]--;
                }
            }
        }
        
        if (to != address(0)) { // Not burning
            for (uint8 i = 0; i < ARRAY_LENGTH; i++) {
                uint8 number = uint8(tokenMetadata[tokenId][i]);
                userNumberCounts[to][i][number]++;
            }
            updatePotentialWins(to, tokenMetadata[tokenId]);
        }
    }

    function updatePotentialWins(address user, uint256[ARRAY_LENGTH] memory newTokenNumbers) internal {
        if (isWinner[user]) return; // Already a winner, no need to check

        for (uint8 i = 0; i < ARRAY_LENGTH; i++) {
            uint8 number = uint8(newTokenNumbers[i]);
            bool hasAllPositions = true;
            for (uint8 j = 0; j < ARRAY_LENGTH; j++) {
                if (userNumberCounts[user][j][number] == 0) {
                    hasAllPositions = false;
                    break;
                }
            }
            if (hasAllPositions) {
                isWinner[user] = true;
                return;
            }
        }
    }

    function checkWinner(address user) public view returns (bool) {
        return isWinner[user];
    }

    function getTokenMetadata(uint256 tokenId) public view returns (uint256[ARRAY_LENGTH] memory) {
        require(_exists(tokenId), "Token does not exist");
        return tokenMetadata[tokenId];
    }

    function getUserNumberCounts(address user, uint8 position) public view returns (uint256[] memory) {
        uint256[] memory counts = new uint256[](MAX_NUMBER);
        for (uint8 i = 1; i <= MAX_NUMBER; i++) {
            counts[i-1] = userNumberCounts[user][position][i];
        }
        return counts;
    }

    function getAllUserNumberCounts(address user) public view returns (uint256[][] memory) {
        uint256[][] memory allCounts = new uint256[][](ARRAY_LENGTH);
        for (uint8 position = 0; position < ARRAY_LENGTH; position++) {
            allCounts[position] = new uint256[](MAX_NUMBER);
            for (uint8 number = 1; number <= MAX_NUMBER; number++) {
                allCounts[position][number-1] = userNumberCounts[user][position][number];
            }
        }
        return allCounts;
    }

    function transferFrom(address from, address to, uint256 tokenId) public override(ERC721, IERC721) {
        require(!isWinner[from], "Winner cannot transfer NFTs");
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public override(ERC721, IERC721) {
        require(!isWinner[from], "Winner cannot transfer NFTs");
        super.safeTransferFrom(from, to, tokenId, _data);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override(ERC721, IERC721) {
        require(!isWinner[from], "Winner cannot transfer NFTs");
        super.safeTransferFrom(from, to, tokenId);
    }

    function withdraw() public onlyOwner {
        uint256 amount = contractBalance;
        contractBalance = 0;
        (bool success, ) = owner().call{value: amount}("");
        require(success, "Failed to send Ether");
    }

    function claimPrize() public {
        require(checkWinner(msg.sender), "Not a winner");
        
        uint256 prize = prizePool / 2;
        prizePool -= prize;

        // Burn all NFTs owned by the winner
        uint256 balance = balanceOf(msg.sender);
        for (uint256 i = balance; i > 0; i--) {
            uint256 tokenId = tokenOfOwnerByIndex(msg.sender, i - 1);
            _burn(tokenId);
        }

        // Increase difficulty
        MAX_NUMBER++;

        // Adjust the mint price
        if (currentMintPrice > MIN_PRICE) {
            currentMintPrice = currentMintPrice - (nextTokenId * (MIN_PRICE / 10));
            if (currentMintPrice < MIN_PRICE) {
                currentMintPrice = MIN_PRICE;
            }
        }

        // Transfer prize
        payable(msg.sender).transfer(prize);
    }
}

