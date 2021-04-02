#!/usr/bin/env python3

"""
model.py: agent-based model of xSD system behavior, against a testnet
"""

import json
import collections
import random
import math
import logging
import time
import sys
import os
from eth_abi import decoding
from web3 import Web3

IS_DEBUG = False
is_try_model_mine = False
max_accounts = 40
block_offset = 19 + max_accounts
tx_pool_latency = 0.01

DEADLINE_FROM_NOW = 60 * 60 * 24 * 7 * 52
UINT256_MAX = 2**256 - 1
ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

deploy_data = None
with open("deploy_output.txt", 'r+') as f:
    deploy_data = f.read()

logger = logging.getLogger(__name__)
#provider = Web3.HTTPProvider('http://127.0.0.1:7545/ext/bc/C/rpc', request_kwargs={"timeout": 60*300})
provider = Web3.WebsocketProvider('ws://127.0.0.1:9545/ext/bc/C/ws', websocket_timeout=60*300)

'''
curl -X POST --data '{ "jsonrpc":"2.0", "id" :1, "method" :"platform.incrementTimeTx", "params" :{ "time": 10000 }}' -H 'content-type:application/json;' http://127.0.0.1:9545/ext/P

curl -X POST --data '{ "jsonrpc":"2.0", "id" :1, "method" :"evm.increaseTime", "params" : [0]}' -H 'content-type:application/json;' http://127.0.0.1:9545/ext/bc/C/rpc
'''
providerAvax = Web3.HTTPProvider('http://127.0.0.1:9545/ext/bc/C/avax', request_kwargs={"timeout": 60*300})
w3 = Web3(provider)
from web3.middleware import geth_poa_middleware
w3.middleware_onion.inject(geth_poa_middleware, layer=0)

w3.eth.defaultAccount = w3.eth.accounts[0]
logger.info(w3.eth.blockNumber)
logger.info(w3.clientVersion)
#sys.exit()

# from (Pangolin pair is at:)
PGL = {
  "addr": '',
  "decimals": 18,
  "symbol": 'PGL',
  "deploy_slug": "Pangolin pair is at: "
}

# USDC is at: 
USDC = {
  "addr": '',
  "decimals": 6,
  "symbol": 'USDC',
  "deploy_slug": "USDC is at: "
}

#Pool is at: 
PGLLP = {
    "addr": '',
    "decimals": 18,
    "deploy_slug": "Pool is at: "
}

#PangolinRouter is at: 
PGLRouter = {
    "addr": "",
    "decimals": 12,
    "deploy_slug": "PangolinRouter is at: "
}

for contract in [PGL, USDC, PGLLP, PGLRouter]:
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
CreditTokenContract = json.loads(open('./build/contracts/CreditToken.json', 'r+').read())
CreditProviderContract = json.loads(open('./build/contracts/CreditProvider.json', 'r+').read())
OptionsExchangeContract = json.loads(open('./build/contracts/OptionsExchange.json', 'r+').read())
OptionTokenContract = json.loads(open('./build/contracts/OptionToken.json', 'r+').read())
ProtocolSettingsContract = json.loads(open('./build/contracts/ProtocolSettings.json', 'r+').read())

ERC20StableCoinContract = json.loads(open('./build/contracts/ERC20.json', 'r+').read())


def get_addr_from_contract(contract):
    return contract["networks"][str(sorted(map(int,contract["networks"].keys()))[0])]["address"]

StableCoin['addr'] = get_addr_from_contract(ERC20StableCoinContract)

def get_nonce(agent):
    current_block = int(w3.eth.get_block('latest')["number"])

    if current_block not in agent.seen_block:
        if (agent.current_block == 0):
            agent.current_block += 1
        else:
            agent.next_tx_count += 1
    else:
        agent.next_tx_count += 1
        agent.seen_block[current_block] = True

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
    
    def __init__(self, dao, pangolin_pair, xsd_token, usdc_token, **kwargs):
 
        # xSD TokenProxy
        self.xsd_token = xsd_token
        # USDC TokenProxy 
        self.usdc_token = usdc_token
        # xSDS (Dao share) balance
        self.xsds = Balance(0, xSDS["decimals"])
        # avax balance
        self.avax = kwargs.get("starting_avax", Balance(0, 18))
        
        # Coupon underlying part by expiration epoch
        self.underlying_coupons = collections.defaultdict(float)
        # Coupon premium part by expiration epoch
        self.premium_coupons = collections.defaultdict(float)
        
        # What's our max faith in the system in USDC?
        self.max_faith = kwargs.get("max_faith", 0.0)
        # And our min faith
        self.min_faith = kwargs.get("min_faith", 0.0)
        # Should we even use faith?
        self.use_faith = kwargs.get("use_faith", True)

        # add wallet addr
        self.address = kwargs.get("wallet_address", '0x0000000000000000000000000000000000000000')

        #coupon expirys
        self.coupon_expirys = []
        # how many times coupons have been redeemmed
        self.redeem_count = 0

        self.dao = dao

        # current coupon assigned index of epoch
        self.max_coupon_epoch_index = 0

        # Pangolin Pair TokenProxy
        self.pangolin_pair_token = pangolin_pair

        # keeps track of latest block seen for nonce tracking/tx
        self.seen_block = {}
        self.next_tx_count = w3.eth.getTransactionCount(self.address, block_identifier=int(w3.eth.get_block('latest')["number"]))
        self.current_block = 0

        if kwargs.get("is_mint", False):
            # need to mint USDC to the wallets for each agent
            start_usdc_formatted = kwargs.get("starting_usdc", Balance(0, USDC["decimals"]))
            tx_hash = self.usdc_token.contract.functions.mint(
                self.address, start_usdc_formatted.to_wei()
            ).transact({
                'nonce': get_nonce(self),
                'from' : self.address,
                'gas': 500000,
                'gasPrice': Web3.toWei(470, 'gwei'),
            })
            time.sleep(1.1)
            w3.eth.waitForTransactionReceipt(tx_hash, poll_latency=tx_pool_latency)
        
    @property
    def xsd(self):
        """
        Get the current balance in USDC from the TokenProxy.
        """
        return self.xsd_token[self]
    
    @property
    def usdc(self):
        """
        Get the current balance in USDC from the TokenProxy.
        """
        return self.usdc_token[self]

    @property
    def lp(self):
        """
        Get the current balance in Pangolin LP Shares from the TokenProxy.
        """
        return self.pangolin_pair_token[self]

    @property
    def coupons(self):
        """
        Get the current balance in of coupons for agent
        """
        return self.dao.total_coupons_for_agent(self)
    
    def __str__(self):
        """
        Turn into a readable string summary.
        """
        return "Agent(xSD={:.2f}, usdc={:.2f}, avax={}, lp={}, coupons={:.2f})".format(
            self.xsd, self.usdc, self.avax, self.lp, self.coupons)

        
    def get_strategy(self, block, price, total_supply, total_coupons, agent_coupons):
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
            if price * total_supply > self.get_faith(block, price, total_supply):
                # There is too much xSD, so we want to sell
                strategy["sell"] = 10.0 if ((agent_coupons> 0) and (price > 1.0)) else 2.0
            else:
                # no faith based buying, just selling
                pass
        
        return strategy
        
    def get_faith(self, block, price, total_supply):
        """
        Get the total faith in xSD that this agent has, in USDC.
        
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
        faith = center_faith + swing_faith * math.sin(block * (2 * math.pi / 50))
        
        return faith
        

class OptionsExchange:
    def __init__(self, contract, stablecoin_token, liquidity_pool, **kwargs):
        self.contract = contract
        self.stablecoin_token = stablecoin_token
        self.liquidity_pool = liquidity_pool

    def deposit(self, agent, amount):
        '''
            ERC20 stablecoin = ERC20(0x123...);
            OptionsExchange exchange = OptionsExchange(0xABC...);

            address to = 0x456...;
            uint value = 100e18;
            stablecoin.approve(address(exchange), value);
            exchange.depositTokens(to, address(stablecoin), value);
        '''
        self.stablecoin_token.ensure_approved(agent, self.contract.address)
        tx = self.contract.functions.depositTokens(
            agent.address,
            self.stablecoin_token.address,
            amount.to_wei()
        ).transact({
            'nonce': get_nonce(agent),
            'from' : agent.address,
            'gas': 500000,
            'gasPrice': Web3.toWei(225, 'gwei'),
        })

        return tx

    def withwdraw(self, agent, amount):
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
            amount,
            StableCoin['decimals'],
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
            Balance(token_amount, StableCoin['decimals']).to_wei()
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

class CreditProvider:
    def __init__(self, contract, stablecoin_token, **kwargs):
        self.contract = contract
        self.stablecoin_token = stablecoin_token

class LiquidityPool:
    def __init__(self, contract, stablecoin_token, **kwargs):
        self.contract = contract
        self.stablecoin_token = stablecoin_token

    def get_holders_index(self, agent):
        pass

    def redeem(self, agent, holders_index):
        '''
            pool.redeem()
        '''
        self.contract.functions.redeem(
        ).transact({
            'nonce': get_nonce(agent),
            'from' : agent.address,
            'gas': 500000,
            'gasPrice': Web3.toWei(225, 'gwei'),
        })
        pass

    def buy(self, agent, symbol, price, volume):
        '''
            stablecoin.approve(address(pool), price * volume / volumeBase);
            pool.buy(symbol, price, volume, address(stablecoin));
        '''
        self.stablecoin_token.ensure_approved(agent, self.contract.address)
        self.contract.functions.buy(
            symbol,
            price,
            volume,
            self.stablecoin_token.contract.address
        ).transact({
            'nonce': get_nonce(agent),
            'from' : agent.address,
            'gas': 500000,
            'gasPrice': Web3.toWei(225, 'gwei'),
        })

    def sell(self, agent, symbol, price, volume, option_token_address):
        '''
            option_token.approve(address(pool), price * volume / volumeBase)`;
            pool.sell(symbol, price, volume)`;
        '''
        option_token = w3.eth.contract(abi=OptionTokenContract['abi'], address=option_token_address)
        self.stablecoin_token.ensure_approved(agent, self.contract.address)

        self.contract.functions.sell(
            symbol,
            price,
            volume
        ).transact({
            'nonce': get_nonce(agent),
            'from' : agent.address,
            'gas': 500000,
            'gasPrice': Web3.toWei(225, 'gwei'),
        })        

class Model:
    """
    Full model of the economy.
    """
    
    def __init__(self, options_exchange, agents, **kwargs):
        """
        Takes in experiment parameters and forwards them on to all components.
        """

        self.agents = []
        self.usdc_token = usdc
        self.pangolin_router = pangolin_router
        self.xsd_token = xsd
        self.max_avax = Balance.from_tokens(1000000, 18)
        self.max_usdc = self.usdc_token.from_tokens(100000)
        self.bootstrap_epoch = 2
        self.max_coupon_exp = 131400
        self.max_coupon_premium = 10
        self.min_usdc_balance = self.usdc_token.from_tokens(1)
        self.agent_coupons = {x: 0 for x in agents}
        self.has_prev_advanced = True


        is_mint = is_try_model_mine
        if w3.eth.get_block('latest')["number"] == block_offset:
            # THIS ONLY NEEDS TO BE RUN ON NEW CONTRACTS
            # TODO: tolerate redeployment or time-based generation
            is_mint = True
        
        total_tx_submitted = len(agents) 
        for i in range(len(agents)):
            start_avax = random.random() * self.max_avax
            start_usdc = random.random() * self.max_usdc
            
            address = agents[i]
            agent = Agent(self.dao, pangolin, xsd, usdc, starting_axax=start_avax, starting_usdc=start_usdc, wallet_address=address, is_mint=is_mint, **kwargs)
             
            self.agents.append(agent)

        # Update caches to current chain state
        self.usdc_token.update(is_init_agents=self.agents)
        self.xsd_token.update(is_init_agents=self.agents)
        self.pangolin.update(is_init_agents=self.agents)

        for i in range(len(agents)):
            if not is_mint:
                self.agent_coupons[self.agents[i].address] = self.agents[i].coupons
                self.dao.get_coupon_expirirations(self.agents[i])
            logger.info(self.agents[i])

        #sys.exit()
        
    def log(self, stream, seleted_advancer, header=False):
        """
        Log model statistics a TSV line.
        If header is True, include a header.
        """
        
        if header:
            stream.write("#block\tepoch\tprice\tsupply\tcoupons\tfaith\n")
        
        stream.write('{}\t{}\t{:.2f}\t{:.2f}\t{:.2f}\t{:.2f}\n'.format(
            w3.eth.get_block('latest')["number"],
            self.dao.epoch(seleted_advancer.address),
            self.pangolin.xsd_price(),
            self.dao.xsd_supply(),
            self.dao.total_coupons(),
            self.get_overall_faith())
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
        self.usdc_token.update()
        self.xsd_token.update()
        self.pangolin.update()

        logger.info("Clock: {}".format(w3.eth.get_block('latest')['timestamp']))

        for agent_num, a in enumerate(self.agents):            
            # TODO: real strategy
            options = []

            start_tx_count = a.next_tx_count
            commitment = random.random() * 0.1

            if len(options) > 0:
                # We can act

                '''
                    LATER:
                        advance: to do maintainence functions, payout from dynamic collateral and/or gov token
                    
                    TODO:
                        redeem                        
                    TOTEST:
                        deposit, withdraw, redeem, burn, write, buy, sell, liquidate
                    WORKS:
                        
                '''
        
                strategy = a.get_strategy(w3.eth.get_block('latest')["number"])
                
                weights = [strategy[o] for o in options]
                
                action = random.choices(options, weights=weights)[0]
                
                # What fraction of the total possible amount of doing this
                # action will the agent do?
                
                
                if action == "deposit":
                elif action == "withdraw":
                elif action == "redeem":
                elif action == "burn":
                elif action == "write":
                elif action == "buy":
                elif action == "liquidate":
                else:
                    raise RuntimeError("Bad action: " + action)
                    
                anyone_acted = True
            else:
                # It's normal for agents other then the first to advance to not be able to act on block 0.
                pass

            end_tx_count = a.next_tx_count

            total_tx_submitted += (end_tx_count - start_tx_count)

        if is_try_model_mine:
            # mine a block after every iteration for every tx sumbitted during round
            logger.info("{} sumbitted, mining blocks for them now, {} coupon bidders".format(
                total_tx_submitted, total_coupoun_bidders)
            )
        else:
            logger.info("{} coupon bidders".format(
                total_coupoun_bidders)
            )

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
    
    logging.basicConfig(level=logging.INFO)

    if w3.eth.get_block('latest')["number"] == block_offset:
        logger.info("Start Clock: {}".format(w3.eth.get_block('latest')['timestamp']))
        #logger.info(provider.make_request("debug_increaseTime", [0]))

        #logger.info(provider.make_request("debug_increaseTime", [7201+2400]))
        
    logger.info(w3.eth.get_block('latest')["number"])

    #sys.exit()

    logger.info('Total Agents: {}'.format(len(w3.eth.accounts[:max_accounts])))
    options_exchange = w3.eth.contract(abi=OptionsExchangeContract['abi'], address=xSDS["addr"])

    # Make a model of the economy
    start_init = time.time()
    logger.info('INIT STARTED')
    model = Model(options_exchange,  w3.eth.accounts[:max_accounts], min_faith=0.5E6, max_faith=1E6, use_faith=True)
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
