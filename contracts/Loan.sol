pragma solidity 0.4.24;

import "./LoanFactory.sol";
import "./SafeMath.sol";

contract Loan {
    using SafeMath for uint256;

    enum LoanStatus {
        Pending,
        Active,
        InterestPayment,
        MarginCall,
        MarginCallInDefault,
        PrincipalRepaymentDefault,
        Matured,
        Completed
    }

    struct Lender {
        bytes32 id;
        bytes32 orderId;
        bytes32 lenderUserId;
        uint256 amount;
        uint256 price;
        uint256 weight;
    }

    struct Interest {
        uint256 paymentTime;
        uint256 amount;
        bool paid;
    }

    LoanFactory public loanFactory;
    uint256 public tenor;
    uint256 public principalAmount;
    uint256 public collateralAmount;
    uint256 public createdTime;
    uint256 public lowerRequiredMargin;
    uint256 public higherRequiredMargin;
    uint256 public lastMarginTime;
    uint256 public constant WEIGHT_DIVISOR = 10000;
    bytes32 public constant INTEREST_CURRENCY = 0x4c4e44;
    bytes32 public borrowerUserId;
    bytes32 public holdingUserId;
    bytes32 public escrowUserId;
    bytes32 public liquidatorUserId;
    bytes32 public id;
    bytes32 public orderId;
    bytes32 public principalCurrency;
    bytes32 public collateralCurrency;
    LoanStatus public status;
    Lender[] public lenders;
    Interest[] public interest;
    uint256 public transferRecordsId;
    bytes32[] public transferRecords;
    bytes32 public constant DEFAULT_TRANSFER_RECORD = 0xdeadbeef;

    event Transfer(bytes32 from, bytes32 to, uint256 amount, bytes32 currency, uint256 transferRecordsId, string functionName);

    modifier onlyOwner() {
        require(msg.sender == loanFactory.owner());
        _;
    }

    modifier onlyWorker() {
        require(msg.sender == loanFactory.worker());
        _;
    }

    constructor(
        uint256[7] newLoanUintInput,
        bytes32[8] newLoanBytesInput
    )
        public
    {
        loanFactory = LoanFactory(msg.sender);
        tenor = newLoanUintInput[0];
        principalAmount = newLoanUintInput[1];
        collateralAmount = newLoanUintInput[2];
        createdTime = newLoanUintInput[3];
        lowerRequiredMargin = newLoanUintInput[4];
        higherRequiredMargin = newLoanUintInput[5];
        lastMarginTime = newLoanUintInput[6];
        borrowerUserId = newLoanBytesInput[0];
        holdingUserId = newLoanBytesInput[1];
        escrowUserId = newLoanBytesInput[2];
        liquidatorUserId = newLoanBytesInput[3];
        id = newLoanBytesInput[4];
        orderId = newLoanBytesInput[5];
        principalCurrency = newLoanBytesInput[6];
        collateralCurrency = newLoanBytesInput[7];
    }

    function() external {
        revert();
    }

    function changeInterest(uint256 paymentTime, uint256 amount, bool paid, uint256 interestId)
        external
        onlyOwner
    {
        interest[interestId].paymentTime = paymentTime;
        interest[interestId].amount = amount;
        interest[interestId].paid = paid;
    }

    function changeStatus(LoanStatus _status)
        external
        onlyOwner
    {
        status = _status;
    }


    function addLenders(
        uint256[] lenderUintInput,
        bytes32[] lenderBytesInput
    )
        external
        onlyWorker
    {
        require(status == LoanStatus.Pending);
        for (uint256 i = 0; i < lenderUintInput.length / 3; i++) {
            lenders.push(Lender({
                id: lenderBytesInput[3 * i + 0],
                orderId: lenderBytesInput[3 * i + 1],
                lenderUserId: lenderBytesInput[3 * i + 2],
                amount: lenderUintInput[3 * i + 0],
                price: lenderUintInput[3 * i + 1],
                weight: lenderUintInput[3 * i + 2]
            }));
        }
    }

    function addInterest(
        uint256[] paymentTime,
        uint256[] amount
    )
        external
        onlyWorker
    {
        require(status == LoanStatus.Pending);
        for (uint256 i = 0; i < paymentTime.length; i++) {
            interest.push(Interest({
                paymentTime: paymentTime[i],
                amount: amount[i],
                paid: false
            }));
        }
    }

    function start()
        external
        onlyWorker
    {
        require(status == LoanStatus.Pending);
        status = LoanStatus.Active;
        emit Transfer(holdingUserId, borrowerUserId, principalAmount, principalCurrency, transferRecordsId++, "start");
        emit Transfer(holdingUserId, escrowUserId, collateralAmount, collateralCurrency, transferRecordsId++, "start");
    }

    function addTransferRecords(bytes32[] _transferRecords)
        external
        onlyWorker
    {
        for (uint256 i = 0; i < _transferRecords.length; i++) {
            transferRecords.push(_transferRecords[i]);
        }
        require(transferRecords.length <= transferRecordsId);
    }

    function payInterest(uint256 interestId)
        external
        onlyWorker
    {
        require(status == LoanStatus.Active);
        if (interestId > 0) {
            require(interest[interestId - 1].paid == true);
        }
        require(interest[interestId].paid == false);
        require(now >= interest[interestId].paymentTime);
        status = LoanStatus.InterestPayment;
        for (uint256 i = 0; i < lenders.length; i++) {
            uint256 interestToPay = interest[interestId].amount.mul(lenders[i].weight).div(WEIGHT_DIVISOR);
            emit Transfer(
                borrowerUserId,
                lenders[i].lenderUserId,
                interestToPay,
                INTEREST_CURRENCY,
                transferRecordsId++,
                "payInterest"
            );
        }
    }

    function interestPaid(uint256 interestId)
        external
        onlyWorker
    {
        require(status == LoanStatus.InterestPayment);
        if (interestId > 0) {
            require(interest[interestId - 1].paid == true);
        }
        require(interest[interestId].paid == false);
        require(transferRecords.length == transferRecordsId);
        require(transferRecords[transferRecordsId - 1] != DEFAULT_TRANSFER_RECORD);
        status = LoanStatus.Active;
    }

    function interestDefault(uint256 interestId, uint256 liquidateCollateralAmount)
        external
        onlyWorker
    {
        require(status == LoanStatus.InterestPayment);
        require(interest[interestId].paid == false);
        require(now > interest[interestId].paymentTime + loanFactory.interestLeadTime(collateralCurrency));
        require(transferRecords[transferRecordsId - 1] == DEFAULT_TRANSFER_RECORD);
        status = LoanStatus.Active;
        emit Transfer(
            escrowUserId,
            liquidatorUserId,
            liquidateCollateralAmount,
            collateralCurrency,
            transferRecordsId++,
            "interestDefault"
        );
        collateralAmount = collateralAmount.sub(liquidateCollateralAmount);
    }

    function marginDefault(uint256 _lowerRequiredMargin, uint256 _higherRequiredMargin, uint256 _lastMarginTime)
        external
        onlyWorker
    {
        require(status == LoanStatus.Active);
        lowerRequiredMargin = _lowerRequiredMargin;
        higherRequiredMargin = _higherRequiredMargin;
        lastMarginTime = _lastMarginTime;
        require(collateralAmount < lowerRequiredMargin);
        require(now > lastMarginTime + loanFactory.marginLeadTime(collateralCurrency));
        status = LoanStatus.MarginCallInDefault;
        emit Transfer(
            escrowUserId,
            liquidatorUserId,
            collateralAmount,
            collateralCurrency,
            transferRecordsId++,
            "marginDefault"
        );
    }

    function marginExcess(uint256 _lowerRequiredMargin, uint256 _higherRequiredMargin, uint256 _lastMarginTime)
        external
        onlyWorker
    {
        require(status == LoanStatus.Active);
        lowerRequiredMargin = _lowerRequiredMargin;
        higherRequiredMargin = _higherRequiredMargin;
        lastMarginTime = _lastMarginTime;
        require(collateralAmount > _higherRequiredMargin);
        uint256 releaseAmount = collateralAmount.sub((lowerRequiredMargin.add(higherRequiredMargin)).div(2));
        emit Transfer(
            escrowUserId,
            borrowerUserId,
            releaseAmount,
            collateralCurrency,
            transferRecordsId++,
            "marginExcess"
        );
        collateralAmount = collateralAmount.sub(releaseAmount);
    }

    function mature()
        external
        onlyWorker
    {
        require(status == LoanStatus.Active);
        require(now >= createdTime + tenor);
        require(transferRecords.length == transferRecordsId);
        status = LoanStatus.Matured;
        emit Transfer(
            borrowerUserId,
            escrowUserId,
            principalAmount,
            principalCurrency,
            transferRecordsId++,
            "mature"
        );
    }

    function matureDefault()
        external
        onlyWorker
    {
        require(status == LoanStatus.Matured);
        require(now >= createdTime + tenor + loanFactory.matureLeadTime(collateralCurrency));
        require(transferRecords[transferRecordsId - 1] == DEFAULT_TRANSFER_RECORD);
        status = LoanStatus.PrincipalRepaymentDefault;
        emit Transfer(
            escrowUserId,
            liquidatorUserId,
            collateralAmount,
            collateralCurrency,
            transferRecordsId++,
            "matureDefault"
        );
    }

    function completeLiquidation(uint256 principalRecovered)
        external
        onlyWorker
    {
        require(status == LoanStatus.MarginCallInDefault || status == LoanStatus.PrincipalRepaymentDefault);
        require(transferRecords.length == transferRecordsId);
        require(transferRecords[transferRecordsId - 1] != DEFAULT_TRANSFER_RECORD);
        status = LoanStatus.Completed;
        for (uint256 i = 0; i < lenders.length; i++) {
            uint256 principalToReturn = principalRecovered.mul(lenders[i].weight).div(WEIGHT_DIVISOR);
            emit Transfer(
                escrowUserId,
                lenders[i].lenderUserId,
                principalToReturn,
                principalCurrency,
                transferRecordsId++,
                "completeLiquidation"
            );
        }
    }

    function completeMature()
        external
        onlyWorker
    {
        require(status == LoanStatus.Matured);
        require(transferRecords.length == transferRecordsId);
        require(transferRecords[transferRecordsId - 1] != DEFAULT_TRANSFER_RECORD);
        status = LoanStatus.Completed;
        emit Transfer(
            escrowUserId,
            borrowerUserId,
            collateralAmount,
            collateralCurrency,
            transferRecordsId++,
            "complete"
        );
        for (uint256 i = 0; i < lenders.length; i++) {
            uint256 principalToReturn = principalAmount.mul(lenders[i].weight).div(WEIGHT_DIVISOR);
            emit Transfer(
                escrowUserId,
                lenders[i].lenderUserId,
                principalToReturn,
                principalCurrency,
                transferRecordsId++,
                "complete"
            );
        }
    }
}
