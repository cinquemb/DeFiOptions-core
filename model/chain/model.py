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
tx_pool_latency = 0.01

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
    "deploy_slug": "timeProvider is at: "
}

EXCHG = {
    "addr": '',
    "deploy_slug": "exchange is at: "
}

CREDPRO = {
    "addr": '',
    "deploy_slug": "creditProvider is at: "
}

STG = {
    "addr": '',
    "deploy_slug": "settings is at: "
}

# USE FROM XSD SIMULATION
USDT = {
  "addr": '',
  "decimals": 6,
  "symbol": 'USDT',
}

LLP = {
    "addr": '',
    "deploy_slug": "pool is at: "
}

BTCUSDAgg = {
  "addr": '',
  "decimals": 18,
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
StableCoin = {
  "addr": '',
  "decimals": 18,
  "symbol": 'StableCoin',
}

AggregatorV3MockContract = json.loads(open('./build/contracts/AggregatorV3Mock.json', 'r+').read())
ChainlinkFeedContract = json.loads(open('./build/contracts/ChainlinkFeedContract.json', 'r+').read())
CreditProviderContract = json.loads(open('./build/contracts/CreditProvider.json', 'r+').read())
OptionsExchangeContract = json.loads(open('./build/contracts/OptionsExchange.json', 'r+').read())
USDTContract = json.loads(open('./build/contracts/TestnetUSDT.json', 'r+').read())
OptionTokenContract = json.loads(open('./build/contracts/OptionToken.json', 'r+').read())
ProtocolSettingsContract = json.loads(open('./build/contracts/ProtocolSettings.json', 'r+').read())
LinearLiquidityPoolContract = json.loads(open('./build/contracts/LinearLiquidityPoolContract.json', 'r+').read())
ERC20StableCoinContract = json.loads(open('./build/contracts/ERC20.json', 'r+').read())
TimeProviderMockContract = json.loads(open('./build/contracts/TimeProviderMock.json', 'r+').read())


def get_addr_from_contract(contract):
    return contract["networks"][str(sorted(map(int,contract["networks"].keys()))[0])]["address"]

avax_cchain_nonces = None
mm = None
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
        raw_data_cov = mm.read().decode('utf8')
        nonce_data = json.loads(raw_data_cov)
        mm.seek(0)
        continue

    # locked == '1', unlocked == '0'

    # LOCK FILE START
    nonce_data['locked'] = '1'
    out_data = bytes(json.dumps(nonce_data), 'utf8')
    mm[:] = out_data
    mm.seek(0)
    # LOCK FILE END
    
    nonce_data[agent.address]["seen_block"] = decode_single('uint256', base64.b64decode(nonce_data[agent.address]["seen_block"]))
    nonce_data[agent.address]["next_tx_count"] = decode_single('uint256', base64.b64decode(nonce_data[agent.address]["next_tx_count"]))
    # DECODE END
    
    if current_block != nonce_data[agent.address]["seen_block"]:
        if (nonce_data[agent.address]["seen_block"] == 0):
            nonce_data[agent.address]["seen_block"] = current_block
            nonce_data[agent.address]["next_tx_count"] = agent.next_tx_count
        else:
            nonce_data[agent.address]["next_tx_count"] += 1
            agent.next_tx_count = nonce_data[agent.address]["next_tx_count"]
    else:
        nonce_data[agent.address]["next_tx_count"] += 1
        agent.next_tx_count = nonce_data[agent.address]["next_tx_count"]

    # ENCODE START
    nonce_data[agent.address]["seen_block"] = base64.b64encode(encode_single('uint256', nonce_data[agent.address]["seen_block"])).decode('ascii')
    nonce_data[agent.address]["next_tx_count"] = base64.b64encode(encode_single('uint256', nonce_data[agent.address]["next_tx_count"])).decode('ascii')
    nonce_data['locked'] = '0'
    out_data = bytes(json.dumps(nonce_data), 'utf8')
    mm[:] = out_data
    # ENCODE END
    return agent.next_tx_count

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
            tx_hash = self.__contract.functions.approve(spender, UINT256_MAX).transact({
                'nonce': get_nonce(owner),
                'from' : getattr(owner, 'address', owner),
                'gas': 500000,
                'gasPrice': Web3.toWei(470, 'gwei'),
            })
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
            tx_hash = self.usdt_token.contract.functions.mint(
                self.address, start_usdt_formatted.to_wei()
            ).transact({
                'nonce': get_nonce(self),
                'from' : self.address,
                'gas': 500000,
                'gasPrice': Web3.toWei(225, 'gwei'),
            })
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
        Get the current balance in Pangolin LP Shares from the TokenProxy.
        """
        return self.linear_liquidity_pool[self]

    @property
    def short_collateral_exposure(self):
        """
        Get the short collateral balance for agent
        """
        return self.options_exchange.get_short_collateral_exposure(self)
    
    def __str__(self):
        """
        Turn into a readable string summary.
        """
        return "Agent(xSD={:.2f}, usdt={:.2f}, avax={}, lp={}, total_written={}, total_holding={}, short_collateral_exposure={:.2f})".format(
            self.xsd, self.usdt, self.avax, self.lp, self.total_written, self.total_holding, self.short_collateral_exposure)

        
    def get_strategy(self, current_timestamp, price, total_supply, total_coupons, agent_coupons):
        """
        Get weights, as a dict from action to float, as a function of the price.
        """
        
        strategy = collections.defaultdict(lambda: 1.0)
        
        # TODO: real (learned? adversarial? GA?) model of the agents
        # TODO: agent preferences/utility function

        # People are fast to coupon bid to get in front of redemption queue
        strategy["coupon_bid"] = 2.0


        strategy["provide_liquidity"] = 0.1
        strategy["remove_liquidity"] = 1.0
        
        
        if price >= 1.0:
            # No rewards for expansion by itself
            strategy["bond"] = 0
            # And not unbond
            strategy["unbond"] = 0
            # Or redeem if possible
            # strategy["redeem"] = 10000000000000.0 if self.coupons > 0 else 0
            # incetive to buy above 1 is for more coupons
            strategy["buy"] = 1.0
            strategy["sell"] = 1.0
        else:
            # We probably want to unbond due to no returns
            strategy["unbond"] = 0
            # And not bond
            strategy["bond"] = 0
       
        if self.use_faith:
            # Vary our strategy based on how much xSD we think ought to exist
            if price * total_supply > self.get_faith(current_timestamp, price, total_supply):
                # There is too much xSD, so we want to sell
                strategy["sell"] = 10.0 if ((agent_coupons> 0) and (price > 1.0)) else 2.0
            else:
                # no faith based buying, just selling
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
    def __init__(self, contract, usdt_token, liquidity_pool, **kwargs):
        self.contract = contract
        self.usdt_token = usdt_token
        self.liquidity_pool = liquidity_pool

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
        tx = self.contract.functions.depositTokens(
            agent.address,
            self.usdt_token.address,
            amount.to_wei()
        ).transact({
            'nonce': get_nonce(agent),
            'from' : agent.address,
            'gas': 500000,
            'gasPrice': Web3.toWei(225, 'gwei'),
        })

        return tx

    def withdraw(self, agent, amount):
        '''
            uint value = 50e18;
            exchange.withdrawTokens(value);
        '''
        tx = self.contract.functions.withwdraw(
            amount.to_wei()
        ).transact({
            'nonce': get_nonce(agent),
            'from' : agent.address,
            'gas': 500000,
            'gasPrice': Web3.toWei(225, 'gwei'),
        })

        return tx

    def write(self, agent, feed_address, amount, strike_price, maturity):
        '''
            uint id = exchange.writeOptions(
                eth_usd_feed, 
                10 * volumeBase, 
                OptionsExchange.OptionType.CALL, 
                strikePrice, 
                maturity
            );
        '''
        tx = self.contract.functions.writeOptions(
            feed_address,
            Balance(amount, 18).to_wei(),
            self.contract.OptionType.CALL,
            strike_price,
            maturity,
        ).transact({
            'nonce': get_nonce(agent),
            'from' : agent.address,
            'gas': 500000,
            'gasPrice': Web3.toWei(225, 'gwei'),
        })

        return tx

    def burn(self, agent, option_token_address, token_amount):
        '''
        uint amount = token_amount * volumeBase;
        token.burn(amount);
        '''
        option_token = w3.eth.contract(abi=OptionTokenContract['abi'], address=option_token_address)

        tx = option_token.contract.functions.burn(
            Balance(token_amount, 18).to_wei()
        ).transact({
            'nonce': get_nonce(agent),
            'from' : agent.address,
            'gas': 500000,
            'gasPrice': Web3.toWei(225, 'gwei'),
        })

        return tx

    def get_book_ids(self, agent):
        return self.contract.caller({'from' : agent.address, 'gas': 100000}).getBookIds(agent.address)

    def liquidate(self, agent, _id):
        '''
            exchange.liquidateOptions()
        '''
        tx = self.contract.functions.liquidateOptions(
            _id
        ).transact({
            'nonce': get_nonce(agent),
            'from' : agent.address,
            'gas': 500000,
            'gasPrice': Web3.toWei(225, 'gwei'),
        })
        return tx

    def get_short_collateral_exposure(self, agent):
        return self.contract.caller({'from' : agent.address, 'gas': 100000}).calcRawCollateralShortage(agent.address)

    def get_total_short_collateral_exposure(self, agent):
        return self.contract.caller({'from' : agent.address, 'gas': 100000}).getOptionsExchangeTotalExposure()

    def get_total_written(self, agent):
        '''
            getTotalWritten() public view returns (uint120)
        '''
        return self.contract.caller({'from' : agent.address, 'gas': 100000}).getTotalWritten()

    def get_total_holding(self, agent):
        '''
            getTotalHolding() public view returns (uint120)
        '''
        return self.contract.caller({'from' : agent.address, 'gas': 100000}).getTotalHolding()

    def get_total_owner_written(self, agent):
        '''
            getTotalOwnerWritten(address owner) public view returns (uint120)
        '''
        return self.contract.caller({'from' : agent.address, 'gas': 100000}).getTotalOwnerWritten(agent.address)

    def get_total_owner_holding(self, agent):
        '''
            getTotalOwnerHolding(address owner) public view returns (uint120)
        '''
        return self.contract.caller({'from' : agent.address, 'gas': 100000}).getTotalOwnerHolding(agent.address)


class CreditProvider:
    def __init__(self, contract, usdt_token, **kwargs):
        self.contract = contract
        self.usdt_token = usdt_token


    def prefetch_daily(self, agent, latest_round_id, iv_bin_window):
        '''

            First call prefetchDailyPrice passing in the "roundId" of the latest sample you appended to your mock, corresponding to the underlying price for the new day
            Then call prefetchDailyVolatility passing in the volatility period defined in the ProtocolSettings contract (defaults to 90 days)
            Maybe twap can be updated daily?
        '''
        txr = self.contract.functions.prefetchDailyPrice(
            latest_round_id
        ).transact({
            'nonce': get_nonce(agent),
            'from' : agent.address,
            'gas': 500000,
            'gasPrice': Web3.toWei(225, 'gwei'),
        })
        txr_recp = w3.eth.waitForTransactionReceipt(txr, poll_latency=tx_pool_latency)

        txv = self.contract.functions.prefetchDailyVolatility(
            iv_bin_window
        ).transact({
            'nonce': get_nonce(agent),
            'from' : agent.address,
            'gas': 500000,
            'gasPrice': Web3.toWei(225, 'gwei'),
        })
        txv_recp = w3.eth.waitForTransactionReceipt(txv, poll_latency=tx_pool_latency)

    def get_total_balance(self, agent):
        '''
            Get total balance of credit tokens issued
        '''
        return self.contract.caller({'from' : agent.address, 'gas': 100000}).getTotalBalance()

class LinearLiquidityPool(TokenProxy):
    def __init__(self, contract, usdt_token, **kwargs):
        self.contract = contract
        self.usdt_token = usdt_token
        super(TokenProxy, self).__init__(self.contract)

    def deposit_pool(self, agent, amount):
        '''
            pool.depositTokens(
                address to, address token, uint value
            );
        '''
        self.usdt_token.ensure_approved(agent, self.contract.address)
        tx = self.contract.functions.depositTokens(
            agent.address,
            self.usdt_token.address,
            amount.to_wei()
        ).transact({
            'nonce': get_nonce(agent),
            'from' : agent.address,
            'gas': 500000,
            'gasPrice': Web3.toWei(225, 'gwei'),
        })

        return tx

    def redeem(self, agent, holders_index):
        '''
            TODO
            pool.redeem()
        '''
        tx = self.contract.functions.redeem(
        ).transact({
            'nonce': get_nonce(agent),
            'from' : agent.address,
            'gas': 500000,
            'gasPrice': Web3.toWei(225, 'gwei'),
        })

        return tx

    def buy(self, agent, symbol, price, volume):
        '''
            stablecoin.approve(address(pool), price * volume / volumeBase);
            pool.buy(symbol, price, volume, address(stablecoin));
        '''
        self.usdt_token.ensure_approved(agent, self.contract.address)
        tx = self.contract.functions.buy(
            symbol,
            price,
            volume,
            self.usdt_token.contract.address
        ).transact({
            'nonce': get_nonce(agent),
            'from' : agent.address,
            'gas': 500000,
            'gasPrice': Web3.toWei(225, 'gwei'),
        })
        return tx

    def sell(self, agent, symbol, price, volume, option_token_address):
        '''
            option_token.approve(address(pool), price * volume / volumeBase)`;
            pool.sell(symbol, price, volume)`;
        '''
        option_token = w3.eth.contract(abi=OptionTokenContract['abi'], address=option_token_address)
        self.usdt_token.ensure_approved(agent, self.contract.address)

        tx = self.contract.functions.sell(
            symbol,
            price,
            volume
        ).transact({
            'nonce': get_nonce(agent),
            'from' : agent.address,
            'gas': 500000,
            'gasPrice': Web3.toWei(225, 'gwei'),
        })

        return tx

    def list_symbols(self, agent):
        symbols = self.contract.caller({'from' : agent.address, 'gas': 100000}).listSymbols()
        return symbols

    def add_symbol(self, agent, udlfeed_address, strike, maturity, current_timestamp, x, y, buyStock, sellStock):
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

        tx = self.contract.functions.addSymbol(
            udlfeed_address,
            strike * 10**18,
            maturity,
            current_timestamp,
            current_timestamp + (60 * 60 * 24),
            x,
            y,
            buyStock,
            sellStock
        ).transact({
            'nonce': get_nonce(agent),
            'from' : agent.address,
            'gas': 500000,
            'gasPrice': Web3.toWei(225, 'gwei'),
        })

        return tx

    def update_symbol(self, agent, udlfeed_address, strike, maturity, current_timestamp, x, y, buyStock, sellStock):
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

        tx = self.contract.functions.addSymbol(
            udlfeed_address,
            strike * 10**18,
            maturity,
            current_timestamp,
            current_timestamp + (60 * 60 * 24),
            x,
            y,
            buyStock,
            sellStock
        ).transact({
            'nonce': get_nonce(agent),
            'from' : agent.address,
            'gas': 500000,
            'gasPrice': Web3.toWei(225, 'gwei'),
        })

        return tx

class Model:
    """
    Full model of the economy.
    """
    
    def __init__(self, options_exchange, credit_provider, linear_liquidity_pool, btcusd_chainlink_feed, btcusd_agg, btcusd_data, agents, **kwargs):
        """
        Takes in experiment parameters and forwards them on to all components.
        """

        self.agents = []
        self.options_exchange = OptionsExchange(options_exchange, **kwargs)
        self.credit_provider = CreditProvider(credit_provider, **kwargs)
        self.linear_liquidity_pool = LinearLiquidityPool(linear_liquidity_pool, **kwargs)
        self.btcusd_chainlink_feed = btcusd_chainlink_feed
        self.btcusd_agg = btcusd_agg
        self.btcusd_data = btcusd_data
        self.btcusd_data_offset = 30
        self.current_round_id = 30
        self.daily_vol_period = 30
        self.prev_timestamp = 0
        self.daily_period = 60 * 60 * 24
        self.days_per_year = 365

        is_mint = is_try_model_mine
        if w3.eth.get_block('latest')["number"] == block_offset:
            # THIS ONLY NEEDS TO BE RUN ON NEW CONTRACTS
            # TODO: tolerate redeployment or time-based generation
            is_mint = True
        
        total_tx_submitted = len(agents) 
        for i in range(len(agents)):
            
            address = agents[i]
            agent = Agent(self.linear_liquidity_pool, pangolin, xsd, usdc, starting_axax=0, starting_usdc=0, wallet_address=address, is_mint=is_mint, **kwargs)
             
            self.agents.append(agent)

        # Update caches to current chain state
        self.usdt_token.update(is_init_agents=self.agents)


        '''
            INIT T-MINUS DATA FOR FEED
        '''
        current_timestamp = w3.eth.get_block('latest')['timestamp']
        seleted_advancer = self.agents[int(random.random() * (len(self.agents) - 1))]
        self.btcusd_agg.setRoundIds(
            range(30)
        ).transact({
            'nonce': get_nonce(seleted_advancer),
            'from' : seleted_advancer.address,
            'gas': 500000,
            'gasPrice': Web3.toWei(225, 'gwei'),
        })
        self.btcusd_agg.setAnswers(
            self.btcusd_data[:self.btcusd_data_offset]
        ).transact({
            'nonce': get_nonce(seleted_advancer),
            'from' : seleted_advancer.address,
            'gas': 500000,
            'gasPrice': Web3.toWei(225, 'gwei'),
        })
        self.btcusd_agg.setUpdatedAts(
            [(x* self.daily_period * -1) + current_timestamp for x in range(self.btcusd_data_offset, 0, -1)]
        ).transact({
            'nonce': get_nonce(seleted_advancer),
            'from' : seleted_advancer.address,
            'gas': 500000,
            'gasPrice': Web3.toWei(225, 'gwei'),
        })
        
    def log(self, stream, seleted_advancer, header=False):
        """
        Log model statistics a TSV line.
        If header is True, include a header.
        """
        
        if header:
            stream.write("#block\twritten\tholding\texposure\tcredit supply\n")#\tfaith\n")
        
        stream.write('{}\t{}\t{:.2f}\t{:.2f}\t{:.2f}\t{:.2f}\n'.format(
                w3.eth.get_block('latest')["number"],
                self.options_exchange.get_total_written(seleted_advancer.address),
                self.options_exchange.get_total_holding(seleted_advancer.address),
                self.options_exchange.get_total_short_collateral_exposure(seleted_advancer.address),
                self.credit_provider.get_total_balance(seleted_advancer.address)
            )
        )
       
    def get_overall_faith(self):
        """
        What target should the system be trying to hit in xSD market cap?
        """
        return self.agents[0].get_faith(w3.eth.get_block('latest')["number"], self.pangolin.xsd_price(), self.dao.xsd_supply())
       
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

        #randomly have an agent do maintence tasks the epoch
        seleted_advancer = self.agents[int(random.random() * (len(self.agents) - 1))]

        available_symbols = self.liquidity_pool.list_symbols(seleted_advancer)

        '''
            UPDATE FEEDS WHEN LASTEST DAY PASSESS
            UPDATE SYMBOL PARAMS
        '''
        if (diff_timestamp >= daily_period):
            self.btcusd_agg.appendRoundId(
                self.current_round_id
            ).transact({
                'nonce': get_nonce(seleted_advancer),
                'from' : seleted_advancer.address,
                'gas': 500000,
                'gasPrice': Web3.toWei(225, 'gwei'),
            })
            self.btcusd_agg.appendAnswer(
                self.btcusd_data[self.current_round_id]
            ).transact({
                'nonce': get_nonce(seleted_advancer),
                'from' : seleted_advancer.address,
                'gas': 500000,
                'gasPrice': Web3.toWei(225, 'gwei'),
            })
            self.btcusd_agg.appendUpdatedAt(
                current_timestamp
            ).transact({
                'nonce': get_nonce(seleted_advancer),
                'from' : seleted_advancer.address,
                'gas': 500000,
                'gasPrice': Web3.toWei(225, 'gwei'),
            })

            self.credit_provider.prefetch_daily(seleted_advancer, self.current_round_id, 30 * self.daily_period)

            for sym in available_symbols:
                sym_parts = sym.split('-')

                '''
                    * sym is something like: `ETH/USD-EC-13e20-1611964800` which represents an ETH european call option with strike price US$ 1300 and maturity at timestamp `1611964800`.
                '''
                # NEED TO MAKE SURE THAT THE DECIMALS ARE CORRECT WHEN NORMING STRIKES
                strike = float(sym_parts[2]) / 10*xSD['decimals']
                maturity = int(sym_parts[3])
                days_until_expiry = (maturity - current_timestamp) / self.daily_period
                num_samples = 2000
                option_type = 'PUT' if sym_parts[1] == 'EP' else 'CALL'


                # NEED TO MAKE SURE THAT THE DECIMALS ARE CORRECT WHEN NORMING VOL
                vol = self.btcusd_chainlink_feed.caller({'from' : seleted_advancer.address, 'gas': 100000}).getDailyVolatility(
                    self.daily_vol_period * self.daily_period
                )

                months_to_exp = (self.days_per_year / 12.0) / days_until_expiry

                '''
                    EXAMPLE: ./op_model "321.00" "0.4" "350" "2000" "0.2" "3.0" "CALL"
                '''
                cmd = './op_model "%s" "%s" "%s" "%s" "%s" "%s" "%s"' % (
                    self.btcusd_data[self.current_round_id] / 10**xSD['decimals'],
                    vol,
                    strike,
                    num_samples,
                    0.2,
                    months_to_exp,
                    option_type
                )

                option_params = filter(None,execute_cmd(cmd).split('\n'))

                '''
                    EXAMPLE:
                    x: 283.000000,294.000000,305.000000,316.000000,327.000000,338.000000,349.000000,360.000000,371.000000,382.000000,393.000000,404.000000,415.000000,426.000000,437.000000,448.000000,459.000000,470.000000,481.000000,492.000000,503.000000,514.000000,525.000000,536.000000,547.000000,558.000000,569.000000,580.000000,591.000000,602.000000,613.000000,624.000000,635.000000,646.000000,657.000000,668.000000,679.000000
                    y0: 0.003759,0.002401,0.296976,0.332279,1.509792,2.329366,6.977463,12.941716,22.072626,29.251028,45.252636,52.544646,63.085901,78.237451,88.115777,99.479040,110.793800,118.115267,129.575667,141.164501,153.272401,162.125617,174.258685,184.612053,194.424776,205.632488,218.769968,232.852854,236.105212,254.479568,266.482429,274.897736,283.868532,295.262663,303.870996,319.351030,328.705660
                    y1: 0.020394,0.021601,0.219137,0.257914,1.210875,2.614407,7.834423,13.922812,22.323261,31.743059,45.731665,53.577131,66.643052,73.091227,87.247594,100.274300,106.781679,119.894730,131.333429,142.715132,152.197227,161.508955,173.117760,185.550314,194.692905,209.250423,216.986668,227.148755,237.249729,250.351358,264.505492,272.567784,287.580319,295.292984,307.545487,316.111073,325.065843
                '''
                x = map(float,option_params[0].split('x: ')[-1].split(','))
                y = map(float,option_params[1].split('y0: ')[-1].split(',')) + map(float,option_params[2].split('y1: ')[-1].split(','))

                '''
                    TODO: need to explore 2:1 bs, 1:1 bs and 1:2 bs
                '''
                buyStock = 100
                sellStock = 200

                self.linear_liquidity_pool.update_symbol(seleted_advancer, self.btcusd_chainlink_feed.address, strike, maturity, current_timestamp, x, y, buyStock, sellStock)

            self.current_round_id += 1
            self.prev_timestamp = current_timestamp


        logger.info("Clock: {}".format(current_timestamp))

        for agent_num, a in enumerate(self.agents):            
            # TODO: real strategy
            options = []

            if len(available_symbols) > 0:
                options.append('write')

            if len(available_symbols) > 0:
                options.append('buy')

            if len(available_symbols) > 0:
                options.append('sell')


            start_tx_count = a.next_tx_count
            commitment = random.random() * 0.1

            if len(options) > 0:
                # We can act

                '''
                    LATER:
                        advance: to do maintainence functions, payout from dynamic collateral and/or gov token
                    
                    TODO:
                        redeem, add_symbol                 
                    TOTEST:
                        deposit_exchange, deposit_pool, withdraw, redeem, burn, write, buy, sell, liquidate
                    WORKS:
                        
                '''
        
                strategy = a.get_strategy(w3.eth.get_block('latest')["number"])
                
                weights = [strategy[o] for o in options]
                
                action = random.choices(options, weights=weights)[0]
                
                # What fraction of the total possible amount of doing this
                # action will the agent do?
                
                
                if action == "deposit_exchange":
                    pass
                elif action == "add_symbol":
                    option_types = ['PUT', 'CALL']
                    # if call, write OTM by random amout, to the upside
                    # if put, write OTM by random amount, to the downside
                    strike_to_write = self.btcusd_data[self.current_round_id]

                    # chose random maturity length less than the maturity of the pool
                    maturity = 223

                    self.linear_liquidity_pool.update_symbol(seleted_advancer, self.btcusd_chainlink_feed.address, strike, maturity, current_timestamp, x, y, buyStock, sellStock)
                elif action == "deposit_pool":
                    pass
                elif action == "withdraw":
                    pass
                elif action == "redeem":
                    pass
                elif action == "burn":
                    pass
                elif action == "write":
                    # select from available symbols
                    available_symbols
                elif action == "buy":
                    pass
                elif action == "sell":
                    pass
                elif action == "liquidate":
                    pass
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
        #'''
        for tmp_tx_hash in tx_hashes:
            receipt = w3.eth.waitForTransactionReceipt(tmp_tx_hash['hash'], poll_latency=tx_pool_latency)
            tx_hashes_good += receipt["status"]
            if receipt["status"] == 0:
                tx_fails.append(tmp_tx_hash['type'])
        #'''

        logger.info("total tx: {}, successful tx: {}, tx fails: {}".format(
                len(tx_hashes), tx_hashes_good, json.dumps(tx_fails)
            )
        )

        return anyone_acted, seleted_advancer

def main():
    """
    Main function: run the simulation.
    """
    global avax_cchain_nonces
    
    logging.basicConfig(level=logging.INFO)
    logger.info('Total Agents: {}'.format(len(w3.eth.accounts[:max_accounts])))
    
    options_exchange = w3.eth.contract(abi=OptionsExchangeContract['abi'], address=EXCHG["addr"])
    usdt = TokenProxy(w3.eth.contract(abi=USDTContract['abi'], address=USDT["addr"]))
    credit_provider = w3.eth.contract(abi=CreditProviderContract['abi'], address=CREDPRO["addr"])
    linear_liquidity_pool = w3.eth.contract(abi=LinearLiquidityPoolContract['abi'], address=LLP["addr"])
    protocol_settings = w3.eth.contract(abi=ProtocolSettingsContract['abi'], address=STG['addr'])
    btcusd_chainlink_feed = w3.eth.contract(abi=ChainlinkFeedContract['abi'], address=BTCUSDc['addr'])
    btcusd_agg = w3.eth.contract(abi=AggregatorV3MockContract['abi'], address=BTCUSDAgg["addr"])


    '''
        INIT FEEDS FOR BTCUSDAGG
    '''
    btcusd_historical_ohlc = []

    with open('data/BTC-USD_vol_date_high_low_close.json', 'r+') as btcusd_file:
        btcusd_historical_ohlc = json.loads(btcusd_file.read())["chart"]
    

    daily_period = 60 * 60 * 24
    current_timestamp = int(w3.eth.get_block('latest')['timestamp'])
    btcusd_answers = [float(x["open"]) * (10**xSD['decimals']) for x in btcusd_historical_ohlc]


    '''
        SETUP POOL:
            All options must have maturities under the pool maturity
    '''
    pool_spread = 5 * (10**7)
    pool_reserve_ratio = 20 * (10**7)
    pool_maturity = (1000000000 * daily_period) + current_timestamp
    linear_liquidity_pool.functions.setParameters(
        pool_spread,
        pool_reserve_ratio,
        pool_maturity
    ).transact({
        'nonce': get_nonce(agent),
        'from' : agent.address,
        'gas': 500000,
        'gasPrice': Web3.toWei(225, 'gwei'),
    })

    '''
        SETUP PROTOCOL SETTINGS FOR POOL
    '''

    protocol_settings.functions.setOwner(
        linear_liquidity_pool.address,
    ).transact({
        'nonce': get_nonce(agent),
        'from' : agent.address,
        'gas': 500000,
        'gasPrice': Web3.toWei(225, 'gwei'),
    })

    protocol_settings.functions.setAllowedToken(
        usdt.address,
        1,
        1
    ).transact({
        'nonce': get_nonce(agent),
        'from' : agent.address,
        'gas': 500000,
        'gasPrice': Web3.toWei(225, 'gwei'),
    })

    protocol_settings.functions.setDefaultUdlFeed(
        btcusd_chainlink_feed.address,
    ).transact({
        'nonce': get_nonce(agent),
        'from' : agent.address,
        'gas': 500000,
        'gasPrice': Web3.toWei(225, 'gwei'),
    })

    protocol_settings.functions.setUdlFeed(
        btcusd_chainlink_feed.address,
        1
    ).transact({
        'nonce': get_nonce(agent),
        'from' : agent.address,
        'gas': 500000,
        'gasPrice': Web3.toWei(225, 'gwei'),
    })

    protocol_settings.functions.setVolatilityPeriod(
        30 * daily_period
    ).transact({
        'nonce': get_nonce(agent),
        'from' : agent.address,
        'gas': 500000,
        'gasPrice': Web3.toWei(225, 'gwei'),
    })

    avax_cchain_nonces = open(MMAP_FILE, "r+b")

    # Make a model of the economy
    start_init = time.time()
    logger.info('INIT STARTED')
    model = Model(options_exchange, credit_provider, liquidity_pool, btcusd_chainlink_feed, btcusd_agg, btcusd_answers, w3.eth.accounts[:max_accounts], min_faith=0.5E6, max_faith=1E6, use_faith=False)
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
        
if __name__ == "__main__":
    main()
