#pragma semicolon              1
#pragma newdecls               required

#include <sourcemod>
#include <sdktools>
#include <nativevotes>
#include <colors>

#undef REQUIRE_PLUGIN
#include <readyup>
#define LIB_READY              "readyup" 

#include "include/mix_team.inc"


public Plugin myinfo =
{
	name = "MixTeam",
	author = "TouchMe",
	description = "Mixing players for versus mode",
	version = "2.0.1",
	url = "https://github.com/TouchMe-Inc/l4d2_mix_team"
};


#define TRANSLATIONS            "mix_team.phrases"

#define FORWARD_DISPLAY_MSG     "GetVoteDisplayMessage"
#define FORWARD_VOTEEND_MSG     "GetVoteEndMessage"
#define FORWARD_IN_PROGRESS     "OnMixInProgress"

#define TEAM_NONE               0
#define TEAM_SPECTATOR          1
#define TEAM_SURVIVOR           2
#define TEAM_INFECTED           3

#define VOTE_TIME               15

#define IS_VALID_CLIENT(%1)     (%1 > 0 && %1 <= MaxClients)
#define IS_REAL_CLIENT(%1)      (IsClientInGame(%1) && !IsFakeClient(%1))
#define IS_SPECTATOR(%1)        (GetClientTeam(%1) == TEAM_SPECTATOR)
#define IS_SURVIVOR(%1)         (GetClientTeam(%1) == TEAM_SURVIVOR)

enum struct TypeItem
{
	Handle plugin;
	char name[MIX_NAME_SIZE];
	int minPlayers;
	int timeout;
}

methodmap TypeList < ArrayList 
{
	public TypeList() {
		return view_as<TypeList>(new ArrayList(sizeof(TypeItem)));
	}

	public int Add(Handle hPlugin, const char[] sName, int iMinPlayers, int iTimeout)
	{
		if (hPlugin == null || IsEmptyString(sName, MIX_NAME_SIZE) || iMinPlayers > MaxClients || iTimeout < 0) {
			return -1;
		}

		TypeItem item;

		item.plugin = hPlugin;
		strcopy(item.name, sizeof(item.name), sName);
		item.minPlayers = iMinPlayers;
		item.timeout = iTimeout;
		
		return this.PushArray(item);
	}

	public int Find(const char[] sName)
	{
		TypeItem item;

		for (int index = 0; index < this.Length; index++)
		{
			this.GetArray(index, item);
			if (StrEqual(item.name, sName, false)) {
				return index;
			}
		}

		return -1;
	}

	public Handle GetPlugin(int index)
	{
		if (this.Length > index)
		{
			TypeItem item;
			this.GetArray(index, item);

			return item.plugin;
		}

		return null;
	}

	public void GetName(int index, char[] sName, int iLen)
	{
		if (this.Length > index)
		{
			TypeItem item;
			this.GetArray(index, item);

			strcopy(sName, iLen, item.name);
		}
	}

	public int GetMinPlayers(int index)
	{
		if (this.Length > index)
		{
			TypeItem item;
			this.GetArray(index, item);

			return item.minPlayers;
		}

		return 0;
	}

	public int GetTimeout(int index)
	{
		if (this.Length > index)
		{
			TypeItem item;
			this.GetArray(index, item);

			return item.timeout;
		}

		return 0;
	}
}

enum struct Players
{
	bool member;
	int team;
}

TypeList
	g_hTypeList = null;

Players 
	g_hPlayers[MAXPLAYERS + 1];

NativeVote
	g_hCurVote = null;

int
	g_iMixTimeout = 0,
	g_iMixState = STATE_NONE,
	g_iMixType = TYPE_NONE;

bool
	g_bReadyUpAvailable = false,
	g_bGamemodeAvailable = false,
	g_bRoundIsLive = false;

ConVar
	g_hGameMode = null;


/**
  * Global event. Called when all plugins loaded.
  *
  * @noreturn
  */
public void OnAllPluginsLoaded() {
	g_bReadyUpAvailable = LibraryExists(LIB_READY);
}

/**
  * Global event. Called when a library is removed.
  *
  * @param sName     Library name
  *
  * @noreturn
  */
public void OnLibraryRemoved(const char[] sName) 
{
	if (StrEqual(sName, LIB_READY)) {
		g_bReadyUpAvailable = false;
	}
}

/**
  * Global event. Called when a library is added.
  *
  * @param sName     Library name
  *
  * @noreturn
  */
public void OnLibraryAdded(const char[] sName)
{
	if (StrEqual(sName, LIB_READY)) {
		g_bReadyUpAvailable = true;
	}
}

/**
  * @requared readyup
  * Global event. Called when all players are ready.
  *
  * @noreturn
  */
public void OnRoundIsLive() 
{
	if (g_iMixState != STATE_NONE) {
		CancelMix();
	}

	g_bRoundIsLive = true;
}

/**
 * Called before OnPluginStart.
 * 
 * @param myself      Handle to the plugin
 * @param late        Whether or not the plugin was loaded "late" (after map load)
 * @param error       Error message buffer in case load failed
 * @param err_max     Maximum number of characters for error message buffer
 * @return            APLRes_Success | APLRes_SilentFailure 
 */
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion engine = GetEngineVersion();

	if (engine != Engine_Left4Dead2) {
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	InitNatives();
	RegPluginLibrary("mix_team");

	return APLRes_Success;
}

void InitNatives()
{
	CreateNative("AddMixType", Native_AddMixType);
	CreateNative("GetMixState", Native_GetMixState);
	CreateNative("GetMixType", Native_GetMixType);
	CreateNative("CallCancelMix", Native_CallCancelMix);
	CreateNative("CallEndMix", Native_CallEndMix);
	CreateNative("IsMixMember", Native_IsMixMember);
	CreateNative("GetLastTeam", Native_GetLastTeam);
}

/**
 * Native
 * 
 * @param hPlugin       Handle to the plugin
 * @param iParams       Number of parameters
 * @return              Return index or -1
 */
int Native_AddMixType(Handle hPlugin, int iParams)
{
	if (iParams < 3) {
		return -1;
	}

	char sName[MIX_NAME_SIZE];
	
	if (GetNativeString(1, sName, sizeof(sName)) == SP_ERROR_NONE)
	{
		int iMinPlayers = GetNativeCell(2);
		int iTimeout = GetNativeCell(3);

		return g_hTypeList.Add(hPlugin, sName, iMinPlayers, iTimeout);
	}

	return -1;
}

/**
 * Native
 * 
 * @param hPlugin       Handle to the plugin
 * @param iParams       Number of parameters
 * @return              Return g_iMixState
 */
int Native_GetMixState(Handle hPlugin, int iParams) {
	return g_iMixState;
}

/**
 * Native
 * 
 * @param hPlugin       Handle to the plugin
 * @param iParams       Number of parameters
 * @return              Return g_iMixType
 */
int Native_GetMixType(Handle hPlugin, int iParams) {
	return g_iMixType;
}

/**
 * Native
 * 
 * @param hPlugin       Handle to the plugin
 * @param iParams       Number of parameters
 * @return              Return 
 */
int Native_CallCancelMix(Handle hPlugin, int iParams)
{
	CancelMix();
	return 1;
}

/**
 * Native
 * 
 * @param hPlugin       Handle to the plugin
 * @param iParams       Number of parameters
 * @return              Return 
 */
int Native_CallEndMix(Handle hPlugin, int iParams)
{
	EndMix();
	return 1;
}

/**
 * Native
 * 
 * @param hPlugin       Handle to the plugin
 * @param iParams       Number of parameters
 * @return              Return 
 */
int Native_IsMixMember(Handle hPlugin, int iParams)
{
	int iClient = GetNativeCell(1);

	return g_hPlayers[iClient].member;
}

/**
 * Native
 * 
 * @param hPlugin       Handle to the plugin
 * @param iParams       Number of parameters
 * @return              Return 
 */
int Native_GetLastTeam(Handle hPlugin, int iParams)
{
	int iClient = GetNativeCell(1);

	return g_hPlayers[iClient].team;
}

/**
 * Fragment
 * 
 * @noreturn
 */
void CancelMix()
{
	EndMix();

	if (g_hCurVote != null) {
		g_hCurVote.Close(); 
	}

	RollbackPlayers();
}

/**
 * Fragment
 * 
 * @noreturn
 */
void EndMix()
{
	g_iMixState = STATE_NONE;
	g_iMixType = TYPE_NONE;
}

/**
 * Called when the plugin is fully initialized and all known external references are resolved.
 * 
 * @noreturn
 */
public void OnPluginStart()
{
	g_hTypeList = new TypeList();

	InitTranslations();
	InitCvars();
	InitCmds();
	InitEvents();
}

/**
 * Called when the plugin is about to be unloaded.
 *
 * @noreturn
*/
public void OnPluginEnd()
{
	if (g_hTypeList != null) {
		delete g_hTypeList;
	}
}

/**
 * Loads dictionary files. On failure, stops the plugin execution.
 * 
 * @noreturn
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
 * Initializing the necessary cvars.
 * 
 * @noreturn
 */
void InitCvars()
{
	g_hGameMode = FindConVar("mp_gamemode");
	g_hGameMode.AddChangeHook(OnGamemodeChanged);
}

/**
 * Called when a console variable value is changed.
 * 
 * @param convar       Handle to the convar that was changed
 * @param oldValue     String containing the value of the convar before it was changed
 * @param newValue     String containing the new value of the convar
 * @noreturn
 */
public void OnGamemodeChanged(ConVar convar, const char[] sOldGameMode, const char[] sNewGameMode) {
	CheckGameMode(sNewGameMode);
}

/**
 * Called when the map has loaded, servercfgfile (server.cfg) has been executed, and all plugin configs are done executing.
 * This will always be called once and only once per map. It will be called after OnMapStart().
 * 
 * @noreturn
*/
public void OnConfigsExecuted() 
{
	char sGameMode[16];
	GetConVarString(g_hGameMode, sGameMode, sizeof(sGameMode));
	CheckGameMode(sGameMode);
}

/**
 * Fragment.
 * 
 * @noreturn
 */
void CheckGameMode(const char[] sGameMode)
{
	if (!StrEqual(sGameMode, "versus", false) && !StrEqual(sGameMode, "mutation12", false)) {
		g_bGamemodeAvailable = false;
	} 
	
	else {
		g_bGamemodeAvailable = true;
	}
}

/**
 * Fragment
 * 
 * @noreturn
 */
void InitEvents() 
{
	HookEvent("versus_round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);

	HookEvent("player_team", Event_PlayerTeam);
}

/**
  * Round start event.
  *
  * @params  				see events.inc > HookEvent.
  *
  * @noreturn
  */
public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) 
{
	if (!g_bReadyUpAvailable)
	{
		g_bRoundIsLive = true;

		if (g_iMixState != STATE_NONE) {
			CancelMix();
		}
	}

	return Plugin_Continue;
}

/**
 * Round end event.
 */
public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) 
{
	if (g_bRoundIsLive) {
		g_bRoundIsLive = false;
	}
	
	return Plugin_Continue;
}

/**
 * Player change his team.
 */
public Action Event_PlayerTeam(Event event, char[] event_name, bool dontBroadcast)
{
	int iClient = GetClientOfUserId(event.GetInt("userid"));

	if (IS_REAL_CLIENT(iClient) && g_iMixState != STATE_NONE)
	{
		int iOldTeam = event.GetInt("oldteam");

		if (iOldTeam == TEAM_NONE)
		{
			SetClientTeam(iClient, TEAM_SPECTATOR);
			return Plugin_Continue;
		}

		int iNewTeam = event.GetInt("team");

		if (iNewTeam == TEAM_NONE && g_hPlayers[iClient].member)
		{
			CancelMix();
			CPrintToChatAll("%t", "CLIENT_LEAVE", iClient);
		}
	}

	return Plugin_Continue;
}

/**
 * Fragment
 * 
 * @noreturn
 */
void InitCmds() 
{
	AddCommandListener(Cmd_OnPlayerJoinTeam, "jointeam");
	RegConsoleCmd("sm_mix", Cmd_VoteMix, "Vote for a team mix.");
	RegConsoleCmd("sm_cancelmix", Cmd_CancelMix, "Interrupting the mix.");
	RegConsoleCmd("sm_unmix", Cmd_CancelMix, "Interrupting the mix.");
}

/**
 * Blocking a team change if there is a mix of teams now.
 * 
 * @param iClient     Client index
 * @param sCmd        No desc
 * @param iArgs       Number of parameters
 * @return            Plugin_Stop | Plugin_Continue
 */
public Action Cmd_OnPlayerJoinTeam(int iClient, const char[] sCmd, int iArgs)
{
	if (g_iMixState != STATE_NONE)
	{
		CPrintToChat(iClient, "%T", "CANT_CHANGE_TEAM", iClient);
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

/**
 * Action on command input at the start of the mix.
 * 
 * @param iClient     Client index
 * @param iArgs       Number of parameters
 * @return            Plugin_Handled | Plugin_Continue
 */
public Action Cmd_VoteMix(int iClient, int iArgs)
{	
	if (!g_bGamemodeAvailable || !IS_VALID_CLIENT(iClient) || IS_SPECTATOR(iClient)) {
		return Plugin_Handled;
	}

	if (g_bReadyUpAvailable && !IsInReady())
	{
		CPrintToChat(iClient, "%T", "LEFT_READYUP", iClient);

		return Plugin_Handled;
	} 
		
	else if (!g_bReadyUpAvailable && g_bRoundIsLive) 
	{
		CPrintToChat(iClient, "%T", "ROUND_LIVE", iClient);

		return Plugin_Handled;
	}

	if (!iArgs) 
	{
		CPrintToChat(iClient, "%T", "NO_ARGUMENT", iClient);
		CPrintExampleArguments(iClient);

		return Plugin_Handled;
	}

	if (g_iMixState != STATE_NONE) 
	{
		CPrintToChat(iClient, "%T", "ALREADY_IN_PROGRESS", iClient);

		return Plugin_Handled;
	}
	
	char sArg[32];
	GetCmdArg(1, sArg, sizeof(sArg));

	int iMixType = g_hTypeList.Find(sArg);

	if (iMixType == -1)
	{
		CPrintToChat(iClient, "%T", "BAD_ARGUMENT", iClient, sArg);
		CPrintExampleArguments(iClient);

		return Plugin_Handled;
	}

	int iMinPlayers = g_hTypeList.GetMinPlayers(iMixType);
	int iTotalPlayers = GetPlayerCount();

	if (iTotalPlayers < iMinPlayers)
	{
		CPrintToChat(iClient, "%T", "BAD_TEAM_SIZE", iClient, iMinPlayers);
		return Plugin_Handled;
	}

	StartVoteMix(iClient, iMixType);
	
	return Plugin_Continue;
}

/**
 * ...
 * 
 * @param iClient     Client index
 * @param iArgs       Number of parameters
 * @return            Plugin_Handled | Plugin_Continue
 */
public Action Cmd_CancelMix(int iClient, int iArgs)
{
	if (!g_bGamemodeAvailable || !IS_VALID_CLIENT(iClient) || !g_hPlayers[iClient].member) {
		return Plugin_Handled;
	}

	if (g_iMixState == STATE_NONE) {
		return Plugin_Handled;
	}

	int iEndTime = g_iMixTimeout - GetTime();

	if (iEndTime < 0)
	{
		CancelMix();
		CPrintToChatAll("%t", "CANCEL_MIX_SUCCESS", iClient);
	} 
	
	else {
		CPrintToChat(iClient, "%T", "CANCEL_MIX_FAIL", iClient, iEndTime);
	}

	return Plugin_Handled;
}

/**
 * Start voting.
 * 
 * @param iClient     Client index
 * @return            Return description
 */
public void StartVoteMix(int iClient, int iMixType) 
{
	if (!NativeVotes_IsVoteTypeSupported(NativeVotesType_Custom_YesNo))
	{
		CPrintToChat(iClient, "%T", "UNSUPPORTED", iClient);
		return;
	}

	if (!NativeVotes_IsNewVoteAllowed())
	{
		CPrintToChat(iClient, "%T", "VOTE_COULDOWN", iClient, NativeVotes_CheckVoteDelay());
		return;
	}

	if (g_bReadyUpAvailable) {
		ToggleReadyPanel(false);
	}

	int iTotalPlayers, iTeam;
	int[] iPlayers = new int[MaxClients];
	
	for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
	{
		if (!IsClientInGame(iPlayer) || IsFakeClient(iPlayer)) {
			continue;
		}

		iTeam = GetClientTeam(iPlayer);

		if (iTeam != TEAM_SPECTATOR)
		{
			iPlayers[iTotalPlayers++] = iPlayer;
			g_hPlayers[iPlayer].member = true;
			g_hPlayers[iPlayer].team = iTeam;
		}

		else {
			g_hPlayers[iPlayer].member = false;
		}
	}

	NativeVote hVote = new NativeVote(HandlerVote, NativeVotesType_Custom_YesNo, NATIVEVOTES_ACTIONS_DEFAULT|MenuAction_Display);
	hVote.Initiator = iClient;

	g_iMixState = STATE_VOTING;
	g_iMixType = iMixType;
	g_hCurVote = hVote;

	hVote.DisplayVote(iPlayers, iTotalPlayers, VOTE_TIME);
}

/**
  * Callback when voting is over and results are available.
  *
  * @param hVote 			Voting ID.
  * @param iAction 			Current action.
  * @param iParam1 		    Client index | Vote status.
  *
  * @noreturn
  */
public int HandlerVote(NativeVote hVote, MenuAction iAction, int iParam1, int iParam2)
{
	switch (iAction)
	{
		case MenuAction_End:
		{
			if (g_bReadyUpAvailable) {
				ToggleReadyPanel(true);
			}

			hVote.Close();
			g_hCurVote = null;
		}

		case MenuAction_Display:
		{
			char sVoteDisplayMessage[DISPLAY_MSG_SIZE];
			int iReturn;

			Handle hPlugin = g_hTypeList.GetPlugin(g_iMixType);
			Function hFunc = GetFunctionByName(hPlugin, FORWARD_DISPLAY_MSG);
		
			if (hFunc == INVALID_FUNCTION) {
				SetFailState("Failed to get the function id of " ... FORWARD_DISPLAY_MSG);
			}

			// call FORWARD_DISPLAY_MSG
			Call_StartFunction(hPlugin, hFunc);
			Call_PushCell(iParam1);
			Call_PushStringEx(sVoteDisplayMessage, sizeof(sVoteDisplayMessage), SM_PARAM_STRING_COPY|SM_PARAM_STRING_UTF8, SM_PARAM_COPYBACK);
			Call_Finish(iReturn);

			NativeVotes_RedrawVoteTitle(sVoteDisplayMessage);

			return view_as<int>(Plugin_Changed);
		}
		
		case MenuAction_VoteCancel:
		{
			if (iParam1 == VoteCancel_NoVotes) {
				hVote.DisplayFail(NativeVotesFail_NotEnoughVotes);
			}
			
			else {
				hVote.DisplayFail(NativeVotesFail_Generic);
			}
		}

		case MenuAction_VoteEnd:
		{
			if (iParam1 == NATIVEVOTES_VOTE_NO) {
				hVote.DisplayFail(NativeVotesFail_Loses);
			}

			else
			{
				char sVoteEndMsg[VOTEEND_MSG_SIZE];
				
				int iReturn;
				Function hFunc;
				Handle hPlugin = g_hTypeList.GetPlugin(g_iMixType);

				if ((hFunc = GetFunctionByName(hPlugin, FORWARD_VOTEEND_MSG)) == INVALID_FUNCTION) {
					SetFailState("Failed to get the function id of " ... FORWARD_VOTEEND_MSG);
				}

				for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
				{
					if (!IsClientInGame(iPlayer) || IsFakeClient(iPlayer) || IS_SPECTATOR(iPlayer)) {
						continue;
					}

					SetGlobalTransTarget(iPlayer);

					// call FORWARD_VOTEEND_MSG
					Call_StartFunction(hPlugin, hFunc);
					Call_PushCell(iPlayer);
					Call_PushStringEx(sVoteEndMsg, sizeof(sVoteEndMsg), SM_PARAM_STRING_COPY|SM_PARAM_STRING_UTF8, SM_PARAM_COPYBACK);
					Call_Finish(iReturn);
					
					hVote.DisplayPassCustomToOne(iPlayer, sVoteEndMsg);
				}

				g_iMixTimeout = GetTime() + g_hTypeList.GetTimeout(g_iMixType);
				g_iMixState = STATE_IN_PROGRESS;

				SetAllClientSpectator();

				if ((hFunc = GetFunctionByName(hPlugin, FORWARD_IN_PROGRESS)) == INVALID_FUNCTION) {
					SetFailState("Failed to get the function id of " ... FORWARD_IN_PROGRESS);
				}

				// call FORWARD_IN_PROGRESS
				Call_StartFunction(hPlugin, hFunc);
				Call_Finish(iReturn);
			}
		}
	}
	
	return 0;
}

/**
 * Returns the number of players in the game.
 * 
 * @return             Client count
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
 *
* @noreturn
*/
void RollbackPlayers()
{
	SetAllClientSpectator();

	for (int iClient = 1; iClient <= MaxClients; iClient++) 
	{
		if (!IS_REAL_CLIENT(iClient) || !g_hPlayers[iClient].member) {
			continue;
		}

		SetClientTeam(iClient, g_hPlayers[iClient].team);
	}
}

/**
 * Sets everyone to spectator team.
 * 
 * @noreturn
 */
void SetAllClientSpectator()
{
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IS_REAL_CLIENT(iClient)) { 
			continue;
		}

		SetClientTeam(iClient, TEAM_SPECTATOR);
	}
}

/**
 * Sets the client team.
 * 
 * @param iClient     Client index
 * @param iTeam       Param description
 * @return            true if success
 */
bool SetClientTeam(int iClient, int iTeam)
{
	if (!IS_VALID_CLIENT(iClient)) {
		return false;
	}

	if (GetClientTeam(iClient) == iTeam) {
		return true;
	}

	if (iTeam != TEAM_SURVIVOR) {
		ChangeClientTeam(iClient, iTeam);
		return true;
	}
	else if (FindSurvivorBot() > 0)
	{
		CheatCommand(iClient, "sb_takecontrol");
		return true;
	}

	return false;
}

/**
 * Hack to execute cheat commands.
 * 
 * @noreturn
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
 * @return     Bot index or -1
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
 * Checks if a string is empty.
 *
 * @return     true|false
*/
bool IsEmptyString(const char[] str, int maxlength)
{
	int len = strlen(str);
	if (len == 0)
		return true;
	
	if (len > maxlength)
		len = maxlength;
	
	for (int i = 0; i < len; ++i)
	{
		if (IsCharSpace(str[i]))
			continue;
		
		if (str[i] == '\r' || str[i] == '\n')
			continue;
		
		return false;
	}
	
	return true;
}

/**
 * Displays all types of mixes.
 *
 * @noreturn
*/
void CPrintExampleArguments(int iClient)
{
	char sMixName[MIX_NAME_SIZE];
	for (int index = 0; index < g_hTypeList.Length; index++)
	{
		g_hTypeList.GetName(index, sMixName, MIX_NAME_SIZE);
		CPrintToChat(iClient, "%T", "ARGUMENT_EXAMPLE", iClient, sMixName);
	}
}
