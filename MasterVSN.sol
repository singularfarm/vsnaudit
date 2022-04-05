//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./libs/IERC20.sol";
import "./Vision.sol";
import "./libs/SafeERC20.sol";
import "./libs/Ichef.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

interface IPol{
    function earn() external;
}
contract MasterVSN is Ownable, ReentrancyGuard{
    using SafeMath for uint;
    using SafeERC20 for IERC20;
    // Info of each user.
    struct UserInfo {
        uint amount;         // How many LP tokens the user has provided.
        uint rewardDebt;     // Reward debt. See explanation below.
        uint nftId;
        uint lastDeposited;
    }
    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint allocPoint;       // How many allocation points assigned to this pool. DUOs to distribute per block.
        uint lastRewardTime;  // Last block number that DUOs distribution occurs.
        uint accVsnPerShare;   // Accumulated DUOs per share, times 1e12. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
        uint16 withdrawFeeBP;
        uint totalcap;
        address strat;
        uint stratId;   //pid in strat contract, not the final dest
        bool NFT;
    }
    Vision public vsn;
    // Dev address.
    address public devaddr;
    address feeAddress;
    address public NFT;
    address public pol;
    uint public vsnPerSec;
    uint public totPaid;
    uint public earlyFeePeriod=3*86400;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint => mapping (address => UserInfo)) public userInfo;
    mapping (address=> mapping (uint=>bool)) public usedNFT;
    mapping (address=>bool) public approvedContracts;
    uint public totalAllocPoint;
    uint public startTime;
    event Deposit(address indexed user, uint indexed pid, uint amount);
    event Withdraw(address indexed user, uint indexed pid, uint amount);
    event EmergencyWithdraw(address indexed user, uint indexed pid, uint amount);
    modifier onlyEOA() {
        require(
            tx.origin == msg.sender || approvedContracts[msg.sender],
            "onlyEOA"
        );
        _;
    }
    constructor(Vision _vsn,address _nft,address _feeAddress,uint _vsnPerSec,uint _startTime) public { 
        require(_startTime>block.timestamp);
        startTime=_startTime; 
        vsn = _vsn;
        NFT=_nft;
        devaddr = msg.sender;
        feeAddress = _feeAddress;
        vsnPerSec = _vsnPerSec;
    }
    function poolLength() external view returns (uint) {
        return poolInfo.length;
    }
    function setStartTime(uint _startTime) external onlyOwner{
        require(block.timestamp<startTime || poolInfo.length==0,"already started");
        startTime=_startTime;
    }
    function setEarlyPeriod(uint _period) external onlyOwner{
        require(_period<=7*86400);
        earlyFeePeriod=_period;
    }
    function setPol(address _pol) external onlyOwner{
        pol=_pol;
    }
    function add(uint _allocPoint, IERC20 _lpToken, uint16 _depositFeeBP,uint16 _withdrawFeeBP, address _strat,uint _stratId,bool _nft,bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 400, "max 4%");
        require(_strat!=address(0));
        if (_withUpdate) {
            massUpdatePools();
        }
        uint lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardTime: lastRewardTime,
            accVsnPerShare: 0,
            depositFeeBP: _depositFeeBP,
            withdrawFeeBP: _withdrawFeeBP,
            totalcap:0,
            strat:_strat,
            stratId:_stratId,
            NFT:_nft
        }));
        if(_strat!=address(0)){
            _lpToken.approve(_strat,uint(-1));
        }
    }
    function set(uint _pid, uint _allocPoint, uint16 _depositFeeBP,uint16 _withdrawFeeBP, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 400, "max 4%");
        if (_withUpdate) {
            massUpdatePools();
        }
        PoolInfo storage pool = poolInfo[_pid];
        totalAllocPoint = totalAllocPoint.sub(pool.allocPoint).add(_allocPoint);
        pool.allocPoint = _allocPoint;
        pool.withdrawFeeBP=_withdrawFeeBP;
        pool.depositFeeBP = _depositFeeBP;
    }
    function pendingToken(uint _pid, address _user) external view returns (uint) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint accVsnPerShare = pool.accVsnPerShare;
        if (block.timestamp > pool.lastRewardTime && pool.totalcap != 0 && totalAllocPoint>0) {
            uint multiplier = block.timestamp.sub(pool.lastRewardTime);
            uint vsnReward = multiplier.mul(vsnPerSec).mul(pool.allocPoint).div(totalAllocPoint);
            accVsnPerShare = accVsnPerShare.add(vsnReward.mul(1e12).div(pool.totalcap));
        }
        return user.amount.mul(accVsnPerShare).div(1e12).sub(user.rewardDebt);
    }
    function massUpdatePools() public {
        uint length = poolInfo.length;
        for (uint pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }
    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        if (pool.totalcap == 0 || pool.allocPoint == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint multiplier = block.timestamp.sub(pool.lastRewardTime);
        uint vsnReward = multiplier.mul(vsnPerSec).mul(pool.allocPoint).div(totalAllocPoint);
        vsn.mint(devaddr, vsnReward.div(10));
        vsn.mint(address(this), vsnReward);
        pool.accVsnPerShare = pool.accVsnPerShare.add(vsnReward.mul(1e12).div(pool.totalcap));
        pool.lastRewardTime = block.timestamp;
    }
    function deposit(uint _pid, uint _amount) external onlyEOA nonReentrant{
        PoolInfo memory pool = poolInfo[_pid];
        require(!pool.NFT,"use NFT deposit");
        _deposit(_pid,_amount);
    }
    function deposit(uint _pid,uint _amount,uint _nftId) external onlyEOA nonReentrant{
        PoolInfo memory pool= poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(pool.NFT,"non NFT pool");
        require(user.nftId==0 || user.nftId==_nftId,"already in use");
        require(usedNFT[msg.sender][_nftId]==false || user.nftId==_nftId,"Id already in use");
        require(ERC721(NFT).ownerOf(_nftId)==msg.sender);
        _deposit(_pid, _amount);
        user.nftId=_nftId;
        usedNFT[msg.sender][_nftId]=true;
    }
    function _deposit(uint _pid,uint _amount) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint pending = user.amount.mul(pool.accVsnPerShare).div(1e12).sub(user.rewardDebt);
            safeVsnTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            uint before=pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
            _amount=pool.lpToken.balanceOf(address(this))-before;
            if(pool.depositFeeBP > 0){
                uint depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                _amount=_amount.sub(depositFee);
            }
            Strat(pool.strat).deposit(pool.stratId,_amount);
            user.amount = user.amount.add(_amount);
            user.lastDeposited=block.timestamp;
            pool.totalcap=pool.totalcap.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accVsnPerShare).div(1e12);
        if(pol!=address(0)){//trigger compounding on pol
            IPol(pol).earn();
        }
        emit Deposit(msg.sender, _pid, _amount);
    }
    function withdraw(uint _pid, uint _amount) external onlyEOA nonReentrant{
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        if(pool.NFT){
            require(ERC721(NFT).ownerOf(user.nftId)==msg.sender);
            if(user.amount==_amount){
                usedNFT[msg.sender][user.nftId]=false;
                user.nftId=0;//reset id
            }
        }
        updatePool(_pid);
        if(user.amount>0){
            uint pending = user.amount.mul(pool.accVsnPerShare).div(1e12).sub(user.rewardDebt);
            safeVsnTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            Strat(pool.strat).withdraw(pool.stratId, _amount);
            user.amount -= _amount;
            pool.totalcap=pool.totalcap.sub(_amount);
            uint feeBP=withdrawFee(msg.sender,_pid);
            uint wdfee=_amount.mul(feeBP).div(10000);
            if(wdfee>0){
                pool.lpToken.safeTransfer(feeAddress, wdfee);
            }
            pool.lpToken.safeTransfer(msg.sender, _amount-wdfee);
        }
        user.rewardDebt = user.amount.mul(pool.accVsnPerShare).div(1e12);
        if(pol!=address(0)){//trigger compounding on pol
            IPol(pol).earn();
        }
        emit Withdraw(msg.sender, _pid, _amount);
    }
    function withdrawFee(address _user,uint _pid) public view returns(uint){
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        if(user.lastDeposited+earlyFeePeriod>block.timestamp){
            return pool.withdrawFeeBP;
        }
        return 0;
    }
    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint _pid) external onlyEOA nonReentrant{
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if(pool.NFT){
            require(ERC721(NFT).ownerOf(user.nftId)==msg.sender);
            usedNFT[msg.sender][user.nftId]=false;
            user.nftId=0;
        }
        uint amount = user.amount;
        if(amount>0){
            Strat(pool.strat).withdraw(pool.stratId,amount);
            uint feeBP=withdrawFee(msg.sender,_pid);
            uint wdfee=amount.mul(feeBP).div(10000);
            if(wdfee>0){
                pool.lpToken.safeTransfer(feeAddress, wdfee);
            }
            pool.lpToken.safeTransfer(msg.sender,amount-wdfee);
            pool.totalcap=pool.totalcap.sub(amount);
            user.amount=0;
            user.rewardDebt=0;
        }
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }
    function safeVsnTransfer(address _to, uint _amount) internal {
        uint vsnBal = vsn.balanceOf(address(this));
        if(_amount>0 || vsnBal>0){
            if (_amount > vsnBal) {
                vsn.transfer(_to, vsnBal);
                vsn.mint(_to,_amount.sub(vsnBal));
            } else {
                vsn.transfer(_to, _amount);
            }
        }
    }
    function dev(address _devaddr) external {
        require(msg.sender == devaddr && _devaddr!=address(0), "dev: wut?");
        devaddr = _devaddr;
    }
    function setFeeAddress(address _feeAddress) external{
        require(msg.sender == feeAddress && _feeAddress!=address(0), "setFeeAddress: FORBIDDEN");
        feeAddress = _feeAddress;
    }
    function setApprovedContract(address _contract) external onlyOwner {
        approvedContracts[_contract] = true;
    }
    function updateEmissionRate(uint _vsnPerSec) external onlyOwner {
        require(_vsnPerSec<1 ether,"too large");
        massUpdatePools();
        vsnPerSec = _vsnPerSec;
    }
}
