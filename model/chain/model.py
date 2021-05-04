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

IS_DEBUG = False
is_try_model_mine = False
max_accounts = 40
block_offset = 19 + max_accounts
tx_pool_latency = 1

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
  "addr": '0x2C15323e0AF6C5C466adF8aB851A5f19C6aEB62d',
  "decimals": 6,
  "symbol": 'USDT',
}

LLP = {
    "addr": '',
    "deploy_slug": "LinearLiquidityPoolAddress is at: "
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

for contract in [BTCUSDc, BTCUSDAgg, LLP, STG, CREDPRO, EXCHG, TPRO]:
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
USDTContract = json.loads(open('./build/contracts/TestnetUSDT.json', 'r+').read())
OptionTokenContract = json.loads(open('./build/contracts/OptionToken.json', 'r+').read())
ProtocolSettingsContract = json.loads(open('./build/contracts/ProtocolSettings.json', 'r+').read())
LinearLiquidityPoolContract = json.loads(open('./build/contracts/LinearLiquidityPool.json', 'r+').read())
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

def reg_int(value, scale):
    """
    Convert from atomic token units with the given number of decimals, to a
    Balance with the right number of decimals.
    """
    return Balance(value, scale)

def unreg_int(value, scale):
    """
    Convert from a Balance with the right number of decimals to atomic token
    units with the given number of decimals.
    """
    
    assert(value.decimals() == scale)
    return value.to_wei()

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
    
    def __init__(self, linear_liquidity_pool, options_exchange, xsd_token, usdt_token, **kwargs):
 
        # xSD TokenProxy
        self.xsd_token = xsd_token
        # USDT TokenProxy 
        self.usdt_token = usdt_token

        self.option_tokens = []
        
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
        return self.xsd_token[self]
    
    @property
    def usdt(self):
        """
        Get the current balance in USDT from the TokenProxy.
        """
        return self.usdt_token[self]

    @property
    def total_written(self):
        return self.options_exchange.get_total_owner_written(self)

    @property
    def total_holding(self):
        return self.options_exchange.get_total_owner_holding(self)

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
        return Balance(bal, USDT['decimals'])

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
                amount * 10**6
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
            Balance(amount, 18).to_wei(),
            0 if option_type == 'CALL' else 1,
            strike_price,
            maturity
        )
        return cc

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
                Balance(amount, 18).to_wei(),
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
            option_token.contract.functions.burn(
                Balance(token_amount, 18).to_wei()
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
        return cs

    def prefetch_daily(self, agent, latest_round_id, iv_bin_window):
        '''

            First call prefetchDailyPrice passing in the "roundId" of the latest sample you appended to your mock, corresponding to the underlying price for the new day
            Then call prefetchDailyVolatility passing in the volatility period defined in the ProtocolSettings contract (defaults to 90 days)
            Maybe twap can be updated daily?
        '''
        txr = transaction_helper(
            agent,
            self.btcusd_chainlink_feed.functions.prefetchDailyPrice(
                latest_round_id
            ),
            500000
        )
        txr_recp = w3.eth.waitForTransactionReceipt(txr, poll_latency=tx_pool_latency, timeout=600)
        
        txv = transaction_helper(
            agent,
            self.btcusd_chainlink_feed.functions.prefetchDailyVolatility(
                iv_bin_window
            ),
            500000
        )
        txv_recp = w3.eth.waitForTransactionReceipt(txv, poll_latency=tx_pool_latency, timeout=600)

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
            Get total balance of credit tokens issued
        '''
        return self.contract.caller({'from' : agent.address, 'gas': 100000}).getTotalBalance()

    def get_short_collateral_exposure(self, agent):
        return self.contract.caller({'from' : agent.address, 'gas': 100000}).calcRawCollateralShortage(agent.address)

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
                volume * 10**6,
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
        option_token.ensure_approved(agent, self.contract.address)
        txc = transaction_helper(
            agent,
            self.options_exchange.contract.functions.setCollateral(
                self.contract.address
            ),
            8000000
        )
        w3.eth.waitForTransactionReceipt(txc, poll_latency=tx_pool_latency)
        '''

        tx = transaction_helper(
            agent,
            self.contract.functions.sell(
                symbol,
                price,
                volume * 10**6
            ),
            8000000
        )
        return tx

    def list_symbols(self, agent):
        symbols = self.contract.caller({'from' : agent.address, 'gas': 8000000}).listSymbols().split('\n')
        return [x for x in list(filter(None,symbols)) if x != '']

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
                strike * 10**18,
                maturity,
                0 if option_type == 'CALL' else 1,
                current_timestamp,
                current_timestamp + (60 * 60 * 24),
                x,
                y,
                buyStock * 10**18,
                sellStock * 10**18
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
        #print(json.dumps([strike * (10**18), maturity, current_timestamp, current_timestamp + (60 * 60 * 24), x, y, buyStock * (10**18), sellStock * (10**18)], indent=4))
        tx = transaction_helper(
            agent,
            self.contract.functions.addSymbol(
                udlfeed_address,
                strike * (10**18),
                maturity,
                0 if option_type == 'CALL' else 1,
                current_timestamp,
                current_timestamp + (60 * 60 * 24 * 2),
                x,
                y,
                buyStock * (10**18),
                sellStock * (10**18)
            ),
            8000000
        )
        return tx

    def pool_free_balance(self, agent):
        pool_free_balance = self.contract.caller({'from' : agent.address, 'gas': 100000}).calcFreeBalance()
        return pool_free_balance

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
        self.btcusd_data_offset = 30
        self.current_round_id = 30
        self.daily_vol_period = 30
        self.prev_timestamp = 1623395489
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
            agent = Agent(self.linear_liquidity_pool, self.options_exchange, xsd, usdt, starting_axax=0, starting_usdt=0, wallet_address=address, is_mint=is_mint, **kwargs)
             
            self.agents.append(agent)

        # Update caches to current chain state
        self.usdt_token.update(is_init_agents=self.agents)


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
                    self.btcusd_data[:self.btcusd_data_offset]
                ),
                500000
            )

            timestamps = [(x* self.daily_period * -1) + current_timestamp for x in range(self.btcusd_data_offset, 0, -1)]
            transaction_helper(
                seleted_advancer,
                self.btcusd_agg.functions.setUpdatedAts(
                    timestamps
                ),
                500000
            )

            print(timestamps)
            print(self.btcusd_data[:self.btcusd_data_offset])

            tx = transaction_helper(
                seleted_advancer,
                self.btcusd_chainlink_feed.functions.initialize(
                    timestamps,
                    self.btcusd_data[:self.btcusd_data_offset]
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
            stream.write("#block\twritten\tholding\texposure\tcredit supply\n")#\tfaith\n")
        
        print(
            w3.eth.get_block('latest')["number"],
            self.options_exchange.get_total_written(seleted_advancer),
            self.options_exchange.get_total_holding(seleted_advancer),
            self.options_exchange.get_total_short_collateral_exposure(seleted_advancer),
            self.credit_provider.get_total_balance(seleted_advancer)
        )
        
        stream.write('{}\t{}\t{}\t{:.2f}\t{:.2f}\n'.format(
                w3.eth.get_block('latest')["number"],
                self.options_exchange.get_total_written(seleted_advancer),
                self.options_exchange.get_total_holding(seleted_advancer),
                self.options_exchange.get_total_short_collateral_exposure(seleted_advancer),
                self.credit_provider.get_total_balance(seleted_advancer)
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

        buyStock = 1000
        sellStock = 1000

        for x in self.linear_liquidity_pool.get_option_tokens(random_advancer):
            if x.address not in self.option_tokens:
                self.option_tokens[x.address] = x

        for x in self.linear_liquidity_pool.get_option_tokens_expired(random_advancer):
            if x.address not in self.option_tokens_expired:
                if x.totalSupply == 0:
                    self.option_tokens_expired_to_burn[x.address] = x
                else:
                    self.option_tokens_expired[x.address] = x

        self.options_exchange.option_tokens = self.option_tokens

        '''
            UPDATE FEEDS WHEN LASTEST DAY PASSESS
            UPDATE SYMBOL PARAMS
        '''
        if (diff_timestamp >= self.daily_period):
            transaction_helper(
                seleted_advancer,
                self.btcusd_agg.functions.appendRoundId(
                    self.current_round_id
                ),
                500000
            )

            transaction_helper(
                seleted_advancer,
                self.btcusd_agg.functions.appendAnswer(
                    self.btcusd_data[self.current_round_id]
                ),
                500000
            )

            transaction_helper(
                seleted_advancer,
                self.btcusd_agg.functions.appendUpdatedAt(
                    current_timestamp
                ),
                500000
            )

            self.options_exchange.prefetch_daily(seleted_advancer, self.current_round_id, self.daily_vol_period * self.daily_period)
            for sym in available_symbols:
                print('update symbol:', sym)
                sym_parts = sym.split('-')

                '''
                    * sym is something like: `ETH/USD-EC-13e20-1611964800` which represents an ETH european call option with strike price US$ 1300 and maturity at timestamp `1611964800`.
                '''
                # NEED TO MAKE SURE THAT THE DECIMALS ARE CORRECT WHEN NORMING STRIKES

                strike = int(float(sym_parts[2]) / 10**xSD['decimals'])
                maturity = int(sym_parts[3])
                days_until_expiry = (maturity - current_timestamp) / self.daily_period
                num_samples = 2000
                option_type = 'PUT' if sym_parts[1] == 'EP' else 'CALL'


                # NEED TO MAKE SURE THAT THE DECIMALS ARE CORRECT WHEN NORMING VOL
                try:
                    vol = self.btcusd_chainlink_feed.caller({'from' : seleted_advancer.address, 'gas': 8000000}).getDailyVolatility(
                        self.daily_vol_period * self.daily_period
                    )
                except Exception as inst:
                    print(inst, "bad vol calc")
                    continue
                normed_vol = vol / (10.**xSD['decimals']) / (10.)
                months_to_exp = days_until_expiry / (self.days_per_year / 12.0)

                '''
                    EXAMPLE: ./op_model "321.00" "0.4" "350" "2000" "0.2" "3.0" "CALL"
                '''
                cmd = './op_model "%s" "%s" "%s" "%s" "%s" "%s" "%s"' % (
                    self.btcusd_data[self.current_round_id] / 10.**BTCUSDAgg['decimals'],
                    normed_vol,
                    strike,
                    num_samples,
                    0.2,
                    months_to_exp,
                    option_type
                )
                model_ret = str(execute_cmd(cmd))

                option_params = list(filter(None, model_ret.split('\\n')))
                x0s = list(filter(None, option_params[0].split('x: ')[-1].split(',')))
                if len(x0s) == 0:
                    continue

                '''
                    EXAMPLE:
                    x: 283.000000,294.000000,305.000000,316.000000,327.000000,338.000000,349.000000,360.000000,371.000000,382.000000,393.000000,404.000000,415.000000,426.000000,437.000000,448.000000,459.000000,470.000000,481.000000,492.000000,503.000000,514.000000,525.000000,536.000000,547.000000,558.000000,569.000000,580.000000,591.000000,602.000000,613.000000,624.000000,635.000000,646.000000,657.000000,668.000000,679.000000
                    y0: 0.003759,0.002401,0.296976,0.332279,1.509792,2.329366,6.977463,12.941716,22.072626,29.251028,45.252636,52.544646,63.085901,78.237451,88.115777,99.479040,110.793800,118.115267,129.575667,141.164501,153.272401,162.125617,174.258685,184.612053,194.424776,205.632488,218.769968,232.852854,236.105212,254.479568,266.482429,274.897736,283.868532,295.262663,303.870996,319.351030,328.705660
                    y1: 0.020394,0.021601,0.219137,0.257914,1.210875,2.614407,7.834423,13.922812,22.323261,31.743059,45.731665,53.577131,66.643052,73.091227,87.247594,100.274300,106.781679,119.894730,131.333429,142.715132,152.197227,161.508955,173.117760,185.550314,194.692905,209.250423,216.986668,227.148755,237.249729,250.351358,264.505492,272.567784,287.580319,295.292984,307.545487,316.111073,325.065843
                '''
                try:
                    x = [int(round(x0,2) * 10**xSD['decimals']) for x0 in list(map(float, x0s))]
                    y = list(map(float,option_params[1].split('y0: ')[-1].split(','))) + list(map(float,option_params[2].split('y1: ')[-1].split(',')))
                    y  = [int(round(y0,2) * 10**xSD['decimals']) for y0 in y]
                    print(x)
                    print(y)
                except Exception as inst:
                    print(inst, "no timestamp data to update")
                    x = [0, 0]
                    y = [0, 0, 0, 0]
                
                
                
                current_timestamp = w3.eth.get_block('latest')['timestamp']
                sym_upd8_tx = self.linear_liquidity_pool.update_symbol(seleted_advancer, self.btcusd_chainlink_feed.address, strike, maturity, option_type, current_timestamp, x, y, buyStock, sellStock)
                receipt = w3.eth.waitForTransactionReceipt(sym_upd8_tx, poll_latency=tx_pool_latency, timeout=600)

            self.current_round_id += 1
            '''
                TODO: NEED TO DUMP TO FILE AND LOAD FROM FILE IN ORDER TO BE ABLE TO START AND STOP MORE ROBUSTLY SANS NUKING CONTRACTS
            '''
            self.prev_timestamp = current_timestamp

            print("current prev_timestamp daily:", self.prev_timestamp)


        logger.info("Clock: {}".format(current_timestamp))
        random.shuffle(self.agents)

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

        pool_free_balance = self.linear_liquidity_pool.pool_free_balance(random_advancer)
        logger.info("pool_free_balance: {}".format(pool_free_balance/10.**6))

        any_calls = any([ts for ts in available_symbols if '-EC-' in ts])
        any_puts = any([ts for ts in available_symbols if '-EP-' in ts])

        print("available_symbols:", available_symbols)
        print((not any_calls or not any_puts))

        self.has_tried_liquidating = False

        for agent_num, a in enumerate(self.agents):            
            # TODO: real strategy
            options = []

            open_option_tokens = self.is_positive_option_token_balance(a)
            open_option_expired_tokens = self.is_positve_option_token_expired_balance(a)

            exchange_bal  = self.options_exchange.balance(a)
            exchange_free_bal = 0
            try:
                exchange_free_bal = self.options_exchange.calc_collateral_surplus(a, a) / 10.**6
            except Exception as inst:
                print(inst, 'FAIL FREE BAL')


            #'''
            #TODO: NEED A BETTER WAY TO FIGURE THIS OUT FOR SYMBOLS THAT FAIL TO UPDATE/HAVE ANY POS TXs
            available_symbols = self.linear_liquidity_pool.list_symbols(seleted_advancer)
            any_calls = any([ts for ts in available_symbols if '-EC-' in ts])
            any_puts = any([ts for ts in available_symbols if '-EP-' in ts])

            if len(available_symbols) != len(self.option_tokens):
                #TRY AND UPDATE OPTION TOKENS AVAILABLE
                for x in self.linear_liquidity_pool.get_option_tokens(seleted_advancer):
                    if x.address not in self.option_tokens:
                        self.option_tokens[x.address] = x
            #'''

            '''
                WORKS BUT, TODO: NEED TO FIND A WAY TO SYM ECONOMY WITH THIS, CANNOT BUY DIRECT ON EXCHANGE
            if exchange_bal > 0 and len(available_symbols) > 0:
                options.append('write')
            '''

            if (exchange_bal > 0) and len(self.option_tokens) > 0 and (len(available_symbols) == len(self.option_tokens)):
                options.append('buy')

            if (exchange_bal > 0 or pool_free_balance > 0) and ((not any_calls or not any_puts) or len(available_symbols) ==0):
                options.append('add_symbol')

            if len(available_symbols) != len(self.option_tokens):
                options.append('create_symbol')

            if (a.total_holding > 0) and (pool_free_balance > 0):
                options.append('sell')

            if a.usdt > 0 and a.total_written == 0 and a.total_holding == 0:
                options.append('deposit_exchange')

            if a.usdt > 0 and a.total_written == 0 and a.total_holding == 0:
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
            if len(any_short_collateral) > 0 and not self.has_tried_liquidating:
                options.append('liquidate')
            '''

            # liquidate expired positons
            if open_option_expired_tokens  or len(self.option_tokens_expired) > 0:
                options.append('liquidate_self')
                options.append('redeem_token')

            '''
            if len(self.option_tokens_expired_to_burn) > 0:
                options.append('burn_token')
            '''


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
                        commitment
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
                    maturity = int(current_timestamp + (self.daily_period * (self.days_per_year / self.months_per_year)))
                    days_until_expiry = (maturity - current_timestamp) / self.daily_period
                    num_samples = 2000
                    option_type = option_types[0 if random.random() > 0.5 else 1]

                    if option_type == 'CALL':
                        if any([ts for ts in available_symbols if '-EC-' in ts]):
                            # call already exists
                            continue

                    if option_type == 'PUT':
                        if any([ts for ts in available_symbols if '-EP-' in ts]):
                            # put already exists
                            continue

                    otm = max(0.0, random.random())
                    if option_type == 'CALL':
                        # if call, write OTM by random amout, to the upside
                        strike = round(current_price * (1 + otm))
                    else:
                        # if put, write OTM by random amount, to the downside
                        strike = round(current_price * (1 - otm))


                    # NEED TO MAKE SURE THAT THE DECIMALS ARE CORRECT WHEN NORMING VOL
                    try:
                        vol = self.btcusd_chainlink_feed.caller({'from' : seleted_advancer.address, 'gas': 8000000}).getDailyVolatility(
                            self.daily_vol_period * self.daily_period
                        )
                    except:
                        continue
                    normed_vol = vol / (10.**xSD['decimals']) / (10.)
                    #print(normed_vol)
                    #sys.exit()
                    months_to_exp = days_until_expiry / (self.days_per_year / 12.0)

                    '''
                        EXAMPLE: ./op_model "321.00" "0.4" "350" "2000" "0.2" "3.0" "CALL"
                    '''
                    cmd = './op_model "%s" "%s" "%s" "%s" "%s" "%s" "%s"' % (
                        self.btcusd_data[self.current_round_id] / 10.**BTCUSDAgg['decimals'],
                        normed_vol,
                        strike,
                        num_samples,
                        0.2,
                        months_to_exp,
                        option_type
                    )
                    model_ret = str(execute_cmd(cmd))
                    option_params = list(filter(None, model_ret.split('\\n')))

                    x0s = list(filter(None, option_params[0].split('x: ')[-1].split(',')))
                    len_x0s = len(x0s)
                    if len_x0s == 0:
                        print('no x0s')
                        continue

                    if len_x0s < 10:
                        print('too few x0s')
                        continue

                    '''
                        EXAMPLE:
                        x: 283.000000,294.000000,305.000000,316.000000,327.000000,338.000000,349.000000,360.000000,371.000000,382.000000,393.000000,404.000000,415.000000,426.000000,437.000000,448.000000,459.000000,470.000000,481.000000,492.000000,503.000000,514.000000,525.000000,536.000000,547.000000,558.000000,569.000000,580.000000,591.000000,602.000000,613.000000,624.000000,635.000000,646.000000,657.000000,668.000000,679.000000
                        y0: 0.003759,0.002401,0.296976,0.332279,1.509792,2.329366,6.977463,12.941716,22.072626,29.251028,45.252636,52.544646,63.085901,78.237451,88.115777,99.479040,110.793800,118.115267,129.575667,141.164501,153.272401,162.125617,174.258685,184.612053,194.424776,205.632488,218.769968,232.852854,236.105212,254.479568,266.482429,274.897736,283.868532,295.262663,303.870996,319.351030,328.705660
                        y1: 0.020394,0.021601,0.219137,0.257914,1.210875,2.614407,7.834423,13.922812,22.323261,31.743059,45.731665,53.577131,66.643052,73.091227,87.247594,100.274300,106.781679,119.894730,131.333429,142.715132,152.197227,161.508955,173.117760,185.550314,194.692905,209.250423,216.986668,227.148755,237.249729,250.351358,264.505492,272.567784,287.580319,295.292984,307.545487,316.111073,325.065843
                    '''
                    x = [int(round(x0,2) * 10**xSD['decimals']) for x0 in list(map(float,x0s))]
                    y = list(map(float,option_params[1].split('y0: ')[-1].split(','))) + list(map(float,option_params[2].split('y1: ')[-1].split(',')))
                    y  = [int(round(y0,2) * 10**xSD['decimals']) for y0 in y]
                    print('x', x, 'y', y)
                    try:
                        current_timestamp = w3.eth.get_block('latest')['timestamp']
                        ads_hash = self.linear_liquidity_pool.add_symbol(a, self.btcusd_chainlink_feed.address, strike, maturity, option_type, current_timestamp, x, y, buyStock, sellStock)
                        providerAvax.make_request("avax.issueBlock", {})
                        receipt = w3.eth.waitForTransactionReceipt(ads_hash, poll_latency=tx_pool_latency, timeout=600)
                        tx_hashes.append({'type': 'add_symbol', 'hash': ads_hash})
                    except Exception as inst:
                        logger.info({"agent": a.address, "error": inst, "action": "add_symbol", "strike": strike, "maturity": maturity, "x": x, "y": y, "normed_vol": normed_vol, "vol": vol})
                elif action == "create_symbol":
                    for sym in available_symbols:
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
                        commitment
                    )
                    try:
                        dpp_hash = self.linear_liquidity_pool.deposit_pool(a, amount)
                        tx_hashes.append({'type': 'deposit_pool', 'hash': dpp_hash})
                    except Exception as inst:
                        logger.info({"agent": a.address, "error": inst, "action": "deposit_pool", "amount": amount})
                elif action == "withdraw":
                    amount = int(portion_dedusted(
                        exchange_free_bal,
                        commitment
                    ))
                    try:
                        logger.info("Before Withdraw; volume: {}".format(amount))
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
                        try:
                            logger.info("Before Redeem Option: {}, {}".format(otv.symbol, otv.totalSupply))
                            rdmt_hash = self.options_exchange.redeem_token(a, otk)
                            tx_hashes.append({'type': 'redeem_token', 'hash': rdmt_hash})
                        except Exception as inst:
                            logger.info({"agent": a.address, "error": inst, "action": "redeem_token", "option_token": otv.address})
                elif action == "burn_token":
                    for otk, otv in self.option_tokens_expired_to_burn.items():
                        try:
                            logger.info("Before Burn Option: {}".format(otv.symbol))
                            rdmt_hash = self.options_exchange.redeem_token(a, otk)
                            tx_hashes.append({'type': 'burn_token', 'hash': rdmt_hash})
                        except Exception as inst:
                            logger.info({"agent": a.address, "error": inst, "action": "burn_token", "option_token": otv.address})

                elif action == "write":
                    # select from available symbols
                    sym = available_symbols[0 if random.random() > 0.5 else 1]
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

                    if amount == 0:
                        amount = 1

                    cc  = self.options_exchange.calc_collateral(a, self.btcusd_chainlink_feed.address, option_type, amount, strike_price, maturity)
                    if((cc / 10.**6) > (exchange_bal / 10.**6)):
                        continue
                    
                    try:
                        w_hash = self.options_exchange.write(a, self.btcusd_chainlink_feed.address, option_type, amount, strike_price, maturity)
                        tx_hashes.append({'type': 'write', 'hash': w_hash})
                    except Exception as inst:
                        logger.info({"agent": a.address, "error": inst, "action": "write", "strike_price": strike_price, "maturity": maturity, "option_type": option_type, "amount": amount})
                elif action == "buy":
                    tks_list = list(self.option_tokens.values())
                    option_token_to_buy = tks_list[0 if random.random() > 0.5 else len(tks_list) - 1]
                    symbol = option_token_to_buy.contract.caller({'from' : a.address, 'gas': 8000000}).symbol()
                    option_token_balance_of_pool = option_token_to_buy.contract.caller({'from' : a.address, 'gas': 8000000}).writtenVolume(self.linear_liquidity_pool.address)
                    print(symbol, option_token_balance_of_pool)
                    try:
                        current_price_volume = self.linear_liquidity_pool.query_buy(a, symbol)
                    except Exception as inst:
                        print("\terror querying buy", inst)
                        continue

                    if (option_token_balance_of_pool / 10.**6) >= buyStock:
                        continue
                    
                    print(symbol, current_price_volume, option_token_balance_of_pool, exchange_bal, 'BUY')
                    volume = int(random.random() * (current_price_volume[1] / 10.**11))
                    if volume == 0:
                        volume = 1
                    price = current_price_volume[0]#int(math.ceil(current_price_volume[0] / 10**18)) * 10**18
                    try:
                        logger.info("Before Buy; symbol: {}, price: {}, volume: {}".format(symbol, price, volume))
                        buy_hash = self.linear_liquidity_pool.buy(a, symbol, price, volume)
                        providerAvax.make_request("avax.issueBlock", {})
                        tx_hashes.append({'type': 'buy', 'hash': buy_hash})
                    except Exception as inst:
                        logger.info({"agent": a.address, "error": inst, "action": "buy", "volume": volume, "price": price, "symbol": symbol})
                elif action == "sell":
                    option_token_to_sell = None
                    volume_to_sell = 0
                    for k, ot in self.option_tokens.items():
                        volume_to_sell = ot.contract.caller({'from' : a.address, 'gas': 8000000}).balanceOf(a.address) 
                        if volume_to_sell > 0:
                            option_token_to_sell = ot
                            break
                    
                    if not option_token_to_sell:
                        continue
                    symbol = option_token_to_sell.contract.caller({'from' : a.address, 'gas': 8000000}).symbol()
                    try:
                        current_price_volume = self.linear_liquidity_pool.query_sell(a, symbol)
                    except Exception as inst:
                        print("\terror querying sell", inst)
                        continue

                    if (volume_to_sell / 10.**6) >= sellStock:
                        continue


                    print(symbol, current_price_volume, volume_to_sell, 'SELL')
                    
                    '''
                    volume = int(round(portion_dedusted(
                        volume_to_sell / 10.**6,
                        commitment
                    )))
                    '''

                    volume = int(random.random() * (current_price_volume[1] / 10.**14))
                    if volume == 0:
                        volume = 1
                    price = current_price_volume[0]
                    try:
                        logger.info("Before Sell; symbol: {}, price: {}, volume: {}".format(symbol, price, volume))
                        sell_hash = self.linear_liquidity_pool.sell(a, symbol, price, volume, option_token_to_sell)
                        tx_hashes.append({'type': 'sell', 'hash': sell_hash})
                    except Exception as inst:
                        logger.info({"agent": a.address, "error": inst, "action": "sell", "volume": volume, "price": price, "symbol": symbol})
                elif action == "liquidate":
                    for short_owners in any_short_collateral:
                        for otk, otv in self.option_tokens.items():
                            try:
                                lqd8_hash = self.options_exchange.liquidate(a, otk, short_owners.address)
                                tx_hashes.append({'type': 'liquidate', 'hash': lqd8_hash})
                            except Exception as inst:
                                logger.info({"agent": a.address, "error": inst, "action": "liquidate", "short_owner": short_owners.address, "option_token": otk})
                elif action == "liquidate_self":
                    for otk, otv in self.option_tokens_expired.items():
                        try:
                            lqd8_hash = self.options_exchange.liquidate(a, otk, self.linear_liquidity_pool.address)
                            tx_hashes.append({'type': 'liquidate_self', 'hash': lqd8_hash})
                        except Exception as inst:
                            logger.info({"agent": a.address, "error": inst, "action": "liquidate_self", "option_token": otv.address})

                    self.has_tried_liquidating = True
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
                tx_fails.append(tmp_tx_hash['type'])
            else:
                tx_good.append(tmp_tx_hash['type'])

        #'''

        logger.info("total tx: {}, successful tx: {}, tx fails: {}, tx passed: {}".format(
                len(tx_hashes), tx_hashes_good, json.dumps(list(set(tx_fails))), json.dumps(list(set(tx_good)))
            )
        )

        return anyone_acted, random_advancer

def main():
    """
    Main function: run the simulation.
    """
    global avax_cchain_nonces

    '''
        curl -X POST --data '{ "jsonrpc":"2.0", "id" :1, "method" :"debug_increaseTime", "params" : ["0x45e8d9a7ca159a0f6957534cb25412b4daa4243906ef2b6e93125246b1e27d05"]}' -H 'content-type:application/json;' http://127.0.0.1:9545/ext/bc/C/rpc
    '''
    #transaction = w3.eth.get_transaction("0xe0c89a15c74d9123a82aa831c8e12e2b38b727c7a5075c4a63bc733981d3fb2f")

    #print(transaction.input)
    #print(provider.make_request("debug_traceTransaction", ["0x45e8d9a7ca159a0f6957534cb25412b4daa4243906ef2b6e93125246b1e27d05"]))
    #print(w3.eth.get_block('latest')['timestamp'])
    #sys.exit()
    
    logging.basicConfig(level=logging.INFO)
    logger.info('Total Agents: {}'.format(len(w3.eth.accounts[:max_accounts])))
    
    options_exchange = w3.eth.contract(abi=OptionsExchangeContract['abi'], address=EXCHG["addr"])
    usdt = TokenProxy(w3.eth.contract(abi=USDTContract['abi'], address=USDT["addr"]))
    credit_provider = w3.eth.contract(abi=CreditProviderContract['abi'], address=CREDPRO["addr"])
    linear_liquidity_pool = w3.eth.contract(abi=LinearLiquidityPoolContract['abi'], address=LLP["addr"])
    protocol_settings = w3.eth.contract(abi=ProtocolSettingsContract['abi'], address=STG['addr'])
    btcusd_chainlink_feed = w3.eth.contract(abi=ChainlinkFeedContract['abi'], address=BTCUSDc['addr'])
    btcusd_agg = w3.eth.contract(abi=AggregatorV3MockContract['abi'], address=BTCUSDAgg["addr"])
    
    mock_time = w3.eth.contract(abi=TimeProviderMockContract['abi'], address=TPRO["addr"])


    '''
    print(credit_provider.caller({'from' : w3.eth.accounts[0], 'gas': 8000000}).balanceOf(linear_liquidity_pool.address))
    print("tx-input -> 0xa606b94a000000000000000000000000bc177dc5f5d910069e6eda3f12d26a5f4dc3fe200000000000000000000000009f7d9386dc282417ffaac588e65e828be809e4ba00000000000000000000000000000000000000000000000000000000007ac0ad")
    print(credit_provider.decode_function_input("0xa606b94a000000000000000000000000bc177dc5f5d910069e6eda3f12d26a5f4dc3fe200000000000000000000000009f7d9386dc282417ffaac588e65e828be809e4ba00000000000000000000000000000000000000000000000000000000007ac0ad"))
    sys.exit()
    '''


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
    #print(btcusd_chainlink_feed.functions.getLatestPrice().call())
    #print(Balance(4.474093538197649, 18).to_wei())

    #sys.exit()

    with open('../../data/BTC-USD_vol_date_high_low_close.json', 'r+') as btcusd_file:
        btcusd_historical_ohlc = json.loads(btcusd_file.read())["chart"]
    

    daily_period = 60 * 60 * 24
    current_timestamp = int(w3.eth.get_block('latest')['timestamp'])
    btcusd_answers = [int(float(x["open"]) * (10**BTCUSDAgg['decimals'])) for x in btcusd_historical_ohlc if x["open"] != 'null']

    avax_cchain_nonces = open(MMAP_FILE, "r+b")

    # temp opx, llp, agent
    opx = OptionsExchange(options_exchange, usdt, btcusd_chainlink_feed)
    _llp = LinearLiquidityPool(linear_liquidity_pool, usdt, opx)
    agent = Agent(_llp, opx, None, usdt, starting_axax=0, starting_usdt=0, wallet_address=w3.eth.accounts[0], is_mint=False)

    '''
        SETUP POOL:
            All options must have maturities under the pool maturity
    '''
    tx_hashes = []
    tx_hashes_good = 0
    tx_fails = []

    pool_spread = 5 * (10**7)
    pool_reserve_ratio = 20 * (10**7)
    pool_maturity = (1000000000 * daily_period) + current_timestamp

    '''
        SETUP PROTOCOL SETTINGS FOR POOL
    '''
    skip = True

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
                1
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

        (anyone_acted, seleted_advancer) = model.step()
        if not anyone_acted:
            # Nobody could act
            logger.info("Nobody could act")
            break
        end_iter = time.time()
        logger.info('iter: %s, sys time %s' % (i, end_iter-start_iter))
        # Log system state
        model.log(stream, seleted_advancer, header=(i == 0))

        if ((i % 2) == 0) and (i != 0):
            provider.make_request("debug_increaseTime", [3600 * 12])
        #sys.exit()
        
if __name__ == "__main__":
    main()
