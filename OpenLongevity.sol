/*
This file is part of the Open Longevity Contract.

The Open Longevity Contract is free software: you can redistribute it and/or
modify it under the terms of the GNU lesser General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

The Open Longevity Contract is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU lesser General Public License for more details.

You should have received a copy of the GNU lesser General Public License
along with the Open Longevity Contract. If not, see <http://www.gnu.org/licenses/>.
*/


pragma solidity ^0.4.0;

contract owned {
    address public owner;

    function owned() {
        owner = msg.sender;
    }
    
    modifier onlyOwner {
        if (owner != msg.sender) throw;
        _;
    }

    function changeOwner(address _owner) onlyOwner public {
        if (_owner == 0) throw;
        owner = _owner;
    }
}

contract Crowdsale is owned {
    
    uint256 public totalSupply = 0;

    struct TokenHolder {
        uint256 balance;
        uint256 balanceHold;
        uint    balanceUpdateTime;
        uint    rewardWithdrawTime;
    }
    mapping (address => TokenHolder) public holders;

    enum State { Disabled, Crowdsale, Enabled }
    State public state = State.Disabled;
    event NewState(State state);
    uint public crowdsaleFinishTime;
    uint public crowdsaleStartTime;

    modifier enabledState {
        if (state != State.Enabled) throw;
        _;
    }

    struct Investor {
        address investor;
        uint    amount;
    }
    Investor[] public investors;
    uint public       numberOfInvestors;
    
    function () payable {
        if (state == State.Disabled) throw;
        if (state == State.Crowdsale) {
            uint256 tokensPerEther;
            if (msg.value >= 300 ether) {
                tokensPerEther = 1750;
            } else if (now < crowdsaleStartTime + 1 days) {
                tokensPerEther = 1500;
            } else if (now < crowdsaleStartTime + 1 weeks) {
                tokensPerEther = 1250;
            } else {
                tokensPerEther = 1000;
            }
            uint256 tokens = tokensPerEther * msg.value / 1000000000000000000;
            if (holders[msg.sender].balance + tokens < holders[msg.sender].balance) throw; // overflow
            holders[msg.sender].balance += tokens;
            totalSupply += tokens;
            numberOfInvestors = investors.length++;
            investors[numberOfInvestors] = Investor({investor: msg.sender, amount: msg.value});
        }
        //if (state == State.Enabled) { /* it is donation */ }
    }
    
    function startCrowdsale() public onlyOwner {
        if (state != State.Disabled) throw;
        crowdsaleStartTime = now;
        crowdsaleFinishTime = now + 30 days;
        state = State.Crowdsale;
        NewState(state);
    }
    
    function timeToFinishCrowdsale() public constant returns(uint t) {
        if (state != State.Crowdsale) throw;
        if (now > crowdsaleFinishTime) {
            t = 0;
        } else {
            t = crowdsaleFinishTime - now;
        }
    }
    
    function finishCrowdsale() public onlyOwner {
        if (state != State.Crowdsale) throw;
        if (now < crowdsaleFinishTime) throw;
        if (this.balance < 25000 ether) {
            // Crowdsale failed. Need to return ether to investors
            for (uint i = 0; i <  investors.length; ++i) {
                Investor inv = investors[i];
                uint amount = inv.amount;
                address investor = inv.investor;
                delete holders[inv.investor];
                if(!investor.send(amount)) throw;
            }
            state = State.Disabled;
        } else {
            if (!msg.sender.send(20000 ether)) throw;
            // Emit additional tokens for owner (20% of complete totalSupply)
            holders[msg.sender].balance = totalSupply / 4;
            totalSupply += totalSupply / 4;
            state = State.Enabled;
        }
        delete investors;
        numberOfInvestors = 0;
        crowdsaleStartTime = 0;
        crowdsaleFinishTime = 0;
        NewState(state);
    }
}

contract Token is Crowdsale {
    
    string  public standard    = 'Token 0.1';
    string  public name        = 'YEAR';
    string  public symbol      = "Y";
    uint8   public decimals    = 0;

    uint lastDivideRewardTime;
    uint totalForWithdraw;
    uint restForWithdraw;

    uint totalReward;

    modifier onlyTokenHolders {
        if (balanceOf(msg.sender) == 0) throw;
        _;
    }

    mapping (address => mapping (address => uint256)) public allowed;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Burned(address indexed owner, uint256 value);
    event DivideUpReward(uint total);

    modifier noEther() {
        if (msg.value > 0) throw; 
        _;
    }

    function Token() Crowdsale() {
        lastDivideRewardTime = now;
        totalForWithdraw = 0;
        restForWithdraw = 0;
        totalReward = 0;
    }

    function balanceOf(address _owner) public constant
        returns (uint256 balance) {
        return holders[_owner].balance;
    }
    
    function transfer(address _to, uint256 _value) public noEther enabledState {
        if (holders[msg.sender].balance < _value) throw;
        if (holders[_to].balance + _value < holders[_to].balance) throw; // overflow
        beforeBalanceChanges(msg.sender);
        beforeBalanceChanges(_to);
        holders[msg.sender].balance -= _value;
        holders[_to].balance += _value;
        Transfer(msg.sender, _to, _value);
    }
    
    function transferFrom(address _from, address _to, uint256 _value) public noEther {
        if (holders[_from].balance < _value) throw;
        if (holders[_to].balance + _value < holders[_to].balance) throw; // overflow
        if (allowed[_from][msg.sender] < _value) throw;
        beforeBalanceChanges(_from);
        beforeBalanceChanges(_to);
        holders[_from].balance -= _value;
        holders[_to].balance += _value;
        allowed[_from][msg.sender] -= _value;
        Transfer(_from, _to, _value);
    }

    function approve(address _spender, uint256 _value) public noEther enabledState {
        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
    }

    function allowance(address _owner, address _spender) public constant enabledState
        returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }

    function burn(uint256 _value) public enabledState {
        if (holders[msg.sender].balance < _value || _value <= 0) throw;
        holders[msg.sender].balance -= _value;
        totalSupply -= _value;
        Burned(msg.sender, _value);

        // Send ether to caller
        uint amount;
        if (totalSupply == 0) {
            amount = this.balance;
        } else {
            amount = this.balance - (totalReward + restForWithdraw);
            amount = (amount * _value) / totalSupply;
        }
        if (!msg.sender.send(amount)) throw;
    }
    
    function reward() constant public enabledState returns(uint) {
        if (holders[msg.sender].rewardWithdrawTime >= lastDivideRewardTime) {
            return 0;
        }
        uint256 balance;
        if (holders[msg.sender].balanceUpdateTime <= lastDivideRewardTime) {
            balance = holders[msg.sender].balance;
        } else {
            balance = holders[msg.sender].balanceHold;
        }
        return totalForWithdraw * balance / totalSupply;
    }

    function withdrawReward() public enabledState returns(uint) {
        uint value = reward();
        if (value == 0) {
            return 0;
        }
        if (!msg.sender.send(value)) {
            return 0;
        }
        if (holders[msg.sender].balance == 0) {
            delete holders[msg.sender];
        } else {
            holders[msg.sender].rewardWithdrawTime = now;
        }
        return value;
    }

    function divideUpReward() enabledState onlyTokenHolders public {
        if (holders[msg.sender].balance == 0) throw;
        if (lastDivideRewardTime + 90 days > now) throw;
        restForWithdraw += totalReward;
        totalForWithdraw = restForWithdraw;
        totalReward = 0;
        lastDivideRewardTime = now;
        DivideUpReward(totalForWithdraw);
    }
    
    function beforeBalanceChanges(address _who) enabledState private {
        if (holders[_who].balanceUpdateTime <= lastDivideRewardTime) {
            holders[_who].balanceUpdateTime = now;
            holders[_who].balanceHold = holders[_who].balance;
        }
    }
}

contract OpenLongevity is Token {

    function OpenLongevity() Token() {}

    event Deployed(address indexed projectOwner, uint weiReqFund, string urlInfo);
    event Voted(address indexed projectOwner, address indexed voter, bool inSupport);
    event VotingFinished(address indexed projectOwner, bool inSupport);
    event Payment(uint service, uint any, address indexed client, uint amount);

    struct Vote {
        bool    inSupport;
        address voter;
    }

    struct Project {
        uint   weiReqFund;
        string urlInfo;
        uint   votingDeadline;
        Vote[] votes;
        mapping (address => bool) voted;
        uint   numberOfVotes;
    }
    mapping (address => Project) public projects;

    function deployProject(uint _weiReqFund, string _urlInfo) public payable enabledState {
        if (msg.value < 1 ether && balanceOf(msg.sender)*1000/totalSupply < 1) throw;
        if (_weiReqFund <= 0 && _weiReqFund > (this.balance - totalReward - restForWithdraw)) throw;
        if (projects[msg.sender].weiReqFund > 0) throw;
        projects[msg.sender].weiReqFund = _weiReqFund;
        projects[msg.sender].urlInfo = _urlInfo;
        projects[msg.sender].votingDeadline = now + 7 days;
        Deployed(msg.sender, _weiReqFund, _urlInfo);
    }
    
    function projectInfo(address _projectOwner) enabledState public 
        returns(uint _weiReqFund, string _urlInfo, uint _timeToFinish) {
        _weiReqFund = projects[_projectOwner].weiReqFund;
        _urlInfo    = projects[_projectOwner].urlInfo;
        if (projects[_projectOwner].votingDeadline <= now) {
            _timeToFinish = 0;
        } else {
            _timeToFinish = projects[_projectOwner].votingDeadline - now;
        }
    }

    function vote(address _projectOwner, bool _inSupport) public onlyTokenHolders enabledState
        returns (uint voteId) {
        Project p = projects[_projectOwner];
        if (p.voted[msg.sender] == true) throw;
        if (p.votingDeadline <= now) throw;
        voteId = p.votes.length++;
        p.votes[voteId] = Vote({inSupport: _inSupport, voter: msg.sender});
        p.voted[msg.sender] = true;
        p.numberOfVotes = voteId + 1;
        Voted(_projectOwner, msg.sender, _inSupport); 
        return voteId;
    }

    function finishVoting(address _projectOwner) public enabledState returns (bool _inSupport) {
        Project p = projects[_projectOwner];
        if (now < p.votingDeadline || p.weiReqFund > (this.balance - totalReward - restForWithdraw)) throw;

        uint yea = 0;
        uint nay = 0;

        for (uint i = 0; i <  p.votes.length; ++i) {
            Vote v = p.votes[i];
            uint voteWeight = balanceOf(v.voter);
            if (v.inSupport) {
                yea += voteWeight;
            } else {
                nay += voteWeight;
            }
        }

        _inSupport = (yea > nay);

        if (_inSupport) {
            if (!_projectOwner.send(p.weiReqFund)) throw;
        }

        VotingFinished(_projectOwner, _inSupport);
        delete projects[_projectOwner];
    }
    
    function paymentForService(uint _service, uint _any) payable enabledState public {
        uint rewardPercent = 5;
        if (now > crowdsaleFinishTime) {
            rewardPercent = 20;
        } else if (now > crowdsaleFinishTime + 2 years) {
            rewardPercent = 15;
        } else if (now > crowdsaleFinishTime + 1 years) {
            rewardPercent = 10;
        }
        uint reward = msg.value * rewardPercent / 100;
        totalReward += reward;        
        Payment(_service, _any, msg.sender, msg.value);
    }
}