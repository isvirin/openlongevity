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
        require(owner == msg.sender);
        _;
    }

    function changeOwner(address _owner) onlyOwner public {
        require(_owner != 0);
        owner = _owner;
    }
}

contract Crowdsale is owned {
    
    uint256 public totalSupply = 0;
    mapping (address => uint256) public balanceOf;

    enum State { Disabled, PreICO, CompletePreICO, Crowdsale, Enabled }
    State public state = State.Disabled;
    event NewState(State state);
    uint public crowdsaleFinishTime;
    uint public crowdsaleStartTime;

    modifier enabledState {
        require(state == State.Enabled);
        _;
    }

    struct Investor {
        address investor;
        uint    amount;
    }
    Investor[] public investors;
    uint public       numberOfInvestors;
    
    function () payable {
        require(state != State.Disabled);
        uint256 tokensPerEther;
        if (state == State.PreICO) {
            if (msg.value >= 150 ether) {
                tokensPerEther = 2500;
            } else {
                tokensPerEther = 2000;
            }
        } else if (state == State.Crowdsale) {
            if (msg.value >= 300 ether) {
                tokensPerEther = 1750;
            } else if (now < crowdsaleStartTime + 1 days) {
                tokensPerEther = 1500;
            } else if (now < crowdsaleStartTime + 1 weeks) {
                tokensPerEther = 1250;
            } else {
                tokensPerEther = 1000;
            }
        }
        if (tokensPerEther > 0) {
            uint256 tokens = tokensPerEther * msg.value / 1000000000000000000;
            if (balanceOf[msg.sender] + tokens < balanceOf[msg.sender]) throw; // overflow
            balanceOf[msg.sender] += tokens;
            totalSupply += tokens;
            numberOfInvestors = investors.length++;
            investors[numberOfInvestors] = Investor({investor: msg.sender, amount: msg.value});
        }
        //if (state == State.Enabled) { /* it is donation */ }
    }
    
    function startTokensSale() public onlyOwner {
        require(state == State.Disabled || state == State.CompletePreICO);
        crowdsaleStartTime = now;
        if (state == State.Disabled) {
            crowdsaleFinishTime = now + 14 days;
            state = State.PreICO;
        } else {
            crowdsaleFinishTime = now + 30 days;
            state = State.Crowdsale;
        }
        NewState(state);
    }
    
    function timeToFinishTokensSale() public constant returns(uint t) {
        require(state == State.PreICO || state == State.Crowdsale);
        if (now > crowdsaleFinishTime) {
            t = 0;
        } else {
            t = crowdsaleFinishTime - now;
        }
    }

    function finishTokensSale() public onlyOwner {
        require(state == State.PreICO || state == State.Crowdsale);
        require(now >= crowdsaleFinishTime);
        if ((this.balance < 1000 ether && state == State.PreICO) &&
            (this.balance < 10000 ether && state == State.Crowdsale)) {
            // Crowdsale failed. Need to return ether to investors
            for (uint i = 0; i <  investors.length; ++i) {
                Investor inv = investors[i];
                uint amount = inv.amount;
                address investor = inv.investor;
                balanceOf[inv.investor] = 0;
                if(!investor.send(amount)) throw;
            }
            if (state == State.PreICO) {
                state = State.Disabled;
            } else {
                state = State.CompletePreICO;
            }
        } else {
            uint withdraw;
            if (state == State.PreICO) {
                withdraw = this.balance;
                state = State.CompletePreICO;
            } else if (state == State.Crowdsale) {
                if (this.balance < 15000 ether) {
                    withdraw = this.balance * 85 / 100;
                } else if (this.balance < 25000 ether) {
                    withdraw = this.balance * 80 / 100;
                } else if (this.balance < 35000 ether) {
                    withdraw = this.balance * 75 / 100;
                } else if (this.balance < 45000 ether) {
                    withdraw = this.balance * 70 / 100;
                } else {
                    withdraw = 13500 ether + (this.balance - 45000 ether);
                }
                state = State.Enabled;
                // Emit additional tokens for owner (20% of complete totalSupply)
                balanceOf[msg.sender] = totalSupply / 4;
                totalSupply += totalSupply / 4;
            }
            if (!msg.sender.send(withdraw)) throw;
            NewState(state);
        }
        delete investors;
        NewState(state);
    }
}

contract Token is Crowdsale {
    
    string  public standard    = 'Token 0.1';
    string  public name        = 'YEAR';
    string  public symbol      = "Y";
    uint8   public decimals    = 0;

    modifier onlyTokenHolders {
        require(balanceOf[msg.sender] != 0);
        _;
    }

    mapping (address => mapping (address => uint256)) public allowed;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Burned(address indexed owner, uint256 value);
    event DivideUpReward(uint total);

    function Token() Crowdsale() {}

    function transfer(address _to, uint256 _value) public enabledState {
        require(balanceOf[msg.sender] >= _value);
        require(balanceOf[_to] + _value >= balanceOf[_to]); // overflow
        balanceOf[msg.sender] -= _value;
        balanceOf[_to] += _value;
        Transfer(msg.sender, _to, _value);
    }
    
    function transferFrom(address _from, address _to, uint256 _value) public {
        require(balanceOf[_from] >= _value);
        require(balanceOf[_to] + _value >= balanceOf[_to]); // overflow
        require(allowed[_from][msg.sender] >= _value);
        balanceOf[_from] -= _value;
        balanceOf[_to] += _value;
        allowed[_from][msg.sender] -= _value;
        Transfer(_from, _to, _value);
    }

    function approve(address _spender, uint256 _value) public enabledState {
        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
    }

    function allowance(address _owner, address _spender) public constant enabledState
        returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }

    function burn(uint256 _value) public enabledState {
        require(now >= crowdsaleFinishTime + 1 years);
        require(balanceOf[msg.sender] >= _value);
        balanceOf[msg.sender] -= _value;
        totalSupply -= _value;
        Burned(msg.sender, _value);

        // Send ether to caller
        uint amount;
        if (totalSupply == 0) {
            amount = this.balance;
        } else {
            amount = (this.balance * _value) / totalSupply;
        }
        if (!msg.sender.send(amount)) throw;
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
        require(msg.value >= 1 ether || balanceOf[msg.sender]*1000/totalSupply >= 1);
        require(_weiReqFund > 0 && _weiReqFund <= this.balance);
        require(projects[msg.sender].weiReqFund == 0);
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
        require(p.voted[msg.sender] != true);
        require(p.votingDeadline > now);
        voteId = p.votes.length++;
        p.votes[voteId] = Vote({inSupport: _inSupport, voter: msg.sender});
        p.voted[msg.sender] = true;
        p.numberOfVotes = voteId + 1;
        Voted(_projectOwner, msg.sender, _inSupport); 
        return voteId;
    }

    function finishVoting(address _projectOwner) public enabledState returns (bool _inSupport) {
        Project p = projects[_projectOwner];
        require(now >= p.votingDeadline && p.weiReqFund <= this.balance);

        uint yea = 0;
        uint nay = 0;

        for (uint i = 0; i <  p.votes.length; ++i) {
            Vote v = p.votes[i];
            uint voteWeight = balanceOf[v.voter];
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
        Payment(_service, _any, msg.sender, msg.value);
    }
}