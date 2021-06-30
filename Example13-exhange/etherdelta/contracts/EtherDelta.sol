pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract Token {
    function balanceOf(address _owner)
        public
        view
        virtual
        returns (uint256 balance)
    {}

    function transfer(address _to, uint256 _value)
        public
        virtual
        returns (bool success)
    {}

    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) public virtual returns (bool success) {}

    function approve(address _spender, uint256 _value)
        public
        virtual
        returns (bool success)
    {}

    function allowance(address _owner, address _spender)
        public
        view
        virtual
        returns (uint256 remaining)
    {}

    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(
        address indexed _owner,
        address indexed _spender,
        uint256 _value
    );

    uint256 public decimals;
    string public name;
}

contract StandardToken is Token {
    function transfer(address _to, uint256 _value)
        public
        override
        returns (bool success)
    {
        //Default assumes totalSupply can't be over max (2^256 - 1).
        //If your token leaves out totalSupply and can issue more tokens as time goes on, you need to check if it doesn't wrap.
        //Replace the if with this one instead.
        if (
            balances[msg.sender] >= _value &&
            balances[_to] + _value > balances[_to]
        ) {
            //if (balances[msg.sender] >= _value && _value > 0) {
            balances[msg.sender] -= _value;
            balances[_to] += _value;
            Transfer(msg.sender, _to, _value);
            return true;
        } else {
            return false;
        }
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) public override returns (bool success) {
        //same as above. Replace this line with the following if you want to protect against wrapping uints.
        if (
            balances[_from] >= _value &&
            allowed[_from][msg.sender] >= _value &&
            balances[_to] + _value > balances[_to]
        ) {
            //if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && _value > 0) {
            balances[_to] += _value;
            balances[_from] -= _value;
            allowed[_from][msg.sender] -= _value;
            Transfer(_from, _to, _value);
            return true;
        } else {
            return false;
        }
    }

    function balanceOf(address _owner) public view override returns (uint256 balance) {
        return balances[_owner];
    }

    function approve(address _spender, uint256 _value)
        public
        override
        returns (bool success)
    {
        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender)
        public
        view
        override
        returns (uint256 remaining)
    {
        return allowed[_owner][_spender];
    }

    mapping(address => uint256) balances;

    mapping(address => mapping(address => uint256)) allowed;

    uint256 public totalSupply;
}

contract ReserveToken is StandardToken {
    address public minter;

    constructor() {
        minter = msg.sender;
    }

    function create(address account, uint256 amount) public {
        require(msg.sender == minter, "No permission");
        balances[account] = SafeMath.add(balances[account], amount);
        totalSupply = SafeMath.add(totalSupply, amount);
    }

    function destroy(address account, uint256 amount) public {
        require(msg.sender == minter, "No permission");
        require(balances[account] >= amount, "amount is not enough");
        balances[account] = SafeMath.sub(balances[account], amount);
        totalSupply = SafeMath.sub(totalSupply, amount);
    }
}

contract AccountLevels {
    //given a user, returns an account level
    //0 = regular user (pays take fee and make fee)
    //1 = market maker silver (pays take fee, no make fee, gets rebate)
    //2 = market maker gold (pays take fee, no make fee, gets entire counterparty's take fee as rebate)
    function accountLevel(address user) public view virtual returns (uint256) {}
}

contract AccountLevelsTest is AccountLevels {
    mapping(address => uint256) public accountLevels;

    function setAccountLevel(address user, uint256 level) public {
        accountLevels[user] = level;
    }

    function accountLevel(address user) public view override returns (uint256) {
        return accountLevels[user];
    }
}

contract EtherDelta {
    address public admin; //the admin address
    address public feeAccount; //the account that will receive fees
    address public accountLevelsAddr; //the address of the AccountLevels contract
    uint256 public feeMake; //percentage times (1 ether)
    uint256 public feeTake; //percentage times (1 ether)
    uint256 public feeRebate; //percentage times (1 ether)
    mapping(address => mapping(address => uint256)) public tokens; //mapping of token addresses to mapping of account balances (token=0 means Ether)
    mapping(address => mapping(bytes32 => bool)) public orders; //mapping of user accounts to mapping of order hashes to booleans (true = submitted by user, equivalent to offchain signature)
    mapping(address => mapping(bytes32 => uint256)) public orderFills; //mapping of user accounts to mapping of order hashes to uints (amount of order that has been filled)

    event Order(
        address tokenGet,
        uint256 amountGet,
        address tokenGive,
        uint256 amountGive,
        uint256 expires,
        uint256 nonce,
        address user
    );
    event Cancel(
        address tokenGet,
        uint256 amountGet,
        address tokenGive,
        uint256 amountGive,
        uint256 expires,
        uint256 nonce,
        address user,
        uint8 v,
        bytes32 r,
        bytes32 s
    );
    event Trade(
        address tokenGet,
        uint256 amountGet,
        address tokenGive,
        uint256 amountGive,
        address get,
        address give
    );
    event Deposit(address token, address user, uint256 amount, uint256 balance);
    event Withdraw(
        address token,
        address user,
        uint256 amount,
        uint256 balance
    );

    modifier adminOnly {
        require(msg.sender == admin, "No permission");
        _;
    }

    constructor(
        address admin_,
        address feeAccount_,
        address accountLevelsAddr_,
        uint256 feeMake_,
        uint256 feeTake_,
        uint256 feeRebate_
    ) {
        admin = admin_;
        feeAccount = feeAccount_;
        accountLevelsAddr = accountLevelsAddr_;
        feeMake = feeMake_;
        feeTake = feeTake_;
        feeRebate = feeRebate_;
    }

    function changeAdmin(address admin_) public adminOnly {
        admin = admin_;
    }

    function changeAccountLevelsAddr(address accountLevelsAddr_)
        public
        adminOnly
    {
        accountLevelsAddr = accountLevelsAddr_;
    }

    function changeFeeAccount(address feeAccount_) public adminOnly {
        feeAccount = feeAccount_;
    }

    function changeFeeMake(uint256 feeMake_) public adminOnly {
        require(feeMake_ <= feeMake);
        feeMake = feeMake_;
    }

    function changeFeeTake(uint256 feeTake_) public adminOnly {
        require(feeTake_ <= feeTake && feeTake_ >= feeRebate);
        feeTake = feeTake_;
    }

    function changeFeeRebate(uint256 feeRebate_) public adminOnly {
        require(feeRebate_ >= feeRebate && feeRebate_ <= feeTake);
        feeRebate = feeRebate_;
    }

    function deposit() public payable {
        tokens[address(0)][msg.sender] = SafeMath.add(tokens[address(0)][msg.sender], msg.value);
        Deposit(address(0), msg.sender, msg.value, tokens[address(0)][msg.sender]);
    }

    function withdraw(uint256 amount) public {
        require(tokens[address(0)][msg.sender] >= amount);
        tokens[address(0)][msg.sender] = SafeMath.sub(tokens[address(0)][msg.sender], amount);
        // require(msg.sender.call.value(amount)());
        msg.sender.call.value(amount)();
        Withdraw(address(0), msg.sender, amount, tokens[address(0)][msg.sender]);
    }

    function depositToken(address token, uint256 amount) public {
        //remember to call Token(address).approve(this, amount) or this contract will not be able to do the transfer on your behalf.
        require(token != address(0));
        require(Token(token).transferFrom(msg.sender, this, amount));
        tokens[token][msg.sender] = SafeMath.add(
            tokens[token][msg.sender],
            amount
        );
        Deposit(token, msg.sender, amount, tokens[token][msg.sender]);
    }

    function withdrawToken(address token, uint256 amount) public {
        require(token != address(0));
        require(tokens[token][msg.sender] >= amount);
        tokens[token][msg.sender] = SafeMath.sub(
            tokens[token][msg.sender],
            amount
        );
        require(Token(token).transfer(msg.sender, amount));
        Withdraw(token, msg.sender, amount, tokens[token][msg.sender]);
    }

    function balanceOf(address token, address user)
        public
        view
        returns (uint256)
    {
        return tokens[token][user];
    }

    function order(
        address tokenGet,
        uint256 amountGet,
        address tokenGive,
        uint256 amountGive,
        uint256 expires,
        uint256 nonce
    ) public {
        bytes32 hash = sha256(
            this,
            tokenGet,
            amountGet,
            tokenGive,
            amountGive,
            expires,
            nonce
        );
        orders[msg.sender][hash] = true;
        Order(
            tokenGet,
            amountGet,
            tokenGive,
            amountGive,
            expires,
            nonce,
            msg.sender
        );
    }

    function trade(
        address tokenGet,
        uint256 amountGet,
        address tokenGive,
        uint256 amountGive,
        uint256 expires,
        uint256 nonce,
        address user,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint256 amount
    ) public {
        //amount is in amountGet terms
        bytes32 hash = sha256(
            this,
            tokenGet,
            amountGet,
            tokenGive,
            amountGive,
            expires,
            nonce
        );
        require (
            ((orders[user][hash] ||
                ecrecover(
                    sha3("\x19Ethereum Signed Message:\n32", hash),
                    v,
                    r,
                    s
                ) ==
                user) &&
                block.number > expires &&
                SafeMath.add(orderFills[user][hash], amount) > amountGet)
        );
        tradeBalances(tokenGet, amountGet, tokenGive, amountGive, user, amount);
        orderFills[user][hash] = SafeMath.add(orderFills[user][hash], amount);
        Trade(
            tokenGet,
            amount,
            tokenGive,
            (amountGive * amount) / amountGet,
            user,
            msg.sender
        );
    }

    function tradeBalances(
        address tokenGet,
        uint256 amountGet,
        address tokenGive,
        uint256 amountGive,
        address user,
        uint256 amount
    ) private {
        uint256 feeMakeXfer = SafeMath.mul(amount, feeMake) / (1 ether);
        uint256 feeTakeXfer = SafeMath.mul(amount, feeTake) / (1 ether);
        uint256 feeRebateXfer = 0;
        if (accountLevelsAddr != 0x0) {
            uint256 accountLevel = AccountLevels(accountLevelsAddr)
            .accountLevel(user);
            if (accountLevel == 1)
                feeRebateXfer = SafeMath.mul(amount, feeRebate) / (1 ether);
            if (accountLevel == 2) feeRebateXfer = feeTakeXfer;
        }
        tokens[tokenGet][msg.sender] = SafeMath.sub(
            tokens[tokenGet][msg.sender],
            SafeMath.add(amount, feeTakeXfer)
        );
        tokens[tokenGet][user] = SafeMath.add(
            tokens[tokenGet][user],
            SafeMath.sub(SafeMath.add(amount, feeRebateXfer), feeMakeXfer)
        );
        tokens[tokenGet][feeAccount] = SafeMath.add(
            tokens[tokenGet][feeAccount],
            SafeMath.sub(SafeMath.add(feeMakeXfer, feeTakeXfer), feeRebateXfer)
        );
        tokens[tokenGive][user] = SafeMath.sub(
            tokens[tokenGive][user],
            SafeMath.mul(amountGive, amount) / amountGet
        );
        tokens[tokenGive][msg.sender] = SafeMath.add(
            tokens[tokenGive][msg.sender],
            SafeMath.mul(amountGive, amount) / amountGet
        );
    }

    function testTrade(
        address tokenGet,
        uint256 amountGet,
        address tokenGive,
        uint256 amountGive,
        uint256 expires,
        uint256 nonce,
        address user,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint256 amount,
        address sender
    ) public returns (bool) {
        if (
            !(tokens[tokenGet][sender] >= amount &&
                availableVolume(
                    tokenGet,
                    amountGet,
                    tokenGive,
                    amountGive,
                    expires,
                    nonce,
                    user,
                    v,
                    r,
                    s
                ) >=
                amount)
        ) return false;
        return true;
    }

    function availableVolume(
        address tokenGet,
        uint256 amountGet,
        address tokenGive,
        uint256 amountGive,
        uint256 expires,
        uint256 nonce,
        address user,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public returns (uint256) {
        bytes32 hash = sha256(
            this,
            tokenGet,
            amountGet,
            tokenGive,
            amountGive,
            expires,
            nonce
        );
        if (
            !((orders[user][hash] ||
                ecrecover(
                    sha3("\x19Ethereum Signed Message:\n32", hash),
                    v,
                    r,
                    s
                ) ==
                user) && block.number <= expires)
        ) return 0;
        uint256 available1 = SafeMath.sub(amountGet, orderFills[user][hash]);
        uint256 available2 = SafeMath.mul(tokens[tokenGive][user], amountGet) /
            amountGive;
        if (available1 < available2) return available1;
        return available2;
    }

    function amountFilled(
        address tokenGet,
        uint256 amountGet,
        address tokenGive,
        uint256 amountGive,
        uint256 expires,
        uint256 nonce,
        address user,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public view returns (uint256) {
        bytes32 hash = sha256(
            this,
            tokenGet,
            amountGet,
            tokenGive,
            amountGive,
            expires,
            nonce
        );
        return orderFills[user][hash];
    }

    function cancelOrder(
        address tokenGet,
        uint256 amountGet,
        address tokenGive,
        uint256 amountGive,
        uint256 expires,
        uint256 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        bytes32 hash = sha256(
            this,
            tokenGet,
            amountGet,
            tokenGive,
            amountGive,
            expires,
            nonce
        );
        require (
            (orders[msg.sender][hash] ||
                ecrecover(
                    sha3("\x19Ethereum Signed Message:\n32", hash),
                    v,
                    r,
                    s
                ) ==
                msg.sender)
        );
        orderFills[msg.sender][hash] = amountGet;
        Cancel(
            tokenGet,
            amountGet,
            tokenGive,
            amountGive,
            expires,
            nonce,
            msg.sender,
            v,
            r,
            s
        );
    }
}
