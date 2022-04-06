#include <sourcemod>
#include <sdktools>
#include <builtinvotes>
#include <colors>

#undef REQUIRE_PLUGIN
#include <readyup>
#define LIB_READY              "ready" 

#pragma semicolon              1
#pragma newdecls               required


public Plugin myinfo =
{
	name = "Mix Team",
	author = "TouchMe", // thx: Tabun [https://github.com/Tabbernaut/], Luckylock [https://github.com/LuckyServ/]
	description = "Mixing players for versus mode",
	version = "IN PROGRESS"
};


#define TIMER_VOTE_HIDE         15

#define TEAM_SPECTATOR          1
#define TEAM_SURVIVOR           2 
#define TEAM_INFECTED           3

#define IS_VALID_CLIENT(%1)     (%1 > 0 && %1 <= MaxClients)
#define IS_REAL_CLIENT(%1)      (IsClientInGame(%1) && !IsFakeClient(%1))
#define IS_SURVIVOR(%1)         (GetClientTeam(%1) == TEAM_SURVIVOR)
#define IS_INFECTED(%1)         (GetClientTeam(%1) == TEAM_INFECTED)
#define IS_SPECTATOR(%1)        (GetClientTeam(%1) == TEAM_SPECTATOR)

#define TYPE_NONE               0
#define TYPE_RANDOM             1
#define TYPE_CAPITAN            2

#define STATE_NONE              0
#define STATE_VOTING            1
#define STATE_RUNNING           2
#define STATE_FIRST_CAPITAN     3
#define STATE_SECOND_CAPITAN    4
#define STATE_PICK_TEAM_FIRST   5
#define STATE_PICK_TEAM_SECOND  6

#define STATUS_NONE             0
#define STATUS_FIRST_CAPITAN    1
#define STATUS_SECOND_CAPITAN   2

#define CHAT_ARG_RANDOM         "random"
#define CHAT_ARG_CAPITAN        "capitan"

#define MAX_MENU_TITLE_LENGTH   64
#define MAX_VOTE_MESSAGE_LENGTH 128
#define MAX_PLAYER_STEAMID_LENGTH 32


enum struct Players
{
	ArrayList steamId;
	ArrayList team;
	ArrayList status;
	ArrayList vote;
}

Players 
	g_hPlayers;

int 
	g_iPlayers = 0;

int
	g_iMixState = STATE_NONE,
	g_iMixType = TYPE_NONE;

bool
	g_bReadyUpAvailable = false,
	g_bRoundIsLive = false;

Menu
	g_hMenu = null;

Handle
	g_hVote = INVALID_HANDLE,
	g_hNextStepTimer = INVALID_HANDLE;

Handle
	g_hOnMixTeamStart = INVALID_HANDLE,
	g_hOnMixTeamEnd = INVALID_HANDLE;

ConVar
	g_hSurvivorLimit = null,
	g_hGameMode = null;

/**
 * Called when the plugin is fully initialized and all known external references are resolved.
 * 
 * @noreturn
 */
public void OnPluginStart()
{
	InitTranslations();
	InitPlayers();
	InitCmds();
	InitEvents();

	g_hSurvivorLimit = FindConVar("survivor_limit");
	g_hGameMode = FindConVar("mp_gamemode");
}

/**
 * Called before client disconnected.
 * 
 * @param iClient     Client index
 * @noreturn
 */
public void OnClientDisconnect(int iClient)
{
    if (IsMixTeam() && IsClientInPlayers(iClient) >= 0)
    {
		CPrintToChatAll("%t", "CHAT_CLIENT_LEAVE", iClient);

		CancelMixTeam();
    }
}

/**
 * Called when a client is entering the game.
 * 
 * @param iClient     Client index
 * @noreturn
 */
public void OnClientPutInServer(int iClient)
{
    if (IsMixTeam() && IS_REAL_CLIENT(iClient)) {
        SetClientTeam(iClient, TEAM_SPECTATOR);
    }
}

/**
 * Fragment
 * 
 * @noreturn
 */
void Run_OnMixTeamStart() 
{
	if (g_bReadyUpAvailable) {
		ToggleReadyPanel(false);
	}

	Forward_OnMixTeamStart();
}

/**
 * Fragment
 * 
 * @noreturn
 */
void CancelMixTeam()
{
	if (g_hNextStepTimer != INVALID_HANDLE) 
	{
		KillTimer(g_hNextStepTimer);
		g_hNextStepTimer = INVALID_HANDLE;
	}

	Run_OnMixTeamEnd();

	g_iMixState = STATE_NONE;

	g_hMenu.Cancel();
}

/**
 * Fragment
 * 
 * @noreturn
*/
void Run_OnMixTeamEnd()
{
	if (g_bReadyUpAvailable) {
		ToggleReadyPanel(true);
	}

	Forward_OnMixTeamEnd();
}

/**
 * Loads dictionary files. On failure, stops the plugin execution.
 * 
 * @noreturn
 */
void InitTranslations() 
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "translations/mix_team.phrases.txt");

	if (FileExists(sPath)) {
		LoadTranslations("mix_team.phrases");
	} else {
		SetFailState("Path %s not found", sPath);
	}
}

/**
 * Fragment
 * 
 * @noreturn
 */
void InitEvents() 
{
	HookEvent("player_left_start_area", Event_LeftStartArea, EventHookMode_PostNoCopy);
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
}

/**
 * Fragment
 * 
 * @noreturn
 */
void InitCmds() 
{
	AddCommandListener(Cmd_OnPlayerJoinTeam, "jointeam");
	RegConsoleCmd("sm_mix", Cmd_MixTeam, "Vote for a team mix.");
}

/**
 * Description
 * 
 * @param convar       Handle to the convar that was changed
 * @param oldValue     String containing the value of the convar before it was changed
 * @param newValue     String containing the new value of the convar
 * @noreturn
 */
public void ConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	CheckGameMode();
}

/**
 * Called when the map has loaded, servercfgfile (server.cfg) has been executed, and all plugin configs are done executing.
 * This will always be called once and only once per map. It will be called after OnMapStart().
 * 
 * @noreturn
*/
public void OnConfigsExecuted() {
	CheckGameMode();
}

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
	if (IsMixTeam()) {
		CancelMixTeam();
	}
}

/**
 * Out of safe zone event.
 */
public Action Event_LeftStartArea(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bReadyUpAvailable) 
	{
		g_bRoundIsLive = true;
 
		if (IsMixTeam()) {
			CancelMixTeam();
		}
	}	
}

/**
 * Round start event.
 */
public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bReadyUpAvailable) {
		g_bRoundIsLive = false;
	}
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
	if (IsMixTeam())
	{
		CPrintToChat(iClient, "%t", "CHAT_CANT_CHAGNE_TEAM");

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
public Action Cmd_MixTeam(int iClient, int iArgs) 
{	
	if (!IS_VALID_CLIENT(iClient) || IS_SPECTATOR(iClient)) {
		return Plugin_Handled;
	}

	if (iArgs > 0) 
	{
		// is a new vote allowed?
		if (!IsNewBuiltinVoteAllowed()) {
			CPrintToChat(iClient, "%t", "CHAT_COULDOWN", CheckBuiltinVoteDelay());
			return Plugin_Handled;
		}

		if (g_bReadyUpAvailable) {
			if (!IsInReady()) {
				CPrintToChat(iClient, "%t", "CHAT_LEFT_READYUP");
				return Plugin_Handled;
			}
		} else {
			if (g_bRoundIsLive) {
				CPrintToChat(iClient, "%t", "CHAT_ROUND_LIVE");
				return Plugin_Handled;
			}
		}
		
		if (IsMixTeam()) {
			CPrintToChat(iClient, "%t", "CHAT_ALREADY_MIX_TEAM");
			return Plugin_Handled;
		}

		char sArg[32];
		GetCmdArg(1, sArg, sizeof(sArg));
		
		int iTotal = GetInGameClientCount();
		int iTeamSize = GetConVarInt(g_hSurvivorLimit);

		if (StrEqual(sArg, CHAT_ARG_RANDOM)) 
		{
			if (iTotal < iTeamSize) 
			{
				CPrintToChat(iClient, "%t", "CHAT_BAD_TEAM_SIZE");
				return Plugin_Continue;
			}

			g_iMixType = TYPE_RANDOM;
		} 
		else if (StrEqual(sArg, CHAT_ARG_CAPITAN)) 
		{
			if (iTotal < (2 * iTeamSize)) 
			{
				CPrintToChat(iClient, "%t", "CHAT_BAD_TEAM_SIZE");
				return Plugin_Continue;
			}

			g_iMixType = TYPE_CAPITAN;
		} else {
			CPrintToChat(iClient, "%t", "CHAT_BAD_ARGUMENT", sArg);
			return Plugin_Continue;
		}

		StartVote(iClient);

		return Plugin_Handled;
	}
	
	CPrintToChat(iClient, "%t", "CHAT_NO_ARGUMENT");

	return Plugin_Continue; 
}

/**
 * Start voting.
 * 
 * @param iClient     Client index
 * @return            Return description
 */
public void StartVote(int iClient) 
{
	// get all non-spectating players
	int iNumPlayers;
	int[] iPlayers = new int[MaxClients];

	for (int i = 1; i <= MaxClients; i++) 
	{
		if (!IS_REAL_CLIENT(i) || IS_SPECTATOR(i)) {
			continue;
		}

		iPlayers[iNumPlayers++] = i;
	}

	// create vote
	g_hVote = CreateBuiltinVote(HandleActionVote, BuiltinVoteType_Custom_YesNo, BuiltinVoteAction_Cancel | BuiltinVoteAction_VoteEnd | BuiltinVoteAction_End);
	SetBuiltinVoteInitiator(g_hVote, iClient);
	SetBuiltinVoteResultCallback(g_hVote, HandleVoteResult);

	char sVoteTitle[MAX_VOTE_MESSAGE_LENGTH];
	if (g_iMixType == TYPE_RANDOM) {
		Format(sVoteTitle, MAX_VOTE_MESSAGE_LENGTH, "%t", "VOTE_TITLE_RANDOM");
	} else if (g_iMixType == TYPE_CAPITAN) {
		Format(sVoteTitle, MAX_VOTE_MESSAGE_LENGTH, "%t", "VOTE_TITLE_CAPITAN");
	}
	
	SetBuiltinVoteArgument(g_hVote, sVoteTitle);

	// show vote
	DisplayBuiltinVote(g_hVote, iPlayers, iNumPlayers, TIMER_VOTE_HIDE);
	FakeClientCommand(iClient, "Vote Yes");

	g_iMixState = STATE_VOTING;
}

/**
 * ???
 * 
 * @param hVote       Voting ID.
 * @param iAction     BuiltinVoteAction_End, BuiltinVoteAction_Cancel
 * @param iParam1     Client index
 * @param iParam2     No desc
 * @noreturn
 */
public void HandleActionVote(Handle hVote, BuiltinVoteAction iAction, int iParam1, int iParam2)
{
	switch (iAction) {
		case BuiltinVoteAction_End: {
			delete hVote;
			g_hVote = null;
		}
		case BuiltinVoteAction_Cancel: {
			DisplayBuiltinVoteFail(hVote, view_as<BuiltinVoteFailReason>(iParam1));
		}
	}
}

/**
 * Callback when voting is over and results are available.
 * 
 * @param hVote           Voting ID.
 * @param iVotes          Total votes counted.
 * @param num_clients     Param description
 * @param num_items       Param description
 * @param iItemsInfo      Array of elements sorted by count
 * @return                Return description
 */
public void HandleVoteResult(Handle hVote, int iVotes, int num_clients, const int[][] client_info, int num_items, const int[][] iItemsInfo)
{
	if (iItemsInfo[0][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES && iItemsInfo[0][BUILTINVOTEINFO_ITEM_VOTES] > (iVotes / 2)) 
	{
		if (g_bRoundIsLive || g_bReadyUpAvailable && !IsInReady()) {
			DisplayBuiltinVoteFail(hVote, BuiltinVoteFail_Loses);
			return;
		}

		char sVoteMsg[MAX_VOTE_MESSAGE_LENGTH];
		if (g_iMixType == TYPE_RANDOM) {
			Format(sVoteMsg, sizeof(sVoteMsg), "%t", "VOTE_PASS_RANDOM");
		} else if (g_iMixType == TYPE_CAPITAN) {
			Format(sVoteMsg, sizeof(sVoteMsg), "%t", "VOTE_PASS_CAPITAN");
		}

		DisplayBuiltinVotePass(hVote, sVoteMsg);

		if (g_iMixType == TYPE_RANDOM) {
			RunRandomMix();
		} else if (g_iMixType == TYPE_CAPITAN) {
			RunCapitanMix();
		}

		return;
	}

	// vote Failed
	DisplayBuiltinVoteFail(hVote, BuiltinVoteFail_Loses);
	return;
}

/**
 * Starting the mix.
 * 
 * @noreturn
 */
void RunRandomMix()
{
	g_iMixState = STATE_RUNNING;

	// save current player / team setup
	int g_iPreviousCount[4];
	int g_iPreviousTeams[4][MAXPLAYERS + 1];

	for (int iClient = 1, iTeam; iClient <= MaxClients; iClient++)
	{
		if (IS_REAL_CLIENT(iClient)) 
		{
			iTeam = GetClientTeam(iClient);
			g_iPreviousTeams[iTeam][g_iPreviousCount[iTeam]] = iClient;
			g_iPreviousCount[iTeam]++;
		}
	}

	// if there are uneven players, move one to the other
	int iTotal = g_iPreviousCount[TEAM_SURVIVOR] + g_iPreviousCount[TEAM_INFECTED];
	int iTeamSize = GetConVarInt(g_hSurvivorLimit);

	if (iTotal < iTeamSize) 
	{
		CPrintToChatAll("%t", "CHAT_BAD_TEAM_SIZE");
		g_iMixState = STATE_NONE;
	}

	if (iTotal < (2 * iTeamSize))
	{
		int tmpDif = g_iPreviousCount[TEAM_SURVIVOR] - g_iPreviousCount[TEAM_INFECTED];
		int iTeamA, iTeamB;

		while (tmpDif > 1 || tmpDif < -1) 
		{
			if (tmpDif > 1) {
				iTeamA = TEAM_SURVIVOR;
				iTeamB = TEAM_INFECTED;	
			}
			else if (tmpDif < -1) {
				iTeamA = TEAM_INFECTED;
				iTeamB = TEAM_SURVIVOR;	
			}

			g_iPreviousCount[iTeamA]--;
			g_iPreviousTeams[iTeamB][g_iPreviousCount[iTeamB]] = g_iPreviousTeams[iTeamA][g_iPreviousCount[iTeamA]];
			g_iPreviousCount[iTeamB]++;

			tmpDif = g_iPreviousCount[TEAM_SURVIVOR] - g_iPreviousCount[TEAM_INFECTED];
		}
	}

	// do shuffle: swap at least teamsize/2 rounded up players
	bool bShuffled[MAXPLAYERS + 1];
	int iShuffleCount = RoundToCeil(float(g_iPreviousCount[TEAM_INFECTED] > g_iPreviousCount[TEAM_SURVIVOR] ? g_iPreviousCount[TEAM_INFECTED] : g_iPreviousCount[TEAM_SURVIVOR]) / 2.0);

	int pickA, pickB;
	int spotA, spotB;

	for (int j = 0; j < iShuffleCount; j++ )
	{
		pickA = -1;
		pickB = -1;

		while (pickA == -1 || bShuffled[pickA]) {
			spotA = GetRandomInt(0, g_iPreviousCount[TEAM_SURVIVOR] - 1);
			pickA = g_iPreviousTeams[TEAM_SURVIVOR][spotA];
		}

		while (pickB == -1 || bShuffled[pickB]) {
			spotB = GetRandomInt(0, g_iPreviousCount[TEAM_INFECTED] - 1);
			pickB = g_iPreviousTeams[TEAM_INFECTED][spotB];
		}

		bShuffled[pickA] = true;
		bShuffled[pickB] = true;

		g_iPreviousTeams[TEAM_SURVIVOR][spotA] = pickB;
		g_iPreviousTeams[TEAM_INFECTED][spotB] = pickA;
	}

	// set all players to spec
	SetAllClientSpectator();

	// now place all the players in the teams according to previousteams (silly name now, but ok)
	for (int iTeam = TEAM_SURVIVOR, iClient; iTeam <= TEAM_INFECTED; iTeam++)
	{
		for (iClient = 0; iClient < g_iPreviousCount[iTeam]; iClient++)
		{
			SetClientTeam(g_iPreviousTeams[iTeam][iClient], iTeam);
		}
	}

	g_iMixState = STATE_NONE;
}

/**
 * Starting the mix.
 * 
 * @noreturn
 */
void RunCapitanMix()
{
	g_iMixState = STATE_RUNNING;

	int iTotal = GetInGameClientCount();
	int iTeamSize = GetConVarInt(g_hSurvivorLimit);

	if (iTotal < (2 * iTeamSize)) 
	{
		CPrintToChatAll("%t", "CHAT_BAD_TEAM_SIZE");
		g_iMixState = STATE_NONE;
		return;
	}

	ClearPlayers();

	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient) || IsFakeClient(iClient) || IS_SPECTATOR(iClient)) { 
			continue;
		}

		PushPlayer(iClient);
	}

	// set all players to spec
	SetAllClientSpectator();

	g_hNextStepTimer = CreateTimer(1.0, NextStepTimer); 
}

/**
  * Preparing menu.
  *
  * @noreturn
  */
public bool InitMenu()
{
	g_hMenu = new Menu(HandleClickMenu);

	if (!IsMixTeam()) {
		return false;
	}

	char sMenuTitle[MAX_MENU_TITLE_LENGTH];

	switch(g_iMixState)
	{
		case STATE_FIRST_CAPITAN: {
			Format(sMenuTitle, MAX_MENU_TITLE_LENGTH, "%t", "MENU_TITLE_FIRST_CAPITAN");
		}

		case STATE_SECOND_CAPITAN: {
			Format(sMenuTitle, MAX_MENU_TITLE_LENGTH, "%t", "MENU_TITLE_SECOND_CAPITAN");
		}

		case STATE_PICK_TEAM_FIRST, STATE_PICK_TEAM_SECOND: {
			Format(sMenuTitle, MAX_MENU_TITLE_LENGTH, "%t", "MENU_TITLE_PICK_TEAMS");
		}

		default: {
			CloseHandle(g_hMenu);
			return false;
		}
	}
	
	g_hMenu.SetTitle(sMenuTitle);
	g_hMenu.ExitButton = false;

	return true;
}

/**
 * Adds players to the menu.
 * 
 * @return            Returns true if at least one is added, otherwise false
 */
bool AddMenuItems() 
{
	g_hMenu.RemoveAllItems();

	int iAdded = 0;
	char name[32];
	char steamId[32];

	for (int iClient = 1; iClient <= MaxClients; iClient++) 
	{
		if (IS_SPECTATOR(iClient) && IsClientInPlayers(iClient) >= 0) 
		{
			GetClientAuthId(iClient, AuthId_SteamID64, steamId, sizeof(steamId));
			GetClientName(iClient, name, sizeof(name));
			g_hMenu.AddItem(steamId, name);
			iAdded ++;
		}
	}

	return iAdded > 0;
}

/**
 * Shows a menu to all players on the spectator team.
 * 
 * @noreturn
 */
void ShowMenu()
{
	for (int iClient = 1; iClient <= MaxClients; iClient++) 
	{
		if (IS_SPECTATOR(iClient) && IsClientInPlayers(iClient) >= 0) {
			g_hMenu.Display(iClient, 10);
		}  
	}
}

/**
 * Menu item selection handler.
 * 
 * @param hMenu       Menu ID
 * @param iAction     Param description
 * @param iClient     Client index
 * @param iIndex      Item index
 * @return            Return description
 */
public int HandleClickMenu(Menu hMenu, MenuAction iAction, int iClient, int iIndex)
{
	char sSelectedSteamId[32];
	hMenu.GetItem(iIndex, sSelectedSteamId, sizeof(sSelectedSteamId));

	switch (iAction) {
		case MenuAction_Select: {
			switch(g_iMixState)
			{
				case STATE_FIRST_CAPITAN, STATE_SECOND_CAPITAN: {
					AddVotePlayer(IsSteamIdInPlayers(sSelectedSteamId));
				}

				case STATE_PICK_TEAM_FIRST, STATE_PICK_TEAM_SECOND: {
					SetClientTeam(GetClientBySteamId(sSelectedSteamId), g_iMixState == STATE_PICK_TEAM_FIRST ? TEAM_SURVIVOR : TEAM_INFECTED);
				}
			}
		}
	}

	return 0;
}

/**
 * Аive circles of hell.
 */
public Action NextStepTimer(Handle timer)
{
	switch(g_iMixState)
	{
		case STATE_RUNNING: 
		{
			Run_OnMixTeamStart();

			// current step
			g_iMixState = STATE_FIRST_CAPITAN;
			
			// clear players from voting
			ClearAllVotePlayers();

			// get first capitan
			if (InitMenu())
			{
				AddMenuItems();
				ShowMenu();
			}

			// go next step (wait 11 sec)!
			g_hNextStepTimer = CreateTimer(11.0, NextStepTimer); 
		}

		case STATE_FIRST_CAPITAN: 
		{
			// set first capitan
			int iFirstCapitan = GetMaxVotePlayer();
			SetPlayerStatus(iFirstCapitan, STATUS_FIRST_CAPITAN);
			SetClientTeam(iFirstCapitan, TEAM_SURVIVOR);

			// current step
			g_iMixState = STATE_SECOND_CAPITAN;
			
			// clear players from voting
			ClearAllVotePlayers();

			// get second capitan
			if (InitMenu())
			{
				AddMenuItems();
				ShowMenu();
			}

			// go next step (wait 11 sec)!
			g_hNextStepTimer = CreateTimer(11.0, NextStepTimer); 
		}

		case STATE_SECOND_CAPITAN: 
		{
			// set first capitan
			int iSecondCapitan = GetMaxVotePlayer();
			SetPlayerStatus(iSecondCapitan, STATUS_SECOND_CAPITAN);
			SetClientTeam(iSecondCapitan, TEAM_INFECTED);

			// current step
			g_iMixState = (GetURandomInt() & 1) ? STATE_PICK_TEAM_FIRST : STATE_PICK_TEAM_SECOND;

			// go next step (wait 1 sec)!
			g_hNextStepTimer = CreateTimer(1.0, NextStepTimer); 
		}

		case STATE_PICK_TEAM_FIRST, STATE_PICK_TEAM_SECOND: 
		{
			// get players for capitan
			if (InitMenu())
			{
				if (AddMenuItems()) 
				{
					int iCapitan = g_iMixState == STATE_PICK_TEAM_FIRST ? 
						FindClientByStatus(STATE_PICK_TEAM_FIRST) : FindClientByStatus(STATE_PICK_TEAM_SECOND);
					g_hMenu.Display(iCapitan, 1);
				} else {
					g_iMixState = STATE_NONE;
				}	
			}

			// rebuild menu (every second)
			g_hNextStepTimer = CreateTimer(1.0, NextStepTimer);
		}

		case STATE_NONE: {
			Run_OnMixTeamEnd();
		}
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
		int flags = GetCommandFlags("sb_takecontrol");
		SetCommandFlags("sb_takecontrol", flags &~FCVAR_CHEAT);
		FakeClientCommand(iClient, "sb_takecontrol");
		SetCommandFlags("sb_takecontrol", flags);
		return true;
	}

	return false;
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
		if (IsClientInGame(iClient) && IsFakeClient(iClient) && IS_SURVIVOR(iClient))
		{
			return iClient;
		}
	}

	return -1;
}

/**
 * Sets everyone to spectator team.
 * 
 * @param iTeam     Param description
 * @noreturn
 */
void SetAllClientSpectator() 
{
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (IS_REAL_CLIENT(iClient)) { 
			SetClientTeam(iClient, TEAM_SPECTATOR);
		} 
	}
}

/**
 * Checks if the mix has started.
 * 
 * @return            Returns true if a mix is ​​currently taking place, otherwise false
 */
bool IsMixTeam() {
	return g_iMixState >= STATE_RUNNING;
}

/**
 * Checks if game mode is supported?
 * 
 * @noreturn
 */
void CheckGameMode() 
{
	char sGameMode[16];
	GetConVarString(g_hGameMode, sGameMode, sizeof(sGameMode));

	if (StrContains(sGameMode, "coop", false) != -1 || StrContains(sGameMode, "survival", false) != -1) {
		SetFailState("Mix does not support gamemode %s", sGameMode);
	}
}

/**
 * Create the array of players.
 * 
 * @noreturn
 */
void InitPlayers() 
{
	g_hPlayers.steamId = new ArrayList(ByteCountToCells(MAX_PLAYER_STEAMID_LENGTH));
	g_hPlayers.team = new ArrayList();
	g_hPlayers.status = new ArrayList();
	g_hPlayers.vote = new ArrayList();
}

/**
 * Clears the array of players.
 * 
 * @param iClient     Client index
 * @noreturn
 */
void ClearPlayers() 
{
	g_hPlayers.steamId.Clear();
	g_hPlayers.team.Clear();
	g_hPlayers.status.Clear();
	g_hPlayers.vote.Clear();
}

/**
 * Adds a player.
 * 
 * @param iClient     Client index
 * @noreturn
 */
void PushPlayer(int iClient) 
{
	char sSteamId[MAX_PLAYER_STEAMID_LENGTH];
	GetClientAuthId(iClient, AuthId_SteamID64, sSteamId, MAX_PLAYER_STEAMID_LENGTH);

	g_hPlayers.steamId.PushString(sSteamId);
	g_hPlayers.team.Push(GetClientTeam(iClient));
	g_hPlayers.status.Push(STATUS_NONE);
	g_hPlayers.vote.Push(0);

	g_iPlayers++;
}

/**
 * Finds player index by client index.
 * 
 * @param iClient     Client index
 * @return            Item index, otherwise -1
 */
int IsClientInPlayers(int iClient)
{
	char sSteamId[MAX_PLAYER_STEAMID_LENGTH];
	GetClientAuthId(iClient, AuthId_SteamID64, sSteamId, MAX_PLAYER_STEAMID_LENGTH);
	
	return IsSteamIdInPlayers(sSteamId);
}

/**
 * Finds player index by steamId.
 * 
 * @param iClient     Client index
 * @return            Item index, otherwise -1
 */
int IsSteamIdInPlayers(const char[] sSteamId)
{
	char sSteamIdTmp[MAX_PLAYER_STEAMID_LENGTH];

	for (int iIndex = 0; iIndex < g_iPlayers; iIndex++)
	{
		g_hPlayers.steamId.GetString(iIndex, sSteamIdTmp, MAX_PLAYER_STEAMID_LENGTH);

		if (StrEqual(sSteamIdTmp, sSteamId)) {
			return iIndex;
		}
	}
	
	return -1;
}

/**
 * Adds a vote for a player.
 * 
 * @param iIndex     Item index
 * @noreturn
 */
void AddVotePlayer(int iIndex)
{
	int vote = g_hPlayers.vote.Get(iIndex);
	g_hPlayers.vote.Set(iIndex, ++vote);
}

/**
 * Returns the index of the player with the most votes.
 * 
 * @return           Index with max vote
 */
int GetMaxVotePlayer()
{
	int iMaxVote = 0;
	int iMaxIndex = 0; 

	for (int iIndex = 0, vote; iIndex < g_iPlayers; iIndex++)
	{
		vote = g_hPlayers.vote.Get(iIndex);

		if (vote > iMaxVote) {
			iMaxVote = vote;
			iMaxIndex = iIndex;
		}
	}
	
	return iMaxIndex;
}

/**
 * Clears the vote for the player.
 * 
 * @param iIndex     Item index
 * @noreturn
 */
void ClearVotePlayer(int iIndex) {
	g_hPlayers.vote.Set(iIndex, 0);
}

/**
 * Sets the status of the captain.
 * 
 * @param iIndex      Item index
 * @param iStatus     Player status
 * @noreturn
 */
void SetPlayerStatus(int iIndex, int iStatus) {
	g_hPlayers.status.Set(iIndex, iStatus);
}

/**
 * Returns the index of a client with a given status.
 * 
 * @param iStatus     Player status
 * @return            Client index
 */
int FindClientByStatus(int iStatus)
{
	for (int iClient = 1, iIndex; iClient <= MaxClients; iClient++) 
	{
		if (!IS_REAL_CLIENT(iClient)) {
			continue;
		}

		iIndex = IsClientInPlayers(iClient);

		if (iIndex >= 0) 
		{
			if (g_hPlayers.status.Get(iIndex) == iStatus) {
				return iClient;
			}
		}
	}
	
	return -1;
}

/**
 * Resets voting results.
 * 
 * @param iClient     Client index
 * @noreturn
 */
void ClearAllVotePlayers()
{
	for (int iIndex = 0; iIndex < g_iPlayers; iIndex++)
	{
		ClearVotePlayer(iIndex);
	}
}

/**
 * Returns the number of players in the game.
 * 
 * @return     Client count
 */
int GetInGameClientCount() 
{
	int iCount = 0;

	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (IS_REAL_CLIENT(iClient) && !IS_SPECTATOR(iClient)) {
			iCount++;
		}
	}

	return iCount;
}

/**
 * Finds the index of a client by its steamId.
 * 
 * @param sSteamId     Client AuthId_SteamID64
 * @return             Client index or 0
 */
int GetClientBySteamId(const char[] sSteamId) 
{
	char sSteamIdTmp[MAX_PLAYER_STEAMID_LENGTH];

	for (int iClient = 1; iClient <= MaxClients; iClient++) 
	{
		GetClientAuthId(iClient, AuthId_SteamID64, sSteamIdTmp, MAX_PLAYER_STEAMID_LENGTH);
		if (StrEqual(sSteamIdTmp, sSteamId)) {
			return iClient;
		}  
	}

	return 0;
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

	CreateNative("IsMixTeam", Native_IsMixTeam);
	CreateNative("GetMixType", Native_GetMixType);

	g_hOnMixTeamStart = CreateGlobalForward("OnMixTeamStart", ET_Ignore);
	g_hOnMixTeamEnd = CreateGlobalForward("OnMixTeamEnd", ET_Ignore);

	RegPluginLibrary("mix_team");

	return APLRes_Success;
}

/**
 * Native
 * 
 * @param plugin        Handle to the plugin
 * @param numParams     Number of parameters
 * @return              Return IsMixTeam
 */
public int Native_IsMixTeam(Handle plugin, int numParams) {
	return IsMixTeam();
}

/**
 * Native
 * 
 * @param plugin        Handle to the plugin
 * @param numParams     Number of parameters
 * @return              Return g_iMixType
 */
public int Native_GetMixType(Handle plugin, int numParams) {
	return g_iMixType;
}

/**
 * Global forward that is called at the beginning of the mix.
 * 
 * @noreturn
 */
public void Forward_OnMixTeamStart() {
	Call_StartForward(g_hOnMixTeamStart);
	Call_Finish();
}

/**
 * Global forward that is called at the end of the mix.
 * 
 * @noreturn
 */
public void Forward_OnMixTeamEnd() {
	Call_StartForward(g_hOnMixTeamEnd);
	Call_Finish();
}
