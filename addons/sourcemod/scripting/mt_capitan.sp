#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <mix_team>
#include <colors>


public Plugin myinfo = {
    name        = "[MixTeam] Capitan",
    author      = "TouchMe",
    description = "Adds capitan mix",
    version     = "build_0005",
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

#define CAPTAIN_SURVIVOR 0
#define CAPTAIN_INFECTED 1

#define MIN_PLAYERS             6


int g_iCaptain[2];
int g_iVotesForCaptain[2][MAXPLAYERS + 1];
int g_iVotedForCaptain[2][MAXPLAYERS + 1];

int g_iRedrawTimer = 0;

int g_iOrderPickPlayer = 0;

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

public Action OnDrawVoteTitle(int iMixIndex, int iClient, char[] szVoteTitle, int iLength)
{
    if (iMixIndex != g_iThisMixIndex) {
        return Plugin_Continue;
    }

    Format(szVoteTitle, iLength, "%T", "VOTE_TITLE", iClient);

    return Plugin_Stop;
}

public Action OnDrawMenuItem(int iMixIndex, int iClient, char[] szMenuItem, int iLength)
{
    if (iMixIndex != g_iThisMixIndex) {
        return Plugin_Continue;
    }

    Format(szMenuItem, iLength, "%T", "MENU_ITEM", iClient);

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
            RedrawSelectionCaptainMenu(CAPTAIN_SURVIVOR, 10);
            ShowSelectionCaptainMenu(CAPTAIN_SURVIVOR);
            
            FlowWithDelay(STEP_SET_SURVIVOR_CAPTAIN, 11.0);
        }

        case STEP_SET_SURVIVOR_CAPTAIN:
        {
            int iCaptain = g_iCaptain[CAPTAIN_SURVIVOR] = GetMostVotes(CAPTAIN_SURVIVOR);

            g_aPlayerPool.Erase(g_aPlayerPool.FindValue(iCaptain));

            SetClientTeam(iCaptain, TEAM_SURVIVOR);

            CPrintToChatAll("%t", "SET_SURVIVOR_CAPTAIN", iCaptain, g_iVotesForCaptain[CAPTAIN_SURVIVOR][iCaptain]);

            Flow(STEP_SELECTION_INFECTED_CAPTAIN);
        }

        case STEP_SELECTION_INFECTED_CAPTAIN:
        {
            RedrawSelectionCaptainMenu(CAPTAIN_INFECTED, 10);
            ShowSelectionCaptainMenu(CAPTAIN_INFECTED);
            
            FlowWithDelay(STEP_SET_INFECTED_CAPTAIN, 11.0);
        }

        case STEP_SET_INFECTED_CAPTAIN:
        {
            int iCaptain = g_iCaptain[CAPTAIN_INFECTED] = GetMostVotes(CAPTAIN_INFECTED);

            g_aPlayerPool.Erase(g_aPlayerPool.FindValue(g_iCaptain[CAPTAIN_INFECTED]));

            SetClientTeam(g_iCaptain[CAPTAIN_INFECTED], TEAM_INFECTED);

            CPrintToChatAll("%t", "SET_INFECTED_CAPTAIN", iCaptain, g_iVotesForCaptain[CAPTAIN_INFECTED][iCaptain]);

            Flow(STEP_PICK_PLAYER);
        }

        case STEP_PICK_PLAYER:
        {
            int iCaptain = (g_iOrderPickPlayer & 2) ? g_iCaptain[CAPTAIN_INFECTED] : g_iCaptain[CAPTAIN_SURVIVOR];

            Menu menu = null;

            int iSize = g_aPlayerPool.Length;

            if (iSize > 1)
            {
                BuildPickPlayersMenu(menu, iCaptain);
                DisplayMenu(menu, iCaptain, 1);
                FlowWithDelay(STEP_PICK_PLAYER, 1.0);
            }

            else
            {
                int iPlayer = g_aPlayerPool.Get(0);
                int iTeamSize = FindConVar("survivor_limit").IntValue;

                int iInfectedCount = GetPlayerCountByTeam(TEAM_INFECTED);
                int iSurvivorCount = GetPlayerCountByTeam(TEAM_SURVIVOR);

                if (iSurvivorCount < iInfectedCount && iSurvivorCount < iTeamSize)
                {
                    SetClientTeam(iPlayer, TEAM_SURVIVOR);
                }
                else if (iInfectedCount < iTeamSize)
                {
                    SetClientTeam(iPlayer, TEAM_INFECTED);
                }
                else if (iSurvivorCount < iTeamSize)
                {
                    SetClientTeam(iPlayer, TEAM_SURVIVOR);
                }
                else
                {
                    FlowWithDelay(STEP_PICK_PLAYER, 1.0);
                    return;
                }

                Call_FinishMix();
            }
        }
    }
}

void FlowWithDelay(int iStep, float fDelay)
{
    CreateTimer(fDelay, Timer_NextStep, iStep, .flags = TIMER_FLAG_NO_MAPCHANGE);
}

void RedrawSelectionCaptainMenu(int iCaptain, int iTimes)
{
    g_iRedrawTimer = iTimes;
    CreateTimer(1.0, Timer_ShowSelectionCaptainMenu, iCaptain, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

Action Timer_ShowSelectionCaptainMenu(Handle hTimer, int iCaptain)
{
    if (GetMixState() != MixState_InProgress) {
        return Plugin_Stop;
    }

    if (--g_iRedrawTimer <= 0) {
        return Plugin_Stop;
    }

    ShowSelectionCaptainMenu(iCaptain);

    return Plugin_Continue;
}

/**
  * Builder menu.
  */
void BuildSelectionCaptainMenu(Menu &menu, int iClient, int iCaptain)
{
    menu = CreateMenu(HandleSelectionCaptainMenu, MenuAction_Select|MenuAction_End);

    switch (iCaptain)
    {
        case CAPTAIN_SURVIVOR: menu.SetTitle("%T", "MENU_SURVIVOR_CAPTAIN_TITLE", iClient);
        case CAPTAIN_INFECTED: menu.SetTitle("%T", "MENU_INFECTED_CAPTAIN_TITLE", iClient);
    }

    int iSize = g_aPlayerPool.Length;
    char szPlayerInfo[6], szPlayerName[MAX_NAME_LENGTH];

    for (int i = 0; i < iSize; i++)
    {
        int iPlayer = g_aPlayerPool.Get(i);

        FormatEx(szPlayerInfo, sizeof(szPlayerInfo), "%d %d", iCaptain, iPlayer);
        FormatEx(szPlayerName, sizeof(szPlayerName), "[%d] %N",  g_iVotesForCaptain[iCaptain][iPlayer], iPlayer);

        AddMenuItem(menu, szPlayerInfo, szPlayerName, g_iVotedForCaptain[iCaptain][iClient] != 0 ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
    }

    SetMenuExitButton(menu, false);
}

/**
 * Menu item selection handler.
 *
 * @param menu       Menu ID.
 * @param action     Param description.
 * @param iParam1    Client index.
 * @param iParam2    Item index.
 */
public int HandleSelectionCaptainMenu(Menu menu, MenuAction action, int iParam1, int iParam2)
{
    switch (action)
    {
        case MenuAction_End: delete menu;

        case MenuAction_Select:
        {
            char szPlayerInfo[6];
            menu.GetItem(iParam2, szPlayerInfo, sizeof(szPlayerInfo));

            char szCaptain[3], szClient[3];
            BreakString(szPlayerInfo[BreakString(szPlayerInfo, szCaptain, sizeof(szCaptain))], szClient, sizeof(szClient));

            int iTarget = StringToInt(szClient);
            int iCaptain = StringToInt(szCaptain);

            g_iVotesForCaptain[iCaptain][iTarget] ++;
            g_iVotedForCaptain[iCaptain][iParam1] = iTarget;
        }
    }

    return 0;
}

/**
  * Builder menu.
  */
void BuildPickPlayersMenu(Menu &menu, int iClient)
{
    menu = CreateMenu(HandlePickPlayersMenu, MenuAction_Select|MenuAction_End);

    menu.SetTitle("%T", "MENU_PICK_PLAYERS_TITLE", iClient);

    int iSize = g_aPlayerPool.Length;
    char szPlayerInfo[3], szPlayerName[MAX_NAME_LENGTH];

    for (int i = 0; i < iSize; i++)
    {
        int iPlayer = g_aPlayerPool.Get(i);

        FormatEx(szPlayerInfo, sizeof(szPlayerInfo), "%d", iPlayer);
        GetClientName(iPlayer, szPlayerName, sizeof(szPlayerName));

        AddMenuItem(menu, szPlayerInfo, szPlayerName);
    }

    SetMenuExitButton(menu, false);
}

/**
 * Menu item selection handler.
 *
 * @param menu       Menu ID.
 * @param action     Param description.
 * @param iClient    Client index.
 * @param iIndex     Item index.
 */
public int HandlePickPlayersMenu(Menu menu, MenuAction action, int iClient, int iIndex)
{
    switch (action)
    {
        case MenuAction_End: delete menu;

        case MenuAction_Select:
        {
            char szPlayerInfo[4];
            menu.GetItem(iIndex, szPlayerInfo, sizeof(szPlayerInfo));

            int iTarget = StringToInt(szPlayerInfo);
            int iPlayerPoolIdx = g_aPlayerPool.FindValue(iTarget);

            switch ((g_iOrderPickPlayer & 2) ? CAPTAIN_INFECTED : CAPTAIN_SURVIVOR)
            {
                case CAPTAIN_SURVIVOR:
                {
                    if (!IsSurvivorCapitan(iClient)) {
                        return 0;
                    }

                    if (iPlayerPoolIdx != -1) {
                        g_aPlayerPool.Erase(iPlayerPoolIdx);
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
                        g_aPlayerPool.Erase(iPlayerPoolIdx);
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

void ShowSelectionCaptainMenu(int iCaptain)
{
    Menu menu = null;

    int iSize = g_aPlayerPool.Length;

    for (int i = 0; i < iSize; i++)
    {
        int iClient = g_aPlayerPool.Get(i);

        BuildSelectionCaptainMenu(menu, iClient, iCaptain);

        DisplayMenu(menu, iClient, 1);
    }
}

/**
 * Resetting voting results.
 */
void ResetVotesForCaptain()
{
    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        g_iVotesForCaptain[CAPTAIN_SURVIVOR][iClient] = 0;
        g_iVotesForCaptain[CAPTAIN_INFECTED][iClient] = 0;
        g_iVotedForCaptain[CAPTAIN_SURVIVOR][iClient] = 0;
        g_iVotedForCaptain[CAPTAIN_INFECTED][iClient] = 0;
    }
}

/**
 * Returns the index of the player with the most votes.
 *
 * @return            Winner index
 */
int GetMostVotes(int iCaptain)
{
    int iMaxVotes = -1;

    ArrayList aWinnerPool = new ArrayList();

    for (int i = 0; i < g_aPlayerPool.Length; i++)
    {
        int iClient = g_aPlayerPool.Get(i);
        int iVotes = g_iVotesForCaptain[iCaptain][iClient];

        if (iVotes > iMaxVotes)
        {
            iMaxVotes = iVotes;
            aWinnerPool.Clear();
            aWinnerPool.Push(iClient);
        }
        else if (iVotes == iMaxVotes)
        {
            aWinnerPool.Push(iClient);
        }
    }

    return aWinnerPool.Length == 1 ?
        aWinnerPool.Get(0) : aWinnerPool.Get(GetRandomInt(0, aWinnerPool.Length - 1));
}

bool IsSurvivorCapitan(int iClient) {
    return g_iCaptain[CAPTAIN_SURVIVOR] == iClient;
}

bool IsInfectedCapitan(int iClient) {
    return g_iCaptain[CAPTAIN_INFECTED] == iClient;
}

int GetPlayerCountByTeam(int iTeam)
{
    int iCount = 0;

    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsClientInGame(iClient) || IsFakeClient(iClient) || GetClientTeam(iClient) != iTeam) {
            continue;
        }

        iCount++;
    }

    return iCount;
}
