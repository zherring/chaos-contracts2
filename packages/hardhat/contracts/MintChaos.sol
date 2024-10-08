//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;


import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MintChaos is ERC721Enumerable, Ownable  {
    uint256 public currentMintPrice = 0.00042 ether;
    uint256 public constant MIN_PRICE = 0.00000042 ether;
    uint256 public nextTokenId = 0;
    uint8 public constant ARRAY_LENGTH = 5;
    uint8 public POSSIBLE_SETS = 5;

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
        
        uint256[ARRAY_LENGTH] memory randomNumbers = getRandomNumbers(tokenId);
        for (uint8 i = 0; i < ARRAY_LENGTH; i++) {
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
            require(!isWinner[from] || to == address(0), "Winner cannot transfer NFTs except for burning");
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

        for (uint8 number = 1; number <= POSSIBLE_SETS; number++) {
            bool hasCompleteSet = true;
            for (uint8 position = 0; position < ARRAY_LENGTH; position++) {
                if (userNumberCounts[user][position][number] == 0) {
                    hasCompleteSet = false;
                    break;
                }
            }
            if (hasCompleteSet) {
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
        uint256[] memory counts = new uint256[](POSSIBLE_SETS);
        for (uint8 i = 1; i <= POSSIBLE_SETS; i++) {
            counts[i-1] = userNumberCounts[user][position][i];
        }
        return counts;
    }

    function getAllUserNumberCounts(address user) public view returns (uint256[][] memory) {
        uint256[][] memory allCounts = new uint256[][](ARRAY_LENGTH);
        for (uint8 position = 0; position < ARRAY_LENGTH; position++) {
            allCounts[position] = new uint256[](POSSIBLE_SETS);
            for (uint8 number = 1; number <= POSSIBLE_SETS; number++) {
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
    require(isWinner[msg.sender], "Not a winner");
    
    uint256 prize = prizePool * 90 / 100;  // 90% of the prize pool
    prizePool -= prize;  // Reduce prize pool by 90%

    // Burn all NFTs owned by the winner
    uint256 balance = balanceOf(msg.sender);
    for (uint256 i = balance; i > 0; i--) {
        uint256 tokenId = tokenOfOwnerByIndex(msg.sender, i - 1);
        _burn(tokenId);
    }

    // Reset winner status
    isWinner[msg.sender] = false;

    // Increase difficulty
    POSSIBLE_SETS++;

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

function getRandomNumbers(uint256 tokenID) public view returns (uint256[ARRAY_LENGTH] memory) {
        
    uint256 seed = uint256(keccak256(abi.encodePacked(
        block.number,
        block.basefee,
        blockhash(block.number - 1),
        tokenID
    )));
    
    uint256[ARRAY_LENGTH] memory numbers;
    for (uint8 i = 0; i < ARRAY_LENGTH; i++) {
        numbers[i] = (uint256(keccak256(abi.encodePacked(seed, i))) % POSSIBLE_SETS) + 1;
    }
    return numbers;
}
}

