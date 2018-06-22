const LoanFactory = artifacts.require('LoanFactory');
const Loan = artifacts.require('Loan');
const {assertEventContain, assertEventFired, loanGenerator} = require('./utils.js');

contract('Loan', (accounts) => {
  it('should emit `TransferExpected` event with correct parameters when `expectTransfer()` called', async () => {
    //Create a new loan contract
    const loanFactory = await LoanFactory.deployed();
    const loan = loanGenerator();
    const _tx = await loanFactory.createLoan(...(loan.formatToContractArgs()));

    //Call `expectTransfer() on it
    const address = _tx.logs[0].args.contractAddress;
    const tx = await Loan.at(address).expectTransfer(
      loan.borrowerUserId,
      loan.meta.holdingUserId,
      loan.meta.collateralAmount,
      loan.meta.collateralCurrency,
      'initiation'
    );

    assertEventFired(tx, 'TransferExpected');
    assertEventContain(tx, {fieldName: 'from'}, loan.borrowerUserId);
    assertEventContain(tx, {fieldName: 'to'}, loan.meta.holdingUserId);
    assertEventContain(tx, {fieldName: 'amount', fieldType: 'uint'}, loan.meta.collateralAmount);
    assertEventContain(tx, {fieldName: 'currency', fieldType: 'bytes32'}, loan.meta.collateralCurrency);
    assertEventContain(tx, {fieldName: 'reason', fieldType: 'string'}, 'initiation');
  });

});