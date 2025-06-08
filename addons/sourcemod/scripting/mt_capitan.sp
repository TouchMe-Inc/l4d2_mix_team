#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <mix_team>
#include <colors>


public Plugin myinfo = {
    name        = "MixTeamCapitan",
    author      = "TouchMe",
    description = "Adds capitan mix",
    version     = "build_0004",
    url         = "https://github.com/TouchMe-Inc/l4d2_mix_team"
};


#define TRANSLATIONS            "mt_capitan.phrases"

/**
 * Teams.
 */
#define TEAM_NONE               0
#define TEAM_SPECTATOR          1
#define TEAM_SURVIVOR           2
#define TEAM_INFECTED           3

/**
 * Mix flow staps.
 */
#define STEP_SELECTION_SURVIVOR_CAPTAIN 1
#define STEP_SET_SURVIVOR_CAPTAIN 2
#define STEP_SELECTION_INFECTED_CAPTAIN 3
#define STEP_SET_INFECTED_CAPTAIN 4
#define STEP_PICK_PLAYER 5

#define MIN_PLAYERS             6

#define CAPTAIN_SURVIVOR 0
#define CAPTAIN_INFECTED 1

int
    g_iFirstCapitan = 0,
    g_iSecondCapitan = 0,
    g_iVotesForCaptain[MAXPLAYERS + 1][2],
    g_iOrderPickPlayer = 0
;

int g_iThisMixIndex = -1;

ArrayList g_aPlayerPool = null;

/**
 * Called when the plugin is fully initialized
 * and all known external references are resolved.
 */
public void OnPluginStart()
{
    LoadTranslations(TRANSLATIONS);

    g_aPlayerPool = new ArrayList();
}

public void OnAllPluginsLoaded()
{
    int iCalcMinPlayers = (FindConVar("survivor_limit").IntValue * 2);
    g_iThisMixIndex = AddMix((iCalcMinPlayers < MIN_PLAYERS) ? MIN_PLAYERS : iCalcMinPlayers, 60);
}

public Action OnDrawVoteTitle(int iMixIndex, int iClient, char[] sTitle, int iLength)
{
    if (iMixIndex != g_iThisMixIndex) {
        return Plugin_Continue;
    }

    Format(sTitle, iLength, "%T", "VOTE_TITLE", iClient);

    return Plugin_Stop;
}

public Action OnDrawMenuItem(int iMixIndex, int iClient, char[] sTitle, int iLength)
{
    if (iMixIndex != g_iThisMixIndex) {
        return Plugin_Continue;
    }

    Format(sTitle, iLength, "%T", "MENU_ITEM", iClient);

    return Plugin_Stop;
}

/**
 * Starting the mix.
 */
public Action OnChangeMixState(int iMixIndex, MixState eOldState, MixState eNewState, bool bIsFail)
{
    if (iMixIndex != g_iThisMixIndex) {
        return Plugin_Continue;
    }

    if (eNewState == MixState_InProgress)
    {
        g_iOrderPickPlayer = 1;

        g_aPlayerPool.Clear();

        ResetVotesForCaptain();

        for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
        {
            if (!IsClientInGame(iPlayer) || !IsMixMember(iPlayer)) {
                continue;
            }

            g_aPlayerPool.Push(iPlayer);
        }

        Flow(STEP_SELECTION_SURVIVOR_CAPTAIN);

        return Plugin_Stop;
    }

    return Plugin_Continue;
}

void Flow(int iStep)
{
    if (GetMixState() != MixState_InProgress) {
        return;
    }

    switch (iStep)
    {
        case STEP_SELECTION_SURVIVOR_CAPTAIN:
        {
            ShowSelectionCaptainMenu(STEP_SELECTION_SURVIVOR_CAPTAIN, 10);
            FlowWithDelay(STEP_SET_SURVIVOR_CAPTAIN, 11.0);
        }

        case STEP_SET_SURVIVOR_CAPTAIN:
        {
            g_iFirstCapitan = GetMostVotes(CAPTAIN_SURVIVOR);

            g_aPlayerPool.Erase(g_aPlayerPool.FindValue(g_iFirstCapitan));

            SetClientTeam(g_iFirstCapitan, TEAM_SURVIVOR);

            CPrintToChatAll("%t", "SET_SURVIVOR_CAPTAIN", g_iFirstCapitan, g_iVotesForCaptain[g_iFirstCapitan]);

            Flow(STEP_SELECTION_INFECTED_CAPTAIN);
        }

        case STEP_SELECTION_INFECTED_CAPTAIN:
        {
            ShowSelectionCaptainMenu(STEP_SELECTION_INFECTED_CAPTAIN, 10);
            FlowWithDelay(STEP_SET_INFECTED_CAPTAIN, 11.0);
        }

        case STEP_SET_INFECTED_CAPTAIN:
        {
            g_iSecondCapitan = GetMostVotes(CAPTAIN_INFECTED);

            g_aPlayerPool.Erase(g_aPlayerPool.FindValue(g_iSecondCapitan));

            SetClientTeam(g_iSecondCapitan, TEAM_INFECTED);

            CPrintToChatAll("%t", "SET_INFECTED_CAPTAIN", g_iSecondCapitan, g_iVotesForCaptain[g_iSecondCapitan]);

            Flow(STEP_PICK_PLAYER);
        }

        case STEP_PICK_PLAYER:
        {
            int iCaptain = (g_iOrderPickPlayer & 2) ? g_iSecondCapitan : g_iFirstCapitan;

            Menu hMenu = null;

            int iSize = g_aPlayerPool.Length;

            if (iSize > 1)
            {
                BuildPickPlayersMenu(hMenu, iCaptain);
                DisplayMenu(hMenu, iCaptain, 1);
                FlowWithDelay(STEP_PICK_PLAYER, 1.0);
            }

            else
            {
                int iPlayer = g_aPlayerPool.Get(0);

                SetClientTeam(iPlayer, FindSurvivorBot() != -1 ? TEAM_SURVIVOR : TEAM_INFECTED);

                Call_FinishMix();
            }
        }
    }
}

void FlowWithDelay(int iStep, float fDelay)
{
    CreateTimer(fDelay, Timer_NextStep, iStep, .flags = TIMER_FLAG_NO_MAPCHANGE);
}

/**
  * Builder menu.
  */
void BuildSelectionCaptainMenu(Menu &hMenu, int iClient, int iCaptain)
{
    hMenu = CreateMenu(HandleSelectionCaptainMenu, MenuAction_Select|MenuAction_End);

    switch (iCaptain)
    {
        case CAPTAIN_SURVIVOR: hMenu.SetTitle("%T", "MENU_SURVIVOR_CAPTAIN_TITLE", iClient);
        case CAPTAIN_INFECTED: hMenu.SetTitle("%T", "MENU_INFECTED_CAPTAIN_TITLE", iClient);
    }

    int iSize = g_aPlayerPool.Length;
    char szPlayerInfo[6], szPlayerName[32];

    for (int i = 0; i < iSize; i++)
    {
        int iPlayer = g_aPlayerPool.Get(i);

        FormatEx(szPlayerInfo, sizeof(szPlayerInfo), "%d %d", iCaptain, iPlayer);
        GetClientName(iPlayer, szPlayerName, sizeof(szPlayerName));

        AddMenuItem(hMenu, szPlayerInfo, szPlayerName);
    }

    SetMenuExitButton(hMenu, false);
}

/**
 * Menu item selection handler.
 *
 * @param hMenu       Menu ID.
 * @param iAction     Param description.
 * @param iClient     Client index.
 * @param iIndex      Item index.
 */
public int HandleSelectionCaptainMenu(Menu hMenu, MenuAction iAction, int iClient, int iIndex)
{
    switch (iAction)
    {
        case MenuAction_End: delete hMenu;

        case MenuAction_Select:
        {
            char szInfo[6];
            hMenu.GetItem(iIndex, szInfo, sizeof(szInfo));

            char szCaptain[2], szClient[3];
            BreakString(szInfo[BreakString(szInfo, szCaptain, sizeof(szCaptain))], szClient, sizeof(szClient));

            int iTarget = StringToInt(szClient);
            int iCaptain = StringToInt(szCaptain);

            g_iVotesForCaptain[iTarget][iCaptain] ++;
        }
    }

    return 0;
}

/**
  * Builder menu.
  */
void BuildPickPlayersMenu(Menu &hMenu, int iClient)
{
    hMenu = CreateMenu(HandleickPlayersMenu, MenuAction_Select|MenuAction_End);

    hMenu.SetTitle("%T", "MENU_PICK_PLAYERS_TITLE", iClient);

    int iSize = g_aPlayerPool.Length;
    char szPlayerInfo[6], szPlayerName[32];

    for (int i = 0; i < iSize; i++)
    {
        int iPlayer = g_aPlayerPool.Get(i);

        FormatEx(szPlayerInfo, sizeof(szPlayerInfo), "%d", iPlayer);
        GetClientName(iPlayer, szPlayerName, sizeof(szPlayerName));

        AddMenuItem(hMenu, szPlayerInfo, szPlayerName);
    }

    SetMenuExitButton(hMenu, false);
}

/**
 * Menu item selection handler.
 *
 * @param hMenu       Menu ID.
 * @param iAction     Param description.
 * @param iClient     Client index.
 * @param iIndex      Item index.
 */
public int HandleickPlayersMenu(Menu hMenu, MenuAction iAction, int iClient, int iIndex)
{
    switch(iAction)
    {
        case MenuAction_End: delete hMenu;

        case MenuAction_Select:
        {
            char szInfo[6];
            hMenu.GetItem(iIndex, szInfo, sizeof(szInfo));

            char szStep[2], szClient[3];
            BreakString(szInfo[BreakString(szInfo, szStep, sizeof(szStep))], szClient, sizeof(szClient));

            int iTarget = StringToInt(szClient);

            int iPlayerPoolIdx = g_aPlayerPool.FindValue(iTarget);

            switch (!(g_iOrderPickPlayer & 2) ? CAPTAIN_INFECTED : CAPTAIN_SURVIVOR)
            {
                case CAPTAIN_SURVIVOR:
                {
                    if (!IsSurvivorCapitan(iClient)) {
                        return 0;
                    }

                    if (iPlayerPoolIdx != -1) {
                        g_aPlayerPool.Erase(iIndex);
                    }

                    SetClientTeam(iTarget, TEAM_SURVIVOR);
                    CPrintToChatAll("%t", "PICK_SURVIVOR_TEAM", iClient, iTarget);

                    g_iOrderPickPlayer ++;
                }

                case CAPTAIN_INFECTED:
                {
                    if (!IsInfectedCapitan(iClient)) {
                        return 0;
                    }

                    if (iPlayerPoolIdx != -1) {
                        g_aPlayerPool.Erase(iIndex);
                    }

                    SetClientTeam(iTarget, TEAM_INFECTED);
                    CPrintToChatAll("%t", "PICK_INFECTED_TEAM", iClient, iTarget);

                    g_iOrderPickPlayer ++;
                }
            }
        }
    }

    return 0;
}

/**
 * Timer.
 */
Action Timer_NextStep(Handle hTimer, int iStep)
{
    Flow(iStep);

    return Plugin_Stop;
}

void ShowSelectionCaptainMenu(int iCaptain, int iTime)
{
    Menu hMenu = null;

    int iSize = g_aPlayerPool.Length;

    for (int i = 0; i < iSize; i++)
    {
        int iClient = g_aPlayerPool.Get(i);

        BuildSelectionCaptainMenu(hMenu, iClient, iCaptain);

        DisplayMenu(hMenu, iClient, iTime);
    }
}

/**
 * Resetting voting results.
 */
void ResetVotesForCaptain()
{
    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        g_iVotesForCaptain[iClient][CAPTAIN_SURVIVOR] = 0;
        g_iVotesForCaptain[iClient][CAPTAIN_INFECTED] = 0;
    }
}

/**
 * Returns the index of the player with the most votes.
 *
 * @return            Winner index
 */
int GetMostVotes(int iCaptain)
{
    int iWinner = g_aPlayerPool.Get(0);

    int iSize = g_aPlayerPool.Length;

    for (int i = 1; i < iSize; i++)
    {
        int iClient = g_aPlayerPool.Get(i);

        if (g_iVotesForCaptain[iWinner][iCaptain] < g_iVotesForCaptain[iClient][iCaptain]) {
            iWinner = iClient;
        }
    }

    return iWinner;
}

bool IsSurvivorCapitan(int iClient) {
    return g_iFirstCapitan == iClient;
}

bool IsInfectedCapitan(int iClient) {
    return g_iSecondCapitan == iClient;
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
        if (!IsClientInGame(iClient) || !IsFakeClient(iClient) || GetClientTeam(iClient) != TEAM_SURVIVOR) {
            continue;
        }

        return iClient;
    }

    return -1;
}
