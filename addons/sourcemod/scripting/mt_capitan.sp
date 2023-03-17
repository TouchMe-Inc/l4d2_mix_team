#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <colors>
#include <mix_team>


public Plugin myinfo = { 
	name = "MixTeamCapitan",
	author = "TouchMe",
	description = "Adds capitan mix",
	version = "2.0.1",
	url = "https://github.com/TouchMe-Inc/l4d2_mix_team"
};


#define TRANSLATIONS            "mt_capitan.phrases"

#define TEAM_SPECTATOR          1
#define TEAM_SURVIVOR           2
#define TEAM_INFECTED           3

#define MENU_TITTLE_SIZE        128

#define STEP_INIT               0
#define STEP_FIRST_CAPITAN      1
#define STEP_SECOND_CAPITAN     2
#define STEP_PICK_PLAYER        3

#define LAST_PICK               0
#define CURRENT_PICK            1

#define MIN_PLAYERS             4

// Macros
#define IS_REAL_CLIENT(%1)      (IsClientInGame(%1) && !IsFakeClient(%1))
#define IS_SPECTATOR(%1)        (GetClientTeam(%1) == TEAM_SPECTATOR)
#define IS_SURVIVOR(%1)         (GetClientTeam(%1) == TEAM_SURVIVOR)


int
	g_iFirstCapitan = 0,
	g_iSecondCapitan = 0,
	g_iVoteCount[MAXPLAYERS + 1] = {0, ...},
	g_iOrderPickPlayer = 0;

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
 * Called when the plugin is fully initialized and all known external references are resolved.
 * 
 * @noreturn
 */
public void OnPluginStart() {
	InitTranslations();
}

public void OnAllPluginsLoaded()
{
	int iCalcMinPlayers = (FindConVar("survivor_limit").IntValue * 2);
	
	// fix for 1v1
	AddMixType("capitan", (iCalcMinPlayers < MIN_PLAYERS) ? MIN_PLAYERS : iCalcMinPlayers, 60);
}

public void GetVoteDisplayMessage(int iClient, char[] sTitle) {
	Format(sTitle, DISPLAY_MSG_SIZE, "%T", "VOTE_DISPLAY_MSG", iClient);
}

public void GetVoteEndMessage(int iClient, char[] sMsg) {
	Format(sMsg, VOTEEND_MSG_SIZE, "%T", "VOTE_END_MSG", iClient);
}

/**
 * Starting the mix.
 * 
 * @noreturn
 */
public void OnMixInProgress() {
	Flow(STEP_INIT);
}

/**
  * Builder menu.
  *
  * @noreturn
  */
public Menu BuildMenu(int iClient, int iStep)
{
	Menu hMenu = new Menu(HandleMenu);

	char sMenuTitle[MENU_TITTLE_SIZE];

	switch(iStep)
	{
		case STEP_FIRST_CAPITAN: {
			Format(sMenuTitle, sizeof(sMenuTitle), "%t", "MENU_TITLE_FIRST_CAPITAN", iClient);
		}

		case STEP_SECOND_CAPITAN: {
			Format(sMenuTitle, sizeof(sMenuTitle), "%t", "MENU_TITLE_SECOND_CAPITAN", iClient);
		}

		case STEP_PICK_PLAYER: {
			Format(sMenuTitle, sizeof(sMenuTitle), "%t", "MENU_TITLE_PICK_TEAMS", iClient);
		}
	}
	
	hMenu.SetTitle(sMenuTitle);

	char sPlayerInfo[6];
	char sPlayerName[32];
	for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++) 
	{
		if (!IS_REAL_CLIENT(iPlayer) || !IS_SPECTATOR(iPlayer) || !IsMixMember(iPlayer)) {
			continue;
		}

		Format(sPlayerInfo, sizeof(sPlayerInfo), "%d %d", iStep, iPlayer);
		GetClientName(iPlayer, sPlayerName, sizeof(sPlayerName));
		
		hMenu.AddItem(sPlayerInfo, sPlayerName);
	}

	hMenu.ExitButton = false;

	return hMenu.ItemCount > 1 ? hMenu : null;
}

bool DisplayMenuAll(int iStep, int iTime) 
{
	Menu hMenu;

	for (int iClient = 1; iClient <= MaxClients; iClient++) 
	{
		if (!IS_REAL_CLIENT(iClient) || !IS_SPECTATOR(iClient) || !IsMixMember(iClient)) {
			continue;
		}

		if ((hMenu = BuildMenu(iClient, iStep)) == null) {
			return false;
		}

		DisplayMenu(hMenu, iClient, iTime);
	}

	return true;
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
public int HandleMenu(Menu hMenu, MenuAction iAction, int iClient, int iIndex)
{
	if (iAction == MenuAction_End) {
		delete hMenu;
	}

	else if (iAction == MenuAction_Select)
	{
		char sInfo[6];
		hMenu.GetItem(iIndex, sInfo, sizeof(sInfo));

		char sStep[2], sClient[3];
		BreakString(sInfo[BreakString(sInfo, sStep, sizeof(sStep))], sClient, sizeof(sClient));

		int iStep = StringToInt(sStep);
		int iTarget = StringToInt(sClient);

		switch(iStep)
		{
			case STEP_FIRST_CAPITAN, STEP_SECOND_CAPITAN: {
				g_iVoteCount[iTarget] ++;
			}

			case STEP_PICK_PLAYER: 
			{
				bool bIsOrderPickFirstCapitan = !(g_iOrderPickPlayer & 2);

				if (bIsOrderPickFirstCapitan && IsFirstCapitan(iClient))
				{
					SetClientTeamByCapitan(iTarget, TEAM_SURVIVOR);	
					CPrintToChatAll("%t", "PICK_TEAM", iClient, iTarget);

					g_iOrderPickPlayer++;
				}

				else if (!bIsOrderPickFirstCapitan && IsSecondCapitan(iClient))
				{
					SetClientTeamByCapitan(iTarget, TEAM_INFECTED);	
					CPrintToChatAll("%t", "PICK_TEAM", iClient, iTarget);

					g_iOrderPickPlayer++;
				}
			}
		}
	}

	return 0;
}

public void Flow(int iStep)
{
	switch(iStep)
	{
		case STEP_INIT:
		{
			g_iOrderPickPlayer = 1;

			PrepareVote();
			DisplayMenuAll(STEP_FIRST_CAPITAN, 10);

			CreateTimer(11.0, NextStepTimer, STEP_FIRST_CAPITAN);
		}

		case STEP_FIRST_CAPITAN: 
		{
			int iFirstCapitan = GetVoteWinner();

			SetFirstCapitan(iFirstCapitan);

			CPrintToChatAll("%t", "NEW_FIRST_CAPITAN", iFirstCapitan, g_iVoteCount[iFirstCapitan]);

			PrepareVote();

			CreateTimer(11.0, NextStepTimer, STEP_SECOND_CAPITAN);

			DisplayMenuAll(STEP_SECOND_CAPITAN, 10);
		}

		case STEP_SECOND_CAPITAN:
		{
			int iSecondCapitan = GetVoteWinner();

			SetSecondCapitan(iSecondCapitan);

			CPrintToChatAll("%t", "NEW_SECOND_CAPITAN", iSecondCapitan, g_iVoteCount[iSecondCapitan]);

			Flow(STEP_PICK_PLAYER);
		}

		case STEP_PICK_PLAYER: 
		{
			int iCapitan = (g_iOrderPickPlayer & 2) ? g_iSecondCapitan : g_iFirstCapitan;

			Menu hMenu = BuildMenu(iCapitan, iStep);

			if (hMenu == null)
			{
				// auto-pick last player
				for (int iClient = 1; iClient <= MaxClients; iClient++) 
				{
					if (!IS_REAL_CLIENT(iClient) || !IS_SPECTATOR(iClient) || !IsMixMember(iClient)) {
						continue;
					}

					(FindSurvivorBot() > 0) ? CheatCommand(iClient, "sb_takecontrol") : ChangeClientTeam(iClient, TEAM_INFECTED);	
					break;
				}

				CallEndMix(); // Required
			}

			else
			{
				CreateTimer(1.0, NextStepTimer, iStep);

				DisplayMenu(hMenu, iCapitan, 1);
			}
		}
	}
}

/**
 * Timer.
 */
public Action NextStepTimer(Handle hTimer, int iStep)
{
	if (GetMixState() != STATE_IN_PROGRESS) {
		return Plugin_Stop;
	}

	Flow(iStep);

	return Plugin_Stop;
}

/**
 * Resetting voting results.
 *
 * @noreturn
 */
void PrepareVote()
{
	for (int iClient = 1; iClient <= MaxClients; iClient++) 
	{
		g_iVoteCount[iClient] = 0;
	}
}

/**
 * Returns the index of the player with the most votes.
 *
 * @return            Winner index
 */
int GetVoteWinner()
{
	int iWinner = -1;

	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient) || !IS_SPECTATOR(iClient) || !IsMixMember(iClient)) {
			continue;
		}

		if (iWinner == -1) {
			iWinner = iClient;
		}

		else if (g_iVoteCount[iWinner] < g_iVoteCount[iClient]) {
			iWinner = iClient;
		}
	}

	return iWinner;
}

void SetFirstCapitan(int iClient) {
	CheatCommand((g_iFirstCapitan = iClient), "sb_takecontrol");
}

bool IsFirstCapitan(int iClient) {
	return g_iFirstCapitan == iClient;
}

void SetSecondCapitan(int iClient) {
	ChangeClientTeam((g_iSecondCapitan = iClient), TEAM_INFECTED);
}

bool IsSecondCapitan(int iClient) {
	return g_iSecondCapitan == iClient;
}

/**
 * Sets the client team by capitan.
 * 
 * @param iClient     Client index
 * @param iTeam       Param description
 * @noreturn
 */
void SetClientTeamByCapitan(int iClient, int iTeam)
{
	if (iTeam == TEAM_INFECTED) {
		ChangeClientTeam(iClient, TEAM_INFECTED);
	}
	
	else if (FindSurvivorBot() > 0) {
		CheatCommand(iClient, "sb_takecontrol");
	}
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
