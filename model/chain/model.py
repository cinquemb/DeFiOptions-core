#!/usr/bin/env python3

"""
model.py: agent-based model of xSD system behavior, against a testnet
"""
from subprocess import Popen
import subprocess
import json
import collections
import random
import math
import logging
import time
import sys
import os
import base64
import mmap
from eth_abi import encode_single, decode_single
from web3 import Web3
import datetime

IS_DEBUG = False
is_try_model_mine = False
max_accounts = 40
block_offset = 19 + max_accounts
tx_pool_latency = 0.25

DEADLINE_FROM_NOW = 60 * 60 * 24 * 7 * 52
UINT256_MAX = 2**256 - 1
ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'
MMAP_FILE = '/tmp/avax-cchain-nonces'

deploy_data = None
with open("deploy_output.txt", 'r+') as f:
    deploy_data = f.read()

logger = logging.getLogger(__name__)
#provider = Web3.HTTPProvider('http://127.0.0.1:7545/ext/bc/C/rpc', request_kwargs={"timeout": 60*300})
provider = Web3.WebsocketProvider('ws://127.0.0.1:9545/ext/bc/C/ws', websocket_timeout=60*300)

providerAvax = Web3.HTTPProvider('http://127.0.0.1:9545/ext/bc/C/avax', request_kwargs={"timeout": 60*300})
w3 = Web3(provider)
from web3.middleware import geth_poa_middleware
w3.middleware_onion.inject(geth_poa_middleware, layer=0)

w3.eth.defaultAccount = w3.eth.accounts[0]
logger.info(w3.eth.blockNumber)
logger.info(w3.clientVersion)
#sys.exit()

TPRO = {
    "addr": '',
    "deploy_slug": "timeProviderAddress is at: "
}

EXCHG = {
    "addr": '',
    "decimals": 18,
    "deploy_slug": "OptionsExchangeAddress is at: "
}

PROPSMNGERHELPER = {
    "addr":"0x04AbCcEEd429062b0b145e85a91ee2D529b2840A"
}

PROPSWRPR = {
    "addr": Web3.toChecksumAddress("0xbe9a38abe9bb3c28b164f1b0f9aeca9591cb8fb1")
}

PROPSMNGER = {
    "addr": '0x6fe9afFFc3ffa4D59638486bbD029d0138D6E0af',
    "deploy_slug": "OptionsExchangeAddress is at: "
} 

CREDPRO = {
    "addr": '',
    "deploy_slug": "CreditProviderAddress is at: "
}

STG = {
    "addr": '',
    "deploy_slug": "ProtocolSettingsAddress is at: "
}

DPLY = {
    "addr": '',
    "deploy_slug": "Deployer4 is at: "
}

# USE FROM XSD SIMULATION
USDT = {
  "addr": '0x351D75454225010b2d2EeBd0E96762291661CDcB',
  "decimals": 6,
  "symbol": 'USDT',
}

LLPF = {
    "addr": '',
    "deploy_slug": "LinearLiquidityPoolFactoryAddress is at: "
}

BTCUSDAgg = {
  "addr": '',
  "decimals": 8,
  "symbol": 'BTCUSD',
  "deploy_slug": "BTCUSDAgg is at: "
}

BTCUSDc = {
    "addr": '',
    "decimals": 18,
    "symbol": 'BTCUSDc',
    "deploy_slug": "BTCUSDMockFeed is at: "
}

for contract in [BTCUSDc, BTCUSDAgg, LLPF, STG, CREDPRO, EXCHG, TPRO]:
    logger.info(contract["deploy_slug"])
    contract["addr"] = deploy_data.split(contract["deploy_slug"])[1].split('\n')[0]
    logger.info('\t'+contract["addr"])


# token (from Deploy Root on testnet)
xSD = {
  "addr": '',
  "decimals": 18,
  "symbol": 'xSD',
}

AggregatorV3MockContract = json.loads(open('./build/contracts/AggregatorV3Mock.json', 'r+').read())
ChainlinkFeedContract = json.loads(open('./build/contracts/ChainlinkFeed.json', 'r+').read())
CreditProviderContract = json.loads(open('./build/contracts/CreditProvider.json', 'r+').read())
OptionsExchangeContract = json.loads(open('./build/contracts/OptionsExchange.json', 'r+').read())
ProposalManagerContract = json.loads(open('./build/contracts/ProposalsManager.json', 'r+').read())

ProposalManagerHelperContract = json.loads(open('./build/contracts/PoolManagementProposal.json', 'r+').read())
ProposalWrapperContract = json.loads(open('./build/contracts/ProposalWrapper.json', 'r+').read())
 
USDTContract = json.loads(open('./build/contracts/TestnetUSDT.json', 'r+').read())
OptionTokenContract = json.loads(open('./build/contracts/OptionToken.json', 'r+').read())
ProtocolSettingsContract = json.loads(open('./build/contracts/ProtocolSettings.json', 'r+').read())
LinearLiquidityPoolContract = json.loads(open('./build/contracts/LinearLiquidityPool.json', 'r+').read())
LinearLiquidityPoolFactoryContract = json.loads(open('./build/contracts/LinearLiquidityPoolFactory.json', 'r+').read())
ERC20StableCoinContract = json.loads(open('./build/contracts/ERC20.json', 'r+').read())
TimeProviderMockContract = json.loads(open('./build/contracts/TimeProviderMock.json', 'r+').read())


def get_addr_from_contract(contract):
    return contract["networks"][str(sorted(map(int,contract["networks"].keys()))[0])]["address"]

avax_cchain_nonces = None
mm = None

def lock_nonce(agent):
    global mm
    # DECODE START
    if not mm:
        mm = mmap.mmap(avax_cchain_nonces.fileno(), 0)

    mm.seek(0)
    raw_data_cov = mm.read().decode('utf8')
    nonce_data = json.loads(raw_data_cov)

    nonce_data['locked'] = '1'
    out_data = bytes(json.dumps(nonce_data), 'utf8')
    mm[0:] = out_data

def get_nonce(agent):
    global mm
    # DECODE START
    if not mm:
        mm = mmap.mmap(avax_cchain_nonces.fileno(), 0)

    mm.seek(0)
    raw_data_cov = mm.read().decode('utf8')
    nonce_data = json.loads(raw_data_cov)
    current_block = int(w3.eth.get_block('latest')["number"])

    while nonce_data['locked'] == '1':
        mm.seek(0)
        raw_data_cov = mm.read().decode('utf8')
        nonce_data = json.loads(raw_data_cov)
        mm.seek(0)
        continue

    # locked == '1', unlocked == '0'
    
    nonce_data[agent.address]["seen_block"] = decode_single('uint256', base64.b64decode(nonce_data[agent.address]["seen_block"]))
    nonce_data[agent.address]["next_tx_count"] = decode_single('uint256', base64.b64decode(nonce_data[agent.address]["next_tx_count"]))
    # DECODE END

    if current_block != nonce_data[agent.address]["seen_block"]:
        if (nonce_data[agent.address]["seen_block"] == 0):
            nonce_data[agent.address]["seen_block"] = current_block
            nonce_data[agent.address]["next_tx_count"] = agent.next_tx_count
        else:
            nonce_data[agent.address]["seen_block"] = current_block
            nonce_data[agent.address]["next_tx_count"] = agent.next_tx_count
            nonce_data[agent.address]["next_tx_count"] += 1
            agent.next_tx_count = nonce_data[agent.address]["next_tx_count"]
    else:
        nonce_data[agent.address]["next_tx_count"] = agent.next_tx_count
        nonce_data[agent.address]["next_tx_count"] += 1
        agent.next_tx_count = nonce_data[agent.address]["next_tx_count"]

    # ENCODE START
    nonce_data[agent.address]["seen_block"] = base64.b64encode(encode_single('uint256', nonce_data[agent.address]["seen_block"])).decode('ascii')
    nonce_data[agent.address]["next_tx_count"] = base64.b64encode(encode_single('uint256', nonce_data[agent.address]["next_tx_count"])).decode('ascii')
    
    # ENCODE END
    return agent.next_tx_count

def unlock_nonce(agent):
    global mm
    # DECODE START
    if not mm:
        mm = mmap.mmap(avax_cchain_nonces.fileno(), 0)

    mm.seek(0)
    raw_data_cov = mm.read().decode('utf8')
    nonce_data = json.loads(raw_data_cov)

    nonce_data['locked'] = '0'
    out_data = bytes(json.dumps(nonce_data), 'utf8')
    mm[:] = out_data

def transaction_helper(agent, prepped_function_call, gas):
    tx_hash = None
    nonce = get_nonce(agent)
    while tx_hash is None:
        try:
            agent.next_tx_count = nonce
            lock_nonce(agent)
            tx_hash = prepped_function_call.transact({
                'chainId': 43112,
                'nonce': nonce,
                'from' : getattr(agent, 'address', agent),
                'gas': gas,
                'gasPrice': Web3.toWei(225, 'gwei'),
            })
            unlock_nonce(agent)
        except Exception as inst:
            err_str = str(inst)
            if 'nonce too low' in err_str:
                # increment tx_hash
                unlock_nonce(agent)
                nonce +=1
            elif 'replacement transaction underpriced' in err_str:
                # increment tx_hash
                unlock_nonce(agent)
                nonce +=1
            else:
                unlock_nonce(agent)
                nonce +=1
                print(inst)
    return tx_hash

def pretty(d, indent=0):
   """
   Pretty-print a value.
   """
   if not isinstance(d, dict) and not isinstance(d, list):
       print('\t' * (indent+1) + str(d))
   else: 
       for key, value in d.items():
          print('\t' * indent + str(key))
          if isinstance(value, dict):
             pretty(value, indent+1)
          elif isinstance(value, list):
            for v in value:
                pretty(v, indent+1)
          else:
             print('\t' * (indent+1) + str(value))

def portion_dedusted(total, fraction):
    """
    Compute the amount of an asset to use, given that you have
    total and you don't want to leave behind dust.
    """
    
    if total - (fraction * total) <= 1:
        return total
    else:
        return fraction * total

def defaultdict_from_dict(d):
    #nd = lambda: collections.defaultdict(nd)
    ni = collections.defaultdict(set)
    ni.update(d)
    return ni

def execute_cmd(cmd):
    try:
        proc = Popen(cmd, shell=True, stdin=None, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, close_fds=True)
        proc_data = proc.communicate()[0]
        return proc_data
    
    except Exception as inst:
        print (inst)
        data = inst
    return data

# Because token balances need to be accuaate to the atomic unit, we can't store
# them as floats. Otherwise we might turn our float back into a token balance
# different from the balance we actually had, and try to spend more than we
# have. But also, it's ugly to throw around total counts of atomic units. So we
# use this class that represents a fixed-point token balance.
class Balance:
    def __init__(self, wei=0, decimals=0):
        self._wei = int(wei)
        self._decimals = int(decimals)
        
    def clone(self):
        """
        Make a deep copy so += and -= on us won't infect the copy.
        """
        return Balance(self._wei, self._decimals)
        
    def to_decimals(self, new_decimals):
        """
        Get a similar balance with a different number of decimals.
        """
        
        return Balance(self._wei * 10**new_decimals // 10**self._decimals, new_decimals)
        
    @classmethod
    def from_tokens(cls, n, decimals=0):
        return cls(n * 10**decimals, decimals)

    def __add__(self, other):
        if isinstance(other, Balance):
            if other._decimals != self._decimals:
                raise ValueError("Cannot add balances with different decimals: {}, {}", self, other)
            return Balance(self._wei + other._wei, self._decimals)
        else:
            return Balance(self._wei + other * 10**self._decimals, self._decimals)

    def __iadd__(self, other):
        if isinstance(other, Balance):
            if other._decimals != self._decimals:
                raise ValueError("Cannot add balances with different decimals: {}, {}", self, other)
            self._wei += other._wei
        else:
            self._wei += other * 10**self._decimals
        return self
        
    def __radd__(self, other):
        return self + other
        
    def __sub__(self, other):
        if isinstance(other, Balance):
            if other._decimals != self._decimals:
                raise ValueError("Cannot subtract balances with different decimals: {}, {}", self, other)
            return Balance(self._wei - other._wei, self._decimals)
        else:
            return Balance(self._wei - other * 10**self._decimals, self._decimals)

    def __isub__(self, other):
        if isinstance(other, Balance):
            if other._decimals != self._decimals:
                raise ValueError("Cannot subtract balances with different decimals: {}, {}", self, other)
            self._wei -= other._wei
        else:
            self._wei -= other * 10**self._decimals
        return self
        
    def __rsub__(self, other):
        return Balance(other * 10**self._decimals, self._decimals) - self
        
    def __mul__(self, other):
        if isinstance(other, Balance):
            raise TypeError("Cannot multiply two balances")
        return Balance(self._wei * other, self._decimals)
        
    def __imul__(self, other):
        if isinstance(other, Balance):
            raise TypeError("Cannot multiply two balances")
        self._wei = int(self._wei * other)
        
    def __rmul__(self, other):
        return self * other
        
    def __truediv__(self, other):
        if isinstance(other, Balance):
            raise TypeError("Cannot divide two balances")
        return Balance(self._wei // other, self._decimals)
        
    def __itruediv__(self, other):
        if isinstance(other, Balance):
            raise TypeError("Cannot divide two balances")
        self._wei = int(self._wei // other)
        
    # No rtruediv because dividing by a balance is silly.
    
    # Todo: floordiv? divmod?
    
    def __lt__(self, other):
        if isinstance(other, Balance):
            if other._decimals != self._decimals:
                raise ValueError("Cannot compare balances with different decimals: {}, {}", self, other)
            return self._wei < other._wei
        else:
            return float(self) < other
            
    def __le__(self, other):
        if isinstance(other, Balance):
            if other._decimals != self._decimals:
                raise ValueError("Cannot compare balances with different decimals: {}, {}", self, other)
            return self._wei <= other._wei
        else:
            return float(self) <= other
            
    def __gt__(self, other):
        if isinstance(other, Balance):
            if other._decimals != self._decimals:
                raise ValueError("Cannot compare balances with different decimals: {}, {}", self, other)
            return self._wei > other._wei
        else:
            return float(self) > other
            
    def __ge__(self, other):
        if isinstance(other, Balance):
            if other._decimals != self._decimals:
                raise ValueError("Cannot compare balances with different decimals: {}, {}", self, other)
            return self._wei >= other._wei
        else:
            return float(self) >= other
            
    def __eq__(self, other):
        if isinstance(other, Balance):
            if other._decimals != self._decimals:
                raise ValueError("Cannot compare balances with different decimals: {}, {}", self, other)
            return self._wei == other._wei
        else:
            return float(self) == other
            
    def __ne__(self, other):
        if isinstance(other, Balance):
            if other._decimals != self._decimals:
                raise ValueError("Cannot compare balances with different decimals: {}, {}", self, other)
            return self._wei != other._wei
        else:
            return float(self) != other

    def __str__(self):
        base = 10**self._decimals
        ipart = self._wei // base
        fpart = self._wei - base * ipart
        return ('{}.{:0' + str(self._decimals) + 'd}').format(ipart, fpart)

    def __repr__(self):
        return 'Balance({}, {})'.format(self._wei, self._decimals)
        
    def __float__(self):
        return self._wei / 10**self._decimals

    def __round__(self):
        return Balance(int(math.floor(self._wei / 10**self._decimals)) * 10**self._decimals, self._decimals)
        
    def __format__(self, s):
        if s == '':
            return str(self)
        return float(self).__format__(s)
        
    def to_wei(self):
        return self._wei
        
    def decimals(self):
        return self._decimals

class TokenProxy:
    """
    A proxy for an ERC20 token. Monitors events, processes them when update()
    is called, and fulfils balance requests from memory.
    """
    
    def __init__(self, contract):
        """
        Set up a proxy around a Web3py contract object that implements ERC20.
        """
        
        self.__contract = contract
        self.__transfer_filter = self.__contract.events.Transfer.createFilter(fromBlock='latest')
        # This maps from string address to Balance balance
        self.__balances = {}
        # This records who we approved for who
        self.__approved_file = "{}-{}.json".format(str(contract.address), 'approvals')

        if not os.path.exists(self.__approved_file):
            f = open(self.__approved_file, 'w+')
            f.write('{}')
            f.close()
            tmp_file_data = {}
        else:
            data = open(self.__approved_file, 'r+').read()
            tmp_file_data = {} if len(data) == 0 else json.loads(data)
        self.__approved = tmp_file_data
        
        # Load initial parameters from the chain.
        # Assumes no events are happening to change the supply while we are doing this.
        self.__decimals = self.__contract.functions.decimals().call()
        self.__symbol = self.__contract.functions.symbol().call()
        self.__supply = Balance(self.__contract.functions.totalSupply().call(), self.__decimals)

    # Expose some properties to make us easy to use in place of the contract
        
    @property
    def decimals(self):
        return self.__decimals
        
    @property
    def symbol(self):
        return self.__symbol
        
    @property
    def totalSupply(self):
        return self.__supply
        
    @property
    def address(self):
        return self.__contract.address
        
    @property
    def contract(self):
        return self.__contract
        
    def update(self, is_init_agents=[]):
        """
        Process pending events and update state to match chain.
        Assumes no transactions are still in flight.
        """
        
        # These addresses need to be polled because we have no balance from
        # before all these events.
        new_addresses = set()
        try:
            for transfer in self.__transfer_filter.get_new_entries():
                # For every transfer event since we last updated...
                
                # Each loooks something like:
                # AttributeDict({'args': AttributeDict({'from': '0x0000000000000000000000000000000000000000', 
                # 'to': '0x20042A784Bf0743fcD81136422e12297f52959a0', 'value': 19060347313}), 
                # 'event': 'Transfer', 'logIndex': 0, 'transactionIndex': 0,
                # 'transactionHash': HexBytes('0xa6f4ca515b28301b224f24b7ee14b8911d783e2bf965dbcda5784b4296c84c23'), 
                # 'address': '0xa2Ff73731Ee46aBb6766087CE33216aee5a30d5e', 
                # 'blockHash': HexBytes('0xb5ffd135318581fcd5cd2463cf3eef8aaf238bef545e460c284ad6283928ed08'),
                # 'blockNumber': 17})
                args = transfer['args']
                
                moved = Balance(args['value'], self.__decimals)
                if args['from'] in self.__balances:
                    self.__balances[args['from']] -= moved
                elif args['from'] == ZERO_ADDRESS:
                    # This is a mint
                    self.__supply += moved
                else:
                    new_addresses.add(args['from'])
                if args['to'] in self.__balances:
                    self.__balances[args['to']] += moved
                elif args['to'] == ZERO_ADDRESS:
                    # This is a burn
                    self.__supply -= moved
                else:
                    new_addresses.add(args['to'])
        except:
            pass
        
        for address in new_addresses:
            # TODO: can we get a return value and a correct-as-of block in the same call?
            self.__balances[address] = Balance(self.__contract.functions.balanceOf(address).call(), self.__decimals)

        if is_init_agents:
            for agent in is_init_agents:
                # TODO: can we get a return value and a correct-as-of block in the same call?
                self.__balances[agent.address] = Balance(self.__contract.functions.balanceOf(agent.address).call(), self.__decimals)

            
    def __getitem__(self, address):
        """
        Get the balance of the given address as a Balance, with the given number of decimals.
        
        Address can be a string or any object with an .address field.
        """
        
        address = getattr(address, 'address', address)
        
        if address not in self.__balances:
            # Don't actually cache here; wait for a transfer.
            # Transactions may still be in flight
            return Balance(self.__contract.functions.balanceOf(address).call(), self.__decimals)
        else:
            # Clone the stored balance so it doesn't get modified and upset the user
            return self.__balances[address].clone()
            
    def ensure_approved(self, owner, spender):
        """
        Approve the given spender to spend all the owner's tokens on their behalf.
        
        Owner and spender may be addresses or things with addresses.
        """
        spender = getattr(spender, 'address', spender)
        
        if (getattr(owner, 'address', owner) not in self.__approved) or (spender not in self.__approved[getattr(owner, 'address', owner)]):
            # Issue an approval
            #logger.info('WAITING FOR APPROVAL {} for {}'.format(getattr(owner, 'address', owner), spender))
            tx_hash = transaction_helper(
                owner,
                self.__contract.functions.approve(spender, UINT256_MAX),
                500000
            )
            receipt = w3.eth.waitForTransactionReceipt(tx_hash, poll_latency=tx_pool_latency)
            #logger.info('APPROVED')
            if getattr(owner, 'address', owner) not in self.__approved:
                self.__approved[getattr(owner, 'address', owner)] = {spender: 1}
            else:
                self.__approved[getattr(owner, 'address', owner)][spender] = 1

            open(self.__approved_file, 'w+').write(json.dumps(self.__approved))
            
    def from_wei(self, wei):
        """
        Convert a number of wei (possibly a float) into a Balance with the
        right number of decimals.
        """
        
        return Balance(wei, self.__decimals)
        
    def from_tokens(self, tokens):
        """
        Convert a number of token units (possibly a float) into a Balance with
        the right number of decimals.
        """
        
        return Balance.from_tokens(tokens, self.__decimals)
        
class Agent:
    """
    Represents an agent. Tracks all the agent's balances.
    """
    
    def __init__(self, linear_liquidity_pool, options_exchange, credit_provider, xsd_token, usdt_token, **kwargs):
 
        # xSD TokenProxy
        self.xsd_token = xsd_token
        # USDT TokenProxy 
        self.usdt_token = usdt_token

        self.option_tokens = []


        self.credit_provider = credit_provider
        
        # avax balance
        self.avax = kwargs.get("starting_avax", Balance(0, 18))
        
        # What's our max faith in the system in USDT?
        self.max_faith = kwargs.get("max_faith", 0.0)
        # And our min faith
        self.min_faith = kwargs.get("min_faith", 0.0)
        # Should we even use faith?
        self.use_faith = kwargs.get("use_faith", True)

        # add wallet addr
        self.address = kwargs.get("wallet_address", '0x0000000000000000000000000000000000000000')

        # Linear Liquidity Pool + Proxy
        self.linear_liquidity_pool = linear_liquidity_pool
        # Options Exchange
        self.options_exchange = options_exchange

        # keeps track of latest block seen for nonce tracking/tx
        self.next_tx_count = w3.eth.getTransactionCount(self.address, block_identifier=int(w3.eth.get_block('latest')["number"]))

        if kwargs.get("is_mint", False):
            # need to mint USDT to the wallets for each agent
            start_usdt_formatted = kwargs.get("starting_usdt", Balance(0, USDT["decimals"]))
            tx_hash = transaction_helper(
                self,
                self.usdt_token.contract.functions.mint(
                    self.address, start_usdt_formatted.to_wei()
                ),
                500000
            )
            time.sleep(1.1)
            w3.eth.waitForTransactionReceipt(tx_hash, poll_latency=tx_pool_latency)
        
    @property
    def xsd(self):
        """
        Get the current balance in USDT from the TokenProxy.
        """
        return self.xsd_token[self] if self.xsd_token else 0
    
    @property
    def usdt(self):
        """
        Get the current balance in USDT from the TokenProxy.
        """
        return self.usdt_token[self]

    @property
    def total_written(self):
        return Balance(self.options_exchange.get_total_owner_written(self), EXCHG['decimals'])

    @property
    def total_holding(self):
        return Balance(self.options_exchange.get_total_owner_holding(self), EXCHG['decimals'])

    @property
    def lp(self):
        """
        Get the current balance in Linear Liquidity Pool LP Shares from the TokenProxy.
        """
        return self.linear_liquidity_pool[self]

    @property
    def short_collateral_exposure(self):
        """
        Get the short collateral balance for agent
        """
        return self.credit_provider.get_short_collateral_exposure(self)
    
    def __str__(self):
        """
        Turn into a readable string summary.
        """
        return "Agent(xSD={:.2f}, usdt={:.2f}, avax={}, lp={}, total_written={}, total_holding={}, short_collateral_exposure={:.2f})".format(
            self.xsd, self.usdt, self.avax, self.lp, self.total_written, self.total_holding, self.short_collateral_exposure)

        
    def get_strategy(self, current_timestamp):
        """
        Get weights, as a dict from action to float, as a function of the price.
        """
        
        strategy = collections.defaultdict(lambda: 1.0)

        strategy["buy"] = 1.0
        strategy["sell"] = 10.0
        strategy["write"] = 1.0
        strategy["deposit_exchange"] = 1.0
        strategy["deposit_pool"] = 1.0
        strategy["add_symbol"] = 1.0
        strategy["create_symbol"] = 1.0
        
       
        if self.use_faith:
            # Vary our strategy based on  ... ?
            pass
        
        return strategy
        
    def get_faith(self, current_timestamp, price, total_supply):
        """
        Get the total faith in xSD that this agent has, in USDT.
        
        If the market cap is over the faith, the agent thinks the system is
        over-valued. If the market cap is under the faith, the agent thinks the
        system is under-valued.
        """
        
        # TODO: model the real economy as bidding on utility in
        # mutually-beneficial exchanges conducted in xSD, for which a velocity
        # is needed, instead of an abstract faith?
        
        # TODO: different faith for different people
        
        center_faith = (self.max_faith + self.min_faith) / 2
        swing_faith = (self.max_faith - self.min_faith) / 2
        faith = center_faith + swing_faith * math.sin(current_timestamp * (2 * math.pi / 5000000))
        
        return faith
        
class OptionsExchange:
    def __init__(self, contract, usdt_token, btcusd_chainlink_feed, **kwargs):
        self.contract = contract
        self.usdt_token = usdt_token
        self.btcusd_chainlink_feed = btcusd_chainlink_feed
        self.option_tokens = {}

    def balance(self, agent):
        bal = self.contract.caller({'from' : agent.address, 'gas': 100000}).balanceOf(agent.address)
        return Balance(bal, EXCHG['decimals'])

    def resolve_token(self, agent, symbol):
        '''
            resolveToken(symbol)
        '''
        option_token_address = None

        try:
            option_token_address = self.contract.caller({'from' : agent.address, 'gas': 100000}).resolveToken(symbol)


        except Exception as inst:
            if "token not found" in str(inst):
                pass
            else:
                raise(inst)
        return option_token_address

    def deposit_exchange(self, agent, amount):
        '''
            ERC20 stablecoin = ERC20(0x123...);
            OptionsExchange exchange = OptionsExchange(0xABC...);

            address to = 0x456...;
            uint value = 100e18;
            stablecoin.approve(address(exchange), value);
            exchange.depositTokens(to, address(stablecoin), value);
        '''
        self.usdt_token.ensure_approved(agent, self.contract.address)
        tx = transaction_helper(
            agent,
            self.contract.functions.depositTokens(
                agent.address,
                self.usdt_token.address,
                amount.to_wei()
            ),
            500000
        )
        return tx

    def withdraw(self, agent, amount):
        '''
            uint value = 50e18;
            exchange.withdrawTokens(value);
        '''
        tx = transaction_helper(
            agent,
            self.contract.functions.withdrawTokens(
                amount.to_wei()
            ),
            8000000
        )
        return tx

    def calc_collateral(self, agent, feed_address, option_type, amount, strike_price, maturity):
        '''

        address eth_usd_feed = address(0x987...);
        uint volumeBase = 1e18;
        uint strikePrice = 1300e18;
        uint maturity = now + 30 days;

        uint collateral = exchange.calcCollateral(
            feed_address, 
            10 * volumeBase, 
            OptionsExchange.OptionType.CALL, 
            strikePrice, 
            maturity
        );
        '''

        cc = self.contract.caller({'from' : agent.address, 'gas': 8000000}).calcCollateral(
            feed_address,
            Balance.from_tokens(amount, EXCHG['decimals']).to_wei(),
            0 if option_type == 'CALL' else 1,
            strike_price,
            maturity
        )
        return Balance(cc, EXCHG['decimals'])

    def write(self, agent, feed_address, option_type, amount, strike_price, maturity):
        '''
            address tkAddr = exchange.writeOptions(
                eth_usd_feed, 
                10 * volumeBase, 
                OptionsExchange.OptionType.CALL, 
                strikePrice, 
                maturity,
                holder
            );
        '''
        tx = transaction_helper(
            agent,
            self.contract.functions.writeOptions(
                feed_address,
                Balance.from_tokens(amount, EXCHG['decimals']).to_wei(),
                0 if option_type == 'CALL' else 1,
                strike_price,
                maturity,
                agent.address
            ),
            8000000
        )
        return tx

    def create_symbol(self, agent, symbol, btcusd_chainlink_feed):
        tx = transaction_helper(
            agent,
            self.contract.functions.createSymbol(
                symbol,
                btcusd_chainlink_feed.address
            ),
            8000000
        )
        return tx


    def burn_token(self, agent, option_token_address, token_amount):
        '''
        uint amount = token_amount * volumeBase;
        token.burn(amount);
        '''
        option_token = w3.eth.contract(abi=OptionTokenContract['abi'], address=option_token_address)
        tx = transaction_helper(
            agent,
            option_token.functions.burn(
                agent.address,
                token_amount.to_wei()
            ),
            8000000
        )
        return tx

    def redeem_token(self, agent, option_token_address):
        option_token = w3.eth.contract(abi=OptionTokenContract['abi'], address=option_token_address)
        tx = transaction_helper(
            agent,
            option_token.functions.redeem(
                agent.address
            ),
            8000000
        )
        return tx

    def liquidate(self, agent, options_address, owner_address):
        '''
            exchange.liquidateOptions()
        '''
        tx = transaction_helper(
            agent,
            self.contract.functions.liquidateOptions(
                options_address,
                owner_address
            ),
            8000000
        )
        return tx

    def get_total_short_collateral_exposure(self, agent):

        '''

        NEED TO FIGURE OUT A BETTER WAY TO TRACK THIS
            return self.contract.caller({'from' : agent.address, 'gas': 100000}).getOptionsExchangeTotalExposure()
        '''
        return 0

    def get_total_written(self, agent):
        '''
            - loop over all options tokens and get (for total written)
                - totalWrittenVolume()
        '''
        tw = 0
        for k, ot in self.option_tokens.items():
            tw += ot.contract.caller({'from' : agent.address, 'gas': 100000}).totalWrittenVolume()
        return tw

    def get_total_holding(self, agent):
        '''
            - loop over all options tokens and get (for total holding)
                - totalSupply()
        '''
        th = 0
        for k, ot in self.option_tokens.items():
            th += ot.contract.caller({'from' : agent.address, 'gas': 100000}).totalSupply()
        return th

    def get_total_owner_written(self, agent):
        '''
            - loop over all options tokens and get (for written)
                - writtenVolume(address owner)
        '''
        ow = 0
        for k, ot in self.option_tokens.items():
            ow += ot.contract.caller({'from' : agent.address, 'gas': 8000000}).writtenVolume(agent.address)
        return ow

    def get_total_owner_holding(self, agent):
        '''
            - loop over all options tokens and get (for holding)
                - balanceOf(address owner)
        '''
        oh = 0
        for k, ot in self.option_tokens.items():
            oh += ot.contract.caller({'from' : agent.address, 'gas': 8000000}).balanceOf(agent.address)
        return oh

    def calc_collateral_surplus(self, checker, agent):
        cs = self.contract.caller({'from' : checker.address, 'gas': 8000000}).calcSurplus(agent.address)
        return Balance(cs, EXCHG['decimals'])

    def prefetch_daily(self, agent, current_round_id, iv_bin_window):
        '''

            First call prefetchDailyPrice passing in the "roundId" of the latest sample you appended to your mock, corresponding to the underlying price for the new day
            Then call prefetchDailyVolatility passing in the volatility period defined in the ProtocolSettings contract (defaults to 90 days)
            Maybe twap can be updated daily?
        '''
        txr = transaction_helper(
            agent,
            self.btcusd_chainlink_feed.functions.prefetchDailyPrice(
                current_round_id
            ),
            8000000
        )
        txr_recp = w3.eth.waitForTransactionReceipt(txr, poll_latency=tx_pool_latency, timeout=600)
        print("prefetchDailyPrice", txr_recp)
        
        txv = transaction_helper(
            agent,
            self.btcusd_chainlink_feed.functions.prefetchDailyVolatility(
                iv_bin_window
            ),
            8000000
        )
        txv_recp = w3.eth.waitForTransactionReceipt(txv, poll_latency=tx_pool_latency, timeout=600)
        print("prefetchDailyVolatility", txr_recp)

    def prefetch_sample(self, agent):
        txr = transaction_helper(
            agent,
            self.btcusd_chainlink_feed.functions.prefetchSample(),
            8000000
        )
        txv_recp = w3.eth.waitForTransactionReceipt(txr, poll_latency=tx_pool_latency, timeout=600)

class CreditProvider:
    def __init__(self, contract, **kwargs):
        self.contract = contract

    def get_total_balance(self, agent):
        '''
            Get total balance of stable coins assinged to agents
        '''
        return self.contract.caller({'from' : agent.address, 'gas': 100000}).getTotalBalance()

    def get_token_stock(self, agent):
        '''
            Get total balance erc20 stables coins deposited into credit provider
        '''
        return self.contract.caller({'from' : agent.address, 'gas': 100000}).totalTokenStock()

    def get_total_debt(self, agent):
        return Balance(self.contract.caller({'from' : agent.address, 'gas': 8000000}).totalDebt(), EXCHG['decimals'])

    def get_short_collateral_exposure(self, agent):
        return Balance(self.contract.caller({'from' : agent.address, 'gas': 8000000}).calcRawCollateralShortage(agent.address), EXCHG['decimals'])

class LinearLiquidityPool(TokenProxy):
    def __init__(self, contract, usdt_token, options_exchange, **kwargs):
        self.usdt_token = usdt_token
        self.options_exchange = options_exchange
        super().__init__(contract)

    def deposit_pool(self, agent, amount):
        '''
            pool.depositTokens(
                address to, address token, uint value
            );
        '''
        self.usdt_token.ensure_approved(agent, self.contract.address)
        tx = transaction_helper(
            agent,
            self.contract.functions.depositTokens(
                agent.address,
                self.usdt_token.address,
                amount.to_wei()
            ),
            500000
        )
        return tx

    def redeem_pool(self, agent):
        '''
            pool.redeem(address)
        '''
        tx = transaction_helper(
            agent,
            self.contract.functions.redeem(
                agent.address
            ),
            8000000
        )
        return tx

    def query_buy(self, agent, symbol):
        print(symbol)
        price_volume = self.contract.caller({'from' : agent.address, 'gas': 80000000}).queryBuy(symbol)
        return price_volume

    def buy(self, agent, symbol, price, volume):
        '''
            stablecoin.approve(address(pool), price * volume / volumeBase);
            pool.buy(symbol, price, volume, address(stablecoin));
        '''
        self.usdt_token.ensure_approved(agent, self.contract.address)
        tx = transaction_helper(
            agent,
            self.contract.functions.buy(
                symbol,
                price,
                volume.to_wei(),
                self.usdt_token.contract.address
            ),
            8000000
        )
        return tx

    def query_sell(self, agent, symbol):
        price_volume = self.contract.caller({'from' : agent.address, 'gas': 80000000}).querySell(symbol)
        return price_volume

    def sell(self, agent, symbol, price, volume, option_token):
        '''
            option_token.approve(address(pool), price * volume / volumeBase)`;
            pool.sell(symbol, price, volume, 0, 0)`;
        '''
        '''
        txc = transaction_helper(
            agent,
            self.options_exchange.contract.functions.setCollateral(
                self.contract.address
            ),
            8000000
        )
        w3.eth.waitForTransactionReceipt(txc, poll_latency=tx_pool_latency)
        '''

        option_token.ensure_approved(agent, self.contract.address)
        tx = transaction_helper(
            agent,
            self.contract.functions.sell(
                symbol,
                price,
                volume.to_wei()
            ),
            8000000
        )
        return tx

    '''
        EXTRACT TIMESTAMP FROM SYMBOL AND FILTER ON IF BEFORE OR AFTER CURRENT BLOCK TIMESTAMP
    '''
    def list_symbols(self, agent):
        symbols = self.contract.caller({'from' : agent.address, 'gas': 8000000}).listSymbols().split('\n')
        return [x for x in list(filter(None,symbols)) if x != '']

    '''
        EXTRACT TIMESTAMP FROM SYMBOL AND FILTER ON IF BEFORE OR AFTER CURRENT BLOCK TIMESTAMP
    '''
    def list_expired_symbols(self, agent):
        symbols = self.contract.caller({'from' : agent.address, 'gas': 8000000}).listExpiredSymbols().split('\n')
        return [x for x in list(filter(None,symbols)) if x != '']

    def get_option_tokens(self, agent):
        symbols = self.list_symbols(agent)
        option_tokens = []
        for sym in symbols:
            option_token_address = self.options_exchange.resolve_token(agent, sym)
            if option_token_address:
                option_token = TokenProxy(w3.eth.contract(abi=OptionTokenContract['abi'], address=option_token_address))
                option_tokens.append(option_token)

        return option_tokens

    def get_option_tokens_expired(self, agent):
        symbols = self.list_expired_symbols(agent)
        option_tokens = []
        for sym in symbols:
            option_token_address = self.options_exchange.resolve_token(agent, sym)
            if option_token_address:
                option_token = TokenProxy(w3.eth.contract(abi=OptionTokenContract['abi'], address=option_token_address))
                option_tokens.append(option_token)

        return option_tokens

    def add_symbol(self, agent, udlfeed_address, strike, maturity, option_type, current_timestamp, x, y, buyStock, sellStock):
        '''
            pool.addSymbol(
                address(feed),
                strike,
                maturity,
                CALL,
                time.getNow(),
                time.getNow() + 1 days,
                x,
                y,
                100 * volumeBase, // buy stock
                200 * volumeBase  // sell stock
            );
        '''
        tx = transaction_helper(
            agent,
            self.contract.functions.addSymbol(
                udlfeed_address,
                strike * (10**EXCHG['decimals']),
                maturity,
                0 if option_type == 'CALL' else 1,
                current_timestamp,
                current_timestamp + (60 * 60 * 24 * 2),
                x,
                y,
                buyStock * 10**EXCHG['decimals'],
                sellStock * 10**EXCHG['decimals']
            ),
            8000000
        )
        return tx

    def update_symbol(self, agent, udlfeed_address, strike, maturity, option_type, current_timestamp, x, y, buyStock, sellStock):
        '''
            pool.addSymbol(
                address(feed),
                strike,
                maturity,
                CALL,
                time.getNow(),
                time.getNow() + 1 days,
                x,
                y,
                100 * volumeBase, // buy stock
                200 * volumeBase  // sell stock
            );
        '''
        tx = transaction_helper(
            agent,
            self.contract.functions.addSymbol(
                udlfeed_address,
                strike * (10**EXCHG['decimals']),
                maturity,
                0 if option_type == 'CALL' else 1,
                current_timestamp,
                current_timestamp + (60 * 60 * 24 * 2),
                x,
                y,
                buyStock * (10**EXCHG['decimals']),
                sellStock * (10**EXCHG['decimals'])
            ),
            8000000
        )
        return tx

    def pool_free_balance(self, agent):
        pool_free_balance = self.contract.caller({'from' : agent.address, 'gas': 100000}).calcFreeBalance()
        return Balance(pool_free_balance, EXCHG['decimals'])

class Model:
    """
    Full model of the economy.
    """
    
    def __init__(self, options_exchange, credit_provider, linear_liquidity_pool, btcusd_chainlink_feed, btcusd_agg, btcusd_data, xsd, usdt, agents, **kwargs):
        """
        Takes in experiment parameters and forwards them on to all components.
        """

        self.agents = []
        self.options_exchange = OptionsExchange(options_exchange, usdt, btcusd_chainlink_feed, **kwargs)
        self.credit_provider = CreditProvider(credit_provider, **kwargs)
        self.linear_liquidity_pool = LinearLiquidityPool(linear_liquidity_pool, usdt, self.options_exchange, **kwargs)
        self.btcusd_chainlink_feed = btcusd_chainlink_feed
        self.btcusd_agg = btcusd_agg
        self.btcusd_data = btcusd_data
        self.btcusd_data_init_bins = 30
        self.current_round_id = 30
        self.daily_vol_period = 30
        self.prev_timestamp = 0
        self.daily_period = 60 * 60 * 24
        self.weekly_period = self.daily_period * 7
        self.days_per_year = 365
        self.months_per_year = 12
        self.option_tokens = {}
        self.option_tokens_expired = {}
        self.option_tokens_expired_to_burn = {}
        self.usdt_token = usdt
        self.symbol_created = {}

        is_mint = is_try_model_mine
        if w3.eth.get_block('latest')["number"] == block_offset:
            # THIS ONLY NEEDS TO BE RUN ON NEW CONTRACTS
            # TODO: tolerate redeployment or time-based generation
            is_mint = True
        
        total_tx_submitted = len(agents) 
        for i in range(len(agents)):
            
            address = agents[i]
            agent = Agent(self.linear_liquidity_pool, self.options_exchange, self.credit_provider, xsd, usdt, starting_axax=0, starting_usdt=0, wallet_address=address, is_mint=is_mint, **kwargs)
             
            self.agents.append(agent)


        is_print_agent_state = False

        if is_print_agent_state:
            # Update caches to current chain state
            self.usdt_token.update(is_init_agents=self.agents)
            self.linear_liquidity_pool.update(is_init_agents=self.agents)

            for x in self.linear_liquidity_pool.get_option_tokens(self.agents[0]):
                if x.address not in self.option_tokens:
                    self.option_tokens[x.address] = x

            self.options_exchange.option_tokens = self.option_tokens


            for i in range(len(agents)):
                logger.info(self.agents[i])

            sys.exit()


        '''
            INIT T-MINUS DATA FOR FEED
        '''

        if self.prev_timestamp == 0:
            current_timestamp = w3.eth.get_block('latest')['timestamp']
            seleted_advancer = self.agents[0]
            transaction_helper(
                seleted_advancer,
                self.btcusd_agg.functions.setRoundIds(
                    range(30)
                ),
                500000
            )

            transaction_helper(
                seleted_advancer,
                self.btcusd_agg.functions.setAnswers(
                    self.btcusd_data[:self.btcusd_data_init_bins]
                ),
                500000
            )

            timestamps = [(x* self.daily_period * -1) + current_timestamp for x in range(self.btcusd_data_init_bins, 0, -1)]
            transaction_helper(
                seleted_advancer,
                self.btcusd_agg.functions.setUpdatedAts(
                    timestamps
                ),
                500000
            )

            print(timestamps)
            print(self.btcusd_data[:self.btcusd_data_init_bins])

            tx = transaction_helper(
                seleted_advancer,
                self.btcusd_chainlink_feed.functions.initialize(
                    timestamps,
                    self.btcusd_data[:self.btcusd_data_init_bins]
                ),
                8000000
            )
            receipt = w3.eth.waitForTransactionReceipt(tx, poll_latency=tx_pool_latency, timeout=600)
            print(receipt)

        
    def log(self, stream, seleted_advancer, header=False):
        """
        Log model statistics a TSV line.
        If header is True, include a header.
        """
        
        if header:
            stream.write("#block\twritten\tholding\texposure\ttotal CB\ttotal SB\ttotal debt\n")#\tfaith\n")
        
        print(
            w3.eth.get_block('latest')["number"],
            self.options_exchange.get_total_written(seleted_advancer),
            self.options_exchange.get_total_holding(seleted_advancer),
            self.options_exchange.get_total_short_collateral_exposure(seleted_advancer),
            self.credit_provider.get_total_balance(seleted_advancer),
            self.credit_provider.get_token_stock(seleted_advancer),
            self.credit_provider.get_total_debt(seleted_advancer)
        )
        
        stream.write('{}\t{}\t{}\t{:.2f}\t{:.2f}\t{:.2f}\t{:.2f}\n'.format(
                w3.eth.get_block('latest')["number"],
                self.options_exchange.get_total_written(seleted_advancer),
                self.options_exchange.get_total_holding(seleted_advancer),
                self.options_exchange.get_total_short_collateral_exposure(seleted_advancer),
                self.credit_provider.get_total_balance(seleted_advancer),
                self.credit_provider.get_token_stock(seleted_advancer),
                self.credit_provider.get_total_debt(seleted_advancer)
            )
        )
       
    def get_overall_faith(self):
        """
        Probably should be related to credit token?
        """
        pass

    def is_positve_option_token_expired_balance(self, agent):
        tokens = []
        for k,v in self.option_tokens_expired.items():
            if v[agent] > 0:
                tokens.append(v)
        return False
    
    def is_positive_option_token_balance(self, agent):
        tokens = []
        for k,v in self.option_tokens.items():
            if v[agent] > 0:
                tokens.append(v)

        for k,v in self.option_tokens_expired.items():
            if v[agent] > 0:
                tokens.append(v)
        return False
       
    def step(self):
        """
        Step the model Let all the agents act.
        
        Returns True if anyone could act.
        """
        # Update caches to current chain state for all the tokens
        self.usdt_token.update()
        self.linear_liquidity_pool.update()

        current_timestamp = w3.eth.get_block('latest')['timestamp']
        diff_timestamp = current_timestamp - self.prev_timestamp

        '''
            TODO:
                randomly have an agent do maintence tasks the epoch, in order to simulate people using governance tokens to do these task, for now, use initializing agent
        '''
        random_advancer = self.agents[int(random.random() * (len(self.agents) - 1))]
        seleted_advancer = self.agents[0]

        available_symbols = self.linear_liquidity_pool.list_symbols(seleted_advancer)


        '''
            TODO: need to explore 2:1 bs, 1:1 bs and 1:2 bs
        '''

        buyStock = 100000
        sellStock = 100000

        
        for x in self.linear_liquidity_pool.get_option_tokens(random_advancer):
            if x.address not in self.option_tokens:
                self.option_tokens[x.address] = x

        for x in self.linear_liquidity_pool.get_option_tokens_expired(random_advancer):
            if x.totalSupply >= 1:
                self.option_tokens_expired[x.address] = x

            else:
                self.option_tokens_expired_to_burn[x.address] = x

            # need to remove expired tokens from reset for long running sims
            if x.address in self.option_tokens:
                del self.option_tokens[x.address]

        self.options_exchange.option_tokens = self.option_tokens

        '''
            UPDATE FEEDS WHEN LASTEST DAY PASSESS
            UPDATE SYMBOL PARAMS
        '''

        #if (datetime.datetime.fromtimestamp(current_timestamp, tz=datetime.timezone.utc).date() > datetime.datetime.fromtimestamp(self.prev_timestamp, tz=datetime.timezone.utc).date()):
        if (datetime.datetime.fromtimestamp(current_timestamp).date() > datetime.datetime.fromtimestamp(self.prev_timestamp).date()):
            
            if self.prev_timestamp > 0:
                # increment round id
                self.current_round_id += 1

            tx = transaction_helper(
                seleted_advancer,
                self.btcusd_agg.functions.appendRoundId(
                    self.current_round_id
                ),
                500000
            )
            receipt = w3.eth.waitForTransactionReceipt(tx, poll_latency=tx_pool_latency, timeout=600)
            print("appendRoundId:", receipt)

            tx = transaction_helper(
                seleted_advancer,
                self.btcusd_agg.functions.appendAnswer(
                    self.btcusd_data[self.current_round_id]
                ),
                500000
            )
            receipt = w3.eth.waitForTransactionReceipt(tx, poll_latency=tx_pool_latency, timeout=600)
            print("appendAnswer:", receipt)

            tx = transaction_helper(
                seleted_advancer,
                self.btcusd_agg.functions.appendUpdatedAt(
                    current_timestamp
                ),
                500000
            )
            receipt = w3.eth.waitForTransactionReceipt(tx, poll_latency=tx_pool_latency, timeout=600)
            print("appendUpdatedAt:", receipt)

            self.options_exchange.prefetch_daily(seleted_advancer, self.current_round_id, self.daily_vol_period * self.daily_period)


            '''
                Prepare JSON data

                {
                    "BTC/USD": {
                        "vol": 0.04,
                        "data": [
                            {"strike": 1234, "option_type": "PUT", vol}
                        ],
                    }
                }
            '''
            maturity = None
            with open('mcmc_symbol_params.json', 'w+') as f:
                mcmc_data = {}
                for sym in available_symbols:
                    print('update symbol param file:', sym)
                    sym_parts = sym.split('-')

                    strike = int(float(sym_parts[2]) / 10**EXCHG['decimals'])
                    maturity = int(sym_parts[3])
                    
                    option_type = 'PUT' if sym_parts[1] == 'EP' else 'CALL'
                    current_price = self.btcusd_data[self.current_round_id] / (10.**BTCUSDAgg['decimals'])

                    if sym_parts[0] in mcmc_data:
                        # just append new strike data
                        mcmc_data[sym_parts[0]]["data"].append({
                            "strike": strike, 
                            "option_type": option_type,
                            "symbol": sym
                        })
                    else:
                        # need to calc feed vol
                        # NEED TO MAKE SURE THAT THE DECIMALS ARE CORRECT WHEN NORMING VOL
                        try:
                            vol = self.btcusd_chainlink_feed.caller({'from' : random_advancer.address, 'gas': 8000000}).getDailyVolatility(
                                self.daily_vol_period * self.daily_period
                            )
                        except Exception as inst:
                            print(inst, "bad vol calc")
                            continue

                        multiplier = 3.0
                        tvol = (vol / (10.**EXCHG['decimals']))
                        normed_vol = math.log((current_price + (tvol * multiplier)) / (current_price - (tvol * multiplier)))

                        mcmc_data[sym_parts[0]] = {}
                        mcmc_data[sym_parts[0]]["curr_price"] = current_price
                        mcmc_data[sym_parts[0]]["vol"] = normed_vol
                        mcmc_data[sym_parts[0]]["data"] = [{
                            "strike": strike, 
                            "option_type": option_type,
                            "symbol": sym
                        }]

                f.write(json.dumps(mcmc_data, indent=4))


            

            if maturity != None:
                '''
                    EXECUTE MODEL HERE FOR ALL DATA
                    EXAMPLE: ./op_model "2000" "0.2" "3.0"
                '''
                days_until_expiry = (maturity - current_timestamp) / self.daily_period
                months_to_exp = days_until_expiry / (self.days_per_year / 12.0)
                num_samples = 2000

                cmd = './op_model "%s" "%s" "%s"' % (
                    num_samples,
                    0.05,
                    months_to_exp,
                )
                model_ret = str(execute_cmd(cmd))


                '''
                    LOAD IN FILE AND MAP DATA TO PAIR
                '''
                with open('mcmc_symbol_computation.json', 'r+') as f:
                    mcmc_symbol_computation = json.loads(f.read())
                    if mcmc_symbol_computation:
                        for sym in available_symbols:
                            print('update symbol:', sym)
                            sym_parts = sym.split('-')

                            if (sym in mcmc_symbol_computation) and mcmc_symbol_computation[sym]:
                                x0s = mcmc_symbol_computation[sym]['x']
                                if len(x0s) == 0:
                                    continue

                                try:
                                    x = [Balance.from_tokens(round(x0,4), EXCHG['decimals']).to_wei() for x0 in x0s]
                                    y = mcmc_symbol_computation[sym]['y0'] + mcmc_symbol_computation[sym]['y1']
                                    y  = [Balance.from_tokens(round(y0,4), EXCHG['decimals']).to_wei() for y0 in y]
                                    print(x)
                                    print(y)
                                except Exception as inst:
                                    print(inst, "no timestamp data to update")
                                    x = [0, 0]
                                    y = [0, 0, 0, 0]

                                strike = int(float(sym_parts[2]) / 10**EXCHG['decimals'])
                                option_type = 'PUT' if sym_parts[1] == 'EP' else 'CALL'
                                current_timestamp = w3.eth.get_block('latest')['timestamp']
                                sym_upd8_tx = self.linear_liquidity_pool.update_symbol(seleted_advancer, self.btcusd_chainlink_feed.address, strike, int(sym_parts[3]), option_type, current_timestamp, x, y, buyStock, sellStock)
                                receipt = w3.eth.waitForTransactionReceipt(sym_upd8_tx, poll_latency=tx_pool_latency, timeout=600)
                                print('update hash:', receipt)

            
            '''
                TODO: NEED TO DUMP TO FILE AND LOAD FROM FILE IN ORDER TO BE ABLE TO START AND STOP MORE ROBUSTLY SANS NUKING CONTRACTS
            '''
            self.prev_timestamp = current_timestamp

            print("current prev_timestamp daily:", self.prev_timestamp)


        logger.info("Clock: {}".format(current_timestamp))
        logger.info("current_round_id: {}".format(self.current_round_id))

        shuffled_agents = list(range(len(self.agents)))
        random.shuffle(shuffled_agents)

        # return list of addres for agents who are short collateral
        any_short_collateral = []
        while True:
            try:
                any_short_collateral = [a for a in self.agents if self.options_exchange.calc_collateral_surplus(random_advancer, a) <= 0]
                break
            except Exception as inst:
                print(inst, 'trying to pretetch sample')
                self.options_exchange.prefetch_sample(random_advancer)
                break

        
        tx_hashes = []
        total_tx_submitted = 0

        unique_available_symbols = list(set([asym.split('-')[1] for asym in available_symbols]))
        tks_list_symbols = [tv.symbol for tv in list(self.option_tokens.values())]

        pool_free_balance = self.linear_liquidity_pool.pool_free_balance(random_advancer)
        logger.info("pool_free_balance: {}".format(pool_free_balance))

        any_calls = any([ts for ts in available_symbols if '-EC-' in ts])
        any_puts = any([ts for ts in available_symbols if '-EP-' in ts])

        print("available_symbols:", available_symbols, len(available_symbols), len(tks_list_symbols))
        print((not any_calls or not any_puts))

        self.has_tried_liquidating = False

        max_symbols_per_type = 10

        for agent_num in shuffled_agents:            
            # TODO: real strategy
            a = self.agents[agent_num]
            options = []

            open_option_tokens = self.is_positive_option_token_balance(a)
            open_option_expired_tokens = self.is_positve_option_token_expired_balance(a)

            exchange_bal  = self.options_exchange.balance(a)
            pool_free_balance = self.linear_liquidity_pool.pool_free_balance(a)
            exchange_free_bal = Balance.from_tokens(0, EXCHG['decimals'])
            try:
                exchange_free_bal = self.options_exchange.calc_collateral_surplus(a, a)
            except Exception as inst:
                pass


            #'''
            #TODO: NEED A BETTER WAY TO FIGURE THIS OUT FOR SYMBOLS THAT FAIL TO UPDATE/HAVE ANY POS TXs
            available_symbols = self.linear_liquidity_pool.list_symbols(seleted_advancer)
            any_calls = [ts for ts in available_symbols if '-EC-' in ts]
            any_puts = [ts for ts in available_symbols if '-EP-' in ts]

            if len(available_symbols) != len(self.option_tokens):
                #TRY AND UPDATE OPTION TOKENS AVAILABLE
                for x in self.linear_liquidity_pool.get_option_tokens(seleted_advancer):
                    if x.address not in self.option_tokens:
                        self.option_tokens[x.address] = x

            tks_list_symbols = [tv.symbol for tv in list(self.option_tokens.values())]
            self.options_exchange.option_tokens = self.option_tokens
            #'''

            if exchange_bal > 0 and len(available_symbols) > 0 and (pool_free_balance > exchange_bal):
                options.append('write')

            if (exchange_bal > 0 or pool_free_balance > 0) and ((len(any_calls) < max_symbols_per_type or len(any_puts) < max_symbols_per_type) or (len(available_symbols) < max_symbols_per_type*2)):
                options.append('add_symbol')

            if len(available_symbols) != len(tks_list_symbols):
                options.append('create_symbol')


            '''
            if (exchange_bal > 0) and len(self.option_tokens) > 0 and (a.total_written <= a.total_holding):
                options.append('buy')
            '''

            if (a.total_holding > 1 or a.total_written > 1) and (pool_free_balance > 0):
                options.append('sell')

            if (a.usdt > 0 and a.total_written < 1 and len(available_symbols) != len(self.option_tokens)) or (len(available_symbols) < max_symbols_per_type*2):
                options.append('deposit_exchange')

            #len(available_symbols) != len(self.option_tokens) is to limit deposits to pool
            if (a.usdt > 0 and a.total_written < 1 and a.total_holding < 1 and len(available_symbols) != len(self.option_tokens)) or (len(available_symbols) < max_symbols_per_type*2):
                options.append('deposit_pool')

            if exchange_free_bal > 0:
                options.append('withdraw')

            '''
            TODO:
                can only redeem after pool expires
            if a.lp > 0:
                options.append('redeem_pool')
            '''

            # option position must be short collateral
            '''
            TODO:
                Test later, since only book positions are pretty much have the pool as the owner for options issued
            '''
            if len(any_short_collateral) > 0 and not self.has_tried_liquidating:
                options.append('liquidate')

            # liquidate expired positons
            if (len(any_short_collateral) > 0) or open_option_expired_tokens or (len(self.option_tokens_expired) > 0):
                options.append('liquidate_self')
                options.append('redeem_token')

            #'''
            if len(self.option_tokens_expired_to_burn) > 0 or len(self.option_tokens) > 0:
                options.append('burn_token')
            #'''


            start_tx_count = a.next_tx_count
            commitment = random.random() * 0.01

            if len(options) > 0:
                # We can act

                '''
                    LATER:
                        advance: to do maintainence functions, payout from dynamic collateral and/or gov token
                    
                    TODO:
                        burn_pool?

                    TOTEST:
                        burn_pool?

                    TOTESTLATER:
                        burn_token (may not be needed, handled by liquidation of option token), redeem_pool (can only reedeem after expiration)
                    WORKS:
                        deposit_exchange, deposit_pool, add_symbol, update_symbol, write, create_symbol, buy, liquidate_self, liquidate, withdraw, sell, redeem_token
                        
                '''
        
                strategy = a.get_strategy(w3.eth.get_block('latest')["number"])
                
                weights = [strategy[o] for o in options]
                
                action = random.choices(options, weights=weights)[0]
                
                # What fraction of the total possible amount of doing this
                # action will the agent do?
                
                
                if action == "deposit_exchange":
                    amount = portion_dedusted(
                        a.usdt,
                        commitment * 0.1
                    )
                    try:
                        dpe_hash = self.options_exchange.deposit_exchange(a, amount)
                        tx_hashes.append({'type': 'deposit_exchange', 'hash': dpe_hash})
                    except Exception as inst:
                        logger.info({"agent": a.address, "error": inst, "action": "deposit_exchange", "amount": amount})
                elif action == "add_symbol":
                    option_types = ['PUT', 'CALL']
                    # NEED TO MAKE SURE THAT THE DECIMALS ARE CORRECT WHEN NORMING STRIKES
                    current_price = self.btcusd_data[self.current_round_id] / (10.**BTCUSDAgg['decimals'])

                    """
                    TODO:
                        choose random maturity length less than the maturity of the pool? 1 month for now
                    """
                    current_timestamp = w3.eth.get_block('latest')['timestamp']
                    num_months = 6.0 # 1.0
                    maturity = int(current_timestamp + (self.daily_period * (self.days_per_year / self.months_per_year * num_months)))
                    days_until_expiry = (maturity - current_timestamp) / self.daily_period
                    months_to_exp = days_until_expiry / (self.days_per_year / 12.0)
                    num_samples = 2000
                    option_type = option_types[0 if random.random() > 0.5 else 1]

                    is_otm_only = False

                    moneyness = max(0.0, random.random())

                    if not is_otm_only:
                        if random.random() > 0.5:
                            strike = round(current_price * (1 + moneyness))
                        else:
                            strike = round(current_price * (1 - moneyness))

                    else:
                        if option_type == 'CALL':
                            # if call, write OTM by random amout, to the upside
                            strike = round(current_price * (1 + moneyness))
                        else:
                            # if put, write OTM by random amount, to the downside
                            strike = round(current_price * (1 - moneyness))

                    with open('mcmc_symbol_params.json', 'w+') as f:
                        mcmc_data = {}
                        # need to calc feed vol
                        # NEED TO MAKE SURE THAT THE DECIMALS ARE CORRECT WHEN NORMING VOL
                        try:
                            vol = self.btcusd_chainlink_feed.caller({'from' : random_advancer.address, 'gas': 8000000}).getDailyVolatility(
                                self.daily_vol_period * self.daily_period
                            )
                        except Exception as inst:
                            print(inst, "bad vol calc")
                            continue

                        multiplier = 3.0
                        tvol = (vol / (10.**EXCHG['decimals']))
                        normed_vol = math.log((current_price + (tvol * multiplier)) / (current_price - (tvol * multiplier)))

                        mcmc_data["pending"] = {}
                        mcmc_data["pending"]["curr_price"] = self.btcusd_data[self.current_round_id] / (10.**BTCUSDAgg['decimals'])
                        mcmc_data["pending"]["vol"] = normed_vol
                        mcmc_data["pending"]["data"] = [{
                            "strike": strike, 
                            "option_type": option_type,
                            "symbol": "pending"
                        }]

                        f.write(json.dumps(mcmc_data, indent=4))

                    '''
                        EXECUTE MODEL HERE FOR ALL DATA
                    '''

                    '''
                        EXAMPLE: ./op_model "2000" "0.2" "3.0"
                    '''
                    cmd = './op_model "%s" "%s" "%s"' % (
                        num_samples,
                        0.05,
                        months_to_exp,
                    )
                    model_ret = str(execute_cmd(cmd))


                    '''
                        LOAD IN FILE AND MAP DATA TO PAIR
                    '''
                    with open('mcmc_symbol_computation.json', 'r+') as f:
                        mcmc_symbol_computation = json.loads(f.read())
                        if mcmc_symbol_computation:
                            if mcmc_symbol_computation["pending"]:
                                x0s = mcmc_symbol_computation["pending"]['x']
                                if len(x0s) == 0:
                                    continue

                                try:
                                    x = [Balance.from_tokens(round(x0,4), EXCHG['decimals']).to_wei() for x0 in x0s]
                                    y = mcmc_symbol_computation["pending"]['y0'] + mcmc_symbol_computation["pending"]['y1']
                                    y  = [Balance.from_tokens(round(y0,4), EXCHG['decimals']).to_wei() for y0 in y]
                                    print(x)
                                    print(y)
                                except Exception as inst:
                                    print ('failed to add_symbol')
                                    continue

                                try:
                                    # must be the selected advancer or governane proposoal
                                    ads_hash = self.linear_liquidity_pool.add_symbol(seleted_advancer, self.btcusd_chainlink_feed.address, strike, maturity, option_type, current_timestamp, x, y, buyStock, sellStock)
                                    providerAvax.make_request("avax.issueBlock", {})
                                    receipt = w3.eth.waitForTransactionReceipt(ads_hash, poll_latency=tx_pool_latency, timeout=600)
                                    tx_hashes.append({'type': 'add_symbol', 'hash': ads_hash})
                                except Exception as inst:
                                    logger.info({"agent": a.address, "error": inst, "action": "add_symbol", "strike": strike, "maturity": maturity, "x": x, "y": y, "normed_vol": normed_vol, "vol": vol})
                elif action == "create_symbol":
                    for sym in available_symbols:
                        if sym not in tks_list_symbols:

                            try:
                                cs_hash = self.options_exchange.create_symbol(a, sym, self.btcusd_chainlink_feed)
                                providerAvax.make_request("avax.issueBlock", {})
                                receipt = w3.eth.waitForTransactionReceipt(cs_hash, poll_latency=tx_pool_latency, timeout=600)
                                tx_hashes.append({'type': 'create_symbol', 'hash': cs_hash})
                            except Exception as inst:
                                logger.info({"agent": a.address, "error": inst, "action": "create_symbol", "sym": sym })
                                continue
                elif action == "deposit_pool":
                    amount = portion_dedusted(
                        a.usdt,
                        commitment * 0.1
                    )
                    try:
                        dpp_hash = self.linear_liquidity_pool.deposit_pool(a, amount)
                        tx_hashes.append({'type': 'deposit_pool', 'hash': dpp_hash})
                    except Exception as inst:
                        logger.info({"agent": a.address, "error": inst, "action": "deposit_pool", "amount": amount})
                elif action == "withdraw":
                    amount = portion_dedusted(
                        exchange_free_bal,
                        commitment * 10.0
                    )
                    try:
                        logger.info("Before Withdraw; volume: {} exchange_free_bal: {}".format(amount, exchange_free_bal))
                        wtd_hash = self.options_exchange.withdraw(a, amount)
                        tx_hashes.append({'type': 'withdraw', 'hash': wtd_hash})
                    except Exception as inst:
                        logger.info({"agent": a.address, "error": inst, "action": "withdraw", "amount": amount})
                elif action == "redeem_pool":
                    try:
                        logger.info("Before Redeem Pool Shares")
                        rdm_hash = self.linear_liquidity_pool.redeem_pool(a)
                        tx_hashes.append({'type': 'redeem_pool', 'hash': rdm_hash})
                    except Exception as inst:
                        logger.info({"agent": a.address, "error": inst, "action": "redeem_pool"})
                elif action == "redeem_token":
                    for otk, otv in self.option_tokens_expired.items():
                        if otv[a] > 0:
                            try:
                                logger.info("Before Redeem Option: {}, {}".format(otv.symbol, otv[a]))
                                rdmt_hash = self.options_exchange.redeem_token(a, otk)
                                tx_hashes.append({'type': 'redeem_token', 'hash': rdmt_hash})
                            except Exception as inst:
                                logger.info({"agent": a.address, "error": inst, "action": "redeem_token", "option_token": otv.address})
                elif action == "burn_token":
                    '''
                    for otk, otv in self.option_tokens_expired_to_burn.items():
                        if otv[a] > 0:
                            try:
                                logger.info("Before Burn Expired Option: {}".format(otv.symbol))
                                rdmt_hash = self.options_exchange.redeem_token(a, otk)
                                tx_hashes.append({'type': 'burn_token', 'hash': rdmt_hash})
                            except Exception as inst:
                                logger.info({"agent": a.address, "error": inst, "action": "burn_token", "option_token": otv.address})
                    '''

                    for otk, otv in self.option_tokens.items():
                        owv = Balance(otv.contract.caller({'from' : a.address, 'gas': 100000}).writtenVolume(a.address), EXCHG['decimals'])
                        if owv > 0 and otv[a] > 0:
                            # written > holding
                            token_amount = Balance(owv.to_wei() - otv[a].to_wei(), EXCHG['decimals'])

                            if token_amount > 0:
                                try:
                                    logger.info("Before Burn Excess Options: {}, token_amount: {}".format(otv.symbol, token_amount))
                                    burn_hash = self.options_exchange.burn_token(a, otk, token_amount)
                                    tx_hashes.append({'type': 'burn_token', 'hash': burn_hash})
                                except Exception as inst:
                                    logger.info({"agent": a.address, "error": inst, "action": "burn_token", "option_token": otv.address})

                elif action == "write":
                    # select from available symbols
                    sym = available_symbols[int(random.random() * (len(available_symbols) - 1))]
                    sym_parts = sym.split('-')

                    '''
                        * sym is something like: `ETH/USD-EC-13e20-1611964800` which represents an ETH european call option with strike price US$ 1300 and maturity at timestamp `1611964800`.
                    '''
                    strike_price = int(float(sym_parts[2]))
                    maturity = int(sym_parts[3])
                    option_type = 'PUT' if sym_parts[1] == 'EP' else 'CALL'
                    amount = int(round(portion_dedusted(
                        buyStock,
                        commitment
                    )))

                    logger.info("Looking to Write; symbol: {}, strike_price: {}, amount: {}, exchange_bal: {}".format(sym, strike_price, amount, exchange_bal))

                    try:
                        cc  = self.options_exchange.calc_collateral(a, self.btcusd_chainlink_feed.address, option_type, amount, strike_price, maturity)
                        cc_s = self.options_exchange.calc_collateral_surplus(a, a)
                    except Exception as inst:
                        print(inst)
                        continue

                    if cc_s < 1:
                        continue

                    if(cc > cc_s):
                        amount /= (cc.to_wei() / cc_s.to_wei())
                        logger.info("Norm to Write; amount: {}".format(amount))

                    if amount < 1:
                        continue

                    try:
                        logger.info("Before Write; symbol: {}, strike_price: {}, amount: {}".format(sym, strike_price, amount))
                        w_hash = self.options_exchange.write(a, self.btcusd_chainlink_feed.address, option_type, amount, strike_price, maturity)
                        tx_hashes.append({'type': 'write', 'hash': w_hash})
                    except Exception as inst:
                        logger.info({"agent": a.address, "error": inst, "action": "write", "strike_price": strike_price, "maturity": maturity, "option_type": option_type, "amount": amount})
                elif action == "buy":
                    tks_list = list(self.option_tokens.values())
                    option_token_to_buy = tks_list[int(random.random() * (len(tks_list) - 1))]
                    symbol = option_token_to_buy.contract.caller({'from' : a.address, 'gas': 8000000}).symbol()
                    option_token_balance_of_pool = Balance(
                        option_token_to_buy.contract.caller({'from' : a.address, 'gas': 8000000}).writtenVolume(self.linear_liquidity_pool.address),
                        EXCHG['decimals']
                    )
                    print(symbol, option_token_balance_of_pool)
                    try:
                        current_price_volume = self.linear_liquidity_pool.query_buy(a, symbol)
                    except Exception as inst:
                        print("\terror querying buy", inst)
                        continue

                    if option_token_balance_of_pool >= buyStock:
                        continue
                    
                    print(symbol, current_price_volume, option_token_balance_of_pool, exchange_bal, 'BUY')
                    volume = Balance(current_price_volume[1], EXCHG['decimals'])

                    price = current_price_volume[0]

                    if (volume * (price / 10.**EXCHG['decimals']) * 100) > exchange_bal:
                        '''
                        sym_parts = symbol.split('-')
                        strike_price = int(float(sym_parts[2]))
                        maturity = int(sym_parts[3])
                        option_type = 'PUT' if sym_parts[1] == 'EP' else 'CALL'
                        try:
                            cc = self.options_exchange.calc_collateral(a, self.btcusd_chainlink_feed.address, option_type, volume, strike_price, maturity)
                        except:
                            continue
                        '''          
                        mod_price = Balance(price, EXCHG['decimals'])
                        print("mod_price", mod_price, mod_price.to_decimals(EXCHG['decimals']), mod_price.to_decimals(EXCHG['decimals']).to_wei(), exchange_bal.to_wei(), volume)
                        volume = Balance.from_tokens(int((exchange_bal.to_wei() / mod_price.to_decimals(EXCHG['decimals']).to_wei()) / 10), EXCHG['decimals'])


                    if volume < 1:
                        volume = Balance.from_tokens(1, EXCHG['decimals'])

                    
                    try:
                        logger.info("Before Buy; symbol: {}, price: {}, volume: {}".format(symbol, price, volume))
                        buy_hash = self.linear_liquidity_pool.buy(a, symbol, price, volume)
                        providerAvax.make_request("avax.issueBlock", {})
                        tx_hashes.append({'type': 'buy', 'hash': buy_hash})
                    except Exception as inst:
                        logger.info({"agent": a.address, "error": inst, "action": "buy", "volume": volume, "price": price, "symbol": symbol})
                elif action == "sell":
                    option_token_to_sell = None
                    symbol = None
                    volume_to_sell = Balance(0, EXCHG['decimals'])
                    current_price_volume = None
                    for k, ot in self.option_tokens.items():
                        volume_to_sell = Balance(ot.contract.caller({'from' : a.address, 'gas': 8000000}).balanceOf(a.address), EXCHG['decimals'])
                        if volume_to_sell > 1:
                            option_token_to_sell = ot
                            
                            if not option_token_to_sell:
                                continue
                            
                            symbol = option_token_to_sell.contract.caller({'from' : a.address, 'gas': 8000000}).symbol()
                            try:
                                current_price_volume = self.linear_liquidity_pool.query_sell(a, symbol)
                            except Exception as inst:
                                print("\terror querying sell", inst)
                                continue

                            if volume_to_sell >= sellStock:
                                print(volume_to_sell, ">", sellStock, "CANT SELL")
                                continue

                            break

                    if not current_price_volume:
                        continue


                    print(symbol, current_price_volume, volume_to_sell, a.total_written, a.total_holding, 'SELL')
                    
                    if a.total_written > 0 and ((a.total_written >= a.total_holding) or (a.total_written < a.total_holding)):
                        # for exchange writers
                        volume = volume_to_sell
                    elif a.total_holding > 0 and a.total_written == 0:
                        # for traders
                        volume = portion_dedusted(
                            volume_to_sell,
                            commitment
                        )
                    
                    if volume == 0:
                        volume = Balance.from_tokens(1, EXCHG['decimals'])
                    price = current_price_volume[0] - (int(current_price_volume[0] * 0.001))
                    
                    try:
                        logger.info("Before Sell; symbol: {}, price: {}, volume: {}".format(symbol, price, volume))
                        sell_hash = self.linear_liquidity_pool.sell(a, symbol, price, volume, option_token_to_sell)
                        tx_hashes.append({'type': 'sell', 'hash': sell_hash, "volume": volume, "price": price, "symbol": symbol})
                    except Exception as inst:
                        logger.info({"agent": a.address, "error": inst, "action": "sell", "volume": volume, "price": price, "symbol": symbol})
                elif action == "liquidate":
                    for short_owner in any_short_collateral:
                        if short_owner.total_written > 1: 
                            for otk, otv in self.option_tokens.items():
                                if otv.contract.caller({'from' : a.address, 'gas': 8000000}).writtenVolume(short_owner.address) > 0:
                                    try:
                                        lqd8_hash = self.options_exchange.liquidate(a, otk, short_owner.address)
                                        tx_hashes.append({'type': 'liquidate', 'hash': lqd8_hash})
                                    except Exception as inst:
                                        logger.info({"agent": a.address, "error": inst, "action": "liquidate", "short_owner": short_owner.address, "option_token": otk})

                    self.has_tried_liquidating = True
                elif action == "liquidate_self":
                    for otk, otv in self.option_tokens_expired.items():
                        if otv[a] > 0:
                            try:
                                lqd8_hash = self.options_exchange.liquidate(a, otk, self.linear_liquidity_pool.address)
                                tx_hashes.append({'type': 'liquidate_self', 'hash': lqd8_hash})
                            except Exception as inst:
                                logger.info({"agent": a.address, "error": inst, "action": "liquidate_self", "option_token": otk})

                    for otk, otv in self.option_tokens.items():
                        if otv[a] > 0:
                            try:
                                lqd8_hash = self.options_exchange.liquidate(a, otk, a.address)
                                tx_hashes.append({'type': 'liquidate_self', 'hash': lqd8_hash})
                            except Exception as inst:
                                logger.info({"agent": a.address, "error": inst, "action": "liquidate_self", "short_owner": a.address, "option_token": otk})

                else:
                    raise RuntimeError("Bad action: " + action)
                    
                anyone_acted = True
            else:
                # It's normal for agents other then the first to advance to not be able to act on block 0.
                pass

            end_tx_count = a.next_tx_count

            total_tx_submitted += (end_tx_count - start_tx_count)

        providerAvax.make_request("avax.issueBlock", {})

        tx_hashes_good = 0
        tx_fails = []
        tx_good = []
        #'''
        for tmp_tx_hash in tx_hashes:
            receipt = w3.eth.waitForTransactionReceipt(tmp_tx_hash['hash'], poll_latency=tx_pool_latency, timeout=600)
            tx_hashes_good += receipt["status"]
            if receipt["status"] == 0:
                tx_fails.append(tmp_tx_hash)
            else:
                tx_good.append(tmp_tx_hash)

        #'''

        logger.info("total tx: {}, successful tx: {}, tx fails: {}, tx passed: {}".format(
                len(tx_hashes), tx_hashes_good, tx_fails, tx_good
            )
        )

        return True, random_advancer, tx_good

def main():
    """
    Main function: run the simulation.
    """
    global avax_cchain_nonces

    '''
        curl -X POST --data '{ "jsonrpc":"2.0", "id" :1, "method" :"debug_increaseTime", "params" : ["0x45e8d9a7ca159a0f6957534cb25412b4daa4243906ef2b6e93125246b1e27d05"]}' -H 'content-type:application/json;' http://127.0.0.1:9545/ext/bc/C/rpc
    '''
    transaction = w3.eth.get_transaction("0x5d385ebc44b8e1e6c01b24ef2a13fa574649d0993cae859a63af64ecc11f5851")

    print(transaction.input)
    #print(provider.make_request("debug_traceTransaction", ["0x45e8d9a7ca159a0f6957534cb25412b4daa4243906ef2b6e93125246b1e27d05"]))
    #print(w3.eth.get_block('latest')['timestamp'])
    #

    
    logging.basicConfig(level=logging.INFO)
    logger.info('Total Agents: {}'.format(len(w3.eth.accounts[:max_accounts])))

    
    options_exchange = w3.eth.contract(abi=OptionsExchangeContract['abi'], address=EXCHG["addr"])
    proposal_wrapper = w3.eth.contract(abi=ProposalWrapperContract['abi'], address=PROPSWRPR["addr"])
    proposal_manager = w3.eth.contract(abi=ProposalManagerContract['abi'], address=PROPSMNGER["addr"])
    proposal_manager_helper = w3.eth.contract(abi=ProposalManagerHelperContract['abi'], address=PROPSMNGERHELPER["addr"])
    usdt = TokenProxy(w3.eth.contract(abi=USDTContract['abi'], address=USDT["addr"]))
    credit_provider = w3.eth.contract(abi=CreditProviderContract['abi'], address=CREDPRO["addr"])
    linear_liquidity_pool_factory = w3.eth.contract(abi=LinearLiquidityPoolFactoryContract['abi'], address=LLPF["addr"])
    protocol_settings = w3.eth.contract(abi=ProtocolSettingsContract['abi'], address=STG['addr'])
    btcusd_chainlink_feed = w3.eth.contract(abi=ChainlinkFeedContract['abi'], address=BTCUSDc['addr'])
    btcusd_agg = w3.eth.contract(abi=AggregatorV3MockContract['abi'], address=BTCUSDAgg["addr"])

    #print(btcusd_chainlink_feed.caller({'from' : w3.eth.accounts[0], 'gas': 8000000}).getLatestPrice())
    #sys.exit()
    
    mock_time = w3.eth.contract(abi=TimeProviderMockContract['abi'], address=TPRO["addr"])


    #''
    #print(credit_provider.caller({'from' : w3.eth.accounts[0], 'gas': 8000000}).balanceOf(linear_liquidity_pool.address))
    print("tx-input -> 0xa53b0041")
    print(proposal_wrapper.decode_function_input("0x5e4d3229"))
    #print(proposal_manager.decode_function_input(transaction.input))

    #print(
    #proposal_manager_helper.caller({'from' : w3.eth.accounts[0], 'gas': 8000000}).getExecutionBytes())


    #sys.exit()

    #''
    '''
        INIT FEEDS FOR BTCUSDAGG
    '''
    btcusd_historical_ohlc = []

    '''
    for acc in w3.eth.accounts[:max_accounts]:
        cs = options_exchange.caller({'from' : acc, 'gas': 8000000}).calcSurplus(acc)
        print(acc, cs)
        '''
    #print(linear_liquidity_pool.caller({'from' : w3.eth.accounts[:max_accounts][0], 'gas': 8000000}).listExpiredSymbols())
    #pretty(options_exchange.functions.resolveToken("BTC/USD-EP-147e18-1623989786").call(), indent=0)
    #print(linear_liquidity_pool.functions.totalSupply().call())
    #print(Balance(4.474093538197649, 18).to_wei())

    #sys.exit()
    '''
    with open('../../data/BTC-USD_vol_date_high_low_close.json', 'r+') as btcusd_file:
        btcusd_historical_ohlc = json.loads(btcusd_file.read())["chart"]
    

    daily_period = 60 * 60 * 24
    current_timestamp = int(w3.eth.get_block('latest')['timestamp'])
    print("current_timestamp", current_timestamp)

    btcusd_answers = []
    start_date = "2017-06-17"#"2017-12-17"
    btcusd_data_offset = 0
    btcusd_data_subtraction_set = 30 # look back period to present to seed data for vol calcs
    start_data_parsing = False # change this if you want to skip foward to specific time period
    for xidx, x in enumerate(btcusd_historical_ohlc):


        if start_data_parsing is False:
            if x['date'] == start_date:
                start_data_parsing = True
                btcusd_data_offset = xidx


        if x["open"] != 'null':
            btcusd_answers.append(int(float(x["open"]) * (10**BTCUSDAgg['decimals'])))

    if btcusd_data_offset <  btcusd_data_subtraction_set:
        btcusd_data_subtraction_set = btcusd_data_offset

    btcusd_answers = btcusd_answers[btcusd_data_offset-btcusd_data_subtraction_set:]

    print('btcusd_data_offset', btcusd_data_offset, start_date)
    '''

    avax_cchain_nonces = open(MMAP_FILE, "r+b")

    tx_hashes = []
    tx_hashes_good = 0
    tx_fails = []

    linear_liquidity_pool_address = None
    linear_liquidity_pool = None
    #''
  # opx = OptionsExchange(options_exchange, usdt, btcusd_chainlink_feed)
    opx = OptionsExchange(options_exchange, usdt, [])
    if not linear_liquidity_pool_address:
        # temp opx, llp, agent
        agent = Agent(None, opx, None, None, usdt, starting_axax=0, starting_usdt=0, wallet_address=w3.eth.accounts[0], is_mint=False)
        '''
        p_hash = transaction_helper(
            agent,
            opx.contract.functions.createPool(
                "DEFAULT",
                "TEST",
            ),
            8000000
        )
        tmp_tx_hash = {'type': 'createPool', 'hash': p_hash}
        print(tmp_tx_hash)
        receipt = w3.eth.waitForTransactionReceipt(tmp_tx_hash['hash'], poll_latency=tx_pool_latency)
        tx_hashes.append(tmp_tx_hash)
        tx_hashes_good += receipt["status"]    
        if receipt["status"] == 0:
            print(receipt)
            tx_fails.append(tmp_tx_hash['type'])
        logs = options_exchange.events.CreatePool().processReceipt(receipt)
        print("linear pool address", logs[0].args.token)
        linear_liquidity_pool_address = logs[0].args.token
        linear_liquidity_pool = w3.eth.contract(abi=LinearLiquidityPoolContract["abi"], address=linear_liquidity_pool_address)
        '''
    else:
        linear_liquidity_pool = w3.eth.contract(abi=LinearLiquidityPoolContract["abi"], address=linear_liquidity_pool_address)
    '''
    _llp = LinearLiquidityPool(linear_liquidity_pool, usdt, opx)
    agent = Agent(_llp, opx, None, None, usdt, starting_axax=0, starting_usdt=0, wallet_address=w3.eth.accounts[0], is_mint=False)
    '''
    '''
        BELOW: USE FOR TESTNET FUNDING OF FAKE STABLECOIN
    '''
    
    sat_hash = transaction_helper(
        agent,
        protocol_settings.functions.setAllowedToken(
            usdt.address,
            1,
            10**(18 - usdt.decimals)
        ),
        500000
    )
    tmp_tx_hash = {'type': 'setAllowedToken', 'hash': sat_hash}
    tx_hashes.append(tmp_tx_hash)
    print(tmp_tx_hash)
    receipt = w3.eth.waitForTransactionReceipt(tmp_tx_hash['hash'], poll_latency=tx_pool_latency)
    tx_hashes_good += receipt["status"]
    if receipt["status"] == 0:
        print(receipt)
        tx_fails.append(tmp_tx_hash['type'])

    

    msp_hash= transaction_helper(
        agent,
        protocol_settings.functions.setMinShareForProposal(
            10,
            1000
        ),
        500000
    )
    tmp_tx_hash = {'type': 'setMinShareForProposal', 'hash': msp_hash}
    tx_hashes.append(tmp_tx_hash)
    print(tmp_tx_hash)
    receipt = w3.eth.waitForTransactionReceipt(tmp_tx_hash['hash'], poll_latency=tx_pool_latency)
    tx_hashes_good += receipt["status"]
    if receipt["status"] == 0:
        print(receipt)
        tx_fails.append(tmp_tx_hash['type'])


    
    sys.exit()

    '''
        ABOVE: FR TESTNET FUNDING OF FAKE STABLECOIN
    '''


    '''
        SETUP POOL:
            All options must have maturities under the pool maturity
    '''


    pool_spread = 5 * (10**7) #5% 
    pool_reserve_ratio = 0 * (10**7) # 20% default
    pool_maturity = (1000000000 * daily_period) + current_timestamp

    '''
        SETUP PROTOCOL SETTINGS FOR POOL
    '''
    skip = False

    if not skip:
        mt_hash = transaction_helper(
            agent,
            mock_time.functions.setFixedTime(
                -1
            ),
            500000
        )
        tmp_tx_hash = {'type': 'setFixedTime', 'hash': mt_hash}
        tx_hashes.append(tmp_tx_hash)
        print(tmp_tx_hash)
        receipt = w3.eth.waitForTransactionReceipt(tmp_tx_hash['hash'], poll_latency=tx_pool_latency)
        tx_hashes_good += receipt["status"]
        if receipt["status"] == 0:
            print(receipt)
            tx_fails.append(tmp_tx_hash['type'])

    if not skip:
        sp_hash = transaction_helper(
            agent,
            linear_liquidity_pool.functions.setParameters(
                pool_spread,
                pool_reserve_ratio,
                pool_maturity
            ),
            500000
        )
        tmp_tx_hash = {'type': 'setParameters', 'hash': sp_hash}
        tx_hashes.append(tmp_tx_hash)
        print(tmp_tx_hash)
        receipt = w3.eth.waitForTransactionReceipt(tmp_tx_hash['hash'], poll_latency=tx_pool_latency)
        tx_hashes_good += receipt["status"]
        if receipt["status"] == 0:
            print(receipt)
            tx_fails.append(tmp_tx_hash['type'])
    
    if not skip:
        so_hash = transaction_helper(
            agent,
            protocol_settings.functions.setOwner(
                agent.address,
            ),
            500000
        )
        tmp_tx_hash = {'type': 'setOwner', 'hash': so_hash}
        tx_hashes.append(tmp_tx_hash)
        print(tmp_tx_hash)
        receipt = w3.eth.waitForTransactionReceipt(tmp_tx_hash['hash'], poll_latency=tx_pool_latency)
        tx_hashes_good += receipt["status"]
        if receipt["status"] == 0:
            print(receipt)
            tx_fails.append(tmp_tx_hash['type'])

    
    if not skip:
        sat_hash = transaction_helper(
            agent,
            protocol_settings.functions.setAllowedToken(
                usdt.address,
                1,
                10**(18 - usdt.decimals)
            ),
            500000
        )
        tmp_tx_hash = {'type': 'setAllowedToken', 'hash': sat_hash}
        tx_hashes.append(tmp_tx_hash)
        print(tmp_tx_hash)
        receipt = w3.eth.waitForTransactionReceipt(tmp_tx_hash['hash'], poll_latency=tx_pool_latency)
        tx_hashes_good += receipt["status"]
        if receipt["status"] == 0:
            print(receipt)
            tx_fails.append(tmp_tx_hash['type'])
    
    if not skip:
        suf_hash = transaction_helper(
            agent,
            protocol_settings.functions.setUdlFeed(
                btcusd_chainlink_feed.address,
                1
            ),
            500000
        )
        tmp_tx_hash = {'type': 'setUdlFeed', 'hash': suf_hash}
        tx_hashes.append(tmp_tx_hash)
        print(tmp_tx_hash)
        receipt = w3.eth.waitForTransactionReceipt(tmp_tx_hash['hash'], poll_latency=tx_pool_latency)
        tx_hashes_good += receipt["status"]
        if receipt["status"] == 0:
            print(receipt)
            tx_fails.append(tmp_tx_hash['type'])

    if not skip:
        svp_hash = transaction_helper(
            agent,
            protocol_settings.functions.setVolatilityPeriod(
                30 * daily_period
            ),
            500000
        )
        tmp_tx_hash = {'type': 'setVolatilityPeriod', 'hash': svp_hash}
        tx_hashes.append(tmp_tx_hash)
        print(tmp_tx_hash)
        receipt = w3.eth.waitForTransactionReceipt(tmp_tx_hash['hash'], poll_latency=tx_pool_latency)
        tx_hashes_good += receipt["status"]
        if receipt["status"] == 0:
            print(receipt)
            tx_fails.append(tmp_tx_hash['type'])


    
    logger.info("total setup tx: {}, successful setup tx: {}, setup tx fails: {}".format(
            len(tx_hashes), tx_hashes_good, json.dumps(tx_fails)
        )
    )

    # Make a model of the options exchnage
    start_init = time.time()
    logger.info('INIT STARTED')
    model = Model(options_exchange, credit_provider, linear_liquidity_pool, btcusd_chainlink_feed, btcusd_agg, btcusd_answers, None, usdt, w3.eth.accounts[:max_accounts], min_faith=0.5E6, max_faith=1E6, use_faith=False)
    end_init = time.time()
    logger.info('INIT FINISHED {} (s)'.format(end_init - start_init))

    # Make a log file for system parameters, for analysis
    stream = open("log.tsv", "a+")
    
    for i in range(50000):
        # Every block
        # Try and tick the model
        start_iter = time.time()

        (anyone_acted, seleted_advancer, tx_passed) = model.step()
        if not anyone_acted:
            # Nobody could act
            logger.info("Nobody could act")
            break
        end_iter = time.time()
        logger.info('iter: %s, sys time %s' % (i, end_iter-start_iter))
        # Log system state
        model.log(stream, seleted_advancer, header=(i == 0))

        filtered_tx_passed = list(set([x['type'] for x in tx_passed]))

        if len(filtered_tx_passed) == 1:
            provider.make_request("debug_increaseTime", [3600 * 24])
        else:
            provider.make_request("debug_increaseTime", [3600 * 6])
        #'''
        #sys.exit()
        
if __name__ == "__main__":
    main()
