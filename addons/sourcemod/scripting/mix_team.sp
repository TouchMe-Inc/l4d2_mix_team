#pragma semicolon              1
#pragma newdecls               required

#include <sourcemod>
#include <sdktools>
#include <nativevotes_rework>
#include <colors>

#undef REQUIRE_PLUGIN
#include <readyup>
#include <left4dhooks>
#define REQUIRE_PLUGIN

#include "include/mix_team.inc"


public Plugin myinfo =
{
	name = "MixTeam",
	author = "TouchMe",
	description = "Adds an API for mix in versus mode",
	version = "build_0006",
	url = "https://github.com/TouchMe-Inc/l4d2_mix_team"
};


// Libs
#define LIB_READY               "readyup" 
#define LIB_DHOOK               "left4dhooks"

// Gamemode
#define GAMEMODE_VERSUS         "versus"
#define GAMEMODE_VERSUS_REALISM "mutation12"

// Forwards
#define FORWARD_DISPLAY_MSG     "GetVoteDisplayMessage"
#define FORWARD_IN_PROGRESS     "OnMixInProgress"
#define FORWARD_ON_MIX_FINISHED "OnMixSuccess"
#define FORWARD_ON_MIX_ABORTED  "OnMixFailed"

// Other
#define TRANSLATIONS            "mix_team.phrases"
#define VOTE_TIME               15

// Macros
#define IS_VALID_CLIENT(%1)     (%1 > 0 && %1 <= MaxClients)
#define IS_REAL_CLIENT(%1)      (IsClientInGame(%1) && !IsFakeClient(%1))

// Sugar
#define SetHumanSpec            L4D_SetHumanSpec
#define TakeOverBot             L4D_TakeOverBot


enum struct MixData {
	Handle plugin;
	char type[MIX_TYPE_SIZE];
	int minPlayers;
	int abortDelay;
}

methodmap MixList < Handle
{
	public MixList() {
		return view_as<MixList>(CreateArray(sizeof(MixData)));
	}

	public int Add(Handle hPlugin, const char[] sType, int iMinPlayers, int iAbortDelay)
	{
		MixData item;

		item.plugin = hPlugin;
		strcopy(item.type, sizeof(item.type), sType);
		item.minPlayers = iMinPlayers;
		item.abortDelay = iAbortDelay;

		return PushArrayArray(this, item);
	}

	public int FindByType(const char[] sType)
	{
		MixData tMixData;

		int iSize = GetArraySize(this);

		for (int iIndex = 0; iIndex < iSize; iIndex++)
		{
			GetArrayArray(this, iIndex, tMixData);

			if (StrEqual(tMixData.type, sType, false)) {
				return iIndex;
			}
		}

		return INVALID_INDEX;
	}

	public Handle GetPlugin(int iIndex)
	{
		MixData tMixData;
		GetArrayArray(this, iIndex, tMixData);

		return tMixData.plugin;
	}

	public void GetTypeByIndex(int iIndex, char[] sType, int iLen)
	{
		MixData tMixData;
		GetArrayArray(this, iIndex, tMixData);

		strcopy(sType, iLen, tMixData.type);
	}

	public int GetMinPlayers(int iIndex)
	{
		MixData tMixData;
		GetArrayArray(this, iIndex, tMixData);

		return tMixData.minPlayers;
	}

	public int AbortDelay(int iIndex)
	{
		MixData tMixData;
		GetArrayArray(this, iIndex, tMixData);

		return tMixData.abortDelay;
	}
}

MixList
	g_hMixList = null;

enum struct PlayerInfo {
	bool mixMember;
	int lastTeam;
}

PlayerInfo
	g_tPlayers[MAXPLAYERS + 1];

int
	g_iMixIndex = INVALID_INDEX,
	g_iState = STATE_NONE,
	g_iAbortDelay = 0;

bool
	g_bReadyUpAvailable = false,
	g_bDHookAvailable = false,
	g_bGamemodeAvailable = false,
	g_bRoundIsLive = false;

ConVar
	g_cvGameMode = null;

GlobalForward
	g_gfOnMixFinished = null,
	g_gfOnMixAborted = null;


/**
  * Global event. Called when all plugins loaded.
  */
public void OnAllPluginsLoaded()
{
	g_bReadyUpAvailable = LibraryExists(LIB_READY);
	g_bDHookAvailable = LibraryExists(LIB_DHOOK);
}

/**
  * Global event. Called when a library is removed.
  *
  * @param sName     Library name
  */
public void OnLibraryRemoved(const char[] sName) 
{
	if (StrEqual(sName, LIB_READY)) {
		g_bReadyUpAvailable = false;
	}

	if (StrEqual(sName, LIB_DHOOK)) {
		g_bDHookAvailable = false;
	}
}

/**
  * Global event. Called when a library is added.
  *
  * @param sName     Library name
  */
public void OnLibraryAdded(const char[] sName)
{
	if (StrEqual(sName, LIB_READY)) {
		g_bReadyUpAvailable = true;
	}

	if (StrEqual(sName, LIB_DHOOK)) {
		g_bDHookAvailable = true;
	}
}

/**
  * @requared readyup
  * Global event. Called when all players are ready.
  */
public void OnRoundIsLive() 
{
	if (IsMixInProgress()) 
	{
		CPrintToChatAll("%t", "LEFT_READYUP");
		AbortMix();
	}
}

/**
 * Called before OnPluginStart.
 *
 * @param myself            Handle to the plugin.
 * @param late              Whether or not the plugin was loaded "late" (after map load).
 * @param error             Error message buffer in case load failed.
 * @param err_max           Maximum number of characters for error message buffer.
 * @return                  APLRes_Success | APLRes_SilentFailure.
 */
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion engine = GetEngineVersion();

	if (engine != Engine_Left4Dead2)
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	CreateNative("Call_AbortMix", Native_AbortMix);
	CreateNative("Call_FinishMix", Native_FinishMix);
	CreateNative("AddMix", Native_AddMix);
	CreateNative("GetMixState", Native_GetMixState);
	CreateNative("GetMixIndex", Native_GetMixIndex);
	CreateNative("IsMixMember", Native_IsMixMember);
	CreateNative("GetLastTeam", Native_GetLastTeam);
	CreateNative("SetClientTeam", Native_SetClientTeam);

	RegPluginLibrary("mix_team");

	return APLRes_Success;
}

/**
 * Adds a mix to the system.
 * 
 * @param hPlugin           Handle to the plugin.
 * @param iParams           Number of parameters.
 * @return                  Return index.
 */
int Native_AddMix(Handle hPlugin, int iParams)
{
	if (iParams < 3) {
		ThrowNativeError(SP_ERROR_NATIVE, "Call native without required params");
	}

	char sType[MIX_TYPE_SIZE];

	if (GetNativeString(1, sType, sizeof(sType)) != SP_ERROR_NONE || IsEmptyString(sType)) {
		ThrowNativeError(SP_ERROR_NATIVE, "Incorrect type");
	}

	int iMinPlayers = GetNativeCell(2);
	int iMaxPlayers = (FindConVar("survivor_limit").IntValue * 2);

	if (iMinPlayers > iMaxPlayers) {
		ThrowNativeError(SP_ERROR_NATIVE, "Incorrect min players");
	}

	int iAbortDelay = GetNativeCell(3);

	if (iAbortDelay < 0) {
		ThrowNativeError(SP_ERROR_NATIVE, "Incorrect abort delay");
	}

	return g_hMixList.Add(hPlugin, sType, iMinPlayers, iAbortDelay);
}

/**
 * Returns the status of the mix.
 * 
 * @param hPlugin           Handle to the plugin.
 * @param iParams           Number of parameters.
 * @return                  Return g_iState.
 */
int Native_GetMixState(Handle hPlugin, int iParams) {
	return g_iState;
}

/**
 * Returns current Mix Index.
 * 
 * @param hPlugin           Handle to the plugin.
 * @param iParams           Number of parameters.
 * @return                  Return g_iMixIndex.
 */
int Native_GetMixIndex(Handle hPlugin, int iParams) {
	return g_iMixIndex;
}

/**
 * Forces the mix to stop.
 * 
 * @param hPlugin           Handle to the plugin.
 * @param iParams           Number of parameters.
 */
int Native_AbortMix(Handle hPlugin, int iParams)
{
	if (!IsMixInProgress()) {
		ThrowNativeError(SP_ERROR_NATIVE, "Call native without mix");
	}

	AbortMix();
	return 0;
}

/**
 * Forcibly ends the mix.
 * 
 * @param hPlugin           Handle to the plugin.
 * @param iParams           Number of parameters.
 */
int Native_FinishMix(Handle hPlugin, int iParams)
{
	if (!IsMixInProgress()) {
		ThrowNativeError(SP_ERROR_NATIVE, "Call native without mix");
	}

	FinishMix();
	return 0;
}

/**
 * Returns whether the player is a member of the mix.
 * 
 * @param hPlugin           Handle to the plugin.
 * @param iParams           Number of parameters.
 * @return                  Return true if member.
 */
int Native_IsMixMember(Handle hPlugin, int iParams)
{
	int iClient = GetNativeCell(1);

	return g_tPlayers[iClient].mixMember;
}

/**
 * Returns the team the player was on after voting for the mix.
 * 
 * @param hPlugin           Handle to the plugin.
 * @param iParams           Number of parameters.
 * @return                  Return client team berfore mix.
 */
int Native_GetLastTeam(Handle hPlugin, int iParams)
{
	int iClient = GetNativeCell(1);

	return g_tPlayers[iClient].lastTeam;
}

/**
 * Sets a command to a player.
 *
 * @param hPlugin           Handle to the plugin.
 * @param iParams           Number of parameters.
 * @return                  Return true if success.
 */
int Native_SetClientTeam(Handle hPlugin, int iParams)
{
	int iClient = GetNativeCell(1);
	int iTeam = GetNativeCell(2);

	return SetupClientTeam(iClient, iTeam);
}


/**
  * Called when the map starts loading.
  */
public void OnMapInit(const char[] sMapName) 
{
	g_bRoundIsLive = false;
	g_iState = STATE_NONE;
	g_iMixIndex = INVALID_INDEX;
	g_iAbortDelay = 0;

	for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
	{
		g_tPlayers[iPlayer].mixMember = false;
	}
}

/**
 * Loads dictionary files. On failure, stops the plugin execution.
 */
void InitTranslations()
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "translations/" ... TRANSLATIONS ... ".txt");

	if (FileExists(sPath)) {
		LoadTranslations(TRANSLATIONS);
	} else {
		SetFailState("Path %s not found", sPath);
	}
}

/**
 * Called when the plugin is fully initialized and all known external references are resolved.
 */
public void OnPluginStart()
{
	InitTranslations();
	InitCvars();
	InitEvents();
	InitCmds();
	InitForwards();

	g_hMixList = new MixList();
}

/**
 * Called when the plugin is about to be unloaded.
 */
public void OnPluginEnd()
{
	if (g_hMixList != null)
	{
		CloseHandle(g_hMixList);
		g_hMixList = null;
	}

	if (g_gfOnMixFinished != null)
	{
		CloseHandle(g_gfOnMixFinished);
		g_gfOnMixFinished = null;
	}

	if (g_gfOnMixAborted != null)
	{
		CloseHandle(g_gfOnMixAborted);
		g_gfOnMixAborted = null;
	}
}

/**
 * Initializing the necessary cvars.
 */
void InitCvars() {
	(g_cvGameMode = FindConVar("mp_gamemode")).AddChangeHook(OnGamemodeChanged);
}

/**
 * Called when a console variable value is changed.
 * 
 * @param convar            Ignored.
 * @param sOldGameMode      Ignored.
 * @param sNewGameMode      String containing new gamemode.
 */
public void OnGamemodeChanged(ConVar hConVar, const char[] sOldGameMode, const char[] sNewGameMode) {
	g_bGamemodeAvailable = IsVersusMode(sNewGameMode);
}

/**
 * Called when the map has loaded, servercfgfile (server.cfg) has been executed, and all
 * plugin configs are done executing. This will always be called once and only once per map.
 * It will be called after OnMapStart().
*/
public void OnConfigsExecuted()
{
	char sGameMode[16];
	GetConVarString(g_cvGameMode, sGameMode, sizeof(sGameMode));
	g_bGamemodeAvailable = IsVersusMode(sGameMode);
}

/**
 * Event interception initialization.
 */
void InitEvents() 
{
	HookEvent("versus_round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);

	HookEvent("player_team", Event_PlayerTeam);
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);
}

/**
 * Round start event.
 */
public Action Event_RoundStart(Event event, const char[] sName, bool bDontBroadcast)
{
	if (!g_bReadyUpAvailable)
	{
		g_bRoundIsLive = true;

		if (IsMixInProgress())
		{
			CPrintToChatAll("%t", "ROUND_LIVE");
			AbortMix();
		}
	}

	return Plugin_Continue;
}

/**
 * Round end event.
 */
public Action Event_RoundEnd(Event event, const char[] sName, bool bDontBroadcast)
{
	if (!g_bReadyUpAvailable) {
		g_bRoundIsLive = false;
	}

	return Plugin_Continue;
}

/**
 * Sends new players to the observer team.
 * Called before player change his team.
 */
public Action Event_PlayerTeam(Event event, char[] sName, bool bDontBroadcast)
{
	if (!IsMixInProgress()) {
		return Plugin_Continue;
	}

	int iClient = GetClientOfUserId(event.GetInt("userid"));

	if (!IS_VALID_CLIENT(iClient) || IsFakeClient(iClient) || g_tPlayers[iClient].mixMember) {
		return Plugin_Continue;
	}

	CreateTimer(1.0, Timer_MoveClientToSpec, iClient);

	return Plugin_Continue;
}

/**
 * Bot kill bug fix timer.
 */
public Action Timer_MoveClientToSpec(Handle hTimer, int iClient)
{
	if (IsClientInGame(iClient) && GetClientTeam(iClient) != TEAM_SPECTATOR) {
		SetupClientTeam(iClient, TEAM_SPECTATOR);
	}

	return Plugin_Stop;
}

/**
 * Interrupting the mix if its participant leaves the game.
 * Called before client disconnected.
 */
public Action Event_PlayerDisconnect(Event event, const char[] sName, bool bDontBroadcast)
{
	if (!IsMixInProgress()) {
		return Plugin_Continue;
	}

	int iClient = GetClientOfUserId(event.GetInt("userid"));

	if (!IS_VALID_CLIENT(iClient) || IsFakeClient(iClient) || !g_tPlayers[iClient].mixMember) {
		return Plugin_Continue;
	}

	CPrintToChatAll("%t", "CLIENT_LEAVE", iClient);
	AbortMix();

	return Plugin_Continue;
}

/**
 * Command interception initialization.
 */
void InitCmds()
{
	AddCommandListener(Listener_OnPlayerJoinTeam, "jointeam");
	RegConsoleCmd("sm_mix", Cmd_RunMix, "Start Team Mix Voting");
	RegConsoleCmd("sm_unmix", Cmd_AbortMix, "Cancel the current Mix");
	RegAdminCmd("sm_fmix", Cmd_ForceMix, ADMFLAG_BAN, "Run forced Mix");
}

/**
 * Blocking a team change if there is a mix of teams now.
 *
 * @param iClient           Client index.
 * @param sCmd              Ignored.
 * @param iArgs             Ignored.
 */
public Action Listener_OnPlayerJoinTeam(int iClient, const char[] sCmd, int iArgs)
{
	if (IsMixInProgress())
	{
		CPrintToChat(iClient, "%T", "CANT_CHANGE_TEAM", iClient);
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

/**
 * Action on command input at the start of the mix.
 *
 * @param iClient           Client index.
 * @param iArgs             Number of parameters.
 */
public Action Cmd_RunMix(int iClient, int iArgs)
{
	if (!g_bGamemodeAvailable || !IS_VALID_CLIENT(iClient) || IS_SPECTATOR(iClient)) {
		return Plugin_Continue;
	}

	if (InSecondHalfOfRound())
	{
		CReplyToCommand(iClient, "%T", "SECOND_HALF_OF_ROUND", iClient);
		return Plugin_Continue;
	}

	if (g_bReadyUpAvailable && !IsInReady())
	{
		CReplyToCommand(iClient, "%T", "LEFT_READYUP", iClient);
		return Plugin_Continue;
	} 

	if (!g_bReadyUpAvailable && g_bRoundIsLive) 
	{
		CReplyToCommand(iClient, "%T", "ROUND_LIVE", iClient);
		return Plugin_Continue;
	}

	if (IsMixInProgress()) 
	{
		CReplyToCommand(iClient, "%T", "ALREADY_IN_PROGRESS", iClient);
		return Plugin_Continue;
	}

	if (!iArgs)
	{
		CReplyToCommand(iClient, "%T", "NO_ARGUMENT", iClient);
		CPrintExampleArguments(iClient);
		return Plugin_Continue;
	}

	char sArg[32]; GetCmdArg(1, sArg, sizeof(sArg));

	int iMixIndex = g_hMixList.FindByType(sArg);

	if (iMixIndex == INVALID_INDEX)
	{
		CReplyToCommand(iClient, "%T", "BAD_ARGUMENT", iClient, sArg);
		CPrintExampleArguments(iClient);
		return Plugin_Continue;
	}

	int iMinPlayers = g_hMixList.GetMinPlayers(iMixIndex);
	int iTotalPlayers = GetPlayerCount();

	if (iTotalPlayers < iMinPlayers)
	{
		CReplyToCommand(iClient, "%T", "BAD_TEAM_SIZE", iClient, iMinPlayers);
		return Plugin_Continue;
	}

	g_iMixIndex = iMixIndex;
	RunVoteMix(iClient);

	return Plugin_Continue;
}

/**
 * Abort the mix before it's finished.
 *
 * @param iClient           Client index.
 * @param iArgs             Number of parameters.
 */
public Action Cmd_AbortMix(int iClient, int iArgs)
{
	if (!g_bGamemodeAvailable 
	|| !IS_VALID_CLIENT(iClient) 
	|| !g_tPlayers[iClient].mixMember
	|| g_iState != STATE_IN_PROGRESS) {
		return Plugin_Continue;
	}

	int iEndTime = g_iAbortDelay - GetTime();

	if (iEndTime <= 0)
	{
		AbortMix();
		CPrintToChatAll("%t", "CANCEL_MIX_SUCCESS", iClient);
	} 

	else {
		CReplyToCommand(iClient, "%T", "CANCEL_MIX_FAIL", iClient, iEndTime);
	}

	return Plugin_Continue;
}

/**
 * Action on command input at the start of the mix.
 *
 * @param iClient           Client index.
 * @param iArgs             Number of parameters.
 */
public Action Cmd_ForceMix(int iClient, int iArgs)
{	
	if (!g_bGamemodeAvailable || !IS_VALID_CLIENT(iClient)) {
		return Plugin_Continue;
	}

	if (InSecondHalfOfRound())
	{
		CReplyToCommand(iClient, "%T", "SECOND_HALF_OF_ROUND", iClient);
		return Plugin_Continue;
	}

	if (g_bReadyUpAvailable && !IsInReady())
	{
		CReplyToCommand(iClient, "%T", "LEFT_READYUP", iClient);
		return Plugin_Continue;
	} 
		
	if (!g_bReadyUpAvailable && g_bRoundIsLive) 
	{
		CReplyToCommand(iClient, "%T", "ROUND_LIVE", iClient);
		return Plugin_Continue;
	}

	if (IsMixInProgress()) 
	{
		CReplyToCommand(iClient, "%T", "ALREADY_IN_PROGRESS", iClient);
		return Plugin_Continue;
	}

	if (!iArgs)
	{
		CReplyToCommand(iClient, "%T", "NO_ARGUMENT", iClient);
		CPrintExampleArguments(iClient);
		return Plugin_Continue;
	}

	char sArg[32]; GetCmdArg(1, sArg, sizeof(sArg));

	int iMixIndex = g_hMixList.FindByType(sArg);

	if (iMixIndex == INVALID_INDEX)
	{
		CReplyToCommand(iClient, "%T", "BAD_ARGUMENT", iClient, sArg);
		CPrintExampleArguments(iClient);
		return Plugin_Continue;
	}

	int iMinPlayers = g_hMixList.GetMinPlayers(iMixIndex);
	int iTotalPlayers = GetPlayerCount();

	if (iTotalPlayers < iMinPlayers)
	{
		CReplyToCommand(iClient, "%T", "BAD_TEAM_SIZE", iClient, iMinPlayers);
		return Plugin_Continue;
	}

	g_iMixIndex = iMixIndex;
	RunMix();

	return Plugin_Continue;
}

/**
 * Initializing global forwards.
 */
void InitForwards() 
{
	g_gfOnMixFinished = new GlobalForward(FORWARD_ON_MIX_FINISHED, ET_Ignore, Param_String);
	g_gfOnMixAborted = new GlobalForward(FORWARD_ON_MIX_ABORTED, ET_Ignore, Param_String);
}

/**
 * Start voting.
 *
 * @param iClient           Client index.
 */
public void RunVoteMix(int iClient) 
{
	if (!NativeVotes_IsNewVoteAllowed())
	{
		CReplyToCommand(iClient, "%T", "VOTE_COULDOWN", iClient, NativeVotes_CheckVoteDelay());
		return;
	}

	g_iState = STATE_VOTING;

	int iTotalPlayers, iTeam;
	int[] iPlayers = new int[MaxClients];

	for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
	{
		g_tPlayers[iPlayer].mixMember = false;

		if (!IsClientInGame(iPlayer) || IsFakeClient(iPlayer)) {
			continue;
		}

		iTeam = GetClientTeam(iPlayer);

		if (iTeam == TEAM_INFECTED || iTeam == TEAM_SURVIVOR)
		{
			iPlayers[iTotalPlayers++] = iPlayer;
			g_tPlayers[iPlayer].mixMember = true;
			g_tPlayers[iPlayer].lastTeam = iTeam;
		}
	}

	NativeVote hVote = new NativeVote(HandlerVote, NativeVotesType_Custom_YesNo);
	hVote.Initiator = iClient;
	hVote.DisplayVote(iPlayers, iTotalPlayers, VOTE_TIME);
}

/**
 * Called when a vote action is completed.
 *
 * @param hVote             The vote being acted upon.
 * @param tAction           The action of the vote.
 * @param iParam1           First action parameter.
 * @param iParam2           Second action parameter.
 */
public Action HandlerVote(NativeVote hVote, VoteAction tAction, int iParam1, int iParam2)
{
	switch (tAction)
	{
		case VoteAction_Start:
		{
			if (g_bReadyUpAvailable) {
				ToggleReadyPanel(false);
			}
		}

		case VoteAction_Display:
		{
			Handle hPlugin = g_hMixList.GetPlugin(g_iMixIndex);
			Function hFunc = GetFunctionByName(hPlugin, FORWARD_DISPLAY_MSG);

			if (hFunc == INVALID_FUNCTION) {
				SetFailState("Failed to get the function id of " ... FORWARD_DISPLAY_MSG);
			}

			char sVoteDisplayMessage[DISPLAY_MSG_SIZE];

			// call FORWARD_DISPLAY_MSG
			Call_StartFunction(hPlugin, hFunc);
			Call_PushCell(iParam1);
			Call_PushStringEx(sVoteDisplayMessage, sizeof(sVoteDisplayMessage), SM_PARAM_STRING_COPY|SM_PARAM_STRING_UTF8, SM_PARAM_COPYBACK);
			Call_Finish();

			hVote.SetDetails(sVoteDisplayMessage);

			return Plugin_Changed;
		}

		case VoteAction_Cancel: {
			hVote.DisplayFail();
		}

		case VoteAction_Finish:
		{
			if (g_iState != STATE_VOTING
				|| (!g_bReadyUpAvailable && g_bRoundIsLive) 
				|| (g_bReadyUpAvailable && !IsInReady()))
			{
				hVote.DisplayFail();

				g_iState = STATE_NONE;
				g_iMixIndex = INVALID_INDEX;

				return Plugin_Continue;
			}

			if (iParam1 == NATIVEVOTES_VOTE_NO)
			{
				hVote.DisplayFail();

				g_iState = STATE_NONE;
				g_iMixIndex = INVALID_INDEX;
			}

			else
			{
				hVote.DisplayPass();

				RunMix();
			}
		}

		case VoteAction_End:
		{
			if (g_bReadyUpAvailable) {
				ToggleReadyPanel(true);
			}

			hVote.Close();
		}
	}

	return Plugin_Continue;
}

void RunMix()
{
	g_iState = STATE_IN_PROGRESS;
	g_iAbortDelay = GetTime() + g_hMixList.AbortDelay(g_iMixIndex);

	SetAllClientSpectator();

	CreateTimer(0.1, Timer_CallOnMixProgress);
}

public Action Timer_CallOnMixProgress(Handle hTimer)
{
	Handle hPlugin = g_hMixList.GetPlugin(g_iMixIndex);
	Function hFunc = GetFunctionByName(hPlugin, FORWARD_IN_PROGRESS);

	if (hFunc == INVALID_FUNCTION) {
		SetFailState("Failed to get the function id of " ... FORWARD_IN_PROGRESS);
	}

	Action aReturn = Plugin_Continue;

	// call FORWARD_IN_PROGRESS
	Call_StartFunction(hPlugin, hFunc);
	Call_Finish(aReturn);

	if (aReturn == Plugin_Continue) {
		FinishMix();
	}

	return Plugin_Stop;
}

/**
 * Initiation of the end of the command mix.
 */
void FinishMix()
{
	char sType[MIX_TYPE_SIZE];
	g_hMixList.GetTypeByIndex(g_iMixIndex, sType, MIX_TYPE_SIZE);

	Call_StartForward(g_gfOnMixFinished);
	Call_PushString(sType);
	Call_Finish();

	g_iState = STATE_NONE;
	g_iMixIndex = INVALID_INDEX;
}

/**
 * Interrupt if players are disconnected or the round has started.
 */
void AbortMix()
{
	RollbackPlayers();

	char sType[MIX_TYPE_SIZE];
	g_hMixList.GetTypeByIndex(g_iMixIndex, sType, MIX_TYPE_SIZE);

	Call_StartForward(g_gfOnMixAborted);
	Call_PushString(sType);
	Call_Finish();

	g_iState = STATE_NONE;
	g_iMixIndex = INVALID_INDEX;
}

/**
 * Checks if a mix is ​​currently running.
 *
 * @return                  Returns true if a mix is ​​currently.
 *                          in progress, otherwise false.
 */
bool IsMixInProgress() {
	return g_iState != STATE_NONE;
}

/**
 * Returns the number of players in the game.
 * 
 * @return                  Client count.
 */
int GetPlayerCount() 
{
	int iCount = 0;

	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IS_REAL_CLIENT(iClient) || IS_SPECTATOR(iClient)) {
			continue;
		}

		iCount++;
	}

	return iCount;
}

/**
 * Returns players to teams before the mix starts.
*/
void RollbackPlayers()
{
	SetAllClientSpectator();

	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IS_REAL_CLIENT(iClient) || !g_tPlayers[iClient].mixMember) {
			continue;
		}

		SetupClientTeam(iClient, g_tPlayers[iClient].lastTeam);
	}
}

/**
 * Sets everyone to spectator team.
 */
void SetAllClientSpectator()
{
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IS_REAL_CLIENT(iClient)) { 
			continue;
		}

		SetupClientTeam(iClient, TEAM_SPECTATOR);
	}
}

/**
 * Checks if a string is empty.
 */
bool IsEmptyString(const char[] sString)
{
	int iLen = strlen(sString);

	if (iLen == 0) {
		return true;
	}
	
	for (int i = 0; i < iLen; ++i)
	{
		if (IsCharSpace(sString[i]) || sString[i] == '\r' || sString[i] == '\n') {
			continue;
		}

		return false;
	}
	
	return true;
}

/**
 * Displays all types of mixes.
 */
void CPrintExampleArguments(int iClient)
{
	char sType[MIX_TYPE_SIZE];
	int iSize = GetArraySize(g_hMixList);

	for (int index = 0; index < iSize; index++)
	{
		g_hMixList.GetTypeByIndex(index, sType, sizeof(sType));
		CReplyToCommand(iClient, "%T", "ARGUMENT_EXAMPLE", iClient, sType);
	}
}

/**
 * Checks if the current round is the second.
 *
 * @return                  Returns true if is second round, otherwise false.
 */
bool InSecondHalfOfRound() {
	return view_as<bool>(GameRules_GetProp("m_bInSecondHalfOfRound"));
}

/**
 * Sets the client team.
 *
 * @param iClient           Client index.
 * @param iTeam             Client team.
 * @return                  Returns true if success.
 */
bool SetupClientTeam(int iClient, int iTeam)
{
	if (GetClientTeam(iClient) == iTeam) {
		return true;
	}

	if (iTeam == TEAM_INFECTED || iTeam == TEAM_SPECTATOR)
	{
		ChangeClientTeam(iClient, iTeam);
		return true;
	}

	int iBot = FindSurvivorBot();
	if (iTeam == TEAM_SURVIVOR && iBot != -1)
	{
		if (g_bDHookAvailable)
		{
			ChangeClientTeam(iClient, TEAM_NONE);
			SetHumanSpec(iBot, iClient);
			TakeOverBot(iClient);
		}

		else {
			CheatCommand(iClient, "sb_takecontrol");
		}

		return true;
	}

	return false;
}

/**
 * Hack to execute cheat commands.
 */
void CheatCommand(int iClient, const char[] sCmd, const char[] sArgs = "")
{
	int iFlags = GetCommandFlags(sCmd);
	SetCommandFlags(sCmd, iFlags & ~FCVAR_CHEAT);
	FakeClientCommand(iClient, "%s %s", sCmd, sArgs);
	SetCommandFlags(sCmd, iFlags);
}

/**
 * Finds a free bot.
 *
 * @return                  Bot index, otherwise -1.
 */
int FindSurvivorBot()
{
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient) || !IsFakeClient(iClient) || !IS_SURVIVOR(iClient)) {
			continue;
		}

		return iClient;
	}

	return -1;
}

/**
 * Is the game mode versus.
 *
 * @param sGameMode         A string containing the name of the game mode.
 *
 * @return                  Returns true if verus, otherwise false.
 */
bool IsVersusMode(const char[] sGameMode) {
	return (StrEqual(sGameMode, GAMEMODE_VERSUS, false) || StrEqual(sGameMode, GAMEMODE_VERSUS_REALISM, false));
}
