// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title  CharityFund
 * @author Your Name
 * @notice A transparent, on-chain charity fund where donors can contribute ETH
 *         to named causes. The fund manager releases donations in tranches
 *         only when a milestone IPFS proof is submitted. Donors can request
 *         a proportional refund if a milestone is missed.
 * @dev    Designed for real-world charitable use on EVM-compatible chains.
 */
contract CharityFund {

    // ─────────────────────────────────────────────
    //  TYPES
    // ─────────────────────────────────────────────

    enum MilestoneStatus { Pending, ProofSubmitted, Released, Expired }

    struct Milestone {
        string          description;       // What must be achieved
        uint256         releaseAmount;     // Wei released upon approval
        uint256         deadline;          // Unix timestamp
        MilestoneStatus status;
        string          proofIpfsHash;     // IPFS CID of evidence (photos, reports)
    }

    struct Campaign {
        address payable manager;
        string          name;
        string          description;       // Plain text or IPFS CID
        uint256         targetAmount;      // Fundraising goal (informational)
        uint256         totalRaised;       // Running total donated
        uint256         totalReleased;     // Cumulative disbursements
        bool            active;
        Milestone[]     milestones;
    }

    // ─────────────────────────────────────────────
    //  STATE
    // ─────────────────────────────────────────────

    uint256 public campaignCount;
    mapping(uint256 => Campaign) private _campaigns;

    /// @dev campaignId => donor => amount
    mapping(uint256 => mapping(address => uint256)) public donations;
    /// @dev campaignId => list of donors (for refund iteration)
    mapping(uint256 => address[]) private _donors;

    // ─────────────────────────────────────────────
    //  EVENTS
    // ─────────────────────────────────────────────

    event CampaignCreated(uint256 indexed id, address indexed manager, string name);
    event DonationReceived(uint256 indexed campaignId, address indexed donor, uint256 amount);
    event MilestoneProofSubmitted(uint256 indexed campaignId, uint256 milestoneIndex, string ipfsHash);
    event MilestoneReleased(uint256 indexed campaignId, uint256 milestoneIndex, uint256 amount);
    event MilestoneExpired(uint256 indexed campaignId, uint256 milestoneIndex);
    event RefundClaimed(uint256 indexed campaignId, address indexed donor, uint256 amount);
    event CampaignClosed(uint256 indexed id);

    // ─────────────────────────────────────────────
    //  ERRORS
    // ─────────────────────────────────────────────

    error Unauthorized();
    error CampaignInactive(uint256 id);
    error NoDonation();
    error MilestoneNotReady(uint256 index);
    error InsufficientBalance();
    error DeadlinePassed(uint256 milestoneIndex);
    error DeadlineNotPassed(uint256 milestoneIndex);
    error TransferFailed();
    error ZeroValue();
    error MilestoneAmountsMismatch();

    // ─────────────────────────────────────────────
    //  MODIFIERS
    // ─────────────────────────────────────────────

    modifier onlyManager(uint256 id) {
        if (msg.sender != _campaigns[id].manager) revert Unauthorized();
        _;
    }

    modifier campaignActive(uint256 id) {
        if (!_campaigns[id].active) revert CampaignInactive(id);
        _;
    }

    // ─────────────────────────────────────────────
    //  EXTERNAL FUNCTIONS
    // ─────────────────────────────────────────────

    /**
     * @notice Create a new charity campaign with milestone-based fund release.
     * @param  name                Human-readable campaign name.
     * @param  description         Description or IPFS CID.
     * @param  targetAmount        Fundraising goal in wei (informational only).
     * @param  milestoneDescs      Descriptions for each milestone.
     * @param  milestoneAmounts    ETH (wei) released per milestone. Must sum ≤ targetAmount.
     * @param  milestoneDeadlines  Unix timestamps, must be strictly increasing.
     * @return id                  Campaign identifier.
     */
    function createCampaign(
        string   calldata   name,
        string   calldata   description,
        uint256             targetAmount,
        string[] calldata   milestoneDescs,
        uint256[] calldata  milestoneAmounts,
        uint256[] calldata  milestoneDeadlines
    ) external returns (uint256 id) {
        require(milestoneDescs.length == milestoneAmounts.length, "Array mismatch");
        require(milestoneAmounts.length == milestoneDeadlines.length, "Array mismatch");
        require(milestoneDescs.length > 0, "No milestones");

        // Validate deadlines are increasing and in the future
        uint256 prev = block.timestamp;
        uint256 totalMilestoneAmt;
        for (uint256 i = 0; i < milestoneDeadlines.length; i++) {
            require(milestoneDeadlines[i] > prev, "Deadlines must increase");
            totalMilestoneAmt += milestoneAmounts[i];
            prev = milestoneDeadlines[i];
        }
        if (totalMilestoneAmt > targetAmount) revert MilestoneAmountsMismatch();

        id = campaignCount++;
        Campaign storage c = _campaigns[id];
        c.manager      = payable(msg.sender);
        c.name         = name;
        c.description  = description;
        c.targetAmount = targetAmount;
        c.active       = true;

        for (uint256 i = 0; i < milestoneDescs.length; i++) {
            c.milestones.push(Milestone({
                description:   milestoneDescs[i],
                releaseAmount: milestoneAmounts[i],
                deadline:      milestoneDeadlines[i],
                status:        MilestoneStatus.Pending,
                proofIpfsHash: ""
            }));
        }

        emit CampaignCreated(id, msg.sender, name);
    }

    /**
     * @notice Donate ETH to a campaign.
     * @param  campaignId Target campaign.
     */
    function donate(uint256 campaignId) external payable campaignActive(campaignId) {
        if (msg.value == 0) revert ZeroValue();

        Campaign storage c = _campaigns[campaignId];

        if (donations[campaignId][msg.sender] == 0) {
            _donors[campaignId].push(msg.sender);
        }
        donations[campaignId][msg.sender] += msg.value;
        c.totalRaised                     += msg.value;

        emit DonationReceived(campaignId, msg.sender, msg.value);
    }

    /**
     * @notice Manager submits IPFS proof for a milestone.
     * @param  campaignId      Campaign identifier.
     * @param  milestoneIndex  Which milestone (0-based).
     * @param  ipfsHash        IPFS CID of proof documents (photos, reports, receipts).
     */
    function submitMilestoneProof(
        uint256 campaignId,
        uint256 milestoneIndex,
        string calldata ipfsHash
    ) external onlyManager(campaignId) campaignActive(campaignId) {
        Milestone storage m = _campaigns[campaignId].milestones[milestoneIndex];

        if (m.status != MilestoneStatus.Pending)
            revert MilestoneNotReady(milestoneIndex);
        if (block.timestamp > m.deadline)
            revert DeadlinePassed(milestoneIndex);

        m.status        = MilestoneStatus.ProofSubmitted;
        m.proofIpfsHash = ipfsHash;

        emit MilestoneProofSubmitted(campaignId, milestoneIndex, ipfsHash);
    }

    /**
     * @notice After proof is submitted, manager releases the milestone funds.
     *         (In a production DAO, this would require a donor vote.)
     * @param  campaignId     Campaign identifier.
     * @param  milestoneIndex Which milestone to release.
     */
    function releaseMilestoneFunds(uint256 campaignId, uint256 milestoneIndex)
        external
        onlyManager(campaignId)
        campaignActive(campaignId)
    {
        Campaign storage c = _campaigns[campaignId];
        Milestone storage m = c.milestones[milestoneIndex];

        if (m.status != MilestoneStatus.ProofSubmitted)
            revert MilestoneNotReady(milestoneIndex);

        uint256 available = address(this).balance;
        if (m.releaseAmount > available) revert InsufficientBalance();

        m.status       = MilestoneStatus.Released;
        c.totalReleased += m.releaseAmount;

        _safeTransfer(c.manager, m.releaseAmount);

        emit MilestoneReleased(campaignId, milestoneIndex, m.releaseAmount);
    }

    /**
     * @notice Mark an expired milestone; enables refunds for that portion.
     * @param  campaignId     Campaign identifier.
     * @param  milestoneIndex Which milestone expired.
     */
    function markExpired(uint256 campaignId, uint256 milestoneIndex) external {
        Milestone storage m = _campaigns[campaignId].milestones[milestoneIndex];

        if (m.status != MilestoneStatus.Pending) revert MilestoneNotReady(milestoneIndex);
        if (block.timestamp <= m.deadline)       revert DeadlineNotPassed(milestoneIndex);

        m.status = MilestoneStatus.Expired;

        emit MilestoneExpired(campaignId, milestoneIndex);
    }

    /**
     * @notice Donor claims a proportional refund of unreleased funds.
     *         Available only when at least one milestone is expired.
     * @param  campaignId Campaign identifier.
     */
    function claimRefund(uint256 campaignId) external {
        Campaign storage c = _campaigns[campaignId];
        uint256 donated = donations[campaignId][msg.sender];
        if (donated == 0) revert NoDonation();

        // Require at least one expired milestone
        bool hasExpired;
        for (uint256 i = 0; i < c.milestones.length; i++) {
            if (c.milestones[i].status == MilestoneStatus.Expired) {
                hasExpired = true;
                break;
            }
        }
        require(hasExpired, "No expired milestones");

        // Proportional share of unreleased balance
        uint256 contractBalance = address(this).balance;
        uint256 refund = (donated * contractBalance) / c.totalRaised;

        // State before transfer (CEI)
        donations[campaignId][msg.sender] = 0;
        c.totalRaised -= donated;

        _safeTransfer(payable(msg.sender), refund);

        emit RefundClaimed(campaignId, msg.sender, refund);
    }

    /**
     * @notice Manager closes a completed campaign (no further donations accepted).
     * @param  campaignId Campaign identifier.
     */
    function closeCampaign(uint256 campaignId)
        external
        onlyManager(campaignId)
    {
        _campaigns[campaignId].active = false;
        emit CampaignClosed(campaignId);
    }

    // ─────────────────────────────────────────────
    //  VIEW FUNCTIONS
    // ─────────────────────────────────────────────

    /// @notice Returns campaign summary.
    function getCampaign(uint256 id)
        external view
        returns (
            address manager,
            string  memory name,
            string  memory description,
            uint256 targetAmount,
            uint256 totalRaised,
            uint256 totalReleased,
            bool    active,
            uint256 milestoneCount
        )
    {
        Campaign storage c = _campaigns[id];
        return (
            c.manager,
            c.name,
            c.description,
            c.targetAmount,
            c.totalRaised,
            c.totalReleased,
            c.active,
            c.milestones.length
        );
    }

    /// @notice Returns a specific milestone.
    function getMilestone(uint256 campaignId, uint256 index)
        external view
        returns (Milestone memory)
    {
        return _campaigns[campaignId].milestones[index];
    }

    /// @notice Returns all donors for a campaign.
    function getDonors(uint256 campaignId)
        external view
        returns (address[] memory)
    {
        return _donors[campaignId];
    }

    // ─────────────────────────────────────────────
    //  INTERNAL
    // ─────────────────────────────────────────────

    function _safeTransfer(address payable to, uint256 amount) internal {
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    receive() external payable {}
}
