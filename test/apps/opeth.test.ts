import {
  MockERC20Instance,
  MarginCalculatorInstance,
  AddressBookInstance,
  MockOracleInstance,
  OtokenInstance,
  ControllerInstance,
  WhitelistInstance,
  MarginPoolInstance,
  OtokenFactoryInstance,
  OpethInstance,
} from '../../build/types/truffle-types'
import {createTokenAmount, createValidExpiry} from '../utils'
import BigNumber from 'bignumber.js'

const {time} = require('@openzeppelin/test-helpers')
const AddressBook = artifacts.require('AddressBook.sol')
const MockOracle = artifacts.require('MockOracle.sol')
const Otoken = artifacts.require('Otoken.sol')
const MockERC20 = artifacts.require('MockERC20.sol')
const MarginCalculator = artifacts.require('MarginCalculator.sol')
const Whitelist = artifacts.require('Whitelist.sol')
const MarginPool = artifacts.require('MarginPool.sol')
const Controller = artifacts.require('Controller.sol')
const MarginVault = artifacts.require('MarginVault.sol')
const OTokenFactory = artifacts.require('OtokenFactory.sol')
const Opeth = artifacts.require('Opeth.sol')
const ZERO_ADDR = '0x0000000000000000000000000000000000000000'

enum ActionType {
  OpenVault,
  MintShortOption,
  BurnShortOption,
  DepositLongOption,
  WithdrawLongOption,
  DepositCollateral,
  WithdrawCollateral,
  SettleVault,
  Redeem,
  Call,
}

contract('Opeth', ([accountOwner1, accountOwner2]) => {
  let expiry: number

  let addressBook: AddressBookInstance
  let calculator: MarginCalculatorInstance
  let controllerProxy: ControllerInstance
  let controllerImplementation: ControllerInstance
  let marginPool: MarginPoolInstance
  let whitelist: WhitelistInstance
  let otokenImplementation: OtokenInstance
  let otokenFactory: OtokenFactoryInstance

  // oracle modulce mock
  let oracle: MockOracleInstance

  let usdc: MockERC20Instance
  let weth: MockERC20Instance

  let putOToken: OtokenInstance
  let opeth: OpethInstance

  let vaultCounter2: number

  const strike = 200
  const optionsAmount = 15
  const usdcDecimals = 6
  const wethDecimals = 18

  async function assertBalances(account: string, expectedBalances: string[]) {
    const balances = await Promise.all([
      opeth.balanceOf(account),
      weth.balanceOf(account),
      putOToken.balanceOf(account),
      usdc.balanceOf(account),
    ])

    assert.equal(balances[0].toString(), expectedBalances[0])
    assert.equal(balances[1].toString(), expectedBalances[1])
    assert.equal(balances[2].toString(), expectedBalances[2])
    assert.equal(balances[3].toString(), expectedBalances[3])
  }

  before('set up contracts', async () => {
    const now = (await time.latest()).toNumber()
    expiry = createValidExpiry(now, 30)

    // setup usdc and weth
    usdc = await MockERC20.new('USDC', 'USDC', usdcDecimals)
    weth = await MockERC20.new('WETH', 'WETH', wethDecimals)

    // initiate addressbook first.
    addressBook = await AddressBook.new()
    // setup calculator
    calculator = await MarginCalculator.new(addressBook.address)
    // setup margin pool
    marginPool = await MarginPool.new(addressBook.address)
    // setup margin vault
    const lib = await MarginVault.new()
    // setup controllerProxy module
    await Controller.link('MarginVault', lib.address)
    controllerImplementation = await Controller.new(addressBook.address)
    // setup mock Oracle module
    oracle = await MockOracle.new(addressBook.address)
    // setup whitelist module
    whitelist = await Whitelist.new(addressBook.address)
    await whitelist.whitelistCollateral(usdc.address)
    await whitelist.whitelistCollateral(weth.address)
    whitelist.whitelistProduct(weth.address, usdc.address, usdc.address, true)
    whitelist.whitelistProduct(weth.address, usdc.address, weth.address, false)
    // setup otoken
    otokenImplementation = await Otoken.new()
    // setup factory
    otokenFactory = await OTokenFactory.new(addressBook.address)

    // setup address book
    await addressBook.setOracle(oracle.address)
    await addressBook.setMarginCalculator(calculator.address)
    await addressBook.setWhitelist(whitelist.address)
    await addressBook.setMarginPool(marginPool.address)
    await addressBook.setOtokenFactory(otokenFactory.address)
    await addressBook.setOtokenImpl(otokenImplementation.address)
    await addressBook.setController(controllerImplementation.address)

    const controllerProxyAddress = await addressBook.getController()
    controllerProxy = await Controller.at(controllerProxyAddress)

    await otokenFactory.createOtoken(
      weth.address,
      usdc.address,
      usdc.address,
      createTokenAmount(strike, 8),
      expiry,
      true,
    )

    const putOtokenAddress = await otokenFactory.getOtoken(
      weth.address,
      usdc.address,
      usdc.address,
      createTokenAmount(strike, 8),
      expiry,
      true,
    )

    putOToken = await Otoken.at(putOtokenAddress)

    // mint usdc to user
    const accountOwner2Usdc = createTokenAmount(strike * optionsAmount, usdcDecimals)

    await Promise.all([
      usdc.mint(accountOwner2, accountOwner2Usdc),
      usdc.approve(marginPool.address, accountOwner2Usdc, {from: accountOwner2}),
    ])

    const vaultCounter2Before = new BigNumber(await controllerProxy.getAccountVaultCounter(accountOwner2))
    vaultCounter2 = vaultCounter2Before.toNumber() + 1

    opeth = await Opeth.new()
    await opeth.init(controllerProxyAddress, putOtokenAddress)
  })

  describe('Integration test: Opeth mint/redeem', () => {
    const scaledOptionsAmount = createTokenAmount(optionsAmount, 8)
    before('accountOwner2 mints the put option, sends it to accountOwner1.', async () => {
      const collateralToMintLong = strike * optionsAmount
      const scaledCollateralToMintLong = createTokenAmount(collateralToMintLong, usdcDecimals)

      const actionArgsAccountOwner2 = [
        {
          actionType: ActionType.OpenVault,
          owner: accountOwner2,
          secondAddress: accountOwner2,
          asset: ZERO_ADDR,
          vaultId: vaultCounter2,
          amount: '0',
          index: '0',
          data: ZERO_ADDR,
        },
        {
          actionType: ActionType.MintShortOption,
          owner: accountOwner2,
          secondAddress: accountOwner2,
          asset: putOToken.address,
          vaultId: vaultCounter2,
          amount: scaledOptionsAmount,
          index: '0',
          data: ZERO_ADDR,
        },
        {
          actionType: ActionType.DepositCollateral,
          owner: accountOwner2,
          secondAddress: accountOwner2,
          asset: usdc.address,
          vaultId: vaultCounter2,
          amount: scaledCollateralToMintLong,
          index: '0',
          data: ZERO_ADDR,
        },
      ]

      await controllerProxy.operate(actionArgsAccountOwner2, {from: accountOwner2})

      // accountOwner2 transfers their put option to accountOwner1
      await putOToken.transfer(accountOwner1, scaledOptionsAmount, {from: accountOwner2})
    })

    it('mint', async () => {
      const scaledWethAmount = createTokenAmount(optionsAmount, 18)
      await Promise.all([
        weth.mint(accountOwner1, scaledWethAmount),
        weth.approve(opeth.address, scaledWethAmount, {from: accountOwner1}),
        putOToken.approve(opeth.address, scaledOptionsAmount, {from: accountOwner1}),
      ])
      await assertBalances(accountOwner1, [
        '0' /* opethBalance */,
        scaledWethAmount /* wethBalance */,
        scaledOptionsAmount /* oTokenBalance */,
        '0' /* usdcBalance */,
      ])

      await opeth.mint(scaledOptionsAmount, {from: accountOwner1})

      await assertBalances(accountOwner1, [
        scaledOptionsAmount /* opethBalance */,
        '0' /* wethBalance */,
        '0' /* oTokenBalance */,
        '0' /* usdcBalance */,
      ])
    })

    it('redeem when isSettlementAllowed == false', async () => {
      const _toRedeem = optionsAmount / 3
      const toRedeem = createTokenAmount(_toRedeem, 8)

      await opeth.redeem(toRedeem, {from: accountOwner1})

      await assertBalances(accountOwner1, [
        createTokenAmount((optionsAmount * 2) / 3, 8) /* opethBalance */,
        createTokenAmount(_toRedeem, 18) /* wethBalance */,
        toRedeem /* oTokenBalance */,
        '0' /* usdcBalance */,
      ])
    })

    it('redeem when isSettlementAllowed == true', async () => {
      // Set the oracle price
      if ((await time.latest()) < expiry) {
        await time.increaseTo(expiry + 2)
      }
      const expirySpotPrice = 180 // strike price was 200
      const scaledETHPrice = createTokenAmount(expirySpotPrice, 8)
      const scaledUSDCPrice = createTokenAmount(1)
      await oracle.setExpiryPriceFinalizedAllPeiodOver(weth.address, expiry, scaledETHPrice, true)
      await oracle.setExpiryPriceFinalizedAllPeiodOver(usdc.address, expiry, scaledUSDCPrice, true)

      const _toRedeem = optionsAmount / 3
      const toRedeem = createTokenAmount(_toRedeem, 8)
      await opeth.redeem(toRedeem, {from: accountOwner1})

      await assertBalances(accountOwner1, [
        createTokenAmount(optionsAmount / 3, 8) /* opethBalance */,
        createTokenAmount(2 * _toRedeem, 18) /* wethBalance */,
        toRedeem /* oTokenBalance - same as above */,
        createTokenAmount(_toRedeem * 20, 6), // usdcBalance = (200 - 180) * _toRedeem
      ])
    })

    it('redeem after settlement', async () => {
      const _toRedeem = optionsAmount / 3
      const toRedeem = createTokenAmount(_toRedeem, 8)
      await opeth.redeem(toRedeem, {from: accountOwner1})

      await assertBalances(accountOwner1, [
        '0' /* opethBalance */,
        createTokenAmount(optionsAmount, 18), // wethBalance
        toRedeem /* oTokenBalance - same as above */,
        createTokenAmount(_toRedeem * 20 * 2, 6), // usdcBalance = (200 - 180) * _toRedeem * 2
      ])
    })
  })
})
