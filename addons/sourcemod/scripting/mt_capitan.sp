#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <mix_team>
#include <colors>


public Plugin myinfo = {
    name        = "MixTeamCapitan",
    author      = "TouchMe",
    description = "Adds capitan mix",
    version     = "build_0003",
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

#define STEP_INIT               0
#define STEP_FIRST_CAPITAN      1
#define STEP_SECOND_CAPITAN     2
#define STEP_PICK_PLAYER        3

#define MIN_PLAYERS             6


int
    g_iFirstCapitan = 0,
    g_iSecondCapitan = 0,
    g_iVoteCount[MAXPLAYERS + 1] = {0, ...},
    g_iOrderPickPlayer = 0
;

int g_iThisMixIndex = -1;

/**
 * Called when the plugin is fully initialized
 * and all known external references are resolved.
 */
public void OnPluginStart() {
    LoadTranslations(TRANSLATIONS);
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
    if (iMixIndex != g_iThisMixIndex || eNewState != MixState_InProgress) {
        return Plugin_Continue;
    }

    Flow(STEP_INIT);

    return Plugin_Stop;
}

/**
  * Builder menu.
  */
int BuildMenu(Menu &hMenu, int iClient, int iStep)
{
    hMenu = CreateMenu(HandleMenu, MenuAction_Select|MenuAction_End);

    char sMenuTitle[64];

    switch(iStep)
    {
        case STEP_FIRST_CAPITAN: FormatEx(sMenuTitle, sizeof(sMenuTitle), "%T", "MENU_TITLE_FIRST_CAPITAN", iClient);

        case STEP_SECOND_CAPITAN: FormatEx(sMenuTitle, sizeof(sMenuTitle), "%T", "MENU_TITLE_SECOND_CAPITAN", iClient);

        case STEP_PICK_PLAYER: FormatEx(sMenuTitle, sizeof(sMenuTitle), "%T", "MENU_TITLE_PICK_TEAMS", iClient);
    }

    hMenu.SetTitle(sMenuTitle);

    char sPlayerInfo[6], sPlayerName[32];
    for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
    {
        if (!IsClientInGame(iPlayer) || !IsClientSpectator(iPlayer) || !IsMixMember(iPlayer) || iClient == iPlayer) {
            continue;
        }

        FormatEx(sPlayerInfo, sizeof(sPlayerInfo), "%d %d", iStep, iPlayer);
        GetClientName(iPlayer, sPlayerName, sizeof(sPlayerName));

        AddMenuItem(hMenu, sPlayerInfo, sPlayerName);
    }

    SetMenuExitButton(hMenu, false);

    return hMenu.ItemCount;
}

/**
 * Menu item selection handler.
 *
 * @param hMenu       Menu ID.
 * @param iAction     Param description.
 * @param iClient     Client index.
 * @param iIndex      Item index.
 */
public int HandleMenu(Menu hMenu, MenuAction iAction, int iClient, int iIndex)
{
    switch(iAction)
    {
        case MenuAction_End: CloseHandle(hMenu);

        case MenuAction_Select:
        {
            char sInfo[6];
            hMenu.GetItem(iIndex, sInfo, sizeof(sInfo));

            char sStep[2], sClient[3];
            BreakString(sInfo[BreakString(sInfo, sStep, sizeof(sStep))], sClient, sizeof(sClient));

            int iStep = StringToInt(sStep);
            int iTarget = StringToInt(sClient);

            if (iStep == STEP_FIRST_CAPITAN || iStep == STEP_SECOND_CAPITAN) {
                g_iVoteCount[iTarget] ++;
            }

            if (iStep == STEP_PICK_PLAYER)
            {
                bool bIsOrderPickFirstCapitan = !(g_iOrderPickPlayer & 2);

                if (bIsOrderPickFirstCapitan && IsFirstCapitan(iClient))
                {
                    SetClientTeam(iTarget, TEAM_SURVIVOR);
                    CPrintToChatAll("%t", "PICK_SURVIVOR_TEAM", iClient, iTarget);

                    g_iOrderPickPlayer ++;
                }

                else if (!bIsOrderPickFirstCapitan && IsSecondCapitan(iClient))
                {
                    SetClientTeam(iTarget, TEAM_INFECTED);
                    CPrintToChatAll("%t", "PICK_INFECTED_TEAM", iClient, iTarget);

                    g_iOrderPickPlayer ++;
                }
            }
        }
    }

    return 0;
}

void Flow(int iStep)
{
    switch(iStep)
    {
        case STEP_INIT:
        {
            g_iOrderPickPlayer = 1;

            ResetVoteCount();
            DisplayMenuAll(STEP_FIRST_CAPITAN, 10);

            CreateTimer(11.0, NextStepTimer, STEP_FIRST_CAPITAN);
        }

        case STEP_FIRST_CAPITAN:
        {
            int iFirstCapitan = GetVoteWinner();

            SetClientTeam((g_iFirstCapitan = iFirstCapitan), TEAM_SURVIVOR);

            CPrintToChatAll("%t", "NEW_FIRST_CAPITAN", iFirstCapitan, g_iVoteCount[iFirstCapitan]);

            ResetVoteCount();

            CreateTimer(11.0, NextStepTimer, STEP_SECOND_CAPITAN);

            DisplayMenuAll(STEP_SECOND_CAPITAN, 10);
        }

        case STEP_SECOND_CAPITAN:
        {
            int iSecondCapitan = GetVoteWinner();

            SetClientTeam((g_iSecondCapitan = iSecondCapitan), TEAM_INFECTED);

            CPrintToChatAll("%t", "NEW_SECOND_CAPITAN", iSecondCapitan, g_iVoteCount[iSecondCapitan]);

            Flow(STEP_PICK_PLAYER);
        }

        case STEP_PICK_PLAYER:
        {
            int iCapitan = (g_iOrderPickPlayer & 2) ? g_iSecondCapitan : g_iFirstCapitan;

            Menu hMenu;

            if (BuildMenu(hMenu, iCapitan, iStep) > 1)
            {
                CreateTimer(1.0, NextStepTimer, iStep);

                DisplayMenu(hMenu, iCapitan, 1);
            }

            else
            {
                if (hMenu != null) {
                    delete hMenu;
                }

                // auto-pick last player
                for (int iClient = 1; iClient <= MaxClients; iClient++)
                {
                    if (!IsClientInGame(iClient) || !IsClientSpectator(iClient) || !IsMixMember(iClient)) {
                        continue;
                    }

                    SetClientTeam(iClient, FindSurvivorBot() != -1 ? TEAM_SURVIVOR : TEAM_INFECTED);
                    break;
                }

                Call_FinishMix();
            }
        }
    }
}

/**
 * Timer.
 */
public Action NextStepTimer(Handle hTimer, int iStep)
{
    if (GetMixState() != MixState_InProgress) {
        return Plugin_Stop;
    }

    Flow(iStep);

    return Plugin_Stop;
}

bool DisplayMenuAll(int iStep, int iTime)
{
    Menu hMenu;

    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsClientInGame(iClient) || !IsClientSpectator(iClient) || !IsMixMember(iClient)) {
            continue;
        }

        if (!BuildMenu(hMenu, iClient, iStep))
        {
            if (hMenu != null) {
                CloseHandle(hMenu);
            }

            return false;
        }

        DisplayMenu(hMenu, iClient, iTime);
    }

    return true;
}

/**
 * Resetting voting results.
 */
void ResetVoteCount()
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
        if (!IsClientInGame(iClient) || !IsClientSpectator(iClient) || !IsMixMember(iClient)) {
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

bool IsFirstCapitan(int iClient) {
    return g_iFirstCapitan == iClient;
}

bool IsSecondCapitan(int iClient) {
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

bool IsClientSpectator(int iClient) {
    return (GetClientTeam(iClient) == TEAM_SPECTATOR);
}
