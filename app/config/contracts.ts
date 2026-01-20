/**
 * Contract Addresses - Base Sepolia Testnet
 * Deployed: 2026-01-20
 */

export const CONTRACTS = {
  // Base Sepolia (Chain ID: 84532)
  baseSepolia: {
    chainId: 84532,
    kledToken: "0x04D672fc9C7F81dAE734d296Ee5F63F8a9273B52" as `0x${string}`,
    streetGovernor: "0xAdf51300dE1608Fb52c1bb3CDDfD0383A530Fd44" as `0x${string}`,
    editSuggestions: "0xFE5433d425Ec31d2Bb110bC05F33AfDad9f442cE" as `0x${string}`,
    // Futarchy contracts - redeployed 2026-01-20 (with setMarketDuration)
    conditionalTokens: "0x9F368E121d91e40e647C6173d17839DCB9D1Bb54" as `0x${string}`,
    futarchyAMM: "0xad4Aa33f1B2d7e39f7eF728d1F02E947431adEb6" as `0x${string}`,
    futarchyTreasury: "0x2ED53da92230dE3E2215CfDe8Ae49AB53511b058" as `0x${string}`,
  },
} as const;

// Current active network
export const ACTIVE_NETWORK = "baseSepolia" as const;

// Helper to get current contracts
export const getContracts = () => CONTRACTS[ACTIVE_NETWORK];

// Contract ABIs (minimal for frontend)
export const KLED_TOKEN_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function getVotes(address) view returns (uint256)",
  "function delegates(address) view returns (address)",
  "function delegate(address)",
  "function approve(address,uint256) returns (bool)",
  "function allowance(address,address) view returns (uint256)",
  "function transfer(address,uint256) returns (bool)",
  "event Transfer(address indexed from, address indexed to, uint256 value)",
  "event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate)",
] as const;

export const STREET_GOVERNOR_ABI = [
  "function propose(string,string) returns (uint256)",
  "function vote(uint256,uint8)",
  "function execute(uint256)",
  "function cancel(uint256)",
  "function claimStake(uint256)",
  "function getProposal(uint256) view returns (tuple(uint256 id, address proposer, string title, string description, uint256 forVotes, uint256 againstVotes, uint256 abstainVotes, uint256 startTime, uint256 endTime, uint256 snapshotTime, uint256 stakeAmount, bool executed, bool canceled, bool stakeReturned))",
  "function proposalCount() view returns (uint256)",
  "function hasVoted(uint256,address) view returns (bool)",
  "function state(uint256) view returns (uint8)",
  "function PROPOSAL_STAKE() view returns (uint256)",
  "function VOTING_DELAY() view returns (uint256)",
  "function VOTING_PERIOD() view returns (uint256)",
  "function SLASH_PERCENT() view returns (uint256)",
  "event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string title, uint256 startTime, uint256 endTime)",
  "event VoteCast(uint256 indexed proposalId, address indexed voter, uint8 support, uint256 weight)",
  "event ProposalExecuted(uint256 indexed proposalId)",
  "event ProposalCanceled(uint256 indexed proposalId)",
  "event StakeSlashed(uint256 indexed proposalId, address indexed proposer, uint256 slashedAmount, uint256 returnedAmount)",
] as const;

export const EDIT_SUGGESTIONS_ABI = [
  "function proposeEdit(uint256,bytes32,string) returns (uint256)",
  "function voteOnSuggestion(uint256,bool)",
  "function getSuggestion(uint256) view returns (tuple(uint256 id, uint256 proposalId, address suggester, bytes32 originalHash, string proposedText, uint256 forVotes, uint256 againstVotes, uint256 editWindowEnd, uint256 voteWindowEnd, uint256 stakeAmount, bool resolved))",
  "function suggestionCount() view returns (uint256)",
  "function hasVotedOnSuggestion(uint256,address) view returns (bool)",
  "function EDIT_STAKE() view returns (uint256)",
  "function EDIT_WINDOW() view returns (uint256)",
  "function VOTE_WINDOW() view returns (uint256)",
  "event EditSuggested(uint256 indexed suggestionId, uint256 indexed proposalId, address indexed suggester, string proposedText)",
  "event SuggestionVoted(uint256 indexed suggestionId, address indexed voter, bool support, uint256 weight)",
] as const;

// Futarchy ABIs
export const FUTARCHY_TREASURY_ABI = [
  "function proposalCount() view returns (uint256)",
  "function getProposal(uint256) view returns (tuple(uint256 id, address proposer, string title, string description, uint256 amount, address recipient, address spendToken, bytes32 conditionId, bytes32 marketId, uint256 stakeAmount, uint256 marketEndTime, uint256 passPrice, uint256 failPrice, bool resolved, bool passed, bool executed, bool canceled))",
  "function getTreasuryBalance(address) view returns (uint256)",
  "function proposalStake() view returns (uint256)",
  "function marketDuration() view returns (uint256)",
  "function createProposal(string,string,uint256,address,address) returns (uint256)",
  "function resolveProposal(uint256)",
  "function executeProposal(uint256)",
  "function cancelProposal(uint256)",
  "function deposit(address,uint256)",
  "event TreasuryProposalCreated(uint256 indexed proposalId, address indexed proposer, string title, uint256 amount, address recipient, bytes32 marketId, uint256 marketEndTime)",
  "event TreasuryProposalResolved(uint256 indexed proposalId, bool passed, uint256 passMarketPrice, uint256 failMarketPrice)",
  "event TreasuryProposalExecuted(uint256 indexed proposalId, address recipient, uint256 amount)",
  "event TreasuryDeposit(address indexed depositor, address indexed token, uint256 amount)",
] as const;

export const FUTARCHY_AMM_ABI = [
  "function getPrice(bytes32,uint256) view returns (uint256)",
  "function getMarketInfo(bytes32) view returns (bytes32 conditionId, address collateralToken, uint256 funding, uint256 yesTokens, uint256 noTokens, uint256 endTime, uint256 fee, bool resolved, uint256 winningOutcome)",
  "function calcBuyAmount(bytes32,uint256,uint256) view returns (uint256)",
  "function calcSellReturn(bytes32,uint256,uint256) view returns (uint256)",
  "function buy(bytes32,uint256,uint256,uint256) returns (uint256)",
  "function sell(bytes32,uint256,uint256,uint256) returns (uint256)",
  "event Buy(bytes32 indexed marketId, address indexed buyer, uint256 outcomeIndex, uint256 investmentAmount, uint256 outcomeTokensBought)",
  "event Sell(bytes32 indexed marketId, address indexed seller, uint256 outcomeIndex, uint256 returnAmount, uint256 outcomeTokensSold)",
  "event MarketResolved(bytes32 indexed marketId, uint256 winningOutcome, uint256 yesPrice, uint256 noPrice)",
] as const;
