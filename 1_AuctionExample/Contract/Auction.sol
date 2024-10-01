// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Auction {
    address internal auction_owner; //소유자(배포자) 지갑주소, 외부에서 접근은 안됨
    uint256 public auction_start; // 경매 시작 시간
    uint256 public auction_end; // 경매 종료 시간
    uint256 public highestBid; // 최고 가액
    address public highestBidder;// 최고가 경매입찰자 주소
    address public winnerBidder;// 경매 최종 입찰자

    enum auction_state {
        CANCELLED,STARTED,SUCCESS
    }

    struct car {
        string Brand; // 브랜드
        string Rnumber; // 차량 번호판
    }

    car public Mycar;
    address[] bidders; // 입찰자들(식별자 : 지갑 주소)
    mapping(address => uint) public bids;// 지갑 주소별 : 입찰 금액
    auction_state public STATE;

    // 경매가 진행 중인지 확인하는 modifier
    modifier an_ongoing_auction() {
        require(STATE == auction_state.STARTED, "msg:Auction has ended"); // 경매가 시작된 상태인지 확인
        require(block.timestamp <= auction_end, "msg:Auction has ended");     // 경매 종료 시간을 넘지 않았는지 확인
        _;
    }

    //경매가 끝났는지 체크하는 modifier CANCELED,SUCCESS 둘의 상태
    modifier auction_ended() {
        require(STATE != auction_state.STARTED, "msg:Auction is still"); // 경매가 시작된 상태인지 확인
        // require(block.timestamp > auction_end, "msg:Auction is still ");
        _;
    }

    // 경매 소유자만 호출할 수 있는 modifier
    modifier only_owner() {
        require(msg.sender == auction_owner, "Only auction owner can call this");
        _;
    }

    


    // 함수 선언에 virtual 키워드 추가
    // 자식에서 override해서 사용한다.
    function bid() public payable virtual returns (bool) {} // 입찰 msg.sender => address , 금액
    function withdraw() public virtual returns (bool) {} // 입찰이 안된사람들 돌려주기
    function cancel_auction() external virtual returns (bool) {}

    // 이벤트 선언
    event BidEvent(address indexed highestBidder, uint256 highestBid);// 최고 입찰자
    event WithdrawalEvent(address withdrawer, uint256 amount); // 금액 돌려줄때
    event CanceledEvent(uint message, uint256 time); // 취소했을때
    event StateUpdated(auction_state newState); // 상태 업데이트 이벤트 추가
    event ContractSucc(address winnerBidder , uint highestBid); // 계약 완료
}
contract MyAuction is Auction {

    // 생성자
    // biddingTime 언제 까지할거냐
    constructor(uint _biddingTime, address _owner, string memory _brand, string memory _Rnumber) {
        auction_owner = _owner; // 처음에 생성 할떄 owner 
        auction_start = block.timestamp; // unix타임 기준
        auction_end = auction_start + _biddingTime * 1 hours; // unix타임으로 관리된다.
        STATE = auction_state.STARTED;
        Mycar.Brand = _brand; // 3번째 변수 기억
        Mycar.Rnumber = _Rnumber; // 4번째 변수 기억
    }

    // 입찰을 할때, 부모 컨트랙트의 bid 함수 재정의 (override)
    function bid() public payable override an_ongoing_auction returns (bool) {
        // 1. 최고 입찰자가 다시 입찰하려는 경우
        if (msg.sender == highestBidder) {
            revert("msg:curr_maximum");  // 에러 메시지: "현재 최고 입찰자입니다."
        }
        
        // 2. 현재 입찰 금액이 최고 입찰 금액보다 작거나 같을 경우
        if (bids[msg.sender] + msg.value <= highestBid) {
            revert("msg:not_enough");  // 에러 메시지: "입찰 금액이 충분하지 않습니다."
        }

        // 3. 최고 입찰자와 입찰 금액 업데이트
        // 동일한 금액 입찰은 막고, 높은 금액이 입찰된 경우만 업데이트
        highestBidder = msg.sender;  // 새로운 최고 입찰자
        highestBid = bids[msg.sender] + msg.value;  // 새로운 최고 입찰 금액
        
        // 4. 입찰 내역 업데이트
        if (bids[msg.sender] == 0) {
            bidders.push(msg.sender);  // 새로운 입찰자는 리스트에 추가
        }
        bids[msg.sender] += msg.value;  // 입찰 금액 갱신
        
        // 5. 입찰 이벤트 발행
        emit BidEvent(highestBidder, highestBid);

        return true;
    }


    // 부모 컨트랙트의 cancel_auction 함수 재정의 (override)
    function cancel_auction() external override only_owner an_ongoing_auction returns (bool) {
        STATE = auction_state.CANCELLED;
        emit CanceledEvent(1, block.timestamp);
        return true;
    }

     // 경매 완료 (selfdestruct 대신 사용)
    function contractSucc() external only_owner {
        STATE = auction_state.SUCCESS;

        // 계좌 잔액 확인
        uint balance = address(this).balance;
        require(balance > 0, "No funds left in the contract");

        // 최고가 입찰 확인
        uint amount = highestBid;
        winnerBidder = highestBidder;

        // 경매 소유주에게 전송
        (bool success, ) = payable(auction_owner).call{value: amount}("");

        require(success, "Transfer to auction owner failed");

        emit ContractSucc(winnerBidder, highestBid);
    }

    // 경매 비활성화 (selfdestruct 대신 사용)
    function deactivateAuction() external only_owner {
        require(block.timestamp > auction_end, "Auction is still ongoing"); //시간만 비교
        STATE = auction_state.CANCELLED;
        emit CanceledEvent(2, block.timestamp);
    }


    // 경매 소유자가 남은 자금을 회수하는 함수
    function withdrawRemainingFunds() external only_owner {
        uint balance = address(this).balance;
        require(balance > 0, "No funds left in the contract");

        (bool success, ) = payable(auction_owner).call{value: balance}("");
        require(success, "Transfer failed");
    }

    // 출금 함수 (입찰자들이 자금을 출금)
    function withdraw() public override auction_ended returns (bool) {
        uint amount = bids[msg.sender];
        require(amount > 0, "No funds to withdraw");

        bids[msg.sender] = 0;

        // 안전한 전송 방법 사용
        // (bool success, ) = payable(msg.sender).call{value: amount}("");
        (bool success, ) = payable(msg.sender).call{value: amount, gas: 5000}(""); 

        require(success, "Transfer failed");

        emit WithdrawalEvent(msg.sender, amount);
        return true;
    }

    // 소유자 정보 반환 함수
    function get_owner() public view returns (address) {
        return auction_owner;
    }

    // 경매 상태를 업데이트하는 함수
    function updateAuctionState(auction_state newState) external only_owner {
        STATE = newState;
        emit StateUpdated(newState); // 상태 업데이트 이벤트 발생
    }
}