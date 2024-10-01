const alertMsg = (msg) => {
  alert(msg);
};

const web3 = new Web3('ws://localhost:7545');

let bidder;
const userWalletAddress = '0x2f151B7E00e678f347882E9270Ce342bc2B44FF8';

async function initializeAccount() {
  try {
    const accounts = await web3.eth.getAccounts();
    console.log(accounts);
    web3.eth.defaultAccount = userWalletAddress;
    bidder = userWalletAddress;
  } catch (error) {
    console.error('Failed to initialize account:', error);
  }
}

async function loadABI() {
  try {
    const response = await fetch('contractABI.json');
    return await response.json();
  } catch (error) {
    console.error('Failed to load ABI:', error);
    throw error;
  }
}

function getContractIdFromURL() {
  const urlParams = new URLSearchParams(window.location.search);
  const contractId = urlParams.get('contractId');
  console.log(contractId ? `Contract ID: ${contractId}` : 'No contract ID found in the URL.');
  return contractId;
}

async function initContract() {
  const abi = await loadABI();
  const contractId = getContractIdFromURL();
  const defaultContractAddress = '0xd61AAA6Fe4A77Bfcd293Db089A286805a7700981';
  const contractAddress = contractId || defaultContractAddress;
  console.log('Contract initialized with address:', contractAddress);
  return new web3.eth.Contract(abi, contractAddress);
}

async function updateAuctionInfo(auctionContract) {
  try {
    const [auctionEnd, highestBidder, highestBid, state, car] = await Promise.all([
      auctionContract.methods.auction_end().call(),
      auctionContract.methods.highestBidder().call(),
      auctionContract.methods.highestBid().call(),
      auctionContract.methods.STATE().call(),
      auctionContract.methods.Mycar().call()
    ]);

    document.getElementById("auction_end").innerHTML = auctionEnd;
    document.getElementById("HighestBidder").innerHTML = highestBidder;
    document.getElementById("HighestBid").innerHTML = web3.utils.fromWei(highestBid, 'ether');
    document.getElementById("STATE").innerHTML = state;
    document.getElementById("car_brand").innerHTML = car[0];
    document.getElementById("registration_number").innerHTML = car[1];

    const myBid = await auctionContract.methods.bids(bidder).call();
    document.getElementById("MyBid").innerHTML = web3.utils.fromWei(myBid, 'ether');
  } catch (error) {
    console.error('Failed to update auction info:', error);
  }
}

async function bid(auctionContract) {
  const mybid = document.getElementById('value').value;
  try {
    const result = await auctionContract.methods.bid().send({
      from: userWalletAddress,
      value: web3.utils.toWei(mybid, "ether"),
      gas: 200000
    });
    document.getElementById("biding_status").innerHTML = `Successful bid, transaction ID: ${result.transactionHash}`;
  } catch (error) {
    handleBidError(error);
  }
}

function handleBidError(error) {
  if (error.message.includes("not_enough")) {
    alert("현재 최고가 보다 낮은 금액을 입력하셨습니다.");
  } else if (error.message.includes("curr_maximum")) {
    alert("입찰자 중 현재 최고 금액 입찰 중이십니다.");
  } else {
    alert("에러 발생 console 참고");
    console.error(error);
  }
  document.getElementById("biding_status").innerHTML = `Bid failed: ${error.message}`;
}

async function cancel_auction(auctionContract) {
  try {
    const result = await auctionContract.methods.cancel_auction().send({ from: userWalletAddress, gas: 200000 });
    console.log(result);
  } catch (error) {
    console.error('Failed to cancel auction:', error);
  }
}

async function withdraw(auctionContract) {
  try {
    const result = await auctionContract.methods.withdraw().send({ from: userWalletAddress, gas: 200000 });
    document.getElementById("withdraw_status").innerHTML = `Withdraw successful, transaction ID: ${result.transactionHash}`;
  } catch (error) {
    console.error('Withdraw failed:', error);
    document.getElementById("withdraw_status").innerHTML = `Withdraw failed: ${error.message}`;
  }
}

function setupEventListeners(auctionContract) {
  auctionContract.events.BidEvent()
    .on("connected", (subscriptionId) => console.log(subscriptionId))
    .on('data', (event) => {
      $("#eventslog").html(`${event.returnValues.highestBidder} has bid (${event.returnValues.highestBid} wei)`);
    })
    .on('error', console.error);

  auctionContract.events.CanceledEvent()
    .on("connected", (subscriptionId) => console.log(subscriptionId))
    .on('data', (event) => {
      $("#eventslog").html(`${event.returnValues.message} at ${event.returnValues.time}`);
    })
    .on('error', console.error);

  auctionContract.events.WithdrawalEvent()
    .on('data', (event) => {
      document.getElementById("STATE").innerHTML = event.returnValues.newState;
      console.log("Auction state updated: ", event.returnValues.newState);
    })
    .on('error', console.error);
}

async function init() {
  try {
    await initializeAccount();
    const auctionContract = await initContract();
    await updateAuctionInfo(auctionContract);

    const auction_owner = await auctionContract.methods.get_owner().call();
    if (bidder !== auction_owner) {
      $("#auction_owner_operations").hide();
    }

    setupEventListeners(auctionContract);

    // Attach event handlers
    document.getElementById('bidButton').addEventListener('click', () => bid(auctionContract));
    document.getElementById('cancelButton').addEventListener('click', () => cancel_auction(auctionContract));
    document.getElementById('withdrawButton').addEventListener('click', () => withdraw(auctionContract));
  } catch (error) {
    console.error('Initialization failed:', error);
  }
}

init();